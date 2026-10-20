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
                    Picker("Cloud tiers", selection: $model.signalsFilter.maxTier) {
                        ForEach(SignalsFilter.tierChoices, id: \.self) { n in
                            Text(n >= 4 ? "All tiers" : (n == 1 ? "Tier 1 only" : "Tiers 1–\(n)")).tag(n)
                        }
                    }
                    Picker("Earnings window", selection: $model.signalsFilter.earningsDays) {
                        ForEach(SignalsFilter.dayChoices, id: \.self) { d in
                            Text(d == 0 ? "All dates" : "Next \(d) days").tag(d)
                        }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter signals")
            }
        }
        .task { await model.loadSignals() }
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

            if let cloud = model.signals?.cloudTiers {
                let longs = cloud.rows.filter { !$0.isShort && matches($0.symbol) }.sorted { $0.rank < $1.rank }
                let shorts = cloud.rows.filter { $0.isShort && matches($0.symbol) }.sorted { $0.rank < $1.rank }
                let scope = "\(model.signalsFilter.tierLabel.lowercased()) of \(cloud.totalRows ?? cloud.rows.count)"
                Section {
                    if longs.isEmpty { Text("No long candidates").foregroundStyle(.secondary) }
                    ForEach(longs) { row in cloudRow(row) }
                } header: {
                    header("Cloud Tiers · Long", count: longs.count, detail: [scanStamp(cloud), scope].compactMap { $0 }.joined(separator: " · "))
                }
                Section {
                    if shorts.isEmpty { Text("No short candidates").foregroundStyle(.secondary) }
                    ForEach(shorts) { row in cloudRow(row) }
                } header: {
                    header("Cloud Tiers · Short", count: shorts.count, detail: nil)
                }
            }

            if let earn = model.signals?.earnings {
                let visible = earn.rows.filter { matches($0.symbol) }
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
