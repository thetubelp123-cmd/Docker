# Docker

[Deutsch](README.md) · **English**

**Docker replaces the macOS Dock with a dock of its own that you can shape however you like.** It shows apps, folders, widgets and minimized windows, can sit at the bottom, left or right edge of the screen, and adapts through profiles to whatever you're working on. It also brings window previews on hover and a fast window switcher.

Docker is a personal macOS app (macOS 13 or later) that runs quietly from an icon in the menu bar.

## Based on DockDoor

Docker is built on the open-source project **[DockDoor](https://github.com/ejbills/DockDoor)** by Ethan Bills (ejbills) and the DockDoor contributors. Features that come from DockDoor include:

- **Window previews** when hovering over an app icon, with actions such as close, minimize or full screen
- **Window switcher** via Alt+Tab with previews of every window
- **Cmd+Tab enhancement** with window selection
- Filters, gestures, keyboard shortcuts and many appearance options

Like DockDoor, Docker is licensed under the **GNU GPL v3** (see [LICENSE](LICENSE)). Docker is not an official DockDoor product and is not affiliated with "DockDoor Pro" or with Docker, Inc.

## New in Docker

### Custom dock
- Fully replaces the macOS Dock. The original Dock is hidden and restored with your previous settings when Docker quits.
- Imports your apps and folders from the macOS Dock on first launch.
- **Bottom, left or right position**, as a floating dock or as an edge-to-edge bar across the whole screen.
- Magnification on hover, adjustable icon size, auto-hide.
- Materials: Liquid Glass, frosted glass, solid or clear, with tint, border and light or dark appearance.
- Running-app indicators as dots or cards, names on hover, launch animation.

### Content
- Pin, rearrange and remove apps, folders and files with drag and drop. Drop files onto apps or into the Trash.
- **Folders as stacks** in fan, grid or list view, sorted by name, date or kind.
- **App groups**: bundle several apps into one icon and open or launch them together.
- **Minimized windows** appear as their own icons before the Trash. One click brings them back.
- **Recent apps**: up to three recently quit apps appear after the running apps.
- **Spacers and dividers** to organize the dock.
- Context menus for apps, folders, groups and the Trash, for example with all of an app's windows, Minimize, Exposé and Quit.

### Widgets
- **Clock** (digital or analog), **Weather** (search a place or use your location), **Calendar**, **Battery** and **Now Playing**.
- Now Playing with lyrics (via LRCLIB) and volume control by scrolling.
- **Widget stacks** that can rotate automatically and switch to Now Playing when music starts.
- Each widget opens a detailed popover when clicked.

### Profiles and displays
- **Profiles** with their own content and look, switchable from a control center in the dock.
- **AppSense**: switches profiles automatically to match the active app.
- **Multiple displays**: show the dock on the main display only, on all displays, or following the mouse pointer.

### Convenience
- **Notification badges** (for example unread messages) on app icons.
- **Letter navigation**: press a keyboard shortcut (⌥⌘D by default) and jump to dock items by their first letter.
- **Backup and restore** of all dock settings and profiles, with a daily automatic backup.
- **Settings search** that covers every dock option.
- Low CPU use while idle, with a log file and hang detection.

## Installation

1. Install Xcode (needed for the build).
2. In the project folder, double-click **"Docker installieren.command"**.
   The script builds the app, installs it to Applications, launches it, and saves a ZIP and a DMG of the version in the "Versionen" folder.
3. On first launch, grant **Accessibility** and **Screen Recording** access (System Settings → Privacy & Security).

## License

GNU General Public License v3.0. See [LICENSE](LICENSE).
Original code © Ethan Bills and the DockDoor contributors. Extensions © Leonard Jäger.
