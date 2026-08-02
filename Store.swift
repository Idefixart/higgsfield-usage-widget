import SwiftUI
import Combine
import WidgetKit

final class CreditsStore: ObservableObject {
    @Published var credits: Double?
    @Published var plan: String = ""
    @Published var email: String = ""
    @Published var transactions: [Transaction] = []
    @Published var balancePoints: [BalancePoint] = []
    @Published var window: StatsWindow = .days7 { didSet { persistWindow() } }
    @Published var lastUpdated: Date?
    @Published var isStale = true
    @Published var breakdownStale = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var needsAuth = false
    @Published var isSigningIn = false
    @Published var needsCLI = false
    @Published var isInstallingCLI = false
    @Published var cliIssue: CLIIssue?
    @Published var needsWorkspace = false
    @Published var workspaces: [Workspace] = []
    @Published var isWorkspaceBusy = false
    @Published var workspaceError: String?
    @Published var language: Lang = .en

    /// A failed install attempt, in the shape the card renders. Separate from
    /// `errorMessage` because each case has its own remedy, not just text.
    enum CLIIssue: Equatable {
        case nodeMissing
        case needsPrivileges
        case offline
        case other(String)
    }

    var config = AppConfig.load() {
        didSet { language = Lang(rawValue: config.language) ?? .en }
    }
    let files = HistoryFiles()

    func t(_ key: String, _ args: CVarArg...) -> String {
        let template = L10n.strings[key]?[language] ?? L10n.strings[key]?[.en] ?? key
        if args.isEmpty { return template }
        return String(format: template, arguments: args)
    }

    // MARK: Derived

    var breakdown: [ModelStat] {
        Aggregation.modelBreakdown(transactions, window: window)
    }
    var sparkValues: [Double] {
        Aggregation.sparkline(balancePoints)
    }

    /// Shown when the selected window reaches further back than the data does,
    /// which is why 7d/30d/All can read identically on a fresh install.
    var coverageNote: String? {
        guard let c = Aggregation.coverage(transactions), c.isTruncated(for: window) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: language.localeIdentifier)
        f.dateFormat = c.days < 1 ? "HH:mm" : "d. MMM"
        return t("label.coverage", f.string(from: c.oldest))
    }
    var menuBarTitle: String {
        guard let c = credits else { return " –" }
        return " \(Int(c.rounded()))"
    }
    var isLow: Bool {
        guard let c = credits else { return false }
        return c < config.warnBelowCredits
    }

    func windowLabel(_ w: StatsWindow) -> String {
        switch w {
        case .days7: return t("window.7d")
        case .days30: return t("window.30d")
        case .all: return t("window.all")
        }
    }

    // MARK: State transitions (call on main queue only)

    /// Show last known data immediately at launch, marked stale.
    func loadCached() {
        transactions = files.loadTransactions()
        balancePoints = files.loadBalance()
        if let last = balancePoints.last {
            credits = last.credits
            lastUpdated = last.timestamp
            isStale = true
        }
    }

    func apply(status: AccountStatus) {
        credits = status.credits
        plan = status.subscriptionPlanType
        email = status.email
        lastUpdated = Date()
        isStale = false
        errorMessage = nil
        needsAuth = false
        needsCLI = false
        cliIssue = nil
        needsWorkspace = false
        workspaceError = nil
        let pts = BalanceHistory.appendPrune(
            balancePoints,
            adding: BalancePoint(timestamp: Date(), credits: status.credits))
        balancePoints = pts
        files.saveBalance(pts)
    }

    func apply(newTransactions: [Transaction]) {
        let merged = HistoryMerge.merge(existing: transactions, new: newTransactions)
        transactions = merged
        files.saveTransactions(merged)
    }

    func fail(_ message: String) {
        isLoading = false
        isStale = true
        let msg = L10n.strings[message] != nil ? t(message) : message
        // A missing CLI, an unselected workspace and an auth failure are all
        // recoverable in-app, via their own buttons — so each gets its own UI
        // state instead of a generic error box the user cannot act on.
        needsCLI = message == "error.cli_missing"
        needsWorkspace = !needsCLI && WorkspaceState.isMissingSelection(message)
        needsAuth = !needsCLI && !needsWorkspace && AuthState.isAuthFailure(message)
        errorMessage = (needsCLI || needsWorkspace || needsAuth) ? nil : msg
        publishSnapshot(error: msg)
    }

    // MARK: Widget snapshot

    func publishSnapshot(error: String? = nil) {
        let top = breakdown.prefix(3).map {
            CreditsSnapshot.Model(name: $0.name, credits: $0.creditsSpent, generations: $0.generations)
        }
        let snap = CreditsSnapshot(
            credits: credits ?? 0,
            plan: plan,
            topModels: Array(top),
            windowLabel: windowLabel(window),
            warnBelow: config.warnBelowCredits,
            updatedAt: lastUpdated ?? Date(),
            error: error)
        SharedStore.write(snap)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func persistWindow() {
        config.statsWindow = window.rawValue
        config.save()
        publishSnapshot()
    }
}
