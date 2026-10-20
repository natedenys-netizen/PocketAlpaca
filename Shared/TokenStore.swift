import Foundation
import Security

/// OAuth access tokens live ONLY in the iPhone Keychain, one per environment
/// (a paper token is useless against the live API and vice versa). The chosen
/// environment is not secret and lives in UserDefaults.
enum TokenStore {
    private static let service = "com.natedenys.PocketAlpaca"
    private static let legacyAccount = "alpaca-oauth-token"   // v1 stored a single token here
    private static let envKey = "alpaca-environment"

    /// App group shared by the app and its widget. Used both as the Keychain
    /// access group (so the widget can read the token) and as the UserDefaults
    /// suite (so both agree on paper vs live).
    static let appGroup = "group.com.natedenys.PocketAlpaca"
    private static let sharedDefaults = UserDefaults(suiteName: appGroup) ?? .standard

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

    // Items are stored in the shared access group. If that is unavailable (no
    // app-group entitlement, e.g. a stripped build), fall back to the app's own
    // keychain so the app still works alone. Reads try the shared group first,
    // then the private one, and promote what they find.
    private static func baseQuery(account: String, shared: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if shared { q[kSecAttrAccessGroup as String] = appGroup }
        return q
    }

    private static func read(account: String) -> String? {
        if let v = read(account: account, shared: true) { return v }
        if let v = read(account: account, shared: false) {
            if write(v, account: account, shared: true) { remove(account: account, shared: false) }
            return v
        }
        return nil
    }

    private static func read(account: String, shared: Bool) -> String? {
        var query = baseQuery(account: account, shared: shared)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String, account: String) -> Bool {
        write(value, account: account, shared: true) || write(value, account: account, shared: false)
    }

    private static func write(_ value: String, account: String, shared: Bool) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        remove(account: account, shared: shared)
        var attrs = baseQuery(account: account, shared: shared)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attrs[kSecValueData as String] = data
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    private static func remove(account: String) {
        remove(account: account, shared: true)
        remove(account: account, shared: false)
    }

    private static func remove(account: String, shared: Bool) {
        SecItemDelete(baseQuery(account: account, shared: shared) as CFDictionary)
    }

    static var environment: AlpacaEnvironment {
        get {
            if let raw = sharedDefaults.string(forKey: envKey), let env = AlpacaEnvironment(rawValue: raw) { return env }
            // Migrate the v1 setting from the app's private defaults.
            if let raw = UserDefaults.standard.string(forKey: envKey), let env = AlpacaEnvironment(rawValue: raw) {
                sharedDefaults.set(raw, forKey: envKey)
                return env
            }
            return .paper
        }
        set { sharedDefaults.set(newValue.rawValue, forKey: envKey) }
    }
}
