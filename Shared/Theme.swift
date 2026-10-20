import SwiftUI

/// Light / dark override. Stored in the shared defaults so the widget could
/// follow it one day; today it drives `preferredColorScheme` in the app.
enum Appearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// A two-colour palette applied as the app's tint plus a stripe on Overview.
/// Gains and losses keep their own green and red whatever the team, because
/// those colours mean something.
struct Theme: Identifiable, Hashable {
    let id: String
    let name: String
    let group: String
    let primaryHex: String
    let secondaryHex: String

    var primary: Color { Color(hex: primaryHex) }
    var secondary: Color { Color(hex: secondaryHex) }

    static let `default` = Theme(id: "default", name: "PocketAlpaca green", group: "Default", primaryHex: "0F5C3D", secondaryHex: "9EF9C0")

    static func named(_ id: String?) -> Theme {
        guard let id else { return .default }
        return all.first { $0.id == id } ?? .default
    }

    static let all: [Theme] = [.default] + nfl

    /// NFL team colours (primary, secondary), grouped by division.
    static let nfl: [Theme] = [
        // AFC East
        Theme(id: "buf", name: "Buffalo Bills",         group: "AFC East",  primaryHex: "00338D", secondaryHex: "C60C30"),
        Theme(id: "mia", name: "Miami Dolphins",        group: "AFC East",  primaryHex: "008E97", secondaryHex: "FC4C02"),
        Theme(id: "ne",  name: "New England Patriots",  group: "AFC East",  primaryHex: "002244", secondaryHex: "C60C30"),
        Theme(id: "nyj", name: "New York Jets",         group: "AFC East",  primaryHex: "125740", secondaryHex: "000000"),
        // AFC North
        Theme(id: "bal", name: "Baltimore Ravens",      group: "AFC North", primaryHex: "241773", secondaryHex: "9E7C0C"),
        Theme(id: "cin", name: "Cincinnati Bengals",    group: "AFC North", primaryHex: "FB4F14", secondaryHex: "000000"),
        Theme(id: "cle", name: "Cleveland Browns",      group: "AFC North", primaryHex: "311D00", secondaryHex: "FF3C00"),
        Theme(id: "pit", name: "Pittsburgh Steelers",   group: "AFC North", primaryHex: "FFB612", secondaryHex: "101820"),
        // AFC South
        Theme(id: "hou", name: "Houston Texans",        group: "AFC South", primaryHex: "03202F", secondaryHex: "A71930"),
        Theme(id: "ind", name: "Indianapolis Colts",    group: "AFC South", primaryHex: "002C5F", secondaryHex: "A2AAAD"),
        Theme(id: "jax", name: "Jacksonville Jaguars",  group: "AFC South", primaryHex: "006778", secondaryHex: "D7A22A"),
        Theme(id: "ten", name: "Tennessee Titans",      group: "AFC South", primaryHex: "0C2340", secondaryHex: "4B92DB"),
        // AFC West
        Theme(id: "den", name: "Denver Broncos",        group: "AFC West",  primaryHex: "FB4F14", secondaryHex: "002244"),
        Theme(id: "kc",  name: "Kansas City Chiefs",    group: "AFC West",  primaryHex: "E31837", secondaryHex: "FFB81C"),
        Theme(id: "lv",  name: "Las Vegas Raiders",     group: "AFC West",  primaryHex: "000000", secondaryHex: "A5ACAF"),
        Theme(id: "lac", name: "Los Angeles Chargers",  group: "AFC West",  primaryHex: "0080C6", secondaryHex: "FFC20E"),
        // NFC East
        Theme(id: "dal", name: "Dallas Cowboys",        group: "NFC East",  primaryHex: "003594", secondaryHex: "869397"),
        Theme(id: "nyg", name: "New York Giants",       group: "NFC East",  primaryHex: "0B2265", secondaryHex: "A71930"),
        Theme(id: "phi", name: "Philadelphia Eagles",   group: "NFC East",  primaryHex: "004C54", secondaryHex: "A5ACAF"),
        Theme(id: "was", name: "Washington Commanders", group: "NFC East",  primaryHex: "5A1414", secondaryHex: "FFB612"),
        // NFC North
        Theme(id: "chi", name: "Chicago Bears",         group: "NFC North", primaryHex: "0B162A", secondaryHex: "C83803"),
        Theme(id: "det", name: "Detroit Lions",         group: "NFC North", primaryHex: "0076B6", secondaryHex: "B0B7BC"),
        Theme(id: "gb",  name: "Green Bay Packers",     group: "NFC North", primaryHex: "203731", secondaryHex: "FFB612"),
        Theme(id: "min", name: "Minnesota Vikings",     group: "NFC North", primaryHex: "4F2683", secondaryHex: "FFC62F"),
        // NFC South
        Theme(id: "atl", name: "Atlanta Falcons",       group: "NFC South", primaryHex: "A71930", secondaryHex: "000000"),
        Theme(id: "car", name: "Carolina Panthers",     group: "NFC South", primaryHex: "0085CA", secondaryHex: "101820"),
        Theme(id: "no",  name: "New Orleans Saints",    group: "NFC South", primaryHex: "D3BC8D", secondaryHex: "101820"),
        Theme(id: "tb",  name: "Tampa Bay Buccaneers",  group: "NFC South", primaryHex: "D50A0A", secondaryHex: "34302B"),
        // NFC West
        Theme(id: "ari", name: "Arizona Cardinals",     group: "NFC West",  primaryHex: "97233F", secondaryHex: "000000"),
        Theme(id: "lar", name: "Los Angeles Rams",      group: "NFC West",  primaryHex: "003594", secondaryHex: "FFA300"),
        Theme(id: "sf",  name: "San Francisco 49ers",   group: "NFC West",  primaryHex: "AA0000", secondaryHex: "B3995D"),
        Theme(id: "sea", name: "Seattle Seahawks",      group: "NFC West",  primaryHex: "002244", secondaryHex: "69BE28"),
    ]

    static var groups: [String] {
        var seen: [String] = []
        for t in all where !seen.contains(t.group) { seen.append(t.group) }
        return seen
    }
}

extension Color {
    /// "RRGGBB" → Color. Falls back to clear on malformed input.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { self = .clear; return }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// Two-colour team stripe used under the Overview title.
struct TeamStripe: View {
    let theme: Theme
    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(theme.primary)
            Rectangle().fill(theme.secondary)
        }
        .frame(height: 4)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}
