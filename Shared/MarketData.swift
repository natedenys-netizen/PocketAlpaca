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

/// The five harmonic shapes the scanner detects, with its exact ratio windows
/// (Universe 1b/02_pattern_detectors.js). ABCD has no X leg; the other four
/// are the same machinery with different ratios and project D from XA.
enum HarmonicPattern: String, CaseIterable, Identifiable, Hashable {
    case abcd, gartley, bat, butterfly, crab
    var id: String { rawValue }
    var label: String { self == .abcd ? "ABCD" : rawValue.capitalized }
    var usesX: Bool { self != .abcd }
    /// The points the planner needs before it can project D, in tap order.
    var inputLabels: [String] { usesX ? ["X", "A", "B", "C"] : ["A", "B", "C"] }

    struct Spec: Hashable {
        let abXA: ClosedRange<Double>?   // AB as a fraction of XA (nil for ABCD)
        let bcAB: ClosedRange<Double>    // BC as a fraction of AB
        let cdBC: ClosedRange<Double>    // CD as a multiple of BC
        let adXA: ClosedRange<Double>?   // AD as a fraction of XA (nil for ABCD)
        let idealAD: Double?             // the classic completion level, as a fraction of XA
        let targetRetrace: Double        // the target retraces this much of AD (of CD for ABCD) from the entry
    }

    /// Inclusive windows, exactly as the detector tests them.
    var spec: Spec {
        switch self {
        case .abcd:      return Spec(abXA: nil,         bcAB: 0.35...0.92, cdBC: 1.20...1.68, adXA: nil,         idealAD: nil,   targetRetrace: 0.618)
        case .gartley:   return Spec(abXA: 0.58...0.68, bcAB: 0.35...0.92, cdBC: 1.20...1.68, adXA: 0.75...0.82, idealAD: 0.786, targetRetrace: 0.618)
        case .bat:       return Spec(abXA: 0.35...0.52, bcAB: 0.35...0.92, cdBC: 1.55...2.68, adXA: 0.85...0.92, idealAD: 0.886, targetRetrace: 0.5)
        case .butterfly: return Spec(abXA: 0.75...0.82, bcAB: 0.35...0.92, cdBC: 1.55...2.68, adXA: 1.20...1.68, idealAD: 1.27,  targetRetrace: 0.618)
        case .crab:      return Spec(abXA: 0.35...0.65, bcAB: 0.35...0.92, cdBC: 2.55...3.68, adXA: 1.55...1.68, idealAD: 1.618, targetRetrace: 0.618)
        }
    }

    /// The shape a scanner pattern name refers to ("Bullish Gartley" → gartley).
    static func named(_ name: String?) -> HarmonicPattern? {
        guard let n = name?.lowercased() else { return nil }
        return allCases.first { n.contains($0.rawValue) }
    }
}

enum HarmonicMath {
    struct Pivot: Hashable {
        enum Kind { case high, low }
        let kind: Kind
        let price: Double
        let index: Int
    }

    /// Exact port of the scanner's findPivots(closes, 5): a bar is a pivot high
    /// when its close is the maximum of the 11-bar window centred on it (low:
    /// the minimum), and an equal-price repeat within one window is skipped as
    /// the same plateau. Pivots need 5 bars on each side, so the newest 5 bars
    /// can never be pivots yet.
    static func findPivots(closes: [Double], window: Int = 5) -> [Pivot] {
        var pivots: [Pivot] = []
        guard closes.count > window * 2 else { return pivots }
        for i in window..<(closes.count - window) {
            let slice = closes[(i - window)...(i + window)]
            let centre = closes[i]
            if centre == slice.max() {
                if let lastHigh = pivots.last(where: { $0.kind == .high }), lastHigh.price == centre, (i - lastHigh.index) <= window { } else {
                    pivots.append(Pivot(kind: .high, price: centre, index: i))
                }
            }
            if centre == slice.min() {
                if let lastLow = pivots.last(where: { $0.kind == .low }), lastLow.price == centre, (i - lastLow.index) <= window { } else {
                    pivots.append(Pivot(kind: .low, price: centre, index: i))
                }
            }
        }
        return pivots
    }

    // MARK: Legs and plans

    /// The input legs of a pattern (X when the shape has one, then A, B, C).
    /// Direction comes from the first leg: a rising XA, or for ABCD a falling
    /// AB, is bullish (buy at D). Nil when the legs don't alternate.
    struct Legs: Hashable {
        let pattern: HarmonicPattern
        let bullish: Bool
        let x: Double?, a: Double, b: Double, c: Double
        var xa: Double? { x.map { abs(a - $0) } }
        var ab: Double { abs(a - b) }
        var bc: Double { abs(c - b) }
    }

    static func legs(pattern: HarmonicPattern, x: Double?, a: Double, b: Double, c: Double) -> Legs? {
        let bullish: Bool
        if pattern.usesX {
            guard let x, x != a else { return nil }
            bullish = a > x
        } else {
            guard a != b else { return nil }
            bullish = b < a
        }
        if bullish { guard b < a, c > b else { return nil } } else { guard b > a, c < b else { return nil } }
        return Legs(pattern: pattern, bullish: bullish, x: pattern.usesX ? x : nil, a: a, b: b, c: c)
    }

    struct Ratio: Hashable {
        let name: String
        let value: Double
        let band: ClosedRange<Double>
        var ok: Bool { band.contains(value) }
    }
    struct DLevel: Hashable { let label: String; let price: Double }

    struct Plan: Hashable {
        let pattern: HarmonicPattern
        let bullish: Bool
        let ratios: [Ratio]              // the input legs against the detector's windows
        let dLevels: [DLevel]            // projected D levels to draw
        let zone: ClosedRange<Double>?   // X-A-B-C shapes: prices where the detector would accept D (AD window ∩ CD window)
        let entry: Double
        let stop: Double
        let target: Double
        let warnings: [String]
        var shapeOK: Bool { ratios.allSatisfy(\.ok) }
        var levels: [Double] { [entry, stop, target] + dLevels.map(\.price) + (zone.map { [$0.lowerBound, $0.upperBound] } ?? []) }
    }

    /// Projects D for any of the five shapes from its input points.
    /// ABCD: D at 1.272 and 1.618 of BC beyond C; entry at the first, stop 1%
    /// beyond the far one, target a 61.8% retrace of CD.
    /// X-A-B-C shapes: D at the shape's classic fraction of XA beyond A
    /// (Gartley 0.786, Bat 0.886, Butterfly 1.27, Crab 1.618), kept inside the
    /// zone where the detector's AD and CD windows both hold; stop 1% beyond
    /// that zone's far edge; target a retrace of AD (50% Bat, 61.8% others).
    static func plan(pattern: HarmonicPattern, x: Double? = nil, a: Double, b: Double, c: Double) -> Plan? {
        guard let L = legs(pattern: pattern, x: x, a: a, b: b, c: c) else { return nil }
        let s = pattern.spec, bullish = L.bullish
        func beyond(_ from: Double, _ dist: Double) -> Double { bullish ? from - dist : from + dist }   // onward in the AB direction
        func span(_ p: Double, _ q: Double) -> ClosedRange<Double> { min(p, q)...max(p, q) }
        var ratios: [Ratio] = []
        var warnings: [String] = []
        if let xa = L.xa, let band = s.abXA { ratios.append(Ratio(name: "AB / XA", value: L.ab / xa, band: band)) }
        ratios.append(Ratio(name: "BC / AB", value: L.bc / L.ab, band: s.bcAB))

        if let xa = L.xa, let adBand = s.adXA, let ideal = s.idealAD {
            let adRange = span(beyond(L.a, adBand.lowerBound * xa), beyond(L.a, adBand.upperBound * xa))
            let cdRange = span(beyond(L.c, s.cdBC.lowerBound * L.bc), beyond(L.c, s.cdBC.upperBound * L.bc))
            let lo = max(adRange.lowerBound, cdRange.lowerBound), hi = min(adRange.upperBound, cdRange.upperBound)
            let zone: ClosedRange<Double>? = lo <= hi ? lo...hi : nil
            let idealD = beyond(L.a, ideal * xa)
            let entry = zone.map { min(max(idealD, $0.lowerBound), $0.upperBound) } ?? idealD
            if zone == nil {
                warnings.append("With these legs the AD window (\(pctBand(adBand)) of XA) and the CD window (\(multBand(s.cdBC)) BC) never overlap, so the detector could not complete a \(pattern.label) here. Levels use the AD window alone.")
            } else if entry != idealD {
                warnings.append("The classic D (\(ideal) of XA) falls outside the detector's joint window; the entry moved to its nearest edge.")
            }
            let used = zone ?? adRange
            let far = bullish ? used.lowerBound : used.upperBound
            let stop = bullish ? far * 0.99 : far * 1.01
            let target = bullish ? entry + s.targetRetrace * (L.a - entry) : entry - s.targetRetrace * (entry - L.a)
            ratios.append(Ratio(name: "CD / BC at D", value: abs(L.c - entry) / L.bc, band: s.cdBC))
            return Plan(pattern: pattern, bullish: bullish, ratios: ratios,
                        dLevels: [DLevel(label: "D \(ideal) XA", price: idealD)],
                        zone: zone, entry: entry, stop: stop, target: target, warnings: warnings)
        }
        let levels = [1.272, 1.618].map { DLevel(label: "D \($0)", price: beyond(L.c, $0 * L.bc)) }
        let entry = levels[0].price, far = levels[1].price
        let stop = bullish ? far * 0.99 : far * 1.01
        let target = entry + (L.c - entry) * s.targetRetrace
        return Plan(pattern: .abcd, bullish: bullish, ratios: ratios, dLevels: levels, zone: nil, entry: entry, stop: stop, target: target, warnings: warnings)
    }

    static func pctBand(_ r: ClosedRange<Double>) -> String {
        "\(Int((r.lowerBound * 100).rounded()))–\(Int((r.upperBound * 100).rounded()))%"
    }
    static func multBand(_ r: ClosedRange<Double>) -> String {
        "\(r.lowerBound.formatted(.number.precision(.fractionLength(2))))–\(r.upperBound.formatted(.number.precision(.fractionLength(2))))×"
    }

    // MARK: Finding patterns on a chart

    /// A pattern found from the chart's own pivots: X (when the shape has one),
    /// A, B, C in order, and D once it has printed.
    struct AutoPattern: Hashable {
        let pattern: HarmonicPattern
        let bullish: Bool
        let pivots: [Pivot]
        var inProgress: Bool { pivots.count == pattern.inputLabels.count }
        var d: Pivot? { inProgress ? nil : pivots.last }
        var points: [PricePoint] {
            zip(pattern.inputLabels + ["D"], pivots).map { PricePoint(label: $0, price: $1.price, index: $1.index) }
        }
    }

    /// The latest pattern of one shape and side on the chart, by the detector's
    /// own windows. Prefers an in-progress one (C is the newest pivot, D still
    /// ahead); otherwise the most recent completed one. Bullish ABCD is A high,
    /// B low, C high, D low; bullish X-A-B-C shapes start from an X low.
    static func latest(_ pattern: HarmonicPattern, pivots: [Pivot], bullish: Bool) -> AutoPattern? {
        let n = pattern.inputLabels.count
        let first: Pivot.Kind = bullish ? (pattern.usesX ? .low : .high) : (pattern.usesX ? .high : .low)
        let kinds: [Pivot.Kind] = (0...n).map { i in (i % 2 == 0) == (first == .low) ? .low : .high }
        let s = pattern.spec

        func inputsOK(_ w: ArraySlice<Pivot>) -> Legs? {
            guard w.count == n else { return nil }
            for (p, k) in zip(w, kinds) where p.kind != k { return nil }
            let arr = Array(w)
            let x = pattern.usesX ? arr[0].price : nil
            guard let L = legs(pattern: pattern, x: x, a: arr[n - 3].price, b: arr[n - 2].price, c: arr[n - 1].price), L.bullish == bullish else { return nil }
            if let xa = L.xa, let band = s.abXA { guard band.contains(L.ab / xa) else { return nil } }
            guard s.bcAB.contains(L.bc / L.ab) else { return nil }
            return L
        }

        if pivots.count >= n, inputsOK(pivots.suffix(n)) != nil {
            return AutoPattern(pattern: pattern, bullish: bullish, pivots: Array(pivots.suffix(n)))
        }
        if pivots.count >= n + 1 {
            var i = pivots.count - (n + 1)
            while i >= 0 {
                let w = pivots[i..<(i + n + 1)]
                let d = pivots[i + n]
                if d.kind == kinds[n], let L = inputsOK(w.dropLast()) {
                    let cdOK = s.cdBC.contains(abs(d.price - L.c) / L.bc) && (bullish ? d.price < L.c : d.price > L.c)
                    var adOK = true
                    if let xa = L.xa, let adBand = s.adXA {
                        adOK = adBand.contains(abs(L.a - d.price) / xa) && (bullish ? d.price < L.a : d.price > L.a)
                    }
                    if cdOK && adOK { return AutoPattern(pattern: pattern, bullish: bullish, pivots: Array(w)) }
                }
                i -= 1
            }
        }
        return nil
    }

    /// Auto's choice for one side: an in-progress shape first (X-A-B-C shapes
    /// before ABCD, since they are stricter), else the completed one whose D
    /// printed most recently.
    static func pick(from found: [HarmonicPattern: AutoPattern]) -> AutoPattern? {
        let order: [HarmonicPattern] = [.gartley, .bat, .butterfly, .crab, .abcd]
        let candidates = order.compactMap { found[$0] }
        if let live = candidates.first(where: { $0.inProgress }) { return live }
        return candidates.max { ($0.d?.index ?? -1) < ($1.d?.index ?? -1) }
    }
}
