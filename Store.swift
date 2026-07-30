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
    @Published var language: Lang = .en

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
        // An auth failure is recoverable in-app via the sign-in button, so it
        // gets its own UI state instead of the generic error box.
        needsAuth = AuthState.isAuthFailure(message)
        errorMessage = needsAuth ? nil : msg
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
