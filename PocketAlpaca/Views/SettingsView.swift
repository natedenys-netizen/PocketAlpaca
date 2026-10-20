import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var tokenInput = ""
    @State private var confirmSignOut = false
    @State private var signalsURLInput = TokenStore.signalsEndpoint?.absoluteString ?? ""
    @State private var signalsKeyInput = ""
    @State private var confirmClearSignals = false

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

                    LabeledContent("Paper token", value: model.hasToken(for: .paper) ? "Saved" : "None")
                    LabeledContent("Live token", value: model.hasToken(for: .live) ? "Saved" : "None")
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
                    Text(model.hasToken ? "Replace \(model.environment.label) token" : "Sign in to \(model.environment.label)")
                } footer: {
                    Text("The token is saved for the environment selected above (\(model.environment.label)). Get one by running Scripts/alpaca_oauth_once.py --env \(model.environment.rawValue) on your Mac. It is read-only and stays in this phone's Keychain. Revoke it any time at app.alpaca.markets under Connected Apps.")
                }

                if model.hasToken {
                    Section {
                        Button("Sign out of \(model.environment.label)", role: .destructive) { confirmSignOut = true }
                    }
                }

                Section {
                    TextField("https://script.google.com/macros/s/…/exec", text: $signalsURLInput)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField(model.signalsConfigured ? "New key (leave blank to keep)" : "Signals key", text: $signalsKeyInput)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save signals") { model.setSignals(endpoint: signalsURLInput, key: signalsKeyInput); signalsKeyInput = "" }
                        .disabled(URL(string: signalsURLInput.trimmingCharacters(in: .whitespacesAndNewlines)) == nil
                                  || (!model.signalsConfigured && signalsKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    if model.signalsConfigured {
                        LabeledContent("Status") {
                            if let err = model.signalsError {
                                Text(err).foregroundStyle(.red).multilineTextAlignment(.trailing).font(.footnote)
                            } else if let s = model.signals, let c = s.cloudTiers {
                                Text("Connected · \(c.rows.count) tiers · \(s.earnings?.rows.count ?? 0) earnings")
                            } else {
                                Text("Saved")
                            }
                        }
                        Button("Test signals now") { Task { await model.loadSignals(force: true) } }
                        Button("Disconnect signals", role: .destructive) { confirmClearSignals = true }
                    }
                    if let note = model.provisionNote {
                        Label(note, systemImage: "laptopcomputer.and.iphone").font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Signals")
                } footer: {
                    Text("The engines' candidate lists (Cloud Tiers and Earnings Watch) come from a read-only web endpoint in your Apps Script account. The URL is the deployment's /exec address; the key is printed once by setupSignalsApiKey().")
                }

                Section("About") {
                    LabeledContent("Access", value: "Read-only")
                    LabeledContent("Data", value: "Alpaca Trading API")
                    LabeledContent("Appearance", value: "Follows system")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .confirmationDialog("Remove the \(model.environment.label) token from this phone?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { model.clearToken() }
            }
            .confirmationDialog("Forget the signals endpoint and key?", isPresented: $confirmClearSignals, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) { model.clearSignals(); signalsURLInput = "" }
            }
        }
    }
}

#Preview {
    SettingsView().environment(AppModel())
}
