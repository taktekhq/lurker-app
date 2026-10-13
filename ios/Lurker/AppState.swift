import Foundation
import LurkerKit
import Observation

/// Owns the four queues and the growth dashboard, and builds a `Client`
/// from whatever `SettingsStore` currently holds (SPEC-v2.md). One
/// instance, created in `LurkerApp` and passed down via `.environment`.
@Observable
@MainActor
final class AppState {
    private(set) var queues: QueuesResponse?
    private(set) var growth: Growth?
    private(set) var isLoading = false
    private(set) var isLoadingGrowth = false
    var errorMessage: String?

    let settings: SettingsStore
    let photos = PhotoLoader()

    private var pollTask: Task<Void, Never>?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var isConfigured: Bool {
        settings.isConfigured
    }

    func makeClient() -> Client? {
        guard settings.isConfigured, let base = settings.serverURL(), let token = settings.token() else {
            return nil
        }
        return Client(base: base, token: token)
    }

    /// `GET /v1/queues`. Reschedules itself every 60 s while the app is
    /// open (SPEC-v2.md); every item action calls this again right after,
    /// which also resets that 60 s clock.
    func refresh() async {
        guard let client = makeClient() else {
            pollTask?.cancel()
            pollTask = nil
            errorMessage = "Add your server from the profile screen first."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            queues = try await client.queues()
            errorMessage = nil
        } catch {
            errorMessage = message(for: error)
        }

        schedulePoll()
    }

    /// `GET /v1/growth`, loaded lazily when the profile screen opens.
    func refreshGrowth() async {
        guard let client = makeClient() else { return }
        isLoadingGrowth = true
        defer { isLoadingGrowth = false }
        do {
            growth = try await client.growth()
        } catch {
            errorMessage = message(for: error)
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// `POST /v1/items/:id/done`.
    func markDone(_ id: String, link: String?) async {
        guard let client = makeClient() else { return }
        do {
            try await client.itemDone(id: id, link: link)
            await refresh()
        } catch {
            errorMessage = message(for: error)
        }
    }

    /// `POST /v1/items/:id/skip`.
    func skip(_ id: String, reason: SkipReason, note: String?) async {
        guard let client = makeClient() else { return }
        do {
            try await client.itemSkip(id: id, reason: reason, note: note)
            await refresh()
        } catch {
            errorMessage = message(for: error)
        }
    }

    private func schedulePoll() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self, !Task.isCancelled else { return }
            await self.refresh()
        }
    }

    private func message(for error: Error) -> String {
        (error as? APIError)?.message ?? error.localizedDescription
    }
}
