import XCTest
@testable import HiggsfieldUsageCore

final class AggregationTests: XCTestCase {
    private let now = ISO8601.parse("2026-07-28T12:00:00Z")!

    private func tx(_ name: String, _ credits: Double, daysAgo: Double, action: String = "spend") -> Transaction {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        let d = now.addingTimeInterval(-daysAgo * 86400)
        return Transaction(displayName: name, credits: credits, action: action, createdAt: f.string(from: d))
    }

    func testBreakdownSumsCountsAndSorts() {
        let txs = [
            tx("Nano Banana Pro", -2, daysAgo: 1),
            tx("Nano Banana Pro", -2, daysAgo: 2),
            tx("Kling 3.0", -20, daysAgo: 1),
            tx("Top Up", 500, daysAgo: 1, action: "refill"),
        ]
        let stats = Aggregation.modelBreakdown(txs, window: .all, now: now)
        XCTAssertEqual(stats.count, 2)
        XCTAssertEqual(stats[0].name, "Kling 3.0")
        XCTAssertEqual(stats[0].creditsSpent, 20)
        XCTAssertEqual(stats[0].generations, 1)
        XCTAssertEqual(stats[1].name, "Nano Banana Pro")
        XCTAssertEqual(stats[1].creditsSpent, 4)
        XCTAssertEqual(stats[1].generations, 2)
    }

    func testWindowFiltering() {
        let txs = [
            tx("A", -2, daysAgo: 1),
            tx("A", -2, daysAgo: 10),
            tx("A", -2, daysAgo: 40),
        ]
        XCTAssertEqual(Aggregation.modelBreakdown(txs, window: .days7, now: now).first?.generations, 1)
        XCTAssertEqual(Aggregation.modelBreakdown(txs, window: .days30, now: now).first?.generations, 2)
        XCTAssertEqual(Aggregation.modelBreakdown(txs, window: .all, now: now).first?.generations, 3)
    }

    func testUnparsableDateOnlyCountsInAll() {
        let bad = Transaction(displayName: "A", credits: -2, action: "spend", createdAt: "garbage")
        XCTAssertTrue(Aggregation.modelBreakdown([bad], window: .days7, now: now).isEmpty)
        XCTAssertEqual(Aggregation.modelBreakdown([bad], window: .all, now: now).first?.generations, 1)
    }

    func testSparklinePassthroughWhenSmall() {
        let pts = (0..<10).map { BalancePoint(timestamp: Date(timeIntervalSince1970: Double($0)), credits: Double($0)) }
        XCTAssertEqual(Aggregation.sparkline(pts), (0..<10).map(Double.init))
    }

    func testSparklineDownsamples() {
        let pts = (0..<120).map { BalancePoint(timestamp: Date(timeIntervalSince1970: Double($0)), credits: Double($0)) }
        let out = Aggregation.sparkline(pts, maxPoints: 60)
        XCTAssertEqual(out.count, 60)
        XCTAssertEqual(out.first!, 0.5, accuracy: 0.001)   // avg of 0,1
        XCTAssertEqual(out.last!, 118.5, accuracy: 0.001)  // avg of 118,119
    }
}
