import SwiftUI
import Charts

/// The app's own candlestick chart: Alpaca bars, the scanner's detected
/// harmonic points, and a planner where three taps (A, B, C) project D with
/// the same ratios the detector uses. Read-only: it plans, it never trades.
struct PlannerView: View {
    @Environment(AppModel.self) private var model
    let symbol: String
    /// Detected harmonic points for this symbol (from the Points column), if any.
    var detected: [String: HarmonicPoint] = [:]
    var detectedLabel: String? = nil
    /// Which side to look for first: true = bullish, false = bearish, nil = whichever is in progress.
    var preferBullish: Bool? = nil

    enum Source: String, CaseIterable, Identifiable {
        case bullish, bearish, manual
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    @State private var timeframe: BarTimeframe = .day
    @State private var bars: [Bar] = []
    @State private var loading = false
    @State private var error: String?
    @State private var taps: [PricePoint] = []        // A, B, C in order
    @State private var copied = false
    @State private var source: Source = .bullish
    @State private var auto: [Bool: HarmonicMath.AutoABCD] = [:]   // keyed by bullish

    private var plan: HarmonicMath.ABCDPlan? {
        guard taps.count >= 3 else { return nil }
        return HarmonicMath.abcd(a: taps[0].price, b: taps[1].price, c: taps[2].price)
    }

    private var currentAuto: HarmonicMath.AutoABCD? {
        switch source {
        case .bullish: return auto[true]
        case .bearish: return auto[false]
        case .manual: return nil
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Picker("Timeframe", selection: $timeframe) {
                ForEach(BarTimeframe.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).padding(.horizontal)
            Picker("Source", selection: $source) {
                ForEach(Source.allCases) { src in
                    Text(src == .manual ? "Manual" : (auto[src == .bullish] == nil ? "\(src.label) —" : src.label)).tag(src)
                }
            }
            .pickerStyle(.segmented).padding(.horizontal)
            .onChange(of: source) { _, _ in applySource() }

            if let error {
                ContentUnavailableView { Label("No bars", systemImage: "chart.bar.xaxis") } description: { Text(error) }
                    .frame(maxHeight: 260)
            } else if bars.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 260)
            } else {
                CandleChart(bars: bars, detected: detectedPoints, taps: taps, plan: plan) { index, price in
                    addTap(index: index, price: price)
                }
                .frame(height: 300)
                .padding(.horizontal, 4)
            }

            planCard
        }
        .task(id: timeframe) { await load() }
    }

    // MARK: - Data

    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do {
            bars = try await model.bars(symbol: symbol, timeframe: timeframe)
            if bars.isEmpty { error = "Alpaca returned no bars for \(symbol) on this timeframe." }
        } catch {
            bars = []
            self.error = (error as? MarketDataError)?.errorDescription ?? error.localizedDescription
        }
        findAutomatically()
    }

    /// Runs the scanner's pivot rule on the bars and picks the latest ABCD for
    /// each side, then loads the preferred side into the plan with no tapping.
    private func findAutomatically() {
        let pivots = HarmonicMath.findPivots(closes: bars.map(\.c))
        auto = [true: HarmonicMath.latestABCD(pivots: pivots, bullish: true),
                false: HarmonicMath.latestABCD(pivots: pivots, bullish: false)].compactMapValues { $0 }
        // Preferred side if it has a pattern, else whichever side is in progress, else bullish.
        if let pref = preferBullish, auto[pref] != nil { source = pref ? .bullish : .bearish }
        else if let inProg = auto.first(where: { $0.value.inProgress })?.key { source = inProg ? .bullish : .bearish }
        else if auto[true] != nil { source = .bullish }
        else if auto[false] != nil { source = .bearish }
        else { source = .manual }
        applySource()
    }

    private func applySource() {
        copied = false
        if let a = currentAuto { taps = a.points } else if source != .manual { taps = [] }
        else { taps = [] }
    }

    /// Detected points land on the chart only on the daily view, because the
    /// scanner works on daily bars and reports "bars ago".
    private var detectedPoints: [PricePoint] {
        guard timeframe == .day, !bars.isEmpty else { return [] }
        let last = bars.count - 1
        return ["X", "A", "B", "C", "D"].compactMap { k in
            guard let p = detected[k] else { return nil }
            let idx = p.barsAgo.map { last - $0 }
            return PricePoint(label: k, price: p.price, index: (idx ?? -1) >= 0 ? idx : nil)
        }
    }

    private func addTap(index: Int, price: Double) {
        if source != .manual { source = .manual; taps = [] }   // a tap means "I'll place them myself"
        guard taps.count < 3, bars.indices.contains(index) else { return }
        // Snap to the bar's high or low, whichever the tap was nearer.
        let bar = bars[index]
        let snapped = abs(price - bar.h) <= abs(price - bar.l) ? bar.h : bar.l
        taps.append(PricePoint(label: ["A", "B", "C"][taps.count], price: snapped, index: index))
    }

    // MARK: - Plan card

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(cardTitle).font(.subheadline.weight(.semibold))
                Spacer()
                if !taps.isEmpty || source != .manual {
                    Button("Clear") { source = .manual; taps.removeAll(); copied = false }.font(.caption)
                }
            }
            if let a = currentAuto {
                Text(a.inProgress
                     ? "Found automatically from the last pivots: C is the newest swing, D is still ahead."
                     : "Latest completed \(a.bullish ? "bullish" : "bearish") ABCD on this chart; D already printed at \(Fmt.price(a.d!.price)).")
                    .font(.caption).foregroundStyle(a.inProgress ? Color.primary : Color.secondary)
            } else if source != .manual {
                Text("No \(source.label.lowercased()) ABCD with the detector's shape in the recent pivots. Try the other side, another timeframe, or tap your own A, B, C.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let label = detectedLabel, !detectedPoints.isEmpty {
                Text("Scanner: \(label) · " + detectedPoints.map { "\($0.label) \(Fmt.price($0.price))" }.joined(separator: "  "))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if !taps.isEmpty {
                Text(taps.map { "\($0.label) \(Fmt.price($0.price))" }.joined(separator: "   "))
                    .font(.caption.monospacedDigit())
            }
            if let plan {
                if !plan.isValidShape {
                    Label("BC retraces \(Int(plan.retraceBC * 100))% of AB; the detector wants 35–92%.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow { Text("Side").foregroundStyle(.secondary); Text(plan.bullish ? "Bullish, buy at D" : "Bearish, short at D") }
                    ForEach(plan.dLevels, id: \.ratio) { d in
                        GridRow { Text("D at \(d.ratio.formatted(.number.precision(.fractionLength(3))))").foregroundStyle(.secondary); Text(Fmt.price(d.price)) }
                    }
                    GridRow { Text("Entry").foregroundStyle(.secondary); Text(Fmt.price(plan.entry)).fontWeight(.semibold) }
                    GridRow { Text("Stop").foregroundStyle(.secondary); Text(Fmt.price(plan.stop)).foregroundStyle(.red) }
                    GridRow { Text("Target").foregroundStyle(.secondary); Text(Fmt.price(plan.target)).foregroundStyle(.green) }
                    GridRow {
                        Text("Reward : risk").foregroundStyle(.secondary)
                        Text(rrText(plan))
                    }
                }
                .font(.caption.monospacedDigit())
                Button {
                    UIPasteboard.general.string = planText(plan)
                    copied = true
                } label: { Label(copied ? "Copied" : "Copy plan", systemImage: copied ? "checkmark" : "doc.on.doc") }
                .font(.caption)
            } else if taps.count == 3 {
                Label("A, B, C must alternate (high, low, high or low, high, low).", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Text("Tap the bar where each pivot is; the tap snaps to that bar's high or low. D is projected at 1.272 and 1.618 of BC, stop 1% beyond the far D, target a 61.8% retrace of CD.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }

    private var cardTitle: String {
        if source == .manual { return taps.count < 3 ? "Tap \(["A", "B", "C"][min(taps.count, 2)]) on the chart" : "ABCD projection" }
        return "\(source.label) ABCD" + (currentAuto.map { $0.inProgress ? " · in progress" : " · completed" } ?? "")
    }

    private func rrText(_ plan: HarmonicMath.ABCDPlan) -> String {
        let risk = abs(plan.entry - plan.stop), reward = abs(plan.target - plan.entry)
        guard risk > 0 else { return "—" }
        return (reward / risk).formatted(.number.precision(.fractionLength(2))) + " : 1"
    }

    private func planText(_ plan: HarmonicMath.ABCDPlan) -> String {
        """
        \(symbol) ABCD \(plan.bullish ? "bullish" : "bearish") (\(timeframe.label), \(source == .manual ? "manual" : "auto"))
        \(taps.map { "\($0.label)=\(Fmt.price($0.price))" }.joined(separator: " "))
        D 1.272=\(Fmt.price(plan.dLevels[0].price))  D 1.618=\(Fmt.price(plan.dLevels[1].price))
        Entry \(Fmt.price(plan.entry))  Stop \(Fmt.price(plan.stop))  Target \(Fmt.price(plan.target))  R:R \(rrText(plan))
        """
    }
}

/// Candles with detected points, user taps, and projected levels.
struct CandleChart: View {
    let bars: [Bar]
    let detected: [PricePoint]
    let taps: [PricePoint]
    let plan: HarmonicMath.ABCDPlan?
    let onTap: (Int, Double) -> Void

    private var yDomain: ClosedRange<Double> {
        var lo = bars.map(\.l).min() ?? 0, hi = bars.map(\.h).max() ?? 1
        for p in detected + taps { lo = min(lo, p.price); hi = max(hi, p.price) }
        if let plan { lo = min(lo, plan.stop, plan.target, plan.dLevels[1].price); hi = max(hi, plan.stop, plan.target, plan.dLevels[1].price) }
        let pad = max((hi - lo) * 0.06, 0.1)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        Chart {
            ForEach(Array(bars.enumerated()), id: \.offset) { i, b in
                RuleMark(x: .value("Bar", i), yStart: .value("Low", b.l), yEnd: .value("High", b.h))
                    .foregroundStyle(b.isUp ? Color.green : Color.red).lineStyle(StrokeStyle(lineWidth: 1))
                RectangleMark(x: .value("Bar", i), yStart: .value("Open", min(b.o, b.c)), yEnd: .value("Close", max(b.o, b.c)), width: .ratio(0.6))
                    .foregroundStyle(b.isUp ? Color.green : Color.red)
            }
            ForEach(detected) { p in
                if let i = p.index {
                    PointMark(x: .value("Bar", i), y: .value("Price", p.price))
                        .foregroundStyle(.blue).symbolSize(70)
                        .annotation(position: .top, spacing: 2) { Text(p.label).font(.caption2.weight(.bold)).foregroundStyle(.blue) }
                } else {
                    RuleMark(y: .value("Price", p.price)).foregroundStyle(.blue.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .trailing, alignment: .leading) { Text(p.label).font(.caption2).foregroundStyle(.blue) }
                }
            }
            ForEach(taps) { p in
                PointMark(x: .value("Bar", p.index ?? 0), y: .value("Price", p.price))
                    .foregroundStyle(.orange).symbolSize(90)
                    .annotation(position: .top, spacing: 2) { Text(p.label).font(.caption.weight(.bold)).foregroundStyle(.orange) }
            }
            if let plan {
                ForEach(plan.dLevels, id: \.ratio) { d in
                    RuleMark(y: .value("D", d.price)).foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .trailing, alignment: .leading) { Text("D \(d.ratio.formatted(.number.precision(.fractionLength(3))))").font(.caption2).foregroundStyle(.orange) }
                }
                RuleMark(y: .value("Stop", plan.stop)).foregroundStyle(.red).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .trailing, alignment: .leading) { Text("stop").font(.caption2).foregroundStyle(.red) }
                RuleMark(y: .value("Target", plan.target)).foregroundStyle(.green).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .trailing, alignment: .leading) { Text("target").font(.caption2).foregroundStyle(.green) }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { v in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let i = v.as(Int.self), bars.indices.contains(i) {
                        Text(bars[i].t.formatted(.dateTime.month(.abbreviated).day())).font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { v in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel { if let d = v.as(Double.self) { Text(Fmt.price(d)).font(.caption2) } }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in
                        guard let frame = proxy.plotFrame else { return }
                        let origin = geo[frame].origin
                        let x = value.location.x - origin.x, y = value.location.y - origin.y
                        if let i: Int = proxy.value(atX: x), let price: Double = proxy.value(atY: y) {
                            onTap(min(max(i, 0), bars.count - 1), price)
                        }
                    })
            }
        }
    }
}
