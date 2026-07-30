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
        "error.cli_missing":       [.en: "higgsfield CLI not found — brew install higgsfield", .de: "higgsfield CLI nicht gefunden — brew install higgsfield"],
        "error.auth":              [.en: "Not logged in — run: higgsfield auth login", .de: "Nicht eingeloggt — führe aus: higgsfield auth login"],
        "error.invalid_json":      [.en: "Invalid JSON from CLI", .de: "Ungültiges JSON vom CLI"],
        "error.login_failed":      [.en: "Sign-in did not complete", .de: "Anmeldung nicht abgeschlossen"],
        "auth.title":              [.en: "Not signed in", .de: "Nicht angemeldet"],
        "auth.body":               [.en: "Higgsfield Usage needs access to your Higgsfield account.", .de: "Higgsfield Usage braucht Zugriff auf dein Higgsfield-Konto."],
        "auth.button":             [.en: "Sign in to Higgsfield", .de: "Bei Higgsfield anmelden"],
        "auth.waiting":            [.en: "Waiting for browser — finish sign-in there, then this updates on its own.", .de: "Warte auf den Browser — schließe die Anmeldung dort ab, danach aktualisiert sich das hier von selbst."],
        "auth.cancel":             [.en: "Cancel", .de: "Abbrechen"],
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
    /// prefix — prepend it rather than rely on the environment.
    private static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = "/opt/homebrew/bin:/usr/local/bin"
        env["PATH"] = extra + ":" + (env["PATH"] ?? "/usr/bin:/bin")
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
