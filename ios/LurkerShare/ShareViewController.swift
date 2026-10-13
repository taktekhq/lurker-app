import SwiftUI
import UIKit

/// The share extension's entry point (`NSExtensionPrincipalClass` in
/// LurkerShare/Info.plist, set via project.yml). Pulls the shared items off
/// `extensionContext`, hands them to `ShareComposer`, and hosts
/// `ShareComposerView` as the extension's whole UI.
final class ShareViewController: UIViewController {
    private let composer = ShareComposer()

    override func viewDidLoad() {
        super.viewDidLoad()

        let composerView = ShareComposerView(
            composer: composer,
            onFinish: { [weak self] in self?.finish() },
            onCancel: { [weak self] in self?.cancel() }
        )
        let hosting = UIHostingController(rootView: composerView)
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        Task { await composer.load(from: items) }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func cancel() {
        let error = NSError(
            domain: "io.taktek.lurker.share",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Cancelled"]
        )
        extensionContext?.cancelRequest(withError: error)
    }
}
