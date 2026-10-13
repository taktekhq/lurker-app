import Foundation
import Security

/// `SettingsStore` backed by the Keychain, in the `group.io.taktek.lurker`
/// App Group's shared keychain (set as a `com.apple.security.application-groups`
/// entitlement on both the app and the share extension) so the extension
/// reads what the app saved in Settings, with no App Group file I/O and no
/// Team ID needed at build time. Two generic-password items, service
/// `io.taktek.lurker.settings`, accounts `serverURL` and `token`.
public final class KeychainSettingsStore: SettingsStore {
    /// The App Group identifier itself, used directly as `kSecAttrAccessGroup`:
    /// since iOS 13, an app and its extensions can share keychain items this
    /// way with no separate Keychain Sharing capability or `$(AppIdentifierPrefix)`
    /// substitution needed. Both targets' entitlements also list a
    /// `keychain-access-groups` array for forward compatibility, but this is
    /// what the code actually reads and writes through.
    public static let defaultAccessGroup = "group.io.taktek.lurker"

    private let service = "io.taktek.lurker.settings"
    private let accessGroup: String

    public init(accessGroup: String = KeychainSettingsStore.defaultAccessGroup) {
        self.accessGroup = accessGroup
    }

    public func serverURL() -> URL? {
        guard let value = read(account: "serverURL") else { return nil }
        return URL(string: value)
    }

    public func token() -> String? {
        read(account: "token")
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
