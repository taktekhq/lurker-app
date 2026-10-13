import Foundation

/// A share's lifecycle, matching the `status` column of the `shares` table
/// (SPEC.md).
public enum ShareStatus: String, Codable, Sendable, Equatable {
    case new
    case drafting
    case drafted
    case failed
    case posted
    case skipped
}

/// One Reddit post draft inside a `Share`, exactly as `drafter/` posts it to
/// `POST /v1/shares/:id/drafts` (SPEC.md). The app only ever reads these; it
/// never posts to Reddit itself.
public struct Draft: Codable, Sendable, Equatable {
    public let sub: String
    public let title: String
    public let body: String
    public let why: String
    public let rulesChecked: Bool
    public let ruleNotes: String?

    public init(sub: String, title: String, body: String, why: String, rulesChecked: Bool, ruleNotes: String?) {
        self.sub = sub
        self.title = title
        self.body = body
        self.why = why
        self.rulesChecked = rulesChecked
        self.ruleNotes = ruleNotes
    }

    private enum CodingKeys: String, CodingKey {
        case sub, title, body, why
        case rulesChecked = "rules_checked"
        case ruleNotes = "rule_notes"
    }
}

/// One shared photo set, with its drafts once `drafter/` has processed it.
/// `GET /v1/shares` returns these newest first (SPEC.md).
public struct Share: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let note: String?
    public let status: ShareStatus
    public let created: Int
    public let updated: Int
    public let photos: [String]
    public let drafts: [Draft]
    public let error: String?

    public init(
        id: String,
        note: String?,
        status: ShareStatus,
        created: Int,
        updated: Int,
        photos: [String],
        drafts: [Draft],
        error: String?
    ) {
        self.id = id
        self.note = note
        self.status = status
        self.created = created
        self.updated = updated
        self.photos = photos
        self.drafts = drafts
        self.error = error
    }
}
