import AppKit
import Defaults
import SwiftUI

// MARK: - Dock tile

struct DockWidgetTileView: View {
    let tile: DockTile
    let page: Int
    let size: CGSize
    let volume: Float?

    private var kind: DockWidgetKind {
        tile.widgets.isEmpty ? .clock : tile.widgets[page % tile.widgets.count]
    }

    /// Everything is designed for a 48 pt tile and scaled from there.
    private var unit: CGFloat { size.height / 48 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size.height * 0.225, style: .continuous)
        ZStack {
            Group {
                switch kind {
                case .clock: ClockTileContent(unit: unit)
                case .weather: WeatherTileContent(unit: unit)
                case .calendar: CalendarTileContent(unit: unit)
                case .battery: BatteryTileContent(unit: unit)
                case .nowPlaying: NowPlayingTileContent(unit: unit)
                }
            }
            .id(kind)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))

            if tile.widgets.count > 1 {
                HStack {
                    Spacer()
                    VStack(spacing: 2 * unit) {
                        ForEach(tile.widgets.indices, id: \.self) { index in
                            Circle()
                                .fill(Color.white.opacity(index == page % tile.widgets.count ? 0.95 : 0.35))
                                .frame(width: 3.2 * unit, height: 3.2 * unit)
                        }
                    }
                    .padding(.trailing, 3 * unit)
                }
            }

            if let volume {
                VolumeOverlay(value: volume, unit: unit)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 2 * unit, y: 1 * unit)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: page)
        .animation(.easeOut(duration: 0.15), value: volume != nil)
        .contentShape(Rectangle())
    }
}

private struct VolumeOverlay: View {
    let value: Float
    let unit: CGFloat

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 4 * unit) {
                Image(systemName: value <= 0.001 ? "speaker.slash.fill" : value < 0.34 ? "speaker.wave.1.fill" : value < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
                    .font(.system(size: 13 * unit, weight: .semibold))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25))
                        Capsule().fill(Color.white).frame(width: proxy.size.width * CGFloat(value))
                    }
                }
                .frame(width: 30 * unit, height: 3.5 * unit)
            }
            .foregroundStyle(.white)
        }
    }
}

// MARK: Clock

private struct ClockTileContent: View {
    let unit: CGFloat
    @Default(.customDockClockStyle) private var style

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            switch style {
            case .digital:
                ZStack {
                    LinearGradient(colors: [Color(white: 0.2), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
                    VStack(spacing: 0) {
                        Text(context.date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                            .font(.system(size: 7.5 * unit, weight: .bold))
                            .foregroundStyle(Color.orange)
                        Text(context.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                            .font(.system(size: 15 * unit, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 3 * unit)
                }
            case .analog:
                ZStack {
                    Color(white: 0.12)
                    AnalogClockFace(date: context.date, light: true)
                        .padding(4 * unit)
                }
            }
        }
    }
}

struct AnalogClockFace: View {
    let date: Date
    var light = true

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            let seconds = Double(components.second ?? 0)
            let minutes = Double(components.minute ?? 0) + seconds / 60
            let hours = Double((components.hour ?? 0) % 12) + minutes / 60
            ZStack {
                Circle().fill(light ? Color.white : Color(white: 0.15))
                ForEach(0 ..< 12, id: \.self) { tick in
                    Capsule()
                        .fill(Color.primary.opacity(tick % 3 == 0 ? 0.8 : 0.35))
                        .frame(width: side * (tick % 3 == 0 ? 0.035 : 0.022), height: side * 0.09)
                        .offset(y: -side * 0.4)
                        .rotationEffect(.degrees(Double(tick) * 30))
                }
                .environment(\.colorScheme, light ? .light : .dark)
                hand(length: 0.26, width: 0.055, angle: hours * 30, side: side)
                hand(length: 0.38, width: 0.04, angle: minutes * 6, side: side)
                Capsule()
                    .fill(Color.orange)
                    .frame(width: side * 0.018, height: side * 0.44)
                    .offset(y: -side * 0.16)
                    .rotationEffect(.degrees(seconds * 6))
                Circle().fill(Color.orange).frame(width: side * 0.07)
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private func hand(length: CGFloat, width: CGFloat, angle: Double, side: CGFloat) -> some View {
        Capsule()
            .fill(light ? Color.black : Color.white)
            .frame(width: side * width, height: side * length)
            .offset(y: -side * length / 2)
            .rotationEffect(.degrees(angle))
    }
}

// MARK: Weather

private struct WeatherTileContent: View {
    let unit: CGFloat
    @ObservedObject private var model = DockWeatherModel.shared

    var body: some View {
        ZStack {
            WeatherBackground(code: model.snapshot?.code ?? 2, isDay: model.snapshot?.isDay ?? true)
            if let snapshot = model.snapshot {
                VStack(spacing: 1 * unit) {
                    Image(systemName: WeatherCondition.symbol(code: snapshot.code, isDay: snapshot.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 16 * unit))
                    Text("\(Int(snapshot.temperature.rounded()))°")
                        .font(.system(size: 13 * unit, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            } else if !model.hasLocation {
                VStack(spacing: 2 * unit) {
                    Image(systemName: "location.magnifyingglass")
                        .font(.system(size: 15 * unit, weight: .medium))
                    Text("Ort?")
                        .font(.system(size: 9 * unit, weight: .semibold))
                }
                .foregroundStyle(.white)
            } else {
                ProgressView().controlSize(.small).tint(.white)
            }
        }
    }
}

struct WeatherBackground: View {
    let code: Int
    let isDay: Bool

    var body: some View {
        let colors: [Color] = if !isDay {
            [Color(red: 0.1, green: 0.13, blue: 0.3), Color(red: 0.03, green: 0.05, blue: 0.14)]
        } else if WeatherCondition.isWet(code) {
            [Color(red: 0.36, green: 0.44, blue: 0.55), Color(red: 0.2, green: 0.26, blue: 0.36)]
        } else if WeatherCondition.isCloudy(code) {
            [Color(red: 0.5, green: 0.6, blue: 0.72), Color(red: 0.32, green: 0.42, blue: 0.56)]
        } else {
            [Color(red: 0.3, green: 0.62, blue: 0.96), Color(red: 0.12, green: 0.4, blue: 0.84)]
        }
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

// MARK: Calendar

private struct CalendarTileContent: View {
    let unit: CGFloat
    @ObservedObject private var model = DockCalendarModel.shared

    var body: some View {
        TimelineView(.everyMinute) { context in
            ZStack {
                Color.white
                VStack(spacing: -1 * unit) {
                    Text(context.date.formatted(.dateTime.weekday(.wide)))
                        .font(.system(size: 7 * unit, weight: .semibold))
                        .foregroundStyle(Color.red)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(context.date.formatted(.dateTime.day()))
                        .font(.system(size: 22 * unit, weight: .light))
                        .foregroundStyle(Color(white: 0.12))
                    if let next = model.nextEvent {
                        Text(next.start.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                            .font(.system(size: 6.5 * unit, weight: .semibold))
                            .foregroundStyle(Color(nsColor: next.color))
                    }
                }
                .padding(.horizontal, 3 * unit)
                if model.todayCount > 0 {
                    VStack {
                        HStack {
                            Spacer()
                            Text("\(model.todayCount)")
                                .font(.system(size: 6.5 * unit, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 10 * unit, minHeight: 10 * unit)
                                .background(Circle().fill(Color.red))
                        }
                        Spacer()
                    }
                    .padding(3 * unit)
                }
            }
        }
    }
}

// MARK: Battery

private struct BatteryTileContent: View {
    let unit: CGFloat
    @ObservedObject private var model = DockBatteryModel.shared

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.2), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
            if model.hasBattery {
                BatteryRing(percent: model.percent, charging: model.isCharging, lineWidth: 3.5 * unit)
                    .padding(7 * unit)
                VStack(spacing: 0) {
                    if model.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 6.5 * unit, weight: .bold))
                            .foregroundStyle(.green)
                    }
                    Text("\(model.percent)")
                        .font(.system(size: 11 * unit, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            } else {
                VStack(spacing: 2 * unit) {
                    Image(systemName: "powerplug.fill")
                        .font(.system(size: 14 * unit))
                    Text("Netz")
                        .font(.system(size: 8 * unit, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

struct BatteryRing: View {
    let percent: Int
    let charging: Bool
    let lineWidth: CGFloat

    var color: Color {
        if charging { return .green }
        if percent <= 10 { return .red }
        if percent <= 20 { return .orange }
        return .green
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: Now Playing

private struct NowPlayingTileContent: View {
    let unit: CGFloat
    @ObservedObject private var media = MediaRemoteService.shared

    var body: some View {
        ZStack {
            if let artwork = media.artwork, media.hasActiveMedia {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 14 * unit)
                    .overlay(Color.black.opacity(0.45))
            } else {
                LinearGradient(colors: [Color(red: 0.95, green: 0.25, blue: 0.4), Color(red: 0.55, green: 0.12, blue: 0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }

            if media.hasActiveMedia {
                HStack(spacing: 6 * unit) {
                    ZStack {
                        if let artwork = media.artwork {
                            Image(nsImage: artwork)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Color.white.opacity(0.2)
                            Image(systemName: "music.note").font(.system(size: 14 * unit)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: 34 * unit, height: 34 * unit)
                    .clipShape(RoundedRectangle(cornerRadius: 6 * unit, style: .continuous))

                    VStack(alignment: .leading, spacing: 1 * unit) {
                        Text(media.title)
                            .font(.system(size: 9.5 * unit, weight: .semibold))
                            .lineLimit(1)
                        Text(media.artist)
                            .font(.system(size: 8.5 * unit))
                            .opacity(0.75)
                            .lineLimit(1)
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            let progress = media.duration > 0 ? min(1, media.interpolatedElapsedTime / media.duration) : 0
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.25))
                                    Capsule().fill(Color.white).frame(width: proxy.size.width * progress)
                                }
                            }
                            .frame(height: 2.5 * unit)
                        }
                        .padding(.top, 2 * unit)
                    }
                    .foregroundStyle(.white)

                    Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 10 * unit, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 10 * unit)
                }
                .padding(.horizontal, 7 * unit)
            } else {
                HStack(spacing: 6 * unit) {
                    Image(systemName: "music.note")
                        .font(.system(size: 17 * unit, weight: .semibold))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Now Playing")
                            .font(.system(size: 9.5 * unit, weight: .semibold))
                        Text("Gerade läuft nichts")
                            .font(.system(size: 8 * unit))
                            .opacity(0.8)
                    }
                }
                .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Popover window

final class DockPopoverController: NSObject, NSWindowDelegate {
    private var panel: StackPanel?
    private var outsideMonitor: Any?
    private var localMonitor: Any?

    private(set) var openKey: String?
    var isOpen: Bool { panel != nil }

    func show<Content: View>(_ content: Content, size: CGSize, key: String, anchor: CGRect, screen: NSScreen, ignoringClicksIn dockWindow: NSWindow?) {
        close()
        openKey = key
        let panel = StackPanel()
        panel.delegate = self
        let hosting = NSHostingView(rootView: DockPopoverChrome { content }.frame(width: size.width, height: size.height))
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel

        var x = anchor.midX - size.width / 2
        x = min(max(x, screen.frame.minX + 6), screen.frame.maxX - size.width - 6)
        let y = min(anchor.maxY + 6, screen.visibleFrame.maxY - size.height)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }

        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.window === panel || event.window === dockWindow { return event }
            close()
            return event
        }
    }

    func close() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        outsideMonitor = nil
        localMonitor = nil
        openKey = nil
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.contentView = nil
        })
    }
}

private struct DockPopoverChrome<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(4)
    }
}

enum DockWidgetPopovers {
    static func size(for kind: DockWidgetKind) -> CGSize {
        switch kind {
        case .clock: CGSize(width: 270, height: 300)
        case .weather: CGSize(width: 330, height: 420)
        case .calendar: CGSize(width: 310, height: 470)
        case .battery: CGSize(width: 270, height: 230)
        case .nowPlaying: CGSize(width: 330, height: 500)
        }
    }

    @ViewBuilder
    static func view(for kind: DockWidgetKind, close: @escaping () -> Void) -> some View {
        switch kind {
        case .clock: ClockPopover(close: close)
        case .weather: WeatherPopover(close: close)
        case .calendar: CalendarPopover(close: close)
        case .battery: BatteryPopover(close: close)
        case .nowPlaying: NowPlayingPopover()
        }
    }

    static func openApp(_ bundleIdentifier: String, fallback: URL? = nil) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
        } else if let fallback {
            NSWorkspace.shared.open(fallback)
        }
    }

    static func openDockSettings() {
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow(nil)
    }
}

private struct PopoverButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: Clock popover

private struct ClockPopover: View {
    let close: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 10) {
                AnalogClockFace(date: context.date, light: true)
                    .frame(width: 130, height: 130)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                Text(context.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("Kalenderwoche \(Calendar(identifier: .iso8601).component(.weekOfYear, from: context.date))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                PopoverButton(title: "Uhr-App öffnen", symbol: "clock") {
                    DockWidgetPopovers.openApp("com.apple.clock")
                    close()
                }
            }
        }
    }
}

// MARK: Weather popover

private struct WeatherPopover: View {
    let close: () -> Void
    @ObservedObject private var model = DockWeatherModel.shared
    @Default(.customDockWeatherPlace) private var place

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(place.isEmpty ? "Wetter" : place, systemImage: "location.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(model.isLoading ? 180 : 0))
                        .animation(.easeInOut(duration: 0.5), value: model.isLoading)
                }
                .buttonStyle(.plain)
                .help("Aktualisieren")
            }

            if !model.hasLocation {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "location.magnifyingglass").font(.system(size: 32)).foregroundStyle(.secondary)
                    Text("Lege in den Einstellungen fest, für welchen Ort das Wetter angezeigt wird.")
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    PopoverButton(title: "Ort festlegen …", symbol: "gearshape") {
                        close()
                        DockWidgetPopovers.openDockSettings()
                    }
                }
                Spacer()
            } else if let snapshot = model.snapshot {
                current(snapshot)
                Divider()
                hourly(snapshot)
                Divider()
                daily(snapshot)
                Spacer(minLength: 0)
                Text("Daten: Open-Meteo · \(snapshot.fetched.formatted(.dateTime.hour().minute())) Uhr")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            } else {
                Spacer()
                if let error = model.errorText {
                    Text(error).font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
                Spacer()
            }
        }
    }

    private func current(_ snapshot: WeatherSnapshot) -> some View {
        HStack(spacing: 14) {
            Image(systemName: WeatherCondition.symbol(code: snapshot.code, isDay: snapshot.isDay))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 44))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(snapshot.temperature.rounded()))°")
                    .font(.system(size: 40, weight: .light, design: .rounded))
                Text(WeatherCondition.description(code: snapshot.code))
                    .font(.system(size: 13, weight: .medium))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let today = snapshot.days.first {
                    Text("H \(Int(today.max.rounded()))°  T \(Int(today.min.rounded()))°")
                }
                Text("Gefühlt \(Int(snapshot.apparent.rounded()))°")
                if let wind = snapshot.wind {
                    Text("Wind \(Int(wind.rounded())) km/h")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    private func hourly(_ snapshot: WeatherSnapshot) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(snapshot.hours.prefix(7).enumerated()), id: \.element.id) { index, hour in
                VStack(spacing: 5) {
                    Text(index == 0 ? "Jetzt" : hour.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted))))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Image(systemName: WeatherCondition.symbol(code: hour.code, isDay: hour.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 15))
                        .frame(height: 18)
                    Text("\(Int(hour.temperature.rounded()))°")
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func daily(_ snapshot: WeatherSnapshot) -> some View {
        let days = Array(snapshot.days.prefix(5))
        let low = days.map(\.min).min() ?? 0
        let high = days.map(\.max).max() ?? 1
        return VStack(spacing: 7) {
            ForEach(days) { day in
                HStack(spacing: 8) {
                    Text(Calendar.current.isDateInToday(day.date) ? "Heute" : day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 44, alignment: .leading)
                    Image(systemName: WeatherCondition.symbol(code: day.code, isDay: true))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 14))
                        .frame(width: 22)
                    Text(day.precipitation.map { $0 >= 20 ? "\($0) %" : "" } ?? "")
                        .font(.system(size: 10))
                        .foregroundStyle(.cyan)
                        .frame(width: 32, alignment: .leading)
                    Text("\(Int(day.min.rounded()))°")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                    GeometryReader { proxy in
                        let span = max(1, high - low)
                        let start = (day.min - low) / span
                        let end = (day.max - low) / span
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.1))
                            Capsule()
                                .fill(LinearGradient(colors: [.cyan, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(6, proxy.size.width * (end - start)))
                                .offset(x: proxy.size.width * start)
                        }
                    }
                    .frame(height: 4)
                    Text("\(Int(day.max.rounded()))°")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 30, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: Calendar popover

private struct CalendarPopover: View {
    let close: () -> Void
    @ObservedObject private var model = DockCalendarModel.shared

    private let calendar: Calendar = {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.today.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 15, weight: .semibold))
            monthGrid
            Divider()
            if model.hasAccess {
                eventList
            } else if model.status == .notDetermined {
                accessPrompt(text: "DockerDoor braucht Zugriff auf deine Kalender, um Termine anzuzeigen.", button: "Zugriff erlauben") {
                    model.requestAccess()
                }
            } else {
                accessPrompt(text: "Kein Zugriff auf deine Kalender. Erlaube ihn in den Systemeinstellungen › Datenschutz & Sicherheit › Kalender.", button: "Systemeinstellungen öffnen") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                    close()
                }
            }
            PopoverButton(title: "Kalender öffnen", symbol: "calendar") {
                DockWidgetPopovers.openApp("com.apple.iCal")
                close()
            }
        }
    }

    private var monthGrid: some View {
        let today = model.today
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        let leading = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let cells: [Int?] = Array(repeating: nil, count: leading) + (1 ... dayCount).map { Optional($0) }
        let eventDays = Set(model.events.compactMap { event -> Int? in
            calendar.isDate(event.start, equalTo: today, toGranularity: .month) ? calendar.component(.day, from: event.start) : nil
        })
        let todayNumber = calendar.component(.day, from: today)
        let symbols = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 3) {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                ZStack {
                    if let day {
                        if day == todayNumber {
                            Circle().fill(Color.red).frame(width: 24, height: 24)
                        }
                        Text("\(day)")
                            .font(.system(size: 12, weight: day == todayNumber ? .bold : .regular))
                            .foregroundStyle(day == todayNumber ? Color.white : Color.primary)
                        if eventDays.contains(day), day != todayNumber {
                            Circle().fill(Color.secondary).frame(width: 3.5, height: 3.5).offset(y: 10)
                        }
                    }
                }
                .frame(height: 26)
            }
        }
    }

    private var eventList: some View {
        let grouped = Dictionary(grouping: model.events) { calendar.startOfDay(for: max($0.start, calendar.startOfDay(for: model.today))) }
        let days = grouped.keys.sorted()
        return Group {
            if model.events.isEmpty {
                Text("Keine Termine in den nächsten Tagen.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(days, id: \.self) { day in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(dayTitle(day))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(grouped[day] ?? []) { event in
                                    eventRow(event)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        if calendar.isDateInToday(day) { return "HEUTE" }
        if calendar.isDateInTomorrow(day) { return "MORGEN" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased()
    }

    private func eventRow(_ event: DockCalendarEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: event.color))
                .frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(event.isAllDay ? "Ganztägig" : "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .opacity(!event.isAllDay && event.end < Date() ? 0.45 : 1)
    }

    private func accessPrompt(text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            PopoverButton(title: button, symbol: "lock.open", action: action)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Battery popover

private struct BatteryPopover: View {
    let close: () -> Void
    @ObservedObject private var model = DockBatteryModel.shared

    var body: some View {
        VStack(spacing: 12) {
            if model.hasBattery {
                HStack(spacing: 16) {
                    ZStack {
                        BatteryRing(percent: model.percent, charging: model.isCharging, lineWidth: 8)
                        Text("\(model.percent) %")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .frame(width: 84, height: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Label(statusTitle, systemImage: model.isCharging ? "bolt.fill" : model.isPluggedIn ? "powerplug.fill" : "battery.75percent")
                            .font(.system(size: 13, weight: .semibold))
                        if let remaining = model.minutesRemaining {
                            Text(model.isCharging ? "Voll in \(format(remaining))" : "Noch \(format(remaining))")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        } else if !model.isPluggedIn {
                            Text("Restlaufzeit wird berechnet …")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Label("Dieser Mac hat keinen Akku.", systemImage: "powerplug.fill")
                    .font(.system(size: 13))
                    .frame(maxHeight: .infinity)
            }
            Spacer(minLength: 0)
            PopoverButton(title: "Batterie-Einstellungen …", symbol: "gearshape") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
                close()
            }
        }
    }

    private var statusTitle: String {
        if model.isCharging { return "Wird geladen" }
        if model.isPluggedIn { return "Am Netzteil" }
        return "Akkubetrieb"
    }

    private func format(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        return hours > 0 ? "\(hours):\(String(format: "%02d", rest)) Std." : "\(rest) Min."
    }
}

// MARK: Now Playing popover

private struct NowPlayingPopover: View {
    @ObservedObject private var media = MediaRemoteService.shared
    @ObservedObject private var lyrics = DockLyricsModel.shared
    @Default(.customDockLoadLyrics) private var loadLyrics
    @State private var showLyrics = false
    @State private var volume: Float = AudioDeviceManager.getSystemVolume()
    @State private var scrubbing: Double?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                if let id = media.activeBundleIdentifier, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Text(media.activeAppName ?? "Now Playing")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if loadLyrics, media.hasActiveMedia {
                    Button {
                        showLyrics.toggle()
                    } label: {
                        Image(systemName: "quote.bubble")
                            .symbolVariant(showLyrics ? .fill : .none)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .help("Songtext")
                }
            }

            if media.hasActiveMedia {
                ZStack {
                    if showLyrics {
                        LyricsPanel(lyrics: lyrics, media: media)
                    } else {
                        artwork
                    }
                }
                .frame(height: 250)

                VStack(spacing: 2) {
                    Text(media.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text([media.artist, media.album].filter { !$0.isEmpty }.joined(separator: " — "))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                progress
                controls
                volumeRow
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "music.note").font(.system(size: 36)).foregroundStyle(.secondary)
                    Text("Gerade läuft nichts.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .onAppear(perform: loadLyricsIfNeeded)
        .onChange(of: media.title) { _ in loadLyricsIfNeeded() }
    }

    private func loadLyricsIfNeeded() {
        guard loadLyrics, media.hasActiveMedia else { return }
        lyrics.load(title: media.title, artist: media.artist, album: media.album, duration: media.duration)
    }

    private var artwork: some View {
        Group {
            if let image = media.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.08))
                    Image(systemName: "music.note").font(.system(size: 60)).foregroundStyle(.secondary)
                }
                .aspectRatio(1, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .scaleEffect(media.isPlaying ? 1 : 0.9)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: media.isPlaying)
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let duration = max(media.duration, 0)
            let elapsed = scrubbing ?? min(media.interpolatedElapsedTime, duration)
            VStack(spacing: 2) {
                GeometryReader { proxy in
                    let fraction = duration > 0 ? elapsed / duration : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.15))
                        Capsule().fill(Color.primary.opacity(0.7)).frame(width: proxy.size.width * fraction)
                    }
                    .frame(height: scrubbing == nil ? 4 : 7)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            scrubbing = min(max(0, value.location.x / proxy.size.width), 1) * duration
                        }
                        .onEnded { _ in
                            if let target = scrubbing { media.seek(to: target) }
                            scrubbing = nil
                        })
                }
                .frame(height: 10)
                HStack {
                    Text(timeString(elapsed))
                    Spacer()
                    Text("-" + timeString(max(0, duration - elapsed)))
                }
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .animation(.easeOut(duration: 0.12), value: scrubbing == nil)
        }
    }

    private var controls: some View {
        HStack(spacing: 34) {
            Button { media.previousTrack() } label: {
                Image(systemName: "backward.fill").font(.system(size: 20))
            }
            Button { media.togglePlayPause() } label: {
                Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28))
                    .frame(width: 30)
            }
            Button { media.nextTrack() } label: {
                Image(systemName: "forward.fill").font(.system(size: 20))
            }
        }
        .buttonStyle(.plain)
    }

    private var volumeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { Double(volume) },
                set: { newValue in
                    volume = Float(newValue)
                    AudioDeviceManager.setSystemVolume(volume)
                }
            ), in: 0 ... 1)
                .controlSize(.small)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

private struct LyricsPanel: View {
    @ObservedObject var lyrics: DockLyricsModel
    @ObservedObject var media: MediaRemoteService

    var body: some View {
        Group {
            if lyrics.isLoading {
                ProgressView()
            } else if lyrics.lines.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "text.badge.xmark").font(.system(size: 26)).foregroundStyle(.secondary)
                    Text("Kein Songtext gefunden.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    let current = lyrics.currentIndex(at: media.interpolatedElapsedTime)
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                                    Text(line.words.isEmpty ? "♪" : line.words)
                                        .font(.system(size: lyrics.isSynced ? 17 : 13, weight: lyrics.isSynced ? .bold : .regular))
                                        .foregroundStyle(index == current || !lyrics.isSynced ? Color.primary : Color.primary.opacity(0.3))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(index)
                                        .onTapGesture {
                                            if lyrics.isSynced { media.seek(to: line.startTime) }
                                        }
                                }
                            }
                            .padding(.vertical, 90)
                        }
                        .onChange(of: current) { index in
                            guard let index else { return }
                            withAnimation(.easeInOut(duration: 0.35)) {
                                proxy.scrollTo(index, anchor: .center)
                            }
                        }
                        .onAppear {
                            if let current { proxy.scrollTo(current, anchor: .center) }
                        }
                    }
                    .mask(LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.18),
                        .init(color: .black, location: 0.82),
                        .init(color: .clear, location: 1),
                    ], startPoint: .top, endPoint: .bottom))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
