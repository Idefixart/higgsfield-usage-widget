import Foundation

/// Classifies CLI failures so the UI can offer a sign-in button instead of a
/// dead-end error box. The CLI reports auth problems as plain stderr text
/// ("Not authenticated.", "Session expired.") plus a "Run: hf auth login"
/// hint — there is no machine-readable error code to key off.
public enum AuthState {
    static let authMarkers = [
        "not authenticated",
        "session expired",
        "auth login",
        "unauthorized",
        "401",
    ]

    public static func isAuthFailure(_ message: String) -> Bool {
        let lower = message.lowercased()
        return authMarkers.contains { lower.contains($0) }
    }
}
