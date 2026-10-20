import SwiftUI
import WebKit

/// A TradingView chart for one symbol, inside the app, with the Ichimoku
/// cloud study already on so it shows the same clouds the engines score.
/// Uses TradingView's free embeddable widget; no account needed.
struct ChartSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let symbol: String
    var subtitle: String? = nil
    var notes: [String] = []

    @State private var interval: ChartInterval = .daily
    @State private var showPosition = false

    enum ChartInterval: String, CaseIterable, Identifiable {
        case daily = "D", hourly = "60", fifteen = "15"
        var id: String { rawValue }
        var label: String { self == .daily ? "Daily" : (self == .hourly ? "Hourly" : "15 min") }
    }

    private var heldPosition: Position? { model.positions.first { $0.symbol == symbol } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Picker("Timeframe", selection: $interval) {
                    ForEach(ChartInterval.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.bottom, 8)
                TradingViewChart(symbol: symbol, interval: interval.rawValue, dark: colorScheme == .dark)
                    .id("\(symbol)-\(interval.rawValue)-\(colorScheme == .dark)")
                if !notes.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(notes, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                    .frame(maxHeight: 150)
                }
            }
            .navigationTitle(symbol)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: URL(string: "https://www.tradingview.com/chart/?symbol=\(symbol)")!) {
                        Label("Open in TradingView", systemImage: "arrow.up.right.square")
                    }
                }
            }
            .sheet(isPresented: $showPosition) {
                if let p = heldPosition { PositionDetailView(position: p) }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let s = subtitle { Text(s).font(.subheadline).foregroundStyle(.secondary) }
                Text("Ichimoku cloud overlay · \(interval.label)").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if let p = heldPosition {
                Button { showPosition = true } label: {
                    HStack(spacing: 6) {
                        HeldChip(position: p)
                        Text(Fmt.money(p.unrealizedPl.value, signed: true))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.pnl(p.unrealizedPl.value))
                    }
                }
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
    }
}

/// WKWebView hosting TradingView's Advanced Chart widget.
struct TradingViewChart: UIViewRepresentable {
    let symbol: String
    let interval: String
    let dark: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.loadHTMLString(html, baseURL: URL(string: "https://www.tradingview.com"))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private var html: String {
        let bg = dark ? "#000000" : "#ffffff"
        // Studies: the Ichimoku cloud is the one the engines trade from.
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>html,body{margin:0;height:100%;background:\(bg)} #tv{height:100%}</style></head>
        <body><div id="tv"></div>
        <script src="https://s3.tradingview.com/tv.js"></script>
        <script>
        new TradingView.widget({
          autosize: true,
          symbol: "\(symbol)",
          interval: "\(interval)",
          timezone: "America/New_York",
          theme: "\(dark ? "dark" : "light")",
          style: "1",
          locale: "en",
          hide_top_toolbar: false,
          hide_legend: false,
          save_image: false,
          studies: ["IchimokuCloud@tv-basicstudies"],
          container_id: "tv"
        });
        </script></body></html>
        """
    }
}
