import Foundation
import Testing
@testable import LurkerKit

@Suite("Share and Draft decoding")
struct ModelsTests {
    @Test("decodes a drafted Share with one Draft, in the exact shapes SPEC.md gives")
    func decodesShareWithDraft() throws {
        let json = """
        {
          "id": "abc123",
          "note": "my ducati at the track",
          "status": "drafted",
          "created": 1733000000,
          "updated": 1733000100,
          "photos": ["p1.jpg", "p2.jpg"],
          "drafts": [
            {
              "sub": "Ducati",
              "title": "Track day on the Panigale",
              "body": "",
              "why": "his own bike, rides, parts",
              "rules_checked": true,
              "rule_notes": "no flair needed"
            }
          ],
          "error": null
        }
        """
        let share = try JSONDecoder().decode(Share.self, from: Data(json.utf8))

        #expect(share.id == "abc123")
        #expect(share.note == "my ducati at the track")
        #expect(share.status == .drafted)
        #expect(share.created == 1733000000)
        #expect(share.updated == 1733000100)
        #expect(share.photos == ["p1.jpg", "p2.jpg"])
        #expect(share.error == nil)
        #expect(share.drafts.count == 1)

        let draft = share.drafts[0]
        #expect(draft.sub == "Ducati")
        #expect(draft.title == "Track day on the Panigale")
        #expect(draft.body == "")
        #expect(draft.why == "his own bike, rides, parts")
        #expect(draft.rulesChecked == true)
        #expect(draft.ruleNotes == "no flair needed")
    }

    @Test("decodes a new share with no drafts yet and a null note")
    func decodesEmptyShare() throws {
        let json = """
        {"id": "xyz", "note": null, "status": "new", "created": 1, "updated": 1,
         "photos": ["p1.jpg"], "drafts": [], "error": null}
        """
        let share = try JSONDecoder().decode(Share.self, from: Data(json.utf8))
        #expect(share.note == nil)
        #expect(share.status == .new)
        #expect(share.drafts.isEmpty)
    }

    @Test("decodes a failed share carrying its error message")
    func decodesFailedShare() throws {
        let json = """
        {"id": "f1", "note": null, "status": "failed", "created": 1, "updated": 2,
         "photos": [], "drafts": [], "error": "no rules for this sub"}
        """
        let share = try JSONDecoder().decode(Share.self, from: Data(json.utf8))
        #expect(share.status == .failed)
        #expect(share.error == "no rules for this sub")
    }

    @Test("a Draft with no rule_notes decodes ruleNotes as nil")
    func draftWithoutRuleNotes() throws {
        let json = """
        {"sub": "Ducati", "title": "t", "body": "b", "why": "w", "rules_checked": false}
        """
        let draft = try JSONDecoder().decode(Draft.self, from: Data(json.utf8))
        #expect(draft.ruleNotes == nil)
        #expect(draft.rulesChecked == false)
    }

    @Test("every ShareStatus from SPEC.md's status column round-trips")
    func allStatusesDecode() throws {
        for raw in ["new", "drafting", "drafted", "failed", "posted", "skipped"] {
            let status = try JSONDecoder().decode(ShareStatus.self, from: Data("\"\(raw)\"".utf8))
            #expect(status.rawValue == raw)
        }
    }
}
