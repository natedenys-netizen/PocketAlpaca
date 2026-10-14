import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var tokenInput = ""
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    Picker("Environment", selection: Binding(
                        get: { model.environment },
                        set: { model.setEnvironment($0) }
                    )) {
                        ForEach(AlpacaEnvironment.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    LabeledContent("Token", value: model.hasToken ? "Saved in Keychain" : "None")
                    if let a = model.account, model.hasToken {
                        LabeledContent("Account", value: a.accountNumber ?? "—")
                        LabeledContent("Status", value: a.status ?? "—")
                    }
                }

                Section {
                    SecureField("Paste Alpaca OAuth token", text: $tokenInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save token") {
                        model.setToken(tokenInput)
                        tokenInput = ""
                    }
                    .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text(model.hasToken ? "Replace token" : "Sign in")
                } footer: {
                    Text("Get the token once by running the OAuth script on your Mac (Scripts/alpaca_oauth_once.py). It is read-only and stays in this phone's Keychain. Revoke it any time at app.alpaca.markets under Connected Apps.")
                }

                if model.hasToken {
                    Section {
                        Button("Sign out", role: .destructive) { confirmSignOut = true }
                    }
                }

                Section("About") {
                    LabeledContent("Access", value: "Read-only")
                    LabeledContent("Data", value: "Alpaca Trading API")
                    LabeledContent("Appearance", value: "Follows system")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .confirmationDialog("Remove the token from this phone?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { model.clearToken() }
            }
        }
    }
}

#Preview {
    SettingsView().environment(AppModel())
}
