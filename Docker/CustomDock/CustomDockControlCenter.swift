import AppKit
import Defaults
import SwiftUI

/// Narrow tile at the start of the dock showing the active profile.
struct ControlTileView: View {
    let symbol: String
    let size: CGSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: min(size.width, size.height) * 0.36, style: .continuous)
        ZStack {
            shape.fill(Color.primary.opacity(0.1))
            shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
            VStack(spacing: size.height * 0.06) {
                Image(systemName: symbol)
                    .font(.system(size: size.height * 0.3, weight: .semibold))
                Image(systemName: "chevron.up")
                    .font(.system(size: size.height * 0.13, weight: .bold))
                    .opacity(0.55)
            }
            .foregroundStyle(Color.primary.opacity(0.8))
        }
        .frame(width: size.width, height: size.height * 0.86)
        .frame(width: size.width, height: size.height, alignment: .bottom)
        .contentShape(Rectangle())
    }
}

/// Popover of the control tile: switch profiles and toggle the most used options.
struct ControlCenterView: View {
    static let size = CGSize(width: 320, height: 430)

    let close: () -> Void

    @Default(.customDockProfiles) private var profiles
    @Default(.customDockActiveProfile) private var activeID
    @Default(.customDockMagnification) private var magnification
    @Default(.customDockAutoHide) private var autoHide
    @Default(.customDockLayoutMode) private var layoutMode
    @Default(.customDockAppearance) private var appearance
    @Default(.customDockAppSenseEnabled) private var appSense
    @Default(.customDockIconSize) private var iconSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profile")
                .font(.system(size: 13, weight: .semibold))

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                    ForEach(profiles) { profile in
                        Button {
                            ProfileManager.activate(profile.id)
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName: profile.symbol)
                                    .font(.system(size: 18, weight: .medium))
                                    .frame(height: 22)
                                Text(profile.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                if !profile.triggerApps.isEmpty {
                                    Text("\(profile.triggerApps.count) App\(profile.triggerApps.count == 1 ? "" : "s")")
                                        .font(.system(size: 9))
                                        .opacity(0.7)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 62)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(profile.id == activeID ? Color.accentColor : Color.primary.opacity(0.07))
                            )
                            .foregroundStyle(profile.id == activeID ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        let profile = ProfileManager.create(name: "Profil \(profiles.count + 1)", copyCurrent: true)
                        ProfileManager.activate(profile.id)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "plus").font(.system(size: 18, weight: .medium)).frame(height: 22)
                            Text("Neu").font(.system(size: 11, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Neues Profil als Kopie des aktuellen")
                }
            }
            .frame(maxHeight: 150)

            Divider()

            VStack(alignment: .leading, spacing: 9) {
                Toggle("Vergrößerung", isOn: $magnification)
                Toggle("Automatisch ausblenden", isOn: $autoHide)
                Toggle("AppSense (Profil je App)", isOn: $appSense)
                HStack {
                    Text("Größe")
                    Slider(value: $iconSize, in: 24 ... 96, step: 2)
                        .controlSize(.small)
                }
                Picker("Layout", selection: $layoutMode) {
                    ForEach(CustomDockLayoutMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Picker("Erscheinungsbild", selection: $appearance) {
                    ForEach(CustomDockAppearance.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .font(.system(size: 12))
            .toggleStyle(.switch)
            .controlSize(.small)

            Spacer(minLength: 0)

            Button {
                close()
                (NSApp.delegate as? AppDelegate)?.openSettingsWindow(nil)
            } label: {
                Label("Profile verwalten …", systemImage: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
    }
}
