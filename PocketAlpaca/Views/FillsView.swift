import SwiftUI

/// Recent executions from Alpaca's account activities, grouped by day.
struct FillsView: View {
    @Environment(AppModel.self) private var model

    private struct Day: Identifiable {
        let id: Date
        let title: String
        let fills: [Fill]
        var notional: Double { fills.compactMap(\.notional).reduce(0, +) }
    }

    private var days: [Day] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: model.fills) { cal.startOfDay(for: $0.transactionTime) }
        return groups.keys.sorted(by: >).map { day in
            let title: String
            if cal.isDateInToday(day) { title = "Today" }
            else if cal.isDateInYesterday(day) { title = "Yesterday" }
            else { title = day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
            return Day(id: day, title: title, fills: groups[day]!.sorted { $0.transactionTime > $1.transactionTime })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SampleDataBanner()
            ErrorBanner()
            List {
                if model.fills.isEmpty && !model.isRefreshing {
                    ContentUnavailableView("No recent fills", systemImage: "clock.arrow.circlepath",
                                           description: Text("Executions appear here as orders fill."))
                } else {
                    ForEach(days) { day in
                        Section {
                            ForEach(day.fills) { FillRow(fill: $0) }
                        } header: {
                            HStack {
                                Text(day.title)
                                Spacer()
                                Text("\(day.fills.count) fill\(day.fills.count == 1 ? "" : "s") · \(Fmt.money(day.notional))")
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await model.refreshAll() }
        }
    }
}

struct FillRow: View {
    let fill: Fill

    private var tint: Color {
        switch fill.side.lowercased() {
        case "buy": return .green
        case "sell_short": return .red
        default: return .blue
        }
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(fill.symbol).font(.headline)
                    Text(fill.sideLabel)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(tint)
                    if fill.isPartial {
                        Text("partial").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text("\(Fmt.qty(fill.qty.value)) sh @ \(Fmt.price(fill.price.value))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.money(fill.notional)).font(.body.monospacedDigit())
                Text(fill.transactionTime.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { FillsView().navigationTitle("Fills") }
        .environment(AppModel())
}
