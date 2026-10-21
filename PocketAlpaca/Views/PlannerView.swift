import SwiftUI
import Charts

/// The app's own candlestick chart: Alpaca bars, the scanner's detected
/// harmonic points, and a planner that finds the latest ABCD, Gartley, Bat,
/// Butterfly or Crab from the chart's pivots (or takes your taps) and projects
/// D with the detector's own ratios. Read-only: it plans, it never trades.
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
    @State private var error: String?
    @State private var taps: [PricePoint] = []     // X (when the shape has one), A, B, C; plus D when a completed pattern was loaded
    @State private var copied = false
    @State private var source: Source = .bullish
    @State private var pattern: HarmonicPattern? = nil   // nil = Auto: the best pattern found on the chosen side
    @State private var found: [Bool: [HarmonicPattern: HarmonicMath.AutoPattern]] = [:]
    @State private var seeded = false

    private var foundOnSide: [HarmonicPattern: HarmonicMath.AutoPattern] {
        switch source {
        case .bullish: return found[true] ?? [:]
        case .bearish: return found[false] ?? [:]
        case .manual: return [:]
        }
    }

    private var currentAuto: HarmonicMath.AutoPattern? {
        guard source != .manual else { return nil }
        if let pattern { return foundOnSide[pattern] }
        return HarmonicMath.pick(from: foundOnSide)
    }

    /// The shape on screen: the chosen one, Auto's pick, or ABCD for a fresh manual plan.
    private var activePattern: HarmonicPattern { pattern ?? currentAuto?.pattern ?? .abcd }
    private var inputLabels: [String] { activePattern.inputLabels }

    private var plan: HarmonicMath.Plan? {
        let n = inputLabels.count
        guard taps.count >= n else { return nil }
        let p = Array(taps.prefix(n))
        return HarmonicMath.plan(pattern: activePattern, x: activePattern.usesX ? p[0].price : nil,
                                 a: p[n - 3].price, b: p[n - 2].price, c: p[n - 1].price)
    }

    var body: some View {
        VStack(spacing: 8) {
            Picker("Timeframe", selection: $timeframe) {
                ForEach(BarTimeframe.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).padding(.horizontal)

            patternChips

            Picker("Source", selection: $source) {
                ForEach(Source.allCases) { src in Text(sourceLabel(src)).tag(src) }
            }
            .pickerStyle(.segmented).padding(.horizontal)
            .onChange(of: source) { _, _ in apply() }

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

    // MARK: - Pattern chips

    private var patternChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("Auto", selected: pattern == nil, state: nil) { choose(nil) }
                ForEach(HarmonicPattern.allCases) { p in
                    chip(p.label, selected: pattern == p, state: foundOnSide[p].map(\.inProgress)) { choose(p) }
                }
            }
            .padding(.horizontal)
        }
        .onChange(of: pattern) { _, _ in apply() }
    }

    /// A dot on the chip says the shape exists on this side: filled = in progress, hollow = completed.
    private func chip(_ title: String, selected: Bool, state: Bool?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let state { Image(systemName: state ? "circle.fill" : "circle").font(.system(size: 7)) }
                Text(title)
            }
            .font(.caption.weight(selected ? .semibold : .regular))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func choose(_ p: HarmonicPattern?) {
        if source == .manual { taps.removeAll(); copied = false }   // the tap labels change with the shape
        pattern = p
    }

    private func sourceLabel(_ src: Source) -> String {
        guard src != .manual else { return "Manual" }
        let m = found[src == .bullish] ?? [:]
        let has = pattern.map { m[$0] != nil } ?? !m.isEmpty
        return has ? src.label : "\(src.label) —"
    }

    // MARK: - Data

    private func load() async {
        error = nil
        do {
            bars = try await model.bars(symbol: symbol, timeframe: timeframe)
            if bars.isEmpty { error = "Alpaca returned no bars for \(symbol) on this timeframe." }
        } catch {
            bars = []
            self.error = (error as? MarketDataError)?.errorDescription ?? error.localizedDescription
        }
        findAutomatically()
    }

    /// Runs the scanner's pivot rule on the bars, finds the latest pattern of
    /// every shape on both sides, then opens the preferred side with no tapping.
    private func findAutomatically() {
        let pivots = HarmonicMath.findPivots(closes: bars.map(\.c))
        var f: [Bool: [HarmonicPattern: HarmonicMath.AutoPattern]] = [:]
        for side in [true, false] {
            var m: [HarmonicPattern: HarmonicMath.AutoPattern] = [:]
            for p in HarmonicPattern.allCases {
                if let a = HarmonicMath.latest(p, pivots: pivots, bullish: side) { m[p] = a }
            }
            f[side] = m
        }
        found = f
        if !seeded {
            seeded = true
            // Open on the shape the scanner named, when this chart has it too.
            if let named = HarmonicPattern.named(detectedLabel), f.values.contains(where: { $0[named] != nil }) { pattern = named }
        }
        func shown(_ side: Bool) -> HarmonicMath.AutoPattern? {
            let m = f[side] ?? [:]
            if let pattern { return m[pattern] }
            return HarmonicMath.pick(from: m)
        }
        if let pref = preferBullish, shown(pref) != nil { source = pref ? .bullish : .bearish }
        else if shown(true)?.inProgress == true { source = .bullish }
        else if shown(false)?.inProgress == true { source = .bearish }
        else if shown(true) != nil { source = .bullish }
        else if shown(false) != nil { source = .bearish }
        else { source = .manual }
        apply()
    }

    /// Loads the found pattern's points as the plan. Manual taps are the
    /// user's own and are left alone here (the onChange after a tap would
    /// otherwise wipe the tap that just switched the source to Manual).
    private func apply() {
        copied = false
        guard source != .manual else { return }
        taps = currentAuto?.points ?? []
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
        if source != .manual {                      // a tap means "I'll place them myself"
            pattern = pattern ?? activePattern      // Auto becomes the shape it had picked, so the labels are fixed
            source = .manual
            taps = []
        }
        let labels = inputLabels
        guard taps.count < labels.count, bars.indices.contains(index) else { return }
        // Snap to the bar's high or low, whichever the tap was nearer.
        let bar = bars[index]
        let snapped = abs(price - bar.h) <= abs(price - bar.l) ? bar.h : bar.l
        taps.append(PricePoint(label: labels[taps.count], price: snapped, index: index))
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
                     ? "Found from the last pivots: \(a.pattern.inputLabels.joined(separator: ", ")) are the newest swings and D is still ahead."
                     : "Latest completed \(a.bullish ? "bullish" : "bearish") \(a.pattern.label) on this chart; D printed at \(Fmt.price(a.d!.price)).")
                    .font(.caption).foregroundStyle(a.inProgress ? Color.primary : Color.secondary)
                if pattern == nil {
                    let others = HarmonicPattern.allCases.filter { $0 != a.pattern && foundOnSide[$0]?.inProgress == true }
                    if !others.isEmpty {
                        Text("The same swings also fit: \(others.map(\.label).joined(separator: ", ")). Pick one above for its projection.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if source != .manual {
                Text("No \(pattern?.label ?? "harmonic pattern") with the detector's shape in the recent \(source.label.lowercased()) pivots. Try the other side, another timeframe, or tap your own \(inputLabels.joined(separator: ", ")).")
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
                Text(plan.ratios.map { "\($0.name) \(ratioValue($0))" }.joined(separator: " · "))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                ForEach(plan.ratios.filter { !$0.ok }, id: \.name) { r in
                    Label("\(r.name) is \(ratioValue(r)); the detector wants \(bandText(r)).", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                ForEach(plan.warnings, id: \.self) { w in
                    Label(w, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                levelsGrid(plan)
                Button {
                    UIPasteboard.general.string = planText(plan)
                    copied = true
                } label: { Label(copied ? "Copied" : "Copy plan", systemImage: copied ? "checkmark" : "doc.on.doc") }
                .font(.caption)
            } else if taps.count >= inputLabels.count {
                Label(activePattern.usesX
                      ? "X, A, B, C must alternate (low, high, low, high or the reverse)."
                      : "A, B, C must alternate (high, low, high or low, high, low).", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Text(helpText).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }

    private func levelsGrid(_ plan: HarmonicMath.Plan) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow { Text("Side").foregroundStyle(.secondary); Text(plan.bullish ? "Bullish, buy at D" : "Bearish, short at D") }
            ForEach(plan.dLevels, id: \.label) { d in
                GridRow { Text(d.label).foregroundStyle(.secondary); Text(Fmt.price(d.price)) }
            }
            if let z = plan.zone {
                GridRow { Text("Detector's D zone").foregroundStyle(.secondary); Text("\(Fmt.price(z.lowerBound)) – \(Fmt.price(z.upperBound))") }
            }
            GridRow { Text("Entry").foregroundStyle(.secondary); Text(Fmt.price(plan.entry)).fontWeight(.semibold) }
            GridRow { Text("Stop").foregroundStyle(.secondary); Text(Fmt.price(plan.stop)).foregroundStyle(.red) }
            GridRow { Text("Target").foregroundStyle(.secondary); Text(Fmt.price(plan.target)).foregroundStyle(.green) }
            GridRow { Text("Reward : risk").foregroundStyle(.secondary); Text(rrText(plan)) }
        }
        .font(.caption.monospacedDigit())
    }

    private var cardTitle: String {
        if source == .manual {
            return taps.count < inputLabels.count ? "Tap \(inputLabels[taps.count]) on the chart" : "\(activePattern.label) projection"
        }
        return "\(source.label) \(activePattern.label)" + (currentAuto.map { $0.inProgress ? " · in progress" : " · completed" } ?? "")
    }

    private var helpText: String {
        let p = activePattern, s = p.spec
        if let ideal = s.idealAD, let ad = s.adXA {
            let retrace = (s.targetRetrace * 100).formatted(.number.precision(.fractionLength(0...1)))
            return "Tap X, A, B, C in order; each tap snaps to that bar's high or low. A \(p.label) completes at \(ideal) of XA beyond A (detector window \(HarmonicMath.pctBand(ad)), with CD \(HarmonicMath.multBand(s.cdBC)) BC); stop 1% beyond the zone's far edge, target a \(retrace)% retrace of AD."
        }
        return "Tap the bar where each pivot is; the tap snaps to that bar's high or low. D is projected at 1.272 and 1.618 of BC, stop 1% beyond the far D, target a 61.8% retrace of CD."
    }

    private func ratioValue(_ r: HarmonicMath.Ratio) -> String {
        r.band.upperBound <= 1 ? "\(Int((r.value * 100).rounded()))%" : r.value.formatted(.number.precision(.fractionLength(2))) + "×"
    }
    private func bandText(_ r: HarmonicMath.Ratio) -> String {
        r.band.upperBound <= 1 ? HarmonicMath.pctBand(r.band) : HarmonicMath.multBand(r.band)
    }

    private func rrText(_ plan: HarmonicMath.Plan) -> String {
        let risk = abs(plan.entry - plan.stop), reward = abs(plan.target - plan.entry)
        guard risk > 0 else { return "—" }
        return (reward / risk).formatted(.number.precision(.fractionLength(2))) + " : 1"
    }

    private func planText(_ plan: HarmonicMath.Plan) -> String {
        var lines = [
            "\(symbol) \(plan.pattern.label) \(plan.bullish ? "bullish" : "bearish") (\(timeframe.label), \(source == .manual ? "manual" : "auto"))",
            taps.map { "\($0.label)=\(Fmt.price($0.price))" }.joined(separator: " "),
            plan.ratios.map { "\($0.name) \(ratioValue($0))" }.joined(separator: "  "),
            plan.dLevels.map { "\($0.label)=\(Fmt.price($0.price))" }.joined(separator: "  ")
                + (plan.zone.map { "  zone \(Fmt.price($0.lowerBound))–\(Fmt.price($0.upperBound))" } ?? ""),
            "Entry \(Fmt.price(plan.entry))  Stop \(Fmt.price(plan.stop))  Target \(Fmt.price(plan.target))  R:R \(rrText(plan))",
        ]
        lines.append(contentsOf: plan.warnings)
        return lines.joined(separator: "\n")
    }
}

/// Candles with detected points, the pattern's legs, user taps, the
/// detector's D zone and the projected levels.
struct CandleChart: View {
    let bars: [Bar]
    let detected: [PricePoint]
    let taps: [PricePoint]
    let plan: HarmonicMath.Plan?
    let onTap: (Int, Double) -> Void

    /// Where to draw D while it hasn't printed: as far past C as B→C took, at least 3 bars.
    private var projectedX: Int? {
        guard plan != nil, !taps.contains(where: { $0.label == "D" }),
              let c = taps.first(where: { $0.label == "C" })?.index,
              let b = taps.first(where: { $0.label == "B" })?.index else { return nil }
        return c + max(3, c - b)
    }
    private var xMax: Int { max(bars.count - 1, projectedX ?? 0) }

    private var yDomain: ClosedRange<Double> {
        var lo = bars.map(\.l).min() ?? 0, hi = bars.map(\.h).max() ?? 1
        for p in detected + taps { lo = min(lo, p.price); hi = max(hi, p.price) }
        if let plan { for v in plan.levels { lo = min(lo, v); hi = max(hi, v) } }
        let pad = max((hi - lo) * 0.06, 0.1)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        Chart {
            if let plan, let z = plan.zone {
                RectangleMark(xStart: .value("Bar", 0), xEnd: .value("Bar", xMax),
                              yStart: .value("Zone", z.lowerBound), yEnd: .value("Zone", z.upperBound))
                    .foregroundStyle(.orange.opacity(0.12))
            }
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
            // The pattern's legs, point to point, in order.
            ForEach(taps) { p in
                if let i = p.index {
                    LineMark(x: .value("Bar", i), y: .value("Price", p.price), series: .value("Series", "legs"))
                        .foregroundStyle(.orange.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            if let plan, let dx = projectedX, let c = taps.first(where: { $0.label == "C" }), let ci = c.index {
                LineMark(x: .value("Bar", ci), y: .value("Price", c.price), series: .value("Series", "projection"))
                    .foregroundStyle(.orange.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                LineMark(x: .value("Bar", dx), y: .value("Price", plan.entry), series: .value("Series", "projection"))
                    .foregroundStyle(.orange.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                PointMark(x: .value("Bar", dx), y: .value("Price", plan.entry))
                    .foregroundStyle(.orange).symbolSize(70)
                    .annotation(position: .top, spacing: 2) { Text("D?").font(.caption.weight(.bold)).foregroundStyle(.orange) }
            }
            ForEach(taps) { p in
                PointMark(x: .value("Bar", p.index ?? 0), y: .value("Price", p.price))
                    .foregroundStyle(.orange).symbolSize(90)
                    .annotation(position: .top, spacing: 2) { Text(p.label).font(.caption.weight(.bold)).foregroundStyle(.orange) }
            }
            if let plan {
                ForEach(plan.dLevels, id: \.label) { d in
                    RuleMark(y: .value("D", d.price)).foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .trailing, alignment: .leading) { Text(d.label).font(.caption2).foregroundStyle(.orange) }
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
