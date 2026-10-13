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
    @State private var openedWithCopy = false

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
        VStack(alignment: .leading, spacing: 6) {
            if openedWithCopy {
                Label(item.queue == .comment ? "Reply copied. Paste it in the reply box." : "Text copied, in case a field comes up empty.",
                      systemImage: "doc.on.clipboard")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            buttons
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button {
                openLink()
            } label: {
                Label("Open", systemImage: "safari")
            }
            .disabled(openPlan == nil)

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

    /// Open fills in what the site allows and puts the rest on the clipboard
    /// (see OpenPlan in LurkerKit).
    private var openPlan: OpenPlan? { OpenPlan.make(for: item) }

    private func openLink() {
        guard let plan = openPlan else { return }
        if let text = plan.clipboard {
            UIPasteboard.general.string = text
            openedWithCopy = true
            Task {
                try? await Task.sleep(for: .seconds(4))
                openedWithCopy = false
            }
        }
        UIApplication.shared.open(plan.url)
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
