import Defaults
import SwiftUI

struct CustomDockSettingsView: View {
    @Default(.customDockEnabled) private var enabled
    @Default(.customDockHideSystemDock) private var hideSystemDock
    @Default(.customDockIconSize) private var iconSize
    @Default(.customDockIndicatorStyle) private var indicatorStyle
    @Default(.customDockShowTrash) private var showTrash
    @Default(.customDockShowAppNames) private var showAppNames
    @State private var showReimportConfirmation = false

    var body: some View {
        BaseSettingsView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsGroup {
                    SettingsIllustratedToggle(isOn: $enabled, title: "Eigenes Dock verwenden") {
                        Text("DockerDoor zeigt ein eigenes Dock am unteren Bildschirmrand.")
                    }
                    .onChange(of: enabled) { _ in applyChanges() }
                }

                if enabled {
                    SettingsGroup(header: "macOS-Dock") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("macOS-Dock ausblenden", isOn: $hideSystemDock)
                                .onChange(of: hideSystemDock) { _ in applyChanges() }
                            Text("Beim Beenden von DockerDoor wird das macOS-Dock mit deinen alten Einstellungen wiederhergestellt.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SettingsGroup(header: "Darstellung") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Symbolgröße")
                                Slider(value: $iconSize, in: 24 ... 96, step: 1)
                                Text("\(Int(iconSize)) pt")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 48, alignment: .trailing)
                            }
                            Picker("Laufende Apps markieren", selection: $indicatorStyle) {
                                ForEach(CustomDockIndicatorStyle.allCases, id: \.self) { style in
                                    Text(style.title).tag(style)
                                }
                            }
                            .pickerStyle(.segmented)
                            Toggle("Namen beim Überfahren anzeigen", isOn: $showAppNames)
                            Toggle("Papierkorb anzeigen", isOn: $showTrash)
                        }
                    }

                    SettingsGroup(header: "Inhalt") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Apps behältst du per Rechtsklick › „Im Dock behalten“. Apps, Ordner und Dateien lassen sich auch aus dem Finder aufs Dock ziehen.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Apps und Ordner aus dem macOS-Dock neu übernehmen …") {
                                showReimportConfirmation = true
                            }
                        }
                    }
                }
            }
        }
        .alert("Dock neu übernehmen?", isPresented: $showReimportConfirmation) {
            Button("Übernehmen", role: .destructive) {
                CustomDockStore.reimportFromSystemDock()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die angehefteten Apps und Ordner in DockerDoor werden durch die aus dem macOS-Dock ersetzt.")
        }
    }

    private func applyChanges() {
        (NSApp.delegate as? AppDelegate)?.updateCustomDock()
    }
}
