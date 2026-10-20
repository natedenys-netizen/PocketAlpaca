import SwiftUI

struct OrdersView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            SampleDataBanner()
            ErrorBanner()
            List {
                Section(header: Text("Open (\(model.openOrders.count))")) {
                    if model.openOrders.isEmpty {
                        Text("No open orders").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.openOrders) { OrderRow(order: $0, currentPrice: model.currentPrice(for: $0.symbol)) }
                    }
                }
                Section(header: Text("Recent")) {
                    if model.recentOrders.isEmpty {
                        Text("No recent orders").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.recentOrders) { OrderRow(order: $0, currentPrice: nil) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await model.refreshAll() }
        }
    }
}

struct OrderRow: View {
    let order: Order
    /// Current price of the matching position, for the distance-to-stop readout.
    var currentPrice: Double? = nil

    private var statusColor: Color {
        switch order.status.lowercased() {
        case "filled": return .green
        case "canceled", "cancelled", "expired", "rejected": return .secondary
        default: return .orange
        }
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(order.symbol).font(.headline)
                    Text(order.status.replacingOccurrences(of: "_", with: " "))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(statusColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(statusColor)
                }
                HStack(spacing: 6) {
                    Text(order.summary)
                    if let t = order.trailDescription { Text("· \(t)") }
                }
                .font(.caption).foregroundStyle(.secondary)
                if let sp = order.stopPrice.value {
                    HStack(spacing: 6) {
                        Text("stop \(Fmt.price(sp))")
                        if let d = order.stopDistance(currentPrice: currentPrice) {
                            Text("· \(Fmt.percent(d, signed: false)) away")
                                .foregroundStyle(d < 0.01 ? Color.orange : Color.secondary)
                        }
                    }
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if let lp = order.limitPrice.value {
                    Text("limit \(Fmt.price(lp))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(Fmt.qty(order.filledQty.value)) / \(Fmt.qty(order.qty.value))")
                    .font(.body.monospacedDigit())
                if let p = order.filledAvgPrice.value {
                    Text("@ \(Fmt.price(p))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(Fmt.time(order.filledAt ?? order.submittedAt ?? order.createdAt))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { OrdersView().navigationTitle("Orders") }
        .environment(AppModel())
}
