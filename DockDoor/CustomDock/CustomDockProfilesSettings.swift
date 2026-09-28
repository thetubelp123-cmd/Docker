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
                Text("Klick öffnet das Kontrollzentrum, Scrollen wechselt das Profil.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("AppSense: Profil automatisch nach aktiver App wechseln", isOn: $appSense)
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
