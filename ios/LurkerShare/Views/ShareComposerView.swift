import SwiftUI
import UIKit

struct ShareComposerView: View {
    @ObservedObject var composer: ShareComposer
    let onFinish: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Share to Lurker")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onCancel() }
                    }
                    if composer.state == .ready {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Send") { send() }
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch composer.state {
        case .loading:
            ProgressView("Reading photos...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .notConfigured:
            ContentUnavailableView(
                "No server set",
                systemImage: "gearshape",
                description: Text("Open Lurker and add your server first.")
            )

        case .failed(let message):
            ContentUnavailableView(
                "Could not send",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )

        case .sent:
            ContentUnavailableView(
                "Sent",
                systemImage: "checkmark.circle",
                description: Text("Lurker will draft posts for this.")
            )

        case .ready, .sending:
            form
        }
    }

    private var form: some View {
        Form {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(composer.photos) { photo in
                            thumbnail(photo)
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .padding(8)
            }

            Section("Note") {
                TextField("Say anything worth knowing (optional)", text: $composer.note, axis: .vertical)
                    .lineLimit(3...6)
            }

            if composer.state == .sending {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Sending...")
                    }
                }
            }
        }
    }

    private func thumbnail(_ photo: SharedPhoto) -> some View {
        Group {
            if let uiImage = UIImage(data: photo.jpeg) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary
            }
        }
        .frame(width: 90, height: 90)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func send() {
        Task {
            if await composer.send() {
                try? await Task.sleep(for: .seconds(1))
                onFinish()
            }
        }
    }
}
