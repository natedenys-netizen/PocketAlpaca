import SwiftUI

struct RootTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false

    var body: some View {
        TabView {
            NavigationStack {
                OverviewView()
                    .navigationTitle("Overview")
                    .toolbar { settingsButton }
            }
            .tabItem { Label("Overview", systemImage: "chart.line.uptrend.xyaxis") }

            NavigationStack {
                PositionsView()
                    .navigationTitle("Positions")
                    .toolbar { settingsButton }
            }
            .tabItem { Label("Positions", systemImage: "briefcase") }

            NavigationStack {
                OrdersView()
                    .navigationTitle("Orders")
                    .toolbar { settingsButton }
            }
            .tabItem { Label("Orders", systemImage: "arrow.left.arrow.right") }

            NavigationStack {
                FillsView()
                    .navigationTitle("Fills")
                    .toolbar { settingsButton }
            }
            .tabItem { Label("Fills", systemImage: "clock.arrow.circlepath") }

            NavigationStack {
                SignalsView()
                    .navigationTitle("Signals")
                    .toolbar { settingsButton }
            }
            .tabItem { Label("Signals", systemImage: "antenna.radiowaves.left.and.right") }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .task { await model.refreshAll() }
        .task(id: scenePhase) {
            // Refresh every 60 s while the app is on screen; stop when backgrounded.
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled { break }
                await model.refreshAll()
            }
        }
    }

    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Settings")
        }
    }
}

/// Shown at the top of every screen while there is no token.
struct SampleDataBanner: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if model.isUsingSampleData {
            Label("Sample data. Paste your Alpaca token in Settings.", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.thinMaterial)
        }
    }
}

/// Shown under the banner when the last refresh failed.
struct ErrorBanner: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let err = model.lastError {
            Label(err, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.red.opacity(0.08))
        }
    }
}
