import SwiftUI

// MARK: - TrendChartView

/// A line chart visualising usage trend over a sequence of `TrendPoint` values.
///
/// Rendering is done entirely with SwiftUI `Path` – no external dependencies.
/// Features:
/// - Gradient fill under the line.
/// - X-axis date labels at sensible intervals.
/// - Y-axis percentage labels (0 %, 50 %, 100 %).
/// - Hover highlight showing the exact value at the nearest data point.
struct TrendChartView: View {

    let points: [TrendPoint]
    var lineColor: Color = .accentColor
    var yAxisLabel: String = "Usage %"

    // MARK: Layout

    private let chartHeight: CGFloat = 140
    private let yAxisWidth: CGFloat = 36
    private let xAxisHeight: CGFloat = 20
    private let horizontalPadding: CGFloat = 8

    // MARK: State

    @State private var hoverX: CGFloat? = nil

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let plotWidth = geo.size.width - yAxisWidth - horizontalPadding
            let plotHeight = chartHeight

            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    // Y-axis labels
                    yAxisLabels(height: plotHeight)
                        .frame(width: yAxisWidth)

                    // Chart area
                    HStack(spacing: 0) {
                        Spacer().frame(width: yAxisWidth)
                        chartArea(width: plotWidth, height: plotHeight)
                    }
                }
                .frame(height: plotHeight)

                // X-axis labels
                HStack(spacing: 0) {
                    Spacer().frame(width: yAxisWidth)
                    xAxisLabels(width: plotWidth)
                        .frame(width: plotWidth, height: xAxisHeight)
                }
            }
        }
        .frame(height: chartHeight + xAxisHeight)
    }

    // MARK: Chart Area

    @ViewBuilder
    private func chartArea(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Background grid lines.
            gridLines(width: width, height: height)

            if points.count >= 2, let maxValue = points.map(\.value).max(), maxValue > 0 {
                let scaled = scaledPoints(width: width, height: height, maxValue: maxValue)

                // Gradient fill.
                gradientFill(points: scaled, width: width, height: height)

                // Line.
                linePath(points: scaled)
                    .stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                // Hover indicator.
                if let hx = hoverX {
                    hoverIndicator(at: hx, scaledPoints: scaled, height: height, maxValue: maxValue)
                }
            } else {
                // No data placeholder.
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: width, height: height)
        .clipShape(Rectangle())
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoverX = location.x
            case .ended:
                hoverX = nil
            }
        }
    }

    // MARK: Path builders

    private func scaledPoints(width: CGFloat, height: CGFloat, maxValue: Double) -> [CGPoint] {
        guard points.count > 1 else { return [] }
        let count = CGFloat(points.count - 1)

        return points.enumerated().map { idx, point in
            let x = CGFloat(idx) / count * width
            let y = height - CGFloat(point.value / maxValue) * height
            return CGPoint(x: x, y: y)
        }
    }

    private func linePath(points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for pt in points.dropFirst() {
                path.addLine(to: pt)
            }
        }
    }

    private func gradientFill(points: [CGPoint], width: CGFloat, height: CGFloat) -> some View {
        let fillPath = Path { path in
            guard let first = points.first else { return }
            path.move(to: CGPoint(x: first.x, y: height))
            path.addLine(to: first)
            for pt in points.dropFirst() {
                path.addLine(to: pt)
            }
            if let last = points.last {
                path.addLine(to: CGPoint(x: last.x, y: height))
            }
            path.closeSubpath()
        }

        return fillPath
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [lineColor.opacity(0.35), lineColor.opacity(0.05)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    private func gridLines(width: CGFloat, height: CGFloat) -> some View {
        Path { path in
            // Horizontal grid at 0 %, 50 %, 100 %.
            for fraction in [0.0, 0.5, 1.0] {
                let y = height * (1.0 - fraction)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
            }
        }
        .stroke(Color.secondary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    // MARK: Hover indicator

    private func hoverIndicator(
        at hx: CGFloat,
        scaledPoints: [CGPoint],
        height: CGFloat,
        maxValue: Double
    ) -> AnyView {
        guard !scaledPoints.isEmpty else { return AnyView(EmptyView()) }

        // Find the nearest scaled point.
        let nearest = scaledPoints.min(by: { abs($0.x - hx) < abs($1.x - hx) })!
        let pointIndex = scaledPoints.firstIndex(where: { $0 == nearest }) ?? 0
        let rawValue = points[pointIndex].value

        return AnyView(
            ZStack {
                // Vertical rule.
                Path { path in
                    path.move(to: CGPoint(x: nearest.x, y: 0))
                    path.addLine(to: CGPoint(x: nearest.x, y: height))
                }
                .stroke(lineColor.opacity(0.5), lineWidth: 1)

                // Dot on the line.
                Circle()
                    .fill(lineColor)
                    .frame(width: 7, height: 7)
                    .position(nearest)

                // Value tooltip.
                Text(formattedValue(rawValue))
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .shadow(radius: 2)
                    )
                    .position(x: min(max(nearest.x, 28), scaledPoints.last?.x ?? nearest.x - 28),
                              y: max(nearest.y - 16, 10))
            }
        )
    }

    private func formattedValue(_ value: Double) -> String {
        if value >= 1 {
            return String(format: "%.0f%%", value * 100)
        } else if value > 0 {
            return String(format: "%.1f%%", value * 100)
        }
        return "0%"
    }

    // MARK: Axis labels

    private func yAxisLabels(height: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            ForEach([0.0, 0.5, 1.0], id: \.self) { fraction in
                let y = height * (1.0 - fraction)
                Text("\(Int(fraction * 100))%")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .offset(y: y - 6)
            }
        }
        .frame(height: height, alignment: .topLeading)
    }

    private func xAxisLabels(width: CGFloat) -> some View {
        guard !points.isEmpty else { return AnyView(EmptyView()) }

        let labelCount = min(points.count, 5)
        let step = max(1, (points.count - 1) / max(1, labelCount - 1))
        var indices: [Int] = stride(from: 0, to: points.count, by: step).map { $0 }
        if let last = indices.last, last != points.count - 1 {
            indices.append(points.count - 1)
        }

        let count = CGFloat(points.count - 1)

        return AnyView(
            ZStack(alignment: .leading) {
                ForEach(indices, id: \.self) { idx in
                    let x = count > 0 ? CGFloat(idx) / count * width : 0
                    Text(shortDateLabel(from: points[idx].id))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .offset(x: x - 14)
                }
            }
            .frame(width: width, alignment: .leading)
        )
    }

    private func shortDateLabel(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: date)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("TrendChartView") {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    let pts: [TrendPoint] = (0..<30).reversed().map { offset in
        let day = cal.date(byAdding: .day, value: -offset, to: today)!
        let v = sin(Double(offset) * 0.4) * 0.3 + 0.5 + Double.random(in: -0.1...0.1)
        return TrendPoint(id: day, value: max(0, min(1, v)))
    }
    return TrendChartView(points: pts, lineColor: .blue)
        .padding()
        .frame(width: 400)
}
#endif
