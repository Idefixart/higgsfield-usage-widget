import XCTest
@testable import HiggsfieldUsageCore

final class ModelsTests: XCTestCase {
    func testStatusDecoding() throws {
        let json = #"{"email":"a@b.c","credits":2451.5,"subscription_plan_type":"creator"}"#
        let s = try APIDecode.status(from: Data(json.utf8))
        XCTAssertEqual(s.email, "a@b.c")
        XCTAssertEqual(s.credits, 2451.5)
        XCTAssertEqual(s.subscriptionPlanType, "creator")
    }

    func testTransactionsDecoding() throws {
        let json = #"[{"display_name":"Nano Banana Pro","credits":-2,"action":"spend","created_at":"2026-07-28T11:47:55.248813Z"}]"#
        let txs = try APIDecode.transactions(from: Data(json.utf8))
        XCTAssertEqual(txs.count, 1)
        XCTAssertEqual(txs[0].displayName, "Nano Banana Pro")
        XCTAssertEqual(txs[0].credits, -2)
        XCTAssertEqual(txs[0].action, "spend")
        XCTAssertEqual(txs[0].createdAt, "2026-07-28T11:47:55.248813Z")
        XCTAssertNotNil(txs[0].date)
    }

    func testMicrosecondDateParsing() {
        XCTAssertNotNil(ISO8601.parse("2026-07-28T11:47:55.248813Z"))
        XCTAssertNotNil(ISO8601.parse("2026-07-28T11:47:55.248Z"))
        XCTAssertNotNil(ISO8601.parse("2026-07-28T11:47:55.5Z"))
        XCTAssertNotNil(ISO8601.parse("2026-07-28T11:47:55Z"))
        XCTAssertNil(ISO8601.parse("not a date"))
    }

    func testMissingDisplayNameDefaults() throws {
        let json = #"[{"credits":100,"action":"refill","created_at":"2026-07-01T00:00:00Z"}]"#
        let txs = try APIDecode.transactions(from: Data(json.utf8))
        XCTAssertEqual(txs[0].displayName, "—")
    }

    func testDedupeKeyStable() {
        let tx = Transaction(displayName: "X", credits: -2, action: "spend",
                             createdAt: "2026-07-28T11:47:55.248813Z")
        XCTAssertEqual(tx.dedupeKey, "2026-07-28T11:47:55.248813Z|X|-2.0")
    }

    func testTransactionCodableRoundtrip() throws {
        let tx = Transaction(displayName: "X", credits: -2, action: "spend",
                             createdAt: "2026-07-28T11:47:55.248813Z")
        let data = try JSONEncoder().encode([tx])
        let back = try JSONDecoder().decode([Transaction].self, from: data)
        XCTAssertEqual(back, [tx])
        XCTAssertEqual(back[0].dedupeKey, tx.dedupeKey)
    }
}
