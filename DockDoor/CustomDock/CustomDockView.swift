import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct CustomDockMetrics {
    let iconSize: CGFloat

    var spacing: CGFloat { max(2, iconSize * 0.1) }
    var paddingH: CGFloat { max(6, iconSize * 0.16) }
    var paddingTop: CGFloat { max(4, iconSize * 0.12) }
    var paddingBottom: CGFloat { max(6, iconSize * 0.18) }
    var separatorWidth: CGFloat { max(9, iconSize * 0.3) }
    var barHeight: CGFloat { iconSize + paddingTop + paddingBottom }
    var cornerRadius: CGFloat { min(barHeight * 0.34, 26) }
    var bottomMargin: CGFloat { 4 }
    var headroom: CGFloat { 48 }
    var panelHeight: CGFloat { bottomMargin + barHeight + headroom }
}

final class CustomDockUIState: ObservableObject {
    @Published var hoveredID: String?
    @Published var dropTargetID: String?
    @Published var barFrame: CGRect = .zero
}

struct CustomDockView: View {
    @ObservedObject var store: CustomDockStore
    @ObservedObject var ui: CustomDockUIState
    @Default(.customDockIconSize) private var iconSize
    @Default(.customDockIndicatorStyle) private var indicatorStyle
    @Default(.customDockShowAppNames) private var showAppNames
    @State private var barIsDropTarget = false

    private var metrics: CustomDockMetrics { CustomDockMetrics(iconSize: CGFloat(iconSize)) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            bar
                .padding(.bottom, metrics.bottomMargin)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: "dockRoot")
    }

    private var bar: some View {
        HStack(spacing: metrics.spacing) {
            ForEach(store.appTiles) { tile in
                tileView(tile)
            }
            if !store.otherTiles.isEmpty {
                separator
                ForEach(store.otherTiles) { tile in
                    tileView(tile)
                }
            }
        }
        .padding(.horizontal, metrics.paddingH)
        .padding(.top, metrics.paddingTop)
        .padding(.bottom, metrics.paddingBottom)
        .background(barBackground)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { ui.barFrame = proxy.frame(in: .named("dockRoot")) }
                    .onChange(of: proxy.frame(in: .named("dockRoot"))) { newFrame in
                        ui.barFrame = newFrame
                    }
            }
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $barIsDropTarget) { providers in
            DockDropLoader.loadURLs(from: providers) { urls in
                for url in urls { store.pin(url: url) }
            }
            return true
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: store.appTiles.map(\.id))
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: store.otherTiles.map(\.id))
    }

    private var barBackground: some View {
        ZStack {
            DockVisualEffectView()
                .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(barIsDropTarget ? 0.12 : 0))
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.25))
            .frame(width: 1, height: metrics.iconSize * 0.78)
            .frame(width: metrics.separatorWidth - metrics.spacing)
    }

    @ViewBuilder
    private func tileView(_ tile: DockTile) -> some View {
        DockTileView(
            tile: tile,
            icon: store.icon(for: tile),
            metrics: metrics,
            indicatorStyle: indicatorStyle,
            isHovered: ui.hoveredID == tile.id,
            isDropTarget: ui.dropTargetID == tile.id,
            isLaunching: store.launchingIDs.contains(tile.id),
            showName: showAppNames
        )
        .onHover { hovering in
            if hovering {
                ui.hoveredID = tile.id
            } else if ui.hoveredID == tile.id {
                ui.hoveredID = nil
            }
        }
        .onTapGesture {
            store.open(tile)
        }
        .contextMenu { contextMenu(for: tile) }
        .onDrop(of: [UTType.fileURL], isTargeted: Binding(
            get: { ui.dropTargetID == tile.id },
            set: { targeted in
                if targeted {
                    ui.dropTargetID = tile.id
                } else if ui.dropTargetID == tile.id {
                    ui.dropTargetID = nil
                }
            }
        )) { providers in
            handleDrop(providers, on: tile)
        }
        .transition(.scale(scale: 0.3).combined(with: .opacity))
    }

    private func handleDrop(_ providers: [NSItemProvider], on tile: DockTile) -> Bool {
        switch tile.kind {
        case .app:
            DockDropLoader.loadURLs(from: providers) { urls in store.open(urls: urls, with: tile) }
            return true
        case .trash:
            DockDropLoader.loadURLs(from: providers) { urls in store.moveToTrash(urls) }
            return true
        case .folder:
            if let folder = tile.url {
                DockDropLoader.loadURLs(from: providers) { urls in
                    for url in urls {
                        let destination = folder.appendingPathComponent(url.lastPathComponent)
                        guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
                        try? FileManager.default.copyItem(at: url, to: destination)
                    }
                }
                return true
            }
            return false
        case .file:
            return false
        }
    }

    @ViewBuilder
    private func contextMenu(for tile: DockTile) -> some View {
        switch tile.kind {
        case .app:
            if tile.isPinned {
                if tile.bundleIdentifier != CustomDockStore.finderBundleID {
                    Button("Aus dem Dock entfernen") { store.unpin(tile) }
                }
            } else if tile.url != nil {
                Button("Im Dock behalten") { store.pin(tile) }
            }
            if tile.url != nil {
                Button("Im Finder zeigen") { store.revealInFinder(tile) }
            }
            if tile.isRunning {
                Divider()
                Button("Ausblenden") { store.hide(tile) }
                if tile.bundleIdentifier != CustomDockStore.finderBundleID {
                    Button("Beenden") { store.quit(tile) }
                    Button("Sofort beenden") { store.quit(tile, force: true) }
                }
            }
        case .folder, .file:
            Button("Öffnen") { store.open(tile) }
            Button("Im Finder zeigen") { store.revealInFinder(tile) }
            Divider()
            Button("Aus dem Dock entfernen") { store.unpin(tile) }
        case .trash:
            Button("Öffnen") { store.open(tile) }
            Button("Papierkorb entleeren …") { confirmEmptyTrash() }
                .disabled(!store.trashIsFull)
        }
    }

    private func confirmEmptyTrash() {
        let alert = NSAlert()
        alert.messageText = "Papierkorb wirklich entleeren?"
        alert.informativeText = "Die Objekte im Papierkorb werden endgültig gelöscht."
        alert.addButton(withTitle: "Entleeren")
        alert.addButton(withTitle: "Abbrechen")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            store.emptyTrash()
        }
    }
}

struct DockTileView: View {
    let tile: DockTile
    let icon: NSImage
    let metrics: CustomDockMetrics
    let indicatorStyle: CustomDockIndicatorStyle
    let isHovered: Bool
    let isDropTarget: Bool
    let isLaunching: Bool
    let showName: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isLaunching)) { context in
            iconImage
                .offset(y: bounceOffset(at: context.date))
        }
        .frame(width: metrics.iconSize, height: metrics.iconSize)
        .background(cardBackground)
        .overlay(alignment: .bottom) { runningDot }
        .overlay(alignment: .top) { nameLabel }
        .contentShape(Rectangle())
    }

    private var iconImage: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: metrics.iconSize, height: metrics.iconSize)
            .brightness(isDropTarget ? 0.12 : 0)
            .opacity(tile.isHidden ? 0.55 : 1)
    }

    private func bounceOffset(at date: Date) -> CGFloat {
        guard isLaunching else { return 0 }
        let t = date.timeIntervalSinceReferenceDate
        return -abs(sin(t * .pi * 1.6)) * metrics.iconSize * 0.3
    }

    @ViewBuilder
    private var cardBackground: some View {
        if indicatorStyle == .card, tile.isRunning {
            RoundedRectangle(cornerRadius: metrics.iconSize * 0.24, style: .continuous)
                .fill(Color.primary.opacity(tile.isActive ? 0.2 : 0.12))
                .padding(-metrics.iconSize * 0.07)
        }
    }

    @ViewBuilder
    private var runningDot: some View {
        if indicatorStyle == .dot, tile.isRunning {
            Circle()
                .fill(Color.primary.opacity(0.75))
                .frame(width: 4, height: 4)
                .offset(y: metrics.paddingBottom / 2 + 2)
        }
    }

    @ViewBuilder
    private var nameLabel: some View {
        if showName, isHovered {
            Text(tile.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
                .alignmentGuide(.top) { d in d[.bottom] + metrics.paddingTop + 8 }
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}

struct DockVisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

enum DockDropLoader {
    static func loadURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let itemURL = item as? URL {
                    url = itemURL
                }
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
            }
        }
        group.notify(queue: .main) { completion(urls) }
    }
}
