import Defaults
import SwiftUI

struct CustomDockSettingsView: View {
    @Default(.customDockEnabled) private var enabled
    @Default(.customDockHideSystemDock) private var hideSystemDock
    @Default(.customDockIconSize) private var iconSize
    @Default(.customDockIndicatorStyle) private var indicatorStyle
    @Default(.customDockShowTrash) private var showTrash
    @Default(.customDockShowAppNames) private var showAppNames
    @Default(.customDockShowMinimized) private var showMinimized
    @Default(.customDockShowRecents) private var showRecents
    @Default(.customDockMagnification) private var magnification
    @Default(.customDockMagnifiedSize) private var magnifiedSize
    @Default(.customDockLayoutMode) private var layoutMode
    @Default(.customDockPosition) private var position
    @Default(.customDockMaterial) private var material
    @Default(.customDockTintOpacity) private var tintOpacity
    @Default(.customDockShowBorder) private var showBorder
    @Default(.customDockAppearance) private var appearance
    @Default(.customDockAutoHide) private var autoHide
    @Default(.customDockShowPreviews) private var showPreviews
    @Default(.customDockStackMode) private var stackMode
    @Default(.customDockStackSort) private var stackSort
    @Default(.customDockPinnedItems) private var pinnedItems
    @Default(.customDockClockStyle) private var clockStyle
    @Default(.customDockTemperatureUnit) private var temperatureUnit
    @Default(.customDockWeatherPlace) private var weatherPlace
    @Default(.customDockWeatherHasLocation) private var weatherHasLocation
    @Default(.customDockVolumeScroll) private var volumeScroll
    @Default(.customDockLoadLyrics) private var loadLyrics
    @Default(.customDockWidgetAutoRotate) private var autoRotate
    @Default(.customDockWidgetRotateSeconds) private var rotateSeconds
    @Default(.customDockWidgetSmartSwitch) private var smartSwitch
    @ObservedObject private var weather = DockWeatherModel.shared
    @State private var placeQuery = ""
    @State private var placeResults: [WeatherPlace] = []
    @State private var isSearchingPlace = false
    @State private var showReimportConfirmation = false

    var body: some View {
        BaseSettingsView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsGroup {
                    SettingsIllustratedToggle(isOn: $enabled, title: "Eigenes Dock verwenden") {
                        Text("Docker zeigt ein eigenes Dock am Bildschirmrand – unten, links oder rechts.")
                    }
                    .settingsSearchTarget("customDock.enabled")
                    .onChange(of: enabled) { _ in applyChanges() }
                }

                if enabled {
                    CustomDockProfilesSettings()

                    SettingsGroup(header: "macOS-Dock") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("macOS-Dock ausblenden", isOn: $hideSystemDock)
                                .settingsSearchTarget("customDock.hideSystemDock")
                                .onChange(of: hideSystemDock) { _ in applyChanges() }
                            Text("Beim Beenden von Docker wird das macOS-Dock mit deinen alten Einstellungen wiederhergestellt.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SettingsGroup(header: "Größe und Layout") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Position", selection: $position) {
                                ForEach(CustomDockPosition.allCases, id: \.self) { item in
                                    Text(item.title).tag(item)
                                }
                            }
                            .settingsSearchTarget("customDock.position")
                            .pickerStyle(.segmented)
                            sliderRow("Symbolgröße", value: $iconSize, range: 24 ... 96)
                                .settingsSearchTarget("customDock.iconSize")
                            Toggle("Vergrößerung beim Überfahren", isOn: $magnification)
                                .settingsSearchTarget("customDock.magnification")
                            if magnification {
                                sliderRow("Vergrößert", value: $magnifiedSize, range: max(iconSize, 32) ... 192)
                            }
                            Picker("Layout", selection: $layoutMode) {
                                ForEach(CustomDockLayoutMode.allCases, id: \.self) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .settingsSearchTarget("customDock.layoutMode")
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
                            .settingsSearchTarget("customDock.material")
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
                                .settingsSearchTarget("customDock.border")
                            Picker("Erscheinungsbild", selection: $appearance) {
                                ForEach(CustomDockAppearance.allCases, id: \.self) { item in
                                    Text(item.title).tag(item)
                                }
                            }
                            .settingsSearchTarget("customDock.appearance")
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
                            .settingsSearchTarget("customDock.indicator")
                            .pickerStyle(.segmented)
                            Toggle("Namen beim Überfahren anzeigen", isOn: $showAppNames)
                                .settingsSearchTarget("customDock.names")
                            Toggle("Papierkorb anzeigen", isOn: $showTrash)
                                .settingsSearchTarget("customDock.trash")
                            Toggle("Minimierte Fenster im Dock zeigen", isOn: $showMinimized)
                                .settingsSearchTarget("customDock.minimized")
                            Toggle("Zuletzt benutzte Apps zeigen", isOn: $showRecents)
                                .settingsSearchTarget("customDock.recents")
                            Text("Minimierte Fenster erscheinen vor dem Papierkorb, bis zu drei zuletzt beendete Apps hinter den laufenden Apps. Abstände und Trennstriche fügst du per Rechtsklick auf das Dock hinzu.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SettingsGroup(header: "Verhalten") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Automatisch ausblenden", isOn: $autoHide)
                                .settingsSearchTarget("customDock.autoHide")
                            Text("Das Dock gleitet an den Rand und erscheint wieder, sobald der Zeiger den Bildschirmrand berührt.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Toggle("Fenstervorschauen beim Überfahren", isOn: $showPreviews)
                                .settingsSearchTarget("customDock.previews")
                            Text("Nutzt die Vorschau-Einstellungen aus „Dock Previews“ (Größe, Verzögerung, Aktionen, Vollbild beim Überfahren).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SettingsGroup(header: "Ordner und Gruppen") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Ordner anzeigen als", selection: $stackMode) {
                                ForEach(StackDisplayMode.allCases, id: \.self) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .settingsSearchTarget("customDock.stackMode")
                            .pickerStyle(.segmented)
                            Picker("Sortieren nach", selection: $stackSort) {
                                ForEach(StackSortOrder.allCases, id: \.self) { sort in
                                    Text(sort.title).tag(sort)
                                }
                            }
                            .settingsSearchTarget("customDock.stackSort")
                            Text("Gilt für alle Ordner ohne eigene Einstellung. Pro Ordner änderst du das per Rechtsklick › „Anzeigen als“ bzw. „Sortieren nach“.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("App-Gruppe erstellen: eine App auf eine andere ziehen und kurz halten, bis sie größer wird – oder Rechtsklick › „Zu Gruppe hinzufügen“.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SettingsGroup(header: "Widgets") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Widget hinzufügen")
                                .font(.subheadline.weight(.medium))
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 8) {
                                ForEach(DockWidgetKind.allCases, id: \.self) { kind in
                                    Button {
                                        CustomDockStore.appendWidget(kind)
                                    } label: {
                                        Label(kind.title, systemImage: kind.symbol)
                                    }
                                }
                            }
                            Text(widgetSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Ein Widget auf ein anderes ziehen und kurz halten ergibt einen Widget-Stapel. Im Stapel blätterst du per Scrollen, Rechtsklick bietet weitere Optionen.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Divider()
                            Picker("Uhr", selection: $clockStyle) {
                                ForEach(DockClockStyle.allCases, id: \.self) { style in
                                    Text(style.title).tag(style)
                                }
                            }
                            .settingsSearchTarget("customDock.clock")
                            .pickerStyle(.segmented)

                            Divider()
                            weatherSettings

                            Divider()
                            Toggle("Lautstärke per Scrollen über Now Playing", isOn: $volumeScroll)
                            Text("In einem Widget-Stapel mit gedrückter ⌥-Taste scrollen.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Toggle("Songtexte laden (LRCLIB)", isOn: $loadLyrics)
                                .settingsSearchTarget("customDock.lyrics")

                            Divider()
                            Toggle("Stapel automatisch durchblättern", isOn: $autoRotate)
                                .settingsSearchTarget("customDock.rotate")
                            if autoRotate {
                                sliderRow("Alle", value: $rotateSeconds, range: 4 ... 60, unit: "s")
                            }
                            Toggle("Zu Now Playing wechseln, wenn Musik startet", isOn: $smartSwitch)
                        }
                    }

                    CustomDockExtrasSettings()

                    SettingsGroup(header: "Inhalt") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Symbole ordnest du per Ziehen neu. Nach oben aus dem Dock ziehen und loslassen entfernt sie. Laufende Apps werden angeheftet, wenn du sie zu den angehefteten ziehst.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Apps behältst du per Rechtsklick › „Im Dock behalten“. Apps, Ordner und Dateien lassen sich auch aus dem Finder aufs Dock ziehen.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Apps und Ordner aus dem macOS-Dock neu übernehmen …") {
                                showReimportConfirmation = true
                            }
                            .settingsSearchTarget("customDock.reimport")
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
            Text("Die angehefteten Apps und Ordner in Docker werden durch die aus dem macOS-Dock ersetzt.")
        }
    }

    private var widgetSummary: String {
        let widgets = pinnedItems.filter { $0.kind == .widget }
        guard !widgets.isEmpty else { return "Noch keine Widgets im Dock. Tipp: Rechtsklick auf eine freie Stelle im Dock › „Widget hinzufügen“." }
        let names = widgets.map { item in (item.widgets ?? []).map(\.title).joined(separator: " + ") }
        return "Im Dock: " + names.joined(separator: ", ")
    }

    @ViewBuilder
    private var weatherSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Wetter-Ort")
                Spacer()
                Text(weatherHasLocation ? weatherPlace : "nicht festgelegt")
                    .foregroundStyle(.secondary)
            }
            HStack {
                TextField("Ort suchen, z. B. Hamburg", text: $placeQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(searchPlace)
                Button("Suchen", action: searchPlace)
                    .disabled(placeQuery.trimmingCharacters(in: .whitespaces).count < 2)
                if isSearchingPlace {
                    ProgressView().controlSize(.small)
                }
            }
            if !placeResults.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(placeResults) { place in
                        Button {
                            weather.choose(place)
                            placeResults = []
                            placeQuery = ""
                        } label: {
                            Label(place.label, systemImage: "mappin.and.ellipse")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 3)
                    }
                }
            }
            HStack {
                Button {
                    weather.useCurrentLocation()
                } label: {
                    Label("Aktuellen Standort verwenden", systemImage: "location")
                }
                Spacer()
                Picker("Einheit", selection: $temperatureUnit) {
                    ForEach(DockTemperatureUnit.allCases, id: \.self) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
            if let message = weather.locationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Wetterdaten von Open-Meteo (kostenlos, ohne Konto).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func searchPlace() {
        let query = placeQuery
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else { return }
        isSearchingPlace = true
        Task {
            let results = await DockWeatherModel.search(query)
            await MainActor.run {
                placeResults = results
                isSearchingPlace = false
            }
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String = "pt") -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range, step: 1)
            Text("\(Int(value.wrappedValue)) \(unit)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }

    private func applyChanges() {
        (NSApp.delegate as? AppDelegate)?.updateCustomDock()
    }
}
