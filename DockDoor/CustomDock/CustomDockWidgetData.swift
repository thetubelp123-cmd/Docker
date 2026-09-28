import AppKit
import Combine
import CoreLocation
import Defaults
import EventKit
import Foundation
import IOKit.ps

/// Starts and stops the data sources depending on which widgets are in the dock.
final class DockWidgetHub {
    static let shared = DockWidgetHub()
    private var active: Set<DockWidgetKind> = []

    func update(activeKinds: Set<DockWidgetKind>) {
        guard activeKinds != active else { return }
        active = activeKinds
        activeKinds.contains(.weather) ? DockWeatherModel.shared.start() : DockWeatherModel.shared.stop()
        activeKinds.contains(.battery) ? DockBatteryModel.shared.start() : DockBatteryModel.shared.stop()
        activeKinds.contains(.calendar) ? DockCalendarModel.shared.start() : DockCalendarModel.shared.stop()
    }
}

// MARK: - Weather (Open-Meteo)

enum WeatherCondition {
    static func symbol(code: Int, isDay: Bool) -> String {
        switch code {
        case 0, 1: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55: "cloud.drizzle.fill"
        case 56, 57, 66, 67: "cloud.sleet.fill"
        case 61, 63: "cloud.rain.fill"
        case 65, 82: "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 80, 81: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func description(code: Int) -> String {
        switch code {
        case 0: "Klar"
        case 1: "Heiter"
        case 2: "Teilweise bewölkt"
        case 3: "Bewölkt"
        case 45, 48: "Nebel"
        case 51, 53, 55: "Nieselregen"
        case 56, 57: "Gefrierender Niesel"
        case 61, 63: "Regen"
        case 65: "Starker Regen"
        case 66, 67: "Gefrierender Regen"
        case 71, 73, 75, 77: "Schnee"
        case 80, 81: "Regenschauer"
        case 82: "Heftige Schauer"
        case 85, 86: "Schneeschauer"
        case 95: "Gewitter"
        case 96, 99: "Gewitter mit Hagel"
        default: "Bewölkt"
        }
    }

    static func isCloudy(_ code: Int) -> Bool { code >= 3 }
    static func isWet(_ code: Int) -> Bool { code >= 51 }
}

struct WeatherSnapshot: Equatable {
    struct Hour: Identifiable, Equatable {
        let date: Date
        let temperature: Double
        let code: Int
        let isDay: Bool
        let precipitation: Int?
        var id: Date { date }
    }

    struct Day: Identifiable, Equatable {
        let date: Date
        let code: Int
        let min: Double
        let max: Double
        let precipitation: Int?
        var id: Date { date }
    }

    let temperature: Double
    let apparent: Double
    let code: Int
    let isDay: Bool
    let humidity: Double?
    let wind: Double?
    let hours: [Hour]
    let days: [Day]
    let fetched: Date
}

struct WeatherPlace: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let admin1: String?

    var label: String {
        [name, admin1, country].compactMap { $0 }.filter { !$0.isEmpty }.reduce(into: [String]()) { result, part in
            if !result.contains(part) { result.append(part) }
        }.joined(separator: ", ")
    }
}

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let apparent_temperature: Double?
        let weather_code: Int
        let is_day: Int?
        let relative_humidity_2m: Double?
        let wind_speed_10m: Double?
    }

    struct Hourly: Decodable {
        let time: [String]
        let temperature_2m: [Double?]
        let weather_code: [Int?]
        let is_day: [Int?]?
        let precipitation_probability: [Int?]?
    }

    struct Daily: Decodable {
        let time: [String]
        let weather_code: [Int?]
        let temperature_2m_max: [Double?]
        let temperature_2m_min: [Double?]
        let precipitation_probability_max: [Int?]?
    }

    let utc_offset_seconds: Int?
    let current: Current
    let hourly: Hourly?
    let daily: Daily?
}

private struct GeocodingResponse: Decodable {
    let results: [WeatherPlace]?
}

final class DockWeatherModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = DockWeatherModel()

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?
    @Published private(set) var locationMessage: String?

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var settingsTask: Task<Void, Never>?
    private var isRunning = false
    private var locationManager: CLLocationManager?
    private var wantsCurrentLocation = false

    var hasLocation: Bool { Defaults[.customDockWeatherHasLocation] }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 20 * 60, repeats: true) { [weak self] _ in self?.refresh() }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self?.refresh() }
        }
        let keys: [Defaults._AnyKey] = [.customDockWeatherLatitude, .customDockWeatherLongitude, .customDockTemperatureUnit, .customDockWeatherHasLocation]
        settingsTask = Task { [weak self] in
            for await _ in Defaults.updates(keys, initial: false) {
                await MainActor.run { self?.refresh() }
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        settingsTask?.cancel()
        settingsTask = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    func refresh() {
        guard hasLocation else {
            snapshot = nil
            errorText = nil
            return
        }
        let latitude = Defaults[.customDockWeatherLatitude]
        let longitude = Defaults[.customDockWeatherLongitude]
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,relative_humidity_2m,wind_speed_10m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day,precipitation_probability"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "6"),
            URLQueryItem(name: "temperature_unit", value: Defaults[.customDockTemperatureUnit] == .fahrenheit ? "fahrenheit" : "celsius"),
        ]
        guard let url = components.url else { return }
        isLoading = true
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            let snapshot = data.flatMap { try? JSONDecoder().decode(OpenMeteoResponse.self, from: $0) }.map(Self.makeSnapshot)
            DispatchQueue.main.async {
                guard let self else { return }
                isLoading = false
                if let snapshot {
                    self.snapshot = snapshot
                    errorText = nil
                } else {
                    errorText = error == nil ? "Wetterdaten konnten nicht gelesen werden." : "Keine Verbindung zum Wetterdienst."
                }
            }
        }.resume()
    }

    private static func makeSnapshot(_ response: OpenMeteoResponse) -> WeatherSnapshot {
        let timeZone = TimeZone(secondsFromGMT: response.utc_offset_seconds ?? 0) ?? .current
        let hourFormatter = DateFormatter()
        hourFormatter.locale = Locale(identifier: "en_US_POSIX")
        hourFormatter.timeZone = timeZone
        hourFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = timeZone
        dayFormatter.dateFormat = "yyyy-MM-dd"

        var hours: [WeatherSnapshot.Hour] = []
        if let hourly = response.hourly {
            let now = Date().addingTimeInterval(-3600)
            for (index, time) in hourly.time.enumerated() {
                guard let date = hourFormatter.date(from: time), date > now,
                      let temperature = hourly.temperature_2m[safe: index] ?? nil,
                      let code = hourly.weather_code[safe: index] ?? nil
                else { continue }
                let isDay = (hourly.is_day?[safe: index] ?? nil).map { $0 == 1 } ?? true
                hours.append(.init(date: date, temperature: temperature, code: code, isDay: isDay, precipitation: hourly.precipitation_probability?[safe: index] ?? nil))
                if hours.count == 8 { break }
            }
        }

        var days: [WeatherSnapshot.Day] = []
        if let daily = response.daily {
            for (index, time) in daily.time.enumerated() {
                guard let date = dayFormatter.date(from: time),
                      let code = daily.weather_code[safe: index] ?? nil,
                      let high = daily.temperature_2m_max[safe: index] ?? nil,
                      let low = daily.temperature_2m_min[safe: index] ?? nil
                else { continue }
                days.append(.init(date: date, code: code, min: low, max: high, precipitation: daily.precipitation_probability_max?[safe: index] ?? nil))
            }
        }

        let current = response.current
        return WeatherSnapshot(
            temperature: current.temperature_2m,
            apparent: current.apparent_temperature ?? current.temperature_2m,
            code: current.weather_code,
            isDay: (current.is_day ?? 1) == 1,
            humidity: current.relative_humidity_2m,
            wind: current.wind_speed_10m,
            hours: hours,
            days: days,
            fetched: Date()
        )
    }

    static func search(_ query: String) async -> [WeatherPlace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "language", value: "de"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(GeocodingResponse.self, from: data)
        else { return [] }
        return response.results ?? []
    }

    func choose(_ place: WeatherPlace) {
        Defaults[.customDockWeatherPlace] = place.name
        Defaults[.customDockWeatherLatitude] = place.latitude
        Defaults[.customDockWeatherLongitude] = place.longitude
        Defaults[.customDockWeatherHasLocation] = true
        locationMessage = nil
        refresh()
    }

    // MARK: Current location

    func useCurrentLocation() {
        let manager = locationManager ?? CLLocationManager()
        locationManager = manager
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        wantsCurrentLocation = true
        locationMessage = "Standort wird ermittelt …"
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            wantsCurrentLocation = false
            locationMessage = "Kein Zugriff auf den Standort. Erlaube ihn in den Systemeinstellungen › Datenschutz & Sicherheit › Ortungsdienste."
        default:
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard wantsCurrentLocation else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            break
        case .denied, .restricted:
            wantsCurrentLocation = false
            locationMessage = "Kein Zugriff auf den Standort. Erlaube ihn in den Systemeinstellungen › Datenschutz & Sicherheit › Ortungsdienste."
        default:
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard wantsCurrentLocation, let location = locations.last else { return }
        wantsCurrentLocation = false
        CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "de_DE")) { [weak self] placemarks, _ in
            DispatchQueue.main.async {
                let name = placemarks?.first?.locality ?? placemarks?.first?.name ?? "Aktueller Standort"
                Defaults[.customDockWeatherPlace] = name
                Defaults[.customDockWeatherLatitude] = location.coordinate.latitude
                Defaults[.customDockWeatherLongitude] = location.coordinate.longitude
                Defaults[.customDockWeatherHasLocation] = true
                self?.locationMessage = nil
                self?.refresh()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard wantsCurrentLocation else { return }
        wantsCurrentLocation = false
        locationMessage = "Standort konnte nicht ermittelt werden. Such den Ort stattdessen über das Suchfeld."
    }
}

// MARK: - Battery (IOKit)

final class DockBatteryModel: ObservableObject {
    static let shared = DockBatteryModel()

    @Published private(set) var hasBattery = false
    @Published private(set) var percent = 0
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    @Published private(set) var minutesRemaining: Int?

    private var runLoopSource: CFRunLoopSource?
    private var timer: Timer?

    init() {
        read()
    }

    func start() {
        guard runLoopSource == nil else { return }
        read()
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let model = Unmanaged<DockBatteryModel>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { model.read() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.read() }
    }

    func stop() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode) }
        runLoopSource = nil
        timer?.invalidate()
        timer = nil
    }

    func read() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            if hasBattery { hasBattery = false }
            return
        }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
            else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let pluggedIn = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let toEmpty = description[kIOPSTimeToEmptyKey] as? Int ?? -1
            let toFull = description[kIOPSTimeToFullChargeKey] as? Int ?? -1
            let newPercent = maximum > 0 ? min(100, max(0, current * 100 / maximum)) : current
            let remaining: Int? = charging ? (toFull > 0 ? toFull : nil) : (!pluggedIn && toEmpty > 0 ? toEmpty : nil)

            if !hasBattery { hasBattery = true }
            if percent != newPercent { percent = newPercent }
            if isCharging != charging { isCharging = charging }
            if isPluggedIn != pluggedIn { isPluggedIn = pluggedIn }
            if minutesRemaining != remaining { minutesRemaining = remaining }
            return
        }
        if hasBattery { hasBattery = false }
    }
}

// MARK: - Calendar (EventKit)

struct DockCalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let color: NSColor
}

final class DockCalendarModel: ObservableObject {
    static let shared = DockCalendarModel()

    @Published private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var events: [DockCalendarEvent] = []
    @Published private(set) var today = Date()

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var timer: Timer?

    var hasAccess: Bool {
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        }
        return status == .authorized
    }

    func start() {
        guard timer == nil else { return }
        status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            requestAccess()
        } else {
            load()
        }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.load()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !Calendar.current.isDate(today, inSameDayAs: Date()) {
                today = Date()
                load()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func requestAccess() {
        let completion: (Bool, Error?) -> Void = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.status = EKEventStore.authorizationStatus(for: .event)
                self?.load()
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: completion)
        } else {
            store.requestAccess(to: .event, completion: completion)
        }
    }

    func load() {
        status = EKEventStore.authorizationStatus(for: .event)
        today = Date()
        guard hasAccess else {
            events = []
            return
        }
        let start = Calendar.current.startOfDay(for: Date())
        guard let end = Calendar.current.date(byAdding: .day, value: 8, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let loaded = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                DockCalendarEvent(
                    id: (event.eventIdentifier ?? UUID().uuidString) + "\(event.startDate.timeIntervalSince1970)",
                    title: event.title ?? "Ohne Titel",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    location: event.location,
                    color: event.calendar.map { NSColor(cgColor: $0.cgColor) ?? .systemRed } ?? .systemRed
                )
            }
        if loaded != events { events = loaded }
    }

    var nextEvent: DockCalendarEvent? {
        let now = Date()
        return events.first { !$0.isAllDay && $0.end > now && Calendar.current.isDateInToday($0.start) }
    }

    var todayCount: Int {
        events.filter { Calendar.current.isDateInToday($0.start) || ($0.start < Date() && $0.end > Date()) }.count
    }
}

// MARK: - Lyrics (LRCLIB)

final class DockLyricsModel: ObservableObject {
    static let shared = DockLyricsModel()

    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var isSynced = false
    @Published private(set) var isLoading = false
    @Published private(set) var trackKey = ""

    private var task: Task<Void, Never>?

    private struct LRCLibEntry: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
        let duration: Double?
    }

    func load(title: String, artist: String, album: String, duration: TimeInterval) {
        let key = "\(title)|\(artist)"
        guard key != trackKey else { return }
        trackKey = key
        task?.cancel()
        lines = []
        isSynced = false
        guard Defaults[.customDockLoadLyrics], !title.isEmpty, !artist.isEmpty else {
            isLoading = false
            return
        }
        isLoading = true
        task = Task { [weak self] in
            let result = await Self.fetch(title: title, artist: artist, album: album, duration: duration)
            await MainActor.run {
                guard let self, !Task.isCancelled, self.trackKey == key else { return }
                self.lines = result.lines
                self.isSynced = result.synced
                self.isLoading = false
            }
        }
    }

    func currentIndex(at time: TimeInterval) -> Int? {
        guard isSynced, !lines.isEmpty else { return nil }
        return lines.lastIndex { $0.startTime <= time + 0.25 }
    }

    private static func fetch(title: String, artist: String, album: String, duration: TimeInterval) async -> (lines: [LyricLine], synced: Bool) {
        var getComponents = URLComponents(string: "https://lrclib.net/api/get")!
        getComponents.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if !album.isEmpty { getComponents.queryItems?.append(URLQueryItem(name: "album_name", value: album)) }
        if duration > 0 { getComponents.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }

        var candidates: [LRCLibEntry] = []
        if let url = getComponents.url, let entry: LRCLibEntry = await request(url) {
            candidates.append(entry)
        }
        if candidates.first?.syncedLyrics?.isEmpty ?? true {
            var searchComponents = URLComponents(string: "https://lrclib.net/api/search")!
            searchComponents.queryItems = [
                URLQueryItem(name: "track_name", value: title),
                URLQueryItem(name: "artist_name", value: artist),
            ]
            if let url = searchComponents.url, let entries: [LRCLibEntry] = await request(url) {
                let sorted = entries.sorted { lhs, rhs in
                    abs((lhs.duration ?? 0) - duration) < abs((rhs.duration ?? 0) - duration)
                }
                candidates.append(contentsOf: sorted)
            }
        }
        if let synced = candidates.lazy.compactMap(\.syncedLyrics).first(where: { !$0.isEmpty }) {
            let parsed = parseLRC(synced)
            if !parsed.isEmpty { return (parsed, true) }
        }
        if let plain = candidates.lazy.compactMap(\.plainLyrics).first(where: { !$0.isEmpty }) {
            let lines = plain.components(separatedBy: .newlines).enumerated().map { index, text in
                LyricLine(startTime: TimeInterval(index), words: text.trimmingCharacters(in: .whitespaces))
            }
            return (lines, false)
        }
        return ([], false)
    }

    private static func request<T: Decodable>(_ url: URL) async -> T? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("DockerDoor (privat)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func parseLRC(_ text: String) -> [LyricLine] {
        guard let regex = try? NSRegularExpression(pattern: "\\[(\\d+):(\\d+)(?:[.:](\\d+))?\\]") else { return [] }
        var result: [LyricLine] = []
        for line in text.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..., in: line)
            let matches = regex.matches(in: line, range: range)
            guard let last = matches.last, let textRange = Range(NSRange(location: last.range.upperBound, length: range.length - last.range.upperBound), in: line) else { continue }
            let words = String(line[textRange]).trimmingCharacters(in: .whitespaces)
            for match in matches {
                func value(_ index: Int) -> String? {
                    Range(match.range(at: index), in: line).map { String(line[$0]) }
                }
                let minutes = Double(value(1) ?? "0") ?? 0
                let seconds = Double(value(2) ?? "0") ?? 0
                var fraction = 0.0
                if let raw = value(3), let number = Double(raw) {
                    fraction = number / pow(10, Double(raw.count))
                }
                result.append(LyricLine(startTime: minutes * 60 + seconds + fraction, words: words))
            }
        }
        return result.sorted { $0.startTime < $1.startTime }
    }
}
