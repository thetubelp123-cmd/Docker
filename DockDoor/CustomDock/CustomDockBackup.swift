import AppKit
import Defaults
import Foundation
import UniformTypeIdentifiers

extension Defaults.Keys {
    static let customDockAutoBackup = Key<Bool>("customDockAutoBackup", default: true)
    static let customDockLastAutoBackup = Key<Double>("customDockLastAutoBackup", default: 0)
}

/// Saves and restores everything DockerDoor's dock remembers (profiles, content,
/// widgets, look) as one file.
enum DockerDoorBackup {
    static let fileExtension = "dockerdoor"
    private static let marker = "DockerDoorBackupVersion"
    private static let maxAutomaticBackups = 10

    /// Machine-specific state that must never be restored from another moment or Mac.
    private static let excludedKeys: Set<String> = [
        "customDockSystemDockHidden",
        "customDockSavedSystemAutohide",
        "customDockSavedSystemAutohideDelay",
        "customDockDidImportSystemDock",
        "customDockLastAutoBackup",
    ]

    enum BackupError: LocalizedError {
        case notABackup
        case unreadable

        var errorDescription: String? {
            switch self {
            case .notABackup: "Die Datei ist keine Docker-Sicherung."
            case .unreadable: "Die Datei konnte nicht gelesen werden."
            }
        }
    }

    static var contentType: UTType {
        UTType(filenameExtension: fileExtension) ?? .propertyList
    }

    static var backupsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DockerDoor/Backups", isDirectory: true)
    }

    private static func restorableSettings() -> [String: Any] {
        UserDefaults.standard.dictionaryRepresentation().filter { key, _ in
            key.hasPrefix("customDock") && !excludedKeys.contains(key)
        }
    }

    static func suggestedFileName(prefix: String = "Docker-Sicherung") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return "\(prefix)_\(formatter.string(from: Date())).\(fileExtension)"
    }

    static func export(to url: URL) throws {
        ProfileManager.saveCurrent()
        let payload: [String: Any] = [
            marker: 1,
            "created": Date(),
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            "settings": restorableSettings(),
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        DockerDoorLog.write("Sicherung geschrieben: \(url.lastPathComponent)")
    }

    struct BackupInfo {
        let created: Date?
        let appVersion: String
        let profileNames: [String]
    }

    static func inspect(_ url: URL) throws -> BackupInfo {
        let settings = try readSettings(url)
        let payload = try readPayload(url)
        var names: [String] = []
        if let raw = settings["customDockProfiles"] as? [String] {
            names = raw.compactMap { entry in
                guard let data = entry.data(using: .utf8),
                      let profile = try? JSONDecoder().decode(DockProfile.self, from: data) else { return nil }
                return profile.name
            }
        }
        return BackupInfo(created: payload["created"] as? Date, appVersion: payload["appVersion"] as? String ?? "?", profileNames: names)
    }

    /// Replaces the current settings with the backup. A safety copy of the current state is written first.
    static func restore(from url: URL) throws {
        let settings = try readSettings(url)
        try export(to: backupsFolder.appendingPathComponent(suggestedFileName(prefix: "Vor-Wiederherstellung")))

        let defaults = UserDefaults.standard
        for key in restorableSettings().keys where settings[key] == nil {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in settings where key.hasPrefix("customDock") && !excludedKeys.contains(key) {
            defaults.set(value, forKey: key)
        }
        defaults.synchronize()
        DockerDoorLog.write("Sicherung wiederhergestellt: \(url.lastPathComponent)")
    }

    static func runAutomaticBackupIfDue() {
        guard Defaults[.customDockAutoBackup] else { return }
        let last = Date(timeIntervalSince1970: Defaults[.customDockLastAutoBackup])
        guard Date().timeIntervalSince(last) > 24 * 60 * 60 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            do {
                try export(to: backupsFolder.appendingPathComponent(suggestedFileName(prefix: "Automatisch")))
                Defaults[.customDockLastAutoBackup] = Date().timeIntervalSince1970
                pruneAutomaticBackups()
            } catch {
                DockerDoorLog.write("Automatische Sicherung fehlgeschlagen: \(error.localizedDescription)")
            }
        }
    }

    private static func pruneAutomaticBackups() {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(at: backupsFolder, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let automatic = files
            .filter { $0.lastPathComponent.hasPrefix("Automatisch") && $0.pathExtension == fileExtension }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in automatic.dropFirst(maxAutomaticBackups) {
            try? manager.removeItem(at: old)
        }
    }

    private static func readPayload(_ url: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw BackupError.unreadable }
        guard plist[marker] != nil else { throw BackupError.notABackup }
        return plist
    }

    private static func readSettings(_ url: URL) throws -> [String: Any] {
        guard let settings = try readPayload(url)["settings"] as? [String: Any] else { throw BackupError.notABackup }
        return settings
    }
}
