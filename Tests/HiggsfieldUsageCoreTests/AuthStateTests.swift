import XCTest
@testable import HiggsfieldUsageCore

final class AuthStateTests: XCTestCase {
    func testDetectsNotAuthenticated() {
        XCTAssertTrue(AuthState.isAuthFailure("Error: Not authenticated.\nHint: Run: hf auth login"))
    }

    func testDetectsSessionExpired() {
        XCTAssertTrue(AuthState.isAuthFailure("Error: Session expired.\nHint: Run: hf auth login"))
    }

    func testDetectsUnauthorizedAndStatusCode() {
        XCTAssertTrue(AuthState.isAuthFailure("request failed: 401 Unauthorized"))
    }

    func testIgnoresUnrelatedFailures() {
        XCTAssertFalse(AuthState.isAuthFailure("higgsfield: request failed (no response received)"))
        XCTAssertFalse(AuthState.isAuthFailure("error.cli_missing"))
        XCTAssertFalse(AuthState.isAuthFailure(""))
    }
}
