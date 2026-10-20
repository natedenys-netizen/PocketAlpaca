import Foundation
import Observation
import WidgetKit

/// One source of truth for the whole app: which client to use, the latest
/// account/positions/orders, and any error to show. Refreshes on demand and
/// on a foreground timer; never writes anything to Alpaca.
@MainActor
@Observable
final class AppModel {
    var environment: AlpacaEnvironment
    private(set) var hasToken: Bool

    var account: Account?
    var positions: [Position] = []
    var openOrders: [Order] = []
    var recentOrders: [Order] = []
    var history: [ChartRange: PortfolioHistory] = [:]
    var clock: MarketClock?
    var fills: [Fill] = []

    // Signals (the engines' candidate lists), fetched separately from Alpaca.
    var signals: SignalsPayload?
    var signalsError: String?
    var signalsLoadedAt: Date?
    var signalsFilter: SignalsFilter = TokenStore.signalsFilter {
        didSet {
            guard signalsFilter != oldValue else { return }
            TokenStore.signalsFilter = signalsFilter
            Task { await loadSignals(force: true) }
        }
    }

    var isRefreshing = false
    var lastRefresh: Date?
    var lastError: String?

    /// What the last Mac-side provisioning did (simulator only), for Settings.
    var provisionNote: String? = Provisioning.lastSummary

    var appearance: Appearance = TokenStore.appearance {
        didSet { TokenStore.appearance = appearance }
    }
    var theme: Theme = TokenStore.theme {
        didSet { TokenStore.theme = theme; WidgetCenter.shared.reloadAllTimelines() }
    }

    /// True while there is no token: the UI shows sample data with a banner.
    var isUsingSampleData: Bool { !hasToken }

    private var client: AlpacaClient

    init() {
        let env = TokenStore.environment
        let token = TokenStore.load(for: env)
        environment = env
        hasToken = token != nil
        client = token.map { LiveAlpacaClient(environment: env, token: $0) } ?? MockAlpacaClient()
    }

    // MARK: - Token / environment

    /// True when a token is saved for the given environment (not necessarily the current one).
    func hasToken(for env: AlpacaEnvironment) -> Bool { TokenStore.load(for: env) != nil }

    /// Saves the token for the CURRENT environment and reloads.
    func setToken(_ token: String) {
        guard TokenStore.save(token, for: environment) else { return }
        rebuildClient()
        clearData()
        Task { await refreshAll() }
    }

    /// Removes the CURRENT environment's token and falls back to sample data.
    func clearToken() {
        TokenStore.delete(for: environment)
        rebuildClient()
        clearData()
        Task { await refreshAll() }
    }

    /// Switches environment; each environment keeps its own token.
    func setEnvironment(_ env: AlpacaEnvironment) {
        guard env != environment else { return }
        environment = env
        TokenStore.environment = env
        rebuildClient()
        clearData()
        Task { await refreshAll() }
    }

    /// Simulator only: picks up a drop file written while the app is running,
    /// then re-reads every stored setting. Cheap when there is nothing waiting.
    func applyProvisioningIfPresent() async {
        guard Provisioning.dropFileExists, let note = Provisioning.applyDropFileIfPresent() else { return }
        provisionNote = note
        environment = TokenStore.environment
        rebuildClient()
        clearData()
        await refreshAll()
        await loadSignals(force: true)
    }

    private func rebuildClient() {
        WidgetCenter.shared.reloadAllTimelines()
        if let token = TokenStore.load(for: environment) {
            client = LiveAlpacaClient(environment: environment, token: token)
            hasToken = true
        } else {
            client = MockAlpacaClient()
            hasToken = false
        }
    }

    private func clearData() {
        account = nil; positions = []; openOrders = []; recentOrders = []; history = [:]; clock = nil; fills = []
        lastError = nil; lastRefresh = nil
    }

    // MARK: - Refresh

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            async let a = client.account()
            async let p = client.positions()
            async let o = client.orders(open: true, limit: 50)
            async let r = client.orders(open: false, limit: 30)
            async let c = client.clock()
            async let f = client.fills(limit: 100)
            let (acct, pos, open, recent, clk, fl) = try await (a, p, o, r, c, f)
            account = acct
            positions = pos.sorted { $0.symbol < $1.symbol }
            openOrders = open
            recentOrders = recent
            clock = clk
            fills = fl.sorted { $0.transactionTime > $1.transactionTime }
            lastError = nil
            lastRefresh = Date()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            lastError = (error as? AlpacaError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadHistory(_ range: ChartRange, force: Bool = false) async {
        if !force, history[range] != nil { return }
        do {
            if range == .all, account == nil {
                // "All" is anchored to the account's creation date; make sure we have it.
                account = try await client.account()
            }
            history[range] = try await client.portfolioHistory(range, accountCreated: account?.createdAt)
        } catch {
            lastError = (error as? AlpacaError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Signals

    var signalsConfigured: Bool { TokenStore.signalsEndpoint != nil && TokenStore.loadSignalsKey() != nil }

    func setSignals(endpoint: String, key: String) {
        let trimmedURL = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        TokenStore.signalsEndpoint = URL(string: trimmedURL)
        if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { TokenStore.saveSignalsKey(key) }
        signals = nil; signalsError = nil; signalsLoadedAt = nil
        Task { await loadSignals(force: true) }
    }

    func clearSignals() {
        TokenStore.signalsEndpoint = nil
        TokenStore.deleteSignalsKey()
        signals = nil; signalsError = nil; signalsLoadedAt = nil
    }

    /// Fetches the candidate lists. Cached for two minutes unless forced; the
    /// endpoint itself caches for one, so pull-to-refresh is cheap either way.
    func loadSignals(force: Bool = false) async {
        guard let url = TokenStore.signalsEndpoint, let key = TokenStore.loadSignalsKey() else {
            signalsError = SignalsError.notConfigured.errorDescription
            return
        }
        if !force, let t = signalsLoadedAt, Date().timeIntervalSince(t) < 120, signals != nil { return }
        do {
            signals = try await SignalsClient(endpoint: url, key: key).fetch(filter: signalsFilter)
            signalsError = nil
            signalsLoadedAt = Date()
        } catch {
            signalsError = (error as? SignalsError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Derived

    /// Current price of an open position, used to show how far a stop order is from triggering.
    func currentPrice(for symbol: String) -> Double? {
        positions.first { $0.symbol == symbol }?.currentPrice.value
    }

    /// Open orders (usually the protective stop) for one symbol.
    func openOrders(for symbol: String) -> [Order] { openOrders.filter { $0.symbol == symbol } }

    /// Recent fills for one symbol, newest first.
    func fills(for symbol: String) -> [Fill] { fills.filter { $0.symbol == symbol } }

    var totalUnrealizedPl: Double { positions.compactMap { $0.unrealizedPl.value }.reduce(0, +) }
    var winners: Int { positions.filter { ($0.unrealizedPl.value ?? 0) > 0 }.count }
    var losers: Int { positions.filter { ($0.unrealizedPl.value ?? 0) < 0 }.count }
}
