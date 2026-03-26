import SwiftUI

// MARK: - StackedBarView

/// An animated carousel that cycles through service usage results in the
/// macOS menu bar label area.
///
/// Each "slide" shows the service icon, its short name, and a compact
/// horizontal usage bar. The carousel dwells longer on the service with
/// the highest usage so the user's attention is naturally drawn to it.
///
/// Rotation stops when only one result is available (no carousel needed).
struct StackedBarView: View {

    // MARK: Input

    let results: [ServiceUsageResult]

    // MARK: State

    @State private var currentIndex: Int = 0
    @State private var timer: Timer?

    // MARK: Constants

    /// Base dwell time per slide in seconds.
    private let baseDwellSeconds: TimeInterval = 3.0
    /// Extra dwell added for the highest-usage slide.
    private let highUsageBonusSeconds: TimeInterval = 2.0
    /// Usage threshold above which a slide earns extra dwell time.
    private let highUsageThreshold: Double = 0.7

    // MARK: Body

    var body: some View {
        Group {
            if results.isEmpty {
                Label("AgentStats", systemImage: "chart.bar.fill")
                    .labelStyle(.iconOnly)
            } else if results.count == 1 {
                slideView(for: results[0])
            } else {
                slideView(for: results[currentIndex])
                    .id(currentIndex)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                    )
                    .animation(.easeInOut(duration: 0.35), value: currentIndex)
            }
        }
        .onAppear { startTimer(for: currentIndex) }
        .onDisappear { stopTimer() }
        .onChange(of: results.count) { _, _ in
            currentIndex = 0
            restartTimer()
        }
    }

    // MARK: Slide content

    @ViewBuilder
    private func slideView(for result: ServiceUsageResult) -> some View {
        HStack(spacing: 4) {
            Image(systemName: result.serviceType.iconSystemName)
                .foregroundStyle(result.serviceType.color)
                .font(.system(size: 11))

            compactBar(for: result)
                .frame(width: 40, height: 6)
        }
    }

    @ViewBuilder
    private func compactBar(for result: ServiceUsageResult) -> some View {
        let percentage = primaryPercentage(for: result)
        UsageProgressBar(
            percentage: percentage,
            color: result.serviceType.color,
            height: 6
        )
    }

    // MARK: Timer management

    private func startTimer(for index: Int) {
        stopTimer()
        guard results.count > 1 else { return }

        let dwell = dwellTime(for: safeIndex(index))
        timer = Timer.scheduledTimer(withTimeInterval: dwell, repeats: false) { _ in
            advance()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func restartTimer() {
        stopTimer()
        startTimer(for: currentIndex)
    }

    private func advance() {
        guard results.count > 1 else { return }
        let next = (currentIndex + 1) % results.count
        currentIndex = next
        startTimer(for: next)
    }

    // MARK: Helpers

    private func safeIndex(_ index: Int) -> Int {
        guard !results.isEmpty else { return 0 }
        return index % results.count
    }

    /// Returns the dwell time for `index`. High-usage slides earn extra time.
    private func dwellTime(for index: Int) -> TimeInterval {
        let result = results[index]
        let pct = primaryPercentage(for: result)
        return pct >= highUsageThreshold
            ? baseDwellSeconds + highUsageBonusSeconds
            : baseDwellSeconds
    }

    /// Returns the primary usage percentage for a result.
    /// Prefers the highest quota window; falls back to 0.
    private func primaryPercentage(for result: ServiceUsageResult) -> Double {
        result.displayData.compactMap { item -> Double? in
            if case .quota(let window) = item { return window.usedPercentage }
            return nil
        }.max() ?? 0.0
    }
}

// MARK: - Preview

#if DEBUG
private func makeResult(
    service: ServiceType,
    percentage: Double
) -> ServiceUsageResult {
    ServiceUsageResult(
        accountKey: AccountKey(serviceType: service),
        displayData: [
            .quota(QuotaWindow(
                id: "5h",
                label: "5 Hour",
                usedPercentage: percentage,
                resetAt: nil
            ))
        ],
        fetchedAt: Date()
    )
}

#Preview("Stacked Bar — multiple") {
    StackedBarView(results: [
        makeResult(service: .claude, percentage: 0.72),
        makeResult(service: .codex, percentage: 0.35),
        makeResult(service: .gemini, percentage: 0.88),
    ])
    .padding()
    .frame(width: 120, height: 24)
}

#Preview("Stacked Bar — single") {
    StackedBarView(results: [makeResult(service: .cursor, percentage: 0.5)])
        .padding()
        .frame(width: 120, height: 24)
}

#Preview("Stacked Bar — empty") {
    StackedBarView(results: [])
        .padding()
        .frame(width: 120, height: 24)
}
#endif
