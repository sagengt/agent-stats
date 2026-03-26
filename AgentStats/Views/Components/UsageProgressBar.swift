import SwiftUI

// MARK: - UsageProgressBar

/// A horizontal progress bar that fills according to a usage percentage.
///
/// The fill colour shifts automatically through green, orange and red as the
/// percentage climbs past the 50 % and 80 % thresholds, giving the user an
/// immediate visual health signal without reading the number.
struct UsageProgressBar: View {

    /// Fraction consumed, in the range `0.0 – 1.0`. Values outside this range
    /// are clamped before rendering.
    let percentage: Double

    /// Explicit override colour. When `nil` the bar uses the threshold-based
    /// green → orange → red gradient.
    var color: Color? = nil

    /// Height of the track. Defaults to 6 pt which fits well in compact rows.
    var height: CGFloat = 6

    /// Corner radius of the track. Defaults to half the height for a pill shape.
    var cornerRadius: CGFloat? = nil

    // MARK: Body

    var body: some View {
        GeometryReader { proxy in
            let clamped = max(0.0, min(1.0, percentage))
            let fillColor = color ?? thresholdColor(for: clamped)
            let radius = cornerRadius ?? (height / 2)

            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: radius)
                    .fill(fillColor.opacity(0.15))
                    .frame(height: height)

                // Fill
                RoundedRectangle(cornerRadius: radius)
                    .fill(fillColor)
                    .frame(
                        width: max(clamped > 0 ? radius * 2 : 0,
                                   proxy.size.width * clamped),
                        height: height
                    )
                    .animation(.easeInOut(duration: 0.3), value: clamped)
            }
        }
        .frame(height: height)
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
#Preview("Usage Progress Bar") {
    VStack(spacing: 12) {
        ForEach([0.0, 0.25, 0.50, 0.75, 0.85, 1.0], id: \.self) { pct in
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Int(pct * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                UsageProgressBar(percentage: pct)
            }
        }

        // Custom colour override
        VStack(alignment: .leading, spacing: 4) {
            Text("Custom color (blue)")
                .font(.caption)
                .foregroundStyle(.secondary)
            UsageProgressBar(percentage: 0.6, color: .blue, height: 8)
        }
    }
    .padding()
    .frame(width: 280)
}
#endif
