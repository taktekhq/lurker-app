import LurkerKit
import SwiftUI

@main
struct LurkerApp: App {
    @State private var appState: AppState

    init() {
        _appState = State(initialValue: AppState(settings: KeychainSettingsStore()))
    }

    var body: some Scene {
        WindowGroup {
            SharesListView()
                .environment(appState)
        }
    }
}
