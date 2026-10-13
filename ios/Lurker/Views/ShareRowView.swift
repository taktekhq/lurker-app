import LurkerKit
import SwiftUI

struct ShareRowView: View {
    let share: Share

    @Environment(AppState.self) private var appState
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !share.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(share.photos, id: \.self) { key in
                            RemotePhotoView(key: key)
                        }
                    }
                }
            }

            if let note = share.note, !note.isEmpty {
                Text(note)
                    .font(.body)
            }

            StatusPill(status: share.status)

            if share.status == .failed, let error = share.error, !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            ForEach(Array(share.drafts.enumerated()), id: \.offset) { _, draft in
                DraftCardView(draft: draft)
            }

            actions
        }
        .padding(.vertical, 8)
        .confirmationDialog("Delete this share?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await appState.delete(share.id) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 12) {
            if share.status == .drafted {
                Button("Posted") {
                    Task { await appState.setStatus(share.id, to: .posted) }
                }
                .buttonStyle(.borderedProminent)

                Button("Skip") {
                    Task { await appState.setStatus(share.id, to: .skipped) }
                }
                .buttonStyle(.bordered)
            }

            if share.status != .new, share.status != .drafting {
                Button("Redo") {
                    Task { await appState.setStatus(share.id, to: .new) }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
            }
        }
        .font(.subheadline)
    }
}

private struct StatusPill: View {
    let status: ShareStatus

    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        switch status {
        case .new: return "New"
        case .drafting: return "Drafting"
        case .drafted: return "Drafted"
        case .failed: return "Failed"
        case .posted: return "Posted"
        case .skipped: return "Skipped"
        }
    }

    private var color: Color {
        switch status {
        case .new, .drafting: return .orange
        case .drafted: return .blue
        case .failed: return .red
        case .posted: return .green
        case .skipped: return .gray
        }
    }
}
