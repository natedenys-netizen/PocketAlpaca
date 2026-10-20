import WidgetKit
import SwiftUI

// MARK: - Timeline

struct AccountEntry: TimelineEntry {
    let date: Date
    let environment: AlpacaEnvironment
    let hasToken: Bool
    let equity: Double?
    let dayChange: Double?
    let dayChangePct: Double?
    let longValue: Double?
    let shortValue: Double?
    let marketOpen: Bool?
    let error: String?

    static let placeholder = AccountEntry(date: .now, environment: .paper, hasToken: true,
                                          equity: 3157.19, dayChange: -5.61, dayChangePct: -0.0018,
                                          longValue: 726.40, shortValue: -1134.04, marketOpen: false, error: nil)
}

struct AccountProvider: TimelineProvider {
    func placeholder(in context: Context) -> AccountEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (AccountEntry) -> Void) {
        if context.isPreview { completion(.placeholder); return }
        Task { completion(await fetch()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AccountEntry>) -> Void) {
        Task {
            let entry = await fetch()
            // WidgetKit allows roughly 40–70 refreshes a day. Every 20 minutes while
            // the market is open, hourly otherwise, keeps well inside that.
            let minutes: Double = (entry.marketOpen ?? false) ? 20 : 60
            completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(minutes * 60))))
        }
    }

    /// Reads the token the app saved in the shared Keychain and asks Alpaca
    /// directly, so the widget stays current without the app being open.
    private func fetch() async -> AccountEntry {
        let env = TokenStore.environment
        guard let token = TokenStore.load(for: env) else {
            return AccountEntry(date: .now, environment: env, hasToken: false, equity: nil, dayChange: nil, dayChangePct: nil,
                                longValue: nil, shortValue: nil, marketOpen: nil, error: nil)
        }
        let client = LiveAlpacaClient(environment: env, token: token)
        do {
            async let a = client.account()
            async let c = client.clock()
            let (acct, clock) = try await (a, c)
            return AccountEntry(date: .now, environment: env, hasToken: true,
                                equity: acct.equity.value, dayChange: acct.dayChange, dayChangePct: acct.dayChangePct,
                                longValue: acct.longMarketValue.value, shortValue: acct.shortMarketValue.value,
                                marketOpen: clock.isOpen, error: nil)
        } catch {
            return AccountEntry(date: .now, environment: env, hasToken: true, equity: nil, dayChange: nil, dayChangePct: nil,
                                longValue: nil, shortValue: nil, marketOpen: nil,
                                error: (error as? AlpacaError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

// MARK: - Views

struct PocketAlpacaWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: AccountEntry

    var body: some View {
        Group {
            if !entry.hasToken {
                message("Open PocketAlpaca and sign in", icon: "person.crop.circle.badge.exclamationmark")
            } else if let err = entry.error, entry.equity == nil {
                message(err, icon: "exclamationmark.triangle")
            } else if family == .systemMedium {
                medium
            } else {
                small
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Spacer(minLength: 0)
            Text(Fmt.money(entry.equity))
                .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                .minimumScaleFactor(0.6).lineLimit(1)
            changeLine
            Spacer(minLength: 0)
            footer
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                header
                Spacer(minLength: 0)
                Text(Fmt.money(entry.equity))
                    .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                    .minimumScaleFactor(0.6).lineLimit(1)
                changeLine
                Spacer(minLength: 0)
                footer
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                stat("Long", entry.longValue, tint: .green)
                stat("Short", entry.shortValue, tint: .red)
                stat("Net", (entry.longValue ?? 0) + (entry.shortValue ?? 0), tint: .primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(.green)
            Text("Equity").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(entry.environment.label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(entry.environment == .live ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(entry.environment == .live ? .orange : .secondary)
        }
    }

    private var changeLine: some View {
        HStack(spacing: 6) {
            Text(Fmt.money(entry.dayChange, signed: true))
            Text(Fmt.percent(entry.dayChangePct))
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .foregroundStyle(Color.pnl(entry.dayChange))
        .lineLimit(1).minimumScaleFactor(0.7)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if let open = entry.marketOpen {
                Circle().fill(open ? Color.green : Color.secondary).frame(width: 6, height: 6)
                Text(open ? "Open" : "Closed")
            }
            Text("· \(entry.date.formatted(date: .omitted, time: .shortened))")
        }
        .font(.system(size: 10)).foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func stat(_ title: String, _ value: Double?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(Fmt.money(value)).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func message(_ text: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(.secondary)
            Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Widget

struct PocketAlpacaWidget: Widget {
    let kind = "PocketAlpacaAccount"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AccountProvider()) { entry in
            PocketAlpacaWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Account")
        .description("Equity, today's change, and market status from your Alpaca account.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    PocketAlpacaWidget()
} timeline: {
    AccountEntry.placeholder
}

#Preview(as: .systemMedium) {
    PocketAlpacaWidget()
} timeline: {
    AccountEntry.placeholder
}
