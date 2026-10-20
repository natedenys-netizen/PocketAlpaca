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
    let trailPercent: StringDouble
    let trailPrice: StringDouble
    let hwm: StringDouble               // high-water mark a trailing stop trails from
    let status: String
    let orderClass: String?

    enum CodingKeys: String, CodingKey {
        case id, symbol, qty, type, side, status, hwm
        case trailPercent = "trail_percent"
        case trailPrice = "trail_price"
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

    var isStopOrder: Bool { type.lowercased().contains("stop") }

    /// How far the market is from triggering this stop, as a fraction of the
    /// current price (always positive; 0.012 = 1.2% away). Nil when it does
    /// not apply or the stop has already been passed.
    func stopDistance(currentPrice: Double?) -> Double? {
        guard isStopOrder, let stop = stopPrice.value, let px = currentPrice, px > 0 else { return nil }
        let d = side.lowercased() == "buy" ? (stop - px) / px : (px - stop) / px
        return d >= 0 ? d : nil
    }

    /// "trail 2%" or "trail $1.50" for trailing stops; nil otherwise.
    var trailDescription: String? {
        if let p = trailPercent.value { return "trail \(p.formatted(.number.precision(.fractionLength(0...2))))%" }
        if let p = trailPrice.value { return "trail $\(p.formatted(.number.precision(.fractionLength(2))))" }
        return nil
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

/// GET /v2/clock
struct MarketClock: Codable, Hashable {
    let timestamp: Date
    let isOpen: Bool
    let nextOpen: Date
    let nextClose: Date

    enum CodingKeys: String, CodingKey {
        case timestamp
        case isOpen = "is_open"
        case nextOpen = "next_open"
        case nextClose = "next_close"
    }

    /// "Market open · closes 2:00 PM" / "Market closed · opens Mon 7:30 AM", in the device's time zone.
    var summary: String {
        let cal = Calendar.current
        func when(_ d: Date) -> String {
            let time = d.formatted(date: .omitted, time: .shortened)
            if cal.isDateInToday(d) { return time }
            if cal.isDateInTomorrow(d) { return "tomorrow \(time)" }
            return d.formatted(.dateTime.weekday(.abbreviated)) + " " + time
        }
        return isOpen ? "Market open · closes \(when(nextClose))" : "Market closed · opens \(when(nextOpen))"
    }
}

/// One execution from GET /v2/account/activities/FILL.
struct Fill: Codable, Hashable, Identifiable {
    let id: String
    let activityType: String?
    let transactionTime: Date
    let type: String            // "fill" or "partial_fill"
    let price: StringDouble
    let qty: StringDouble
    let side: String            // "buy", "sell", "sell_short"
    let symbol: String
    let leavesQty: StringDouble
    let orderId: String?
    let cumQty: StringDouble

    enum CodingKeys: String, CodingKey {
        case id, type, price, qty, side, symbol
        case activityType = "activity_type"
        case transactionTime = "transaction_time"
        case leavesQty = "leaves_qty"
        case orderId = "order_id"
        case cumQty = "cum_qty"
    }

    var isBuy: Bool { side.lowercased() == "buy" }
    var sideLabel: String {
        switch side.lowercased() {
        case "buy": return "BUY"
        case "sell_short": return "SHORT"
        default: return "SELL"
        }
    }
    var notional: Double? {
        guard let p = price.value, let q = qty.value else { return nil }
        return p * q
    }
    var isPartial: Bool { type.lowercased() == "partial_fill" }
}
