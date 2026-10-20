import SwiftUI

enum PositionSort: String, CaseIterable, Identifiable {
    case symbol, dollar, percent, value
    var id: String { rawValue }
    var label: String {
        switch self {
        case .symbol:  return "Symbol A–Z"
        case .dollar:  return "Gain, $"
        case .percent: return "Gain, %"
        case .value:   return "Position size"
        }
    }
    var systemImage: String {
        switch self {
        case .symbol:  return "textformat.abc"
        case .dollar:  return "dollarsign.circle"
        case .percent: return "percent"
        case .value:   return "chart.bar"
        }
    }

    func sorted(_ positions: [Position]) -> [Position] {
        switch self {
        case .symbol:  return positions.sorted { $0.symbol < $1.symbol }
        case .dollar:  return positions.sorted { ($0.unrealizedPl.value ?? 0) > ($1.unrealizedPl.value ?? 0) }
        case .percent: return positions.sorted { ($0.unrealizedPlpc.value ?? 0) > ($1.unrealizedPlpc.value ?? 0) }
        case .value:   return positions.sorted { abs($0.marketValue.value ?? 0) > abs($1.marketValue.value ?? 0) }
        }
    }
}

struct PositionsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("positionsSort") private var sortRaw = PositionSort.symbol.rawValue
    @State private var selected: Position?

    private var sort: PositionSort { PositionSort(rawValue: sortRaw) ?? .symbol }
    private var positions: [Position] { sort.sorted(model.positions) }

    var body: some View {
        VStack(spacing: 0) {
            SampleDataBanner()
            ErrorBanner()
            List {
                Section {
                    summaryRow
                    exposureRow
                    protectionRow
                }
                Section(header: Text("\(model.positions.count) position\(model.positions.count == 1 ? "" : "s") · \(sort.label)")) {
                    if model.positions.isEmpty && !model.isRefreshing {
                        ContentUnavailableView("No open positions", systemImage: "briefcase",
                                               description: Text("Positions appear here as soon as the account holds any."))
                    } else {
                        ForEach(positions) { position in
                            Button { selected = position } label: {
                                PositionRow(position: position, ledger: model.ledgerRow(for: position.symbol))
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(LedgerHeat.rowBackground(fraction: position.unrealizedPlpc.value))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await model.refreshAll() }
        }
        .safeAreaInset(edge: .bottom) { refreshStamp }
        .sheet(item: $selected) { PositionDetailView(position: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Sort by", selection: $sortRaw) {
                        ForEach(PositionSort.allCases) { Label($0.label, systemImage: $0.systemImage).tag($0.rawValue) }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort positions")
            }
        }
    }

    // Long and short exposure. Alpaca's account figures are authoritative;
    // the sums of the position rows are the fallback while the account loads.
    private var longValue: Double {
        model.account?.longMarketValue.value
            ?? model.positions.filter { !$0.isShort }.compactMap { $0.marketValue.value }.reduce(0, +)
    }
    private var shortValue: Double {
        model.account?.shortMarketValue.value
            ?? model.positions.filter { $0.isShort }.compactMap { $0.marketValue.value }.reduce(0, +)
    }

    /// From the engines' ledger: how many held positions have no stop or only
    /// partial coverage. Hidden until the Signals endpoint is connected.
    @ViewBuilder private var protectionRow: some View {
        if model.signals?.ledger != nil {
            let bad = model.unprotectedPositions
            if bad.isEmpty {
                Label("Every position has a stop covering all shares", systemImage: "checkmark.shield")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Label("\(bad.count) position\(bad.count == 1 ? "" : "s") not fully protected: \(bad.map(\.symbol).joined(separator: ", "))",
                      systemImage: "exclamationmark.shield.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.red)
            }
        } else if model.signalsConfigured == false {
            Label("Connect Signals in Settings to see each position's engine and stop", systemImage: "antenna.radiowaves.left.and.right")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var exposureRow: some View {
        HStack {
            exposureCell("Long", longValue, tint: .green)
            Divider().frame(height: 28)
            exposureCell("Short", shortValue, tint: .red)
            Divider().frame(height: 28)
            exposureCell("Net", longValue + shortValue, tint: .primary)
        }
        .padding(.vertical, 2)
    }

    private func exposureCell(_ title: String, _ value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Fmt.money(value)).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Sits in the bottom safe-area inset, so the list scrolls above it instead of under it.
    private var refreshStamp: some View {
        Group {
            if let t = model.lastRefresh {
                Text("Updated \(t.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.vertical, 4)
            }
        }
    }
}

struct PositionRow: View {
    let position: Position
    var ledger: LedgerRow? = nil

    private var atRisk: Bool { ledger.map { $0.unprotected || $0.noStop } ?? false }

    var body: some View {
        HStack(alignment: .top) {
            if atRisk {
                RoundedRectangle(cornerRadius: 2).fill(Color.red).frame(width: 4)
                    .accessibilityLabel("Not fully protected")
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(position.symbol).font(.headline)
                    Text(position.isShort ? "SHORT" : "LONG")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(position.isShort ? Color.red.opacity(0.15) : Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(position.isShort ? .red : .green)
                    if let tag = ledger?.engineTag {
                        Text(tag).font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                Text("\(Fmt.qty(position.signedQty)) sh  ·  avg \(Fmt.price(position.avgEntryPrice.value))  →  \(Fmt.price(position.currentPrice.value))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let l = ledger {
                    HStack(spacing: 6) {
                        Image(systemName: atRisk ? "exclamationmark.shield.fill" : "shield")
                        Text(l.stopSummary)
                        if let d = l.daysHeld { Text("· \(Int(d))d held") }
                        if l.unprotected { Text("· shares unprotected").fontWeight(.semibold) }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(atRisk ? Color.red : Color.secondary)
                }
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
