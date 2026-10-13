import Foundation

/// Builds a `multipart/form-data` body for `POST /v1/shares` (SPEC.md): one
/// optional `note` text field, then one repeated `photo` file field per
/// image. Stateless beyond the boundary string, so a fresh `Multipart` per
/// request is cheap and never reused by accident across requests.
public struct Multipart: Sendable {
    public let boundary: String

    public init(boundary: String = UUID().uuidString) {
        self.boundary = boundary
    }

    public var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    /// `note` is skipped entirely when `nil` or empty: the worker treats a
    /// missing `note` field the same as an empty one (SPEC.md).
    public func body(note: String?, photos: [Data]) -> Data {
        var data = Data()

        if let note, !note.isEmpty {
            appendField(&data, name: "note", value: note)
        }
        for (index, photo) in photos.enumerated() {
            appendFile(&data, name: "photo", filename: "photo\(index + 1).jpg", contentType: "image/jpeg", contents: photo)
        }
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return data
    }

    private func appendField(_ data: inout Data, name: String, value: String) {
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        data.append(value.data(using: .utf8)!)
        data.append("\r\n".data(using: .utf8)!)
    }

    private func appendFile(_ data: inout Data, name: String, filename: String, contentType: String, contents: Data) {
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
                .data(using: .utf8)!
        )
        data.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        data.append(contents)
        data.append("\r\n".data(using: .utf8)!)
    }
}
