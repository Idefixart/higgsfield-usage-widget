import XCTest
@testable import HiggsfieldUsageCore

final class SnapshotTests: XCTestCase {
    private func makeSnapshot(credits: Double = 2451.5) -> CreditsSnapshot {
        CreditsSnapshot(
            credits: credits, plan: "creator",
            topModels: [CreditsSnapshot.Model(name: "Nano Banana Pro", credits: 486, generations: 243)],
            windowLabel: "7d", warnBelow: 500,
            updatedAt: Date(timeIntervalSince1970: 1_785_239_275), error: nil)
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("hf-snap-\(UUID().uuidString)", isDirectory: true)
    }

    func testDiskRoundtrip() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("credits-snapshot.json")

        SharedStore.write(makeSnapshot(), to: url)
        let back = try XCTUnwrap(SharedStore.read(from: url))
        XCTAssertEqual(back.credits, 2451.5)
        XCTAssertEqual(back.plan, "creator")
        XCTAssertEqual(back.topModels.first?.generations, 243)
        XCTAssertEqual(back.updatedAt, Date(timeIntervalSince1970: 1_785_239_275))
    }

    func testWriteCreatesMissingDirectory() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("credits-snapshot.json")

        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        SharedStore.write(makeSnapshot(), to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testWriteOverwrites() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("credits-snapshot.json")

        SharedStore.write(makeSnapshot(credits: 100), to: url)
        SharedStore.write(makeSnapshot(credits: 42), to: url)
        XCTAssertEqual(try XCTUnwrap(SharedStore.read(from: url)).credits, 42)
    }

    func testReadMissingFileReturnsNil() {
        let url = tempDir().appendingPathComponent("credits-snapshot.json")
        XCTAssertNil(SharedStore.read(from: url))
    }

    func testReadCorruptFileReturnsNil() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("credits-snapshot.json")
        try Data("not json".utf8).write(to: url)

        XCTAssertNil(SharedStore.read(from: url))
    }

    func testSnapshotURLLivesInContainer() {
        XCTAssertEqual(SharedStore.snapshotURL.lastPathComponent, "credits-snapshot.json")
        XCTAssertEqual(SharedStore.snapshotURL.deletingLastPathComponent().path,
                       SharedStore.containerURL.path)
    }
}
