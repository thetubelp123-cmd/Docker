import Cocoa
import Defaults

@_silgen_name("CoreDockSendNotification")
private func CoreDockSendNotification(_ notification: CFString, _ unknown: Int32)

/// Builds the right-click menu for a dock icon.
final class CustomDockMenuBuilder: NSObject {
    private let store: CustomDockStore
    private var tile: DockTile?
    private var windows: [WindowInfo] = []
    var onOpenStack: ((DockTile) -> Void)?

    init(store: CustomDockStore) {
        self.store = store
    }

    func menu(for tile: DockTile?) -> NSMenu {
        self.tile = tile
        let menu = NSMenu()
        menu.autoenablesItems = false

        guard let tile else {
            addDockOptions(to: menu)
            return menu
        }

        switch tile.kind {
        case .app:
            buildAppMenu(menu, tile: tile)
        case .folder:
            add(menu, "Als Stapel öffnen", "rectangle.stack", #selector(openStack))
            add(menu, "Im Finder öffnen", "arrow.up.forward.app", #selector(openTile))
            add(menu, "Im Finder zeigen", "folder", #selector(revealTile))
            menu.addItem(.separator())
            addStackModeMenu(to: menu, tile: tile)
            addStackSortMenu(to: menu, tile: tile)
            menu.addItem(.separator())
            add(menu, "Aus dem Dock entfernen", "minus.circle", #selector(unpinTile))
        case .file:
            add(menu, "Öffnen", "arrow.up.forward.app", #selector(openTile))
            add(menu, "Im Finder zeigen", "folder", #selector(revealTile))
            menu.addItem(.separator())
            add(menu, "Aus dem Dock entfernen", "minus.circle", #selector(unpinTile))
        case .group:
            add(menu, "Öffnen", "square.grid.2x2", #selector(openStack))
            add(menu, "Alle Apps starten", "play", #selector(launchAllMembers))
            add(menu, "Umbenennen …", "pencil", #selector(renameGroup))
            menu.addItem(.separator())
            addStackModeMenu(to: menu, tile: tile)
            menu.addItem(.separator())
            add(menu, "Gruppe auflösen", "square.split.2x2", #selector(dissolveGroup))
            add(menu, "Aus dem Dock entfernen", "minus.circle", #selector(unpinTile))
        case .widget:
            buildWidgetMenu(menu, tile: tile)
        case .trash:
            add(menu, "Öffnen", "trash", #selector(openTile))
            let empty = add(menu, "Papierkorb entleeren …", "trash.slash", #selector(emptyTrash))
            empty.isEnabled = store.trashIsFull
        }
        return menu
    }

    private func buildAppMenu(_ menu: NSMenu, tile: DockTile) {
        let isFinder = tile.bundleIdentifier == CustomDockStore.finderBundleID
        let app = tile.pid.flatMap { NSRunningApplication(processIdentifier: $0) }
        windows = tile.pid.map { WindowUtil.readCachedWindows(for: $0) }?.filter { !$0.isWindowlessApp } ?? []

        if tile.isPinned {
            if !isFinder { add(menu, "Aus dem Dock entfernen", "minus.circle", #selector(unpinTile)) }
        } else if tile.url != nil {
            add(menu, "Im Dock behalten", "pin", #selector(pinTile))
        }
        if tile.url != nil {
            add(menu, "Im Finder zeigen", "folder", #selector(revealTile))
        }
        if tile.url != nil, !isFinder {
            addGroupMenu(to: menu)
        }

        guard let app, tile.isRunning else {
            menu.addItem(.separator())
            add(menu, "Öffnen", "arrow.up.forward.app", #selector(openTile))
            return
        }

        menu.addItem(.separator())
        if app.isHidden {
            add(menu, "Einblenden", "eye", #selector(unhideApp))
        } else {
            add(menu, "Ausblenden", "eye.slash", #selector(hideApp))
        }
        let hasWindows = !windows.isEmpty
        add(menu, "Alle minimieren", "arrow.down.right.and.arrow.up.left", #selector(minimizeAll)).isEnabled = hasWindows && windows.contains { !$0.isMinimized }
        if windows.contains(where: \.isMinimized) {
            add(menu, "Alle wiederherstellen", "arrow.up.left.and.arrow.down.right", #selector(restoreAll))
        }
        add(menu, "Alle Fenster hierher holen", "rectangle.portrait.and.arrow.forward", #selector(bringAllHere)).isEnabled = hasWindows
        add(menu, "Exposé zeigen", "rectangle.3.group", #selector(showExpose)).isEnabled = hasWindows
        add(menu, "Neues Fenster", "plus.rectangle", #selector(newWindow))
        add(menu, "Alle Fenster schließen", "xmark.rectangle", #selector(closeAll)).isEnabled = hasWindows

        if hasWindows {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Fenster", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for (index, window) in windows.enumerated() {
                var title = window.windowName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if title.isEmpty { title = app.localizedName ?? tile.name }
                if window.isMinimized { title += " (minimiert)" }
                let item = NSMenuItem(title: title, action: #selector(focusWindow(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                item.indentationLevel = 1
                if window.isMinimized { item.image = NSImage(systemSymbolName: "minus.square", accessibilityDescription: nil) }
                menu.addItem(item)
            }
        }

        if !isFinder {
            menu.addItem(.separator())
            add(menu, "Neu starten", "arrow.clockwise", #selector(relaunchApp))
            add(menu, "Beenden", "power", #selector(quitApp))
            let force = add(menu, "Sofort beenden", "exclamationmark.octagon", #selector(forceQuitApp))
            force.isAlternate = true
            force.keyEquivalentModifierMask = [.option]
        } else {
            menu.addItem(.separator())
            add(menu, "Finder neu starten", "arrow.clockwise", #selector(relaunchApp))
        }
    }

    private func addGroupMenu(to menu: NSMenu) {
        let item = NSMenuItem(title: "Zu Gruppe hinzufügen", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for group in store.groups {
            let entry = NSMenuItem(title: group.name ?? "Gruppe", action: #selector(addToGroup(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = group.id
            submenu.addItem(entry)
        }
        if !submenu.items.isEmpty { submenu.addItem(.separator()) }
        let newGroup = NSMenuItem(title: "Neue Gruppe …", action: #selector(addToNewGroup), keyEquivalent: "")
        newGroup.target = self
        submenu.addItem(newGroup)
        item.submenu = submenu
        menu.addItem(item)
    }

    private func addStackModeMenu(to menu: NSMenu, tile: DockTile) {
        let current = tile.stackMode ?? (tile.kind == .group ? .grid : Defaults[.customDockStackMode])
        let item = NSMenuItem(title: "Anzeigen als", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for mode in StackDisplayMode.allCases {
            let entry = NSMenuItem(title: mode.title, action: #selector(setStackMode(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = mode.rawValue
            entry.image = NSImage(systemSymbolName: mode.symbol, accessibilityDescription: nil)
            entry.state = mode == current ? .on : .off
            submenu.addItem(entry)
        }
        item.submenu = submenu
        menu.addItem(item)
    }

    private func addStackSortMenu(to menu: NSMenu, tile: DockTile) {
        let current = tile.stackSort ?? Defaults[.customDockStackSort]
        let item = NSMenuItem(title: "Sortieren nach", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for sort in StackSortOrder.allCases {
            let entry = NSMenuItem(title: sort.title, action: #selector(setStackSort(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = sort.rawValue
            entry.state = sort == current ? .on : .off
            submenu.addItem(entry)
        }
        item.submenu = submenu
        menu.addItem(item)
    }

    private func buildWidgetMenu(_ menu: NSMenu, tile: DockTile) {
        add(menu, "Öffnen", "arrow.up.forward.app", #selector(openStack))
        if tile.widgets.contains(.clock) {
            let style = NSMenuItem(title: "Uhr", action: nil, keyEquivalent: "")
            style.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
            let submenu = NSMenu()
            for clockStyle in DockClockStyle.allCases {
                let entry = NSMenuItem(title: clockStyle.title, action: #selector(setClockStyle(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = clockStyle.rawValue
                entry.state = Defaults[.customDockClockStyle] == clockStyle ? .on : .off
                submenu.addItem(entry)
            }
            style.submenu = submenu
            menu.addItem(style)
        }
        if tile.widgets.contains(.weather) {
            add(menu, "Wetter aktualisieren", "arrow.clockwise", #selector(refreshWeather))
            add(menu, "Wetter-Ort ändern …", "location", #selector(openSettings))
        }
        menu.addItem(.separator())

        let missing = DockWidgetKind.allCases.filter { !tile.widgets.contains($0) }
        if !missing.isEmpty {
            let addItem = NSMenuItem(title: "Zum Stapel hinzufügen", action: nil, keyEquivalent: "")
            addItem.image = NSImage(systemSymbolName: "plus.square.on.square", accessibilityDescription: nil)
            let submenu = NSMenu()
            for kind in missing {
                let entry = NSMenuItem(title: kind.title, action: #selector(addWidgetToStack(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = kind.rawValue
                entry.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)
                submenu.addItem(entry)
            }
            addItem.submenu = submenu
            menu.addItem(addItem)
        }
        if tile.isWidgetStack {
            let removeItem = NSMenuItem(title: "Aus Stapel nehmen", action: nil, keyEquivalent: "")
            removeItem.image = NSImage(systemSymbolName: "square.stack.3d.down.right", accessibilityDescription: nil)
            let submenu = NSMenu()
            for kind in tile.widgets {
                let entry = NSMenuItem(title: kind.title, action: #selector(removeWidgetFromStack(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = kind.rawValue
                entry.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)
                submenu.addItem(entry)
            }
            removeItem.submenu = submenu
            menu.addItem(removeItem)
            add(menu, "Stapel auflösen", "square.split.2x2", #selector(dissolveWidgetStack))
        }
        menu.addItem(.separator())
        add(menu, "Aus dem Dock entfernen", "minus.circle", #selector(unpinTile))
    }

    private func addWidgetMenu(to menu: NSMenu) {
        let item = NSMenuItem(title: "Widget hinzufügen", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "plus.square", accessibilityDescription: nil)
        let submenu = NSMenu()
        for kind in DockWidgetKind.allCases {
            let entry = NSMenuItem(title: kind.title, action: #selector(addWidget(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = kind.rawValue
            entry.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)
            submenu.addItem(entry)
        }
        item.submenu = submenu
        menu.addItem(item)
    }

    private func addDockOptions(to menu: NSMenu) {
        addWidgetMenu(to: menu)
        menu.addItem(.separator())
        let magnification = add(menu, "Vergrößerung", nil, #selector(toggleMagnification))
        magnification.state = Defaults[.customDockMagnification] ? .on : .off
        let autoHide = add(menu, "Automatisch ausblenden", nil, #selector(toggleAutoHide))
        autoHide.state = Defaults[.customDockAutoHide] ? .on : .off
        menu.addItem(.separator())
        add(menu, "Dock-Einstellungen …", "gearshape", #selector(openSettings))
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ symbol: String?, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        menu.addItem(item)
        return item
    }

    private var runningApp: NSRunningApplication? {
        tile?.pid.flatMap { NSRunningApplication(processIdentifier: $0) }
    }

    // MARK: - Actions

    @objc private func openTile() { if let tile { store.open(tile) } }
    @objc private func revealTile() { if let tile { store.revealInFinder(tile) } }
    @objc private func pinTile() { if let tile { store.pin(tile) } }
    @objc private func unpinTile() { if let tile { store.unpin(tile) } }
    @objc private func hideApp() { runningApp?.hide() }
    @objc private func unhideApp() { runningApp?.unhide() }
    @objc private func quitApp() { runningApp?.terminate() }
    @objc private func forceQuitApp() { runningApp?.forceTerminate() }

    @objc private func addWidget(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = DockWidgetKind(rawValue: raw) else { return }
        store.addWidget(kind)
    }

    @objc private func addWidgetToStack(_ sender: NSMenuItem) {
        guard let tile, let raw = sender.representedObject as? String, let kind = DockWidgetKind(rawValue: raw) else { return }
        store.addWidget(kind, toStack: tile.id)
    }

    @objc private func removeWidgetFromStack(_ sender: NSMenuItem) {
        guard let tile, let raw = sender.representedObject as? String, let kind = DockWidgetKind(rawValue: raw) else { return }
        store.removeWidget(kind, fromStack: tile.id)
    }

    @objc private func dissolveWidgetStack() {
        guard let tile else { return }
        store.dissolveWidgetStack(tile.id)
    }

    @objc private func setClockStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = DockClockStyle(rawValue: raw) else { return }
        Defaults[.customDockClockStyle] = style
    }

    @objc private func refreshWeather() {
        DockWeatherModel.shared.refresh()
    }

    @objc private func openStack() {
        guard let tile else { return }
        let open = onOpenStack
        DispatchQueue.main.async { open?(tile) }
    }

    @objc private func launchAllMembers() {
        tile?.members.forEach { store.openApp(at: $0.url) }
    }

    @objc private func renameGroup() {
        guard let tile, let name = askForGroupName(title: "Gruppe umbenennen", current: tile.name) else { return }
        store.renameGroup(tile.id, to: name)
    }

    @objc private func dissolveGroup() {
        guard let tile else { return }
        store.dissolveGroup(tile.id)
    }

    @objc private func addToGroup(_ sender: NSMenuItem) {
        guard let tile, let groupID = sender.representedObject as? String else { return }
        store.add(tile, toGroup: groupID)
    }

    @objc private func addToNewGroup() {
        guard let tile, let name = askForGroupName(title: "Neue Gruppe", current: "Gruppe") else { return }
        store.createGroup(with: tile, name: name)
    }

    @objc private func setStackMode(_ sender: NSMenuItem) {
        guard let tile, let raw = sender.representedObject as? String, let mode = StackDisplayMode(rawValue: raw) else { return }
        store.setStackMode(mode, for: tile.id)
    }

    @objc private func setStackSort(_ sender: NSMenuItem) {
        guard let tile, let raw = sender.representedObject as? String, let sort = StackSortOrder(rawValue: raw) else { return }
        store.setStackSort(sort, for: tile.id)
    }

    private func askForGroupName(title: String, current: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Name der Gruppe:"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Abbrechen")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = current
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    @objc private func emptyTrash() {
        let alert = NSAlert()
        alert.messageText = "Papierkorb wirklich entleeren?"
        alert.informativeText = "Die Objekte im Papierkorb werden endgültig gelöscht."
        alert.addButton(withTitle: "Entleeren")
        alert.addButton(withTitle: "Abbrechen")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            store.emptyTrash()
        }
    }

    @objc private func minimizeAll() {
        WindowUtil.minimizeWindowsAsync(windows)
    }

    @objc private func restoreAll() {
        runningApp?.unhide()
        for window in windows where window.isMinimized {
            var copy = window
            _ = copy.toggleMinimize()
        }
        runningApp?.activate(options: [.activateAllWindows])
    }

    @objc private func bringAllHere() {
        guard let app = runningApp else { return }
        if !WindowUtil.moveAppWindowsToCurrentManagedSpace(for: app) {
            app.unhide()
            app.activate(options: [.activateAllWindows])
        }
    }

    @objc private func showExpose() {
        guard let app = runningApp else { return }
        app.unhide()
        app.activate(options: [.activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            CoreDockSendNotification("com.apple.expose.front.awake" as CFString, 0)
        }
    }

    @objc private func newWindow() {
        guard let app = runningApp else { return }
        WindowUtil.activateAndOpenNewWindow(app: app)
    }

    @objc private func closeAll() {
        for window in windows {
            _ = window.close()
        }
    }

    @objc private func focusWindow(_ sender: NSMenuItem) {
        guard windows.indices.contains(sender.tag) else { return }
        var window = windows[sender.tag]
        runningApp?.unhide()
        if window.isMinimized {
            _ = window.toggleMinimize()
        }
        window.bringToFront()
    }

    @objc private func relaunchApp() {
        guard let app = runningApp, let url = app.bundleURL else { return }
        app.terminate()
        let deadline = Date().addingTimeInterval(15)
        func relaunchWhenGone() {
            if app.isTerminated {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
            } else if Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { relaunchWhenGone() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { relaunchWhenGone() }
    }

    @objc private func toggleMagnification() {
        Defaults[.customDockMagnification].toggle()
    }

    @objc private func toggleAutoHide() {
        Defaults[.customDockAutoHide].toggle()
    }

    @objc private func openSettings() {
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow(nil)
    }
}
