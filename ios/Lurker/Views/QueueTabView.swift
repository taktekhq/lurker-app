import LurkerKit
import SwiftUI

/// The app's root: two tabs, Reddit and HN (SPEC-v2.md), a shared toolbar
/// with the profile button that opens the growth dashboard, and the one
/// place `AppState` is asked to refresh and keep polling.
struct QueueTabView: View {
    @Environment(AppState.self) private var appState
    @State private var selection: Platform = .reddit
    @State private var showGrowth = false

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                QueueListView(platform: .reddit)
                    .tag(Platform.reddit)
                    .tabItem { Label("Reddit", systemImage: "bubble.left.and.bubble.right.fill") }

                QueueListView(platform: .hn)
                    .tag(Platform.hn)
                    .tabItem { Label("Hacker News", systemImage: "flame.fill") }
            }
            .navigationTitle(selection == .reddit ? "Reddit" : "Hacker News")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showGrowth = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Profile")
                }
            }
            .task { await appState.refresh() }
            .onDisappear { appState.stopPolling() }
            .sheet(isPresented: $showGrowth) {
                GrowthView()
            }
            .alert("Could not refresh", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(appState.errorMessage ?? "")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { appState.errorMessage != nil },
            set: { shown in if !shown { appState.errorMessage = nil } }
        )
    }
}
