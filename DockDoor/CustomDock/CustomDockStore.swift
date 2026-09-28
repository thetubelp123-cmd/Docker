import Cocoa
import Combine
import Defaults

enum DockTileKind: Equatable {
    case app
    case folder
    case file
    case trash
    case group
    case widget
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
    var members: [PinnedGroupMember] = []
    var stackMode: StackDisplayMode?
    var stackSort: StackSortOrder?
    var widgets: [DockWidgetKind] = []

    var isGroup: Bool { kind == .group }
    var isWidgetStack: Bool { kind == .widget && widgets.count > 1 }
    var widthFactor: CGFloat { kind == .widget ? (widgets.map(\.widthFactor).max() ?? 1) : 1 }
    var isFinder: Bool { bundleIdentifier == CustomDockStore.finderBundleID }
    /// Tiles the user can drag to a new place.
    var isMovable: Bool { kind != .trash && !isFinder }
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

        for item in pinned where item.kind == .app || item.kind == .group {
            if item.kind == .group {
                let members = item.members ?? []
                var anyRunning = false
                var anyActive = false
                for member in members {
                    if let app = orderedRunning.first(where: { app in
                        !usedPIDs.contains(app.processIdentifier) && matches(app, path: member.path, bundleIdentifier: member.bundleIdentifier)
                    }) {
                        usedPIDs.insert(app.processIdentifier)
                        anyRunning = true
                        if app.processIdentifier == frontmostPID { anyActive = true }
                    }
                }
                apps.append(DockTile(
                    id: item.id,
                    kind: .group,
                    url: nil,
                    bundleIdentifier: nil,
                    name: item.name ?? "Gruppe",
                    isPinned: true,
                    isRunning: anyRunning,
                    isActive: anyActive,
                    isHidden: false,
                    pid: nil,
                    members: members,
                    stackMode: item.stackMode,
                    stackSort: item.stackSort
                ))
                continue
            }
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

        var others: [DockTile] = pinned.filter { Self.isOtherSection($0.kind) }.map { item in
            if item.kind == .widget {
                let widgets = item.widgets ?? []
                return DockTile(
                    id: item.id,
                    kind: .widget,
                    url: nil,
                    bundleIdentifier: nil,
                    name: widgets.count > 1 ? "Widget-Stapel" : (widgets.first?.title ?? "Widget"),
                    isPinned: true,
                    isRunning: false,
                    isActive: false,
                    isHidden: false,
                    pid: nil,
                    widgets: widgets
                )
            }
            return DockTile(
                id: item.id,
                kind: item.kind == .folder ? .folder : .file,
                url: item.url,
                bundleIdentifier: nil,
                name: displayName(for: item.url, fallback: nil),
                isPinned: true,
                isRunning: false,
                isActive: false,
                isHidden: false,
                pid: nil,
                stackMode: item.stackMode,
                stackSort: item.stackSort
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

    private func matches(_ app: NSRunningApplication, path: String, bundleIdentifier: String?) -> Bool {
        if let bundleIdentifier, let appBID = app.bundleIdentifier { return bundleIdentifier == appBID }
        return app.bundleURL?.standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path
    }

    func normalizedPinnedItems() -> [PinnedDockItem] {
        var items: [PinnedDockItem] = Defaults[.customDockPinnedItems].compactMap { item in
            if item.kind == .widget {
                return item.widgets?.isEmpty == false ? item : nil
            }
            guard item.kind == .group else {
                return FileManager.default.fileExists(atPath: item.path) ? item : nil
            }
            var group = item
            group.members = (item.members ?? []).filter { FileManager.default.fileExists(atPath: $0.path) }
            return group.members?.isEmpty == false ? group : nil
        }
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
        if tile.kind == .widget {
            let kind = tile.widgets.first ?? .clock
            let key = "widget|\(kind.rawValue)"
            if let cached = iconCache[key] { return cached }
            let image = Self.widgetIcon(for: kind)
            iconCache[key] = image
            return image
        }
        if tile.kind == .group {
            let key = "group|" + tile.members.prefix(4).map(\.path).joined(separator: "|")
            if let cached = iconCache[key] { return cached }
            let image = Self.groupIcon(for: tile.members.prefix(4).map { NSWorkspace.shared.icon(forFile: $0.path) })
            iconCache[key] = image
            return image
        }
        let key = tile.url?.path ?? tile.id
        if let cached = iconCache[key] { return cached }

        let image: NSImage = if let url = tile.url {
            NSWorkspace.shared.icon(forFile: url.path)
        } else if let pid = tile.pid, let app = NSRunningApplication(processIdentifier: pid), let appIcon = app.icon {
            appIcon
        } else {
            NSWorkspace.shared.icon(for: .applicationBundle)
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
        case .group, .widget:
            break
        }
    }

    func openApp(at url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
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

    // MARK: - Reordering

    /// Moves a tile inside its section. `index` counts pinned items of that section
    /// (apps and groups, or folders and files). Unpinned running apps become pinned.
    func move(_ tile: DockTile, toIndex index: Int) {
        guard tile.isMovable else { return }
        let items = normalizedPinnedItems()
        let isAppSection = tile.kind == .app || tile.kind == .group
        var section = items.filter { isAppSection ? !Self.isOtherSection($0.kind) : Self.isOtherSection($0.kind) }
        let rest = items.filter { isAppSection ? Self.isOtherSection($0.kind) : !Self.isOtherSection($0.kind) }

        var moving: PinnedDockItem
        if let existing = section.firstIndex(where: { $0.id == tile.id }) {
            moving = section.remove(at: existing)
        } else if tile.kind == .app, let url = tile.url {
            moving = PinnedDockItem(kind: .app, path: url.standardizedFileURL.path, bundleIdentifier: tile.bundleIdentifier)
        } else {
            return
        }
        var target = min(max(index, 0), section.count)
        if isAppSection, target == 0, section.first?.bundleIdentifier == Self.finderBundleID { target = 1 }
        section.insert(moving, at: target)
        Defaults[.customDockPinnedItems] = isAppSection ? section + rest : rest + section
    }

    static func isOtherSection(_ kind: PinnedDockItemKind) -> Bool {
        kind == .folder || kind == .file || kind == .widget
    }

    // MARK: - Widgets

    func addWidget(_ kind: DockWidgetKind) {
        Self.appendWidget(kind)
    }

    static func appendWidget(_ kind: DockWidgetKind) {
        var items = Defaults[.customDockPinnedItems]
        items.append(.newWidget([kind]))
        Defaults[.customDockPinnedItems] = items
    }

    func addWidget(_ kind: DockWidgetKind, toStack stackID: String) {
        var items = normalizedPinnedItems()
        guard let index = items.firstIndex(where: { $0.id == stackID }) else { return }
        var widgets = items[index].widgets ?? []
        if !widgets.contains(kind) { widgets.append(kind) }
        items[index].widgets = widgets
        Defaults[.customDockPinnedItems] = items
    }

    /// Puts the widgets of `tile` into the stack `targetID` (a single widget becomes a stack).
    func mergeWidgets(_ tile: DockTile, into targetID: String) {
        var items = normalizedPinnedItems()
        guard tile.id != targetID, let index = items.firstIndex(where: { $0.id == targetID }) else { return }
        var widgets = items[index].widgets ?? []
        for kind in tile.widgets where !widgets.contains(kind) {
            widgets.append(kind)
        }
        items[index].widgets = widgets
        items.removeAll { $0.id == tile.id }
        Defaults[.customDockPinnedItems] = items
    }

    /// Takes one widget out of a stack and puts it next to the stack.
    func removeWidget(_ kind: DockWidgetKind, fromStack stackID: String) {
        var items = normalizedPinnedItems()
        guard let index = items.firstIndex(where: { $0.id == stackID }) else { return }
        var widgets = items[index].widgets ?? []
        widgets.removeAll { $0 == kind }
        if widgets.isEmpty {
            items.remove(at: index)
        } else {
            items[index].widgets = widgets
            items.insert(.newWidget([kind]), at: index + 1)
        }
        Defaults[.customDockPinnedItems] = items
    }

    func dissolveWidgetStack(_ stackID: String) {
        var items = normalizedPinnedItems()
        guard let index = items.firstIndex(where: { $0.id == stackID }) else { return }
        let singles = (items[index].widgets ?? []).map { PinnedDockItem.newWidget([$0]) }
        items.remove(at: index)
        items.insert(contentsOf: singles, at: index)
        Defaults[.customDockPinnedItems] = items
    }

    static func widgetIcon(for kind: DockWidgetKind) -> NSImage {
        let size = NSSize(width: 256, height: 256)
        return NSImage(size: size, flipped: false) { rect in
            let background = NSBezierPath(roundedRect: rect.insetBy(dx: 14, dy: 14), xRadius: 56, yRadius: 56)
            NSColor(white: 0.2, alpha: 0.9).setFill()
            background.fill()
            let configuration = NSImage.SymbolConfiguration(pointSize: 110, weight: .medium)
                .applying(.init(paletteColors: [.white]))
            if let symbol = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
                let symbolSize = symbol.size
                symbol.draw(in: NSRect(
                    x: rect.midX - symbolSize.width / 2,
                    y: rect.midY - symbolSize.height / 2,
                    width: symbolSize.width,
                    height: symbolSize.height
                ))
            }
            return true
        }
    }

    // MARK: - App groups

    var groups: [PinnedDockItem] {
        normalizedPinnedItems().filter(\.isGroup)
    }

    private func member(for tile: DockTile) -> PinnedGroupMember? {
        guard tile.kind == .app, let url = tile.url else { return nil }
        return PinnedGroupMember(path: url.standardizedFileURL.path, bundleIdentifier: tile.bundleIdentifier)
    }

    /// Creates a group from `tile` and `other` at the position of `other`.
    func createGroup(from tile: DockTile, with other: DockTile, name: String = "Gruppe") {
        guard let first = member(for: other), let second = member(for: tile), !tile.isFinder, !other.isFinder else { return }
        var items = normalizedPinnedItems()
        let position = items.firstIndex { $0.id == other.id } ?? items.filter { $0.kind == .app || $0.kind == .group }.count
        items.removeAll { $0.id == tile.id || $0.id == other.id }
        let group = PinnedDockItem.newGroup(name: name, members: [first, second])
        items.insert(group, at: min(position, items.count))
        Defaults[.customDockPinnedItems] = items
    }

    func createGroup(with tile: DockTile, name: String = "Gruppe") {
        guard let first = member(for: tile), !tile.isFinder else { return }
        var items = normalizedPinnedItems()
        let position = items.firstIndex { $0.id == tile.id } ?? items.filter { $0.kind == .app || $0.kind == .group }.count
        items.removeAll { $0.id == tile.id }
        items.insert(PinnedDockItem.newGroup(name: name, members: [first]), at: min(position, items.count))
        Defaults[.customDockPinnedItems] = items
    }

    func add(_ tile: DockTile, toGroup groupID: String) {
        guard let newMember = member(for: tile), !tile.isFinder else { return }
        var items = normalizedPinnedItems()
        items.removeAll { $0.id == tile.id }
        guard let index = items.firstIndex(where: { $0.id == groupID }) else { return }
        var members = items[index].members ?? []
        if !members.contains(where: { $0.path == newMember.path }) { members.append(newMember) }
        items[index].members = members
        Defaults[.customDockPinnedItems] = items
    }

    func add(appURL: URL, toGroup groupID: String) {
        var items = normalizedPinnedItems()
        guard let index = items.firstIndex(where: { $0.id == groupID }) else { return }
        let path = appURL.standardizedFileURL.path
        var members = items[index].members ?? []
        if !members.contains(where: { $0.path == path }) {
            members.append(PinnedGroupMember(path: path, bundleIdentifier: Bundle(url: appURL)?.bundleIdentifier))
        }
        items[index].members = members
        Defaults[.customDockPinnedItems] = items
    }

    /// Removes an app from a group and puts it back into the dock right after the group.
    func remove(memberPath: String, fromGroup groupID: String) {
        var items = normalizedPinnedItems()
        guard let index = items.firstIndex(where: { $0.id == groupID }) else { return }
        var members = items[index].members ?? []
        guard let memberIndex = members.firstIndex(where: { $0.path == memberPath }) else { return }
        let removed = members.remove(at: memberIndex)
        let appItem = PinnedDockItem(kind: .app, path: removed.path, bundleIdentifier: removed.bundleIdentifier)
        if members.isEmpty {
            items[index] = appItem
        } else {
            items[index].members = members
            items.insert(appItem, at: index + 1)
        }
        Defaults[.customDockPinnedItems] = items
    }

    func dissolveGroup(_ groupID: String) {
        var items = normalizedPinnedItems()
        guard let index = items.firstIndex(where: { $0.id == groupID }) else { return }
        let apps = (items[index].members ?? []).map { PinnedDockItem(kind: .app, path: $0.path, bundleIdentifier: $0.bundleIdentifier) }
            .filter { app in !items.contains { $0.path == app.path } }
        items.remove(at: index)
        items.insert(contentsOf: apps, at: index)
        Defaults[.customDockPinnedItems] = items
    }

    func renameGroup(_ groupID: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = normalizedPinnedItems()
        guard let index = items.firstIndex(where: { $0.id == groupID }) else { return }
        items[index].name = trimmed
        Defaults[.customDockPinnedItems] = items
    }

    func removeGroup(_ groupID: String) {
        Defaults[.customDockPinnedItems] = normalizedPinnedItems().filter { $0.id != groupID }
    }

    // MARK: - Stack options

    func setStackMode(_ mode: StackDisplayMode?, for tileID: String) {
        var items = normalizedPinnedItems()
        guard let index = items.firstIndex(where: { $0.id == tileID }) else { return }
        items[index].stackMode = mode
        Defaults[.customDockPinnedItems] = items
    }

    func setStackSort(_ sort: StackSortOrder?, for tileID: String) {
        var items = normalizedPinnedItems()
        guard let index = items.firstIndex(where: { $0.id == tileID }) else { return }
        items[index].stackSort = sort
        Defaults[.customDockPinnedItems] = items
    }

    static func groupIcon(for icons: [NSImage]) -> NSImage {
        let size = NSSize(width: 256, height: 256)
        return NSImage(size: size, flipped: true) { rect in
            let background = NSBezierPath(roundedRect: rect.insetBy(dx: 14, dy: 14), xRadius: 56, yRadius: 56)
            NSColor(white: 0.55, alpha: 0.38).setFill()
            background.fill()
            NSColor(white: 1, alpha: 0.25).setStroke()
            background.lineWidth = 3
            background.stroke()
            let inset: CGFloat = 38
            let gap: CGFloat = 12
            let cell = (rect.width - inset * 2 - gap) / 2
            for (index, icon) in icons.prefix(4).enumerated() {
                let column = CGFloat(index % 2)
                let row = CGFloat(index / 2)
                let frame = NSRect(x: inset + column * (cell + gap), y: inset + row * (cell + gap), width: cell, height: cell)
                icon.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            return true
        }
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
