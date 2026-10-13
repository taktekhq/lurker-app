import Foundation

/// What Open does for an item: the page to open, with as much filled in as the
/// site allows, and the text to put on the clipboard first.
///
/// - HN post: `submitlink?t=<title>&u=<link>` fills both fields; the text, if any,
///   goes on the clipboard for the text box.
/// - Reddit post: `/r/<sub>/submit?title=...&text=...` (or `&url=` for a link post).
///   The text also goes on the clipboard, in case the Reddit app opens instead of
///   the browser and drops the fields.
/// - Comments: no site fills a reply box from a URL, so the reply goes on the
///   clipboard and the thread opens.
public struct OpenPlan: Equatable, Sendable {
    public let url: URL
    public let clipboard: String?

    public static func make(for item: QueueItem) -> OpenPlan? {
        let title = (item.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (item.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let link = sharedLink(item)

        if item.queue == .comment {
            guard let raw = item.url, let url = URL(string: raw) else { return nil }
            return OpenPlan(url: url, clipboard: body.isEmpty ? nil : body)
        }

        switch item.platform {
        case .hn:
            var q: [(String, String)] = [("t", title)]
            if let link { q.append(("u", link)) }
            return url("https://news.ycombinator.com/submitlink", q).map {
                OpenPlan(url: $0, clipboard: body.isEmpty ? nil : body)
            }
        case .reddit:
            let sub = (item.target ?? "").replacingOccurrences(of: "r/", with: "")
            let base = sub.isEmpty ? "https://www.reddit.com/submit" : "https://www.reddit.com/r/\(sub)/submit"
            var q: [(String, String)] = [("title", title)]
            if let link {
                q.append(("url", link))
            } else if !body.isEmpty {
                q.append(("text", body))
            }
            return url(base, q).map { OpenPlan(url: $0, clipboard: body.isEmpty ? title : body) }
        }
    }

    /// The outside link a post shares: the item's url, unless it is a submit page
    /// or the site itself.
    static func sharedLink(_ item: QueueItem) -> String? {
        guard let raw = item.url, let u = URL(string: raw), let host = u.host?.lowercased() else { return nil }
        if host.hasSuffix("ycombinator.com") && u.path.hasPrefix("/submit") { return nil }
        if host.hasSuffix("reddit.com") && u.path.contains("/submit") { return nil }
        return raw
    }

    /// Builds a URL whose query values are fully percent-encoded ("+" and "&"
    /// included: HN keeps a literal "+" in titles).
    static func url(_ base: String, _ query: [(String, String)]) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?#/:")
        let q = query.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
        return URL(string: base + "?" + q.joined(separator: "&"))
    }
}
