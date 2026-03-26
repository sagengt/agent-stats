import SwiftUI

// MARK: - CycleHeatmapView

/// A 7-day cycle consistency heatmap showing average usage intensity per weekday.
///
/// Each row represents one weekday (Monday through Sunday). The bar width and
/// cell color indicate the average usage intensity for that day of the week
/// across the selected date range.
struct CycleHeatmapView: View {

    /// Seven cells ordered Monday (index 0) through Sunday (index 6).
    let cells: [HeatmapCell]
    var barColor: Color = .accentColor

    private let rowHeight: CGFloat = 22
    private let barMaxWidth: CGFloat = 160
    private let labelWidth: CGFloat = 32

    private let weekdayNames: [String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Weekly Pattern")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            ForEach(Array(zip(weekdayNames, normalizedCells).enumerated()), id: \.offset) { _, pair in
                let (name, cell) = pair
                weekdayRow(label: name, cell: cell)
            }
        }
    }

    // MARK: Row

    private func weekdayRow(label: String, cell: HeatmapCell) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .trailing)

            GeometryReader { geo in
                let availableWidth = geo.size.width
                let fillWidth = availableWidth * CGFloat(cell.value)

                ZStack(alignment: .leading) {
                    // Background track.
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.12))

                    // Filled portion.
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor.opacity(0.2 + cell.value * 0.8))
                        .frame(width: max(fillWidth, cell.value > 0 ? 4 : 0))
                }
            }
            .frame(width: barMaxWidth, height: 14)

            // Percentage label.
            Text(cell.value > 0 ? String(format: "%.0f%%", cell.value * 100) : "—")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)
        }
        .frame(height: rowHeight)
    }

    // MARK: Helpers

    /// Returns cells padded / truncated to exactly 7 entries.
    private var normalizedCells: [HeatmapCell] {
        guard cells.count == 7 else {
            // Pad with empty cells if fewer than 7.
            var result = cells
            while result.count < 7 {
                let stableDate = Date(timeIntervalSinceReferenceDate: Double(result.count) * 86400)
                result.append(HeatmapCell(id: stableDate, value: 0, recordCount: 0))
            }
            return Array(result.prefix(7))
        }
        return cells
    }
}

// MARK: - Preview

#if DEBUG
#Preview("CycleHeatmapView") {
    let values: [Double] = [0.8, 0.9, 0.75, 0.85, 0.6, 0.2, 0.1]
    let cells: [HeatmapCell] = values.enumerated().map { idx, v in
        HeatmapCell(
            id: Date(timeIntervalSinceReferenceDate: Double(idx + 2) * 86400),
            value: v,
            recordCount: Int(v * 20)
        )
    }
    return CycleHeatmapView(cells: cells, barColor: .blue)
        .padding()
        .frame(width: 280)
}
#endif
