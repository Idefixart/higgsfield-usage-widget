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
    /// Higgsfield brand lime, taken from their design tokens (`--color-lime`).
    /// Neon on dark, but ~1.3:1 against white — as text in a light-mode
    /// popover it would be unreadable, so that variant is darkened.
    static let hfLime = Color(nsColor: NSColor(name: "hfLime") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 209 / 255, green: 254 / 255, blue: 23 / 255, alpha: 1)   // #D1FE17
            : NSColor(srgbRed: 104 / 255, green: 133 / 255, blue: 0 / 255, alpha: 1)    // #688500
    })

    /// Unmodified brand lime, for fills and bars where the shape carries the
    /// contrast instead of thin glyph strokes.
    static let hfLimeSolid = Color(red: 209 / 255, green: 254 / 255, blue: 23 / 255)
}

// MARK: - Assets

enum AppAssets {
    /// The Higgsfield glyph as a vector PDF, so it stays crisp at any menu bar
    /// or Retina scale. Loaded once; nil if the resource is missing from the
    /// bundle, in which case callers fall back to an SF Symbol.
    static let logo: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "pdf") else { return nil }
        return NSImage(contentsOf: url)
    }()

    /// Menu bar glyphs sit around 15pt in a 22pt bar. Template mode lets macOS
    /// invert it for light/dark menu bars instead of us guessing.
    static func menuBarIcon(height: CGFloat = 15) -> NSImage? {
        guard let img = logo?.copy() as? NSImage else { return nil }
        let aspect = img.size.height > 0 ? img.size.width / img.size.height : 1
        img.size = NSSize(width: height * aspect, height: height)
        img.isTemplate = true
        return img
    }
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
        "label.coverage":          [.en: "History starts %@ — shorter than this window", .de: "Verlauf beginnt %@ — kürzer als dieser Zeitraum"],
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
        "error.cli_missing":       [.en: "higgsfield CLI not found", .de: "higgsfield CLI nicht gefunden"],
        "error.auth":              [.en: "Not logged in — run: higgsfield auth login", .de: "Nicht eingeloggt — führe aus: higgsfield auth login"],
        "error.invalid_json":      [.en: "Invalid JSON from CLI", .de: "Ungültiges JSON vom CLI"],
        "error.login_failed":      [.en: "Sign-in did not complete", .de: "Anmeldung nicht abgeschlossen"],
        "auth.title":              [.en: "Not signed in", .de: "Nicht angemeldet"],
        "auth.body":               [.en: "Higgsfield Usage needs access to your Higgsfield account.", .de: "Higgsfield Usage braucht Zugriff auf dein Higgsfield-Konto."],
        "auth.button":             [.en: "Sign in to Higgsfield", .de: "Bei Higgsfield anmelden"],
        "auth.waiting":            [.en: "Waiting for browser — finish sign-in there, then this updates on its own.", .de: "Warte auf den Browser — schließe die Anmeldung dort ab, danach aktualisiert sich das hier von selbst."],
        "auth.cancel":             [.en: "Cancel", .de: "Abbrechen"],
        "cli.title":               [.en: "One step left", .de: "Nur noch ein Schritt"],
        "cli.body":                [.en: "Higgsfield Usage reads your credits through the higgsfield CLI. Install it once and this card disappears.", .de: "Higgsfield Usage liest deine Credits über die higgsfield CLI. Einmal installieren, dann verschwindet diese Karte."],
        "cli.button":              [.en: "Install higgsfield CLI", .de: "higgsfield CLI installieren"],
        "cli.installing":          [.en: "Installing @higgsfield/cli — this takes up to a minute.", .de: "Installiere @higgsfield/cli — das dauert bis zu einer Minute."],
        "cli.retry":               [.en: "Try again", .de: "Erneut versuchen"],
        "cli.copy":                [.en: "Copy command", .de: "Befehl kopieren"],
        "cli.copied":              [.en: "Copied", .de: "Kopiert"],
        "cli.node_title":          [.en: "Node.js required", .de: "Node.js erforderlich"],
        "cli.node_body":           [.en: "The CLI ships as an npm package, so Node.js has to be installed first. Install it, then come back here.", .de: "Die CLI ist ein npm-Paket, deshalb muss zuerst Node.js installiert werden. Installieren, dann hierher zurückkommen."],
        "cli.node_button":         [.en: "Open nodejs.org", .de: "nodejs.org öffnen"],
        "cli.node_brew":           [.en: "With Homebrew instead:", .de: "Alternativ mit Homebrew:"],
        "cli.privileges":          [.en: "npm may not write to its global folder. Run this in Terminal, then try again:", .de: "npm darf nicht in seinen globalen Ordner schreiben. Führe das im Terminal aus, dann erneut versuchen:"],
        "cli.offline":             [.en: "No connection to the npm registry. Check your internet, then try again.", .de: "Keine Verbindung zur npm-Registry. Prüfe dein Internet und versuche es erneut."],
        "cli.failed":              [.en: "Install failed: %@", .de: "Installation fehlgeschlagen: %@"],
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

/// Finds node-based binaries for a GUI app, which inherits launchd's PATH and
/// therefore sees none of the Homebrew or version-manager prefixes a shell
/// would. Hits are cached because lookups run on every refresh; misses are not,
/// so installing the CLI in a terminal is picked up without a restart.
enum NodeToolchain {
    private static var cache: [String: String] = [:]

    /// npm can be pointed at any global prefix (`npm config set prefix`), which
    /// no fixed list can predict — so after an install we ask npm where it put
    /// things and remember that directory across launches.
    static var learnedBinDirectory: String? {
        get { UserDefaults.standard.string(forKey: "npmGlobalBin") }
        set { UserDefaults.standard.set(newValue, forKey: "npmGlobalBin") }
    }

    static func locate(_ tool: String) -> String? {
        let fm = FileManager.default
        if let hit = cache[tool], fm.isExecutableFile(atPath: hit) { return hit }
        let hit = searchDirectories()
            .lazy
            .map { "\($0)/\(tool)" }
            .first { fm.isExecutableFile(atPath: $0) }
        // Assigning nil removes the key, so only hits stay cached.
        cache[tool] = hit
        return hit
    }

    static func forgetCachedPaths() { cache.removeAll() }

    private static func searchDirectories() -> [String] {
        let fm = FileManager.default
        var dirs = CLIInstall.binDirectories(home: fm.homeDirectoryForCurrentUser.path) { root in
            (try? fm.contentsOfDirectory(atPath: root)) ?? []
        }
        if let learned = learnedBinDirectory { dirs.insert(learned, at: 0) }
        return dirs
    }

    /// PATH for spawning node-based tools: the directory node actually lives in
    /// first, since a CLI resolved under nvm cannot run against a PATH that
    /// only knows Homebrew.
    static func searchPath(base: String?) -> String {
        var dirs: [String] = []
        if let node = locate("node") {
            dirs.append((node as NSString).deletingLastPathComponent)
        }
        if let learned = learnedBinDirectory { dirs.append(learned) }
        dirs += CLIInstall.systemBinDirectories
        dirs.append(base ?? "/usr/bin:/bin")
        return dirs.joined(separator: ":")
    }
}

final class HiggsfieldCLI {
    static func find() -> String? {
        NodeToolchain.locate("higgsfield")
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

    /// `auth login` opens a browser and blocks until the OAuth loopback
    /// callback arrives. Run from a terminal, closing that terminal sends
    /// SIGHUP and the token is never written — which is exactly how the
    /// credentials file ends up missing. Owning the process here avoids that:
    /// the app outlives the browser round-trip.
    private var loginProcess: Process?
    var isLoggingIn: Bool { loginProcess?.isRunning ?? false }

    /// Fails the login after this long so a closed browser tab cannot leave
    /// the UI spinning forever.
    static let loginTimeout: TimeInterval = 300

    func login(completion: @escaping (Result<Void, Error>) -> Void) {
        guard !isLoggingIn else { return }
        guard let bin = Self.find() else {
            completion(.failure(CLIError.missing))
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["auth", "login", "--no-color"]
        p.environment = Self.environment()
        let err = Pipe()
        p.standardOutput = Pipe()
        p.standardError = err
        do {
            try p.run()
        } catch {
            completion(.failure(error))
            return
        }
        loginProcess = p

        let deadline = DispatchTime.now() + Self.loginTimeout
        DispatchQueue.global().asyncAfter(deadline: deadline) { [weak p] in
            guard let p, p.isRunning else { return }
            p.terminate()
        }

        DispatchQueue.global().async { [weak self] in
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            self?.loginProcess = nil
            if p.terminationStatus == 0 {
                completion(.success(()))
                return
            }
            let msg = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            completion(.failure(CLIError.failed(msg.isEmpty ? "error.login_failed" : msg)))
        }
    }

    func cancelLogin() {
        loginProcess?.terminate()
        loginProcess = nil
    }

    /// The CLI derives its credential path from `$HOME` (`~/.config/higgsfield`).
    /// Sharing that with the terminal means both sides rotate the same refresh
    /// token: whoever refreshes second is rejected, and the CLI then deletes
    /// credentials.json outright. That is why running `higgsfield` in a shell
    /// signed the widget out, and vice versa. Giving the app its own HOME gives
    /// it its own session, so the two no longer collide.
    static var cliHome: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("HiggsfieldUsage/cli-home", isDirectory: true)
    }

    /// The CLI is a `#!/usr/bin/env node` script, so node must be on PATH. A
    /// GUI app inherits launchd's PATH, which usually lacks the Homebrew
    /// prefix — prepend the directories we actually found tools in rather than
    /// rely on the environment.
    private static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = NodeToolchain.searchPath(base: env["PATH"])
        prepareCLIHome()
        env["HOME"] = cliHome.path
        return env
    }

    /// Creates the private CLI home and seeds it with the workspace selection
    /// from the user's real config — credentials stay separate on purpose, but
    /// a different workspace would report different credits.
    private static func prepareCLIHome() {
        let fm = FileManager.default
        let configDir = cliHome.appendingPathComponent(".config/higgsfield", isDirectory: true)
        try? fm.createDirectory(at: configDir, withIntermediateDirectories: true)

        let ours = configDir.appendingPathComponent("config.json")
        guard !fm.fileExists(atPath: ours.path) else { return }
        let theirs = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/higgsfield/config.json")
        try? fm.copyItem(at: theirs, to: ours)
    }

    // MARK: One-click install

    /// What a `npm install -g @higgsfield/cli` attempt left behind.
    enum InstallOutcome: Equatable {
        case installed
        /// No npm on the machine at all, so there is nothing to install with.
        case nodeMissing
        case failed(CLIInstall.Failure)
    }

    private var installProcess: Process?
    var isInstalling: Bool { installProcess?.isRunning ?? false }

    /// A cold npm install of a scoped package runs well under a minute; past
    /// that it is hanging on a stalled registry connection.
    static let installTimeout: TimeInterval = 240

    /// Installs the CLI for the user. Unlike the CLI calls this keeps the real
    /// `$HOME`, so npm honours the user's own registry config and cache — only
    /// Higgsfield credentials need the private home.
    func installCLI(completion: @escaping (InstallOutcome) -> Void) {
        guard !isInstalling else { return }
        guard let npm = NodeToolchain.locate("npm") else {
            completion(.nodeMissing)
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: npm)
        p.arguments = CLIInstall.installArguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = NodeToolchain.searchPath(base: env["PATH"])
        p.environment = env
        let err = Pipe()
        p.standardOutput = Pipe()
        p.standardError = err
        do {
            try p.run()
        } catch {
            completion(.failed(.other(error.localizedDescription)))
            return
        }
        installProcess = p

        let deadline = DispatchTime.now() + Self.installTimeout
        DispatchQueue.global().asyncAfter(deadline: deadline) { [weak p] in
            guard let p, p.isRunning else { return }
            p.terminate()
        }

        DispatchQueue.global().async { [weak self] in
            // Read to EOF before waiting — npm is chatty enough to fill the pipe.
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            self?.installProcess = nil
            let stderr = String(data: errData, encoding: .utf8) ?? ""

            guard p.terminationStatus == 0 else {
                completion(.failed(CLIInstall.classify(stderr)))
                return
            }
            NodeToolchain.forgetCachedPaths()
            if Self.find() != nil {
                completion(.installed)
                return
            }
            // Installed successfully but not into any directory we search, so
            // the prefix is a custom one. Ask npm and remember the answer.
            NodeToolchain.learnedBinDirectory = Self.npmGlobalBin(npm: npm, env: env)
            NodeToolchain.forgetCachedPaths()
            completion(Self.find() != nil ? .installed : .failed(.other(CLIInstall.summarize(stderr))))
        }
    }

    func cancelInstall() {
        installProcess?.terminate()
        installProcess = nil
    }

    /// `npm prefix -g` prints the global prefix; binaries land in its `bin`.
    private static func npmGlobalBin(npm: String, env: [String: String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: npm)
        p.arguments = ["prefix", "-g"]
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let prefix = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !prefix.isEmpty
        else { return nil }
        return "\(prefix)/bin"
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
            p.environment = Self.environment()
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
