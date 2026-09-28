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

    init(kind: PinnedDockItemKind, path: String, bundleIdentifier: String? = nil, name: String? = nil,
         members: [PinnedGroupMember]? = nil, stackMode: StackDisplayMode? = nil, stackSort: StackSortOrder? = nil)
    {
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

    // State of the macOS Dock before DockerDoor hid it; -1 = key was not set.
    static let customDockSystemDockHidden = Key<Bool>("customDockSystemDockHidden", default: false)
    static let customDockSavedSystemAutohide = Key<Int>("customDockSavedSystemAutohide", default: -1)
    static let customDockSavedSystemAutohideDelay = Key<Double>("customDockSavedSystemAutohideDelay", default: -1)
}
