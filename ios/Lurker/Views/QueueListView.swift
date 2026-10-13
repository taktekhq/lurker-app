import LurkerKit
import SwiftUI

/// One platform's tab: a post queue section and a comment queue section,
/// each headed by `done_today / target` (SPEC-v2.md).
struct QueueListView: View {
    let platform: Platform

    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let queues = appState.queues {
                List {
                    QueueSectionView(title: "Post queue", queue: queues.queue(platform, .post))
                    QueueSectionView(title: "Comment queue", queue: queues.queue(platform, .comment))
                }
                .listStyle(.insetGrouped)
            } else if appState.isLoading {
                ProgressView()
            } else {
                ContentUnavailableView(
                    "Not connected",
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    description: Text(
                        appState.isConfigured
                            ? "Pull to refresh."
                            : "Add your server from the profile screen to get started."
                    )
                )
            }
        }
        .refreshable { await appState.refresh() }
    }
}

private struct QueueSectionView: View {
    let title: String
    let queue: Queue

    var body: some View {
        Section {
            if queue.open.isEmpty {
                Text("Nothing waiting right now.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(queue.open) { item in
                    ItemCardView(item: item)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                Text("\(queue.doneToday)/\(queue.target)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
