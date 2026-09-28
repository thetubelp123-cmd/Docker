import Cocoa
import Defaults

/// Connects the DockerDoor dock to DockDoor's window preview panel.
enum CustomDockPreviews {
    private static var refreshToken = UUID()
    /// Which side of the icon previews open on (DockDoor treats .cli as "above").
    static var placement: CustomDockPosition = .bottom

    /// DockDoor position used for placing the preview next to a DockerDoor icon.
    static var cliPlacement: DockPosition? {
        switch placement {
        case .bottom: nil
        case .left: .left
        case .right: .right
        }
    }

    static var coordinator: SharedPreviewWindowCoordinator? {
        SharedPreviewWindowCoordinator.activeInstance
    }

    static var isMouseInPreview: Bool {
        guard let coordinator, coordinator.isVisible else { return false }
        return coordinator.mouseIsWithinPreviewWindow || coordinator.frame.contains(NSEvent.mouseLocation)
    }

    static var isVisible: Bool {
        coordinator?.isVisible ?? false
    }

    static func hide() {
        refreshToken = UUID()
        coordinator?.hideWindow()
    }

    /// - Parameter anchor: the hovered icon in screen coordinates (bottom-left origin).
    static func show(for tile: DockTile, anchor: CGRect, screen: NSScreen, isStillHovered: @escaping () -> Bool) {
        guard Defaults[.customDockShowPreviews], Defaults[.enableDockPreviews],
              let coordinator,
              !coordinator.windowSwitcherCoordinator.windowSwitcherActive
        else { return }

        guard tile.kind == .app, let pid = tile.pid, let app = NSRunningApplication(processIdentifier: pid) else {
            hide()
            return
        }
        if WindowUtil.isAppFiltered(app) {
            hide()
            return
        }

        var apps = [app]
        if Defaults[.groupAppInstancesInDock], let bundleID = app.bundleIdentifier, !bundleID.isEmpty {
            let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if !instances.isEmpty { apps = instances }
        }

        let quartzMouse = DockObserver.getMousePosition()
        var windows = apps.flatMap { WindowUtil.readCachedWindows(for: $0.processIdentifier) }
        if Defaults[.ignoreAppsWithSingleWindow], windows.count <= 1 {
            windows = []
        }
        windows = filter(windows, quartzMouse: quartzMouse)
        if windows.isEmpty, Defaults[.showWindowlessAppsInDockPreview] {
            windows = [WindowInfo.windowlessEntry(for: app)]
        }

        // The preview sits right above the icon. DockDoor adds its "buffer from dock"
        // on top of the anchor, so the anchor is stretched to cancel that out.
        let lift = max(0, -Defaults[.bufferFromDock]) + 6
        let anchorFrame = switch placement {
        case .bottom: CGRect(x: anchor.minX, y: anchor.minY, width: anchor.width, height: anchor.height + lift)
        case .left: CGRect(x: anchor.minX, y: anchor.minY, width: anchor.width + lift, height: anchor.height)
        case .right: CGRect(x: anchor.minX - lift, y: anchor.minY, width: anchor.width + lift, height: anchor.height)
        }

        let token = UUID()
        refreshToken = token
        let appName = app.localizedName ?? tile.name

        func present(_ windows: [WindowInfo], immediately: Bool) {
            coordinator.showWindow(
                appName: appName,
                windows: windows,
                mouseLocation: NSEvent.mouseLocation,
                mouseScreen: screen,
                dockItemElement: nil,
                overrideDelay: immediately,
                onWindowTap: { hide() },
                bundleIdentifier: app.bundleIdentifier,
                bypassDockMouseValidation: true,
                dockPositionOverride: .cli,
                dockItemFrameOverride: anchorFrame
            )
        }

        if !windows.isEmpty {
            present(windows, immediately: false)
        }

        Task.detached {
            var fresh: [WindowInfo] = []
            for instance in apps {
                if let found = try? await WindowUtil.getActiveWindows(of: instance) {
                    fresh.append(contentsOf: found)
                }
            }
            fresh = filter(fresh, quartzMouse: quartzMouse)
            let freshWindows = fresh
            await MainActor.run {
                guard refreshToken == token, isStillHovered() else { return }
                if coordinator.isVisible, coordinator.currentlyDisplayedPID == pid {
                    coordinator.mergeWindowsIfNeeded(pid, windows: freshWindows, dockPosition: .cli, bestGuessMonitor: screen)
                } else if !freshWindows.isEmpty {
                    present(freshWindows, immediately: false)
                }
            }
        }
    }

    private static func filter(_ windows: [WindowInfo], quartzMouse: CGPoint) -> [WindowInfo] {
        var result = windows
        if Defaults[.showWindowsFromCurrentSpaceOnly] {
            result = WindowUtil.filterWindowsByCurrentSpace(result)
        }
        if Defaults[.showWindowsFromCurrentMonitorOnly] {
            result = WindowUtil.filterWindowsByCurrentMonitor(result, mouseLocation: quartzMouse)
        }
        if !Defaults[.includeHiddenWindowsInDockPreview] {
            result = result.filter { !$0.isHidden && !$0.isMinimized }
        }
        return result
    }
}
