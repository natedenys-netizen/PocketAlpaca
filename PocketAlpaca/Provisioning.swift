import Foundation

#if targetEnvironment(simulator)
/// Simulator-only hand-off of settings from the Mac, so nothing has to be typed
/// into the simulator. `Scripts/simulator_provision.py` writes a 0600 JSON file
/// into this app's group container and brings the app to the front; the app
/// applies it, deletes it, and leaves a receipt the script waits for. Nothing
/// travels through the environment or the command line, so `ps` never sees it.
///
/// This whole type is replaced by an inert stub in device builds (see below).
enum Provisioning {
    struct Payload: Decodable {
        var nonce: String?
        var paperToken: String?
        var liveToken: String?
        var environment: String?
        var signalsURL: String?
        var signalsKey: String?
    }

    struct Receipt: Encodable {
        var nonce: String?
        var applied: [String]
        var error: String?
    }

    static let dropFileName = "pa_provision.json"
    static let receiptFileName = "pa_provision_receipt.json"

    /// Last summary, for the UI to acknowledge what arrived.
    nonisolated(unsafe) static var lastSummary: String?

    private static var groupURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TokenStore.appGroup)
    }

    /// True when a drop file is waiting (cheap: one stat).
    static var dropFileExists: Bool {
        guard let dir = groupURL else { return false }
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent(dropFileName).path)
    }

    /// Applies a waiting drop file, if any. Safe to call often. Returns a
    /// human-readable summary when something was processed, else nil.
    @discardableResult
    static func applyDropFileIfPresent() -> String? {
        guard let dir = groupURL else { return nil }
        let drop = dir.appendingPathComponent(dropFileName)
        guard FileManager.default.fileExists(atPath: drop.path) else { return nil }

        var applied: [String] = []
        var problems: [String] = []
        var nonce: String?

        do {
            let data = try Data(contentsOf: drop)
            let p = try JSONDecoder().decode(Payload.self, from: data)
            nonce = p.nonce

            if let t = p.paperToken {
                if TokenStore.save(t, for: .paper) { applied.append("paper token") } else { problems.append("paper token could not be saved") }
            }
            if let t = p.liveToken {
                if TokenStore.save(t, for: .live) { applied.append("live token") } else { problems.append("live token could not be saved") }
            }
            if let e = p.environment, let env = AlpacaEnvironment(rawValue: e.lowercased()) {
                // Never switch to an environment that has no token: that would
                // show sample data while the Terminal reports success.
                if TokenStore.load(for: env) != nil {
                    TokenStore.environment = env
                    applied.append("environment \(env.label)")
                } else {
                    problems.append("no \(env.label) token is stored, environment left as is")
                }
            }
            switch (p.signalsURL, p.signalsKey) {
            case let (u?, k?):
                let trimmed = u.trimmingCharacters(in: .whitespacesAndNewlines)
                if let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true, TokenStore.saveSignalsKey(k) {
                    TokenStore.signalsEndpoint = url
                    applied.append("signals URL and key")
                } else {
                    problems.append("signals URL or key was invalid, neither applied")
                }
            case (nil, nil):
                break
            default:
                problems.append("signals URL and key must arrive together, neither applied")
            }
        } catch {
            problems.append("file could not be read: \(error.localizedDescription)")
        }

        // Remove the drop file before writing the receipt, so a script that
        // sees the receipt can be sure the secrets are gone from disk.
        try? FileManager.default.removeItem(at: drop)
        let receipt = Receipt(nonce: nonce, applied: applied, error: problems.isEmpty ? nil : problems.joined(separator: "; "))
        if let data = try? JSONEncoder().encode(receipt) {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(receiptFileName).path,
                                           contents: data, attributes: [.posixPermissions: 0o600])
        }

        var summary = applied.isEmpty ? "Provisioning from the Mac applied nothing." : "Provisioned from the Mac: " + applied.joined(separator: ", ") + "."
        if !problems.isEmpty { summary += " Problems: " + problems.joined(separator: "; ") + "." }
        lastSummary = summary
        return summary
    }
}
#else
/// Device builds: provisioning does not exist.
enum Provisioning {
    static var lastSummary: String? { nil }
    static var dropFileExists: Bool { false }
    @discardableResult
    static func applyDropFileIfPresent() -> String? { nil }
}
#endif
