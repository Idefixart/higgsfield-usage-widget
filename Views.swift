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

// MARK: - Sign-in

struct AuthCard: View {
    @ObservedObject var store: CreditsStore
    let onSignIn: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.hfBlue)
                Text(store.t("auth.title"))
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(store.isSigningIn ? store.t("auth.waiting") : store.t("auth.body"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if store.isSigningIn {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.5).frame(width: 14, height: 14)
                    Button(store.t("auth.cancel"), action: onCancel)
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
            } else {
                Button(action: onSignIn) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.app.fill")
                        Text(store.t("auth.button"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hfBlue.opacity(0.07))
        .cornerRadius(8)
    }
}

// MARK: - Popover content

struct ContentView: View {
    @ObservedObject var store: CreditsStore
    let onSignIn: () -> Void
    let onCancelSignIn: () -> Void

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

            if store.needsAuth {
                AuthCard(store: store, onSignIn: onSignIn, onCancel: onCancelSignIn)
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

            if store.credits == nil && store.errorMessage == nil && !store.needsAuth {
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
    let onSignIn: () -> Void
    let onCancelSignIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ContentView(store: store, onSignIn: onSignIn, onCancelSignIn: onCancelSignIn)
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
