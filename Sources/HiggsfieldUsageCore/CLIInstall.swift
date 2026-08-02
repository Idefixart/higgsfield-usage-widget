import Foundation

/// Finding and installing the `higgsfield` CLI, which ships as an npm package
/// (`npm i -g @higgsfield/cli`) rather than a Homebrew formula. Process
/// spawning lives in the app layer; everything decidable without touching the
/// system lives here so it can be tested.
public enum CLIInstall {
    public static let package = "@higgsfield/cli"
    public static let installArguments = ["install", "-g", "@higgsfield/cli"]
    public static let command = "npm install -g @higgsfield/cli"
    public static let sudoCommand = "sudo npm install -g @higgsfield/cli"
    public static let brewNodeCommand = "brew install node"
    public static let nodeDownloadURL = "https://nodejs.org/en/download"

    // MARK: - Discovery

    /// Fixed locations, highest priority first: both Homebrew prefixes (Apple
    /// silicon, Intel) and the path the official Node installer writes to.
    public static let systemBinDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
    ]

    /// Version-manager layouts that keep one prefix per installed Node version,
    /// paired with the path from a version directory down to its binaries.
    static func versionedRoots(home: String) -> [(root: String, binSuffix: String)] {
        [
            (root: "\(home)/.nvm/versions/node", binSuffix: "bin"),
            (root: "\(home)/.fnm/node-versions", binSuffix: "installation/bin"),
            (root: "\(home)/Library/Application Support/fnm/node-versions", binSuffix: "installation/bin"),
        ]
    }

    /// Every directory a globally installed node binary could sit in, in the
    /// order they should be tried.
    ///
    /// A GUI app inherits launchd's PATH, not the shell's, so nvm/fnm/Volta
    /// prefixes are invisible unless searched explicitly — which is why a
    /// colleague can have the CLI installed and still be told it is missing.
    /// `listing` returns a directory's entries (empty when it does not exist)
    /// and is injected so this stays filesystem-free under test.
    public static func binDirectories(home: String, listing: (String) -> [String]) -> [String] {
        var dirs = systemBinDirectories
        // The documented `npm config set prefix` escape hatch, and Volta's
        // shim directory.
        dirs.append("\(home)/.npm-global/bin")
        dirs.append("\(home)/.volta/bin")
        for spec in versionedRoots(home: home) {
            // Newest version first — that is what the user's shell resolves to.
            for version in listing(spec.root).sorted(by: isDescendingVersion) {
                dirs.append("\(spec.root)/\(version)/\(spec.binSuffix)")
            }
        }
        return dirs
    }

    /// Orders `v20.11.0` above `v9.7.0`, which a plain string sort gets wrong.
    static func isDescendingVersion(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: .numeric) == .orderedDescending
    }

    // MARK: - Failure classification

    /// Why `npm install -g` failed, reduced to the cases a user can act on.
    public enum Failure: Equatable {
        /// npm cannot write to the global prefix. The usual outcome when Node
        /// came from the official .pkg installer and owns /usr/local as root,
        /// so the same command only works under sudo.
        case needsPrivileges
        case offline
        case other(String)
    }

    static let privilegeMarkers = [
        "eacces",
        "eperm",
        "permission denied",
        "missing write access",
        "operation not permitted",
    ]

    static let networkMarkers = [
        "enotfound",
        "etimedout",
        "econnrefused",
        "econnreset",
        "getaddrinfo",
        "socket hang up",
        "network",
    ]

    public static func classify(_ stderr: String) -> Failure {
        let lower = stderr.lowercased()
        if privilegeMarkers.contains(where: lower.contains) { return .needsPrivileges }
        if networkMarkers.contains(where: lower.contains) { return .offline }
        return .other(summarize(stderr))
    }

    static let logPrefixes = ["npm err! ", "npm error ", "npm warn ", "npm notice "]

    /// Lines that carry no information for the user, only log plumbing.
    static func isNoise(_ line: String) -> Bool {
        if line.isEmpty { return true }
        let lower = line.lowercased()
        if lower.hasPrefix("a complete log of this run") { return true }
        if lower.hasPrefix("code ") { return true }
        // Bare paths to npm's debug log.
        if line.hasPrefix("/") && lower.hasSuffix(".log") { return true }
        return false
    }

    /// npm answers a failure with dozens of prefixed lines; the first one
    /// carrying a real message is what a user can act on, the rest is noise.
    public static func summarize(_ stderr: String, limit: Int = 200) -> String {
        let candidates = stderr
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var text = line.trimmingCharacters(in: .whitespaces)
                for prefix in logPrefixes where text.lowercased().hasPrefix(prefix) {
                    text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                }
                return text
            }
            .filter { !isNoise($0) }

        guard let first = candidates.first else { return "npm install failed" }
        return first.count > limit ? String(first.prefix(limit)) + "…" : first
    }
}
