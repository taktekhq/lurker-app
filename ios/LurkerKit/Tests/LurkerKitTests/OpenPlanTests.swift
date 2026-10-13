import Foundation
import Testing
@testable import LurkerKit

private func item(_ platform: Platform, _ queue: QueueKind, title: String?, body: String?, url: String?, target: String? = nil) -> QueueItem {
    QueueItem(id: "x", platform: platform, queue: queue, status: .open, title: title, body: body, url: url,
              target: target, why: nil, source: nil, photos: [], day: nil, created: 0, updated: 0,
              link: nil, skipReason: nil, skipNote: nil)
}

@Suite("OpenPlan")
struct OpenPlanTests {
    @Test func hnLinkPostFillsTitleAndURL() throws {
        let p = try #require(OpenPlan.make(for: item(.hn, .post, title: "C++ & you", body: nil, url: "https://example.com/a?b=1")))
        #expect(p.url.absoluteString == "https://news.ycombinator.com/submitlink?t=C%2B%2B%20%26%20you&u=https%3A%2F%2Fexample.com%2Fa%3Fb%3D1")
        #expect(p.clipboard == nil)
    }

    @Test func hnSubmitPageIsNotASharedLink() throws {
        let p = try #require(OpenPlan.make(for: item(.hn, .post, title: "Ask HN: x", body: "text", url: "https://news.ycombinator.com/submit")))
        #expect(p.url.absoluteString == "https://news.ycombinator.com/submitlink?t=Ask%20HN%3A%20x")
        #expect(p.clipboard == "text")
    }

    @Test func redditTextPostFillsTitleAndText() throws {
        let p = try #require(OpenPlan.make(for: item(.reddit, .post, title: "my ride", body: "went to faraya", url: nil, target: "r/Ducati")))
        #expect(p.url.absoluteString == "https://www.reddit.com/r/Ducati/submit?title=my%20ride&text=went%20to%20faraya")
        #expect(p.clipboard == "went to faraya")
    }

    @Test func redditLinkPostUsesURL() throws {
        let p = try #require(OpenPlan.make(for: item(.reddit, .post, title: "t", body: nil, url: "https://example.com", target: "webdev")))
        #expect(p.url.absoluteString == "https://www.reddit.com/r/webdev/submit?title=t&url=https%3A%2F%2Fexample.com")
        #expect(p.clipboard == "t")
    }

    @Test func commentOpensThreadAndCopiesOnlyTheReply() throws {
        let i = item(.reddit, .comment, title: "Thread title", body: "my reply", url: "https://www.reddit.com/r/x/comments/1/")
        let p = try #require(OpenPlan.make(for: i))
        #expect(p.url.absoluteString == "https://www.reddit.com/r/x/comments/1/")
        #expect(p.clipboard == "my reply")
        #expect(i.draftText == "my reply")
    }

    @Test func commentWithoutThreadHasNoPlan() {
        #expect(OpenPlan.make(for: item(.hn, .comment, title: "t", body: "b", url: nil)) == nil)
    }
}
