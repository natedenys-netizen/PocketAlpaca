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
