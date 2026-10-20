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
        // Simulator only: accept settings handed over by Scripts/simulator_provision.py
        // before the model reads the Keychain. Compiles to nothing on a device.
        Provisioning.applyFromEnvironmentIfPresent()
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(model)
        }
    }
}
