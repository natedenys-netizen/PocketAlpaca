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

struct CloudTiersSection: Codable, Hashable {
    let scanDate: String?
    let scanTime: String?
    let totalRows: Int?         // rows on the sheet before the tier filter
    let maxTier: Int?
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

/// What the Signals tab asks the endpoint to trim to. Persisted by the model.
struct SignalsFilter: Codable, Hashable {
    var maxTier: Int = 2         // 1...4; 4 = everything
    var earningsDays: Int = 7    // 0 = everything

    static let tierChoices = [1, 2, 3, 4]
    static let dayChoices = [7, 14, 30, 0]

    var tierLabel: String { maxTier >= 4 ? "All tiers" : (maxTier == 1 ? "Tier 1 only" : "Tiers 1–\(maxTier)") }
    var daysLabel: String { earningsDays == 0 ? "All dates" : "Next \(earningsDays) days" }
}

struct SignalsPayload: Codable, Hashable {
    let ok: Bool
    let error: String?
    let version: Int?
    let generatedAt: Date?
    let timeZone: String?
    let cloudTiers: CloudTiersSection?
    let earnings: EarningsSection?
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

    func fetch(section: String = "all", filter: SignalsFilter = SignalsFilter()) async throws -> SignalsPayload {
        var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "key", value: key), .init(name: "section", value: section),
                            .init(name: "maxTier", value: String(filter.maxTier)),
                            .init(name: "earningsDays", value: String(filter.earningsDays))]
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
