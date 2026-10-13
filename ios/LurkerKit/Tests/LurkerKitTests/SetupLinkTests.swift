import Foundation
import Testing
@testable import LurkerKit

@Suite("SetupLink")
struct SetupLinkTests {
    @Test func parsesServerAndToken() throws {
        let url = URL(string: "lurker://setup?server=https%3A%2F%2Fx.workers.dev&token=abc123")!
        let got = try #require(SetupLink.parse(url))
        #expect(got.server.absoluteString == "https://x.workers.dev")
        #expect(got.token == "abc123")
    }

    @Test func rejectsPlainHTTPAndMissingParts() {
        #expect(SetupLink.parse(URL(string: "lurker://setup?server=http%3A%2F%2Fx.dev&token=a")!) == nil)
        #expect(SetupLink.parse(URL(string: "lurker://setup?server=https%3A%2F%2Fx.dev")!) == nil)
        #expect(SetupLink.parse(URL(string: "lurker://other?server=https%3A%2F%2Fx.dev&token=a")!) == nil)
        #expect(SetupLink.parse(URL(string: "https://setup?server=https%3A%2F%2Fx.dev&token=a")!) == nil)
    }
}
