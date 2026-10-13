import LurkerKit
import SwiftUI
import UIKit

struct DraftCardView: View {
    let draft: Draft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("r/\(draft.sub)")
                .font(.headline)

            Text(draft.title)
                .font(.body.weight(.medium))

            if !draft.body.isEmpty {
                Text(draft.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Text(draft.why)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let notes = draft.ruleNotes, !notes.isEmpty {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !draft.rulesChecked {
                Label("Rules not checked", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                Button("Copy title") {
                    UIPasteboard.general.string = draft.title
                }
                if !draft.body.isEmpty {
                    Button("Copy body") {
                        UIPasteboard.general.string = draft.body
                    }
                }
            }
            .font(.subheadline)
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
