import XCTest
@testable import HiggsfieldUsageCore

final class HistoryTests: XCTestCase {
    private func tx(_ name: String, _ credits: Double, _ createdAt: String) -> Transaction {
        Transaction(displayName: name, credits: credits, action: "spend", createdAt: createdAt)
    }

    func testMergeDedupesAndSortsNewestFirst() {
        let a = tx("A", -2, "2026-07-28T10:00:00.000001Z")
        let b = tx("B", -4, "2026-07-28T11:00:00.000001Z")
        let c = tx("C", -6, "2026-07-28T12:00:00.000001Z")
        let merged = HistoryMerge.merge(existing: [b, a], new: [c, b])
        XCTAssertEqual(merged.map(\.displayName), ["C", "B", "A"])
    }

    func testMergeSortsChronologicallyAcrossFractionWidths() {
        // The API omits the fraction when microseconds are exactly zero, so a
        // whole-second timestamp can be newer than a fractional one in the same
        // second. Plain string compare gets this backwards ('Z' > '.').
        let older = tx("older", -2, "2026-07-28T10:00:00.500000Z")
        let newer = tx("newer", -2, "2026-07-28T10:00:01Z")
        XCTAssertEqual(HistoryMerge.merge(existing: [older], new: [newer]).map(\.displayName),
                       ["newer", "older"])
    }

    func testMergeSinksUnparsableDatesToBottom() {
        let good = tx("good", -2, "2026-07-28T10:00:00Z")
        let bad = tx("bad", -2, "garbage")
        XCTAssertEqual(HistoryMerge.merge(existing: [bad], new: [good]).map(\.displayName),
                       ["good", "bad"])
    }

    func testMergeKeepsSameTimestampDifferentModel() {
        let a = tx("A", -2, "2026-07-28T10:00:00Z")
        let b = tx("B", -2, "2026-07-28T10:00:00Z")
        XCTAssertEqual(HistoryMerge.merge(existing: [a], new: [b]).count, 2)
    }

    func testBalanceAppendSkipsUnchangedWithinHour() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let pts = [BalancePoint(timestamp: t0, credits: 100)]
        let out = BalanceHistory.appendPrune(pts, adding: BalancePoint(timestamp: t0.addingTimeInterval(120), credits: 100))
        XCTAssertEqual(out.count, 1)
    }

    func testBalanceAppendsOnChange() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let pts = [BalancePoint(timestamp: t0, credits: 100)]
        let out = BalanceHistory.appendPrune(pts, adding: BalancePoint(timestamp: t0.addingTimeInterval(120), credits: 98))
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out.last?.credits, 98)
    }

    func testBalanceAppendsUnchangedAfterHour() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let pts = [BalancePoint(timestamp: t0, credits: 100)]
        let out = BalanceHistory.appendPrune(pts, adding: BalancePoint(timestamp: t0.addingTimeInterval(3601), credits: 100))
        XCTAssertEqual(out.count, 2)
    }

    func testBalancePrunesOld() {
        let now = Date(timeIntervalSince1970: 100 * 86400)
        let old = BalancePoint(timestamp: now.addingTimeInterval(-91 * 86400), credits: 500)
        let out = BalanceHistory.appendPrune([old], adding: BalancePoint(timestamp: now, credits: 400))
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.credits, 400)
    }

    func testFilesRoundtrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hf-test-\(UUID().uuidString)", isDirectory: true)
        let files = HistoryFiles(dir: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertEqual(files.loadTransactions(), [])
        XCTAssertEqual(files.loadBalance(), [])

        let txs = [tx("A", -2, "2026-07-28T10:00:00.123456Z")]
        files.saveTransactions(txs)
        XCTAssertEqual(files.loadTransactions(), txs)

        let pts = [BalancePoint(timestamp: Date(timeIntervalSince1970: 1_000_000), credits: 42)]
        files.saveBalance(pts)
        XCTAssertEqual(files.loadBalance().count, 1)
        XCTAssertEqual(files.loadBalance().first?.credits, 42)
    }
}
