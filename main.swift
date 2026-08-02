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
    var didCancelSignIn = false

    init(store: CreditsStore, config: AppConfig) {
        self.store = store
        self.config = config
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let btn = statusItem.button {
            btn.image = AppAssets.menuBarIcon()
                ?? NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Higgsfield Credits")
            btn.image?.accessibilityDescription = "Higgsfield Credits"
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

    /// Page size is capped at 100 by the API. A busy day can fill that in
    /// hours, which makes the 7d/30d/All windows collapse onto identical
    /// numbers — so walk the cursor until the history is deep enough to make
    /// the widest window meaningful.
    static let pageSize = 100
    static let targetHistoryDays: Double = 35
    static let maxPages = 12

    private func fetchTransactions() {
        fetchTransactionPage(offset: 0, page: 1, collected: [])
    }

    /// `--cursor` is a row offset, not an id or timestamp — the CLI parses it
    /// with ParseInt and the API skips that many rows.
    private func fetchTransactionPage(offset: Int, page: Int, collected: [Transaction]) {
        var args = ["account", "transactions", "--size", "\(Self.pageSize)"]
        if offset > 0 { args += ["--cursor", "\(offset)"] }

        cli.run(args) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard case .success(let data) = result,
                      let page1 = try? APIDecode.transactions(from: data) else {
                    // A failed first page means no fresh breakdown at all; a
                    // failed later page just means less depth than hoped.
                    self.finishTransactions(collected, stale: collected.isEmpty)
                    return
                }

                let merged = HistoryMerge.merge(existing: collected, new: page1)
                // Stop on a short page (end of history), on a page that added
                // nothing new (guards against an offset the API ignores, which
                // would otherwise loop forever), once the history is deep
                // enough, or at the page ceiling.
                let gainedRows = merged.count > collected.count
                let deepEnough = (Aggregation.coverage(merged)?.days ?? 0) >= Self.targetHistoryDays
                guard page1.count == Self.pageSize,
                      gainedRows,
                      !deepEnough,
                      page < Self.maxPages
                else {
                    self.finishTransactions(merged, stale: false)
                    return
                }
                self.fetchTransactionPage(offset: offset + page1.count, page: page + 1, collected: merged)
            }
        }
    }

    private func finishTransactions(_ txs: [Transaction], stale: Bool) {
        store.isLoading = false
        if !txs.isEmpty { store.apply(newTransactions: txs) }
        store.breakdownStale = stale
        store.publishSnapshot()
    }

    /// Owning the OAuth process here is the whole point: run from a terminal,
    /// `auth login` dies with the terminal before the callback lands and the
    /// token is never written.
    func signIn() {
        guard !store.isSigningIn else { return }
        store.isSigningIn = true
        cli.login { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.store.isSigningIn = false
                switch result {
                case .success:
                    self.refresh()
                case .failure(let error):
                    // Cancelling terminates the process, which reports failure
                    // — not worth an error box. Real failures still surface,
                    // alongside the sign-in card so the user can retry.
                    if self.didCancelSignIn {
                        self.didCancelSignIn = false
                    } else {
                        let raw = error.localizedDescription
                        self.store.errorMessage = L10n.strings[raw] != nil ? self.store.t(raw) : raw
                    }
                }
            }
        }
    }

    func cancelSignIn() {
        didCancelSignIn = true
        cli.cancelLogin()
        store.isSigningIn = false
    }

    /// One-click install of the npm package the CLI ships as. On success the
    /// refresh clears `needsCLI`, which is what makes the card disappear.
    func installCLI() {
        guard !store.isInstallingCLI else { return }
        store.isInstallingCLI = true
        store.cliIssue = nil
        cli.installCLI { [weak self] outcome in
            DispatchQueue.main.async {
                guard let self else { return }
                self.store.isInstallingCLI = false
                switch outcome {
                case .installed:
                    self.store.needsCLI = false
                    self.refresh()
                case .nodeMissing:
                    self.store.cliIssue = .nodeMissing
                case .failed(let reason):
                    switch reason {
                    case .needsPrivileges: self.store.cliIssue = .needsPrivileges
                    case .offline:         self.store.cliIssue = .offline
                    case .other(let msg):  self.store.cliIssue = .other(msg)
                    }
                }
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
            onQuit: { NSApp.terminate(nil) },
            onSignIn: { [weak self] in self?.signIn() },
            onCancelSignIn: { [weak self] in self?.cancelSignIn() },
            onInstallCLI: { [weak self] in self?.installCLI() }
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
