import LurkerKit
import SwiftUI

struct SharesListView: View {
    @Environment(AppState.self) private var appState
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.shares.isEmpty && !appState.isLoading {
                    ContentUnavailableView(
                        "No shares yet",
                        systemImage: "photo.on.rectangle",
                        description: Text(
                            appState.isConfigured
                                ? "Share photos from your Photos app to see them here."
                                : "Add your server in Settings to get started."
                        )
                    )
                } else {
                    List(appState.shares) { share in
                        ShareRowView(share: share)
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Lurker")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .refreshable { await appState.refresh() }
            .task { await appState.refresh() }
            .onDisappear { appState.stopPolling() }
            .sheet(isPresented: $showSettings) {
                SettingsView()
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
