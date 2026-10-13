import LurkerKit
import SwiftUI
import UIKit

/// One queue item (SPEC-v2.md): title, target, why, the draft text, a
/// source label, and the four actions. Photo items (source `"photo"`) show
/// their thumbnails, same as the old share cards did.
struct ItemCardView: View {
    let item: QueueItem

    @Environment(AppState.self) private var appState
    @State private var showDone = false
    @State private var showSkip = false
    @State private var justCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !item.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(item.photos, id: \.self) { key in
                            RemotePhotoView(key: key)
                        }
                    }
                }
            }

            if let target = item.target, !target.isEmpty {
                Text(item.platform == .reddit ? "r/\(target)" : target)
                    .font(.headline)
            }

            if let title = item.title, !title.isEmpty {
                Text(title)
                    .font(.body.weight(.medium))
            }

            if let body = item.body, !body.isEmpty {
                Text(body)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if let why = item.why, !why.isEmpty {
                Text(why)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let source = item.source {
                Text(sourceLabel(source))
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }

            actions
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showDone) {
            DoneSheetView(item: item)
        }
        .sheet(isPresented: $showSkip) {
            SkipSheetView(item: item)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                openLink()
            } label: {
                Label("Open", systemImage: "safari")
            }
            .disabled(openTarget == nil)

            Button {
                UIPasteboard.general.string = item.draftText
                justCopied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    justCopied = false
                }
            } label: {
                Label(justCopied ? "Copied" : "Copy", systemImage: justCopied ? "checkmark" : "doc.on.doc")
            }
            .disabled(item.draftText.isEmpty)

            Button {
                showDone = true
            } label: {
                Label("Done", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive) {
                showSkip = true
            } label: {
                Label("Skip", systemImage: "xmark.circle")
            }
        }
        .font(.subheadline)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .labelStyle(.titleOnly)
    }

    /// `url` is the thread to answer or the submit page (SPEC-v2.md); when
    /// the engine hasn't filled it in, fall back to a sensible default so
    /// Open still goes somewhere useful.
    private var openTarget: URL? {
        if let url = item.url, let parsed = URL(string: url) {
            return parsed
        }
        return fallbackSubmitURL
    }

    private var fallbackSubmitURL: URL? {
        switch item.platform {
        case .reddit:
            if let target = item.target, !target.isEmpty {
                return URL(string: "https://www.reddit.com/r/\(target)/submit")
            }
            return URL(string: "https://www.reddit.com")
        case .hn:
            return URL(string: "https://news.ycombinator.com/submit")
        }
    }

    private func openLink() {
        guard let url = openTarget else { return }
        UIApplication.shared.open(url)
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "kbase": return "From your notes"
        case "work": return "From recent work"
        case "link": return "Worth sharing"
        case "thread": return "From a live thread"
        case "photo": return "From a photo"
        default: return source
        }
    }
}
