import SwiftUI

/// Everything Alpaca knows about one open position, plus the orders guarding
/// it and its recent fills. Presented as a sheet from the Positions list.
struct PositionDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let position: Position

    /// Always show the freshest copy if the list has refreshed since the sheet opened.
    private var live: Position { model.positions.first { $0.id == position.id } ?? position }

    var body: some View {
        NavigationStack {
            List {
                Section { header }
                    .listRowBackground(LedgerHeat.rowBackground(fraction: live.unrealizedPlpc.value))

                Section("Profit / loss") {
                    plRow("Since entry", live.unrealizedPl.value, live.unrealizedPlpc.value)
                    plRow("Today", live.unrealizedIntradayPl.value, live.unrealizedIntradayPlpc.value)
                }

                Section("Position") {
                    LabeledContent("Shares", value: Fmt.qty(live.signedQty))
                    LabeledContent("Available to close", value: Fmt.qty(live.qtyAvailable.value))
                    LabeledContent("Average entry", value: Fmt.price(live.avgEntryPrice.value))
                    LabeledContent("Current price", value: Fmt.price(live.currentPrice.value))
                    LabeledContent("Previous close", value: Fmt.price(live.lastdayPrice.value))
                    LabeledContent("Change today") {
                        Text(Fmt.percent(live.changeToday.value)).foregroundStyle(Color.pnl(live.changeToday.value))
                    }
                    LabeledContent("Market value", value: Fmt.money(live.marketValue.value))
                    LabeledContent("Cost basis", value: Fmt.money(live.costBasis.value))
                }

                if let l = model.ledgerRow(for: live.symbol) {
                    Section("Engine ledger") {
                        if let e = l.engine { LabeledContent("Engine", value: e) }
                        if let t = l.stopText {
                            LabeledContent("Stop") {
                                Text(t).multilineTextAlignment(.trailing).font(.footnote)
                                    .foregroundStyle(l.unprotected ? Color.red : Color.primary)
                            }
                        } else {
                            LabeledContent("Stop") { Text("none").foregroundStyle(.red) }
                        }
                        if let p = l.stopPct { LabeledContent("Stop distance", value: "\(p.formatted(.number.precision(.fractionLength(0...2))))%") }
                        if let t1 = l.tier1 { LabeledContent("Take-profit tier 1") { Text(t1).multilineTextAlignment(.trailing).font(.footnote) } }
                        if let t2 = l.tier2 { LabeledContent("Take-profit tier 2") { Text(t2).multilineTextAlignment(.trailing).font(.footnote) } }
                        if let d = l.daysHeld { LabeledContent("Days held", value: "\(Int(d))") }
                        if let u = l.lastUpdated { LabeledContent("Ledger updated", value: u) }
                    }
                }

                let orders = model.openOrders(for: live.symbol)
                Section(orders.isEmpty ? "No open orders" : "Open orders") {
                    if orders.isEmpty {
                        Label("Nothing is protecting this position right now.", systemImage: "exclamationmark.shield")
                            .font(.footnote).foregroundStyle(.orange)
                    } else {
                        ForEach(orders) { OrderRow(order: $0, currentPrice: live.currentPrice.value) }
                    }
                }

                let fills = Array(model.fills(for: live.symbol).prefix(10))
                if !fills.isEmpty {
                    Section("Recent fills") {
                        ForEach(fills) { FillRow(fill: $0) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(live.symbol)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(live.symbol).font(.title.weight(.bold))
                    Text(live.isShort ? "SHORT" : "LONG")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(live.isShort ? Color.red.opacity(0.15) : Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(live.isShort ? .red : .green)
                }
                Text([live.exchange, live.assetClass?.replacingOccurrences(of: "_", with: " ")].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.money(live.unrealizedPl.value, signed: true))
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text(Fmt.percent(live.unrealizedPlpc.value)).font(.subheadline.monospacedDigit())
            }
            .foregroundStyle(Color.pnl(live.unrealizedPl.value))
        }
        .padding(.vertical, 4)
    }

    private func plRow(_ title: String, _ dollars: Double?, _ fraction: Double?) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(Fmt.money(dollars, signed: true))
                Text(Fmt.percent(fraction)).foregroundStyle(.secondary)
            }
            .font(.body.monospacedDigit())
            .foregroundStyle(Color.pnl(dollars))
        }
    }
}

#Preview {
    PositionDetailView(position: Position(
        assetId: "1", symbol: "MSBI", exchange: "NASDAQ", assetClass: "us_equity", side: "long",
        qty: .init(7), qtyAvailable: .init(7), avgEntryPrice: .init(33.15), currentPrice: .init(33.42),
        lastdayPrice: .init(33.10), changeToday: .init(0.0097), marketValue: .init(233.94), costBasis: .init(232.05),
        unrealizedPl: .init(1.89), unrealizedPlpc: .init(0.0081), unrealizedIntradayPl: .init(2.24), unrealizedIntradayPlpc: .init(0.0097)))
    .environment(AppModel())
}
