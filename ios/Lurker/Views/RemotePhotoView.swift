import LurkerKit
import SwiftUI
import UIKit

/// Loads one share's photo from `GET /v1/photos/:key` through `AppState`'s
/// shared `PhotoLoader` (`AsyncImage` can't send the bearer token this needs).
struct RemotePhotoView: View {
    let key: String

    @Environment(AppState.self) private var appState
    @State private var image: Image?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else if failed {
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .frame(width: 120, height: 120)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: key) {
            guard image == nil, let client = appState.makeClient() else { return }
            do {
                let data = try await appState.photos.data(for: key, using: client)
                if let uiImage = UIImage(data: data) {
                    image = Image(uiImage: uiImage)
                } else {
                    failed = true
                }
            } catch {
                failed = true
            }
        }
    }
}
