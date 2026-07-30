import Foundation

public enum StatsWindow: String, CaseIterable, Identifiable {
    case days7, days30, all
    public var id: String { rawValue }
    public var days: Double? {
        switch self {
        case .days7: return 7
        case .days30: return 30
        case .all: return nil
        }
    }
}

public struct ModelStat: Equatable, Identifiable {
    public let name: String
    public let creditsSpent: Double
    public let generations: Int
    public var id: String { name }
    public init(name: String, creditsSpent: Double, generations: Int) {
        self.name = name
        self.creditsSpent = creditsSpent
        self.generations = generations
    }
}

/// How far back the stored history actually reaches. Without this the window
/// picker looks broken: with only a day of data, 7d/30d/All are identical
/// numbers and nothing explains why.
public struct Coverage: Equatable {
    public let oldest: Date
    public let days: Double

    /// True when the window asks for more history than we hold, i.e. the
    /// figures shown are the same as the next window down.
    public func isTruncated(for window: StatsWindow) -> Bool {
        guard let want = window.days else { return true }
        return days < want
    }
}

public enum Aggregation {
    public static func coverage(_ txs: [Transaction], now: Date = Date()) -> Coverage? {
        let dates = txs.filter { $0.action == "spend" }.compactMap(\.date)
        guard let oldest = dates.min() else { return nil }
        return Coverage(oldest: oldest, days: max(0, now.timeIntervalSince(oldest) / 86400))
    }

    /// Per-model spend over a window. Only "spend" transactions count; one
    /// spend transaction == one generation. Sorted by credits spent, desc.
    public static func modelBreakdown(_ txs: [Transaction], window: StatsWindow, now: Date = Date()) -> [ModelStat] {
        let cutoff = window.days.map { now.addingTimeInterval(-$0 * 86400) }
        var spent: [String: Double] = [:]
        var count: [String: Int] = [:]
        for tx in txs where tx.action == "spend" {
            if let cutoff {
                guard let d = tx.date, d >= cutoff else { continue }
            }
            spent[tx.displayName, default: 0] += abs(tx.credits)
            count[tx.displayName, default: 0] += 1
        }
        // Ties break on name — dictionary iteration order is randomized per
        // process, so without it equal-spend rows shuffle between launches.
        return spent
            .map { ModelStat(name: $0.key, creditsSpent: $0.value, generations: count[$0.key] ?? 0) }
            .sorted { $0.creditsSpent == $1.creditsSpent ? $0.name < $1.name : $0.creditsSpent > $1.creditsSpent }
    }

    /// Bucket-averaged downsampling for the balance sparkline.
    public static func sparkline(_ points: [BalancePoint], maxPoints: Int = 60) -> [Double] {
        let values = points.map(\.credits)
        guard values.count > maxPoints, maxPoints > 0 else { return values }
        let bucketSize = Double(values.count) / Double(maxPoints)
        return (0..<maxPoints).map { i in
            let start = Int(Double(i) * bucketSize)
            let end = min(values.count, max(Int(Double(i + 1) * bucketSize), start + 1))
            let slice = values[start..<end]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }
}
