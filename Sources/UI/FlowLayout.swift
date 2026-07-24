import SwiftUI

/// Left-aligned wrapping layout: children keep their natural size and flow
/// onto additional rows as the container narrows. Used by RadioBar so the
/// radio controls reflow instead of clipping when the window or score panel
/// squeezes the left pane.
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 6

    /// Pure row packing (unit tested): subview indices grouped per row.
    /// An item that doesn't fit starts a new row; oversized items still get
    /// a row of their own.
    static func packRows(itemWidths: [CGFloat], containerWidth: CGFloat, spacing: CGFloat) -> [[Int]] {
        var rows: [[Int]] = []
        var current: [Int] = []
        var rowWidth: CGFloat = 0
        for (index, width) in itemWidths.enumerated() {
            let widthIfAppended = current.isEmpty ? width : rowWidth + spacing + width
            if !current.isEmpty && widthIfAppended > containerWidth {
                rows.append(current)
                current = [index]
                rowWidth = width
            } else {
                current.append(index)
                rowWidth = widthIfAppended
            }
        }
        if !current.isEmpty {
            rows.append(current)
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let container = proposal.width ?? .infinity
        let rows = Self.packRows(
            itemWidths: sizes.map(\.width),
            containerWidth: container,
            spacing: horizontalSpacing
        )
        var height: CGFloat = 0
        var widest: CGFloat = 0
        for (rowIndex, row) in rows.enumerated() {
            height += (row.map { sizes[$0].height }.max() ?? 0)
                + (rowIndex > 0 ? verticalSpacing : 0)
            let rowWidth = row.reduce(CGFloat(0)) { $0 + sizes[$1].width }
                + CGFloat(max(0, row.count - 1)) * horizontalSpacing
            widest = max(widest, rowWidth)
        }
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = Self.packRows(
            itemWidths: sizes.map(\.width),
            containerWidth: bounds.width,
            spacing: horizontalSpacing
        )
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map { sizes[$0].height }.max() ?? 0
            var x = bounds.minX
            for index in row {
                let size = sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (rowHeight - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + horizontalSpacing
            }
            y += rowHeight + verticalSpacing
        }
    }
}
