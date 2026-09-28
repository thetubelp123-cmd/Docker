import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

final class CustomDockUIState: ObservableObject {
    @Published var layout: DockLayoutResult = .empty
    @Published var metrics = CustomDockMetrics(iconSize: 48, magnifiedSize: 88, magnification: true, mode: .floating)
    @Published var hoveredID: String?
    @Published var dropTargetID: String?
    @Published var isHidden = false
    @Published var isInteracting = false
    @Published var widgetPages: [String: Int] = [:]
    @Published var volumeOverlay: (id: String, value: Float)?
    /// Typed text while letter navigation is active; nil = inactive.
    @Published var letterQuery: String?
    @Published var letterSelectionID: String?
    @Published var edge: CustomDockPosition = .bottom
}

struct CustomDockView: View {
    @ObservedObject var store: CustomDockStore
    @ObservedObject var ui: CustomDockUIState
    @Default(.customDockIndicatorStyle) private var indicatorStyle
    @Default(.customDockShowAppNames) private var showAppNames
    @Default(.customDockMaterial) private var material
    @Default(.customDockTintOpacity) private var tintOpacity
    @Default(.customDockShowBorder) private var showBorder
    @Default(.customDockShowBadges) private var showBadges
    @ObservedObject private var badgeMonitor = DockBadgeMonitor.shared
    @State private var barIsDropTarget = false

    private var metrics: CustomDockMetrics { ui.metrics }

    private var spring: Animation {
        ui.isInteracting
            ? .interactiveSpring(response: 0.2, dampingFraction: 0.82, blendDuration: 0.05)
            : .spring(response: 0.34, dampingFraction: 0.8)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            barBackground
                .frame(width: max(0, ui.layout.barRect.width), height: max(0, ui.layout.barRect.height))
                .onDrop(of: [UTType.fileURL], isTargeted: $barIsDropTarget) { providers in
                    DockDropLoader.loadURLs(from: providers) { urls in
                        for url in urls {
                            store.pin(url: url)
                        }
                    }
                    return true
                }
                .position(x: ui.layout.barRect.midX, y: ui.layout.barRect.midY)

            if let frame = ui.layout.frames["separator-0"] {
                Rectangle()
                    .fill(Color.primary.opacity(0.25))
                    .frame(width: ui.edge.isVertical ? frame.width : 1, height: ui.edge.isVertical ? 1 : frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }

            ForEach(store.allTiles) { tile in
                if let frame = ui.layout.frames[tile.id] {
                    tileView(tile, frame: frame)
                }
            }

            if let query = ui.letterQuery {
                let selected = ui.letterSelectionID.flatMap { id in store.allTiles.first { $0.id == id } }
                let frame = ui.letterSelectionID.flatMap { ui.layout.frames[$0] }
                LetterQueryLabel(query: query, name: selected?.name)
                    .modifier(BesideTile(edge: ui.edge, frame: frame ?? ui.layout.barRect, gap: 24))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            } else if showAppNames, let hoveredID = ui.hoveredID,
                      let tile = store.allTiles.first(where: { $0.id == hoveredID }), tile.kind != .widget, tile.kind != .spacer,
                      let frame = ui.layout.frames[hoveredID]
            {
                NameLabel(text: tile.name)
                    .modifier(BesideTile(edge: ui.edge, frame: frame, gap: 22))
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .id("label-\(hoveredID)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .offset(
            x: ui.isHidden ? (ui.edge == .left ? -metrics.hiddenOffset : ui.edge == .right ? metrics.hiddenOffset : 0) : 0,
            y: ui.isHidden && ui.edge == .bottom ? metrics.hiddenOffset : 0
        )
        .opacity(ui.isHidden ? 0 : 1)
        .animation(spring, value: ui.layout)
        .animation(.easeInOut(duration: 0.25), value: ui.isHidden)
        .animation(.easeOut(duration: 0.12), value: ui.hoveredID)
    }

    @ViewBuilder
    private var barBackground: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
        ZStack {
            switch material {
            case .liquidGlass:
                if #available(macOS 26.0, *) {
                    LiquidGlassRepresentable(
                        cornerRadius: metrics.cornerRadius,
                        glassOpacity: 1,
                        tintOpacity: CGFloat(tintOpacity),
                        blurRadius: 0,
                        saturation: 1.8,
                        variant: 4
                    )
                } else {
                    DockVisualEffectView().clipShape(shape)
                }
            case .frosted:
                DockVisualEffectView().clipShape(shape)
                shape.fill(Color(nsColor: .windowBackgroundColor).opacity(tintOpacity))
            case .solid:
                shape.fill(Color(nsColor: .windowBackgroundColor))
            case .clear:
                shape.fill(Color.primary.opacity(tintOpacity * 0.5))
            }
            shape.fill(Color.white.opacity(barIsDropTarget ? 0.12 : 0))
            if showBorder {
                shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
            }
        }
        .shadow(color: .black.opacity(material == .clear ? 0 : 0.22), radius: 10, y: 3)
    }

    @ViewBuilder
    private func tileView(_ tile: DockTile, frame: CGRect) -> some View {
        if tile.kind == .widget {
            DockWidgetTileView(
                tile: tile,
                page: ui.widgetPages[tile.id] ?? 0,
                size: frame.size,
                volume: ui.volumeOverlay?.id == tile.id ? ui.volumeOverlay?.value : nil
            )
            .scaleEffect(ui.dropTargetID == tile.id || ui.letterSelectionID == tile.id ? 1.1 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: ui.dropTargetID == tile.id || ui.letterSelectionID == tile.id)
            .position(x: frame.midX, y: frame.midY)
            .transition(.scale(scale: 0.3).combined(with: .opacity))
        } else if tile.kind == .control {
            ControlTileView(symbol: tile.bundleIdentifier ?? "slider.horizontal.3", size: frame.size)
                .position(x: frame.midX, y: frame.midY)
                .transition(.opacity)
        } else if tile.kind == .spacer {
            DockSpacerView(
                style: tile.spacerStyle ?? .space,
                vertical: ui.edge.isVertical,
                highlighted: tile.isPinned && (ui.hoveredID == tile.id || ui.letterSelectionID == tile.id)
            )
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .transition(.opacity)
        } else {
            iconTileView(tile, frame: frame)
        }
    }

    @ViewBuilder
    private func iconTileView(_ tile: DockTile, frame: CGRect) -> some View {
        DockTileView(
            tile: tile,
            icon: store.icon(for: tile),
            size: frame.width,
            baseSize: metrics.iconSize,
            indicatorStyle: indicatorStyle,
            indicatorOffset: metrics.paddingBottom / 2 + 2,
            edge: ui.edge,
            isDropTarget: ui.dropTargetID == tile.id || ui.letterSelectionID == tile.id,
            isLaunching: store.launchingIDs.contains(tile.id)
        )
        .frame(width: frame.width, height: frame.height)
        .overlay(alignment: .topTrailing) {
            if showBadges, let badge = badgeMonitor.badge(for: tile) {
                DockBadgeView(text: badge, size: frame.width)
                    .offset(x: frame.width * 0.1, y: -frame.width * 0.06)
                    .allowsHitTesting(false)
                    .transition(.scale.combined(with: .opacity))
            }
        }
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
        .position(x: frame.midX, y: frame.midY)
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
            guard let folder = tile.url else { return false }
            DockDropLoader.loadURLs(from: providers) { urls in
                for url in urls {
                    let destination = folder.appendingPathComponent(url.lastPathComponent)
                    guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
                    try? FileManager.default.copyItem(at: url, to: destination)
                }
            }
            return true
        case .group:
            DockDropLoader.loadURLs(from: providers) { urls in
                for url in urls where url.pathExtension == "app" {
                    store.add(appURL: url, toGroup: tile.id)
                }
            }
            return true
        case .file, .widget, .control, .spacer, .minimized:
            return false
        }
    }
}

/// Empty space or a divider line between dock items.
private struct DockSpacerView: View {
    let style: DockSpacerStyle
    let vertical: Bool
    let highlighted: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                if style == .line {
                    let length = (vertical ? size.width : size.height) * 0.62
                    Capsule()
                        .fill(Color.primary.opacity(0.28))
                        .frame(width: vertical ? length : 1.2, height: vertical ? 1.2 : length)
                }
                if highlighted {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .padding(3)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
        }
    }
}

private struct LetterQueryLabel: View {
    let query: String
    let name: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard")
                .foregroundStyle(.secondary)
            if query.isEmpty {
                Text(name ?? "Buchstaben tippen …")
                    .font(.system(size: 13, weight: .medium))
            } else {
                Text(query)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(name == nil ? Color.red : Color.accentColor)
                if let name {
                    Text(name).font(.system(size: 13, weight: .medium))
                }
            }
            Text("←→ · ↩ · ⎋")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .fixedSize()
    }
}

/// Places a label next to a dock tile, on the side facing away from the screen edge.
private struct BesideTile: ViewModifier {
    let edge: CustomDockPosition
    let frame: CGRect
    let gap: CGFloat

    func body(content: Content) -> some View {
        switch edge {
        case .bottom:
            content.position(x: frame.midX, y: max(16, frame.minY - gap))
        case .left:
            content
                .frame(width: 180, alignment: .leading)
                .position(x: frame.maxX + 8 + 90, y: frame.midY)
        case .right:
            content
                .frame(width: 180, alignment: .trailing)
                .position(x: frame.minX - 8 - 90, y: frame.midY)
        }
    }
}

private struct NameLabel: View {
    let text: String

    var body: some View {
        Text(text)
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
    }
}

struct DockTileView: View {
    let tile: DockTile
    let icon: NSImage
    let size: CGFloat
    let baseSize: CGFloat
    let indicatorStyle: CustomDockIndicatorStyle
    let indicatorOffset: CGFloat
    var edge: CustomDockPosition = .bottom
    let isDropTarget: Bool
    let isLaunching: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isLaunching)) { context in
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .brightness(isDropTarget ? 0.12 : 0)
                .scaleEffect(isDropTarget ? 1.12 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDropTarget)
                .opacity(tile.isHidden ? 0.55 : 1)
                .offset(bounceOffset(at: context.date))
        }
        .background(cardBackground)
        .overlay(alignment: indicatorAlignment) { runningDot }
        .contentShape(Rectangle())
    }

    /// Launch bounce, always away from the screen edge.
    private func bounceOffset(at date: Date) -> CGSize {
        guard isLaunching else { return .zero }
        let t = date.timeIntervalSinceReferenceDate
        let amount = abs(sin(t * .pi * 1.6)) * baseSize * 0.3
        return switch edge {
        case .bottom: CGSize(width: 0, height: -amount)
        case .left: CGSize(width: amount, height: 0)
        case .right: CGSize(width: -amount, height: 0)
        }
    }

    private var indicatorAlignment: Alignment {
        switch edge {
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if indicatorStyle == .card, tile.isRunning {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Color.primary.opacity(tile.isActive ? 0.2 : 0.12))
                .padding(-size * 0.07)
        }
    }

    @ViewBuilder
    private var runningDot: some View {
        if indicatorStyle == .dot, tile.isRunning {
            Circle()
                .fill(Color.primary.opacity(0.75))
                .frame(width: 4, height: 4)
                .offset(
                    x: edge == .left ? -indicatorOffset : edge == .right ? indicatorOffset : 0,
                    y: edge == .bottom ? indicatorOffset : 0
                )
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
