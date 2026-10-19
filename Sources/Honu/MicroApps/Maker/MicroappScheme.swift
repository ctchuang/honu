import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves a microapp's folder at `honu-app://<folder name>/`, so each
/// microapp has an origin of its own, a secure context, and relative links
/// to the files beside its page.
struct MicroappScheme: URLSchemeHandler {
    static let scheme = "honu-app"

    let folder: URL

    /// Where the page at the root of a microapp's folder is.
    static func url(of folder: URL) -> URL {
        URL(string: "\(scheme)://\(folder.lastPathComponent)/index.html")!
    }

    func reply(for request: URLRequest) -> AsyncThrowingStream<URLSchemeTaskResult, any Error> {
        AsyncThrowingStream { replies in
            let url = request.url ?? Self.url(of: folder)
            if let file = file(at: url), let data = try? Data(contentsOf: file) {
                let type = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType
                replies.yield(
                    .response(Self.response(url, 200, type ?? "application/octet-stream")))
                replies.yield(.data(data))
            } else {
                replies.yield(.response(Self.response(url, 404, "text/plain")))
            }
            replies.finish()
        }
    }

    /// The file in the folder `url` names, if it stays inside the folder.
    func file(at url: URL) -> URL? {
        let path = url.path(percentEncoded: false)
        let name = path.isEmpty || path == "/" ? "index.html" : String(path.dropFirst())
        let file = folder.appending(path: name).standardizedFileURL
        let inside = file.path().hasPrefix(folder.standardizedFileURL.path())
        return inside ? file : nil
    }

    private static func response(_ url: URL, _ status: Int, _ type: String) -> URLResponse {
        HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": type, "Cache-Control": "no-store"])!
    }
}
