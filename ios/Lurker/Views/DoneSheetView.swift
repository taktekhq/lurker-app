import LurkerKit
import SwiftUI

/// `POST /v1/items/:id/done` (SPEC-v2.md): an optional link, left empty to
/// let the engine go find it later.
struct DoneSheetView: View {
    let item: QueueItem

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Link", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Leave it empty and Lurker will find it.")
                }
            }
            .navigationTitle("Done")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await appState.markDone(item.id, link: trimmed.isEmpty ? nil : trimmed)
            isSaving = false
            dismiss()
        }
    }
}
