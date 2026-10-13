import Foundation

/// One case per `Client` call. Each case knows its own method and path --
/// `Client` attaches auth and the body. Paths and methods follow SPEC.md's
/// route table exactly.
enum Endpoint {
    case shares
    case createShare(note: String?, photos: [Data])
    case updateStatus(id: String, status: ShareStatus)
    case deleteShare(id: String)
    case photo(key: String)
    case queues
    case itemDone(id: String, link: String?)
    case itemSkip(id: String, reason: SkipReason, note: String?)
    case itemLink(id: String, link: String)
    case growth
}

extension Endpoint {
    var method: String {
        switch self {
        case .shares, .photo, .queues, .growth:
            return "GET"
        case .createShare, .updateStatus, .itemDone, .itemSkip, .itemLink:
            return "POST"
        case .deleteShare:
            return "DELETE"
        }
    }

    var path: String {
        switch self {
        case .shares, .createShare:
            return "/v1/shares"
        case .updateStatus(let id, _):
            return "/v1/shares/\(id)/status"
        case .deleteShare(let id):
            return "/v1/shares/\(id)"
        case .photo(let key):
            return "/v1/photos/\(key)"
        case .queues:
            return "/v1/queues"
        case .itemDone(let id, _):
            return "/v1/items/\(id)/done"
        case .itemSkip(let id, _, _):
            return "/v1/items/\(id)/skip"
        case .itemLink(let id, _):
            return "/v1/items/\(id)/link"
        case .growth:
            return "/v1/growth"
        }
    }
}

/// The lurker worker's API client (SPEC.md). Holds only the base URL, bearer
/// token and transport, nothing mutable, so both the app and the share
/// extension build a fresh one from whatever `SettingsStore` currently
/// holds, every time they need one.
public final class Client: Sendable {
    private let base: URL
    private let token: String
    private let transport: Transport

    public init(base: URL, token: String, transport: Transport = URLSessionTransport()) {
        self.base = base
        self.token = token
        self.transport = transport
    }

    /// `GET /v1/shares`: newest first, up to 100 (SPEC.md).
    public func shares() async throws -> [Share] {
        struct Response: Decodable { let shares: [Share] }
        let data = try await send(.shares)
        return try JSONDecoder().decode(Response.self, from: data).shares
    }

    /// `POST /v1/shares`: multipart, 1 to 10 photos plus an optional note.
    /// Returns the new share's id. Used by the share extension, not the
    /// main app.
    public func createShare(note: String?, photos: [Data]) async throws -> String {
        struct Response: Decodable { let id: String }
        let data = try await send(.createShare(note: note, photos: photos))
        return try JSONDecoder().decode(Response.self, from: data).id
    }

    /// `POST /v1/shares/:id/status`.
    public func updateStatus(id: String, status: ShareStatus) async throws {
        _ = try await send(.updateStatus(id: id, status: status))
    }

    /// `DELETE /v1/shares/:id`.
    public func deleteShare(id: String) async throws {
        _ = try await send(.deleteShare(id: id))
    }

    /// `GET /v1/photos/:key`: the raw JPEG bytes.
    public func photo(key: String) async throws -> Data {
        try await send(.photo(key: key))
    }

    /// `GET /v1/queues` (SPEC-v2.md).
    public func queues() async throws -> QueuesResponse {
        let data = try await send(.queues)
        return try JSONDecoder().decode(QueuesResponse.self, from: data)
    }

    /// `POST /v1/items/:id/done`. An empty or missing `link` asks the engine
    /// to find it later (SPEC-v2.md).
    public func itemDone(id: String, link: String?) async throws {
        _ = try await send(.itemDone(id: id, link: link))
    }

    /// `POST /v1/items/:id/skip`.
    public func itemSkip(id: String, reason: SkipReason, note: String?) async throws {
        _ = try await send(.itemSkip(id: id, reason: reason, note: note))
    }

    /// `POST /v1/items/:id/link`: add or fix the link on a done item.
    public func itemLink(id: String, link: String) async throws {
        _ = try await send(.itemLink(id: id, link: link))
    }

    /// `GET /v1/growth` (SPEC-v2.md).
    public func growth() async throws -> Growth {
        let data = try await send(.growth)
        return try JSONDecoder().decode(Growth.self, from: data)
    }

    private func resolve(_ path: String) -> URL {
        let baseString = base.absoluteString
        let trimmedBase = baseString.hasSuffix("/") ? String(baseString.dropLast()) : baseString
        let trimmedPath = path.hasPrefix("/") ? path : "/\(path)"
        return URL(string: trimmedBase + trimmedPath) ?? base
    }

    private func send(_ endpoint: Endpoint) async throws -> Data {
        var request = URLRequest(url: resolve(endpoint.path))
        request.httpMethod = endpoint.method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        switch endpoint {
        case .createShare(let note, let photos):
            let multipart = Multipart()
            request.setValue(multipart.contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = multipart.body(note: note, photos: photos)
        case .updateStatus(_, let status):
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["status": status.rawValue])
        case .itemDone(_, let link):
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var body: [String: String] = [:]
            if let link, !link.isEmpty { body["link"] = link }
            request.httpBody = try JSONEncoder().encode(body)
        case .itemSkip(_, let reason, let note):
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            struct SkipBody: Encodable { let reason: String; let note: String? }
            let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            request.httpBody = try JSONEncoder().encode(
                SkipBody(reason: reason.rawValue, note: (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote)
            )
        case .itemLink(_, let link):
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["link": link])
        case .shares, .deleteShare, .photo, .queues, .growth:
            break
        }

        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.decode(status: response.statusCode, data: data)
        }
        return data
    }
}
