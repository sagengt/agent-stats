import Foundation

/// Actor that holds the latest fetch result for each account.
///
/// This is an in-memory store only — no persistence.
/// ViewModels subscribe via `resultStream()`, which emits the full result
/// set whenever any account is updated.
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

    private var results: [AccountKey: ServiceUsageResult] = [:]
    private var subscribers: [UUID: Subscriber] = [:]

    // MARK: - Public API

    /// Replaces or inserts each element of `newResults`, then broadcasts.
    ///
    /// Accepting a batch ensures subscribers receive one notification per
    /// refresh cycle rather than one per account.
    func update(results newResults: [ServiceUsageResult]) async {
        for result in newResults {
            results[result.accountKey] = result
        }
        broadcast()
    }

    /// Returns the most recent result for `key`, or `nil` if not yet fetched.
    func result(for key: AccountKey) async -> ServiceUsageResult? {
        results[key]
    }

    /// Returns all stored results ordered by insertion order (stable across broadcasts).
    func allResults() async -> [ServiceUsageResult] {
        Array(results.values)
    }

    /// Removes the stored result for `key`, then broadcasts the updated set.
    ///
    /// Called by `AccountManager.unregister(_:)` to clean up after account deletion.
    func remove(account key: AccountKey) async {
        results.removeValue(forKey: key)
        broadcast()
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
        let current = Array(results.values)
        if !current.isEmpty {
            continuation.yield(current)
        }
        return subscriber.id
    }

    private func removeSubscriber(id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    private func broadcast() {
        let snapshot = Array(results.values)
        AppLogger.log("[UsageResultStore] Broadcasting \(snapshot.count) result(s) to \(subscribers.count) subscriber(s)")
        for subscriber in subscribers.values {
            subscriber.continuation.yield(snapshot)
        }
    }
}
