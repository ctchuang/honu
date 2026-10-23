import AppKit
import SwiftUI
import WebKit

/// What hears from a microapp's page as it runs: when it has loaded, what
/// errors it reports, both at the time they happen, and what size it asks
/// for. The Maker is one, for the microapps Claude makes, and each
/// microapp built into Honu as a web page is another.
@MainActor
protocol PageHost: AnyObject {
    func loaded(_ item: ItemID, at time: TimeInterval)
    func report(_ problem: String, in item: ItemID, at time: TimeInterval)
    func resize(_ item: ItemID, to size: CGSize)
}

/// Runs a microapp: the page `site` serves, with `window.honu` to save its
/// state in `dataURL`. It loads the page again for each new `version`, and
/// tells `host` when the page has loaded, what errors it reports, and what
/// size it asks for.
struct MicroappView: View {
    let version: Int
    // Spelled out instead of `@State`, whose macro ships only with Xcode.
    private let runner: State<MicroappRunner>

    init(
        host: any PageHost, item: ItemID, site: MicroappScheme, dataURL: URL, version: Int
    ) {
        self.version = version
        runner = State(
            initialValue: MicroappRunner(
                site: site, dataURL: dataURL,
                onLoad: { [weak host] in host?.loaded(item, at: now()) },
                onProblem: { [weak host] in host?.report($0, in: item, at: now()) },
                onResize: { [weak host] in host?.resize(item, to: $0) }))
    }

    var body: some View {
        let runner = runner.wrappedValue
        WebView(runner.page)
            .task(id: version) {
                do {
                    for try await event in runner.page.load(URLRequest(url: runner.site.pageURL))
                    where event == .finished {
                        runner.onLoad()
                    }
                } catch {
                    // A load replaced by the next version's needs no word; the
                    // page's own errors come through the bridge.
                }
            }
    }
}

/// Creates its page only when first used, since SwiftUI builds a new
/// initial value every time the view is recreated and keeps only the first.
@MainActor
final class MicroappRunner {
    let site: MicroappScheme
    let dataURL: URL
    let onLoad: () -> Void
    private let onProblem: (String) -> Void
    private let onResize: (CGSize) -> Void

    init(
        site: MicroappScheme, dataURL: URL, onLoad: @escaping () -> Void,
        onProblem: @escaping (String) -> Void, onResize: @escaping (CGSize) -> Void
    ) {
        self.site = site
        self.dataURL = dataURL
        self.onLoad = onLoad
        self.onProblem = onProblem
        self.onResize = onResize
    }

    lazy var bridge = Bridge(dataURL: dataURL, onProblem: onProblem, onResize: onResize)

    lazy var page: WebPage = {
        var configuration = WebPage.Configuration()
        configuration.urlSchemeHandlers[URLScheme(site.scheme)!] = site
        configuration.userContentController = bridge.controller()
        let page = WebPage(
            configuration: configuration, navigationDecider: StaysHome(scheme: site.scheme))
        page.isInspectable = true
        return page
    }()
}

/// Keeps a microapp's page where it is: a link leaving it opens in the
/// browser instead, while frames inside the page go anywhere.
struct StaysHome: WebPage.NavigationDeciding {
    /// The scheme the page is served by, which it stays in.
    let scheme: String

    func decidePolicy(
        for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        guard let url = action.request.url, action.target?.isMainFrame ?? true,
            url.scheme != scheme
        else { return .allow }
        if ["http", "https"].contains(url.scheme?.lowercased()) {
            NSWorkspace.shared.open(url)
        }
        return .cancel
    }
}
