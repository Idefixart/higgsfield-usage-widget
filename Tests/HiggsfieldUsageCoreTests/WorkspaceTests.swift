import XCTest
@testable import HiggsfieldUsageCore

final class WorkspaceTests: XCTestCase {

    /// Verbatim from `higgsfield workspace list --json`.
    let listJSON = """
    [
      {
        "id": "97b75841-aaca-4c17-8567-1141558232d5",
        "name": null,
        "plan_type": "creator",
        "credits": 635.7000122070312,
        "is_selected": true,
        "user_role": "owner"
      }
    ]
    """.data(using: .utf8)!

    func testDecodesWorkspaceList() throws {
        let list = try WorkspaceState.list(from: listJSON)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].id, "97b75841-aaca-4c17-8567-1141558232d5")
        XCTAssertNil(list[0].name)
        XCTAssertEqual(list[0].planType, "creator")
        XCTAssertEqual(list[0].credits, 635.7000122070312, accuracy: 0.0001)
        XCTAssertTrue(list[0].isSelected)
        XCTAssertEqual(list[0].userRole, "owner")
    }

    func testDecodeToleratesMissingOptionalFields() throws {
        let json = #"[{"id":"abc"}]"#.data(using: .utf8)!
        let list = try WorkspaceState.list(from: json)
        XCTAssertEqual(list[0].planType, "")
        XCTAssertEqual(list[0].credits, 0)
        XCTAssertFalse(list[0].isSelected)
    }

    func testDecodeFailsWithoutID() {
        let json = #"[{"plan_type":"creator"}]"#.data(using: .utf8)!
        XCTAssertThrowsError(try WorkspaceState.list(from: json))
    }

    // MARK: - Display name

    func testDisplayNamePrefersRealName() {
        let ws = Workspace(id: "abcdef1234", name: "Studio", planType: "creator",
                           credits: 0, isSelected: false, userRole: "owner")
        XCTAssertEqual(ws.displayName, "Studio")
    }

    func testDisplayNameFallsBackToPlanWhenUnnamed() {
        let ws = Workspace(id: "abcdef1234", name: nil, planType: "creator",
                           credits: 0, isSelected: false, userRole: "owner")
        XCTAssertEqual(ws.displayName, "Creator")
    }

    func testDisplayNameFallsBackToShortIDWhenNothingElse() {
        let ws = Workspace(id: "abcdef1234", name: "   ", planType: "",
                           credits: 0, isSelected: false, userRole: "member")
        XCTAssertEqual(ws.displayName, "abcdef12")
    }

    // MARK: - Failure classification

    func testDetectsMissingSelectionFromCLIWording() {
        let stderr = "No workspace selected.\nRun: higgsfield workspace set <workspace_id>"
        XCTAssertTrue(WorkspaceState.isMissingSelection(stderr))
    }

    func testDetectsMissingSelectionFromHintAlone() {
        XCTAssertTrue(WorkspaceState.isMissingSelection(
            "Run: hf workspace set <workspace_id>. To use your personal account, run: hf workspace unset"))
    }

    func testIgnoresUnrelatedFailures() {
        XCTAssertFalse(WorkspaceState.isMissingSelection("Session expired."))
        XCTAssertFalse(WorkspaceState.isMissingSelection("error.cli_missing"))
        XCTAssertFalse(WorkspaceState.isMissingSelection(""))
        // A successful selection must not be mistaken for the failure.
        XCTAssertFalse(WorkspaceState.isMissingSelection("Selected workspace: Studio"))
    }
}
