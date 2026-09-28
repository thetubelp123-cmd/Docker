import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

/// Settings groups for profiles, AppSense and per-display docks.
struct CustomDockProfilesSettings: View {
    @Default(.customDockProfiles) private var profiles
    @Default(.customDockActiveProfile) private var activeID
    @Default(.customDockShowControlTile) private var showControlTile
    @Default(.customDockAppSenseEnabled) private var appSense
    @Default(.customDockDisplayMode) private var displayMode
    @Default(.customDockDisplayProfiles) private var displayProfiles
    @State private var screenCount = NSScreen.screens.count

    var body: some View {
        SettingsGroup(header: "Profile") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ein Profil speichert Inhalt und Aussehen des Docks. Änderungen gehören immer zum aktiven Profil.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(profiles) { profile in
                    ProfileRow(profile: profile, isActive: profile.id == activeID, canDelete: profiles.count > 1)
                    if profile.id != profiles.last?.id { Divider() }
                }

                HStack {
                    Button {
                        ProfileManager.create(name: "Profil \(profiles.count + 1)", copyCurrent: true)
                    } label: {
                        Label("Neues Profil (Kopie)", systemImage: "plus.square.on.square")
                    }
                    Button {
                        ProfileManager.create(name: "Profil \(profiles.count + 1)", copyCurrent: false)
                    } label: {
                        Label("Neues leeres Profil", systemImage: "plus.square")
                    }
                }

                Divider()
                Toggle("Profil-Schalter im Dock zeigen", isOn: $showControlTile)
                    .settingsSearchTarget("customDock.controlTile")
                Text("Klick öffnet das Kontrollzentrum, Scrollen wechselt das Profil.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("AppSense: Profil automatisch nach aktiver App wechseln", isOn: $appSense)
                    .settingsSearchTarget("customDock.appSense")
                Text("Kommt eine App nach vorne, die einem Profil zugeordnet ist, wechselt das Dock dorthin. Danach geht es zurück zum vorherigen Profil.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        SettingsGroup(header: "Bildschirme") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Dock anzeigen auf", selection: $displayMode) {
                    ForEach(CustomDockDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .settingsSearchTarget("customDock.displays")
                .pickerStyle(.segmented)

                switch displayMode {
                case .main:
                    Text("Ein Dock auf dem Hauptbildschirm.")
                        .font(.caption).foregroundStyle(.secondary)
                case .follow:
                    Text("Ein Dock, das auf den Bildschirm wechselt, an dessen unteren Rand du den Zeiger bewegst.")
                        .font(.caption).foregroundStyle(.secondary)
                case .all:
                    Text("Jeder Bildschirm bekommt ein eigenes Dock. Wähle pro Bildschirm, welches Profil es zeigt. Das Aussehen (Größe, Material …) gilt für alle Docks.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        let id = screen.uniqueIdentifier()
                        Picker(screen.displayName, selection: Binding(
                            get: { displayProfiles[id] ?? "" },
                            set: { newValue in
                                var map = displayProfiles
                                map[id] = newValue.isEmpty ? nil : newValue
                                displayProfiles = map
                            }
                        )) {
                            Text("Aktives Profil").tag("")
                            ForEach(profiles) { profile in
                                Label(profile.name, systemImage: profile.symbol).tag(profile.id)
                            }
                        }
                    }
                    if screenCount < 2 {
                        Text("Gerade ist nur ein Bildschirm angeschlossen.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screenCount = NSScreen.screens.count
        }
    }
}

private struct ProfileRow: View {
    let profile: DockProfile
    let isActive: Bool
    let canDelete: Bool
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(DockProfile.symbols, id: \.self) { symbol in
                        Button {
                            ProfileManager.update(profile.id) { $0.symbol = symbol }
                        } label: {
                            Label(symbol, systemImage: symbol)
                        }
                    }
                } label: {
                    Image(systemName: profile.symbol)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Symbol wählen")

                TextField("Name", text: Binding(
                    get: { profile.name },
                    set: { newValue in ProfileManager.update(profile.id) { $0.name = newValue } }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)

                if isActive {
                    Text("Aktiv")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                } else {
                    Button("Aktivieren") { ProfileManager.activate(profile.id) }
                }
                Spacer()
                Button {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(!canDelete)
                .help("Profil löschen")
            }

            HStack(alignment: .top, spacing: 6) {
                Text("AppSense:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if profile.triggerApps.isEmpty {
                    Text("keine Apps")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(profile.triggerApps, id: \.self) { bundleID in
                            HStack(spacing: 4) {
                                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                        .resizable()
                                        .frame(width: 14, height: 14)
                                }
                                Text(ProfileManager.appName(for: bundleID))
                                    .font(.caption)
                                Button {
                                    ProfileManager.update(profile.id) { $0.triggerApps.removeAll { $0 == bundleID } }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                Spacer()
                Button("App hinzufügen …", action: addApps)
                    .controlSize(.small)
            }
        }
        .alert("Profil „\(profile.name)“ löschen?", isPresented: $confirmDelete) {
            Button("Löschen", role: .destructive) { ProfileManager.delete(profile.id) }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Inhalt und Einstellungen dieses Profils gehen verloren.")
        }
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.title = "Apps für „\(profile.name)“ wählen"
        panel.prompt = "Hinzufügen"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        guard !ids.isEmpty else { return }
        // An app can only belong to one profile.
        for other in ProfileManager.profiles where other.id != profile.id {
            ProfileManager.update(other.id) { $0.triggerApps.removeAll { ids.contains($0) } }
        }
        ProfileManager.update(profile.id) { entry in
            for id in ids where !entry.triggerApps.contains(id) {
                entry.triggerApps.append(id)
            }
        }
    }
}

/// Settings groups for letter navigation, badges and backups.
struct CustomDockExtrasSettings: View {
    @Default(.customDockLetterShortcut) private var shortcut
    @Default(.customDockShowBadges) private var showBadges
    @Default(.customDockAutoBackup) private var autoBackup
    @Default(.customDockLastAutoBackup) private var lastAutoBackup
    @State private var pendingRestore: URL?
    @State private var pendingInfo: DockerDoorBackup.BackupInfo?
    @State private var message: String?

    var body: some View {
        SettingsGroup(header: "Tastatur und Badges") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Buchstaben-Navigation", selection: $shortcut) {
                    ForEach(DockLetterShortcut.allCases, id: \.self) { item in
                        Text(item.title).tag(item)
                    }
                }
                .settingsSearchTarget("customDock.letterNav")
                Text("Kürzel drücken, dann Anfangsbuchstaben tippen: Das Dock springt zur passenden App. ←/→ oder Tab wechseln, ↩ öffnet, ⎋ bricht ab. Mehrmals denselben Buchstaben tippen blättert durch alle Treffer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Benachrichtigungs-Badges anzeigen", isOn: $showBadges)
                    .settingsSearchTarget("customDock.badges")
                Text("Zeigt die roten Zahlen der Apps (z. B. ungelesene Mails) an den Symbolen. Bei Gruppen werden sie zusammengezählt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        SettingsGroup(header: "Sichern und Wiederherstellen") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Eine Sicherung enthält alle Profile, den Dock-Inhalt, Widgets und das Aussehen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button {
                        exportBackup()
                    } label: {
                        Label("Sichern …", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        chooseRestore()
                    } label: {
                        Label("Wiederherstellen …", systemImage: "square.and.arrow.down")
                    }
                }
                Toggle("Täglich automatisch sichern (die letzten 10 bleiben erhalten)", isOn: $autoBackup)
                    .settingsSearchTarget("customDock.backup")
                HStack {
                    Text(lastAutoBackup > 0
                        ? "Letzte automatische Sicherung: \(Date(timeIntervalSince1970: lastAutoBackup).formatted(date: .abbreviated, time: .shortened))"
                        : "Noch keine automatische Sicherung.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Sicherungsordner öffnen") {
                        try? FileManager.default.createDirectory(at: DockerDoorBackup.backupsFolder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(DockerDoorBackup.backupsFolder)
                    }
                    .controlSize(.small)
                }
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .alert("Sicherung wiederherstellen?", isPresented: Binding(
            get: { pendingRestore != nil },
            set: { if !$0 { pendingRestore = nil } }
        )) {
            Button("Wiederherstellen und neu starten", role: .destructive) { performRestore() }
            Button("Abbrechen", role: .cancel) { pendingRestore = nil }
        } message: {
            Text(restoreDescription)
        }
    }

    private var restoreDescription: String {
        guard let info = pendingInfo else { return "Die aktuellen Dock-Einstellungen werden ersetzt." }
        var text = "Die aktuellen Dock-Einstellungen werden ersetzt"
        if let created = info.created {
            text += " durch den Stand vom \(created.formatted(date: .long, time: .shortened))"
        }
        text += " (Docker \(info.appVersion))."
        if !info.profileNames.isEmpty {
            text += " Profile: \(info.profileNames.joined(separator: ", "))."
        }
        return text + " Vorher wird automatisch eine Sicherung des jetzigen Stands angelegt. Docker startet danach neu."
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.title = "Docker sichern"
        panel.nameFieldStringValue = DockerDoorBackup.suggestedFileName()
        panel.allowedContentTypes = [DockerDoorBackup.contentType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DockerDoorBackup.export(to: url)
            message = "Gesichert: \(url.lastPathComponent)"
        } catch {
            message = "Sichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func chooseRestore() {
        let panel = NSOpenPanel()
        panel.title = "Docker-Sicherung wählen"
        panel.allowedContentTypes = [DockerDoorBackup.contentType, .propertyList]
        panel.allowsMultipleSelection = false
        panel.directoryURL = DockerDoorBackup.backupsFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            pendingInfo = try DockerDoorBackup.inspect(url)
            pendingRestore = url
        } catch {
            message = error.localizedDescription
        }
    }

    private func performRestore() {
        guard let url = pendingRestore else { return }
        pendingRestore = nil
        do {
            try DockerDoorBackup.restore(from: url)
            (NSApp.delegate as? AppDelegate)?.restartApp()
        } catch {
            message = "Wiederherstellen fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
