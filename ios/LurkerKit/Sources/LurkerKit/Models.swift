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

// MARK: - SPEC-v2.md: queues

/// The two sites the queues cover.
public enum Platform: String, Codable, Sendable, Equatable, CaseIterable {
    case reddit
    case hn
}

/// Each platform has one queue for new posts and one for comments on other
/// people's threads.
public enum QueueKind: String, Codable, Sendable, Equatable, CaseIterable {
    case post
    case comment
}

/// A queue item's lifecycle (SPEC-v2.md). `open` items show up in the queue;
/// `done`, `skipped` and `expired` items have left it.
public enum ItemStatus: String, Codable, Sendable, Equatable {
    case open
    case done
    case skipped
    case expired
}

/// Why a suggestion was skipped: `bad` so the engine learns from it, `later`
/// if it is fine but not now.
public enum SkipReason: String, Codable, Sendable, Equatable, CaseIterable {
    case bad
    case later
}

/// One suggestion in a queue, exactly as `GET /v1/queues` and `GET /v1/items`
/// return it (SPEC-v2.md). The app only ever reads and marks these; it never
/// posts or comments itself.
public struct QueueItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let platform: Platform
    public let queue: QueueKind
    public let status: ItemStatus
    public let title: String?
    public let body: String?
    public let url: String?
    public let target: String?
    public let why: String?
    public let source: String?
    public let photos: [String]
    public let day: String?
    public let created: Int
    public let updated: Int
    public let link: String?
    public let skipReason: SkipReason?
    public let skipNote: String?

    public init(
        id: String,
        platform: Platform,
        queue: QueueKind,
        status: ItemStatus,
        title: String?,
        body: String?,
        url: String?,
        target: String?,
        why: String?,
        source: String?,
        photos: [String],
        day: String?,
        created: Int,
        updated: Int,
        link: String?,
        skipReason: SkipReason?,
        skipNote: String?
    ) {
        self.id = id
        self.platform = platform
        self.queue = queue
        self.status = status
        self.title = title
        self.body = body
        self.url = url
        self.target = target
        self.why = why
        self.source = source
        self.photos = photos
        self.day = day
        self.created = created
        self.updated = updated
        self.link = link
        self.skipReason = skipReason
        self.skipNote = skipNote
    }

    private enum CodingKeys: String, CodingKey {
        case id, platform, queue, status, title, body, url, target, why, source, photos, day, created, updated, link
        case skipReason = "skip_reason"
        case skipNote = "skip_note"
    }

    /// The text worth copying to the clipboard before posting: title and
    /// body where each is present, title alone for most posts, body alone
    /// for most comments.
    public var draftText: String {
        [title, body]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

/// One platform's post or comment queue (SPEC-v2.md). `open` is oldest first.
public struct Queue: Codable, Sendable, Equatable {
    public let open: [QueueItem]
    public let doneToday: Int
    public let skippedToday: Int
    public let target: Int

    public init(open: [QueueItem], doneToday: Int, skippedToday: Int, target: Int) {
        self.open = open
        self.doneToday = doneToday
        self.skippedToday = skippedToday
        self.target = target
    }

    private enum CodingKeys: String, CodingKey {
        case open
        case doneToday = "done_today"
        case skippedToday = "skipped_today"
        case target
    }
}

/// One platform's post and comment queues.
public struct PlatformQueues: Codable, Sendable, Equatable {
    public let post: Queue
    public let comment: Queue

    public init(post: Queue, comment: Queue) {
        self.post = post
        self.comment = comment
    }
}

/// `GET /v1/queues` (SPEC-v2.md).
public struct QueuesResponse: Codable, Sendable, Equatable {
    public let day: String
    public let platforms: Platforms

    public init(day: String, platforms: Platforms) {
        self.day = day
        self.platforms = platforms
    }

    public struct Platforms: Codable, Sendable, Equatable {
        public let reddit: PlatformQueues
        public let hn: PlatformQueues

        public init(reddit: PlatformQueues, hn: PlatformQueues) {
            self.reddit = reddit
            self.hn = hn
        }
    }

    public func queue(_ platform: Platform, _ kind: QueueKind) -> Queue {
        let platformQueues = platform == .reddit ? platforms.reddit : platforms.hn
        return kind == .post ? platformQueues.post : platformQueues.comment
    }
}

// MARK: - SPEC-v2.md: growth

/// One `[day, value]` pair, decoded from and encoded back to a two-element
/// JSON array (the growth JSON's shape for karma and done series).
public struct DayValue: Codable, Sendable, Equatable, Identifiable {
    public var id: String { day }
    public let day: String
    public let value: Int

    public init(day: String, value: Int) {
        self.day = day
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        day = try container.decode(String.self)
        value = try container.decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(day)
        try container.encode(value)
    }
}

/// The 90/10 split for one platform: how many of the last items were about
/// the maker's own work, and how many more until it is fair to post about
/// their own work again.
public struct SplitStats: Codable, Sendable, Equatable {
    public let own: Int
    public let last: Int
    public let need: Int

    public init(own: Int, last: Int, need: Int) {
        self.own = own
        self.last = last
        self.need = need
    }
}

/// One of the best recent posts or comments, as the engine found it.
public struct BestPost: Codable, Sendable, Equatable, Identifiable {
    public var id: String { link }
    public let platform: String
    public let title: String
    public let link: String
    public let score: Int
    public let comments: Int

    public init(platform: String, title: String, link: String, score: Int, comments: Int) {
        self.platform = platform
        self.title = title
        self.link = link
        self.score = score
        self.comments = comments
    }
}

/// `GET /v1/growth` (SPEC-v2.md): engine-owned, the app renders whatever is
/// there. Every field is optional so a missing or still-empty `{}` growth
/// object decodes cleanly into "nothing to show yet" rather than an error.
public struct Growth: Codable, Sendable, Equatable {
    public let updated: Int?
    public let karma: [String: [DayValue]]?
    public let done: [String: [String: [DayValue]]]?
    public let split: [String: SplitStats]?
    public let best: [BestPost]?
    public let streakDays: Int?

    public init(
        updated: Int? = nil,
        karma: [String: [DayValue]]? = nil,
        done: [String: [String: [DayValue]]]? = nil,
        split: [String: SplitStats]? = nil,
        best: [BestPost]? = nil,
        streakDays: Int? = nil
    ) {
        self.updated = updated
        self.karma = karma
        self.done = done
        self.split = split
        self.best = best
        self.streakDays = streakDays
    }

    private enum CodingKeys: String, CodingKey {
        case updated, karma, done, split, best
        case streakDays = "streak_days"
    }

    /// True once every field is empty: the profile screen shows a friendly
    /// empty state instead of blank charts.
    public var isEmpty: Bool {
        (karma?.isEmpty ?? true) && (done?.isEmpty ?? true) && (split?.isEmpty ?? true) && (best?.isEmpty ?? true)
    }
}
