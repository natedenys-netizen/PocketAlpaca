import Foundation
import Observation

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

    var isRefreshing = false
    var lastRefresh: Date?
    var lastError: String?

    /// True while there is no token: the UI shows sample data with a banner.
    var isUsingSampleData: Bool { !hasToken }

    private var client: AlpacaClient

    init() {
        let env = TokenStore.environment
        let token = TokenStore.load()
        environment = env
        hasToken = token != nil
        client = token.map { LiveAlpacaClient(environment: env, token: $0) } ?? MockAlpacaClient()
    }

    // MARK: - Token / environment

    func setToken(_ token: String) {
        guard TokenStore.save(token) else { return }
        hasToken = true
        rebuildClient()
        clearData()
        Task { await refreshAll() }
    }

    func clearToken() {
        TokenStore.delete()
        hasToken = false
        rebuildClient()
        clearData()
        Task { await refreshAll() }
    }

    func setEnvironment(_ env: AlpacaEnvironment) {
        guard env != environment else { return }
        environment = env
        TokenStore.environment = env
        rebuildClient()
        clearData()
        Task { await refreshAll() }
    }

    private func rebuildClient() {
        if let token = TokenStore.load() {
            client = LiveAlpacaClient(environment: environment, token: token)
        } else {
            client = MockAlpacaClient()
        }
    }

    private func clearData() {
        account = nil; positions = []; openOrders = []; recentOrders = []; history = [:]
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
            let (acct, pos, open, recent) = try await (a, p, o, r)
            account = acct
            positions = pos.sorted { $0.symbol < $1.symbol }
            openOrders = open
            recentOrders = recent
            lastError = nil
            lastRefresh = Date()
        } catch {
            lastError = (error as? AlpacaError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadHistory(_ range: ChartRange, force: Bool = false) async {
        if !force, history[range] != nil { return }
        do {
            history[range] = try await client.portfolioHistory(range)
        } catch {
            lastError = (error as? AlpacaError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Derived

    var totalUnrealizedPl: Double { positions.compactMap { $0.unrealizedPl.value }.reduce(0, +) }
    var winners: Int { positions.filter { ($0.unrealizedPl.value ?? 0) > 0 }.count }
    var losers: Int { positions.filter { ($0.unrealizedPl.value ?? 0) < 0 }.count }
}
