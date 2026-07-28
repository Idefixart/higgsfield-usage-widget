# Higgsfield Usage Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Native macOS menu bar app showing the Higgsfield credit balance, with a popover (balance, sparkline, per-model spend breakdown, recent transactions) and a WidgetKit desktop widget.

**Architecture:** Fork of the claude-usage-widget pattern (single-module swiftc build, no Xcode project). Testable logic lives in a SwiftPM library `HiggsfieldUsageCore` (Foundation-only) covered by `swift test`; the app and widget binaries are compiled by `build.sh` from the root Swift files plus the core sources. Data comes from the `higgsfield` CLI (`account status --json`, `account transactions --size 100 --json`) — no Python, no cookies.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit, WidgetKit, SwiftPM (tests only), bash build scripts. Target `arm64-apple-macos14`. Reference implementation: `../claude-usage-widget`.

**Working directory for ALL tasks:** `the repository root`

**File structure (final):**

```
Package.swift                          SwiftPM manifest (core lib + tests)
Sources/HiggsfieldUsageCore/
  Models.swift                         AccountStatus, Transaction, ISO8601 parsing
  History.swift                        merge/dedupe, balance history, file persistence
  Aggregation.swift                    StatsWindow, ModelStat, breakdown, sparkline
  Snapshot.swift                       CreditsSnapshot + SharedStore (app group)
Tests/HiggsfieldUsageCoreTests/
  ModelsTests.swift
  HistoryTests.swift
  AggregationTests.swift
AppSupport.swift                       LoginItem, colors, Lang/L10n, AppConfig, CLI runner
Store.swift                            CreditsStore (ObservableObject)
Views.swift                            popover + settings SwiftUI views
main.swift                             MenuBarController, AppDelegate, entry point
HiggsfieldWidget.swift                 WidgetKit extension (small + medium)
app.entitlements / widget.entitlements
build.sh / install.sh / package.sh
README.md
```

**Identifiers (used consistently everywhere):**
- App name: `Higgsfield Usage`, binary `HiggsfieldUsage`
- Bundle id: `com.higgsfield.usage-widget`
- Widget: `HiggsfieldUsageWidget.appex`, id `com.higgsfield.usage-widget.HiggsfieldUsageWidget`, binary `HiggsfieldUsageWidgetExt`
- App group: `group.com.higgsfield.usage-widget`
- Config/data dir: `~/.higgsfield-usage-widget/` (`config.json`, `transactions.json`, `balance-history.json`)
- Version: `1.0.0`

---

### Task 1: SwiftPM scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/HiggsfieldUsageCore/Models.swift` (empty placeholder module file)
- Create: `Tests/HiggsfieldUsageCoreTests/ModelsTests.swift` (empty test case)

- [ ] **Step 1: Write Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HiggsfieldUsageCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "HiggsfieldUsageCore", path: "Sources/HiggsfieldUsageCore"),
        .testTarget(
            name: "HiggsfieldUsageCoreTests",
            dependencies: ["HiggsfieldUsageCore"],
            path: "Tests/HiggsfieldUsageCoreTests"
        ),
    ]
)
```

- [ ] **Step 2: Create minimal module + test files**

`Sources/HiggsfieldUsageCore/Models.swift`:

```swift
import Foundation
```

`Tests/HiggsfieldUsageCoreTests/ModelsTests.swift`:

```swift
import XCTest
@testable import HiggsfieldUsageCore

final class ModelsTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 3: Run tests**

Run: `swift test`
Expected: `Test Suite 'All tests' passed` (1 test).

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "chore: SwiftPM scaffold for core library"
```

---

### Task 2: API models + ISO8601 parsing

**Files:**
- Modify: `Sources/HiggsfieldUsageCore/Models.swift`
- Modify: `Tests/HiggsfieldUsageCoreTests/ModelsTests.swift`

Higgsfield's API sends timestamps with **6 fractional digits** (`2026-07-28T11:47:55.248813Z`). `ISO8601DateFormatter` with `.withFractionalSeconds` only accepts exactly 3 — this must be normalized. `created_at` is kept as the **raw string** on `Transaction` so the dedupe key is byte-stable across save/load cycles.

- [ ] **Step 1: Write failing tests** — replace `ModelsTests.swift` entirely:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: FAIL — `cannot find 'APIDecode' in scope`, etc.

- [ ] **Step 3: Implement** — replace `Models.swift` entirely:

```swift
import Foundation

// MARK: - ISO8601 parsing

public enum ISO8601 {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// ISO8601DateFormatter only accepts exactly 3 fractional digits; the API
    /// sends 6. Truncate/pad the fraction to 3 digits before parsing.
    static func normalizeFraction(_ s: String) -> String {
        guard let r = s.range(of: #"\.\d+"#, options: .regularExpression) else { return s }
        var digits = String(s[r].dropFirst())
        if digits.count > 3 { digits = String(digits.prefix(3)) }
        while digits.count < 3 { digits += "0" }
        return s.replacingCharacters(in: r, with: "." + digits)
    }

    public static func parse(_ s: String) -> Date? {
        fractional.date(from: normalizeFraction(s)) ?? plain.date(from: s)
    }
}

// MARK: - API models

public struct AccountStatus: Codable, Equatable {
    public let email: String
    public let credits: Double
    public let subscriptionPlanType: String

    enum CodingKeys: String, CodingKey {
        case email, credits
        case subscriptionPlanType = "subscription_plan_type"
    }

    public init(email: String, credits: Double, subscriptionPlanType: String) {
        self.email = email
        self.credits = credits
        self.subscriptionPlanType = subscriptionPlanType
    }
}

public struct Transaction: Codable, Equatable, Hashable {
    public let displayName: String
    public let credits: Double
    public let action: String
    /// Raw ISO8601 string, kept verbatim so the dedupe key survives
    /// encode/decode cycles without losing microsecond precision.
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case credits, action
        case displayName = "display_name"
        case createdAt = "created_at"
    }

    public init(displayName: String, credits: Double, action: String, createdAt: String) {
        self.displayName = displayName
        self.credits = credits
        self.action = action
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? "—"
        credits = try c.decodeIfPresent(Double.self, forKey: .credits) ?? 0
        action = try c.decodeIfPresent(String.self, forKey: .action) ?? ""
        createdAt = try c.decode(String.self, forKey: .createdAt)
    }

    public var date: Date? { ISO8601.parse(createdAt) }
    public var dedupeKey: String { "\(createdAt)|\(displayName)|\(credits)" }
}

public enum APIDecode {
    public static func status(from data: Data) throws -> AccountStatus {
        try JSONDecoder().decode(AccountStatus.self, from: data)
    }
    public static func transactions(from data: Data) throws -> [Transaction] {
        try JSONDecoder().decode([Transaction].self, from: data)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: API models with microsecond-safe ISO8601 parsing"
```

---

### Task 3: Transaction history + balance history

**Files:**
- Create: `Sources/HiggsfieldUsageCore/History.swift`
- Create: `Tests/HiggsfieldUsageCoreTests/HistoryTests.swift`

Rules encoded here: merge dedupes by `dedupeKey` and sorts newest-first (ISO8601 UTC strings sort chronologically as plain strings). Balance points are only appended when the balance changed OR the last point is ≥ 1 h old (bounds file growth at 2-min refresh); points older than 90 days are pruned.

- [ ] **Step 1: Write failing tests** — create `HistoryTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: FAIL — `cannot find 'HistoryMerge' in scope`, etc.

- [ ] **Step 3: Implement** — create `History.swift`:

```swift
import Foundation

// MARK: - Transaction history

public enum HistoryMerge {
    /// Merge a freshly fetched page into the stored history. Dedupe by
    /// dedupeKey, newest first. ISO8601 UTC strings sort chronologically,
    /// so plain string comparison is a correct sort key.
    public static func merge(existing: [Transaction], new: [Transaction]) -> [Transaction] {
        var seen = Set<String>()
        var out: [Transaction] = []
        for tx in existing + new where seen.insert(tx.dedupeKey).inserted {
            out.append(tx)
        }
        return out.sorted { $0.createdAt > $1.createdAt }
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: PASS (13 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: transaction/balance history with dedupe and pruning"
```

---

### Task 4: Aggregation (model breakdown + sparkline)

**Files:**
- Create: `Sources/HiggsfieldUsageCore/Aggregation.swift`
- Create: `Tests/HiggsfieldUsageCoreTests/AggregationTests.swift`

Semantics: only `action == "spend"` transactions count toward the breakdown; one spend transaction == one generation; credits are reported as positive spend amounts (`abs`). Window filtering uses parsed dates against an injected `now` (testable). Transactions with unparsable dates only count in the `.all` window.

- [ ] **Step 1: Write failing tests** — create `AggregationTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: FAIL — `cannot find 'Aggregation' in scope`.

- [ ] **Step 3: Implement** — create `Aggregation.swift`:

```swift
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

public enum Aggregation {
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
        return spent
            .map { ModelStat(name: $0.key, creditsSpent: $0.value, generations: count[$0.key] ?? 0) }
            .sorted { $0.creditsSpent > $1.creditsSpent }
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: PASS (18 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: per-model spend aggregation and sparkline downsampling"
```

---

### Task 5: Widget snapshot + shared store

**Files:**
- Create: `Sources/HiggsfieldUsageCore/Snapshot.swift`
- Modify: `Tests/HiggsfieldUsageCoreTests/AggregationTests.swift` (append one test)

The WidgetKit extension runs sandboxed; it reads a JSON snapshot from the shared App Group container that the main app rewrites after every fetch. Same mechanism as the reference project's `WidgetShared.swift`.

- [ ] **Step 1: Write failing test** — append inside `AggregationTests`:

```swift
    func testSnapshotCodableRoundtrip() throws {
        let snap = CreditsSnapshot(
            credits: 2451.5, plan: "creator",
            topModels: [CreditsSnapshot.Model(name: "Nano Banana Pro", credits: 486, generations: 243)],
            windowLabel: "7d", warnBelow: 500,
            updatedAt: Date(timeIntervalSince1970: 1_785_239_275), error: nil)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(CreditsSnapshot.self, from: enc.encode(snap))
        XCTAssertEqual(back.credits, 2451.5)
        XCTAssertEqual(back.topModels.first?.generations, 243)
        XCTAssertEqual(back.warnBelow, 500)
    }
```

- [ ] **Step 2: Run tests to verify it fails**

Run: `swift test`
Expected: FAIL — `cannot find 'CreditsSnapshot' in scope`.

- [ ] **Step 3: Implement** — create `Snapshot.swift`:

```swift
import Foundation

// Written by the main app after every fetch, read by the WidgetKit extension
// through the shared App Group container.

public let appGroupID = "group.com.higgsfield.usage-widget"

public struct CreditsSnapshot: Codable {
    public struct Model: Codable {
        public var name: String
        public var credits: Double
        public var generations: Int
        public init(name: String, credits: Double, generations: Int) {
            self.name = name
            self.credits = credits
            self.generations = generations
        }
    }

    public var credits: Double
    public var plan: String
    public var topModels: [Model]
    public var windowLabel: String
    public var warnBelow: Double
    public var updatedAt: Date
    public var error: String?

    public init(credits: Double, plan: String, topModels: [Model], windowLabel: String,
                warnBelow: Double, updatedAt: Date, error: String?) {
        self.credits = credits
        self.plan = plan
        self.topModels = topModels
        self.windowLabel = windowLabel
        self.warnBelow = warnBelow
        self.updatedAt = updatedAt
        self.error = error
    }

    public static let placeholder = CreditsSnapshot(
        credits: 2451, plan: "creator",
        topModels: [
            Model(name: "Nano Banana Pro", credits: 486, generations: 243),
            Model(name: "Seedance 2.0", credits: 240, generations: 12),
            Model(name: "Kling 3.0", credits: 180, generations: 9),
        ],
        windowLabel: "7d", warnBelow: 500, updatedAt: Date(), error: nil)
}

public enum SharedStore {
    /// `containerURL(...)` works when the calling binary carries the app-group
    /// entitlement (the sandboxed widget); the non-sandboxed main app falls
    /// back to the literal path, which is the same folder.
    public static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/\(appGroupID)", isDirectory: true)
    }

    public static var snapshotURL: URL { containerURL.appendingPathComponent("credits-snapshot.json") }

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

    public static func write(_ snapshot: CreditsSnapshot) {
        try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: snapshotURL, options: .atomic)
    }

    public static func read() -> CreditsSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? decoder.decode(CreditsSnapshot.self, from: data)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: PASS (19 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: widget snapshot codec with app-group shared store"
```

---

### Task 6: App support layer (config, L10n, CLI runner)

**Files:**
- Create: `AppSupport.swift` (repo root — compiled into the app by build.sh, NOT part of the SwiftPM package)

No unit tests for this file (UI/process glue); verified by typecheck now and by the running app in Task 9.

- [ ] **Step 1: Create `AppSupport.swift`**

```swift
import AppKit
import SwiftUI
import ServiceManagement

// MARK: - Login Item

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
    static func set(_ enabled: Bool) throws {
        let svc = SMAppService.mainApp
        if enabled {
            if svc.status != .enabled { try svc.register() }
        } else {
            if svc.status == .enabled { try svc.unregister() }
        }
    }
}

// MARK: - Brand

extension Color {
    static let hfBlue = Color(red: 0 / 255, green: 194 / 255, blue: 255 / 255)  // #00C2FF
}

// MARK: - Localization

enum Lang: String, CaseIterable, Identifiable {
    case en, de
    var id: String { rawValue }
    var displayName: String {
        switch self { case .en: return "English"; case .de: return "Deutsch" }
    }
    var localeIdentifier: String {
        switch self { case .en: return "en_US"; case .de: return "de_DE" }
    }
}

enum L10n {
    static let strings: [String: [Lang: String]] = [
        "app.name":                [.en: "Higgsfield Usage", .de: "Higgsfield Usage"],
        "label.credits":           [.en: "Credits", .de: "Credits"],
        "section.models":          [.en: "Model Spend", .de: "Model-Verbrauch"],
        "section.recent":          [.en: "Recent", .de: "Zuletzt"],
        "window.7d":               [.en: "7 days", .de: "7 Tage"],
        "window.30d":              [.en: "30 days", .de: "30 Tage"],
        "window.all":              [.en: "All", .de: "Alle"],
        "label.updated":           [.en: "Updated: ", .de: "Aktualisiert: "],
        "label.stale":             [.en: "As of: ", .de: "Stand: "],
        "label.loading":           [.en: "Loading credits...", .de: "Lade Credits..."],
        "label.no_data":           [.en: "No spend data yet", .de: "Noch keine Verbrauchsdaten"],
        "action.refresh":          [.en: "Refresh", .de: "Aktualisieren"],
        "action.settings":         [.en: "Settings...", .de: "Einstellungen..."],
        "action.quit":             [.en: "Quit", .de: "Beenden"],
        "settings.title":          [.en: "Settings", .de: "Einstellungen"],
        "settings.window_title":   [.en: "Higgsfield Usage – Settings", .de: "Higgsfield Usage – Einstellungen"],
        "settings.interval":       [.en: "Refresh Interval", .de: "Aktualisierungs-Intervall"],
        "settings.min":            [.en: "min", .de: "Min"],
        "settings.warn":           [.en: "Warn below", .de: "Warnung unter"],
        "settings.warn_hint":      [.en: "Menu bar turns red when credits drop below this value", .de: "Menubar wird rot, wenn die Credits unter diesen Wert fallen"],
        "settings.autostart":      [.en: "Launch at login", .de: "Beim Login automatisch starten"],
        "settings.autostart_hint": [.en: "Higgsfield Usage opens at every system start", .de: "Higgsfield Usage öffnet sich bei jedem Systemstart"],
        "settings.language":       [.en: "Language", .de: "Sprache"],
        "settings.save":           [.en: "Save", .de: "Speichern"],
        "settings.data_source":    [.en: "Data via higgsfield CLI", .de: "Daten via higgsfield CLI"],
        "error.cli_missing":       [.en: "higgsfield CLI not found — brew install higgsfield", .de: "higgsfield CLI nicht gefunden — brew install higgsfield"],
        "error.auth":              [.en: "Not logged in — run: higgsfield auth login", .de: "Nicht eingeloggt — führe aus: higgsfield auth login"],
        "error.invalid_json":      [.en: "Invalid JSON from CLI", .de: "Ungültiges JSON vom CLI"],
    ]

    static func t(_ key: String, lang: Lang, _ args: CVarArg...) -> String {
        let template = strings[key]?[lang] ?? strings[key]?[.en] ?? key
        if args.isEmpty { return template }
        return String(format: template, arguments: args)
    }
}

// MARK: - Configuration

struct AppConfig: Codable {
    var refreshInterval: TimeInterval
    var warnBelowCredits: Double
    var language: String    // "en" | "de"
    var statsWindow: String // StatsWindow rawValue

    static let `default` = AppConfig(
        refreshInterval: 120,
        warnBelowCredits: 500,
        language: "en",
        statsWindow: "days7"
    )

    static var configDir: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.higgsfield-usage-widget"
    }
    static var configPath: String { "\(configDir)/config.json" }

    static func load() -> AppConfig {
        if let data = FileManager.default.contents(atPath: configPath),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            return decoded
        }
        return .default
    }

    func save() {
        try? FileManager.default.createDirectory(atPath: AppConfig.configDir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = .prettyPrinted
        if let data = try? enc.encode(self) {
            FileManager.default.createFile(atPath: AppConfig.configPath, contents: data)
        }
    }
}

// MARK: - CLI runner

final class HiggsfieldCLI {
    static let candidates = [
        "/opt/homebrew/bin/higgsfield",
        "/usr/local/bin/higgsfield",
        "/usr/bin/higgsfield",
    ]

    static func find() -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    enum CLIError: LocalizedError {
        case missing
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .missing: return "error.cli_missing"
            case .failed(let msg): return msg
            }
        }
    }

    /// Runs `higgsfield <args> --json --no-color` off the main thread.
    /// Completion fires on a background queue — callers hop to main.
    func run(_ args: [String], completion: @escaping (Result<Data, Error>) -> Void) {
        guard let bin = Self.find() else {
            completion(.failure(CLIError.missing))
            return
        }
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = args + ["--json", "--no-color"]
            let out = Pipe()
            let err = Pipe()
            p.standardOutput = out
            p.standardError = err
            do {
                try p.run()
            } catch {
                completion(.failure(error))
                return
            }
            // Read to EOF BEFORE waitUntilExit — the reverse order can deadlock
            // once output exceeds the 64 KB pipe buffer.
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                let msg = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                completion(.failure(CLIError.failed(msg.isEmpty ? "error.auth" : msg)))
                return
            }
            completion(.success(data))
        }
    }
}
```

- [ ] **Step 2: Typecheck**

Run: `swiftc -typecheck -target arm64-apple-macos14 AppSupport.swift Sources/HiggsfieldUsageCore/*.swift`
Expected: no output, exit 0.

- [ ] **Step 3: Commit**

```bash
git add AppSupport.swift
git commit -m "feat: app support layer — config, localization, CLI runner"
```

---

### Task 7: CreditsStore

**Files:**
- Create: `Store.swift` (repo root)

All `@Published` mutations happen on the main queue — the controller (Task 9) hops to main before calling `apply`/`fail`.

- [ ] **Step 1: Create `Store.swift`**

```swift
import SwiftUI
import Combine
import WidgetKit

final class CreditsStore: ObservableObject {
    @Published var credits: Double?
    @Published var plan: String = ""
    @Published var email: String = ""
    @Published var transactions: [Transaction] = []
    @Published var balancePoints: [BalancePoint] = []
    @Published var window: StatsWindow = .days7 { didSet { persistWindow() } }
    @Published var lastUpdated: Date?
    @Published var isStale = true
    @Published var breakdownStale = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var language: Lang = .en

    var config = AppConfig.load() {
        didSet { language = Lang(rawValue: config.language) ?? .en }
    }
    let files = HistoryFiles()

    func t(_ key: String, _ args: CVarArg...) -> String {
        let template = L10n.strings[key]?[language] ?? L10n.strings[key]?[.en] ?? key
        if args.isEmpty { return template }
        return String(format: template, arguments: args)
    }

    // MARK: Derived

    var breakdown: [ModelStat] {
        Aggregation.modelBreakdown(transactions, window: window)
    }
    var sparkValues: [Double] {
        Aggregation.sparkline(balancePoints)
    }
    var menuBarTitle: String {
        guard let c = credits else { return " –" }
        return " \(Int(c.rounded()))"
    }
    var isLow: Bool {
        guard let c = credits else { return false }
        return c < config.warnBelowCredits
    }

    func windowLabel(_ w: StatsWindow) -> String {
        switch w {
        case .days7: return t("window.7d")
        case .days30: return t("window.30d")
        case .all: return t("window.all")
        }
    }

    // MARK: State transitions (call on main queue only)

    /// Show last known data immediately at launch, marked stale.
    func loadCached() {
        transactions = files.loadTransactions()
        balancePoints = files.loadBalance()
        if let last = balancePoints.last {
            credits = last.credits
            lastUpdated = last.timestamp
            isStale = true
        }
    }

    func apply(status: AccountStatus) {
        credits = status.credits
        plan = status.subscriptionPlanType
        email = status.email
        lastUpdated = Date()
        isStale = false
        errorMessage = nil
        let pts = BalanceHistory.appendPrune(
            balancePoints,
            adding: BalancePoint(timestamp: Date(), credits: status.credits))
        balancePoints = pts
        files.saveBalance(pts)
    }

    func apply(newTransactions: [Transaction]) {
        let merged = HistoryMerge.merge(existing: transactions, new: newTransactions)
        transactions = merged
        files.saveTransactions(merged)
    }

    func fail(_ message: String) {
        isLoading = false
        isStale = true
        let msg = L10n.strings[message] != nil ? t(message) : message
        errorMessage = msg
        publishSnapshot(error: msg)
    }

    // MARK: Widget snapshot

    func publishSnapshot(error: String? = nil) {
        let top = breakdown.prefix(3).map {
            CreditsSnapshot.Model(name: $0.name, credits: $0.creditsSpent, generations: $0.generations)
        }
        let snap = CreditsSnapshot(
            credits: credits ?? 0,
            plan: plan,
            topModels: Array(top),
            windowLabel: windowLabel(window),
            warnBelow: config.warnBelowCredits,
            updatedAt: lastUpdated ?? Date(),
            error: error)
        SharedStore.write(snap)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func persistWindow() {
        config.statsWindow = window.rawValue
        config.save()
        publishSnapshot()
    }
}
```

- [ ] **Step 2: Typecheck**

Run: `swiftc -typecheck -target arm64-apple-macos14 AppSupport.swift Store.swift Sources/HiggsfieldUsageCore/*.swift`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add Store.swift
git commit -m "feat: credits store with cached-launch and widget snapshot publishing"
```

---

### Task 8: SwiftUI views

**Files:**
- Create: `Views.swift` (repo root)

- [ ] **Step 1: Create `Views.swift`**

```swift
import AppKit
import SwiftUI

let popoverWidth: CGFloat = 340

func fmtCredits(_ v: Double) -> String {
    v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
}

func relativeTime(_ d: Date?, lang: Lang) -> String {
    guard let d else { return "" }
    let f = RelativeDateTimeFormatter()
    f.locale = Locale(identifier: lang.localeIdentifier)
    f.unitsStyle = .short
    return f.localizedString(for: d, relativeTo: Date())
}

// MARK: - Building blocks

struct SectionLabel: View {
    let icon: String
    let title: String
    var warn: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.5)
            if warn {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
            }
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
        }
        .foregroundColor(.secondary.opacity(0.55))
    }
}

struct SparklineView: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            if values.count > 1, let mn = values.min(), let mx = values.max() {
                let range = mx - mn
                Path { p in
                    for (i, v) in values.enumerated() {
                        let x = geo.size.width * CGFloat(i) / CGFloat(values.count - 1)
                        let norm = range > 0 ? (v - mn) / range : 0.5
                        let y = geo.size.height * (1 - CGFloat(norm) * 0.9 - 0.05)
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(Color.hfBlue, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: 36)
    }
}

struct ModelStatRow: View {
    let stat: ModelStat
    let maxCredits: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(stat.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(fmtCredits(stat.creditsSpent)) cr · \(stat.generations) gens")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [Color.hfBlue.opacity(0.55), .hfBlue],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(3, geo.size.width * CGFloat(maxCredits > 0 ? stat.creditsSpent / maxCredits : 0)))
                }
            }
            .frame(height: 6)
        }
    }
}

struct TransactionRow: View {
    let tx: Transaction
    let lang: Lang

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(tx.displayName)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text(relativeTime(tx.date, lang: lang))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            Spacer()
            Text(tx.credits > 0 ? "+\(fmtCredits(tx.credits))" : fmtCredits(tx.credits))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(tx.credits > 0 ? .green : .secondary)
        }
    }
}

// MARK: - Popover content

struct ContentView: View {
    @ObservedObject var store: CreditsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.hfBlue)
                Text(store.t("app.name"))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if store.isLoading {
                    ProgressView().scaleEffect(0.5).frame(width: 14, height: 14)
                }
            }

            if let error = store.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.primary.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(8)
            }

            if store.credits == nil && store.errorMessage == nil {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(store.t("label.loading"))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
            } else if let credits = store.credits {
                // Balance card
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.t("label.credits"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(fmtCredits(credits))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(store.isLow ? .red : .hfBlue)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        if !store.plan.isEmpty {
                            Text(store.plan.capitalized)
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.hfBlue.opacity(0.12))
                                .foregroundColor(.hfBlue)
                                .clipShape(Capsule())
                        }
                        if !store.email.isEmpty {
                            Text(store.email)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.hfBlue.opacity(0.05))
                .cornerRadius(8)

                if store.sparkValues.count > 1 {
                    SparklineView(values: store.sparkValues)
                }

                // Model breakdown
                SectionLabel(icon: "chart.bar.fill", title: store.t("section.models"), warn: store.breakdownStale)
                Picker("", selection: $store.window) {
                    ForEach(StatsWindow.allCases) { w in
                        Text(store.windowLabel(w)).tag(w)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                let stats = store.breakdown
                if stats.isEmpty {
                    Text(store.t("label.no_data"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    let maxCr = stats.first?.creditsSpent ?? 1
                    ForEach(stats.prefix(6)) { s in
                        ModelStatRow(stat: s, maxCredits: maxCr)
                    }
                }

                // Recent transactions
                if !store.transactions.isEmpty {
                    SectionLabel(icon: "clock", title: store.t("section.recent"))
                    ForEach(Array(store.transactions.prefix(5)), id: \.dedupeKey) { tx in
                        TransactionRow(tx: tx, lang: store.language)
                    }
                }

                // Footer
                HStack {
                    Spacer()
                    if let updated = store.lastUpdated {
                        Text(store.isStale ? store.t("label.stale") : store.t("label.updated"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.4))
                        +
                        Text(updated, style: .relative)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                }
            }
        }
        .padding(16)
        .frame(width: popoverWidth)
    }
}

// MARK: - Popover shell

struct PopoverView: View {
    @ObservedObject var store: CreditsStore
    let onRefresh: () -> Void
    let onSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ContentView(store: store)
            Divider().padding(.horizontal, 14)
            VStack(spacing: 2) {
                popButton(icon: "arrow.clockwise", label: store.t("action.refresh"), action: onRefresh)
                popButton(icon: "gearshape", label: store.t("action.settings"), action: onSettings)
                Divider().padding(.horizontal, 14)
                popButton(icon: "xmark.circle", label: store.t("action.quit"), action: onQuit)
            }
            .padding(.vertical, 6)
        }
        .frame(width: popoverWidth)
    }

    func popButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12)).frame(width: 18)
                Text(label).font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings

func installEditMenu(store: CreditsStore) {
    let mainMenu = NSMenu()
    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: store.t("action.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    mainMenu.addItem(appItem)
    let editItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = editMenu
    mainMenu.addItem(editItem)
    NSApp.mainMenu = mainMenu
}

final class SettingsWindowController {
    var window: NSWindow?
    var config: AppConfig
    let store: CreditsStore
    let onSave: (AppConfig) -> Void

    init(config: AppConfig, store: CreditsStore, onSave: @escaping (AppConfig) -> Void) {
        self.config = config
        self.store = store
        self.onSave = onSave
    }

    func show() {
        installEditMenu(store: store)
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(config: config, store: store) { [weak self] c in
            self?.onSave(c)
            self?.window?.close()
            self?.window = nil
        }
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = store.t("settings.window_title")
        w.styleMask = [.titled, .closable]
        w.setContentSize(NSSize(width: 460, height: 400))
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w
    }
}

struct SettingsView: View {
    @ObservedObject var store: CreditsStore
    @State var refreshMinutes: Double
    @State var warnBelow: Double
    @State var autoStart: Bool
    @State var autoStartError: String?
    @State var language: Lang
    let onSave: (AppConfig) -> Void

    init(config: AppConfig, store: CreditsStore, onSave: @escaping (AppConfig) -> Void) {
        self.store = store
        _refreshMinutes = State(initialValue: config.refreshInterval / 60.0)
        _warnBelow = State(initialValue: config.warnBelowCredits)
        _autoStart = State(initialValue: LoginItem.isEnabled)
        _language = State(initialValue: Lang(rawValue: config.language) ?? .en)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(store.t("settings.title"))
                .font(.system(size: 18, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text(store.t("settings.language"))
                    .font(.system(size: 14, weight: .medium))
                Picker("", selection: $language) {
                    ForEach(Lang.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: language) { _, newLang in
                    store.language = newLang
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(store.t("settings.interval"))
                    .font(.system(size: 14, weight: .medium))
                HStack(spacing: 12) {
                    Slider(value: $refreshMinutes, in: 1...15, step: 1)
                    Text("\(Int(refreshMinutes)) \(store.t("settings.min"))")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .frame(width: 70, alignment: .trailing)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(store.t("settings.warn"))
                    .font(.system(size: 14, weight: .medium))
                HStack(spacing: 12) {
                    Slider(value: $warnBelow, in: 0...2000, step: 50)
                    Text("\(Int(warnBelow))")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.red)
                        .frame(width: 60, alignment: .trailing)
                }
                Text(store.t("settings.warn_hint"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $autoStart) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.t("settings.autostart"))
                            .font(.system(size: 14, weight: .medium))
                        Text(store.t("settings.autostart_hint"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: autoStart) { _, newValue in
                    do {
                        try LoginItem.set(newValue)
                        autoStartError = nil
                    } catch {
                        autoStart = LoginItem.isEnabled
                        autoStartError = error.localizedDescription
                    }
                }
                if let err = autoStartError {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            }

            Spacer()

            HStack {
                Text(store.t("settings.data_source"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Button(store.t("settings.save")) {
                    var config = AppConfig.load()
                    config.refreshInterval = refreshMinutes * 60
                    config.warnBelowCredits = warnBelow
                    config.language = language.rawValue
                    config.save()
                    onSave(config)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
```

- [ ] **Step 2: Typecheck**

Run: `swiftc -typecheck -target arm64-apple-macos14 AppSupport.swift Store.swift Views.swift Sources/HiggsfieldUsageCore/*.swift`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add Views.swift
git commit -m "feat: popover and settings views"
```

---

### Task 9: Entry point, entitlements, app build

**Files:**
- Create: `main.swift` (repo root)
- Create: `app.entitlements`
- Create: `widget.entitlements`
- Create: `build.sh` (app-only version; widget added in Task 10)

- [ ] **Step 1: Create `main.swift`**

```swift
import AppKit
import SwiftUI
import Combine
import WidgetKit

// MARK: - Menu Bar Controller

final class MenuBarController: NSObject, NSPopoverDelegate {
    let statusItem: NSStatusItem
    let popover = NSPopover()
    let store: CreditsStore
    var settingsController: SettingsWindowController?
    var config: AppConfig
    let cli = HiggsfieldCLI()
    var refreshTimer: Timer?
    var cancellables = Set<AnyCancellable>()
    var outsideClickMonitor: Any?

    init(store: CreditsStore, config: AppConfig) {
        self.store = store
        self.config = config
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Higgsfield Credits")
            btn.imagePosition = .imageLeft
            btn.title = " –"
            btn.action = #selector(togglePopover)
            btn.target = self
        }
        observeStore()
        startTimer()
        refresh()
    }

    func observeStore() {
        store.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let btn = self.statusItem.button else { return }
                btn.title = self.store.menuBarTitle
                btn.contentTintColor = self.store.isLow ? .systemRed : nil
            }
            .store(in: &cancellables)
    }

    func startTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: config.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        store.isLoading = true
        cli.run(["account", "status"]) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let data):
                    do {
                        let status = try APIDecode.status(from: data)
                        self.store.apply(status: status)
                        self.fetchTransactions()
                    } catch {
                        self.store.fail("error.invalid_json")
                    }
                case .failure(let error):
                    self.store.fail(error.localizedDescription)
                }
            }
        }
    }

    private func fetchTransactions() {
        cli.run(["account", "transactions", "--size", "100"]) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.store.isLoading = false
                if case .success(let data) = result,
                   let txs = try? APIDecode.transactions(from: data) {
                    self.store.apply(newTransactions: txs)
                    self.store.breakdownStale = false
                } else {
                    self.store.breakdownStale = true
                }
                self.store.publishSnapshot()
            }
        }
    }

    func showSettings() {
        popover.performClose(nil)
        if settingsController == nil {
            settingsController = SettingsWindowController(config: config, store: store) { [weak self] c in
                self?.config = c
                self?.store.config = c
                self?.startTimer()
            }
        }
        settingsController?.config = config
        settingsController?.show()
    }

    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let btn = statusItem.button else { return }
        let hosting = NSHostingController(rootView: PopoverView(
            store: store,
            onRefresh: { [weak self] in self?.refresh() },
            onSettings: { [weak self] in self?.showSettings() },
            onQuit: { NSApp.terminate(nil) }
        ))
        // Make NSPopover size to SwiftUI intrinsic, else top clips
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.delegate = self
        popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        startOutsideClickMonitor()
    }

    func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.popover.performClose(nil)
        }
    }

    func stopOutsideClickMonitor() {
        if let m = outsideClickMonitor {
            NSEvent.removeMonitor(m)
            outsideClickMonitor = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitor()
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = AppConfig.load()
        let store = CreditsStore()
        store.config = config
        store.language = Lang(rawValue: config.language) ?? .en
        store.window = StatsWindow(rawValue: config.statsWindow) ?? .days7
        store.loadCached()
        controller = MenuBarController(store: store, config: config)
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 2: Create entitlements**

`app.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.higgsfield.usage-widget</string>
    </array>
</dict>
</plist>
```

`widget.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.higgsfield.usage-widget</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 3: Create `build.sh` (app-only for now)**

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Higgsfield Usage"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
APP_ID="com.higgsfield.usage-widget"
TARGET="arm64-apple-macos14"
VERSION="1.0.0"

echo "Building $APP_NAME..."

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# --- Compile main app (main.swift has top-level code) ---
swiftc "$SCRIPT_DIR/main.swift" \
    "$SCRIPT_DIR/AppSupport.swift" \
    "$SCRIPT_DIR/Store.swift" \
    "$SCRIPT_DIR/Views.swift" \
    "$SCRIPT_DIR/Sources/HiggsfieldUsageCore/"*.swift \
    -framework AppKit \
    -framework SwiftUI \
    -framework Combine \
    -framework WidgetKit \
    -target "$TARGET" \
    -O \
    -o "$BUILD_DIR/HiggsfieldUsage"
echo "App binary compiled."

# --- Assemble .app bundle ---
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/HiggsfieldUsage" "$APP_BUNDLE/Contents/MacOS/HiggsfieldUsage"

# Optional app icon
if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Higgsfield Usage</string>
    <key>CFBundleDisplayName</key>
    <string>Higgsfield Usage</string>
    <key>CFBundleIdentifier</key>
    <string>$APP_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>HiggsfieldUsage</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - \
    --entitlements "$SCRIPT_DIR/app.entitlements" \
    --identifier "$APP_ID" \
    "$APP_BUNDLE"
echo "App bundle signed (ad-hoc)."
echo "App bundle created: $APP_BUNDLE"
```

- [ ] **Step 4: Build and smoke-test**

```bash
chmod +x build.sh
./build.sh
```
Expected: `App bundle created: .../build/Higgsfield Usage.app`, exit 0.

Then launch and verify manually:

```bash
open "build/Higgsfield Usage.app"
sleep 8
cat ~/.higgsfield-usage-widget/balance-history.json
```
Expected: menu bar shows ⚡ + credit number within a few seconds; `balance-history.json` contains one point with the current balance. Quit the app via popover → Quit (or `pkill HiggsfieldUsage`).

- [ ] **Step 5: Commit**

```bash
git add main.swift app.entitlements widget.entitlements build.sh
git commit -m "feat: menu bar app entry point and build script"
```

---

### Task 10: WidgetKit desktop widget

**Files:**
- Create: `HiggsfieldWidget.swift`
- Modify: `build.sh` (add widget compile + appex packaging + sign order)

- [ ] **Step 1: Create `HiggsfieldWidget.swift`**

```swift
import WidgetKit
import SwiftUI

private extension Color {
    static let hfBlue = Color(red: 0 / 255, green: 194 / 255, blue: 255 / 255)  // #00C2FF
}

private func fmt(_ v: Double) -> String {
    v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
}

// MARK: - Timeline

struct CreditsEntry: TimelineEntry {
    let date: Date
    let snapshot: CreditsSnapshot
}

struct CreditsProvider: TimelineProvider {
    func placeholder(in context: Context) -> CreditsEntry {
        CreditsEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (CreditsEntry) -> Void) {
        completion(CreditsEntry(date: Date(), snapshot: SharedStore.read() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CreditsEntry>) -> Void) {
        let snap = SharedStore.read() ?? .placeholder
        let now = Date()
        // The main app pushes reloads after each fetch; this is just a safety
        // net so the widget stays roughly fresh if the app is not running.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        completion(Timeline(entries: [CreditsEntry(date: now, snapshot: snap)], policy: .after(next)))
    }
}

// MARK: - Pieces

private struct Header: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11))
                .foregroundColor(.hfBlue)
            Text("Higgsfield")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
        }
    }
}

private func creditsColor(_ snap: CreditsSnapshot) -> Color {
    snap.credits < snap.warnBelow ? .red : .hfBlue
}

private struct ModelMini: View {
    let model: CreditsSnapshot.Model
    let maxCredits: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(fmt(model.credits)) cr · \(model.generations)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(colors: [Color.hfBlue.opacity(0.65), .hfBlue],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(3, geo.size.width * CGFloat(maxCredits > 0 ? model.credits / maxCredits : 0)))
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - Small

private struct SmallView: View {
    let snapshot: CreditsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Header()
            Spacer(minLength: 0)
            Text("Credits")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(fmt(snapshot.credits))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(creditsColor(snapshot))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if !snapshot.plan.isEmpty {
                Text(snapshot.plan.capitalized)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.hfBlue)
            }
        }
    }
}

// MARK: - Medium

private struct MediumView: View {
    let snapshot: CreditsSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Header()
                Spacer(minLength: 0)
                Text("Credits")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Text(fmt(snapshot.credits))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(creditsColor(snapshot))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if !snapshot.plan.isEmpty {
                    Text(snapshot.plan.capitalized)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.hfBlue)
                }
            }
            .frame(width: 118, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text(snapshot.windowLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                let maxCr = snapshot.topModels.map(\.credits).max() ?? 1
                ForEach(Array(snapshot.topModels.prefix(3).enumerated()), id: \.offset) { _, m in
                    ModelMini(model: m, maxCredits: maxCr)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Widget

struct HiggsfieldWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: CreditsEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall: SmallView(snapshot: entry.snapshot)
            default: MediumView(snapshot: entry.snapshot)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct HiggsfieldUsageWidget: Widget {
    let kind = "HiggsfieldUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CreditsProvider()) { entry in
            HiggsfieldWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Higgsfield Usage")
        .description("Your Higgsfield credit balance and top model spend at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct HiggsfieldUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        HiggsfieldUsageWidget()
    }
}
```

- [ ] **Step 2: Replace `build.sh` with the full version (app + widget)**

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Higgsfield Usage"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
APP_ID="com.higgsfield.usage-widget"
WIDGET_ID="$APP_ID.HiggsfieldUsageWidget"
TARGET="arm64-apple-macos14"
VERSION="1.0.0"

echo "Building $APP_NAME..."

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# --- Compile main app (main.swift has top-level code) ---
swiftc "$SCRIPT_DIR/main.swift" \
    "$SCRIPT_DIR/AppSupport.swift" \
    "$SCRIPT_DIR/Store.swift" \
    "$SCRIPT_DIR/Views.swift" \
    "$SCRIPT_DIR/Sources/HiggsfieldUsageCore/"*.swift \
    -framework AppKit \
    -framework SwiftUI \
    -framework Combine \
    -framework WidgetKit \
    -target "$TARGET" \
    -O \
    -o "$BUILD_DIR/HiggsfieldUsage"
echo "App binary compiled."

# --- Compile widget extension (@main WidgetBundle, no top-level code) ---
swiftc "$SCRIPT_DIR/HiggsfieldWidget.swift" \
    "$SCRIPT_DIR/Sources/HiggsfieldUsageCore/"*.swift \
    -framework WidgetKit \
    -framework SwiftUI \
    -target "$TARGET" \
    -O \
    -o "$BUILD_DIR/HiggsfieldUsageWidgetExt"
echo "Widget binary compiled."

# --- Assemble .app bundle ---
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/HiggsfieldUsage" "$APP_BUNDLE/Contents/MacOS/HiggsfieldUsage"

# Optional app icon
if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Higgsfield Usage</string>
    <key>CFBundleDisplayName</key>
    <string>Higgsfield Usage</string>
    <key>CFBundleIdentifier</key>
    <string>$APP_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>HiggsfieldUsage</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# --- Assemble widget extension (.appex) inside Contents/PlugIns ---
APPEX="$APP_BUNDLE/Contents/PlugIns/HiggsfieldUsageWidget.appex"
mkdir -p "$APPEX/Contents/MacOS"
cp "$BUILD_DIR/HiggsfieldUsageWidgetExt" "$APPEX/Contents/MacOS/HiggsfieldUsageWidgetExt"

cat > "$APPEX/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>HiggsfieldUsageWidget</string>
    <key>CFBundleDisplayName</key>
    <string>Higgsfield Usage</string>
    <key>CFBundleIdentifier</key>
    <string>$WIDGET_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>HiggsfieldUsageWidgetExt</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
PLIST

# --- Code sign (ad-hoc). Inner extension first, then the app bundle. ---
codesign --force --sign - \
    --entitlements "$SCRIPT_DIR/widget.entitlements" \
    --identifier "$WIDGET_ID" \
    "$APPEX"
echo "Widget extension signed (ad-hoc)."

codesign --force --sign - \
    --entitlements "$SCRIPT_DIR/app.entitlements" \
    --identifier "$APP_ID" \
    "$APP_BUNDLE"
echo "App bundle signed (ad-hoc)."

echo "App bundle created: $APP_BUNDLE"
echo ""
echo "To install, run: ./install.sh"
echo "Or open directly: open \"$APP_BUNDLE\""
```

- [ ] **Step 3: Build and verify signing**

```bash
./build.sh
codesign -dv --entitlements - "build/Higgsfield Usage.app/Contents/PlugIns/HiggsfieldUsageWidget.appex" 2>&1 | grep -E "app-sandbox|application-groups"
```
Expected: build exits 0; codesign output shows `com.apple.security.app-sandbox` and the app group.

- [ ] **Step 4: Commit**

```bash
git add HiggsfieldWidget.swift build.sh
git commit -m "feat: WidgetKit desktop widget (small + medium)"
```

---

### Task 11: install.sh, package.sh, README

**Files:**
- Create: `install.sh`
- Create: `package.sh`
- Create: `README.md`

- [ ] **Step 1: Create `install.sh`**

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Higgsfield Usage"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="/Applications"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Building first..."
    bash "$SCRIPT_DIR/build.sh"
fi

echo "Installing to $INSTALL_DIR..."
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP_BUNDLE" "$INSTALL_DIR/"
echo "Installed to $INSTALL_DIR/$APP_NAME.app"

# The widget won't appear in the gallery if macOS has stale copies of the same
# bundle id registered. Re-register the installed one.
LSR="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSR" ]; then
    echo "Cleaning stale widget registrations..."
    "$LSR" -u "$APP_BUNDLE" 2>/dev/null || true
    "$LSR" -u "$BUILD_DIR/dmg/$APP_NAME.app" 2>/dev/null || true
    "$LSR" -f "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true
    killall chronod 2>/dev/null || true
fi

echo ""
read -p "Beim Login automatisch starten? (j/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Jj]$ ]]; then
    osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$INSTALL_DIR/$APP_NAME.app\", hidden:true}"
    echo "Login-Item hinzugefuegt."
fi

echo ""
echo "Starte App..."
open "$INSTALL_DIR/$APP_NAME.app"
echo "Fertig! Du siehst jetzt das Blitz-Symbol in deiner Menueleiste."
```

- [ ] **Step 2: Create `package.sh`**

```bash
#!/bin/bash
# Package the app as a shareable DMG.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Higgsfield Usage"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_DIR="$BUILD_DIR/dmg"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

# Build fresh (build.sh already ad-hoc signs app AND widget with their
# entitlements — do NOT re-sign with --deep here).
bash "$SCRIPT_DIR/build.sh"

rm -rf "$DMG_DIR" "$DMG_PATH"
mkdir -p "$DMG_DIR"
cp -R "$APP_BUNDLE" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

cat > "$DMG_DIR/LIES_MICH.txt" << 'EOF'
Higgsfield Usage Widget
=======================

Installation:
1. "Higgsfield Usage.app" in "Applications" ziehen.
2. Beim ersten Start: Rechtsklick -> "Oeffnen" (ungesigniert, ad-hoc).

Voraussetzungen:
- macOS 14+ (Apple Silicon)
- higgsfield CLI installiert und eingeloggt:
  brew install higgsfield && higgsfield auth login

Das Widget zeigt:
- Aktuelle Higgsfield Credits in der Menueleiste
- Popover: Guthaben-Verlauf, Model-Verbrauch (7d/30d/gesamt),
  letzte Transaktionen
- Desktop-Widget (klein + mittel) via "Widgets bearbeiten"
EOF

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

xattr -d com.apple.quarantine "$DMG_PATH" 2>/dev/null || true

echo ""
echo "DMG ready: $DMG_PATH"
```

- [ ] **Step 3: Create `README.md`**

```markdown
# Higgsfield Usage Widget

A lightweight macOS menu bar app + desktop widget that shows your Higgsfield
credit balance in real time — balance sparkline, per-model spend breakdown
(credits + generation count over 7d/30d/all), and recent transactions.

Data comes from the official `higgsfield` CLI (`higgsfield account status`,
`higgsfield account transactions`) — no API keys, no cookies, read-only.

## Requirements

- macOS 14 (Sonoma) or newer, Apple Silicon
- [higgsfield CLI](https://higgsfield.ai) installed and signed in:
  `brew install higgsfield && higgsfield auth login`

## Build & install

```bash
./build.sh          # compile app + widget bundle
./install.sh        # install to /Applications, optional login item
./package.sh        # optional: build a shareable DMG
```

## Tests

Core logic (parsing, history dedupe, aggregation) is a SwiftPM library:

```bash
swift test
```

## Configuration

Click the bolt in the menu bar → Settings:
refresh interval (1–15 min), low-credit warning threshold, launch at login,
language (EN/DE). Config: `~/.higgsfield-usage-widget/config.json`.
Local history: `transactions.json`, `balance-history.json` (same folder).

## Project layout

```
main.swift / AppSupport.swift / Store.swift / Views.swift   menu bar app
HiggsfieldWidget.swift                                      WidgetKit extension
Sources/HiggsfieldUsageCore/                                testable core logic
build.sh / install.sh / package.sh                          build & distribution
```

MIT.
```

- [ ] **Step 4: Make scripts executable, commit**

```bash
chmod +x install.sh package.sh
git add install.sh package.sh README.md
git commit -m "feat: install/package scripts and README"
```

---

### Task 12: End-to-end verification

**Files:** none (verification only)

- [ ] **Step 1: Full test suite**

Run: `swift test`
Expected: all tests pass (19).

- [ ] **Step 2: Fresh build + launch**

```bash
./build.sh
open "build/Higgsfield Usage.app"
```

Manual checklist (report each item):
- Menu bar shows bolt + credit count matching `higgsfield account status`
- Popover: balance card (credits, plan badge, email), model breakdown with
  window toggle reacting, recent transactions with relative times
- Settings opens, language toggle DE/EN live-switches labels, Save persists
  (`cat ~/.higgsfield-usage-widget/config.json`)
- Refresh button triggers a fetch (spinner appears)
- `cat ~/Library/Group\ Containers/group.com.higgsfield.usage-widget/credits-snapshot.json`
  shows a fresh snapshot after refresh

- [ ] **Step 3: Error-path check**

Quit the app. Temporarily hide the CLI, launch, expect the CLI-missing error
in the popover, then restore:

```bash
sudo mv /opt/homebrew/bin/higgsfield /opt/homebrew/bin/higgsfield.bak
open "build/Higgsfield Usage.app"
# popover should show: "higgsfield CLI not found — brew install higgsfield"
# menu bar should show "⚡ –" (or last cached value marked stale)
sudo mv /opt/homebrew/bin/higgsfield.bak /opt/homebrew/bin/higgsfield
```
(If sudo is unavailable, skip this step and note it.)

- [ ] **Step 4: Install for real + widget gallery**

```bash
./install.sh
```
Then: right-click desktop → Edit Widgets → search "Higgsfield" → add small +
medium. Verify both render snapshot data.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "chore: v1.0.0 — verified end-to-end"
```

---

## Verification summary (maps to spec)

| Spec requirement | Task |
|---|---|
| Menu bar credits + low-warning color | 7, 9 |
| CLI data source, no Python | 6 |
| Local transaction history beyond API page | 3 |
| Balance sparkline + 90d prune | 3, 4, 8 |
| Per-model breakdown (credits + gens, 7d/30d/all) | 4, 8 |
| Recent transactions | 8 |
| WidgetKit small/medium via app group | 5, 10 |
| Settings (interval, threshold, login item, DE/EN) | 6, 8 |
| Error handling (CLI missing / auth / stale) | 6, 7, 12 |
| Tests as pure functions via swift test | 2–5 |
| build.sh / install.sh / package.sh / README | 9–11 |
