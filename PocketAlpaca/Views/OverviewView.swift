import SwiftUI
import Charts

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @State private var range: ChartRange = .day

    var body: some View {
        VStack(spacing: 0) {
            SampleDataBanner()
            ErrorBanner()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    equityHeader
                    chartCard
                    statsGrid
                }
                .padding()
            }
            .refreshable {
                await model.refreshAll()
                await model.loadHistory(range, force: true)
            }
        }
        .task(id: range) { await model.loadHistory(range) }
    }

    private var equityHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Equity").font(.caption).foregroundStyle(.secondary)
            Text(Fmt.money(model.account?.equity.value))
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
            HStack(spacing: 8) {
                let change = model.account?.dayChange
                Text(Fmt.money(change, signed: true))
                Text(Fmt.percent(model.account?.dayChangePct))
                Text("today").foregroundStyle(.secondary)
            }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(Color.pnl(model.account?.dayChange))
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Range", selection: $range) {
                ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if let h = model.history[range] {
                if h.points.isEmpty {
                    ContentUnavailableView("No history for this range", systemImage: "chart.xyaxis.line",
                                           description: Text("Alpaca returned no equity for these dates."))
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    EquityChart(points: h.points, range: range)
                        .frame(height: 220)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private var statsGrid: some View {
        let a = model.account
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(title: "Buying power", value: Fmt.money(a?.buyingPower.value))
            StatTile(title: "Cash", value: Fmt.money(a?.cash.value))
            StatTile(title: "Long value", value: Fmt.money(a?.longMarketValue.value))
            StatTile(title: "Short value", value: Fmt.money(a?.shortMarketValue.value))
            StatTile(title: "Positions", value: "\(model.positions.count)")
            StatTile(title: "Open orders", value: "\(model.openOrders.count)")
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct EquityChart: View {
    let points: [PortfolioHistory.Point]
    let range: ChartRange

    private var isUp: Bool { (points.last?.equity ?? 0) >= (points.first?.equity ?? 0) }
    private var tint: Color { isUp ? .green : .red }

    var body: some View {
        let lo = points.map(\.equity).min() ?? 0
        let hi = points.map(\.equity).max() ?? 1
        let pad = max((hi - lo) * 0.08, 0.5)

        Chart(points) { p in
            AreaMark(x: .value("Time", p.date), yStart: .value("Floor", lo - pad), yEnd: .value("Equity", p.equity))
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Time", p.date), y: .value("Equity", p.equity))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        // Whole dollars normally; cents only when the whole range is tiny.
                        let digits = (hi - lo) < 10 ? 2 : 0
                        Text(d.formatted(.currency(code: "USD").precision(.fractionLength(digits)))).font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel(format: range == .day ? .dateTime.hour() : .dateTime.month().day(), centered: false)
                    .font(.caption2)
            }
        }
    }
}

#Preview {
    NavigationStack { OverviewView().navigationTitle("Overview") }
        .environment(AppModel())
}
