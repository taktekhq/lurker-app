import Foundation
import Testing
@testable import LurkerKit

@Suite("Queue item and growth decoding (SPEC-v2.md)")
struct QueueModelsTests {
    @Test("decodes a reddit post item with every field set")
    func decodesFullItem() throws {
        let json = """
        {
          "id": "a1", "platform": "reddit", "queue": "post", "status": "open",
          "title": "morning ride", "body": "", "url": "https://reddit.com/r/Ducati/submit",
          "target": "Ducati", "why": "his own bike", "source": "kbase", "photos": [],
          "day": "2026-10-13", "created": 1, "updated": 2,
          "link": null, "skip_reason": null, "skip_note": null
        }
        """
        let item = try JSONDecoder().decode(QueueItem.self, from: Data(json.utf8))
        #expect(item.id == "a1")
        #expect(item.platform == .reddit)
        #expect(item.queue == .post)
        #expect(item.status == .open)
        #expect(item.target == "Ducati")
        #expect(item.day == "2026-10-13")
        #expect(item.link == nil)
    }

    @Test("decodes an hn comment item with no title, target or url")
    func decodesCommentItem() throws {
        let json = """
        {
          "id": "c1", "platform": "hn", "queue": "comment", "status": "done",
          "title": null, "body": "nice project", "url": "https://news.ycombinator.com/item?id=1",
          "target": null, "why": "relevant thread", "source": "thread", "photos": [],
          "day": "2026-10-13", "created": 1, "updated": 2,
          "link": "https://news.ycombinator.com/item?id=1#c1", "skip_reason": null, "skip_note": null
        }
        """
        let item = try JSONDecoder().decode(QueueItem.self, from: Data(json.utf8))
        #expect(item.platform == .hn)
        #expect(item.queue == .comment)
        #expect(item.title == nil)
        #expect(item.target == nil)
        #expect(item.link == "https://news.ycombinator.com/item?id=1#c1")
    }

    @Test("decodes a skipped item's reason and note")
    func decodesSkippedItem() throws {
        let json = """
        {
          "id": "s1", "platform": "reddit", "queue": "post", "status": "skipped",
          "title": "t", "body": "", "url": null, "target": "Ducati", "why": "w",
          "source": "kbase", "photos": [], "day": "2026-10-13", "created": 1, "updated": 2,
          "link": null, "skip_reason": "bad", "skip_note": "not his voice"
        }
        """
        let item = try JSONDecoder().decode(QueueItem.self, from: Data(json.utf8))
        #expect(item.status == .skipped)
        #expect(item.skipReason == .bad)
        #expect(item.skipNote == "not his voice")
    }

    @Test("draftText joins title and body, skipping whichever is empty or nil")
    func draftText() {
        let base = QueueItem(
            id: "a", platform: .reddit, queue: .post, status: .open,
            title: nil, body: nil, url: nil, target: nil, why: nil, source: nil,
            photos: [], day: nil, created: 0, updated: 0, link: nil, skipReason: nil, skipNote: nil
        )
        #expect(base.draftText == "")

        var withTitle = base
        withTitle = QueueItem(
            id: "a", platform: .reddit, queue: .post, status: .open,
            title: "a title", body: "", url: nil, target: nil, why: nil, source: nil,
            photos: [], day: nil, created: 0, updated: 0, link: nil, skipReason: nil, skipNote: nil
        )
        #expect(withTitle.draftText == "a title")

        let withBoth = QueueItem(
            id: "a", platform: .hn, queue: .comment, status: .open,
            title: "a title", body: "a comment", url: nil, target: nil, why: nil, source: nil,
            photos: [], day: nil, created: 0, updated: 0, link: nil, skipReason: nil, skipNote: nil
        )
        #expect(withBoth.draftText == "a title\n\na comment")
    }

    @Test("Queue decodes done_today, skipped_today and target")
    func queueDecoding() throws {
        let json = """
        {"open": [], "done_today": 3, "skipped_today": 1, "target": 5}
        """
        let queue = try JSONDecoder().decode(Queue.self, from: Data(json.utf8))
        #expect(queue.doneToday == 3)
        #expect(queue.skippedToday == 1)
        #expect(queue.target == 5)
    }

    @Test("QueuesResponse.queue(_:_:) picks out the right platform and kind")
    func queuesResponseLookup() throws {
        let json = """
        {"day": "2026-10-13", "platforms": {
          "reddit": {"post": {"open": [], "done_today": 1, "skipped_today": 0, "target": 5},
                     "comment": {"open": [], "done_today": 2, "skipped_today": 0, "target": 5}},
          "hn": {"post": {"open": [], "done_today": 3, "skipped_today": 0, "target": 5},
                 "comment": {"open": [], "done_today": 4, "skipped_today": 0, "target": 5}}
        }}
        """
        let response = try JSONDecoder().decode(QueuesResponse.self, from: Data(json.utf8))
        #expect(response.queue(.reddit, .post).doneToday == 1)
        #expect(response.queue(.reddit, .comment).doneToday == 2)
        #expect(response.queue(.hn, .post).doneToday == 3)
        #expect(response.queue(.hn, .comment).doneToday == 4)
    }

    @Test("growth decodes karma and done as [day, value] pairs")
    func growthSeries() throws {
        let json = """
        {"updated": 1791900000,
         "karma": {"hn": [["2026-10-01", 99], ["2026-10-02", 101]], "reddit": [["2026-10-01", 117]]},
         "done": {"hn": {"post": [["2026-10-13", 1]], "comment": []}, "reddit": {"post": [], "comment": []}},
         "split": {"hn": {"own": 1, "last": 10, "need": 9}, "reddit": {"own": 0, "last": 10, "need": 0}},
         "best": [{"platform": "reddit", "title": "a post", "link": "https://reddit.com/x", "score": 22, "comments": 4}],
         "streak_days": 3}
        """
        let growth = try JSONDecoder().decode(Growth.self, from: Data(json.utf8))
        #expect(growth.updated == 1791900000)
        #expect(growth.karma?["hn"]?.map(\.value) == [99, 101])
        #expect(growth.karma?["hn"]?.map(\.day) == ["2026-10-01", "2026-10-02"])
        #expect(growth.done?["hn"]?["post"]?.first?.value == 1)
        #expect(growth.split?["hn"] == SplitStats(own: 1, last: 10, need: 9))
        #expect(growth.best?.first?.title == "a post")
        #expect(growth.streakDays == 3)
        #expect(growth.isEmpty == false)
    }

    @Test("an empty growth object decodes to isEmpty true")
    func growthEmptyObject() throws {
        let growth = try JSONDecoder().decode(Growth.self, from: Data("{}".utf8))
        #expect(growth.isEmpty)
        #expect(growth.updated == nil)
        #expect(growth.best == nil)
    }

    @Test("ItemStatus and SkipReason round-trip every raw value")
    func enumsRoundTrip() throws {
        for raw in ["open", "done", "skipped", "expired"] {
            let status = try JSONDecoder().decode(ItemStatus.self, from: Data("\"\(raw)\"".utf8))
            #expect(status.rawValue == raw)
        }
        for raw in ["bad", "later"] {
            let reason = try JSONDecoder().decode(SkipReason.self, from: Data("\"\(raw)\"".utf8))
            #expect(reason.rawValue == raw)
        }
    }
}
