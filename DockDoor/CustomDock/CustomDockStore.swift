import Cocoa
import Combine
import Defaults

enum DockTileKind: Equatable {
    case app
    case folder
    case file
    case trash
}

struct DockTile: Identifiable, Equatable {
    let id: String
    let kind: DockTileKind
    let url: URL?
    let bundleIdentifier: String?
    let name: String
    let isPinned: Bool
    let isRunning: Bool
    let isActive: Bool
    let isHidden: Bool
    let pid: pid_t?
}

final class CustomDockStore: ObservableObject {
    static let finderPath = "/System/Library/CoreServices/Finder.app"
    static let finderBundleID = "com.apple.finder"

    @Published private(set) var appTiles: [DockTile] = []
    @Published private(set) var otherTiles: [DockTile] = []
    @Published private(set) var launchingIDs: Set<String> = []
    @Published private(set) var trashIsFull = false

    private var runningOrder: [pid_t] = []
    private var iconCache: [String: NSImage] = [:]
    private var observers: [NSObjectProtocol] = []
    private var defaultsTask: Task<Void, Never>?
    private var trashTimer: Timer?

    var allTiles: [DockTile] { appTiles + otherTiles }

    init() {
        importSystemDockIfNeeded()
        runningOrder = NSWorkspace.shared.runningApplications.map(\.processIdentifier)
        observeWorkspace()
        let keys: [Defaults._AnyKey] = [.customDockPinnedItems, .customDockShowTrash]
        defaultsTask = Task { [weak self] in
            for await _ in Defaults.updates(keys, initial: false) {
                await MainActor.run { self?.rebuild() }
            }
        }
        trashTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshTrashState()
        }
        refreshTrashState()
        rebuild()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        trashTimer?.invalidate()
        defaultsTask?.cancel()
    }

    // MARK: - Building tiles

    func rebuild() {
        let pinned = normalizedPinnedItems()
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        let orderedRunning = running.sorted { lhs, rhs in
            (runningOrder.firstIndex(of: lhs.processIdentifier) ?? Int.max) < (runningOrder.firstIndex(of: rhs.processIdentifier) ?? Int.max)
        }
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        var usedPIDs = Set<pid_t>()
        var apps: [DockTile] = []

        for item in pinned where item.kind == .app {
            let match = orderedRunning.first { app in
                guard !usedPIDs.contains(app.processIdentifier) else { return false }
                if let bid = item.bundleIdentifier, let appBID = app.bundleIdentifier { return bid == appBID }
                return app.bundleURL?.standardizedFileURL.path == item.url.standardizedFileURL.path
            }
            if let match { usedPIDs.insert(match.processIdentifier) }
            apps.append(DockTile(
                id: item.id,
                kind: .app,
                url: item.url,
                bundleIdentifier: item.bundleIdentifier ?? match?.bundleIdentifier,
                name: displayName(for: item.url, fallback: match?.localizedName),
                isPinned: true,
                isRunning: match != nil,
                isActive: match?.processIdentifier == frontmostPID,
                isHidden: match?.isHidden ?? false,
                pid: match?.processIdentifier
            ))
        }

        var usedIDs = Set(apps.map(\.id))
        for app in orderedRunning where !usedPIDs.contains(app.processIdentifier) {
            let url = app.bundleURL
            var tileID = url?.path ?? "pid-\(app.processIdentifier)"
            if usedIDs.contains(tileID) { tileID = "pid-\(app.processIdentifier)" }
            usedIDs.insert(tileID)
            apps.append(DockTile(
                id: tileID,
                kind: .app,
                url: url,
                bundleIdentifier: app.bundleIdentifier,
                name: app.localizedName ?? url.map { displayName(for: $0, fallback: nil) } ?? "App",
                isPinned: false,
                isRunning: true,
                isActive: app.processIdentifier == frontmostPID,
                isHidden: app.isHidden,
                pid: app.processIdentifier
            ))
        }

        var others: [DockTile] = pinned.filter { $0.kind != .app }.map { item in
            DockTile(
                id: item.id,
                kind: item.kind == .folder ? .folder : .file,
                url: item.url,
                bundleIdentifier: nil,
                name: displayName(for: item.url, fallback: nil),
                isPinned: true,
                isRunning: false,
                isActive: false,
                isHidden: false,
                pid: nil
            )
        }
        if Defaults[.customDockShowTrash] {
            others.append(DockTile(
                id: "trash",
                kind: .trash,
                url: Self.trashURL,
                bundleIdentifier: nil,
                name: "Papierkorb",
                isPinned: true,
                isRunning: false,
                isActive: false,
                isHidden: false,
                pid: nil
            ))
        }

        let runningIDs = Set(apps.filter(\.isRunning).map(\.id))
        let stillLaunching = launchingIDs.subtracting(runningIDs)

        if apps != appTiles { appTiles = apps }
        if others != otherTiles { otherTiles = others }
        if stillLaunching != launchingIDs { launchingIDs = stillLaunching }
    }

    private func normalizedPinnedItems() -> [PinnedDockItem] {
        var items = Defaults[.customDockPinnedItems].filter { FileManager.default.fileExists(atPath: $0.path) }
        if !items.contains(where: { $0.bundleIdentifier == Self.finderBundleID || $0.path == Self.finderPath }) {
            items.insert(PinnedDockItem(kind: .app, path: Self.finderPath, bundleIdentifier: Self.finderBundleID), at: 0)
        }
        return items
    }

    private func displayName(for url: URL, fallback: String?) -> String {
        if let fallback, !fallback.isEmpty { return fallback }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    // MARK: - Icons

    func icon(for tile: DockTile) -> NSImage {
        if tile.kind == .trash {
            let name = trashIsFull ? "NSTrashFull" : "NSTrashEmpty"
            return NSImage(named: NSImage.Name(name)) ?? NSWorkspace.shared.icon(for: .folder)
        }
        let key = tile.url?.path ?? tile.id
        if let cached = iconCache[key] { return cached }

        let image: NSImage
        if let url = tile.url {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else if let pid = tile.pid, let app = NSRunningApplication(processIdentifier: pid), let appIcon = app.icon {
            image = appIcon
        } else {
            image = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        image.size = NSSize(width: 256, height: 256)
        iconCache[key] = image
        return image
    }

    // MARK: - Workspace observation

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    if name == NSWorkspace.didLaunchApplicationNotification, !runningOrder.contains(app.processIdentifier) {
                        runningOrder.append(app.processIdentifier)
                    } else if name == NSWorkspace.didTerminateApplicationNotification {
                        runningOrder.removeAll { $0 == app.processIdentifier }
                    }
                }
                rebuild()
                // Some apps switch to a regular activation policy shortly after launch.
                if name == NSWorkspace.didLaunchApplicationNotification {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.rebuild() }
                }
            })
        }
    }

    // MARK: - Actions

    func open(_ tile: DockTile) {
        switch tile.kind {
        case .app:
            openApp(tile)
        case .folder, .file:
            if let url = tile.url { NSWorkspace.shared.open(url) }
        case .trash:
            NSWorkspace.shared.open(Self.trashURL)
        }
    }

    private func openApp(_ tile: DockTile) {
        if let pid = tile.pid, let app = NSRunningApplication(processIdentifier: pid), app.isHidden {
            app.unhide()
        }
        guard let url = tile.url else {
            if let pid = tile.pid { NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows]) }
            return
        }
        if !tile.isRunning {
            launchingIDs.insert(tile.id)
            let id = tile.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
                self?.launchingIDs.remove(id)
            }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            if let error {
                DebugLogger.log("CustomDock", details: "Open failed for \(url.path): \(error)")
                DispatchQueue.main.async { self?.launchingIDs.remove(tile.id) }
            }
        }
    }

    func open(urls: [URL], with tile: DockTile) {
        guard tile.kind == .app, let appURL = tile.url, !urls.isEmpty else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration, completionHandler: nil)
    }

    func moveToTrash(_ urls: [URL]) {
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                DebugLogger.log("CustomDock", details: "Trash failed for \(url.path): \(error)")
            }
        }
        refreshTrashState()
    }

    func pin(_ tile: DockTile) {
        guard let url = tile.url, !tile.isPinned else { return }
        pin(url: url, bundleIdentifier: tile.bundleIdentifier)
    }

    func pin(url: URL, bundleIdentifier: String? = nil) {
        let path = url.standardizedFileURL.path
        var items = Defaults[.customDockPinnedItems]
        guard !items.contains(where: { $0.path == path }) else { return }
        let kind: PinnedDockItemKind
        if url.pathExtension == "app" {
            kind = .app
        } else {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            kind = isDirectory.boolValue ? .folder : .file
        }
        let bid = bundleIdentifier ?? (kind == .app ? Bundle(url: url)?.bundleIdentifier : nil)
        items.append(PinnedDockItem(kind: kind, path: path, bundleIdentifier: bid))
        Defaults[.customDockPinnedItems] = items
    }

    func unpin(_ tile: DockTile) {
        guard tile.isPinned, tile.bundleIdentifier != Self.finderBundleID else { return }
        Defaults[.customDockPinnedItems].removeAll { $0.path == tile.id }
    }

    func revealInFinder(_ tile: DockTile) {
        guard let url = tile.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func hide(_ tile: DockTile) {
        guard let pid = tile.pid else { return }
        NSRunningApplication(processIdentifier: pid)?.hide()
    }

    func quit(_ tile: DockTile, force: Bool = false) {
        guard let pid = tile.pid, let app = NSRunningApplication(processIdentifier: pid) else { return }
        if force { app.forceTerminate() } else { app.terminate() }
    }

    func emptyTrash() {
        let script = NSAppleScript(source: "tell application \"Finder\" to empty trash")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if let error { DebugLogger.log("CustomDock", details: "Empty trash failed: \(error)") }
        refreshTrashState()
    }

    // MARK: - Trash

    static var trashURL: URL {
        FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
    }

    private func refreshTrashState() {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: Self.trashURL.path)) ?? []
        let full = contents.contains { $0 != ".DS_Store" && $0 != ".localized" }
        if full != trashIsFull { trashIsFull = full }
    }

    // MARK: - Import from the macOS Dock

    func importSystemDockIfNeeded() {
        guard !Defaults[.customDockDidImportSystemDock] else { return }
        let imported = Self.readSystemDockItems()
        if !imported.isEmpty {
            Defaults[.customDockPinnedItems] = imported
        }
        Defaults[.customDockDidImportSystemDock] = true
    }

    static func reimportFromSystemDock() {
        let imported = readSystemDockItems()
        guard !imported.isEmpty else { return }
        Defaults[.customDockPinnedItems] = imported
    }

    static func readSystemDockItems() -> [PinnedDockItem] {
        let domain = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(domain)
        let apps = CFPreferencesCopyAppValue("persistent-apps" as CFString, domain) as? [[String: Any]] ?? []
        let others = CFPreferencesCopyAppValue("persistent-others" as CFString, domain) as? [[String: Any]] ?? []

        var result: [PinnedDockItem] = [PinnedDockItem(kind: .app, path: finderPath, bundleIdentifier: finderBundleID)]
        for entry in apps {
            guard let item = parseTile(entry, defaultKind: .app) else { continue }
            if !result.contains(where: { $0.path == item.path }) { result.append(item) }
        }
        for entry in others {
            guard let item = parseTile(entry, defaultKind: .folder) else { continue }
            if !result.contains(where: { $0.path == item.path }) { result.append(item) }
        }
        return result
    }

    private static func parseTile(_ entry: [String: Any], defaultKind: PinnedDockItemKind) -> PinnedDockItem? {
        let tileType = entry["tile-type"] as? String ?? ""
        guard tileType == "file-tile" || tileType == "directory-tile" else { return nil }
        guard let tileData = entry["tile-data"] as? [String: Any],
              let fileData = tileData["file-data"] as? [String: Any],
              let urlString = fileData["_CFURLString"] as? String
        else { return nil }

        let urlType = fileData["_CFURLStringType"] as? Int ?? 15
        let url: URL? = urlType == 0 ? URL(fileURLWithPath: urlString) : URL(string: urlString)
        guard let url, url.isFileURL else { return nil }
        let path = url.standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let kind: PinnedDockItemKind
        if url.pathExtension == "app" {
            kind = .app
        } else if tileType == "directory-tile" {
            kind = .folder
        } else {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            kind = isDirectory.boolValue ? .folder : (defaultKind == .app ? .file : .file)
        }
        let bundleID = tileData["bundle-identifier"] as? String ?? (kind == .app ? Bundle(url: url)?.bundleIdentifier : nil)
        return PinnedDockItem(kind: kind, path: path, bundleIdentifier: bundleID)
    }
}
