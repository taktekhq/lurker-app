import Foundation
import Security

/// `SettingsStore` backed by the Keychain, in a keychain access group shared by
/// the app and the share extension (`keychain-access-groups` entitlement on
/// both), so the extension reads what the app saved in Settings. Two
/// generic-password items, service `io.taktek.lurker.settings`, accounts
/// `serverURL` and `token`.
public final class KeychainSettingsStore: SettingsStore {
    /// `<team prefix>io.taktek.lurker.shared`, matching the entitlements. The
    /// prefix comes from the `AppIdentifierPrefix` Info.plist key, which the
    /// build fills from the signing team, so no team id lives in the code.
    /// Keychain groups need no registration with Apple, unlike App Groups.
    public static var defaultAccessGroup: String {
        let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String ?? ""
        return prefix + "io.taktek.lurker.shared"
    }

    private let service = "io.taktek.lurker.settings"
    private let accessGroup: String

    public init(accessGroup: String = KeychainSettingsStore.defaultAccessGroup) {
        self.accessGroup = accessGroup
    }

    /// What Settings saved wins; otherwise the values built into this copy of the
    /// app (LURKER_SERVER / LURKER_TOKEN, see README), so a personal build works
    /// the moment it opens.
    public func serverURL() -> URL? {
        guard let value = read(account: "serverURL") ?? Self.bundled("LurkerServer") else { return nil }
        return URL(string: value)
    }

    public func token() -> String? {
        read(account: "token") ?? Self.bundled("LurkerToken")
    }

    static func bundled(_ key: String) -> String? {
        guard let v = Bundle.main.object(forInfoDictionaryKey: key) as? String, !v.isEmpty else { return nil }
        return v
    }

    public func set(serverURL: URL?, token: String?) {
        write(account: "serverURL", value: serverURL?.absoluteString)
        write(account: "token", value: token)
    }

    private func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func write(account: String, value: String?) {
        guard let value, !value.isEmpty else {
            SecItemDelete(baseQuery(account: account) as CFDictionary)
            return
        }

        let data = Data(value.utf8)
        var addQuery = baseQuery(account: account)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        // A failure other than "already exists" (e.g. a locked Keychain) has
        // no error channel to report through here; Settings' Test button is
        // how a maker finds out the save didn't take.
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemUpdate(baseQuery(account: account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup
        ]
    }
}
