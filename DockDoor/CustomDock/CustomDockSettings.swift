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

enum PinnedDockItemKind: String, Codable {
    case app
    case folder
    case file
}

struct PinnedDockItem: Codable, Hashable, Identifiable, Defaults.Serializable {
    var kind: PinnedDockItemKind
    var path: String
    var bundleIdentifier: String?

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
}

extension Defaults.Keys {
    static let customDockEnabled = Key<Bool>("customDockEnabled", default: true)
    static let customDockHideSystemDock = Key<Bool>("customDockHideSystemDock", default: true)
    static let customDockIconSize = Key<Double>("customDockIconSize", default: 48)
    static let customDockIndicatorStyle = Key<CustomDockIndicatorStyle>("customDockIndicatorStyle", default: .dot)
    static let customDockShowTrash = Key<Bool>("customDockShowTrash", default: true)
    static let customDockShowAppNames = Key<Bool>("customDockShowAppNames", default: true)
    static let customDockPinnedItems = Key<[PinnedDockItem]>("customDockPinnedItems", default: [])
    static let customDockDidImportSystemDock = Key<Bool>("customDockDidImportSystemDock", default: false)

    // State of the macOS Dock before DockerDoor hid it; -1 = key was not set.
    static let customDockSystemDockHidden = Key<Bool>("customDockSystemDockHidden", default: false)
    static let customDockSavedSystemAutohide = Key<Int>("customDockSavedSystemAutohide", default: -1)
    static let customDockSavedSystemAutohideDelay = Key<Double>("customDockSavedSystemAutohideDelay", default: -1)
}
