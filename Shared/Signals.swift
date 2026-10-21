import Foundation

// The Signals API is a small read-only Apps Script web app in the Universe
// repo (Scripts/signals_api). It serves today's candidate lists from the
// trading spreadsheet: the morning cloud screen's tiers and the earnings
// watch list. Nothing here can trade.

/// A cell that may arrive as a string, a number, a bool, or null.
struct Flex: Codable, Hashable {
    let text: String
    let number: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { text = ""; number = nil; return }
        if let d = try? c.decode(Double.self) {
            number = d
            text = d == d.rounded() && abs(d) < 1e12 ? String(Int(d)) : String(d)
            return
        }
        if let b = try? c.decode(Bool.self) { text = b ? "Yes" : "No"; number = nil; return }
        let s = try c.decode(String.self)
        text = s
        number = Double(s.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "%", with: ""))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let n = number { try c.encode(n) } else { try c.encode(text) }
    }

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
}

struct CloudTierRow: Codable, Hashable, Identifiable {
    let tier: String            // "T1".."T4" (long) or "S1".."S4" (short)
    let symbol: String
    let side: String            // LONG / SHORT
    let price: Double?
    let dailyPos: String?
    let hourlyPos: String?
    let daysAbove: Double?
    let rvol: Double?
    let ichiScore: Double?
    let cloudColor: String?
    let tkCross: String?

    var id: String { tier + ":" + symbol }
    var isShort: Bool { side.uppercased() == "SHORT" }
    /// 1...4 within its side; used for sorting and badge shading.
    var rank: Int { Int(tier.dropFirst()) ?? 9 }
}

extension CloudTierRow {
    struct Factor: Hashable { let name: String; let ok: Bool }

    /// The four things the morning screen scores, read against this row's side.
    /// For a long: daily above the cloud, green cloud, TK bull cross, hourly above.
    /// For a short: daily below, red cloud, TK bear cross, hourly below.
    var confluence: [Factor] {
        let pos = isShort ? "below" : "above"
        let colour = isShort ? "red" : "green"
        let tk = isShort ? "bear" : "bull"
        return [
            Factor(name: "daily \(pos)", ok: (dailyPos ?? "").lowercased() == pos),
            Factor(name: "\(colour) cloud", ok: (cloudColor ?? "").lowercased() == colour),
            Factor(name: "TK \(tk)", ok: (tkCross ?? "").lowercased() == tk),
            Factor(name: "hourly \(pos)", ok: (hourlyPos ?? "").lowercased() == pos),
        ]
    }
    var confluenceCount: Int { confluence.filter(\.ok).count }
    var isFullConfluence: Bool { confluenceCount == confluence.count }
    /// Ichi score is daily ±20, cloud ±10, TK +10/−5: +40 and −35 are the extremes.
    var ichiAtExtreme: Bool { isShort ? (ichiScore ?? 0) <= -35 : (ichiScore ?? 0) >= 40 }
    var ichiStrength: Double { abs(ichiScore ?? 0) }
}

struct CloudTiersSection: Codable, Hashable {
    let scanDate: String?
    let scanTime: String?
    let totalRows: Int?         // rows on the sheet before any trimming
    let tiers: [String]?
    let maxPrice: Double?
    let rows: [CloudTierRow]
}

/// One Earnings Watch row. Column A (symbol), section, and earnings date are
/// fixed; every other column is optional and keyed by its camel-cased header,
/// so the app keeps working when the sheet gains or loses columns.
struct EarningsRow: Codable, Hashable, Identifiable {
    let fields: [String: Flex]

    init(from decoder: Decoder) throws {
        fields = try decoder.singleValueContainer().decode([String: Flex].self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(fields)
    }

    private func s(_ key: String) -> String? {
        guard let f = fields[key], !f.isEmpty else { return nil }
        return f.text
    }

    var symbol: String { s("symbol") ?? "?" }
    var id: String { symbol + ":" + (s("earningsDate") ?? "") }
    var section: String? { s("section") }
    var earningsDate: Date? {
        guard let raw = s("earningsDate") else { return nil }
        if let d = try? Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(raw) { return d }
        if let d = try? Date.ISO8601FormatStyle().parse(raw) { return d }
        // Plain "2026-10-22"
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        if parts.count == 3 { return cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) }
        return nil
    }
    var timing: String? { s("timing") ?? s("time") }          // BMO / AMC
    var price: Double? { fields["price"]?.number }
    var bias: String? { s("bias") }
    var conviction: String? { s("conviction") ?? s("confidence") }
    var take: String? { s("claudesTake") }
    var reactionCall: String? { s("earningsReactionCall") }
    var catalystAngle: String? { s("catalystAngle") }
    var optionsPlay: String? { s("optionsPlay") }
    var ivRank: Double? { fields["iVRank"]?.number ?? fields["ivRank"]?.number }
    var recentSurprise: Double? { fields["recentSurprise"]?.number }
    var sector: String? { s("sector") }
}

struct EarningsSection: Codable, Hashable {
    let columns: [String]
    let totalRows: Int?         // rows on the sheet before the date window
    let days: Int?
    let rows: [EarningsRow]
}

/// What the Signals tab shows and asks the endpoint to trim to. Persisted
/// by the model so the choice sticks between launches.
struct SignalsFilter: Codable, Hashable {
    enum View: String, Codable, CaseIterable, Identifiable {
        case cloud, earnings, patterns, both
        var id: String { rawValue }
        var label: String {
            switch self {
            case .cloud: return "Cloud"
            case .earnings: return "Earnings"
            case .patterns: return "Patterns"
            case .both: return "All"
            }
        }
        var section: String { self == .both ? "all" : rawValue }
        var showsCloud: Bool { self == .cloud || self == .both }
        var showsEarnings: Bool { self == .earnings || self == .both }
        var showsPatterns: Bool { self == .patterns || self == .both }
    }
    enum PatternCategory: String, Codable, CaseIterable, Identifiable {
        case all, candlestick, harmonic, chart
        var id: String { rawValue }
        var label: String { self == .all ? "All patterns" : rawValue.capitalized }
    }
    enum PatternDirection: String, Codable, CaseIterable, Identifiable {
        case all, bullish, bearish
        var id: String { rawValue }
        var label: String { self == .all ? "Both directions" : rawValue.capitalized }
    }
    enum TierSort: String, Codable, CaseIterable, Identifiable {
        case tier, confluence, rvol, ichi, price
        var id: String { rawValue }
        var label: String {
            switch self {
            case .tier: return "Tier"
            case .confluence: return "Confluence first"
            case .rvol: return "RVOL, highest first"
            case .ichi: return "Ichi score, strongest first"
            case .price: return "Price, lowest first"
            }
        }
    }

    static let allTiers = ["T1", "T2", "T3", "T4", "S1", "S2", "S3", "S4"]
    static let priceChoices: [Double] = [0, 25, 50, 100, 250]
    static let dayChoices = [7, 14, 30, 0]

    var view: View = .cloud
    var tiers: Set<String> = ["T1", "T2", "S1", "S2"]
    var maxPrice: Double = 0          // 0 = any
    var tierSort: TierSort = .tier
    var earningsDays: Int = 7         // 0 = all
    var callsOnly: Bool = false       // earnings rows with a Reaction Call only
    var refusedOnly: Bool = false     // only candidates an engine recently refused
    var confluenceOnly: Bool = false  // cloud rows where all four factors agree
    var patternCategory: PatternCategory = .all
    var patternDirection: PatternDirection = .all

    /// Tier labels in canonical order, for the request and the header.
    var orderedTiers: [String] { Self.allTiers.filter { tiers.contains($0) } }

    var tierLabel: String {
        if tiers.count == Self.allTiers.count || tiers.isEmpty { return "All tiers" }
        return orderedTiers.joined(separator: " ")
    }
    var priceLabel: String { maxPrice > 0 ? "≤ $\(Int(maxPrice))" : "Any price" }
    var daysLabel: String { earningsDays == 0 ? "All dates" : "Next \(earningsDays) days" }
}

/// One row of 2a's Live Position Ledger: the engines' own view of an open
/// position. Columns are keyed by camel-cased header; the endpoint adds
/// `unprotected` and `noStop` flags derived from the stop text.
struct LedgerRow: Codable, Hashable, Identifiable {
    let fields: [String: Flex]

    init(from decoder: Decoder) throws {
        fields = try decoder.singleValueContainer().decode([String: Flex].self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(fields)
    }

    private func s(_ key: String) -> String? {
        guard let f = fields[key], !f.isEmpty else { return nil }
        return f.text
    }

    var symbol: String { s("symbol") ?? "?" }
    var id: String { symbol + ":" + (s("direction") ?? "") }
    var direction: String? { s("direction") }
    var engine: String? { s("engine") }
    var stopText: String? { s("stopPrice") }
    var stopPct: Double? { fields["stop"]?.number ?? fields["stopPercent"]?.number }
    var tier1: String? { s("takeProfitTier1") }
    var tier2: String? { s("takeProfitTier2") }
    var daysHeld: Double? { fields["daysHeld"]?.number }
    var lastUpdated: String? { s("lastUpdatedET") ?? s("lastUpdated") }
    var unprotected: Bool { fields["unprotected"]?.text.lowercased() == "yes" || fields["unprotected"]?.number == 1 }
    var noStop: Bool { fields["noStop"]?.text.lowercased() == "yes" || fields["noStop"]?.number == 1 }

    /// Short engine tag for a chip: "Core", "ECS", "Aligned", "CYRX", "Split"…
    var engineTag: String? {
        guard let e = engine else { return nil }
        let lower = e.lowercased()
        if lower.contains("earnings confluence") { return "ECS" }
        if lower.contains("aligned") { return "Aligned" }
        if lower.contains("cyrx") { return "CYRX" }
        if lower.contains("core split") { return "Split" }
        if lower.contains("core") { return "Core" }
        return e.components(separatedBy: " ").prefix(2).joined(separator: " ")
    }

    /// A one-line stop description: "trailing 5.50%" / "$71.33" / "no stop".
    var stopSummary: String {
        guard let t = stopText, !t.isEmpty else { return "no stop" }
        if let r = t.range(of: #"trailing\s+[0-9.]+%"#, options: .regularExpression) { return String(t[r]) }
        if let r = t.range(of: #"\$?[0-9]+\.[0-9]{2}"#, options: .regularExpression) { return "stop " + String(t[r]).replacingOccurrences(of: "$", with: "") }
        return String(t.prefix(28))
    }
}

struct LedgerSection: Codable, Hashable {
    let totalRows: Int?
    let columns: [String]
    let rows: [LedgerRow]
}

/// Aggregate results for a group of closed trades (an engine, a direction, a tier, or everything).
struct TradeStats: Codable, Hashable, Identifiable {
    var engine: String?
    var direction: String?
    var tier: String?
    var unknowable: Bool?
    let n: Int
    let wins: Int
    let losses: Int
    let winRate: Double?
    let totalPnl: Double
    let avgPnl: Double?
    let medianPnl: Double?
    let avgReturn: Double?
    let best: Double?
    let worst: Double?
    let concentration: Double?
    let avgMfePct: Double?
    let avgMaePct: Double?
    var directions: [TradeStats]? = nil
    var tiers: [TradeStats]? = nil

    var id: String { [engine, direction, tier].compactMap { $0 }.joined(separator: "|") + "#\(n)" }
}

typealias EngineStats = TradeStats
extension TradeStats {
    var engineName: String { engine ?? "?" }
}

struct ScoreWindowStats: Codable, Hashable {
    let from: String?
    let to: String?
    let total: TradeStats
    let engines: [TradeStats]
}

struct ScorecardWindows: Codable, Hashable {
    let recent: ScoreWindowStats?
    let all: ScoreWindowStats?
}

struct ScorecardSection: Codable, Hashable {
    let days: Int?
    let trustFrom: String?
    let openTrades: Int?
    let mismatches: Int?
    let error: String?
    let windows: ScorecardWindows
}

/// One refused candidate from an engine's refusal ledger.
struct RefusalRow: Codable, Hashable, Identifiable {
    let symbol: String
    let stage: String
    let date: String?
    let direction: String?
    let score: Double?
    let run: String?
    var id: String { symbol + "|" + (direction ?? "") + "|" + (date ?? "") }
}

struct RefusalGroup: Codable, Hashable {
    let count: Int
    let byStage: [String: Int]
    let rows: [RefusalRow]

    /// Stages by frequency, most common first.
    var topStages: [(stage: String, count: Int)] {
        byStage.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }
}

struct RefusalsSection: Codable, Hashable {
    let days: Int?
    let from: String?
    let core: RefusalGroup
    let ecs: RefusalGroup
}

/// One detected pattern from 1b's Candlestick / Harmonic / Chart sheets.
struct PatternRow: Codable, Hashable, Identifiable {
    let fields: [String: Flex]

    init(from decoder: Decoder) throws {
        fields = try decoder.singleValueContainer().decode([String: Flex].self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(fields)
    }

    private func s(_ key: String) -> String? {
        guard let f = fields[key], !f.isEmpty else { return nil }
        return f.text
    }

    var category: String { s("category") ?? "?" }
    var symbol: String { s("symbol") ?? "?" }
    var pattern: String { s("pattern") ?? "?" }
    var id: String { category + "|" + symbol + "|" + pattern + "|" + (s("date") ?? "") }
    var direction: String? { s("direction")?.uppercased() }
    var isBullish: Bool { direction == "BULLISH" }
    var isBearish: Bool { direction == "BEARISH" }
    var confidence: Double? { fields["confidence"]?.number }
    var strength: String? { s("strength") }
    var price: Double? { fields["price"]?.number }
    var rvol: Double? { fields["rvol"]?.number }
    var targetPct: Double? { fields["target"]?.number }
    var stopPct: Double? { fields["stop"]?.number }
    var rr: Double? { fields["rR"]?.number ?? fields["rr"]?.number }
    var description: String? { s("description") }
    var cheatsheetPattern: String? { s("cheatsheetPattern") }
    var entryRule: String? { s("entryRule") }
    var stopRule: String? { s("stopRule") }
    var date: String? { s("date") }

    /// Confidence as a 0...1 fraction whether the sheet stored 0.82 or 82.
    var confidenceFraction: Double? {
        guard let c = confidence else { return nil }
        return c > 1 ? c / 100 : c
    }

    /// Harmonic pivots from the Points column ({"A":{"price":..,"barsAgo":..},...}).
    var points: [String: HarmonicPoint] {
        guard let raw = s("points"), let data = raw.data(using: .utf8),
              let obj = try? JSONDecoder().decode([String: HarmonicPoint].self, from: data) else { return [:] }
        return obj
    }
}

struct HarmonicPoint: Codable, Hashable {
    let price: Double
    let barsAgo: Int?
}

struct PatternCategoryInfo: Codable, Hashable {
    let total: Int
    let bullish: Int
    let bearish: Int
    let scanDate: String?
}

struct PatternsSection: Codable, Hashable {
    let cap: Int?
    let categories: [String: PatternCategoryInfo]
    let rows: [PatternRow]
}

struct SignalsPayload: Codable, Hashable {
    let ok: Bool
    let error: String?
    let version: Int?
    let generatedAt: Date?
    let timeZone: String?
    let cloudTiers: CloudTiersSection?
    let earnings: EarningsSection?
    let ledger: LedgerSection?
    let scorecard: ScorecardSection?
    let refusals: RefusalsSection?
    let patterns: PatternsSection?
}

enum SignalsError: LocalizedError {
    case notConfigured
    case http(Int)
    case server(String)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:   return "Signals are not set up. Add the endpoint URL and key in Settings."
        case .http(let c):     return "The signals endpoint returned HTTP \(c)."
        case .server(let m):   return m == "Unauthorized" ? "The signals key was rejected. Check it in Settings." : m
        case .decoding(let m): return "Could not read the signals response: \(m)"
        case .transport(let m): return "Network problem: \(m)"
        }
    }
}

struct SignalsClient: Sendable {
    let endpoint: URL
    let key: String

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let frac = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let plain = Date.ISO8601FormatStyle()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = try? frac.parse(s) { return date }
            if let date = try? plain.parse(s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unrecognized date: \(s)")
        }
        return d
    }()

    func fetch(filter: SignalsFilter = SignalsFilter()) async throws -> SignalsPayload {
        var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        let tiers = filter.tiers.isEmpty ? SignalsFilter.allTiers : filter.orderedTiers
        comps.queryItems = [.init(name: "key", value: key),
                            .init(name: "section", value: filter.view.section),
                            .init(name: "tiers", value: tiers.joined(separator: ",")),
                            .init(name: "maxPrice", value: String(Int(filter.maxPrice))),
                            .init(name: "earningsDays", value: String(filter.earningsDays)),
                            .init(name: "ledger", value: "1"),
                            .init(name: "scorecard", value: "1"),
                            .init(name: "refusals", value: "1"),
                            .init(name: "patterns", value: "1")]
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 30
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: req) }
        catch { throw SignalsError.transport(error.localizedDescription) }
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else { throw SignalsError.http(code) }
        let payload: SignalsPayload
        do { payload = try Self.decoder.decode(SignalsPayload.self, from: data) }
        catch {
            // Apps Script answers HTML (a sign-in or authorization page) when the
            // deployment is not authorized yet; say so instead of a JSON error.
            if let text = String(data: data, encoding: .utf8), text.lowercased().contains("<html") {
                throw SignalsError.server("The endpoint answered with a web page instead of data. Run setupSignalsApiKey() in the Apps Script editor once to authorize it.")
            }
            throw SignalsError.decoding(String(describing: error))
        }
        guard payload.ok else { throw SignalsError.server(payload.error ?? "Unknown error") }
        return payload
    }
}
