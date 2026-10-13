import Foundation

/// Any non-2xx response from the worker (SPEC.md). The worker's exact error
/// body shape isn't pinned down beyond "JSON with an error message", so this
/// decodes `{"error": "..."}` when it can and falls back to the raw body
/// text, then to a generic message, rather than failing to report the
/// failure at all.
public struct APIError: Error, Equatable, Sendable {
    public let status: Int
    public let message: String

    public init(status: Int, message: String) {
        self.status = status
        self.message = message
    }
}

extension APIError {
    private struct Body: Decodable {
        let error: String
    }

    static func decode(status: Int, data: Data) -> APIError {
        if let body = try? JSONDecoder().decode(Body.self, from: data) {
            return APIError(status: status, message: body.error)
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return APIError(status: status, message: text)
        }
        return APIError(status: status, message: "Server error (\(status)).")
    }
}

extension APIError: LocalizedError {
    public var errorDescription: String? { message }
}
