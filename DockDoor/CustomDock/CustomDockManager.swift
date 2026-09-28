import Cocoa
import Defaults

/// Creates one DockerDoor dock per screen (or one that follows the pointer),
/// binds each to its profile and runs AppSense.
final class CustomDockManager {
    private var controllers: [String: CustomDockController] = [:]
    private var screenObserver: NSObjectProtocol?
    private var defaultsTask: Task<Void, Never>?
    private var followTimer: Timer?
    private let appSense = AppSenseMonitor()
    private var followScreenID: String?
    private var hotKey: GlobalHotKey?
    private var hotKeyTask: Task<Void, Never>?

    init() {
        ProfileManager.ensureDefaultProfile()
        rebuild()
        DockBadgeMonitor.shared.start()
        DockerDoorBackup.runAutomaticBackupIfDue()

        hotKeyTask = Task { [weak self] in
            for await shortcut in Defaults.updates(.customDockLetterShortcut) {
                await MainActor.run { self?.registerHotKey(shortcut) }
            }
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Screens are reported slightly delayed after plugging in a display.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.rebuild() }
        }

        let keys: [Defaults._AnyKey] = [.customDockDisplayMode, .customDockDisplayProfiles, .customDockAppSenseEnabled]
        defaultsTask = Task { [weak self] in
            for await _ in Defaults.updates(keys, initial: false) {
                await MainActor.run { self?.rebuild() }
            }
        }
    }

    func tearDown() {
        ProfileManager.saveCurrent()
        appSense.stop()
        hotKeyTask?.cancel()
        hotKey = nil
        DockBadgeMonitor.shared.stop()
        followTimer?.invalidate()
        followTimer = nil
        defaultsTask?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        controllers.values.forEach { $0.tearDown() }
        controllers.removeAll()
    }

    private func rebuild() {
        let screens = NSScreen.screens
        guard let main = screens.first else { return }
        let mode = Defaults[.customDockDisplayMode]
        let assignments = Defaults[.customDockDisplayProfiles]

        var wanted: [String: String?] = [:] // key → profile
        switch mode {
        case .main:
            wanted["main"] = .some(nil)
        case .follow:
            wanted["follow"] = .some(nil)
        case .all:
            for screen in screens {
                let id = screen.uniqueIdentifier()
                let profile = assignments[id].flatMap { $0.isEmpty ? nil : $0 }
                wanted[id] = .some(profile)
            }
        }

        for (key, controller) in controllers where wanted[key] == nil {
            controller.tearDown()
            controllers[key] = nil
        }

        for (key, profile) in wanted {
            let screenID: String? = switch key {
            case "main": main.uniqueIdentifier()
            case "follow": followScreenID ?? main.uniqueIdentifier()
            default: key
            }
            if let controller = controllers[key] {
                controller.setScreen(screenID)
                controller.setProfile(profile)
            } else {
                controllers[key] = CustomDockController(screenID: screenID, profileID: profile)
            }
        }

        if mode == .follow {
            startFollowing()
        } else {
            followTimer?.invalidate()
            followTimer = nil
        }

        if Defaults[.customDockAppSenseEnabled] {
            appSense.start()
        } else {
            appSense.stop()
        }
        DockerDoorLog.write("Docks: \(mode.title), \(controllers.count) Dock(s)")
    }

    private func registerHotKey(_ shortcut: DockLetterShortcut) {
        hotKey = nil
        guard let keyCode = shortcut.keyCode else { return }
        hotKey = GlobalHotKey(keyCode: keyCode, modifiers: shortcut.carbonModifiers) { [weak self] in
            self?.startLetterNavigation()
        }
    }

    /// Opens letter navigation on the dock of the screen with the pointer.
    private func startLetterNavigation() {
        let mouse = NSEvent.mouseLocation
        let screenID = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }?.uniqueIdentifier()
        let target = controllers.values.first { $0.screenID == screenID && screenID != nil } ?? controllers.values.first
        target?.toggleLetterNavigation()
    }

    /// "Folgt dem Zeiger": the dock moves to the screen whose bottom edge the pointer touches.
    private func startFollowing() {
        guard followTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.checkFollow() }
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    private func checkFollow() {
        guard let controller = controllers["follow"] else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
              mouse.y <= screen.frame.minY + 2
        else { return }
        let id = screen.uniqueIdentifier()
        guard id != controller.screenID else { return }
        followScreenID = id
        controller.setScreen(id)
        DockerDoorLog.write("Dock wechselt auf \(screen.localizedName)")
    }
}
