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
            btn.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Higgsfield Credits")
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

    private func fetchTransactions() {
        cli.run(["account", "transactions", "--size", "100"]) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.store.isLoading = false
                if case .success(let data) = result,
                   let txs = try? APIDecode.transactions(from: data) {
                    self.store.apply(newTransactions: txs)
                    self.store.breakdownStale = false
                } else {
                    self.store.breakdownStale = true
                }
                self.store.publishSnapshot()
            }
        }
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
            onCancelSignIn: { [weak self] in self?.cancelSignIn() }
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
