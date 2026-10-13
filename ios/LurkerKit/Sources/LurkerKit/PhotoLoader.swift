import Foundation

/// Loads and caches photo bytes from `GET /v1/photos/:key` (SPEC.md), which
/// needs the bearer token -- `AsyncImage` can't send one, so every photo
/// shown in the app or the share extension goes through this instead. An
/// actor: several share cards can be loading thumbnails concurrently.
public actor PhotoLoader {
    private var cache: [String: Data] = [:]

    public init() {}

    public func data(for key: String, using client: Client) async throws -> Data {
        if let cached = cache[key] {
            return cached
        }
        let data = try await client.photo(key: key)
        cache[key] = data
        return data
    }
}
