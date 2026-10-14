import SwiftUI

struct PositionsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            SampleDataBanner()
            ErrorBanner()
            List {
                Section {
                    summaryRow
                }
                Section(header: Text("\(model.positions.count) position\(model.positions.count == 1 ? "" : "s")")) {
                    if model.positions.isEmpty && !model.isRefreshing {
                        ContentUnavailableView("No open positions", systemImage: "briefcase",
                                               description: Text("Positions appear here as soon as the account holds any."))
                    } else {
                        ForEach(model.positions) { PositionRow(position: $0) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await model.refreshAll() }
        }
        .overlay(alignment: .bottom) { refreshStamp }
    }

    private var summaryRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Unrealized P/L").font(.caption).foregroundStyle(.secondary)
                Text(Fmt.money(model.totalUnrealizedPl, signed: true))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.pnl(model.totalUnrealizedPl))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Up \(model.winners)").foregroundStyle(.green)
                Text("Down \(model.losers)").foregroundStyle(.red)
            }
            .font(.subheadline.monospacedDigit())
        }
        .padding(.vertical, 4)
    }

    private var refreshStamp: some View {
        Group {
            if let t = model.lastRefresh {
                Text("Updated \(t.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 6)
            }
        }
    }
}

struct PositionRow: View {
    let position: Position

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(position.symbol).font(.headline)
                    Text(position.isShort ? "SHORT" : "LONG")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(position.isShort ? Color.red.opacity(0.15) : Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(position.isShort ? .red : .green)
                }
                Text("\(Fmt.qty(position.signedQty)) sh  ·  avg \(Fmt.price(position.avgEntryPrice.value))  →  \(Fmt.price(position.currentPrice.value))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.money(position.unrealizedPl.value, signed: true))
                    .font(.body.weight(.semibold).monospacedDigit())
                Text(Fmt.percent(position.unrealizedPlpc.value))
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(Color.pnl(position.unrealizedPl.value))
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { PositionsView().navigationTitle("Positions") }
        .environment(AppModel())
}
