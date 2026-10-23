import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves a microapp's folder at `<scheme>://<folder name>/`, so each
/// microapp has an origin of its own, a secure context, and relative links
/// to the files beside its page. It only reads the folder, and never serves
/// what its instances saved (`instances/`): a page reads only its own,
/// through `honu.load`.
struct MicroappScheme: URLSchemeHandler {
    /// The scheme of the microapps Claude makes.
    static let scheme = "honu-app"

    /// The scheme it serves, which is part of the page's origin.
    let scheme: String
    let folder: URL

    init(folder: URL, scheme: String = Self.scheme) {
        self.folder = folder
        self.scheme = scheme
    }

    /// Where the page at the root of its folder is.
    var pageURL: URL {
        URL(string: "\(scheme)://\(folder.lastPathComponent)/index.html")!
    }

    /// Where the page at the root of a microapp's folder is, served by the
    /// microapps' scheme.
    static func url(of folder: URL) -> URL {
        MicroappScheme(folder: folder).pageURL
    }

    func reply(for request: URLRequest) -> AsyncThrowingStream<URLSchemeTaskResult, any Error> {
        AsyncThrowingStream { replies in
            let url = request.url ?? pageURL
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

    /// The file in the folder `url` names, if it stays inside the folder
    /// and out of `instances/`.
    func file(at url: URL) -> URL? {
        let path = url.path(percentEncoded: false)
        let name = path.isEmpty || path == "/" ? "index.html" : String(path.dropFirst())
        let file = folder.appending(path: name).standardizedFileURL
        let root = folder.standardizedFileURL.pathComponents
        guard file.pathComponents.starts(with: root) else { return nil }
        // Compared without case, as the Mac's file system usually is.
        let top = file.pathComponents.dropFirst(root.count).first?.lowercased()
        return top == AppFolder.instances ? nil : file
    }

    private static func response(_ url: URL, _ status: Int, _ type: String) -> URLResponse {
        HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": type, "Cache-Control": "no-store"])!
    }
}
