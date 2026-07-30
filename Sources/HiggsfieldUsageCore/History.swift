import Foundation

// MARK: - Transaction history

public enum HistoryMerge {
    /// Merge a freshly fetched page into the stored history. Dedupe by
    /// dedupeKey, newest first. Sorting uses the parsed date, not the raw
    /// string: the API omits the fraction when microseconds are zero, and
    /// "…:01Z" compares below "…:00.5Z" as plain text. Unparsable dates sink
    /// to the bottom; exact ties break on the raw string so order is stable.
    public static func merge(existing: [Transaction], new: [Transaction]) -> [Transaction] {
        var seen = Set<String>()
        var out: [Transaction] = []
        for tx in existing + new where seen.insert(tx.dedupeKey).inserted {
            out.append(tx)
        }
        return out.sorted { a, b in
            switch (a.date, b.date) {
            case let (x?, y?): return x == y ? a.createdAt > b.createdAt : x > y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.createdAt > b.createdAt
            }
        }
    }
}

// MARK: - Balance history

public struct BalancePoint: Codable, Equatable {
    public let timestamp: Date
    public let credits: Double
    public init(timestamp: Date, credits: Double) {
        self.timestamp = timestamp
        self.credits = credits
    }
}

public enum BalanceHistory {
    public static let keepDays: Double = 90

    /// Append unless the balance is unchanged and the last point is < 1 h old
    /// (bounds file growth at short refresh intervals). Prune > keepDays.
    public static func appendPrune(_ points: [BalancePoint], adding p: BalancePoint) -> [BalancePoint] {
        var pts = points
        let skip = pts.last.map {
            $0.credits == p.credits && p.timestamp.timeIntervalSince($0.timestamp) < 3600
        } ?? false
        if !skip { pts.append(p) }
        let cutoff = p.timestamp.addingTimeInterval(-Self.keepDays * 86400)
        return pts.filter { $0.timestamp >= cutoff }
    }
}

// MARK: - Persistence

public struct HistoryFiles {
    public let dir: URL

    public init(dir: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".higgsfield-usage-widget", isDirectory: true)) {
        self.dir = dir
    }

    public var transactionsURL: URL { dir.appendingPathComponent("transactions.json") }
    public var balanceURL: URL { dir.appendingPathComponent("balance-history.json") }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public func loadTransactions() -> [Transaction] {
        guard let data = try? Data(contentsOf: transactionsURL) else { return [] }
        return (try? Self.decoder.decode([Transaction].self, from: data)) ?? []
    }

    public func saveTransactions(_ txs: [Transaction]) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? Self.encoder.encode(txs) else { return }
        try? data.write(to: transactionsURL, options: .atomic)
    }

    public func loadBalance() -> [BalancePoint] {
        guard let data = try? Data(contentsOf: balanceURL) else { return [] }
        return (try? Self.decoder.decode([BalancePoint].self, from: data)) ?? []
    }

    public func saveBalance(_ points: [BalancePoint]) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? Self.encoder.encode(points) else { return }
        try? data.write(to: balanceURL, options: .atomic)
    }
}
