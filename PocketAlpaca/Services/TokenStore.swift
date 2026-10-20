import Foundation
import Security

/// OAuth access tokens live ONLY in the iPhone Keychain, one per environment
/// (a paper token is useless against the live API and vice versa). The chosen
/// environment is not secret and lives in UserDefaults.
enum TokenStore {
    private static let service = "com.natedenys.PocketAlpaca"
    private static let legacyAccount = "alpaca-oauth-token"   // v1 stored a single token here
    private static let envKey = "alpaca-environment"

    private static func account(for env: AlpacaEnvironment) -> String { "alpaca-oauth-token-\(env.rawValue)" }

    static func load(for env: AlpacaEnvironment) -> String? {
        if let t = read(account: account(for: env)) { return t }
        // One-time migration: a token saved by v1 belongs to whichever
        // environment was selected at the time; adopt it for the current one.
        if env == environment, let legacy = read(account: legacyAccount) {
            if write(legacy, account: account(for: env)) { remove(account: legacyAccount) }
            return legacy
        }
        return nil
    }

    @discardableResult
    static func save(_ token: String, for env: AlpacaEnvironment) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return write(trimmed, account: account(for: env))
    }

    static func delete(for env: AlpacaEnvironment) { remove(account: account(for: env)) }

    // MARK: - Keychain primitives

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        remove(account: account)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    private static func remove(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static var environment: AlpacaEnvironment {
        get { AlpacaEnvironment(rawValue: UserDefaults.standard.string(forKey: envKey) ?? "") ?? .paper }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: envKey) }
    }
}
