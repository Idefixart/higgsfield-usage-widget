import XCTest
@testable import HiggsfieldUsageCore

final class CLIInstallTests: XCTestCase {

    // MARK: - Discovery

    func testSearchesSystemPrefixesBeforeManagedOnes() {
        let dirs = CLIInstall.binDirectories(home: "/Users/dev", listing: { _ in [] })
        XCTAssertEqual(Array(dirs.prefix(3)), CLIInstall.systemBinDirectories)
        XCTAssertTrue(dirs.contains("/Users/dev/.npm-global/bin"))
        XCTAssertTrue(dirs.contains("/Users/dev/.volta/bin"))
    }

    func testIncludesNvmVersionDirectories() {
        let dirs = CLIInstall.binDirectories(home: "/Users/dev", listing: { root in
            root == "/Users/dev/.nvm/versions/node" ? ["v18.19.0", "v20.11.0"] : []
        })
        XCTAssertTrue(dirs.contains("/Users/dev/.nvm/versions/node/v20.11.0/bin"))
        XCTAssertTrue(dirs.contains("/Users/dev/.nvm/versions/node/v18.19.0/bin"))
    }

    func testIncludesFnmVersionDirectoriesWithInstallationSuffix() {
        let dirs = CLIInstall.binDirectories(home: "/Users/dev", listing: { root in
            root.hasSuffix("fnm/node-versions") ? ["v22.3.0"] : []
        })
        XCTAssertTrue(dirs.contains("/Users/dev/.fnm/node-versions/v22.3.0/installation/bin"))
        XCTAssertTrue(dirs.contains(
            "/Users/dev/Library/Application Support/fnm/node-versions/v22.3.0/installation/bin"))
    }

    func testPrefersNewestNodeVersion() {
        let dirs = CLIInstall.binDirectories(home: "/Users/dev", listing: { root in
            root == "/Users/dev/.nvm/versions/node" ? ["v9.7.0", "v20.11.0", "v18.19.0"] : []
        })
        let versions = dirs.filter { $0.hasPrefix("/Users/dev/.nvm") }
        XCTAssertEqual(versions.first, "/Users/dev/.nvm/versions/node/v20.11.0/bin")
        // A plain string sort would rank v9 highest.
        XCTAssertEqual(versions.last, "/Users/dev/.nvm/versions/node/v9.7.0/bin")
    }

    func testNoVersionManagersInstalledYieldsOnlyFixedDirectories() {
        let dirs = CLIInstall.binDirectories(home: "/Users/dev", listing: { _ in [] })
        XCTAssertEqual(dirs.count, CLIInstall.systemBinDirectories.count + 2)
    }

    // MARK: - Failure classification

    func testClassifiesPermissionFailureFromOfficialInstallerPrefix() {
        let stderr = """
        npm ERR! code EACCES
        npm ERR! syscall mkdir
        npm ERR! path /usr/local/lib/node_modules/@higgsfield
        npm ERR! errno -13
        npm ERR! Error: EACCES: permission denied, mkdir '/usr/local/lib/node_modules/@higgsfield'
        """
        XCTAssertEqual(CLIInstall.classify(stderr), .needsPrivileges)
    }

    func testClassifiesMissingWriteAccess() {
        XCTAssertEqual(
            CLIInstall.classify("npm ERR! Missing write access to /usr/local/lib/node_modules"),
            .needsPrivileges)
    }

    func testClassifiesNetworkFailure() {
        let stderr = """
        npm ERR! code ENOTFOUND
        npm ERR! errno ENOTFOUND
        npm ERR! network request to https://registry.npmjs.org/@higgsfield%2fcli failed
        """
        XCTAssertEqual(CLIInstall.classify(stderr), .offline)
    }

    func testPermissionWinsOverNetworkWhenBothAppear() {
        // npm retries over the network before failing on the prefix; the
        // actionable cause is still the permission error.
        let stderr = """
        npm WARN network retrying request
        npm ERR! code EACCES
        npm ERR! Error: EACCES: permission denied
        """
        XCTAssertEqual(CLIInstall.classify(stderr), .needsPrivileges)
    }

    func testUnknownFailureKeepsFirstMeaningfulLine() {
        let stderr = """
        npm ERR! code E404
        npm ERR! 404 Not Found - GET https://registry.npmjs.org/@higgsfield%2fcli
        npm ERR! A complete log of this run can be found in: /Users/dev/.npm/_logs/x.log
        """
        XCTAssertEqual(
            CLIInstall.classify(stderr),
            .other("404 Not Found - GET https://registry.npmjs.org/@higgsfield%2fcli"))
    }

    func testSummarizeStripsNewStyleNpmErrorPrefix() {
        XCTAssertEqual(CLIInstall.summarize("npm error Cannot find module 'semver'"),
                       "Cannot find module 'semver'")
    }

    func testSummarizeFallsBackWhenNothingUsable() {
        XCTAssertEqual(CLIInstall.summarize(""), "npm install failed")
        XCTAssertEqual(CLIInstall.summarize("npm ERR! code E404\n"), "npm install failed")
    }

    func testSummarizeTruncatesRunawayOutput() {
        let long = String(repeating: "x", count: 500)
        let summary = CLIInstall.summarize(long, limit: 20)
        XCTAssertEqual(summary.count, 21) // 20 characters plus the ellipsis
        XCTAssertTrue(summary.hasSuffix("…"))
    }
}
