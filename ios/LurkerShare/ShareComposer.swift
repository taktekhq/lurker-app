import Foundation
import LurkerKit
import UniformTypeIdentifiers

/// One image the extension pulled from the share sheet, already resized and
/// re-encoded (SPEC.md: 1600 px long edge, JPEG quality 0.8 -- re-encoding
/// drops EXIF, GPS included). `jpeg` is exactly what gets POSTed.
struct SharedPhoto: Identifiable {
    let id = UUID()
    let jpeg: Data
}

/// Drives the whole share-extension flow: loads the shared images, lets the
/// maker add a note, sends, and reports back what happened. Owns no UIKit
/// or `NSExtensionContext` -- `ShareViewController` is the only thing that
/// talks to the extension context itself.
@MainActor
final class ShareComposer: ObservableObject {
    enum State: Equatable {
        case loading
        case notConfigured
        case ready
        case sending
        case sent
        case failed(String)
    }

    @Published private(set) var photos: [SharedPhoto] = []
    @Published var note = ""
    @Published private(set) var state: State = .loading

    private let settings: SettingsStore

    init(settings: SettingsStore = KeychainSettingsStore()) {
        self.settings = settings
    }

    /// Reads every image attachment out of the share sheet's items, up to
    /// 10 (SPEC.md), resizing each as it is read so the extension's tight
    /// memory limit never has to hold more than one full-size photo at a
    /// time.
    func load(from items: [NSExtensionItem]) async {
        guard settings.isConfigured else {
            state = .notConfigured
            return
        }

        var loaded: [SharedPhoto] = []
        outer: for item in items {
            for provider in item.attachments ?? [] {
                guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { continue }
                guard let raw = try? await Self.loadImageData(provider) else { continue }
                guard let prepared = try? ImagePrep.prepare(raw) else { continue }
                loaded.append(SharedPhoto(jpeg: prepared))
                if loaded.count >= 10 { break outer }
            }
        }

        photos = loaded
        state = loaded.isEmpty ? .failed("Could not read any photos from this share.") : .ready
    }

    /// `POST /v1/shares`. On success moves to `.sent`, which the view turns
    /// into the extension closing itself.
    @discardableResult
    func send() async -> Bool {
        guard let base = settings.serverURL(), let token = settings.token() else {
            state = .notConfigured
            return false
        }
        guard !photos.isEmpty else {
            state = .failed("Nothing to send.")
            return false
        }

        state = .sending
        let client = Client(base: base, token: token)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            _ = try await client.createShare(
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                photos: photos.map(\.jpeg)
            )
            state = .sent
            return true
        } catch let error as APIError {
            state = .failed(error.message)
            return false
        } catch {
            state = .failed(error.localizedDescription)
            return false
        }
    }

    private static func loadImageData(_ provider: NSItemProvider) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: ImagePrepError.decodeFailed)
                }
            }
        }
    }
}
