import Cocoa
import Defaults

@_silgen_name("CoreDockSendNotification")
private func CoreDockSendNotification(_ notification: CFString, _ unknown: Int32)

/// Builds the right-click menu for a dock icon.
final class CustomDockMenuBuilder: NSObject {
    private let store: CustomDockStore
    private var tile: DockTile?
    private var windows: [WindowInfo] = []

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
        case .folder, .file:
            add(menu, "Öffnen", "arrow.up.forward.app", #selector(openTile))
            add(menu, "Im Finder zeigen", "folder", #selector(revealTile))
            menu.addItem(.separator())
            add(menu, "Aus dem Dock entfernen", "minus.circle", #selector(unpinTile))
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

    private func addDockOptions(to menu: NSMenu) {
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
