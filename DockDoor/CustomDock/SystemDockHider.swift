import Cocoa
import Defaults

/// Hides the macOS Dock by turning on auto-hide with a very long reveal delay,
/// and restores the user's original settings afterwards.
enum SystemDockHider {
    private static let dockDomain = "com.apple.dock" as CFString
    private static let hiddenDelay: Double = 1000

    static func sync() {
        let shouldHide = Defaults[.customDockEnabled] && Defaults[.customDockHideSystemDock]
        if shouldHide {
            hide()
        } else {
            restore()
        }
    }

    static func hide() {
        if !Defaults[.customDockSystemDockHidden] {
            Defaults[.customDockSavedSystemAutohide] = readBool("autohide").map { $0 ? 1 : 0 } ?? -1
            Defaults[.customDockSavedSystemAutohideDelay] = readDouble("autohide-delay") ?? -1
            Defaults[.customDockSystemDockHidden] = true
        }

        let alreadyHidden = readBool("autohide") == true && (readDouble("autohide-delay") ?? 0) >= hiddenDelay
        guard !alreadyHidden else { return }

        runDefaults(["write", "com.apple.dock", "autohide", "-bool", "true"])
        runDefaults(["write", "com.apple.dock", "autohide-delay", "-float", "\(hiddenDelay)"])
        restartDock()
    }

    static func restore() {
        guard Defaults[.customDockSystemDockHidden] else { return }

        switch Defaults[.customDockSavedSystemAutohide] {
        case 1: runDefaults(["write", "com.apple.dock", "autohide", "-bool", "true"])
        case 0: runDefaults(["write", "com.apple.dock", "autohide", "-bool", "false"])
        default: runDefaults(["delete", "com.apple.dock", "autohide"])
        }

        let delay = Defaults[.customDockSavedSystemAutohideDelay]
        if delay >= 0, delay < hiddenDelay {
            runDefaults(["write", "com.apple.dock", "autohide-delay", "-float", "\(delay)"])
        } else {
            runDefaults(["delete", "com.apple.dock", "autohide-delay"])
        }

        Defaults[.customDockSystemDockHidden] = false
        restartDock()
    }

    private static func readBool(_ key: String) -> Bool? {
        CFPreferencesAppSynchronize(dockDomain)
        guard let value = CFPreferencesCopyAppValue(key as CFString, dockDomain) else { return nil }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return (string as NSString).boolValue }
        return nil
    }

    private static func readDouble(_ key: String) -> Double? {
        CFPreferencesAppSynchronize(dockDomain)
        guard let value = CFPreferencesCopyAppValue(key as CFString, dockDomain) else { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func runDefaults(_ arguments: [String]) {
        run("/usr/bin/defaults", arguments)
    }

    private static func restartDock() {
        run("/usr/bin/killall", ["Dock"])
    }

    private static func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            DebugLogger.log("SystemDockHider", details: "\(path) \(arguments.joined(separator: " ")) failed: \(error)")
        }
    }
}
