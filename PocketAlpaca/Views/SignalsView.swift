import SwiftUI

/// Today's candidates from the Universe engines: the morning cloud screen's
/// tiered list and the earnings watch list. Read-only, like everything else.
struct SignalsView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false
    @State private var chartTarget: ChartTarget?
    @State private var search = ""

    struct ChartTarget: Identifiable {
        let symbol: String
        let subtitle: String
        let notes: [String]
        var id: String { symbol + subtitle }
    }

    var body: some View {
        VStack(spacing: 0) {
            ErrorBanner()
            if !model.signalsConfigured {
                ContentUnavailableView {
                    Label("Signals not connected", systemImage: "antenna.radiowaves.left.and.right.slash")
                } description: {
                    Text("Add the Signals endpoint URL and key in Settings to see the engines' candidates here.")
                } actions: {
                    Button("Open Settings") { showSettings = true }
                }
            } else {
                list
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $chartTarget) { ChartSheet(symbol: $0.symbol, subtitle: $0.subtitle, notes: $0.notes) }
        .searchable(text: $search, prompt: "Symbol")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                @Bindable var model = model
                Menu {
                    Picker("Show", selection: $model.signalsFilter.view) {
                        ForEach(SignalsFilter.View.allCases) { Text($0.label).tag($0) }
                    }
                    if model.signalsFilter.view.showsCloud {
                        Toggle("Only full confluence (4 of 4)", isOn: $model.signalsFilter.confluenceOnly)
                        Menu("Tiers · \(model.signalsFilter.tierLabel)") {
                            ForEach(SignalsFilter.allTiers, id: \.self) { t in
                                Toggle(t, isOn: Binding(
                                    get: { model.signalsFilter.tiers.contains(t) },
                                    set: { on in if on { model.signalsFilter.tiers.insert(t) } else { model.signalsFilter.tiers.remove(t) } }))
                            }
                            Divider()
                            Button("Longs only") { model.signalsFilter.tiers = ["T1", "T2", "T3", "T4"] }
                            Button("Shorts only") { model.signalsFilter.tiers = ["S1", "S2", "S3", "S4"] }
                            Button("Top tiers (T1 T2 S1 S2)") { model.signalsFilter.tiers = ["T1", "T2", "S1", "S2"] }
                            Button("All tiers") { model.signalsFilter.tiers = Set(SignalsFilter.allTiers) }
                        }
                        Picker("Max price · \(model.signalsFilter.priceLabel)", selection: $model.signalsFilter.maxPrice) {
                            ForEach(SignalsFilter.priceChoices, id: \.self) { p in
                                Text(p == 0 ? "Any price" : "$\(Int(p)) or less").tag(p)
                            }
                        }
                        Picker("Sort tiers by", selection: $model.signalsFilter.tierSort) {
                            ForEach(SignalsFilter.TierSort.allCases) { Text($0.label).tag($0) }
                        }
                    }
                    Toggle("Only candidates an engine refused", isOn: $model.signalsFilter.refusedOnly)
                    if model.signalsFilter.view.showsPatterns {
                        Picker("Pattern type", selection: $model.signalsFilter.patternCategory) {
                            ForEach(SignalsFilter.PatternCategory.allCases) { Text($0.label).tag($0) }
                        }
                        Picker("Pattern direction", selection: $model.signalsFilter.patternDirection) {
                            ForEach(SignalsFilter.PatternDirection.allCases) { Text($0.label).tag($0) }
                        }
                    }
                    if model.signalsFilter.view.showsEarnings {
                        Picker("Earnings window · \(model.signalsFilter.daysLabel)", selection: $model.signalsFilter.earningsDays) {
                            ForEach(SignalsFilter.dayChoices, id: \.self) { d in
                                Text(d == 0 ? "All dates" : "Next \(d) days").tag(d)
                            }
                        }
                        Toggle("Only with a reaction call", isOn: $model.signalsFilter.callsOnly)
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter signals")
            }
        }
        .task { await model.loadSignals() }
    }

    /// The active choices, always visible so the list is never a mystery.
    private var filterSummary: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 8) {
            Picker("Show", selection: $model.signalsFilter.view) {
                ForEach(SignalsFilter.View.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if model.signalsFilter.view.showsCloud {
                        Pill(text: model.signalsFilter.tierLabel, tint: .blue)
                        Pill(text: model.signalsFilter.priceLabel, tint: .blue)
                        if model.signalsFilter.confluenceOnly { Pill(text: "full confluence", tint: .blue) }
                        if model.signalsFilter.tierSort != .tier { Pill(text: "sort: \(model.signalsFilter.tierSort.label)", tint: .blue) }
                    }
                    if model.signalsFilter.view.showsPatterns {
                        Pill(text: model.signalsFilter.patternCategory.label, tint: .teal)
                        if model.signalsFilter.patternDirection != .all { Pill(text: model.signalsFilter.patternDirection.label, tint: .teal) }
                    }
                    if model.signalsFilter.view.showsEarnings {
                        Pill(text: model.signalsFilter.daysLabel, tint: .purple)
                        if model.signalsFilter.callsOnly { Pill(text: "calls only", tint: .purple) }
                    }
                    if model.signalsFilter.refusedOnly { Pill(text: "refused only", tint: .orange) }
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Confluence plus a bonus when a same-direction pattern fired today.
    private func confluenceScore(_ row: CloudTierRow) -> Int {
        row.confluenceCount + (model.patterns(for: row.symbol, side: row.side).isEmpty ? 0 : 1)
    }

    private func sortedCloud(_ rows: [CloudTierRow]) -> [CloudTierRow] {
        switch model.signalsFilter.tierSort {
        case .tier:  return rows.sorted { ($0.rank, $0.symbol) < ($1.rank, $1.symbol) }
        case .confluence:
            return rows.sorted {
                let a = confluenceScore($0), b = confluenceScore($1)
                if a != b { return a > b }
                if $0.ichiStrength != $1.ichiStrength { return $0.ichiStrength > $1.ichiStrength }
                return ($0.rank, $0.symbol) < ($1.rank, $1.symbol)
            }
        case .rvol:  return rows.sorted { ($0.rvol ?? -1) > ($1.rvol ?? -1) }
        case .ichi:  return rows.sorted { ($0.ichiScore ?? -1) > ($1.ichiScore ?? -1) }
        case .price: return rows.sorted { ($0.price ?? .infinity) < ($1.price ?? .infinity) }
        }
    }

    private func matches(_ symbol: String) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces).uppercased()
        return q.isEmpty || symbol.uppercased().contains(q)
    }

    private var list: some View {
        List {
            if let err = model.signalsError, model.signals == nil {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red)
                }
            }

            Section { filterSummary }

            if let ref = model.signals?.refusals {
                Section {
                    refusalSummary("Cloud engine (2a)", ref.core)
                    refusalSummary("Earnings sleeve", ref.ecs)
                } header: {
                    Text("Refused in the last \(ref.days ?? 3) days")
                } footer: {
                    Text("From the engines' own refusal ledgers: the stage that stopped each candidate. A cap stage means the setup passed every quality gate and only a position limit said no.")
                }
            }

            if model.signalsFilter.view.showsCloud, let cloud = model.signals?.cloudTiers {
                let refusedOnly = model.signalsFilter.refusedOnly
                let fullOnly = model.signalsFilter.confluenceOnly
                let keep: (CloudTierRow) -> Bool = { r in
                    matches(r.symbol) && (!refusedOnly || model.coreRefusal(symbol: r.symbol, side: r.side) != nil) && (!fullOnly || r.isFullConfluence)
                }
                let longs = sortedCloud(cloud.rows.filter { !$0.isShort && keep($0) })
                let shorts = sortedCloud(cloud.rows.filter { $0.isShort && keep($0) })
                let scope = "of \(cloud.totalRows ?? cloud.rows.count) on the sheet"
                if !longs.isEmpty || model.signalsFilter.tiers.contains(where: { $0.hasPrefix("T") }) {
                    Section {
                        if longs.isEmpty { Text("No long candidates match").foregroundStyle(.secondary) }
                        ForEach(longs) { row in cloudRow(row) }
                    } header: {
                        header("Long", count: longs.count, detail: [scanStamp(cloud), scope].compactMap { $0 }.joined(separator: " · "))
                    }
                }
                if !shorts.isEmpty || model.signalsFilter.tiers.contains(where: { $0.hasPrefix("S") }) {
                    Section {
                        if shorts.isEmpty { Text("No short candidates match").foregroundStyle(.secondary) }
                        ForEach(shorts) { row in cloudRow(row) }
                    } header: {
                        header("Short", count: shorts.count, detail: longs.isEmpty ? [scanStamp(cloud), scope].compactMap { $0 }.joined(separator: " · ") : nil)
                    }
                }
            }

            if model.signalsFilter.view.showsPatterns, let pats = model.signals?.patterns {
                patternSections(pats)
            }

            if model.signalsFilter.view.showsEarnings, let earn = model.signals?.earnings {
                let visible = earn.rows.filter { matches($0.symbol) && (!model.signalsFilter.callsOnly || !($0.reactionCall ?? "").isEmpty)
                                                 && (!model.signalsFilter.refusedOnly || model.ecsRefusal(symbol: $0.symbol) != nil) }
                let groups = Dictionary(grouping: visible) { $0.section ?? "OTHER" }
                let scope = "\(model.signalsFilter.daysLabel.lowercased()) of \(earn.totalRows ?? earn.rows.count)"
                ForEach(Array(["BULLISH", "BEARISH", "NEUTRAL", "OTHER"].enumerated()), id: \.element) { i, key in
                    if let rows = groups[key], !rows.isEmpty {
                        Section {
                            ForEach(rows.sorted { ($0.earningsDate ?? .distantFuture) < ($1.earningsDate ?? .distantFuture) }) { row in
                                earningsRow(row)
                            }
                        } header: {
                            header("Earnings · \(key.capitalized)", count: rows.count, detail: i == 0 || groups.keys.sorted().first == key ? scope : nil)
                        }
                    }
                }
                if visible.isEmpty {
                    Section { Text("No earnings candidates in this window").foregroundStyle(.secondary) } header: { header("Earnings", count: 0, detail: scope) }
                }
            }

            if model.signals == nil && model.signalsError == nil {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await model.loadSignals(force: true) }
        .safeAreaInset(edge: .bottom) {
            if let t = model.signals?.generatedAt {
                Text("Engines' data as of \(t.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Rows

    private func header(_ title: String, count: Int, detail: String?) -> some View {
        HStack {
            Text("\(title) (\(count))")
            Spacer()
            if let d = detail { Text(d) }
        }
    }

    private func scanStamp(_ cloud: CloudTiersSection) -> String? {
        guard let d = cloud.scanDate else { return nil }
        let day = String(d.prefix(10))
        return [day, cloud.scanTime].compactMap { $0 }.joined(separator: " ")
    }

    private func heldPosition(_ symbol: String) -> Position? {
        model.positions.first { $0.symbol == symbol }
    }

    private func cloudRow(_ row: CloudTierRow) -> some View {
        let sideColor: Color = row.isShort ? .red : .green
        let pats = model.patterns(for: row.symbol, side: row.side)
        let full = row.isFullConfluence
        return Button {
            chartTarget = ChartTarget(symbol: row.symbol,
                                      subtitle: "\(row.tier) \(row.side.capitalized) · \(row.confluenceCount)/4 aligned · Ichi \(Int(row.ichiScore ?? 0))",
                                      notes: pats.map { "\($0.category.capitalized): \($0.pattern)" + ($0.entryRule.map { " — \($0)" } ?? "") })
        } label: {
            HStack(alignment: .top, spacing: 10) {
                TierBadge(tier: row.tier, isShort: row.isShort)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(row.symbol).font(.headline)
                        if let p = heldPosition(row.symbol) { HeldChip(position: p) }
                        else if let r = model.coreRefusal(symbol: row.symbol, side: row.side) { RefusalPill(row: r) }
                        if full { Pill(text: "4/4", tint: sideColor) }
                    }
                    confluenceLine(row, sideColor: sideColor)
                    Text(cloudDetail(row))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .lineLimit(2)
                    if !pats.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(pats.prefix(2)) { Pill(text: $0.pattern, tint: .teal) }
                            if pats.count > 2 { Text("+\(pats.count - 2)").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(Fmt.price(row.price)).font(.body.monospacedDigit())
                    if let r = row.rvol { Text("RVOL \(r.formatted(.number.precision(.fractionLength(1))))").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .listRowBackground(confluenceBackground(row, sideColor: sideColor))
    }

    /// Four dots, one per factor, filled when it agrees with the side.
    private func confluenceLine(_ row: CloudTierRow, sideColor: Color) -> some View {
        HStack(spacing: 8) {
            ForEach(row.confluence, id: \.self) { f in
                HStack(spacing: 3) {
                    Image(systemName: f.ok ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 9))
                        .foregroundStyle(f.ok ? sideColor : Color.secondary.opacity(0.5))
                    Text(f.name).font(.system(size: 10)).foregroundStyle(f.ok ? .primary : .secondary)
                }
            }
        }
        .lineLimit(1).minimumScaleFactor(0.8)
    }

    /// Outline the row when the factors line up: solid and tinted at 4/4, thin at 3/4.
    private func confluenceBackground(_ row: CloudTierRow, sideColor: Color) -> some View {
        let count = row.confluenceCount
        return ZStack {
            Color(.secondarySystemGroupedBackground)
            if count == 4 { sideColor.opacity(0.10) }
            if count >= 3 {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(sideColor.opacity(count == 4 ? 0.9 : 0.45), lineWidth: count == 4 ? 2.5 : 1)
                    .padding(3)
            }
        }
    }

    // MARK: - Patterns

    @ViewBuilder private func patternSections(_ pats: PatternsSection) -> some View {
        let f = model.signalsFilter
        let cats: [String] = f.patternCategory == .all ? ["candlestick", "harmonic", "chart"] : [f.patternCategory.rawValue]
        ForEach(cats, id: \.self) { cat in
            let rows = pats.rows.filter { r in
                r.category == cat && matches(r.symbol)
                    && (f.patternDirection == .all || (f.patternDirection == .bullish ? r.isBullish : r.isBearish))
                    && (!f.refusedOnly || model.coreRefusal(symbol: r.symbol, side: r.isBearish ? "SHORT" : "LONG") != nil)
            }.sorted { ($0.confidenceFraction ?? 0) > ($1.confidenceFraction ?? 0) }
            let info = pats.categories[cat]
            Section {
                if rows.isEmpty { Text("No \(cat) patterns match").foregroundStyle(.secondary) }
                ForEach(rows) { patternRow($0) }
            } header: {
                header("\(cat.capitalized) patterns", count: rows.count,
                       detail: info.map { "\($0.bullish) bull · \($0.bearish) bear of \($0.total)" + ($0.scanDate.map { " · \(String($0.prefix(10)))" } ?? "") })
            }
        }
    }

    private func patternRow(_ r: PatternRow) -> some View {
        let tint: Color = r.isBearish ? .red : (r.isBullish ? .green : .secondary)
        return Button {
            chartTarget = ChartTarget(symbol: r.symbol,
                                      subtitle: "\(r.category.capitalized) · \(r.pattern)" + (r.direction.map { " · \($0.capitalized)" } ?? ""),
                                      notes: [r.description, r.cheatsheetPattern.map { "Cheatsheet: \($0)" }, r.entryRule.map { "Entry: \($0)" }, r.stopRule.map { "Stop: \($0)" }].compactMap { $0 })
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(r.symbol).font(.headline)
                        if let d = r.direction { Pill(text: d.capitalized, tint: tint) }
                        if let p = heldPosition(r.symbol) { HeldChip(position: p) }
                    }
                    Text(r.pattern).font(.subheadline)
                    HStack(spacing: 6) {
                        if let st = r.strength, !st.isEmpty { Text(st) }
                        if let rr = r.rr { Text("· R:R \(rr.formatted(.number.precision(.fractionLength(0...2))))") }
                        if let t = r.targetPct { Text("· target \(t.formatted(.number.precision(.fractionLength(0...1))))%") }
                        if let sp = r.stopPct { Text("· stop \(sp.formatted(.number.precision(.fractionLength(0...1))))%") }
                    }
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(Fmt.price(r.price)).font(.body.monospacedDigit())
                    if let c = r.confidenceFraction {
                        Text("\(Int((c * 100).rounded()))% conf").font(.caption.monospacedDigit()).foregroundStyle(tint)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func cloudDetail(_ row: CloudTierRow) -> String {
        var parts: [String] = []
        if let s = row.ichiScore { parts.append("Ichi \(s.formatted(.number.precision(.fractionLength(0...1))))") }
        if let d = row.daysAbove { parts.append("\(Int(d))d \(row.isShort ? "below" : "above")") }
        if let c = row.cloudColor, !c.isEmpty { parts.append(c.lowercased() + " cloud") }
        if let t = row.tkCross, !t.isEmpty { parts.append("TK " + t.lowercased()) }
        if let h = row.hourlyPos, !h.isEmpty { parts.append("hourly " + h.lowercased()) }
        return parts.joined(separator: " · ")
    }

    private func earningsRow(_ row: EarningsRow) -> some View {
        Button {
            chartTarget = ChartTarget(symbol: row.symbol,
                                      subtitle: "Earnings " + earningsWhen(row) + (row.section.map { " · \($0.capitalized)" } ?? ""),
                                      notes: [row.take, row.catalystAngle.map { "Catalyst: \($0)" }, row.optionsPlay.map { "Options play: \($0)" }].compactMap { $0 })
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.symbol).font(.headline)
                    if let p = heldPosition(row.symbol) { HeldChip(position: p) }
                    else if let r = model.ecsRefusal(symbol: row.symbol) { RefusalPill(row: r) }
                    Spacer()
                    Text(earningsWhen(row)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    if let c = row.reactionCall, !c.isEmpty { Pill(text: "Call: \(c)", tint: callTint(c)) }
                    if let v = row.conviction, !v.isEmpty { Pill(text: v, tint: .secondary) }
                    if let iv = row.ivRank { Pill(text: "IV \(Int(iv))", tint: .secondary) }
                    if let s = row.recentSurprise { Pill(text: "Surprise \(s.formatted(.number.precision(.fractionLength(0...1))))%", tint: s >= 0 ? .green : .red) }
                }
                if let t = row.take, !t.isEmpty {
                    Text(t).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func refusalSummary(_ title: String, _ g: RefusalGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(g.count) refusal\(g.count == 1 ? "" : "s")").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            if g.count > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(g.topStages.prefix(6), id: \.stage) { st in
                            Pill(text: "\(RefusalPill.label(st.stage)) \(st.count)", tint: RefusalPill.tint(st.stage))
                        }
                    }
                }
            } else {
                Text("Nothing refused in the window").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func earningsWhen(_ row: EarningsRow) -> String {
        var s = row.earningsDate.map { $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? "date ?"
        if let t = row.timing, !t.isEmpty { s += " · " + t.uppercased() }
        return s
    }

    private func callTint(_ call: String) -> Color {
        let c = call.lowercased()
        if c.contains("avoid") { return .orange }
        if c.contains("bull") || c.contains("up") || c.contains("beat") { return .green }
        if c.contains("bear") || c.contains("down") || c.contains("miss") { return .red }
        return .secondary
    }
}

struct TierBadge: View {
    let tier: String
    let isShort: Bool
    var body: some View {
        Text(tier)
            .font(.caption.weight(.bold).monospacedDigit())
            .frame(width: 34, height: 24)
            .background((isShort ? Color.red : Color.green).opacity(opacity), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(isShort ? .red : .green)
    }
    private var opacity: Double {
        switch Int(tier.dropFirst()) ?? 4 {
        case 1: return 0.28
        case 2: return 0.20
        case 3: return 0.14
        default: return 0.09
        }
    }
}

/// "refused: cap" — the engine's own stage name, lightly humanised.
struct RefusalPill: View {
    let row: RefusalRow
    var body: some View {
        Pill(text: "refused: \(Self.label(row.stage))", tint: Self.tint(row.stage))
    }
    static func label(_ stage: String) -> String {
        stage.replacingOccurrences(of: "_", with: " ").lowercased()
    }
    static func tint(_ stage: String) -> Color {
        let s = stage.lowercased()
        if s.contains("cap") || s.contains("slot") { return .orange }      // quality passed; a limit said no
        if s.contains("bias") { return .purple }
        return .secondary
    }
}

struct HeldChip: View {
    let position: Position
    var body: some View {
        Text("held \(position.isShort ? "short" : "long")")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.blue.opacity(0.15), in: Capsule())
            .foregroundStyle(.blue)
    }
}

struct Pill: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
            .lineLimit(1)
    }
}

#Preview {
    NavigationStack { SignalsView().navigationTitle("Signals") }
        .environment(AppModel())
}
