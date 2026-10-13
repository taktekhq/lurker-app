import Foundation

/// A one-tap setup link: `lurker://setup?server=<https url>&token=<app token>`.
/// Opening it saves both values, so nobody has to type a long token on a phone.
public enum SetupLink {
    public static func parse(_ url: URL) -> (server: URL, token: String)? {
        guard url.scheme == "lurker", url.host == "setup",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "server" })?.value,
              let server = URL(string: raw), server.scheme == "https", server.host != nil,
              let token = items.first(where: { $0.name == "token" })?.value, !token.isEmpty
        else { return nil }
        return (server, token)
    }
}
