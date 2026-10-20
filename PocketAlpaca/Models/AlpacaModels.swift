import Foundation

// Alpaca returns most numbers as strings ("12.34"). These wrappers decode
// either a string or a number into a Double, and tolerate null.

struct StringDouble: Codable, Hashable {
    let value: Double?

    init(_ value: Double?) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = nil; return }
        if let d = try? c.decode(Double.self) { value = d; return }
        if let s = try? c.decode(String.self) { value = Double(s); return }
        value = nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let v = value { try c.encode(v) } else { try c.encodeNil() }
    }
}

enum AlpacaEnvironment: String, CaseIterable, Codable, Identifiable {
    case paper, live
    var id: String { rawValue }

    var tradingBaseURL: URL {
        switch self {
        case .paper: return URL(string: "https://paper-api.alpaca.markets/v2")!
        case .live:  return URL(string: "https://api.alpaca.markets/v2")!
        }
    }

    var label: String { self == .paper ? "Paper" : "Live" }
}

struct Account: Codable, Hashable {
    let id: String
    let accountNumber: String?
    let status: String?
    let currency: String?
    let equity: StringDouble
    let lastEquity: StringDouble
    let buyingPower: StringDouble
    let cash: StringDouble
    let portfolioValue: StringDouble
    let longMarketValue: StringDouble
    let shortMarketValue: StringDouble
    let daytradeCount: Int?
    let patternDayTrader: Bool?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status, currency, equity, cash
        case createdAt = "created_at"
        case accountNumber = "account_number"
        case lastEquity = "last_equity"
        case buyingPower = "buying_power"
        case portfolioValue = "portfolio_value"
        case longMarketValue = "long_market_value"
        case shortMarketValue = "short_market_value"
        case daytradeCount = "daytrade_count"
        case patternDayTrader = "pattern_day_trader"
    }

    /// Dollar change since the previous close, from Alpaca's own last_equity.
    var dayChange: Double? {
        guard let e = equity.value, let l = lastEquity.value else { return nil }
        return e - l
    }

    /// Fractional change since the previous close (0.0123 = +1.23%).
    var dayChangePct: Double? {
        guard let e = equity.value, let l = lastEquity.value, l != 0 else { return nil }
        return (e - l) / l
    }
}

struct Position: Codable, Hashable, Identifiable {
    let assetId: String
    let symbol: String
    let exchange: String?
    let assetClass: String?
    let side: String            // "long" or "short"
    let qty: StringDouble
    let qtyAvailable: StringDouble
    let avgEntryPrice: StringDouble
    let currentPrice: StringDouble
    let lastdayPrice: StringDouble
    let changeToday: StringDouble
    let marketValue: StringDouble
    let costBasis: StringDouble
    let unrealizedPl: StringDouble
    let unrealizedPlpc: StringDouble        // fraction, e.g. -0.0123
    let unrealizedIntradayPl: StringDouble
    let unrealizedIntradayPlpc: StringDouble

    var id: String { assetId }

    enum CodingKeys: String, CodingKey {
        case symbol, exchange, side, qty
        case assetId = "asset_id"
        case assetClass = "asset_class"
        case qtyAvailable = "qty_available"
        case avgEntryPrice = "avg_entry_price"
        case currentPrice = "current_price"
        case lastdayPrice = "lastday_price"
        case changeToday = "change_today"
        case marketValue = "market_value"
        case costBasis = "cost_basis"
        case unrealizedPl = "unrealized_pl"
        case unrealizedPlpc = "unrealized_plpc"
        case unrealizedIntradayPl = "unrealized_intraday_pl"
        case unrealizedIntradayPlpc = "unrealized_intraday_plpc"
    }

    var isShort: Bool { side.lowercased() == "short" }

    /// Signed share count: negative for shorts, matching how the broker reports qty.
    var signedQty: Double { qty.value ?? 0 }
}

struct Order: Codable, Hashable, Identifiable {
    let id: String
    let clientOrderId: String?
    let createdAt: Date?
    let submittedAt: Date?
    let filledAt: Date?
    let canceledAt: Date?
    let symbol: String
    let qty: StringDouble
    let filledQty: StringDouble
    let filledAvgPrice: StringDouble
    let type: String
    let side: String
    let timeInForce: String?
    let limitPrice: StringDouble
    let stopPrice: StringDouble
    let status: String
    let orderClass: String?

    enum CodingKeys: String, CodingKey {
        case id, symbol, qty, type, side, status
        case clientOrderId = "client_order_id"
        case createdAt = "created_at"
        case submittedAt = "submitted_at"
        case filledAt = "filled_at"
        case canceledAt = "canceled_at"
        case filledQty = "filled_qty"
        case filledAvgPrice = "filled_avg_price"
        case timeInForce = "time_in_force"
        case limitPrice = "limit_price"
        case stopPrice = "stop_price"
        case orderClass = "order_class"
    }

    var isOpen: Bool {
        ["new", "accepted", "pending_new", "partially_filled", "held", "accepted_for_bidding"].contains(status.lowercased())
    }

    /// e.g. "Stop Buy GTC", "Market Sell Day"
    var summary: String {
        let t = type.replacingOccurrences(of: "_", with: " ").capitalized
        let s = side.capitalized
        let tif = (timeInForce ?? "").uppercased()
        return [t, s, tif].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

struct PortfolioHistory: Codable, Hashable {
    let timestamp: [Int]
    let equity: [Double?]
    let profitLoss: [Double?]
    let profitLossPct: [Double?]
    let baseValue: Double?
    let timeframe: String?

    enum CodingKeys: String, CodingKey {
        case timestamp, equity, timeframe
        case profitLoss = "profit_loss"
        case profitLossPct = "profit_loss_pct"
        case baseValue = "base_value"
    }

    struct Point: Identifiable, Hashable {
        let id: Int
        let date: Date
        let equity: Double
    }

    /// Chart points. Days before the account was funded come back as 0 (or null)
    /// and would flatten the whole chart, so leading non-positive points are dropped.
    var points: [Point] {
        let all = zip(timestamp, equity).compactMap { ts, eq -> Point? in
            guard let eq else { return nil }
            return Point(id: ts, date: Date(timeIntervalSince1970: TimeInterval(ts)), equity: eq)
        }
        guard let first = all.firstIndex(where: { $0.equity > 0 }) else { return [] }
        return Array(all[first...])
    }
}

enum ChartRange: String, CaseIterable, Identifiable {
    case day = "1D", month = "1M", year = "1Y", all = "All"
    var id: String { rawValue }

    /// Query parameters for GET /v2/account/portfolio/history.
    /// "All" starts at the account's creation date when known (Alpaca has no
    /// documented "all" period); otherwise it falls back to five years.
    func query(accountCreated: Date?) -> [URLQueryItem] {
        switch self {
        case .day:   return [.init(name: "period", value: "1D"), .init(name: "timeframe", value: "5Min"), .init(name: "intraday_reporting", value: "extended_hours")]
        case .month: return [.init(name: "period", value: "1M"), .init(name: "timeframe", value: "1D")]
        case .year:  return [.init(name: "period", value: "1A"), .init(name: "timeframe", value: "1D")]
        case .all:
            if let created = accountCreated {
                // Without an explicit end, Alpaca applies its default one-month
                // period on top of `start`; send both ends of the window.
                return [.init(name: "start", value: created.formatted(.iso8601)),
                        .init(name: "end", value: Date().formatted(.iso8601)),
                        .init(name: "timeframe", value: "1D")]
            }
            return [.init(name: "period", value: "5A"), .init(name: "timeframe", value: "1D")]
        }
    }
}
