import AppKit
import Defaults
import Foundation

/// Look and behaviour of a dock, stored with every profile.
struct DockProfileSettings: Codable, Hashable {
    var iconSize: Double
    var magnification: Bool
    var magnifiedSize: Double
    var layoutMode: String
    var material: String
    var tintOpacity: Double
    var showBorder: Bool
    var appearance: String
    var autoHide: Bool
    var indicatorStyle: String
    var showTrash: Bool
    var showAppNames: Bool

    static func current() -> DockProfileSettings {
        DockProfileSettings(
            iconSize: Defaults[.customDockIconSize],
            magnification: Defaults[.customDockMagnification],
            magnifiedSize: Defaults[.customDockMagnifiedSize],
            layoutMode: Defaults[.customDockLayoutMode].rawValue,
            material: Defaults[.customDockMaterial].rawValue,
            tintOpacity: Defaults[.customDockTintOpacity],
            showBorder: Defaults[.customDockShowBorder],
            appearance: Defaults[.customDockAppearance].rawValue,
            autoHide: Defaults[.customDockAutoHide],
            indicatorStyle: Defaults[.customDockIndicatorStyle].rawValue,
            showTrash: Defaults[.customDockShowTrash],
            showAppNames: Defaults[.customDockShowAppNames]
        )
    }

    func apply() {
        // Only write what differs, so unchanged settings don't trigger relayouts.
        func set<T: Equatable & Defaults.Serializable>(_ key: Defaults.Key<T>, _ value: T) {
            if Defaults[key] != value { Defaults[key] = value }
        }
        set(.customDockIconSize, iconSize)
        set(.customDockMagnification, magnification)
        set(.customDockMagnifiedSize, magnifiedSize)
        if let value = CustomDockLayoutMode(rawValue: layoutMode) { set(.customDockLayoutMode, value) }
        if let value = CustomDockMaterial(rawValue: material) { set(.customDockMaterial, value) }
        set(.customDockTintOpacity, tintOpacity)
        set(.customDockShowBorder, showBorder)
        if let value = CustomDockAppearance(rawValue: appearance) { set(.customDockAppearance, value) }
        set(.customDockAutoHide, autoHide)
        if let value = CustomDockIndicatorStyle(rawValue: indicatorStyle) { set(.customDockIndicatorStyle, value) }
        set(.customDockShowTrash, showTrash)
        set(.customDockShowAppNames, showAppNames)
    }
}

struct DockProfile: Codable, Hashable, Identifiable, Defaults.Serializable {
    var id: String
    var name: String
    var symbol: String
    var pinnedItems: [PinnedDockItem]
    var settings: DockProfileSettings
    /// Bundle identifiers that switch to this profile when they become active (AppSense).
    var triggerApps: [String]

    static let symbols = [
        "house", "briefcase", "graduationcap", "book", "paintbrush", "music.note",
        "gamecontroller", "film", "chevron.left.forwardslash.chevron.right", "globe",
        "moon", "sun.max", "star", "heart", "bolt", "leaf",
    ]
}

enum CustomDockDisplayMode: String, CaseIterable, Defaults.Serializable {
    case main
    case all
    case follow

    var title: String {
        switch self {
        case .main: "Hauptbildschirm"
        case .all: "Alle Bildschirme"
        case .follow: "Folgt dem Zeiger"
        }
    }
}

extension Defaults.Keys {
    static let customDockProfiles = Key<[DockProfile]>("customDockProfiles", default: [])
    static let customDockActiveProfile = Key<String>("customDockActiveProfile", default: "")
    static let customDockAppSenseEnabled = Key<Bool>("customDockAppSenseEnabled", default: false)
    static let customDockShowControlTile = Key<Bool>("customDockShowControlTile", default: true)
    static let customDockDisplayMode = Key<CustomDockDisplayMode>("customDockDisplayMode", default: .main)
    /// Screen identifier → profile ID for "Alle Bildschirme". Missing or empty = active profile.
    static let customDockDisplayProfiles = Key<[String: String]>("customDockDisplayProfiles", default: [:])
}

/// Profiles store a full dock (content and look). The live settings keys always belong
/// to the active profile; switching saves them into it and loads the other profile.
enum ProfileManager {
    static var profiles: [DockProfile] { Defaults[.customDockProfiles] }

    static var active: DockProfile? {
        let id = Defaults[.customDockActiveProfile]
        return profiles.first { $0.id == id }
    }

    static func ensureDefaultProfile() {
        var list = profiles
        if list.isEmpty {
            let profile = DockProfile(
                id: UUID().uuidString,
                name: "Standard",
                symbol: "house",
                pinnedItems: Defaults[.customDockPinnedItems],
                settings: .current(),
                triggerApps: []
            )
            list = [profile]
            Defaults[.customDockProfiles] = list
        }
        if !list.contains(where: { $0.id == Defaults[.customDockActiveProfile] }) {
            Defaults[.customDockActiveProfile] = list[0].id
        }
    }

    /// Writes the live dock into the active profile.
    static func saveCurrent() {
        var list = profiles
        guard let index = list.firstIndex(where: { $0.id == Defaults[.customDockActiveProfile] }) else { return }
        let items = Defaults[.customDockPinnedItems]
        let settings = DockProfileSettings.current()
        guard list[index].pinnedItems != items || list[index].settings != settings else { return }
        list[index].pinnedItems = items
        list[index].settings = settings
        Defaults[.customDockProfiles] = list
    }

    static func activate(_ id: String, reason: String = "manuell") {
        guard id != Defaults[.customDockActiveProfile],
              let target = profiles.first(where: { $0.id == id })
        else { return }
        saveCurrent()
        Defaults[.customDockActiveProfile] = id
        if Defaults[.customDockPinnedItems] != target.pinnedItems {
            Defaults[.customDockPinnedItems] = target.pinnedItems
        }
        target.settings.apply()
        DockerDoorLog.write("Profil „\(target.name)“ aktiv (\(reason))")
    }

    static func activateNeighbour(_ step: Int) {
        let list = profiles
        guard list.count > 1,
              let index = list.firstIndex(where: { $0.id == Defaults[.customDockActiveProfile] })
        else { return }
        activate(list[(index + step + list.count) % list.count].id)
    }

    @discardableResult
    static func create(name: String, copyCurrent: Bool) -> DockProfile {
        saveCurrent()
        let finder = PinnedDockItem(kind: .app, path: CustomDockStore.finderPath, bundleIdentifier: CustomDockStore.finderBundleID)
        let used = Set(profiles.map(\.symbol))
        let profile = DockProfile(
            id: UUID().uuidString,
            name: name,
            symbol: DockProfile.symbols.first { !used.contains($0) } ?? "star",
            pinnedItems: copyCurrent ? Defaults[.customDockPinnedItems] : [finder],
            settings: .current(),
            triggerApps: []
        )
        Defaults[.customDockProfiles] = profiles + [profile]
        return profile
    }

    static func update(_ id: String, _ change: (inout DockProfile) -> Void) {
        var list = profiles
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        change(&list[index])
        Defaults[.customDockProfiles] = list
    }

    static func delete(_ id: String) {
        let list = profiles
        guard list.count > 1 else { return }
        if id == Defaults[.customDockActiveProfile], let other = list.first(where: { $0.id != id }) {
            activate(other.id)
        }
        Defaults[.customDockProfiles] = profiles.filter { $0.id != id }
        Defaults[.customDockDisplayProfiles] = Defaults[.customDockDisplayProfiles].filter { $0.value != id }
    }

    static func appName(for bundleIdentifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return bundleIdentifier }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// Switches profiles automatically when an app that belongs to a profile comes to the front.
final class AppSenseMonitor {
    private var observer: NSObjectProtocol?
    private var pending: DispatchWorkItem?
    /// Profile to return to when no AppSense app is in front anymore.
    private var returnProfileID: String?
    private var appSenseProfileID: String?

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.schedule(app?.bundleIdentifier)
        }
        schedule(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        pending?.cancel()
        returnProfileID = nil
        appSenseProfileID = nil
    }

    private func schedule(_ bundleIdentifier: String?) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.evaluate(bundleIdentifier) }
        pending = work
        // Short delay so quickly flipping through apps (Cmd+Tab) doesn't switch every time.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func evaluate(_ bundleIdentifier: String?) {
        guard let bundleIdentifier, bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let active = Defaults[.customDockActiveProfile]

        // The user changed the profile by hand since our last switch: respect that.
        if let appSenseProfileID, appSenseProfileID != active {
            self.appSenseProfileID = nil
            returnProfileID = nil
        }

        if let match = ProfileManager.profiles.first(where: { $0.triggerApps.contains(bundleIdentifier) }) {
            guard match.id != active else { return }
            if appSenseProfileID == nil { returnProfileID = active }
            appSenseProfileID = match.id
            ProfileManager.activate(match.id, reason: "AppSense: \(ProfileManager.appName(for: bundleIdentifier))")
        } else if appSenseProfileID != nil, let back = returnProfileID {
            appSenseProfileID = nil
            returnProfileID = nil
            ProfileManager.activate(back, reason: "AppSense: zurück")
        }
    }
}
