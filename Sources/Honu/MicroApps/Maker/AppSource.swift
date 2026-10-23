import Foundation

/// What a microapp's page says about itself in its head: its name, the size
/// it wants, and the symbol for its closed bubble.
struct PageMeta: Equatable {
    var title: String?
    var size: CGSize?
    var symbol: String?
}

/// Reading microapp pages: finding the page in Claude's answer, and what the
/// page says about itself.
enum AppSource {
    /// The smallest and largest a page can be, in points.
    static let minSize = CGSize(width: 240, height: 160)
    static let maxSize = CGSize(width: 1000, height: 800)

    /// The page in `answer`: from `<!doctype html>` or `<html>` to the last
    /// `</html>`, leaving out anything around it, such as Markdown fences.
    /// Nothing if the page is missing or cut off.
    static func page(from answer: String) -> String? {
        // The page starts a line of its own, so tags named in the text
        // before it are not taken for it.
        let lineStart = /^[ \t]*(?<tag><!doctype html|<html)/.ignoresCase()
            .anchorsMatchLineEndings()
        let start =
            answer.firstMatch(of: lineStart)?.output.tag.startIndex
            ?? [
                answer.range(of: "<!doctype html", options: .caseInsensitive),
                answer.range(of: "<html", options: .caseInsensitive),
            ].compactMap { $0?.lowerBound }.min()
        guard let start,
            let end = answer.range(of: "</html>", options: [.caseInsensitive, .backwards]),
            start < end.lowerBound
        else { return nil }
        return String(answer[start..<end.upperBound])
    }

    /// What `page` says about itself.
    static func meta(of page: String) -> PageMeta {
        let size = meta("honu-size", in: page).flatMap(size(from:))
        return PageMeta(
            title: title(in: page),
            size: size,
            symbol: meta("honu-symbol", in: page))
    }

    /// `size` kept within what a page can be.
    static func clamped(_ size: CGSize) -> CGSize {
        CGSize(
            width: min(max(size.width, minSize.width), maxSize.width),
            height: min(max(size.height, minSize.height), maxSize.height))
    }

    /// A size written `WIDTHxHEIGHT`, kept within limits.
    static func size(from text: String) -> CGSize? {
        let parts = text.lowercased().split(separator: "x").map {
            Double($0.trimmingCharacters(in: .whitespaces))
        }
        guard parts.count == 2, let width = parts[0], let height = parts[1] else { return nil }
        return clamped(CGSize(width: width, height: height))
    }

    private static func title(in page: String) -> String? {
        let pattern = /<title[^>]*>(?<text>[^<]*)<\/title>/.ignoresCase()
        guard let match = page.firstMatch(of: pattern) else { return nil }
        let title = decode(String(match.output.text)).trimmingCharacters(
            in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    /// The content of the `<meta>` named `name`, with its attributes in
    /// either order.
    private static func meta(_ name: String, in page: String) -> String? {
        for match in page.matches(of: /<meta\s[^>]*>/.ignoresCase()) {
            let tag = String(page[match.range])
            guard attribute("name", in: tag)?.lowercased() == name else { continue }
            return attribute("content", in: tag).map(decode)
        }
        return nil
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = try! Regex(#"\s"# + name + #"\s*=\s*(?:"([^"]*)"|'([^']*)')"#)
            .ignoresCase()
        guard let match = tag.firstMatch(of: pattern) else { return nil }
        return (match.output[1].substring ?? match.output[2].substring).map(String.init)
    }

    /// `text` with the few HTML entities a title is likely to hold decoded.
    private static func decode(_ text: String) -> String {
        [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")]
            .reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}
