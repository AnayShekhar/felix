import SwiftUI

/// Simple wrapping flow layout (left-to-right, wraps to new lines). Used for the
/// per-word animated transcript on Home.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var x: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(size)
            x += size.width + spacing
        }
        var total: CGFloat = 0
        for row in rows {
            total += (row.map(\.height).max() ?? 0) + spacing
        }
        return CGSize(width: maxWidth == .infinity ? rowsWidth(rows, spacing) : maxWidth,
                      height: max(0, total - spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func rowsWidth(_ rows: [[CGSize]], _ spacing: CGFloat) -> CGFloat {
        rows.map { row in row.reduce(0) { $0 + $1.width + spacing } }.max() ?? 0
    }
}
