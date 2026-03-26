import SwiftUI

// MARK: - HeatmapView

/// GitHub-style contribution heatmap showing one square per calendar day.
///
/// - `cells` must be pre-sorted oldest-first (left-to-right, top-to-bottom).
/// - The grid is always 7 rows tall (one per weekday). The number of columns
///   is derived from `cells.count` rounded up to the nearest multiple of 7.
/// - Month labels are drawn above the first column of a new month.
/// - The `columns` parameter sets how many weeks are rendered when `cells` is
///   empty; it is ignored when `cells` is non-empty.
struct HeatmapView: View {

    let cells: [HeatmapCell]
    var columns: Int = 52
    var cellColor: Color = .accentColor
    var onCellTapped: ((HeatmapCell) -> Void)? = nil

    // MARK: Layout constants

    private let cellSize: CGFloat = 11
    private let cellSpacing: CGFloat = 2
    private let rowCount: Int = 7       // always 7 rows (Mon – Sun)
    private let monthLabelHeight: CGFloat = 16
    private let weekdayLabelWidth: CGFloat = 26

    // MARK: Computed helpers

    private var effectiveColumns: Int {
        guard !cells.isEmpty else { return max(columns, 1) }
        return Int(ceil(Double(cells.count) / Double(rowCount)))
    }

    private var gridWidth: CGFloat {
        CGFloat(effectiveColumns) * (cellSize + cellSpacing) - cellSpacing
    }

    private var gridHeight: CGFloat {
        CGFloat(rowCount) * (cellSize + cellSpacing) - cellSpacing
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Month labels row
            monthLabelsRow

            HStack(alignment: .top, spacing: 4) {
                // Weekday labels
                weekdayLabelsColumn

                // The cell grid
                cellGrid
            }
        }
        .fixedSize()
    }

    // MARK: Subviews

    private var monthLabelsRow: some View {
        HStack(spacing: 0) {
            // Spacer matching weekday labels column width.
            Spacer().frame(width: weekdayLabelWidth + 4)

            ZStack(alignment: .leading) {
                ForEach(monthLabelPositions, id: \.offset) { pos in
                    Text(pos.label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .offset(x: pos.offset)
                }
            }
            .frame(width: gridWidth, height: monthLabelHeight, alignment: .topLeading)
        }
    }

    private var weekdayLabelsColumn: some View {
        VStack(alignment: .trailing, spacing: cellSpacing) {
            ForEach(0..<rowCount, id: \.self) { row in
                Text(weekdayLabel(for: row))
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(height: cellSize)
            }
        }
        .frame(width: weekdayLabelWidth)
    }

    private var cellGrid: some View {
        Canvas { context, _ in
            for colIndex in 0..<effectiveColumns {
                for rowIndex in 0..<rowCount {
                    let cellIndex = colIndex * rowCount + rowIndex
                    let cell = cellIndex < cells.count ? cells[cellIndex] : nil

                    let x = CGFloat(colIndex) * (cellSize + cellSpacing)
                    let y = CGFloat(rowIndex) * (cellSize + cellSpacing)
                    let rect = CGRect(x: x, y: y, width: cellSize, height: cellSize)
                    let path = Path(roundedRect: rect, cornerRadius: 2)

                    let intensity = cell?.value ?? 0
                    let color = intensityColor(intensity)
                    context.fill(path, with: .color(color))
                }
            }
        }
        .frame(width: gridWidth, height: gridHeight)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture()
                .onEnded { event in
                    handleTap(at: event.location)
                }
        )
    }

    // MARK: Helpers

    /// Maps an intensity value in `0.0–1.0` to an appropriate color.
    private func intensityColor(_ intensity: Double) -> Color {
        if intensity <= 0 {
            return Color(nsColor: .separatorColor).opacity(0.35)
        }
        let clamped = min(max(intensity, 0), 1)
        // Four-stop gradient: very light → saturated brand color.
        return cellColor.opacity(0.15 + clamped * 0.85)
    }

    /// Returns the abbreviated weekday label for a given row (0 = Mon, 6 = Sun).
    private func weekdayLabel(for row: Int) -> String {
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        // Only render every other label to avoid crowding.
        return row.isMultiple(of: 2) ? labels[row] : ""
    }

    /// Computes (label, x-offset) pairs for month boundary columns.
    private var monthLabelPositions: [(label: String, offset: CGFloat)] {
        guard !cells.isEmpty else { return [] }

        let cal = Calendar.current
        var positions: [(label: String, offset: CGFloat)] = []
        var lastMonth = -1

        for colIndex in 0..<effectiveColumns {
            let cellIndex = colIndex * rowCount
            guard cellIndex < cells.count else { break }
            let date = cells[cellIndex].id
            let month = cal.component(.month, from: date)
            if month != lastMonth {
                lastMonth = month
                let offset = CGFloat(colIndex) * (cellSize + cellSpacing)
                let label = shortMonthLabel(from: date)
                positions.append((label: label, offset: offset))
            }
        }
        return positions
    }

    private func shortMonthLabel(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f.string(from: date)
    }

    private func handleTap(at location: CGPoint) {
        guard let onCellTapped else { return }
        let col = Int(location.x / (cellSize + cellSpacing))
        let row = Int(location.y / (cellSize + cellSpacing))
        let idx = col * rowCount + row
        guard idx < cells.count else { return }
        onCellTapped(cells[idx])
    }
}

// MARK: - Preview

#if DEBUG
#Preview("HeatmapView") {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    let cells: [HeatmapCell] = (0..<365).reversed().map { offset in
        let day = cal.date(byAdding: .day, value: -offset, to: today)!
        let v = Double.random(in: 0...1)
        let value = v < 0.3 ? 0.0 : v  // sparse
        return HeatmapCell(id: day, value: value, recordCount: Int(value * 10))
    }
    return HeatmapView(cells: cells, cellColor: .blue)
        .padding()
}
#endif
