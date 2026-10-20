import Foundation
import WebKit

/// The Swift side of `window.honu`, what a microapp's page can ask of Honu:
/// to load and save its state in `data.json` in its folder, to fetch from
/// the web without the page's CORS limits, and to resize its panel. It also
/// hears of the page's errors.
@MainActor
final class Bridge: NSObject, WKScriptMessageHandlerWithReply, WKScriptMessageHandler {
    /// The name the page posts requests to, which reply.
    static let requests = "honu"
    /// The name the page posts its errors to.
    static let problems = "honuProblem"
    /// The most `honu.fetch` takes in.
    static let fetchLimit = 5_000_000
    /// The longest error kept, in characters.
    static let problemLimit = 600

    let folder: URL
    /// Called with each error the page reports.
    private let onProblem: (String) -> Void
    /// Called with the size the page asks for.
    private let onResize: (CGSize) -> Void

    init(
        folder: URL, onProblem: @escaping (String) -> Void = { _ in },
        onResize: @escaping (CGSize) -> Void = { _ in }
    ) {
        self.folder = folder
        self.onProblem = onProblem
        self.onResize = onResize
    }

    private var dataURL: URL { folder.appending(path: "data.json") }

    /// A user content controller that gives a page `window.honu` and reports
    /// its errors here.
    func controller() -> WKUserContentController {
        let controller = WKUserContentController()
        controller.addUserScript(
            WKUserScript(
                source: Self.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.addScriptMessageHandler(self, contentWorld: .page, name: Self.requests)
        controller.add(self, name: Self.problems)
        return controller
    }

    func userContentController(
        _ controller: WKUserContentController, didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any] else {
            return (nil, "Not allowed")
        }
        switch body["op"] as? String {
        case "load":
            guard let data = try? Data(contentsOf: dataURL) else { return (NSNull(), nil) }
            return (String(decoding: data, as: UTF8.self), nil)
        case "save":
            let state = body["state"] as? String ?? "null"
            do {
                try Data(state.utf8).write(to: dataURL, options: .atomic)
                return (nil, nil)
            } catch {
                return (nil, error.localizedDescription)
            }
        case "fetch":
            return await fetch(body)
        case "resize":
            guard let width = body["width"] as? Double, let height = body["height"] as? Double
            else { return (nil, "honu.resize takes a width and a height") }
            onResize(CGSize(width: width, height: height))
            return (nil, nil)
        default:
            return (nil, "Unknown request")
        }
    }

    func userContentController(
        _ controller: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }
        let problem = "\(body["kind"] ?? "error"): \(body["message"] ?? "")"
        onProblem(String(problem.prefix(Self.problemLimit)))
    }

    /// What `honu.fetch` may fetch: http and https URLs only.
    static func fetchable(_ text: String) -> URL? {
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased())
        else { return nil }
        return url
    }

    /// Fetches what the page asked for.
    private func fetch(_ body: [String: Any]) async -> (Any?, String?) {
        guard let url = Self.fetchable(body["url"] as? String ?? "") else {
            return (nil, "Only http and https URLs can be fetched")
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = body["method"] as? String ?? "GET"
        for (name, value) in body["headers"] as? [String: String] ?? [:] {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let text = body["body"] as? String {
            request.httpBody = Data(text.utf8)
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard data.count <= Self.fetchLimit else { return (nil, "The response is too large") }
            let http = response as? HTTPURLResponse
            let headers = (http?.allHeaderFields ?? [:]).reduce(into: [String: String]()) {
                $0["\($1.key)".lowercased()] = "\($1.value)"
            }
            return (
                [
                    "status": http?.statusCode ?? 0, "headers": headers,
                    "text": String(decoding: data, as: UTF8.self),
                ], nil
            )
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    /// `window.honu`, and what reports the page's errors.
    static let script = """
        (() => {
          const ask = (op, args) => window.webkit.messageHandlers.\(requests).postMessage({ op, ...args });
          const report = (kind, message) => {
            try { window.webkit.messageHandlers.\(problems).postMessage({ kind, message: String(message) }); } catch {}
          };
          window.honu = Object.freeze({
            load: async () => { const text = await ask("load", {}); return text == null ? null : JSON.parse(text); },
            save: (state) => ask("save", { state: JSON.stringify(state ?? null) }),
            fetch: (url, init = {}) => ask("fetch", {
              url: String(url), method: init.method ?? "GET", headers: init.headers ?? {},
              ...(init.body == null ? {} : { body: String(init.body) }),
            }),
            resize: (width, height) => ask("resize", { width: Number(width), height: Number(height) }),
          });
          window.addEventListener("error", (e) => report("error", e.error?.stack ?? e.message));
          window.addEventListener("unhandledrejection", (e) => report("rejection", e.reason?.stack ?? e.reason));
          const consoleError = console.error;
          console.error = (...parts) => { report("console", parts.join(" ")); consoleError.apply(console, parts); };
        })();
        """
}
