import SwiftUI

enum Fmt {
    static func money(_ v: Double?, signed: Bool = false) -> String {
        guard let v else { return "—" }
        let s = v.formatted(.currency(code: "USD").precision(.fractionLength(2)))
        return (signed && v > 0) ? "+" + s : s
    }

    /// `pct` is a FRACTION from Alpaca (0.0123). Never recompute this from qty;
    /// that is how the retired app produced NaN%.
    static func percent(_ fraction: Double?, signed: Bool = true) -> String {
        guard let f = fraction, f.isFinite else { return "—" }
        let s = (f * 100).formatted(.number.precision(.fractionLength(2))) + "%"
        return (signed && f > 0) ? "+" + s : s
    }

    static func qty(_ v: Double?) -> String {
        guard let v else { return "—" }
        return v.formatted(.number.precision(.fractionLength(0...4)))
    }

    static func price(_ v: Double?) -> String {
        guard let v else { return "—" }
        return v.formatted(.number.precision(.fractionLength(2)))
    }

    static func time(_ d: Date?) -> String {
        guard let d else { return "—" }
        return d.formatted(date: .abbreviated, time: .shortened)
    }
}

extension Color {
    /// Green for gains, red for losses, secondary for flat/unknown. Adapts to dark mode automatically.
    static func pnl(_ v: Double?) -> Color {
        guard let v, v != 0 else { return .secondary }
        return v > 0 ? .green : .red
    }
}

/// Row heat, ported from the Live Position Ledger's ptLedgerHeatColor_:
/// neutral at flat, linearly stronger green/red with the size of the move,
/// fully saturated at ±3% (where this account's stops sit). Endpoint colours
/// are Google Sheets' own scale values, chosen to keep text readable.
enum LedgerHeat {
    static let capPercent = 3.0
    static let green = Color(red: 87 / 255, green: 187 / 255, blue: 138 / 255)   // #57BB8A
    static let red = Color(red: 230 / 255, green: 124 / 255, blue: 115 / 255)    // #E67C73

    /// `fraction` is Alpaca's unrealized_plpc (0.0137 = +1.37%). Returns the
    /// endpoint colour and a 0...1 strength, or nil when flat/unknown.
    static func heat(fraction: Double?) -> (color: Color, strength: Double)? {
        guard let f = fraction, f.isFinite, f != 0 else { return nil }
        let pct = f * 100
        return (pct > 0 ? green : red, min(abs(pct) / capPercent, 1))
    }

    /// A row background for List rows: the endpoint colour over the system
    /// row background, so it works in light and dark mode alike.
    static func rowBackground(fraction: Double?) -> some View {
        ZStack {
            Color(.secondarySystemGroupedBackground)
            if let h = heat(fraction: fraction) { h.color.opacity(0.08 + 0.52 * h.strength) }
        }
    }
}
