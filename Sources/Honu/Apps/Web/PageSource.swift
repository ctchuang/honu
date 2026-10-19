import Foundation

/// The video id of a YouTube link, if `url` is one.
func youTubeID(_ url: URL) -> String? {
    guard let host = url.host()?.lowercased() else { return nil }
    let path = url.pathComponents.filter { $0 != "/" }
    if host == "youtu.be" {
        return path.first
    }
    guard host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }
    if let first = path.first, ["embed", "shorts", "live"].contains(first), path.count > 1 {
        return path[1]
    }
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    return query?.first { $0.name == "v" }?.value
}

/// What a page shows: a web page, or a YouTube video in its embedded player.
enum PageSource: Hashable {
    case web(URL)
    case video(id: String)

    init(_ url: URL) {
        self = youTubeID(url).map { .video(id: $0) } ?? .web(url)
    }
}
