import Carbon
import Cocoa
import Defaults

enum DockLetterShortcut: String, CaseIterable, Defaults.Serializable {
    case optionCommandD
    case controlOptionD
    case controlOptionSpace
    case optionCommandSpace
    case off

    var title: String {
        switch self {
        case .optionCommandD: "⌥⌘D"
        case .controlOptionD: "⌃⌥D"
        case .controlOptionSpace: "⌃⌥ Leertaste"
        case .optionCommandSpace: "⌥⌘ Leertaste"
        case .off: "Aus"
        }
    }

    var keyCode: UInt32? {
        switch self {
        case .optionCommandD, .controlOptionD: UInt32(kVK_ANSI_D)
        case .controlOptionSpace, .optionCommandSpace: UInt32(kVK_Space)
        case .off: nil
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .optionCommandD, .optionCommandSpace: UInt32(optionKey | cmdKey)
        case .controlOptionD, .controlOptionSpace: UInt32(controlKey | optionKey)
        case .off: 0
        }
    }
}

extension Defaults.Keys {
    static let customDockLetterShortcut = Key<DockLetterShortcut>("customDockLetterShortcut", default: .optionCommandD)
}

/// A system-wide keyboard shortcut via Carbon hot keys (no event tap involved).
final class GlobalHotKey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handlerRef: EventHandlerRef?
    private static var nextID: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        Self.installHandlerIfNeeded()
        id = Self.nextID
        Self.nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x444B_4452), id: id) // "DKDR"
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr, hotKeyRef != nil else {
            DockerDoorLog.write("Tastenkürzel konnte nicht registriert werden (Status \(status)) – evtl. schon belegt")
            return nil
        }
        Self.actions[id] = action
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        Self.actions[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr, let action = GlobalHotKey.actions[hotKeyID.id] else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { action() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}

enum LetterSearch {
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    /// Finds the tile for a typed query. Repeating one letter ("sss") cycles through
    /// the tiles starting with that letter, like in the Finder.
    static func match(_ query: String, in tiles: [DockTile]) -> DockTile? {
        let folded = fold(query)
        guard !folded.isEmpty else { return nil }
        if let prefix = tiles.first(where: { fold($0.name).hasPrefix(folded) }) {
            if folded.count > 1, Set(folded).count == 1 {
                return cycle(folded, tiles) ?? prefix
            }
            return prefix
        }
        if folded.count > 1, Set(folded).count == 1, let cycled = cycle(folded, tiles) {
            return cycled
        }
        return tiles.first { fold($0.name).contains(folded) }
    }

    private static func cycle(_ folded: String, _ tiles: [DockTile]) -> DockTile? {
        let letter = String(folded.first!)
        let candidates = tiles.filter { fold($0.name).hasPrefix(letter) }
        guard !candidates.isEmpty else { return nil }
        return candidates[(folded.count - 1) % candidates.count]
    }
}
