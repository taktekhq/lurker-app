import LurkerKit
import Testing

/// Placeholder app-level test target (XcodeGen scaffold). Real logic lives
/// in LurkerKit and is tested with `swift test --package-path ios/LurkerKit`;
/// this just confirms the app target can see LurkerKit's public API.
@Test("LurkerKit's ShareStatus is visible from the app target")
func lurkerKitIsLinked() {
    #expect(ShareStatus.new.rawValue == "new")
}
