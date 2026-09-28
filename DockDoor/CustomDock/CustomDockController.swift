import Cocoa
import Combine
import Defaults
import SwiftUI

final class CustomDockPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class CustomDockHostingView<Content: View>: NSHostingView<Content> {
    var onRightMouseDown: ((NSEvent) -> Void)?
    var onMouseDown: (() -> Void)?
    var onMouseDragged: (() -> Void)?
    var onMouseUp: (() -> Void)?
    var onScroll: ((NSEvent) -> Bool)?

    override func scrollWheel(with event: NSEvent) {
        if onScroll?(event) != true { super.scrollWheel(with: event) }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if let onMouseDown { onMouseDown() } else { super.mouseDown(with: event) }
    }

    override func mouseDragged(with event: NSEvent) {
        if let onMouseDragged { onMouseDragged() } else { super.mouseDragged(with: event) }
    }

    override func mouseUp(with event: NSEvent) {
        if let onMouseUp { onMouseUp() } else { super.mouseUp(with: event) }
    }

    override func rightMouseDown(with event: NSEvent) {
        if let onRightMouseDown {
            onRightMouseDown(event)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

/// Owns the DockerDoor dock window: lays out the icons (including magnification),
/// lets clicks outside the dock pass through, handles auto-hide, previews and menus.
final class CustomDockController {
    let store = CustomDockStore()
    let ui = CustomDockUIState()

    private let panel = CustomDockPanel()
    private var hostingView: CustomDockHostingView<CustomDockView>?
    private lazy var menuBuilder = CustomDockMenuBuilder(store: store)
    private var mouseTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var defaultsTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?

    private var metrics = CustomDockController.currentMetrics()
    private var mouseX: CGFloat?
    private var isInside = false
    private var isRevealed = true
    private var lastKeepVisible = Date()
    private var isMenuOpen = false

    let stackController = StackPanelController()
    let popoverController = DockPopoverController()
    private var rotateTimer: Timer?
    private var rotationTask: Task<Void, Never>?
    private var scrollAccumulator: CGFloat = 0
    private var lastPageFlip = Date.distantPast
    private var volumeClearWork: DispatchWorkItem?
    private var drag: DockDrag?
    private var buttonReleasedAt: Date?
    private var ghost: DockDragGhost?
    static let gapID = "drag-gap"

    init() {
        ui.metrics = metrics
        let hostingView = CustomDockHostingView(rootView: CustomDockView(store: store, ui: ui))
        hostingView.autoresizingMask = [.width, .height]
        hostingView.sizingOptions = []
        hostingView.onRightMouseDown = { [weak self] event in self?.showMenu(for: event) }
        hostingView.onMouseDown = { [weak self] in self?.mouseDown() }
        hostingView.onMouseDragged = { [weak self] in self?.mouseDragged() }
        hostingView.onMouseUp = { [weak self] in self?.mouseUp() }
        hostingView.onScroll = { [weak self] event in self?.handleScroll(event) ?? false }
        self.hostingView = hostingView
        panel.contentView = hostingView
        panel.ignoresMouseEvents = true
        applyAppearance()

        isRevealed = !Defaults[.customDockAutoHide]
        ui.isHidden = !isRevealed

        updatePanelFrame()
        relayout()
        panel.orderFrontRegardless()

        store.$appTiles.combineLatest(store.$otherTiles)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.relayout()
                self?.widgetsChanged()
            }
            .store(in: &cancellables)

        MediaRemoteService.shared.$isPlaying
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] playing in
                guard playing, Defaults[.customDockWidgetSmartSwitch] else { return }
                self?.showNowPlayingInStacks()
            }
            .store(in: &cancellables)

        let rotationKeys: [Defaults._AnyKey] = [.customDockWidgetAutoRotate, .customDockWidgetRotateSeconds]
        rotationTask = Task { [weak self] in
            for await _ in Defaults.updates(rotationKeys, initial: true) {
                await MainActor.run { self?.configureRotation() }
            }
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updatePanelFrame()
            self?.relayout()
        }

        let keys: [Defaults._AnyKey] = [
            .customDockIconSize, .customDockMagnification, .customDockMagnifiedSize,
            .customDockLayoutMode, .customDockAutoHide, .customDockAppearance,
        ]
        defaultsTask = Task { [weak self] in
            for await _ in Defaults.updates(keys, initial: false) {
                await MainActor.run { self?.settingsChanged() }
            }
        }

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }

    func tearDown() {
        mouseTimer?.invalidate()
        mouseTimer = nil
        defaultsTask?.cancel()
        cancellables.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        CustomDockPreviews.hide()
        stackController.close()
        popoverController.close()
        rotateTimer?.invalidate()
        rotateTimer = nil
        rotationTask?.cancel()
        DockWidgetHub.shared.update(activeKinds: [])
        ghost?.close()
        ghost = nil
        drag = nil
        panel.orderOut(nil)
        panel.contentView = nil
        hostingView = nil
    }

    deinit {
        mouseTimer?.invalidate()
        defaultsTask?.cancel()
    }

    var dockScreen: NSScreen? {
        NSScreen.screens.first ?? NSScreen.main
    }

    private static func currentMetrics() -> CustomDockMetrics {
        CustomDockMetrics(
            iconSize: CGFloat(Defaults[.customDockIconSize]),
            magnifiedSize: CGFloat(Defaults[.customDockMagnifiedSize]),
            magnification: Defaults[.customDockMagnification],
            mode: Defaults[.customDockLayoutMode]
        )
    }

    private func settingsChanged() {
        metrics = Self.currentMetrics()
        ui.metrics = metrics
        applyAppearance()
        if !Defaults[.customDockAutoHide] {
            isRevealed = true
            ui.isHidden = false
        }
        updatePanelFrame()
        relayout()
    }

    private func applyAppearance() {
        switch Defaults[.customDockAppearance] {
        case .system: panel.appearance = nil
        case .light: panel.appearance = NSAppearance(named: .aqua)
        case .dark: panel.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func updatePanelFrame() {
        guard let screen = dockScreen else { return }
        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.minY,
            width: screen.frame.width,
            height: metrics.panelHeight
        )
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func relayout() {
        let size = panel.frame.size
        guard size.width > 0 else { return }
        var appIDs = store.appTiles.map(\.id)
        var otherIDs = store.otherTiles.map(\.id)
        var magnifyX = mouseX
        var widthFactors: [String: CGFloat] = [:]
        for tile in store.otherTiles where tile.kind == .widget && tile.widthFactor != 1 {
            widthFactors[tile.id] = tile.widthFactor
        }
        if let drag, drag.isActive {
            magnifyX = nil
            widthFactors[Self.gapID] = drag.tile.widthFactor
            appIDs.removeAll { $0 == drag.tile.id }
            otherIDs.removeAll { $0 == drag.tile.id }
            if !drag.isRemoving {
                if drag.isAppSection {
                    appIDs.insert(Self.gapID, at: min(drag.insertionIndex, appIDs.count))
                } else {
                    let movable = store.otherTiles.filter { $0.kind != .trash && $0.id != drag.tile.id }.count
                    otherIDs.insert(Self.gapID, at: min(drag.insertionIndex, movable))
                }
            }
        }
        let layout = CustomDockLayoutEngine.layout(
            appIDs: appIDs,
            otherIDs: otherIDs,
            size: size,
            metrics: metrics,
            mouseX: magnifyX,
            widthFactors: widthFactors
        )
        if layout != ui.layout { ui.layout = layout }
    }

    // MARK: - Coordinates

    private func viewPoint(fromScreen point: NSPoint) -> CGPoint {
        let frame = panel.frame
        return CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
    }

    private func screenRect(fromView rect: CGRect) -> CGRect {
        let frame = panel.frame
        return CGRect(x: frame.minX + rect.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: - Pointer tracking

    private func tick() {
        guard let screen = dockScreen else { return }
        let mouse = NSEvent.mouseLocation
        let point = viewPoint(fromScreen: mouse)
        let dragging = NSEvent.pressedMouseButtons & 1 == 1
        let layout = ui.layout

        // Auto-hide
        if Defaults[.customDockAutoHide] {
            let atEdge = mouse.y <= screen.frame.minY + 1.5 && mouse.x >= screen.frame.minX && mouse.x <= screen.frame.maxX
            let overDock = isRevealed && layout.contentRect.insetBy(dx: -4, dy: -8).contains(point)
            let keep = atEdge || overDock || isMenuOpen || CustomDockPreviews.isMouseInPreview || drag != nil || stackController.isOpen || popoverController.isOpen
            if keep { lastKeepVisible = Date() }
            if !isRevealed, atEdge {
                isRevealed = true
                ui.isHidden = false
            } else if isRevealed, !keep, Date().timeIntervalSince(lastKeepVisible) > 0.45 {
                isRevealed = false
                ui.isHidden = true
            }
        }

        var inside = false
        if isRevealed {
            if layout.baseBarRect.insetBy(dx: -2, dy: -2).contains(point) || layout.barRect.contains(point) {
                inside = true
            } else if isInside || dragging, layout.contentRect.insetBy(dx: -2, dy: -2).contains(point) {
                inside = true
            }
        }
        if isMenuOpen { inside = isInside }
        if drag != nil {
            inside = true
            // Safety net: if the mouse-up never reached us, end the drag anyway.
            if dragging {
                buttonReleasedAt = nil
            } else if let released = buttonReleasedAt {
                if Date().timeIntervalSince(released) > 0.3 {
                    buttonReleasedAt = nil
                    DockerDoorLog.write("Ziehen ohne Maus-Loslassen beendet (Sicherheitsnetz)")
                    mouseUp()
                    return
                }
            } else {
                buttonReleasedAt = Date()
            }
        } else {
            buttonReleasedAt = nil
        }

        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
        if ui.isInteracting != inside { ui.isInteracting = inside }
        isInside = inside

        if drag?.isActive == true {
            updateDrag(at: point)
            return
        }

        let newMouseX: CGFloat? = inside && !isMenuOpen ? point.x : (isMenuOpen ? mouseX : nil)
        if newMouseX != mouseX {
            mouseX = newMouseX
            relayout()
        }

        let hovered = inside ? ui.layout.tileID(at: point, spacing: metrics.spacing) : nil
        if !isMenuOpen, hovered != ui.hoveredID {
            ui.hoveredID = hovered
            hoverChanged(to: hovered, screen: screen)
        }
        if !inside, !dragging, ui.dropTargetID != nil {
            ui.dropTargetID = nil
        }
    }

    private func hoverChanged(to id: String?, screen: NSScreen) {
        guard let id, !stackController.isOpen, !popoverController.isOpen else { return }
        guard let tile = store.allTiles.first(where: { $0.id == id }),
              let frame = ui.layout.frames[id]
        else { return }

        if tile.kind == .app, tile.isRunning {
            let anchor = screenRect(fromView: frame)
            CustomDockPreviews.show(for: tile, anchor: anchor, screen: screen) { [weak self] in
                self?.ui.hoveredID == id || CustomDockPreviews.isMouseInPreview
            }
        } else if !CustomDockPreviews.isMouseInPreview {
            CustomDockPreviews.hide()
        }
    }

    // MARK: - Context menu

    private func showMenu(for event: NSEvent) {
        guard let hostingView else { return }
        let local = hostingView.convert(event.locationInWindow, from: nil)
        let point = CGPoint(x: local.x, y: hostingView.isFlipped ? local.y : hostingView.bounds.height - local.y)
        let tileID = ui.layout.tileID(at: point, spacing: metrics.spacing)
        let tile = tileID.flatMap { id in store.allTiles.first { $0.id == id } }

        CustomDockPreviews.hide()
        stackController.close()
        popoverController.close()
        menuBuilder.onOpenStack = { [weak self] tile in
            if tile.kind == .widget {
                self?.togglePopover(for: tile)
            } else {
                self?.toggleStack(for: tile)
            }
        }
        let menu = menuBuilder.menu(for: tile)
        isMenuOpen = true
        NSMenu.popUpContextMenu(menu, with: event, for: hostingView)
        isMenuOpen = false
        lastKeepVisible = Date()
    }

    // MARK: - Clicks

    private func handleTap(_ tile: DockTile) {
        switch tile.kind {
        case .folder, .group:
            toggleStack(for: tile)
        case .widget:
            togglePopover(for: tile)
        default:
            stackController.close()
            popoverController.close()
            CustomDockPreviews.hide()
            store.open(tile)
        }
    }

    // MARK: - Stacks

    func toggleStack(for tile: DockTile) {
        if stackController.openTileID == tile.id {
            stackController.close()
            return
        }
        guard let screen = dockScreen, let frame = ui.layout.frames[tile.id] else { return }
        popoverController.close()
        let source: StackModel.Source
        if tile.kind == .group {
            source = .group(id: tile.id, members: tile.members)
        } else if let url = tile.url {
            source = .folder(url)
        } else {
            return
        }
        CustomDockPreviews.hide()
        let model = StackModel(
            tileID: tile.id,
            source: source,
            title: tile.name,
            mode: tile.stackMode ?? (tile.kind == .group ? .grid : Defaults[.customDockStackMode]),
            sort: tile.stackSort ?? Defaults[.customDockStackSort]
        )
        let tileID = tile.id
        model.onModeChange = { [weak self] mode in
            self?.store.setStackMode(mode, for: tileID)
        }
        model.onRemoveMember = { [weak self] path in
            self?.stackController.close()
            self?.store.remove(memberPath: path, fromGroup: tileID)
        }
        stackController.show(model, anchor: screenRect(fromView: frame), screen: screen, ignoringClicksIn: panel)
    }

    // MARK: - Widgets

    private func widgetsChanged() {
        DockWidgetHub.shared.update(activeKinds: Set(store.otherTiles.flatMap(\.widgets)))
    }

    private func currentWidget(of tile: DockTile) -> DockWidgetKind? {
        guard !tile.widgets.isEmpty else { return nil }
        return tile.widgets[(ui.widgetPages[tile.id] ?? 0) % tile.widgets.count]
    }

    func togglePopover(for tile: DockTile) {
        guard let kind = currentWidget(of: tile) else { return }
        let key = "\(tile.id)|\(kind.rawValue)"
        if popoverController.openKey == key {
            popoverController.close()
            return
        }
        guard let screen = dockScreen, let frame = ui.layout.frames[tile.id] else { return }
        stackController.close()
        CustomDockPreviews.hide()
        switch kind {
        case .weather:
            let weather = DockWeatherModel.shared
            if weather.snapshot.map({ Date().timeIntervalSince($0.fetched) > 600 }) ?? true { weather.refresh() }
        case .calendar:
            DockCalendarModel.shared.load()
        case .battery:
            DockBatteryModel.shared.read()
        case .clock, .nowPlaying:
            break
        }
        let popover = popoverController
        popoverController.show(
            DockWidgetPopovers.view(for: kind, close: { [weak popover] in popover?.close() }),
            size: DockWidgetPopovers.size(for: kind),
            key: key,
            anchor: screenRect(fromView: frame),
            screen: screen,
            ignoringClicksIn: panel
        )
    }

    private func flipPage(of tile: DockTile, by step: Int) {
        let count = tile.widgets.count
        guard count > 1 else { return }
        let current = (ui.widgetPages[tile.id] ?? 0) % count
        ui.widgetPages[tile.id] = (current + step + count) % count
        if popoverController.openKey?.hasPrefix(tile.id + "|") == true {
            popoverController.close()
        }
    }

    private func showNowPlayingInStacks() {
        for tile in store.otherTiles where tile.isWidgetStack {
            if let index = tile.widgets.firstIndex(of: .nowPlaying) {
                ui.widgetPages[tile.id] = index
            }
        }
    }

    private func configureRotation() {
        rotateTimer?.invalidate()
        rotateTimer = nil
        guard Defaults[.customDockWidgetAutoRotate] else { return }
        let interval = max(4, Defaults[.customDockWidgetRotateSeconds])
        rotateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.rotateStacks()
        }
    }

    private func rotateStacks() {
        guard drag == nil else { return }
        let nowPlayingActive = MediaRemoteService.shared.isPlaying && Defaults[.customDockWidgetSmartSwitch]
        for tile in store.otherTiles where tile.isWidgetStack && tile.id != ui.hoveredID {
            if popoverController.openKey?.hasPrefix(tile.id + "|") == true { continue }
            // While music plays the smart stack stays on Now Playing.
            if nowPlayingActive, currentWidget(of: tile) == .nowPlaying { continue }
            flipPage(of: tile, by: 1)
        }
    }

    private func handleScroll(_ event: NSEvent) -> Bool {
        let point = viewPoint(fromScreen: NSEvent.mouseLocation)
        guard let id = ui.layout.tileID(at: point, spacing: metrics.spacing),
              let tile = store.allTiles.first(where: { $0.id == id }),
              tile.kind == .widget, let current = currentWidget(of: tile)
        else { return false }
        guard event.momentumPhase.isEmpty else { return true }

        var delta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : -event.scrollingDeltaX
        if event.isDirectionInvertedFromDevice { delta = -delta }

        let wantsVolume = current == .nowPlaying && Defaults[.customDockVolumeScroll]
            && (!tile.isWidgetStack || event.modifierFlags.contains(.option))
        if wantsVolume {
            let step = Float(delta) * (event.hasPreciseScrollingDeltas ? 0.004 : 0.03)
            let value = max(0, min(1, AudioDeviceManager.getSystemVolume() + step))
            AudioDeviceManager.setSystemVolume(value)
            showVolume(value, on: tile.id)
            return true
        }

        guard tile.isWidgetStack else { return true }
        if event.phase == .began { scrollAccumulator = 0 }
        scrollAccumulator += delta
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 28 : 0.5
        if abs(scrollAccumulator) >= threshold, Date().timeIntervalSince(lastPageFlip) > 0.3 {
            flipPage(of: tile, by: scrollAccumulator > 0 ? -1 : 1)
            scrollAccumulator = 0
            lastPageFlip = Date()
        }
        if event.phase == .ended || event.phase == .cancelled { scrollAccumulator = 0 }
        return true
    }

    private func showVolume(_ value: Float, on id: String) {
        ui.volumeOverlay = (id: id, value: value)
        volumeClearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.ui.volumeOverlay = nil }
        volumeClearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }

    // MARK: - Dragging icons

    private func mouseDown() {
        let point = viewPoint(fromScreen: NSEvent.mouseLocation)
        guard let id = ui.layout.tileID(at: point, spacing: metrics.spacing),
              let tile = store.allTiles.first(where: { $0.id == id })
        else {
            drag = nil
            return
        }
        let frame = ui.layout.frames[id] ?? CGRect(origin: point, size: .zero)
        drag = DockDrag(
            tile: tile,
            startPoint: point,
            grabOffset: CGSize(width: point.x - frame.midX, height: point.y - frame.midY),
            grabbedSize: max(1, frame.height)
        )
    }

    private func mouseDragged() {
        guard var current = drag else { return }
        let point = viewPoint(fromScreen: NSEvent.mouseLocation)
        if !current.isActive {
            guard current.tile.isMovable,
                  hypot(point.x - current.startPoint.x, point.y - current.startPoint.y) > 5
            else { return }
            current.isActive = true
            let section = sectionTiles(for: current, includingDragged: true)
            current.insertionIndex = section.firstIndex { $0.id == current.tile.id } ?? section.count
            drag = current
            CustomDockPreviews.hide()
            stackController.close()
            popoverController.close()
            ui.hoveredID = nil
            mouseX = nil
            let ghost = DockDragGhost(icon: store.icon(for: current.tile), size: metrics.iconSize * 1.1)
            self.ghost = ghost
            relayout()
        }
        updateDrag(at: point)
    }

    private func mouseUp() {
        guard let finished = drag else {
            stackController.close()
            popoverController.close()
            return
        }
        drag = nil
        guard finished.isActive else {
            handleTap(finished.tile)
            return
        }
        finishDrag(finished)
    }

    /// Tiles of the dragged tile's section in dock order (without the trash).
    private func sectionTiles(for drag: DockDrag, includingDragged: Bool) -> [DockTile] {
        let tiles = drag.isAppSection ? store.appTiles : store.otherTiles.filter { $0.kind != .trash }
        return includingDragged ? tiles : tiles.filter { $0.id != drag.tile.id }
    }

    private func canMerge(_ dragged: DockTile, onto target: DockTile) -> Bool {
        if dragged.kind == .widget {
            return target.kind == .widget && target.id != dragged.id
        }
        guard dragged.id != target.id, dragged.kind == .app, dragged.url != nil, !dragged.isFinder else { return false }
        if target.kind == .group { return true }
        return target.kind == .app && target.url != nil && !target.isFinder
    }

    private func updateDrag(at point: CGPoint) {
        guard var current = drag, current.isActive else { return }
        let layout = ui.layout
        var needsLayout = false

        if let ghost {
            let scale = ghost.size / current.grabbedSize
            let screenPoint = NSPoint(
                x: panel.frame.minX + point.x - current.grabOffset.width * scale,
                y: panel.frame.maxY - (point.y - current.grabOffset.height * scale)
            )
            ghost.move(centerAt: screenPoint)
        }

        let removing = current.tile.isPinned && point.y < layout.barRect.minY - max(44, metrics.iconSize)
        if removing != current.isRemoving {
            current.isRemoving = removing
            ghost?.model.removing = removing
            needsLayout = true
        }

        var candidate: String?
        if !removing {
            let section = sectionTiles(for: current, includingDragged: false)
            var index = current.insertionIndex
            let framed = section.compactMap { tile in layout.frames[tile.id].map { (tile, $0) } }
            if let first = framed.first, point.x < first.1.minX {
                index = 0
            } else if let last = framed.last, point.x >= last.1.maxX {
                index = framed.count
            }
            for (offset, entry) in framed.enumerated() {
                let (tile, frame) = entry
                guard point.x >= frame.minX, point.x < frame.maxX else { continue }
                let relative = (point.x - frame.minX) / max(1, frame.width)
                let verticallyInside = point.y >= layout.barRect.minY - metrics.iconSize * 0.5
                if canMerge(current.tile, onto: tile), verticallyInside {
                    if relative < 0.25 {
                        index = offset
                    } else if relative > 0.75 {
                        index = offset + 1
                    } else {
                        candidate = tile.id
                    }
                } else {
                    index = relative < 0.5 ? offset : offset + 1
                }
            }
            if current.isAppSection, section.first?.isFinder == true {
                index = max(1, index)
            }
            if index != current.insertionIndex {
                current.insertionIndex = index
                needsLayout = true
            }
        }

        if candidate != current.candidateID {
            current.candidateID = candidate
            current.candidateSince = Date()
            current.mergeTargetID = nil
        } else if candidate != nil, current.mergeTargetID == nil, Date().timeIntervalSince(current.candidateSince) >= 0.55 {
            current.mergeTargetID = candidate
        }
        if ui.dropTargetID != current.mergeTargetID { ui.dropTargetID = current.mergeTargetID }

        drag = current
        if needsLayout { relayout() }
    }

    private func finishDrag(_ finished: DockDrag) {
        ui.dropTargetID = nil
        let ghost = ghost
        self.ghost = nil

        if finished.isRemoving {
            ghost?.vanish()
            store.unpin(finished.tile)
        } else if let targetID = finished.mergeTargetID,
                  let target = store.allTiles.first(where: { $0.id == targetID })
        {
            ghost?.close()
            if finished.tile.kind == .widget {
                store.mergeWidgets(finished.tile, into: targetID)
            } else if target.kind == .group {
                store.add(finished.tile, toGroup: targetID)
            } else {
                store.createGroup(from: finished.tile, with: target)
            }
        } else {
            ghost?.close()
            let section = sectionTiles(for: finished, includingDragged: false)
            let pinnedCount = section.filter(\.isPinned).count
            if finished.tile.isPinned || finished.insertionIndex <= pinnedCount {
                store.move(finished.tile, toIndex: min(finished.insertionIndex, pinnedCount))
            }
        }
        store.rebuild()
        relayout()
    }
}

private struct DockDrag {
    let tile: DockTile
    let startPoint: CGPoint
    let grabOffset: CGSize
    let grabbedSize: CGFloat
    var isActive = false
    var insertionIndex = 0
    var isRemoving = false
    var candidateID: String?
    var candidateSince = Date()
    var mergeTargetID: String?

    var isAppSection: Bool { tile.kind == .app || tile.kind == .group }
}

// MARK: - Drag image

final class DockDragGhostModel: ObservableObject {
    @Published var removing = false
}

private struct DockDragGhostView: View {
    let icon: NSImage
    let size: CGFloat
    @ObservedObject var model: DockDragGhostModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .opacity(model.removing ? 0.6 : 1)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            if model.removing {
                Image(systemName: "minus.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
                    .font(.system(size: max(14, size * 0.3), weight: .bold))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: size + 16, height: size + 16)
        .animation(.easeOut(duration: 0.15), value: model.removing)
    }
}

final class DockDragGhost {
    let size: CGFloat
    let model = DockDragGhostModel()
    private let panel: NSPanel

    init(icon: NSImage, size: CGFloat) {
        self.size = size
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size + 16, height: size + 16),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: DockDragGhostView(icon: icon, size: size, model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    func move(centerAt point: NSPoint) {
        let frame = panel.frame
        panel.setFrameOrigin(NSPoint(x: point.x - frame.width / 2, y: point.y - frame.height / 2))
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func close() {
        panel.orderOut(nil)
    }

    /// Small "poof": grows a little and fades out.
    func vanish() {
        let panel = panel
        let frame = panel.frame
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
            panel.animator().setFrame(frame.insetBy(dx: -frame.width * 0.25, dy: -frame.height * 0.25), display: true)
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}
