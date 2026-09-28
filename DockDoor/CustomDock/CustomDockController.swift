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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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

    init() {
        ui.metrics = metrics
        let hostingView = CustomDockHostingView(rootView: CustomDockView(store: store, ui: ui))
        hostingView.autoresizingMask = [.width, .height]
        hostingView.sizingOptions = []
        hostingView.onRightMouseDown = { [weak self] event in self?.showMenu(for: event) }
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
            .sink { [weak self] _, _ in self?.relayout() }
            .store(in: &cancellables)

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
        let layout = CustomDockLayoutEngine.layout(
            appIDs: store.appTiles.map(\.id),
            otherIDs: store.otherTiles.map(\.id),
            size: size,
            metrics: metrics,
            mouseX: mouseX
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
            let keep = atEdge || overDock || isMenuOpen || CustomDockPreviews.isMouseInPreview
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

        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
        if ui.isInteracting != inside { ui.isInteracting = inside }
        isInside = inside

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
        guard let id else { return }
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
        let menu = menuBuilder.menu(for: tile)
        isMenuOpen = true
        NSMenu.popUpContextMenu(menu, with: event, for: hostingView)
        isMenuOpen = false
        lastKeepVisible = Date()
    }
}
