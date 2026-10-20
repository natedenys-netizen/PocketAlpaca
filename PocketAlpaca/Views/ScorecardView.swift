import SwiftUI

/// Per-engine results from the real-money Trade Performance sheet, computed
/// by the Signals endpoint with the same rules as the repo's validator.
/// Last 30 days leads; all-time sits beside it for contrast.
struct ScorecardView: View {
    @Environment(AppModel.self) private var model
    @State private var window: ScoreWindow = .recent

    enum ScoreWindow: String, CaseIterable, Identifiable {
        case recent, all
        var id: String { rawValue }
    }

    private var card: ScorecardSection? { model.signals?.scorecard }
    private var current: ScoreWindowStats? { window == .recent ? card?.windows.recent : card?.windows.all }

    var body: some View {
        List {
            if let card {
                Section {
                    Picker("Window", selection: $window) {
                        Text("Last \(card.days ?? 30) days").tag(ScoreWindow.recent)
                        Text("All-time").tag(ScoreWindow.all)
                    }
                    .pickerStyle(.segmented)
                    if let w = current {
                        totalsRow(w.total, from: window == .recent ? w.from : nil)
                    }
                }

                if let w = current {
                    if w.engines.isEmpty {
                        Section { Text("No closed trades in this window").foregroundStyle(.secondary) }
                    }
                    ForEach(w.engines) { e in
                        Section {
                            NavigationLink { EngineDetailView(engine: e) } label: { EngineRow(stats: e) }
                                .listRowBackground(LedgerHeat.rowBackground(fraction: heatFraction(e)))
                        }
                    }
                }

                Section {
                    if let t = card.trustFrom {
                        Text("Engine credit starts \(t), when the Engine column became trustworthy. Earlier trades sit in the \"unknowable\" bucket rather than being credited to an engine.")
                    }
                    Text("A trade belongs to the window it was entered in. P&L is the sum of a trade's exits; return is P&L over entry notional. \(card.openTrades ?? 0) trades are still open and not scored.")
                } footer: { EmptyView() }
                .font(.footnote).foregroundStyle(.secondary)
            } else if let err = model.signalsError {
                Section { Label(err, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            } else {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Engine scorecard")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.loadSignals(force: true) }
        .task { await model.loadSignals() }
    }

    /// Heat for the engine row: average return, saturating at ±3% like the ledger.
    private func heatFraction(_ e: EngineStats) -> Double? { (e.unknowable ?? false) ? nil : e.avgReturn }

    private func totalsRow(_ t: TradeStats, from: String?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(from.map { "Entered since \($0)" } ?? "All closed trades").font(.caption).foregroundStyle(.secondary)
                Text(Fmt.money(t.totalPnl, signed: true))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.pnl(t.totalPnl))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(t.n) trades · \(Fmt.percent(t.winRate, signed: false)) win").font(.subheadline.monospacedDigit())
                Text("avg \(Fmt.money(t.avgPnl, signed: true)) · median \(Fmt.money(t.medianPnl, signed: true))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct EngineRow: View {
    let stats: EngineStats
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(stats.engineName).font(.headline).lineLimit(2)
                Text("\(stats.n) trades · \(Fmt.percent(stats.winRate, signed: false)) win · avg \(Fmt.money(stats.avgPnl, signed: true))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if let c = stats.concentration, c >= 0.5, stats.n >= 3 {
                    Label("\(Int(c * 100))% of the total rests on one trade", systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.money(stats.totalPnl, signed: true))
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.pnl(stats.totalPnl))
                Text(Fmt.percent(stats.avgReturn) + " avg").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct EngineDetailView: View {
    let engine: EngineStats

    var body: some View {
        List {
            Section("Totals") { statsRows(engine) }
            if let dirs = engine.directions, !dirs.isEmpty {
                Section("By direction") {
                    ForEach(dirs) { d in
                        DisclosureGroup { statsRows(d) } label: { compactRow(title: d.direction ?? "?", stats: d) }
                    }
                }
            }
            if let tiers = engine.tiers, !tiers.isEmpty {
                Section("By tier") {
                    ForEach(tiers) { t in
                        DisclosureGroup { statsRows(t) } label: { compactRow(title: t.tier ?? "?", stats: t) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(engine.engineName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func compactRow(title: String, stats: TradeStats) -> some View {
        HStack {
            Text(title).font(.body.weight(.medium))
            Spacer()
            Text("\(stats.n) · \(Fmt.percent(stats.winRate, signed: false))")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text(Fmt.money(stats.totalPnl, signed: true))
                .font(.body.monospacedDigit()).foregroundStyle(Color.pnl(stats.totalPnl))
        }
    }

    @ViewBuilder private func statsRows(_ s: TradeStats) -> some View {
        LabeledContent("Trades", value: "\(s.n) (\(s.wins) won, \(s.losses) lost)")
        LabeledContent("Win rate", value: Fmt.percent(s.winRate, signed: false))
        LabeledContent("Total P/L", value: Fmt.money(s.totalPnl, signed: true))
        LabeledContent("Average P/L", value: Fmt.money(s.avgPnl, signed: true))
        LabeledContent("Median P/L", value: Fmt.money(s.medianPnl, signed: true))
        LabeledContent("Average return", value: Fmt.percent(s.avgReturn))
        LabeledContent("Best / worst", value: "\(Fmt.money(s.best, signed: true)) / \(Fmt.money(s.worst, signed: true))")
        if let c = s.concentration { LabeledContent("Best trade's share of total", value: "\(Int(c * 100))%") }
        if let m = s.avgMfePct { LabeledContent("Avg max favorable excursion", value: m.formatted(.number.precision(.fractionLength(1))) + "%") }
        if let a = s.avgMaePct { LabeledContent("Avg max adverse excursion", value: a.formatted(.number.precision(.fractionLength(1))) + "%") }
    }
}

/// Compact card for Overview: the top engines in the last 30 days.
struct ScorecardCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let card = model.signals?.scorecard, let w = card.windows.recent {
            NavigationLink { ScorecardView() } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Engines · last \(card.days ?? 30) days").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(w.total.n) trades · \(Fmt.money(w.total.totalPnl, signed: true))")
                            .font(.caption.monospacedDigit()).foregroundStyle(Color.pnl(w.total.totalPnl))
                    }
                    ForEach(w.engines.filter { !($0.unknowable ?? false) }.prefix(4)) { e in
                        HStack {
                            Text(e.engineName).font(.subheadline).lineLimit(1)
                            Spacer()
                            Text("\(e.n) · \(Fmt.percent(e.winRate, signed: false))")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text(Fmt.money(e.totalPnl, signed: true))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Color.pnl(e.totalPnl))
                                .frame(minWidth: 70, alignment: .trailing)
                        }
                    }
                    if w.engines.isEmpty {
                        Text("No closed trades in the window").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }
}
