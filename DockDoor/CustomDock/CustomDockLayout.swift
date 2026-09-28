import CoreGraphics
import Foundation

struct CustomDockMetrics: Equatable {
    let iconSize: CGFloat
    let magnifiedSize: CGFloat
    let magnification: Bool
    let mode: CustomDockLayoutMode

    var spacing: CGFloat { max(2, iconSize * 0.1) }
    var paddingH: CGFloat { max(6, iconSize * 0.16) }
    var paddingTop: CGFloat { max(4, iconSize * 0.12) }
    var paddingBottom: CGFloat { max(6, iconSize * 0.18) }
    var separatorWidth: CGFloat { max(9, iconSize * 0.3) }
    var barHeight: CGFloat { iconSize + paddingTop + paddingBottom }
    var cornerRadius: CGFloat { mode == .edgeToEdge ? 0 : min(barHeight * 0.34, 26) }
    var bottomMargin: CGFloat { mode == .edgeToEdge ? 0 : 4 }
    var maxScale: CGFloat { magnification ? max(1, magnifiedSize / iconSize) : 1 }
    var headroom: CGFloat { iconSize * (maxScale - 1) + 48 }
    var panelHeight: CGFloat { bottomMargin + barHeight + headroom }
    /// Distance (in icon slots) over which neighbours still grow.
    var magnificationRange: CGFloat { 3 }
    /// How far the dock slides down when auto-hidden.
    var hiddenOffset: CGFloat { barHeight + bottomMargin + 12 }
}

enum DockLayoutElement: Equatable {
    case tile(String)
    case separator(Int)

    var id: String {
        switch self {
        case let .tile(id): id
        case let .separator(index): "separator-\(index)"
        }
    }
}

/// Positions of everything in the dock window. Coordinates use a top-left origin
/// inside the dock window, like SwiftUI.
struct DockLayoutResult: Equatable {
    var frames: [String: CGRect] = [:]
    var barRect: CGRect = .zero
    var baseBarRect: CGRect = .zero

    static let empty = DockLayoutResult()

    func tileID(at point: CGPoint, spacing: CGFloat) -> String? {
        for (id, frame) in frames where !id.hasPrefix("separator-") {
            if point.x >= frame.minX - spacing / 2, point.x < frame.maxX + spacing / 2,
               point.y >= min(frame.minY, barRect.minY) - 2, point.y <= barRect.maxY
            {
                return id
            }
        }
        return nil
    }

    /// Bar plus everything that currently sticks out of it (magnified icons).
    var contentRect: CGRect {
        frames.values.reduce(barRect) { $0.union($1) }
    }
}

enum CustomDockLayoutEngine {
    static func layout(
        appIDs: [String],
        otherIDs: [String],
        size: CGSize,
        metrics: CustomDockMetrics,
        mouseX: CGFloat?,
        widthFactors: [String: CGFloat] = [:]
    ) -> DockLayoutResult {
        let barBottom = size.height - metrics.bottomMargin
        let barTop = barBottom - metrics.barHeight
        let iconBottom = barBottom - metrics.paddingBottom

        var elements: [DockLayoutElement] = appIDs.map { .tile($0) }
        var othersElements: [DockLayoutElement] = []
        if !otherIDs.isEmpty {
            othersElements = [.separator(0)] + otherIDs.map { .tile($0) }
        }

        var result = DockLayoutResult()

        switch metrics.mode {
        case .floating:
            elements += othersElements
            let block = layoutBlock(elements, anchorCenterX: size.width / 2, containerWidth: size.width, metrics: metrics, mouseX: mouseX, widthFactors: widthFactors)
            for (id, placed) in block.items {
                result.frames[id] = CGRect(x: placed.minX, y: iconBottom - placed.height, width: placed.width, height: placed.height)
            }
            let baseWidth = block.baseWidth + metrics.paddingH * 2
            result.baseBarRect = CGRect(x: (size.width - baseWidth) / 2, y: barTop, width: baseWidth, height: metrics.barHeight)
            result.barRect = CGRect(
                x: block.renderedMinX - metrics.paddingH,
                y: barTop,
                width: block.renderedWidth + metrics.paddingH * 2,
                height: metrics.barHeight
            )
        case .edgeToEdge:
            let apps = layoutBlock(elements, anchorCenterX: size.width / 2, containerWidth: size.width, metrics: metrics, mouseX: mouseX, widthFactors: widthFactors)
            for (id, placed) in apps.items {
                result.frames[id] = CGRect(x: placed.minX, y: iconBottom - placed.height, width: placed.width, height: placed.height)
            }
            if !othersElements.isEmpty {
                let othersBase = baseWidth(of: othersElements, metrics: metrics, widthFactors: widthFactors)
                let center = size.width - metrics.paddingH - othersBase / 2
                let others = layoutBlock(othersElements, anchorCenterX: center, containerWidth: size.width, metrics: metrics, mouseX: mouseX, rightAligned: true, widthFactors: widthFactors)
                for (id, placed) in others.items {
                    result.frames[id] = CGRect(x: placed.minX, y: iconBottom - placed.height, width: placed.width, height: placed.height)
                }
            }
            result.baseBarRect = CGRect(x: 0, y: barTop, width: size.width, height: metrics.barHeight)
            result.barRect = result.baseBarRect
        }

        // Separators keep the bar height instead of growing.
        for (id, frame) in result.frames where id.hasPrefix("separator-") {
            let height = metrics.iconSize * 0.78
            result.frames[id] = CGRect(x: frame.minX, y: iconBottom - metrics.iconSize / 2 - height / 2, width: frame.width, height: height)
        }
        return result
    }

    private struct PlacedItem {
        var minX: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    private struct BlockResult {
        var items: [(String, PlacedItem)]
        var baseWidth: CGFloat
        var renderedMinX: CGFloat
        var renderedWidth: CGFloat
    }

    private static func elementWidth(_ element: DockLayoutElement, metrics: CustomDockMetrics, widthFactors: [String: CGFloat]) -> CGFloat {
        switch element {
        case .separator: metrics.separatorWidth
        case let .tile(id): metrics.iconSize * (widthFactors[id] ?? 1)
        }
    }

    private static func baseWidth(of elements: [DockLayoutElement], metrics: CustomDockMetrics, widthFactors: [String: CGFloat]) -> CGFloat {
        guard !elements.isEmpty else { return 0 }
        let widths = elements.map { elementWidth($0, metrics: metrics, widthFactors: widthFactors) }
        return widths.reduce(0, +) + metrics.spacing * CGFloat(elements.count - 1)
    }

    /// Lays out one row of items. With magnification the item under the pointer
    /// stays under the pointer while its neighbours grow and push outwards.
    private static func layoutBlock(
        _ elements: [DockLayoutElement],
        anchorCenterX: CGFloat,
        containerWidth: CGFloat,
        metrics: CustomDockMetrics,
        mouseX: CGFloat?,
        rightAligned: Bool = false,
        widthFactors: [String: CGFloat]
    ) -> BlockResult {
        guard !elements.isEmpty else {
            return BlockResult(items: [], baseWidth: 0, renderedMinX: anchorCenterX, renderedWidth: 0)
        }
        let spacing = metrics.spacing
        let baseWidths = elements.map { elementWidth($0, metrics: metrics, widthFactors: widthFactors) }
        let totalBase = baseWidths.reduce(0, +) + spacing * CGFloat(elements.count - 1)
        let baseStart = anchorCenterX - totalBase / 2

        var baseLefts: [CGFloat] = []
        var cursor = baseStart
        for width in baseWidths {
            baseLefts.append(cursor)
            cursor += width + spacing
        }

        var renderedWidths = baseWidths
        var renderedHeights = elements.map { _ in metrics.iconSize }
        if let mouseX, metrics.maxScale > 1 {
            let slot = metrics.iconSize + spacing
            for (index, element) in elements.enumerated() {
                guard case .tile = element else { continue }
                let left = baseLefts[index], right = left + baseWidths[index]
                // Wide tiles count as "under the pointer" along their whole width.
                let nearest = min(max(mouseX, left + metrics.iconSize / 2), right - metrics.iconSize / 2)
                let distance = abs(mouseX - nearest) / slot
                guard distance < metrics.magnificationRange else { continue }
                let falloff = (cos(.pi * distance / metrics.magnificationRange) + 1) / 2
                let scale = 1 + (metrics.maxScale - 1) * falloff
                renderedWidths[index] = baseWidths[index] * scale
                renderedHeights[index] = metrics.iconSize * scale
            }
        }
        let totalRendered = renderedWidths.reduce(0, +) + spacing * CGFloat(elements.count - 1)

        var renderedStart: CGFloat
        if let mouseX, mouseX >= baseStart, mouseX <= baseStart + totalBase, totalRendered != totalBase {
            // Keep the point under the pointer fixed.
            var index = baseLefts.lastIndex(where: { $0 <= mouseX }) ?? 0
            index = min(index, elements.count - 1)
            let fraction = min(1, max(0, (mouseX - baseLefts[index]) / baseWidths[index]))
            var renderedBefore: CGFloat = 0
            for i in 0 ..< index {
                renderedBefore += renderedWidths[i] + spacing
            }
            renderedStart = mouseX - (renderedBefore + fraction * renderedWidths[index])
        } else if rightAligned {
            renderedStart = baseStart + totalBase - totalRendered
        } else {
            renderedStart = anchorCenterX - totalRendered / 2
        }
        let margin = metrics.paddingH
        renderedStart = min(max(renderedStart, margin), max(margin, containerWidth - margin - totalRendered))

        var items: [(String, PlacedItem)] = []
        var x = renderedStart
        for (index, element) in elements.enumerated() {
            items.append((element.id, PlacedItem(minX: x, width: renderedWidths[index], height: renderedHeights[index])))
            x += renderedWidths[index] + spacing
        }
        return BlockResult(items: items, baseWidth: totalBase, renderedMinX: renderedStart, renderedWidth: totalRendered)
    }
}
