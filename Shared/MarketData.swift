import Foundation

// Bars straight from Alpaca's Market Data API, fetched by the phone with the
// same OAuth token (it needs the `data` scope). This never touches the
// Apps Script quota: the request goes from the phone to Alpaca.

struct Bar: Codable, Hashable, Identifiable {
    let t: Date
    let o: Double
    let h: Double
    let l: Double
    let c: Double
    let v: Double?
    var id: Date { t }
    var isUp: Bool { c >= o }
}

struct BarsResponse: Codable {
    let bars: [Bar]?
    let symbol: String?
    let nextPageToken: String?
    enum CodingKeys: String, CodingKey { case bars, symbol; case nextPageToken = "next_page_token" }
}

enum BarTimeframe: String, CaseIterable, Identifiable {
    case day, hour, fifteen
    var id: String { rawValue }
    var label: String { self == .day ? "Daily" : (self == .hour ? "Hourly" : "15 min") }
    var apiValue: String { self == .day ? "1Day" : (self == .hour ? "1Hour" : "15Min") }
    /// How far back to ask for, and how many bars to keep.
    var lookback: TimeInterval { self == .day ? 400 * 86400 : (self == .hour ? 40 * 86400 : 8 * 86400) }
    var keep: Int { self == .day ? 160 : 200 }
}

enum MarketDataError: LocalizedError {
    case noDataScope
    case other(String)
    var errorDescription: String? {
        switch self {
        case .noDataScope:
            return "This token can't read market data. Sign in once more with the data scope: run the OAuth script with --scope data, then provision the simulator again."
        case .other(let m): return m
        }
    }
}

extension LiveAlpacaClient {
    static let dataBaseURL = URL(string: "https://data.alpaca.markets/v2")!

    /// Recent bars for a symbol, oldest first.
    func bars(symbol: String, timeframe: BarTimeframe) async throws -> [Bar] {
        var comps = URLComponents(url: Self.dataBaseURL.appendingPathComponent("stocks/\(symbol)/bars"), resolvingAgainstBaseURL: false)!
        let start = Date().addingTimeInterval(-timeframe.lookback)
        comps.queryItems = [
            .init(name: "timeframe", value: timeframe.apiValue),
            .init(name: "start", value: start.formatted(.iso8601)),
            .init(name: "limit", value: "10000"),
            .init(name: "adjustment", value: "split"),
            .init(name: "feed", value: "iex"),
            .init(name: "sort", value: "asc"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: req) }
        catch { throw MarketDataError.other("Network problem: \(error.localizedDescription)") }
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        if code == 401 || code == 403 { throw MarketDataError.noDataScope }
        guard (200..<300).contains(code) else {
            throw MarketDataError.other("Alpaca market data returned HTTP \(code). \(String(data: data, encoding: .utf8)?.prefix(120) ?? "")")
        }
        let decoder = JSONDecoder()
        let frac = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let plain = Date.ISO8601FormatStyle()
        decoder.dateDecodingStrategy = .custom { d in
            let c = try d.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = try? frac.parse(s) { return date }
            if let date = try? plain.parse(s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad date \(s)")
        }
        let resp: BarsResponse
        do { resp = try decoder.decode(BarsResponse.self, from: data) }
        catch { throw MarketDataError.other("Could not read bars: \(error)") }
        let all = (resp.bars ?? []).filter { $0.h.isFinite && $0.l.isFinite && $0.o.isFinite && $0.c.isFinite }
        return Array(all.suffix(timeframe.keep))
    }
}

extension MockAlpacaClient {
    /// A deterministic random walk so previews and the sample mode have candles.
    func bars(symbol: String, timeframe: BarTimeframe) -> [Bar] {
        var seed = UInt64(symbol.utf8.reduce(7) { $0 &* 31 &+ UInt64($1) })
        func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        var price = 20 + rnd() * 80
        let step: TimeInterval = timeframe == .day ? 86400 : (timeframe == .hour ? 3600 : 900)
        let n = timeframe.keep
        let start = Date().addingTimeInterval(-Double(n) * step)
        return (0..<n).map { i in
            let o = price
            let c = max(1, o * (1 + (rnd() - 0.48) * 0.03))
            let h = max(o, c) * (1 + rnd() * 0.012)
            let l = min(o, c) * (1 - rnd() * 0.012)
            price = c
            return Bar(t: start.addingTimeInterval(Double(i) * step), o: o, h: h, l: l, c: c, v: 1000 + rnd() * 5000)
        }
    }
}

// MARK: - Harmonic math shared by the detector's points and the planner

/// A pivot the scanner matched, or one the user tapped.
struct PricePoint: Hashable, Identifiable {
    let label: String      // "X", "A", "B", "C", "D"
    let price: Double
    let index: Int?        // bar index on the current chart, when known
    var id: String { label }
}

enum HarmonicMath {
    /// The CD extensions the detector accepts (1.20–1.68 of BC); 1.272 and
    /// 1.618 are the classic completion levels.
    static let dExtensions: [Double] = [1.272, 1.618]

    struct ABCDPlan: Hashable {
        let bullish: Bool            // A high → B low → C high → D low (buy at D)
        let retraceBC: Double        // BC as a fraction of AB
        let dLevels: [(ratio: Double, price: Double)]
        let entry: Double            // first completion (1.272)
        let stop: Double             // 1% beyond the far completion (1.618)
        let target: Double           // 61.8% retrace of the CD leg from the entry
        var isValidShape: Bool { retraceBC >= 0.35 && retraceBC <= 0.92 }

        static func == (a: ABCDPlan, b: ABCDPlan) -> Bool { a.entry == b.entry && a.stop == b.stop && a.target == b.target }
        func hash(into h: inout Hasher) { h.combine(entry); h.combine(stop); h.combine(target) }
    }

    /// Projects D from A, B, C. Direction comes from the AB leg: a falling AB
    /// means a bullish ABCD (buy the D low); a rising AB means bearish.
    static func abcd(a: Double, b: Double, c: Double) -> ABCDPlan? {
        let ab = b - a
        let bc = c - b
        guard ab != 0, bc != 0, (ab > 0) != (bc > 0) else { return nil }   // legs must alternate
        let bullish = ab < 0
        let retrace = abs(bc) / abs(ab)
        let sign: Double = bullish ? -1 : 1                                  // CD continues the AB direction
        let levels = dExtensions.map { k in (ratio: k, price: c + sign * k * abs(bc)) }
        let entry = levels[0].price
        let far = levels[1].price
        let stop = bullish ? far * 0.99 : far * 1.01
        let target = entry + (c - entry) * 0.618
        return ABCDPlan(bullish: bullish, retraceBC: retrace, dLevels: levels, entry: entry, stop: stop, target: target)
    }
}
