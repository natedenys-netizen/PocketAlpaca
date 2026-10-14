//
//  PocketAlpacaApp.swift
//  PocketAlpaca
//
//  A private, read-only iPhone view of an Alpaca account.
//  Built on the Alpaca Connect program (OAuth, read scope only).
//

import SwiftUI

@main
struct PocketAlpacaApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(model)
        }
    }
}
