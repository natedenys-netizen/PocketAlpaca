import Foundation

enum AlpacaError: LocalizedError {
    case noToken
    case http(Int, String)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .noToken:              return "No Alpaca token. Open Settings and paste one."
        case .http(let code, let body):
            if code == 401 || code == 403 { return "Alpaca rejected the token (HTTP \(code)). Revoke it and sign in again." }
            return "Alpaca returned HTTP \(code). \(body.prefix(140))"
        case .decoding(let msg):    return "Could not read Alpaca's response: \(msg)"
        case .transport(let msg):   return "Network problem: \(msg)"
        }
    }
}

protocol AlpacaClient: Sendable {
    func account() async throws -> Account
    func positions() async throws -> [Position]
    func orders(open: Bool, limit: Int) async throws -> [Order]
    func portfolioHistory(_ range: ChartRange, accountCreated: Date?) async throws -> PortfolioHistory
    func clock() async throws -> MarketClock
    func fills(limit: Int) async throws -> [Fill]
}

/// Read-only client. Every call is GET; nothing here can place or change an order.
struct LiveAlpacaClient: AlpacaClient {
    let environment: AlpacaEnvironment
    let token: String

    // Alpaca sends RFC 3339 with or without fractional seconds, e.g.
    // "2026-10-14T13:30:00.123456Z" or "2026-10-14T13:30:00-04:00".
    // Format styles are value types (Sendable), so the closure can use them safely.
    private static let isoFractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let isoPlain = Date.ISO8601FormatStyle()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = try? LiveAlpacaClient.isoFractional.parse(s) { return date }
            if let date = try? LiveAlpacaClient.isoPlain.parse(s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unrecognized date: \(s)")
        }
        return d
    }()

    private func get<T: Decodable>(_ path: String, _ query: [URLQueryItem] = []) async throws -> T {
        var comps = URLComponents(url: environment.tradingBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw AlpacaError.transport(error.localizedDescription)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            throw AlpacaError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw AlpacaError.decoding(String(describing: error))
        }
    }

    func account() async throws -> Account { try await get("account") }

    func positions() async throws -> [Position] { try await get("positions") }

    func orders(open: Bool, limit: Int = 50) async throws -> [Order] {
        try await get("orders", [
            .init(name: "status", value: open ? "open" : "closed"),
            .init(name: "limit", value: String(limit)),
            .init(name: "direction", value: "desc"),
        ])
    }

    func portfolioHistory(_ range: ChartRange, accountCreated: Date?) async throws -> PortfolioHistory {
        try await get("account/portfolio/history", range.query(accountCreated: accountCreated))
    }

    func clock() async throws -> MarketClock { try await get("clock") }

    func fills(limit: Int = 100) async throws -> [Fill] {
        try await get("account/activities/FILL", [
            .init(name: "page_size", value: String(min(max(limit, 1), 100))),
            .init(name: "direction", value: "desc"),
        ])
    }
}

/// Sample data for Xcode previews and for the simulator before a token exists.
struct MockAlpacaClient: AlpacaClient {
    func account() async throws -> Account {
        Account(id: "mock", accountNumber: "PA3XXXX", status: "ACTIVE", currency: "USD",
                equity: .init(3062.70), lastEquity: .init(3056.30), buyingPower: .init(9137.45),
                cash: .init(1200), portfolioValue: .init(3062.70),
                longMarketValue: .init(1480.12), shortMarketValue: .init(-382.40),
                daytradeCount: 0, patternDayTrader: false, createdAt: Date().addingTimeInterval(-400 * 86400))
    }

    func positions() async throws -> [Position] {
        [
            Position(assetId: "1", symbol: "MSBI", exchange: "NASDAQ", assetClass: "us_equity", side: "long",
                     qty: .init(7), qtyAvailable: .init(7), avgEntryPrice: .init(33.15), currentPrice: .init(33.42),
                     lastdayPrice: .init(33.10), changeToday: .init(0.0097), marketValue: .init(233.94), costBasis: .init(232.05),
                     unrealizedPl: .init(1.89), unrealizedPlpc: .init(0.0081), unrealizedIntradayPl: .init(2.24), unrealizedIntradayPlpc: .init(0.0097)),
            Position(assetId: "2", symbol: "AMCR", exchange: "NYSE", assetClass: "us_equity", side: "short",
                     qty: .init(-5), qtyAvailable: .init(-5), avgEntryPrice: .init(42.29), currentPrice: .init(42.61),
                     lastdayPrice: .init(42.20), changeToday: .init(0.0097), marketValue: .init(-213.05), costBasis: .init(-211.45),
                     unrealizedPl: .init(-1.60), unrealizedPlpc: .init(-0.0076), unrealizedIntradayPl: .init(-2.05), unrealizedIntradayPlpc: .init(-0.0097)),
            Position(assetId: "3", symbol: "CM", exchange: "NYSE", assetClass: "us_equity", side: "short",
                     qty: .init(-2), qtyAvailable: .init(-2), avgEntryPrice: .init(112.76), currentPrice: .init(111.90),
                     lastdayPrice: .init(112.40), changeToday: .init(-0.0044), marketValue: .init(-223.80), costBasis: .init(-225.52),
                     unrealizedPl: .init(1.72), unrealizedPlpc: .init(0.0076), unrealizedIntradayPl: .init(1.00), unrealizedIntradayPlpc: .init(0.0044)),
        ]
    }

    func orders(open: Bool, limit: Int) async throws -> [Order] {
        let now = Date()
        return [
            Order(id: "o1", clientOrderId: nil, createdAt: now.addingTimeInterval(-3600), submittedAt: now.addingTimeInterval(-3600), filledAt: nil, canceledAt: nil,
                  symbol: "CM", qty: .init(2), filledQty: .init(0), filledAvgPrice: .init(nil), type: "trailing_stop", side: "buy", timeInForce: "gtc",
                  limitPrice: .init(nil), stopPrice: .init(117.30), trailPercent: .init(2), trailPrice: .init(nil), hwm: .init(114.99), status: "new", orderClass: "simple"),
            Order(id: "o2", clientOrderId: nil, createdAt: now.addingTimeInterval(-7200), submittedAt: now.addingTimeInterval(-7200), filledAt: now.addingTimeInterval(-7190), canceledAt: nil,
                  symbol: "MSBI", qty: .init(7), filledQty: .init(7), filledAvgPrice: .init(33.15), type: "market", side: "buy", timeInForce: "day",
                  limitPrice: .init(nil), stopPrice: .init(nil), trailPercent: .init(nil), trailPrice: .init(nil), hwm: .init(nil), status: "filled", orderClass: "simple"),
        ].filter { open ? $0.isOpen : !$0.isOpen }
    }

    func portfolioHistory(_ range: ChartRange, accountCreated: Date?) async throws -> PortfolioHistory {
        let n = 60
        let start = Int(Date().timeIntervalSince1970) - n * 300
        var eq: [Double?] = []
        var v = 3056.0
        for i in 0..<n { v += Double((i * 7919) % 11) * 0.3 - 1.2; eq.append(v) }
        return PortfolioHistory(timestamp: (0..<n).map { start + $0 * 300 }, equity: eq,
                                profitLoss: eq.map { ($0 ?? 0) - 3056 }, profitLossPct: eq.map { (($0 ?? 0) - 3056) / 3056 },
                                baseValue: 3056, timeframe: "5Min")
    }

    func clock() async throws -> MarketClock {
        let now = Date()
        return MarketClock(timestamp: now, isOpen: false, nextOpen: now.addingTimeInterval(14 * 3600), nextClose: now.addingTimeInterval(20.5 * 3600))
    }

    func fills(limit: Int) async throws -> [Fill] {
        let now = Date()
        func f(_ id: String, _ ago: TimeInterval, _ sym: String, _ side: String, _ qty: Double, _ px: Double) -> Fill {
            Fill(id: id, activityType: "FILL", transactionTime: now.addingTimeInterval(-ago), type: "fill",
                 price: .init(px), qty: .init(qty), side: side, symbol: sym, leavesQty: .init(0), orderId: nil, cumQty: .init(qty))
        }
        return [
            f("f1", 2 * 3600, "MSBI", "buy", 7, 33.15),
            f("f2", 3 * 3600, "AMCR", "sell_short", 5, 42.29),
            f("f3", 26 * 3600, "CM", "sell_short", 2, 112.76),
            f("f4", 27 * 3600, "GSG", "sell", 10, 21.40),
            f("f5", 3 * 86400, "GSG", "buy", 10, 21.05),
        ]
    }
}
