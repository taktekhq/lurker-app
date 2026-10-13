import LurkerKit
import SwiftUI

/// `POST /v1/items/:id/skip` (SPEC-v2.md): "It's bad" (the engine learns
/// from it) or "Not now" (fine, just not today), with an optional note.
struct SkipSheetView: View {
    let item: QueueItem

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var reason: SkipReason = .later
    @State private var note = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reason", selection: $reason) {
                        Text("It's bad").tag(SkipReason.bad)
                        Text("Not now").tag(SkipReason.later)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Note (optional)") {
                    TextField("What's off about it?", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Skip")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Skip") { skip() }
                        .disabled(isSaving)
                }
            }
        }
    }

    private func skip() {
        isSaving = true
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await appState.skip(item.id, reason: reason, note: trimmed.isEmpty ? nil : trimmed)
            isSaving = false
            dismiss()
        }
    }
}
