import Cocoa
import Defaults
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct StackEntry: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isApp: Bool
    let dateAdded: Date?
    let dateModified: Date?
    let dateCreated: Date?
    let typeIdentifier: String?

    var id: String { url.path }
}

/// Everything the stack popup shows: a folder's contents or the apps of a group.
final class StackModel: ObservableObject {
    enum Source: Equatable {
        case folder(URL)
        case group(id: String, members: [PinnedGroupMember])
    }

    let tileID: String
    let rootSource: Source
    @Published var mode: StackDisplayMode
    @Published var sort: StackSortOrder
    @Published private(set) var entries: [StackEntry] = []
    @Published private(set) var folderPath: [URL] = []
    @Published var title: String

    var onClose: (() -> Void)?
    var onModeChange: ((StackDisplayMode) -> Void)?
    var onRemoveMember: ((String) -> Void)?

    init(tileID: String, source: Source, title: String, mode: StackDisplayMode, sort: StackSortOrder) {
        self.tileID = tileID
        rootSource = source
        self.title = title
        self.mode = mode
        self.sort = sort
        reload()
    }

    var isGroup: Bool {
        if case .group = rootSource { return true }
        return false
    }

    var currentFolder: URL? {
        if let last = folderPath.last { return last }
        if case let .folder(url) = rootSource { return url }
        return nil
    }

    func reload() {
        switch rootSource {
        case let .group(_, members):
            entries = members.map { member in
                StackEntry(
                    url: member.url,
                    name: FileManager.default.displayName(atPath: member.path).replacingOccurrences(of: ".app", with: ""),
                    isDirectory: false,
                    isApp: true,
                    dateAdded: nil,
                    dateModified: nil,
                    dateCreated: nil,
                    typeIdentifier: UTType.application.identifier
                )
            }
        case .folder:
            guard let folder = currentFolder else { return }
            entries = Self.contents(of: folder, sort: sort)
        }
    }

    func open(_ entry: StackEntry) {
        if entry.isApp {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: entry.url, configuration: configuration, completionHandler: nil)
            onClose?()
        } else if entry.isDirectory, mode != .fan {
            folderPath.append(entry.url)
            title = entry.name
            reload()
        } else {
            NSWorkspace.shared.open(entry.url)
            onClose?()
        }
    }

    func goBack() {
        guard !folderPath.isEmpty else { return }
        folderPath.removeLast()
        if let folder = currentFolder {
            title = FileManager.default.displayName(atPath: folder.path)
        }
        reload()
    }

    func openInFinder() {
        guard let folder = currentFolder else { return }
        NSWorkspace.shared.open(folder)
        onClose?()
    }

    static func contents(of folder: URL, sort: StackSortOrder) -> [StackEntry] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isPackageKey, .localizedNameKey, .addedToDirectoryDateKey,
            .contentModificationDateKey, .creationDateKey, .typeIdentifierKey,
        ]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        let entries: [StackEntry] = urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isPackage = values?.isPackage ?? false
            return StackEntry(
                url: url,
                name: values?.localizedName ?? url.lastPathComponent,
                isDirectory: (values?.isDirectory ?? false) && !isPackage,
                isApp: url.pathExtension == "app",
                dateAdded: values?.addedToDirectoryDate,
                dateModified: values?.contentModificationDate,
                dateCreated: values?.creationDate,
                typeIdentifier: values?.typeIdentifier
            )
        }
        switch sort {
        case .name:
            return entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .dateAdded:
            return entries.sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
        case .dateModified:
            return entries.sorted { ($0.dateModified ?? .distantPast) > ($1.dateModified ?? .distantPast) }
        case .dateCreated:
            return entries.sorted { ($0.dateCreated ?? .distantPast) > ($1.dateCreated ?? .distantPast) }
        case .kind:
            return entries.sorted {
                let lhs = $0.typeIdentifier ?? "", rhs = $1.typeIdentifier ?? ""
                return lhs == rhs ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : lhs < rhs
            }
        }
    }
}

// MARK: - Panel

final class StackPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        (delegate as? StackPanelController)?.close()
    }
}

final class StackPanelController: NSObject, NSWindowDelegate {
    private var panel: StackPanel?
    private var model: StackModel?
    private var outsideMonitor: Any?
    private var localMonitor: Any?

    var openTileID: String? { model?.tileID }
    var isOpen: Bool { panel != nil }
    var panelFrame: CGRect? { panel?.frame }

    /// - Parameter anchor: the dock icon in screen coordinates.
    private var edge: CustomDockPosition = .bottom

    func show(_ model: StackModel, anchor: CGRect, screen: NSScreen, edge: CustomDockPosition = .bottom, ignoringClicksIn dockWindow: NSWindow?) {
        self.edge = edge
        close()
        self.model = model
        model.onClose = { [weak self] in self?.close() }

        let panel = StackPanel()
        panel.delegate = self
        let hosting = NSHostingView(rootView: StackView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
        layout(anchor: anchor, screen: screen)

        let externalModeChange = model.onModeChange
        model.onModeChange = { [weak self] mode in
            externalModeChange?(mode)
            self?.layout(anchor: anchor, screen: screen)
        }

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

    private func layout(anchor: CGRect, screen: NSScreen) {
        guard let panel, let model else { return }
        let size = StackView.panelSize(for: model)
        var x: CGFloat = switch model.mode {
        case .fan:
            // The icon column sits at the right edge, names grow to the left.
            anchor.midX - (size.width - StackView.fanColumnInset)
        case .grid, .list:
            anchor.midX - size.width / 2
        }
        let visible = screen.visibleFrame
        var y = min(anchor.maxY + 6, visible.maxY - size.height)
        switch edge {
        case .bottom:
            break
        case .left:
            x = anchor.maxX + 6
            y = anchor.midY - size.height / 2
        case .right:
            x = anchor.minX - size.width - 6
            y = anchor.midY - size.height / 2
        }
        x = min(max(x, screen.frame.minX + 6), screen.frame.maxX - size.width - 6)
        y = min(max(y, visible.minY + 6), visible.maxY - size.height)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    func close() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        outsideMonitor = nil
        localMonitor = nil
        guard let panel else { return }
        self.panel = nil
        model = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.contentView = nil
        })
    }
}

// MARK: - Views

struct StackView: View {
    @ObservedObject var model: StackModel

    static let fanRowHeight: CGFloat = 54
    static let fanIconSize: CGFloat = 46
    static let fanColumnInset: CGFloat = 44
    static let fanLimit = 12
    static let gridCell = CGSize(width: 92, height: 96)
    static let listRowHeight: CGFloat = 30

    static func panelSize(for model: StackModel) -> CGSize {
        let count = max(1, model.entries.count)
        switch model.mode {
        case .fan:
            let rows = min(count, fanLimit) + 1
            return CGSize(width: 440, height: CGFloat(rows) * fanRowHeight + 16)
        case .grid:
            let columns = min(max(3, Int(ceil(sqrt(Double(count))))), 6)
            let rows = Int(ceil(Double(count) / Double(columns)))
            let visibleRows = min(rows, 4)
            return CGSize(
                width: CGFloat(columns) * gridCell.width + 28,
                height: CGFloat(visibleRows) * gridCell.height + 100
            )
        case .list:
            let visibleRows = min(count, 14)
            return CGSize(width: 320, height: CGFloat(visibleRows) * listRowHeight + 100)
        }
    }

    var body: some View {
        switch model.mode {
        case .fan:
            FanStackView(model: model)
        case .grid, .list:
            PanelStackView(model: model)
        }
    }
}

private struct PanelStackView: View {
    @ObservedObject var model: StackModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            if model.entries.isEmpty {
                Text(model.isGroup ? "Keine Apps" : "Ordner ist leer")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.mode == .grid {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(StackView.gridCell.width), spacing: 0), count: columnCount), spacing: 0) {
                        ForEach(model.entries) { entry in
                            StackGridItem(entry: entry, model: model)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.entries) { entry in
                            StackListRow(entry: entry, model: model)
                        }
                    }
                    .padding(6)
                }
            }
            if !model.isGroup {
                Divider().opacity(0.5)
                Button {
                    model.openInFinder()
                } label: {
                    Label("Im Finder öffnen", systemImage: "folder")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(height: 32)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(4)
    }

    private var columnCount: Int {
        min(max(3, Int(ceil(sqrt(Double(max(1, model.entries.count)))))), 6)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if !model.folderPath.isEmpty {
                Button {
                    model.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
            }
            Text(model.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer()
            StackModePicker(model: model)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }
}

private struct StackModePicker: View {
    @ObservedObject var model: StackModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(StackDisplayMode.allCases, id: \.self) { mode in
                Button {
                    model.mode = mode
                    model.onModeChange?(mode)
                } label: {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.primary.opacity(model.mode == mode ? 0.14 : 0))
                        )
                }
                .buttonStyle(.plain)
                .help(mode.title)
            }
        }
    }
}

private struct FanStackView: View {
    @ObservedObject var model: StackModel
    @State private var appeared = false

    private var visibleEntries: [StackEntry] {
        Array(model.entries.prefix(StackView.fanLimit))
    }

    var body: some View {
        GeometryReader { proxy in
            let columnX = proxy.size.width - StackView.fanColumnInset
            ZStack(alignment: .topLeading) {
                ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                    let curve = pow(CGFloat(index), 1.55) * 1.6
                    let y = proxy.size.height - 8 - CGFloat(index + 1) * StackView.fanRowHeight + StackView.fanRowHeight / 2
                    FanRow(entry: entry, model: model)
                        .rotationEffect(.degrees(Double(index) * -0.9), anchor: .trailing)
                        .position(x: columnX - 150 + curve + StackView.fanIconSize / 2, y: appeared ? y : proxy.size.height)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.34, dampingFraction: 0.78).delay(Double(index) * 0.018), value: appeared)
                }
                if !model.isGroup {
                    let index = visibleEntries.count
                    let curve = pow(CGFloat(index), 1.55) * 1.6
                    let y = proxy.size.height - 8 - CGFloat(index + 1) * StackView.fanRowHeight + StackView.fanRowHeight / 2
                    Button {
                        model.openInFinder()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.forward.app")
                            Text(model.entries.count > StackView.fanLimit ? "\(model.entries.count - StackView.fanLimit) weitere im Finder" : "Im Finder öffnen")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.regularMaterial))
                    }
                    .buttonStyle(.plain)
                    .position(x: columnX - 60 + curve, y: appeared ? y : proxy.size.height)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.34, dampingFraction: 0.78).delay(Double(index) * 0.018), value: appeared)
                }
            }
        }
        .onAppear { appeared = true }
    }
}

private struct FanRow: View {
    let entry: StackEntry
    @ObservedObject var model: StackModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text(entry.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 230, alignment: .trailing)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(hovering ? Color.accentColor.opacity(0.85) : Color.black.opacity(0.55))
                )
                .foregroundStyle(.white)
            StackThumbnail(url: entry.url, size: StackView.fanIconSize)
                .scaleEffect(hovering ? 1.08 : 1)
        }
        .frame(width: 300, alignment: .trailing)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.open(entry) }
        .onDrag { NSItemProvider(object: entry.url as NSURL) }
        .contextMenu { StackEntryMenu(entry: entry, model: model) }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct StackGridItem: View {
    let entry: StackEntry
    @ObservedObject var model: StackModel
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            StackThumbnail(url: entry.url, size: 54)
            Text(entry.name)
                .font(.system(size: 11))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(width: StackView.gridCell.width - 12)
        }
        .frame(width: StackView.gridCell.width, height: StackView.gridCell.height)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.1 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.open(entry) }
        .onDrag { NSItemProvider(object: entry.url as NSURL) }
        .contextMenu { StackEntryMenu(entry: entry, model: model) }
    }
}

private struct StackListRow: View {
    let entry: StackEntry
    @ObservedObject var model: StackModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            StackThumbnail(url: entry.url, size: 20)
            Text(entry.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if entry.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: StackView.listRowHeight)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hovering ? Color.accentColor.opacity(0.8) : Color.clear)
        )
        .foregroundStyle(hovering ? Color.white : Color.primary)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.open(entry) }
        .onDrag { NSItemProvider(object: entry.url as NSURL) }
        .contextMenu { StackEntryMenu(entry: entry, model: model) }
    }
}

private struct StackEntryMenu: View {
    let entry: StackEntry
    let model: StackModel

    var body: some View {
        Button("Öffnen") { model.open(entry) }
        Button("Im Finder zeigen") {
            NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            model.onClose?()
        }
        if model.isGroup {
            Divider()
            Button("Aus Gruppe entfernen") { model.onRemoveMember?(entry.url.path) }
        } else {
            Divider()
            Button("In den Papierkorb legen") {
                try? FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
                model.reload()
            }
        }
    }
}

/// File icon that upgrades to a Quick Look thumbnail (images, PDFs, …) once available.
struct StackThumbnail: View {
    let url: URL
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Image(nsImage: image ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .task(id: url) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        guard url.pathExtension != "app" else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: scale,
            representationTypes: .thumbnail
        )
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            image = representation.nsImage
        }
    }
}
