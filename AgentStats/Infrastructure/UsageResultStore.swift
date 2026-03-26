import Foundation

/// Actor that holds the latest fetch result for each service.
///
/// This is an in-memory store only — no persistence.
/// ViewModels subscribe via `resultStream()`, which emits the full result
/// set whenever any service is updated.
actor UsageResultStore {

    // MARK: - Subscriber token

    /// Wraps an `AsyncStream.Continuation` with a stable identity so that
    /// registered subscribers can be removed by token without requiring
    /// `Equatable` or reference equality on the continuation struct.
    private final class Subscriber {
        let id = UUID()
        let continuation: AsyncStream<[ServiceUsageResult]>.Continuation
        init(continuation: AsyncStream<[ServiceUsageResult]>.Continuation) {
            self.continuation = continuation
        }
    }

    // MARK: - State

    private var results: [ServiceType: ServiceUsageResult] = [:]
    private var subscribers: [UUID: Subscriber] = [:]

    // MARK: - Public API

    /// Replaces or inserts each element of `newResults`, then broadcasts.
    ///
    /// Accepting a batch ensures subscribers receive one notification per
    /// refresh cycle rather than one per service.
    func update(results newResults: [ServiceUsageResult]) async {
        for result in newResults {
            results[result.serviceType] = result
        }
        broadcast()
    }

    /// Returns the most recent result for `service`, or `nil` if not yet fetched.
    func result(for service: ServiceType) async -> ServiceUsageResult? {
        results[service]
    }

    /// Returns all stored results ordered by `ServiceType.allCases`.
    func allResults() async -> [ServiceUsageResult] {
        ServiceType.allCases.compactMap { results[$0] }
    }

    /// Returns an `AsyncStream` that emits the full result set on every update.
    ///
    /// The stream yields the current state immediately upon subscription so
    /// new observers are synchronised without waiting for the next refresh.
    nonisolated func resultStream() -> AsyncStream<[ServiceUsageResult]> {
        AsyncStream { continuation in
            Task {
                let id = await self.addSubscriber(continuation: continuation)
                continuation.onTermination = { [weak self] _ in
                    guard let self else { return }
                    Task { await self.removeSubscriber(id: id) }
                }
            }
        }
    }

    // MARK: - Private helpers

    private func addSubscriber(
        continuation: AsyncStream<[ServiceUsageResult]>.Continuation
    ) -> UUID {
        let subscriber = Subscriber(continuation: continuation)
        subscribers[subscriber.id] = subscriber
        // Emit current state immediately.
        let current = ServiceType.allCases.compactMap { results[$0] }
        if !current.isEmpty {
            continuation.yield(current)
        }
        return subscriber.id
    }

    private func removeSubscriber(id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    private func broadcast() {
        let snapshot = ServiceType.allCases.compactMap { results[$0] }
        for subscriber in subscribers.values {
            subscriber.continuation.yield(snapshot)
        }
    }
}
