import Foundation
import LurkerKit
import Observation

/// Owns the share list and the polling loop, and builds a `Client` from
/// whatever `SettingsStore` currently holds. One instance, created in
/// `LurkerApp` and passed down via `.environment`.
@Observable
@MainActor
final class AppState {
    private(set) var shares: [Share] = []
    private(set) var isLoading = false
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

    /// `GET /v1/shares`. Schedules another refresh in 5 s while any share is
    /// still `new` or `drafting` (SPEC.md); stops once none are.
    func refresh() async {
        guard let client = makeClient() else {
            pollTask?.cancel()
            pollTask = nil
            errorMessage = "Add your server in Settings first."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            shares = try await client.shares()
            errorMessage = nil
        } catch {
            errorMessage = message(for: error)
        }

        let hasPending = shares.contains { $0.status == .new || $0.status == .drafting }
        if hasPending {
            schedulePoll()
        } else {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func setStatus(_ id: String, to status: ShareStatus) async {
        guard let client = makeClient() else { return }
        do {
            try await client.updateStatus(id: id, status: status)
            await refresh()
        } catch {
            errorMessage = message(for: error)
        }
    }

    func delete(_ id: String) async {
        guard let client = makeClient() else { return }
        do {
            try await client.deleteShare(id: id)
            shares.removeAll { $0.id == id }
        } catch {
            errorMessage = message(for: error)
        }
    }

    private func schedulePoll() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled else { return }
            await self.refresh()
        }
    }

    private func message(for error: Error) -> String {
        (error as? APIError)?.message ?? error.localizedDescription
    }
}
