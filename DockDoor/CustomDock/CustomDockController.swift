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

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the DockerDoor dock window: sizes it to the screen, keeps it in place
/// and lets clicks outside the visible bar pass through to the windows below.
final class CustomDockController {
    let store = CustomDockStore()
    let ui = CustomDockUIState()

    private let panel = CustomDockPanel()
    private var mouseTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var defaultsTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?

    init() {
        let hostingView = FirstMouseHostingView(rootView: CustomDockView(store: store, ui: ui))
        hostingView.autoresizingMask = [.width, .height]
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.ignoresMouseEvents = true

        layout()
        panel.orderFrontRegardless()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.layout()
        }

        let keys: [Defaults._AnyKey] = [.customDockIconSize]
        defaultsTask = Task { [weak self] in
            for await _ in Defaults.updates(keys, initial: false) {
                await MainActor.run { self?.layout() }
            }
        }

        mouseTimer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateMousePassThrough()
        }
        if let mouseTimer { RunLoop.main.add(mouseTimer, forMode: .common) }
    }

    func tearDown() {
        mouseTimer?.invalidate()
        mouseTimer = nil
        defaultsTask?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panel.orderOut(nil)
        panel.contentView = nil
    }

    deinit {
        mouseTimer?.invalidate()
        defaultsTask?.cancel()
    }

    var dockScreen: NSScreen? {
        NSScreen.screens.first ?? NSScreen.main
    }

    func layout() {
        guard let screen = dockScreen else { return }
        let metrics = CustomDockMetrics(iconSize: CGFloat(Defaults[.customDockIconSize]))
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

    /// The visible dock bar in screen coordinates.
    private var barScreenRect: CGRect {
        let bar = ui.barFrame
        guard bar.width > 0 else { return .zero }
        let frame = panel.frame
        return CGRect(
            x: frame.minX + bar.minX,
            y: frame.minY + (frame.height - bar.maxY),
            width: bar.width,
            height: bar.height
        )
    }

    private func updateMousePassThrough() {
        let mouse = NSEvent.mouseLocation
        let insideBar = barScreenRect.insetBy(dx: -2, dy: -2).contains(mouse)
        let dragging = NSEvent.pressedMouseButtons & 1 == 1

        if panel.ignoresMouseEvents == insideBar {
            panel.ignoresMouseEvents = !insideBar
        }
        if !insideBar, !dragging {
            if ui.hoveredID != nil { ui.hoveredID = nil }
            if ui.dropTargetID != nil { ui.dropTargetID = nil }
        }
    }
}
