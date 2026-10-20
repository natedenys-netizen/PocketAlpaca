import Foundation

/// Simulator-only hand-off of settings from the Mac, so nothing has to be typed
/// into the simulator. `Scripts/simulator_provision.py` launches the app with
/// an environment variable `SIMCTL_CHILD_PA_PROVISION=<base64 JSON>`; simctl
/// strips the prefix, and this reads `PA_PROVISION` once at startup.
///
/// The whole type compiles to nothing on a real device.
enum Provisioning {
    struct Payload: Decodable {
        var paperToken: String?
        var liveToken: String?
        var environment: String?
        var signalsURL: String?
        var signalsKey: String?
    }

    /// Last summary, for the UI to acknowledge what arrived.
    nonisolated(unsafe) static var lastSummary: String?

    /// Applies whatever the launch environment carries. Call BEFORE the app
    /// model reads the Keychain. Returns a human-readable summary or nil.
    @discardableResult
    static func applyFromEnvironmentIfPresent() -> String? {
        #if targetEnvironment(simulator)
        guard let raw = ProcessInfo.processInfo.environment["PA_PROVISION"], !raw.isEmpty else { return nil }
        guard let data = Data(base64Encoded: raw),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            lastSummary = "Provisioning data from the Mac could not be read."
            return lastSummary
        }
        var applied: [String] = []
        if let t = payload.paperToken, TokenStore.save(t, for: .paper) { applied.append("paper token") }
        if let t = payload.liveToken, TokenStore.save(t, for: .live) { applied.append("live token") }
        if let e = payload.environment, let env = AlpacaEnvironment(rawValue: e.lowercased()) {
            TokenStore.environment = env
            applied.append("environment \(env.label)")
        }
        if let u = payload.signalsURL, let url = URL(string: u.trimmingCharacters(in: .whitespacesAndNewlines)) {
            TokenStore.signalsEndpoint = url
            applied.append("signals URL")
        }
        if let k = payload.signalsKey, TokenStore.saveSignalsKey(k) { applied.append("signals key") }
        lastSummary = applied.isEmpty ? "Provisioning data from the Mac contained nothing usable."
                                      : "Provisioned from the Mac: " + applied.joined(separator: ", ") + "."
        print(lastSummary!)   // shows in `xcrun simctl launch --console` and Xcode's console
        return lastSummary
        #else
        return nil
        #endif
    }
}
