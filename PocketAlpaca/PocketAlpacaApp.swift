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
    @State private var model: AppModel

    init() {
        // Simulator only: a drop file left by Scripts/simulator_provision.py is
        // applied before the model reads the Keychain. Inert on a device.
        Provisioning.applyDropFileIfPresent()
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(model)
        }
    }
}
