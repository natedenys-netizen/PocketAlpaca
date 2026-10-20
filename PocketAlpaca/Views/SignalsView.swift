import SwiftUI

/// Today's candidates from the Universe engines: the morning cloud screen's
/// tiered list and the earnings watch list. Read-only, like everything else.
struct SignalsView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false
    @State private var selectedPosition: Position?
    @State private var search = ""

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
        .sheet(item: $selectedPosition) { PositionDetailView(position: $0) }
        .searchable(text: $search, prompt: "Symbol")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                @Bindable var model = model
                Menu {
                    Picker("Show", selection: $model.signalsFilter.view) {
                        ForEach(SignalsFilter.View.allCases) { Text($0.label).tag($0) }
                    }
                    if model.signalsFilter.view != .earnings {
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
                    if model.signalsFilter.view != .cloud {
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
                    if model.signalsFilter.view != .earnings {
                        Pill(text: model.signalsFilter.tierLabel, tint: .blue)
                        Pill(text: model.signalsFilter.priceLabel, tint: .blue)
                        if model.signalsFilter.tierSort != .tier { Pill(text: "sort: \(model.signalsFilter.tierSort.label)", tint: .blue) }
                    }
                    if model.signalsFilter.view != .cloud {
                        Pill(text: model.signalsFilter.daysLabel, tint: .purple)
                        if model.signalsFilter.callsOnly { Pill(text: "calls only", tint: .purple) }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func sortedCloud(_ rows: [CloudTierRow]) -> [CloudTierRow] {
        switch model.signalsFilter.tierSort {
        case .tier:  return rows.sorted { ($0.rank, $0.symbol) < ($1.rank, $1.symbol) }
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

            if model.signalsFilter.view != .earnings, let cloud = model.signals?.cloudTiers {
                let longs = sortedCloud(cloud.rows.filter { !$0.isShort && matches($0.symbol) })
                let shorts = sortedCloud(cloud.rows.filter { $0.isShort && matches($0.symbol) })
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

            if model.signalsFilter.view != .cloud, let earn = model.signals?.earnings {
                let visible = earn.rows.filter { matches($0.symbol) && (!model.signalsFilter.callsOnly || !($0.reactionCall ?? "").isEmpty) }
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
        Button {
            if let p = heldPosition(row.symbol) { selectedPosition = p }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                TierBadge(tier: row.tier, isShort: row.isShort)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(row.symbol).font(.headline)
                        if let p = heldPosition(row.symbol) { HeldChip(position: p) }
                    }
                    Text(cloudDetail(row))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .lineLimit(2)
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
            if let p = heldPosition(row.symbol) { selectedPosition = p }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.symbol).font(.headline)
                    if let p = heldPosition(row.symbol) { HeldChip(position: p) }
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
