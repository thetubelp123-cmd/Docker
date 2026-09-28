import Defaults
import SwiftUI

struct CustomDockSettingsView: View {
    @Default(.customDockEnabled) private var enabled
    @Default(.customDockHideSystemDock) private var hideSystemDock
    @Default(.customDockIconSize) private var iconSize
    @Default(.customDockIndicatorStyle) private var indicatorStyle
    @Default(.customDockShowTrash) private var showTrash
    @Default(.customDockShowAppNames) private var showAppNames
    @Default(.customDockMagnification) private var magnification
    @Default(.customDockMagnifiedSize) private var magnifiedSize
    @Default(.customDockLayoutMode) private var layoutMode
    @Default(.customDockMaterial) private var material
    @Default(.customDockTintOpacity) private var tintOpacity
    @Default(.customDockShowBorder) private var showBorder
    @Default(.customDockAppearance) private var appearance
    @Default(.customDockAutoHide) private var autoHide
    @Default(.customDockShowPreviews) private var showPreviews
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

                    SettingsGroup(header: "Größe und Layout") {
                        VStack(alignment: .leading, spacing: 12) {
                            sliderRow("Symbolgröße", value: $iconSize, range: 24 ... 96)
                            Toggle("Vergrößerung beim Überfahren", isOn: $magnification)
                            if magnification {
                                sliderRow("Vergrößert", value: $magnifiedSize, range: max(iconSize, 32) ... 192)
                            }
                            Picker("Layout", selection: $layoutMode) {
                                ForEach(CustomDockLayoutMode.allCases, id: \.self) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            Text("Schwebend: mittig mit Abstand zum Rand. Randlos: eine Leiste über die ganze Bildschirmbreite, Ordner und Papierkorb rechts.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SettingsGroup(header: "Material") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Material", selection: $material) {
                                ForEach(CustomDockMaterial.allCases, id: \.self) { item in
                                    Text(item.title).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)
                            if material != .solid {
                                HStack {
                                    Text("Tönung")
                                    Slider(value: $tintOpacity, in: 0 ... 1)
                                    Text("\(Int(tintOpacity * 100)) %")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                        .frame(width: 48, alignment: .trailing)
                                }
                            }
                            Toggle("Rahmen anzeigen", isOn: $showBorder)
                            Picker("Erscheinungsbild", selection: $appearance) {
                                ForEach(CustomDockAppearance.allCases, id: \.self) { item in
                                    Text(item.title).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    SettingsGroup(header: "Anzeige") {
                        VStack(alignment: .leading, spacing: 12) {
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

                    SettingsGroup(header: "Verhalten") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Automatisch ausblenden", isOn: $autoHide)
                            Text("Das Dock gleitet nach unten weg und erscheint wieder, sobald der Zeiger den unteren Bildschirmrand berührt.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Toggle("Fenstervorschauen beim Überfahren", isOn: $showPreviews)
                            Text("Nutzt die Vorschau-Einstellungen aus „Dock Previews“ (Größe, Verzögerung, Aktionen, Vollbild beim Überfahren).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range, step: 1)
            Text("\(Int(value.wrappedValue)) pt")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }

    private func applyChanges() {
        (NSApp.delegate as? AppDelegate)?.updateCustomDock()
    }
}
