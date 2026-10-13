import Foundation

/// Where the app and the share extension get the worker's base URL and
/// bearer token (SPEC.md): set once in the app's Settings screen, read by
/// both sides through the shared keychain access group, so the extension
/// sees whatever the app last saved without needing the app to be running.
public protocol SettingsStore: Sendable {
    func serverURL() -> URL?
    func token() -> String?
    func set(serverURL: URL?, token: String?)
}

public extension SettingsStore {
    /// `true` once both a server URL and a non-empty token are saved. The
    /// share extension checks this before showing its compose UI: when
    /// `false`, SPEC.md asks for "Open Lurker and add your server first."
    var isConfigured: Bool {
        guard let token = token(), !token.isEmpty else { return false }
        return serverURL() != nil
    }
}
