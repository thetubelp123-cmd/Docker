import Defaults
import Foundation

enum CustomDockIndicatorStyle: String, CaseIterable, Defaults.Serializable {
    case dot
    case card
    case none

    var title: String {
        switch self {
        case .dot: "Punkt"
        case .card: "Karte"
        case .none: "Keine"
        }
    }
}

enum CustomDockLayoutMode: String, CaseIterable, Defaults.Serializable {
    case floating
    case edgeToEdge

    var title: String {
        switch self {
        case .floating: "Schwebend"
        case .edgeToEdge: "Randlos"
        }
    }
}

enum CustomDockPosition: String, CaseIterable, Defaults.Serializable {
    case bottom
    case left
    case right

    var title: String {
        switch self {
        case .bottom: "Unten"
        case .left: "Links"
        case .right: "Rechts"
        }
    }

    var isVertical: Bool { self != .bottom }
}

enum CustomDockMaterial: String, CaseIterable, Defaults.Serializable {
    case liquidGlass
    case frosted
    case solid
    case clear

    var title: String {
        switch self {
        case .liquidGlass: "Liquid Glass"
        case .frosted: "Milchglas"
        case .solid: "Fest"
        case .clear: "Klar"
        }
    }

    static var defaultValue: CustomDockMaterial {
        if #available(macOS 26.0, *) { return .liquidGlass }
        return .frosted
    }
}

enum CustomDockAppearance: String, CaseIterable, Defaults.Serializable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: "Wie System"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }
}

enum StackDisplayMode: String, Codable, CaseIterable, Defaults.Serializable {
    case fan
    case grid
    case list

    var title: String {
        switch self {
        case .fan: "Fächer"
        case .grid: "Raster"
        case .list: "Liste"
        }
    }

    var symbol: String {
        switch self {
        case .fan: "rectangle.stack"
        case .grid: "square.grid.3x3"
        case .list: "list.bullet"
        }
    }
}

enum StackSortOrder: String, Codable, CaseIterable, Defaults.Serializable {
    case name
    case dateAdded
    case dateModified
    case dateCreated
    case kind

    var title: String {
        switch self {
        case .name: "Name"
        case .dateAdded: "Hinzugefügt am"
        case .dateModified: "Geändert am"
        case .dateCreated: "Erstellt am"
        case .kind: "Art"
        }
    }
}

enum PinnedDockItemKind: String, Codable {
    case app
    case folder
    case file
    case group
    case widget
    case spacer
}

enum DockSpacerStyle: String, Codable, CaseIterable {
    case space
    case small
    case line

    var title: String {
        switch self {
        case .space: "Abstand"
        case .small: "Kleiner Abstand"
        case .line: "Trennstrich"
        }
    }

    var widthFactor: CGFloat {
        switch self {
        case .space: 1
        case .small: 0.5
        case .line: 0.4
        }
    }
}

enum DockWidgetKind: String, Codable, CaseIterable, Defaults.Serializable {
    case clock
    case weather
    case calendar
    case battery
    case nowPlaying

    var title: String {
        switch self {
        case .clock: "Uhr"
        case .weather: "Wetter"
        case .calendar: "Kalender"
        case .battery: "Akku"
        case .nowPlaying: "Now Playing"
        }
    }

    var symbol: String {
        switch self {
        case .clock: "clock"
        case .weather: "cloud.sun"
        case .calendar: "calendar"
        case .battery: "battery.75percent"
        case .nowPlaying: "music.note"
        }
    }

    /// Width of the tile in icon widths.
    var widthFactor: CGFloat {
        self == .nowPlaying ? 2.6 : 1
    }
}

enum DockClockStyle: String, CaseIterable, Defaults.Serializable {
    case digital
    case analog

    var title: String {
        switch self {
        case .digital: "Digital"
        case .analog: "Analog"
        }
    }
}

enum DockTemperatureUnit: String, CaseIterable, Defaults.Serializable {
    case celsius
    case fahrenheit

    var title: String {
        switch self {
        case .celsius: "°C"
        case .fahrenheit: "°F"
        }
    }
}

struct PinnedGroupMember: Codable, Hashable {
    var path: String
    var bundleIdentifier: String?

    var url: URL { URL(fileURLWithPath: path) }
}

struct PinnedDockItem: Codable, Hashable, Identifiable, Defaults.Serializable {
    var kind: PinnedDockItemKind
    var path: String
    var bundleIdentifier: String?
    var name: String?
    var members: [PinnedGroupMember]?
    var stackMode: StackDisplayMode?
    var stackSort: StackSortOrder?
    var widgets: [DockWidgetKind]?
    var spacerStyle: DockSpacerStyle?

    init(kind: PinnedDockItemKind, path: String, bundleIdentifier: String? = nil, name: String? = nil,
         members: [PinnedGroupMember]? = nil, stackMode: StackDisplayMode? = nil, stackSort: StackSortOrder? = nil,
         widgets: [DockWidgetKind]? = nil)
    {
        self.widgets = widgets
        self.kind = kind
        self.path = path
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.members = members
        self.stackMode = stackMode
        self.stackSort = stackSort
    }

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var isGroup: Bool { kind == .group }

    static func newGroup(name: String, members: [PinnedGroupMember]) -> PinnedDockItem {
        PinnedDockItem(kind: .group, path: "group:\(UUID().uuidString)", name: name, members: members)
    }

    static func newSpacer(_ style: DockSpacerStyle) -> PinnedDockItem {
        var item = PinnedDockItem(kind: .spacer, path: "spacer:\(UUID().uuidString)")
        item.spacerStyle = style
        return item
    }

    static func newWidget(_ widgets: [DockWidgetKind]) -> PinnedDockItem {
        PinnedDockItem(kind: .widget, path: "widget:\(UUID().uuidString)", widgets: widgets)
    }
}

extension Defaults.Keys {
    static let customDockEnabled = Key<Bool>("customDockEnabled", default: true)
    static let customDockHideSystemDock = Key<Bool>("customDockHideSystemDock", default: true)
    static let customDockIconSize = Key<Double>("customDockIconSize", default: 48)
    static let customDockIndicatorStyle = Key<CustomDockIndicatorStyle>("customDockIndicatorStyle", default: .dot)
    static let customDockShowTrash = Key<Bool>("customDockShowTrash", default: true)
    static let customDockShowAppNames = Key<Bool>("customDockShowAppNames", default: true)
    static let customDockMagnification = Key<Bool>("customDockMagnification", default: true)
    static let customDockMagnifiedSize = Key<Double>("customDockMagnifiedSize", default: 88)
    static let customDockLayoutMode = Key<CustomDockLayoutMode>("customDockLayoutMode", default: .floating)
    static let customDockPosition = Key<CustomDockPosition>("customDockPosition", default: .bottom)
    static let customDockMaterial = Key<CustomDockMaterial>("customDockMaterial", default: CustomDockMaterial.defaultValue)
    static let customDockTintOpacity = Key<Double>("customDockTintOpacity", default: 0.15)
    static let customDockShowBorder = Key<Bool>("customDockShowBorder", default: true)
    static let customDockAppearance = Key<CustomDockAppearance>("customDockAppearance", default: .system)
    static let customDockAutoHide = Key<Bool>("customDockAutoHide", default: false)
    static let customDockShowPreviews = Key<Bool>("customDockShowPreviews", default: true)
    static let customDockStackMode = Key<StackDisplayMode>("customDockStackMode", default: .fan)
    static let customDockStackSort = Key<StackSortOrder>("customDockStackSort", default: .dateAdded)
    static let customDockPinnedItems = Key<[PinnedDockItem]>("customDockPinnedItems", default: [])
    static let customDockDidImportSystemDock = Key<Bool>("customDockDidImportSystemDock", default: false)

    static let customDockShowMinimized = Key<Bool>("customDockShowMinimized", default: true)
    static let customDockShowRecents = Key<Bool>("customDockShowRecents", default: true)
    static let customDockRecentApps = Key<[String]>("customDockRecentApps", default: [])
    static let customDockClockStyle = Key<DockClockStyle>("customDockClockStyle", default: .digital)
    static let customDockTemperatureUnit = Key<DockTemperatureUnit>("customDockTemperatureUnit", default: .celsius)
    static let customDockWeatherPlace = Key<String>("customDockWeatherPlace", default: "")
    static let customDockWeatherLatitude = Key<Double>("customDockWeatherLatitude", default: 0)
    static let customDockWeatherLongitude = Key<Double>("customDockWeatherLongitude", default: 0)
    static let customDockWeatherHasLocation = Key<Bool>("customDockWeatherHasLocation", default: false)
    static let customDockVolumeScroll = Key<Bool>("customDockVolumeScroll", default: true)
    static let customDockLoadLyrics = Key<Bool>("customDockLoadLyrics", default: true)
    static let customDockWidgetAutoRotate = Key<Bool>("customDockWidgetAutoRotate", default: false)
    static let customDockWidgetRotateSeconds = Key<Double>("customDockWidgetRotateSeconds", default: 12)
    static let customDockWidgetSmartSwitch = Key<Bool>("customDockWidgetSmartSwitch", default: true)

    // State of the macOS Dock before DockerDoor hid it; -1 = key was not set.
    static let customDockSystemDockHidden = Key<Bool>("customDockSystemDockHidden", default: false)
    static let customDockSavedSystemAutohide = Key<Int>("customDockSavedSystemAutohide", default: -1)
    static let customDockSavedSystemAutohideDelay = Key<Double>("customDockSavedSystemAutohideDelay", default: -1)
}
