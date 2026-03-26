import SwiftUI

// MARK: - UsageDonutView

/// A circular donut chart that visualises a single quota percentage.
///
/// The arc sweeps clockwise from the 12 o'clock position. A percentage label
/// is centred inside the ring. The stroke colour follows the same green →
/// orange → red threshold progression used by `UsageProgressBar`.
struct UsageDonutView: View {

    /// Fraction consumed, in the range `0.0 – 1.0`. Values are clamped.
    let usedPercentage: Double

    /// Outer diameter of the donut in points.
    let size: CGFloat

    /// Optional explicit colour override. When `nil` threshold colours apply.
    var color: Color? = nil

    // MARK: Private constants

    private var strokeWidth: CGFloat { max(4, size * 0.12) }
    private var fontSize: CGFloat { max(8, size * 0.22) }

    // MARK: Body

    var body: some View {
        let clamped = max(0.0, min(1.0, usedPercentage))
        let fillColor = color ?? thresholdColor(for: clamped)
        let pctInt = Int((clamped * 100).rounded())

        ZStack {
            // Background track
            Circle()
                .stroke(fillColor.opacity(0.15), lineWidth: strokeWidth)

            // Usage arc
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    fillColor,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: clamped)

            // Percentage label
            Text("\(pctInt)%")
                .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(fillColor)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(width: size, height: size)
    }

    // MARK: Private helpers

    private func thresholdColor(for percentage: Double) -> Color {
        switch percentage {
        case ..<0.5:  return .green
        case ..<0.8:  return .orange
        default:      return .red
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Usage Donut") {
    HStack(spacing: 16) {
        ForEach([0.1, 0.45, 0.72, 0.91], id: \.self) { pct in
            VStack(spacing: 6) {
                UsageDonutView(usedPercentage: pct, size: 56)
                Text("\(Int(pct * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        // Small variant
        UsageDonutView(usedPercentage: 0.65, size: 32, color: .blue)
    }
    .padding()
}
#endif
