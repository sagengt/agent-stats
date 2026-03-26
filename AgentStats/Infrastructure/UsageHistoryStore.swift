import Foundation

// MARK: - DayFile

/// Internal container written to / read from one `YYYY-MM-DD.json` file.
private struct DayFile: Codable {
    let date: String
    let records: [UsageHistoryRecord]
}

// MARK: - UsageHistoryStore

/// Phase 4 persistent history store.
///
/// Stores `UsageHistoryRecord` values as one JSON file per calendar day at:
/// `~/Library/Application Support/AgentStats/history/YYYY-MM-DD.json`
///
/// Design decisions:
/// - Files older than 365 days are automatically pruned on every write.
/// - Records whose `schemaVersion` does not match `UsageHistoryRecord.schemaVersion`
///   are silently skipped on read (forward-compat reads can be added later).
/// - A corrupted day file is skipped entirely; an error is logged to stderr.
/// - An in-memory cache keyed on date string avoids redundant disk reads within
///   a single app session.
actor UsageHistoryStore: UsageHistoryStoreProtocol {

    // MARK: - State

    private let storageDir: URL
    private var cache: [String: [UsageHistoryRecord]] = [:]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    private static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Init

    init(storageDirectory: URL? = nil) {
        if let dir = storageDirectory {
            storageDir = dir
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            storageDir = appSupport.appendingPathComponent("AgentStats/history", isDirectory: true)
        }

        // Best-effort directory creation; failures surface at first write.
        try? FileManager.default.createDirectory(
            at: storageDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    // MARK: - UsageHistoryStoreProtocol

    func record(results: [ServiceUsageResult]) async {
        guard !results.isEmpty else { return }

        let now = Date()
        let dateString = Self.dateFormatter.string(from: now)

        let newRecords = results.map { result in
            UsageHistoryRecord(
                schemaVersion: UsageHistoryRecord.schemaVersion,
                accountKey: result.accountKey,
                displayData: result.displayData.map { CodableUsageDisplayData(from: $0) },
                recordedAt: now
            )
        }

        // Merge with existing records for today.
        var existing = cache[dateString] ?? (loadDayFile(dateString: dateString) ?? [])
        existing.append(contentsOf: newRecords)
        cache[dateString] = existing

        saveDayFile(dateString: dateString, records: existing)
        pruneOldFiles()
    }

    func records(
        for service: ServiceType,
        accountKey: AccountKey?,
        since: Date,
        until: Date
    ) async -> [UsageHistoryRecord] {
        let dateStrings = dateStringsInRange(since: since, until: until)
        var result: [UsageHistoryRecord] = []

        for dateString in dateStrings {
            let dayRecords = cache[dateString] ?? (loadDayFile(dateString: dateString) ?? [])
            // Populate cache to avoid re-reading the same file in subsequent calls.
            if cache[dateString] == nil {
                cache[dateString] = dayRecords
            }

            let filtered = dayRecords.filter { record in
                guard record.serviceType == service
                        && record.schemaVersion == UsageHistoryRecord.schemaVersion
                        && record.recordedAt >= since
                        && record.recordedAt <= until
                else { return false }

                if let key = accountKey {
                    return record.accountKey == key
                }
                return true
            }
            result.append(contentsOf: filtered)
        }

        return result.sorted { $0.recordedAt < $1.recordedAt }
    }

    func availableServices() async -> [ServiceType] {
        // Scan all cached records first, then fall back to on-disk files.
        var seen = Set<ServiceType>()

        for records in cache.values {
            records.forEach { seen.insert($0.serviceType) }
        }

        // Also check files not yet in cache.
        let uncachedDates = onDiskDateStrings().filter { cache[$0] == nil }
        for dateString in uncachedDates {
            if let records = loadDayFile(dateString: dateString) {
                cache[dateString] = records
                records.forEach { seen.insert($0.serviceType) }
            }
        }

        return ServiceType.allCases.filter { seen.contains($0) }
    }

    // MARK: - Private helpers

    /// Loads and decodes a single day file. Returns `nil` on missing or unreadable files.
    private func loadDayFile(dateString: String) -> [UsageHistoryRecord]? {
        let url = fileURL(for: dateString)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            let day = try Self.jsonDecoder.decode(DayFile.self, from: data)
            // Filter incompatible schema versions.
            let compatible = day.records.filter {
                $0.schemaVersion == UsageHistoryRecord.schemaVersion
            }
            return compatible
        } catch {
            fputs("[UsageHistoryStore] Failed to read \(url.lastPathComponent): \(error)\n", stderr)
            return nil
        }
    }

    /// Encodes and writes records for a given day to disk.
    private func saveDayFile(dateString: String, records: [UsageHistoryRecord]) {
        let day = DayFile(date: dateString, records: records)
        let url = fileURL(for: dateString)
        do {
            let data = try Self.jsonEncoder.encode(day)
            try data.write(to: url, options: .atomic)
        } catch {
            fputs("[UsageHistoryStore] Failed to write \(url.lastPathComponent): \(error)\n", stderr)
        }
    }

    /// Removes day files older than 365 days from disk and cache.
    private func pruneOldFiles() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? Date()
        let cutoffString = Self.dateFormatter.string(from: cutoff)

        let allDates = onDiskDateStrings()
        for dateString in allDates {
            // String comparison works correctly for ISO-format dates.
            if dateString < cutoffString {
                let url = fileURL(for: dateString)
                try? FileManager.default.removeItem(at: url)
                cache.removeValue(forKey: dateString)
            }
        }
    }

    /// Returns all `YYYY-MM-DD` strings found as JSON filenames in `storageDir`.
    private func onDiskDateStrings() -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: storageDir,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return contents.compactMap { url -> String? in
            guard url.pathExtension == "json" else { return nil }
            let name = url.deletingPathExtension().lastPathComponent
            // Validate format with a simple length + dash check.
            guard name.count == 10,
                  name.dropFirst(4).hasPrefix("-"),
                  name.dropFirst(7).hasPrefix("-")
            else { return nil }
            return name
        }
    }

    /// Generates an ordered array of `YYYY-MM-DD` strings covering `[since, until]`.
    private func dateStringsInRange(since: Date, until: Date) -> [String] {
        var strings: [String] = []
        var cursor = Calendar.current.startOfDay(for: since)
        let end = Calendar.current.startOfDay(for: until)

        while cursor <= end {
            strings.append(Self.dateFormatter.string(from: cursor))
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return strings
    }

    /// Constructs the file URL for a given date string.
    private func fileURL(for dateString: String) -> URL {
        storageDir.appendingPathComponent("\(dateString).json")
    }
}
