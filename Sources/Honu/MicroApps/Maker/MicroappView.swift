import AppKit
import SwiftUI
import WebKit

/// Runs a microapp: its folder's page, served at `honu-app://`, with
/// `window.honu` to save its state in `dataURL`. It loads the page again for each new
/// `version`, and tells `app` when the page has loaded, what errors it
/// reports, and what size it asks for.
struct MicroappView: View {
    let version: Int
    // Spelled out instead of `@State`, whose macro ships only with Xcode.
    private let runner: State<MicroappRunner>

    init(app: MakerApp, item: ItemID, folder: URL, dataURL: URL, version: Int) {
        self.version = version
        runner = State(
            initialValue: MicroappRunner(
                folder: folder, dataURL: dataURL,
                onLoad: { [weak app] in app?.loaded(item) },
                onProblem: { [weak app] in app?.report($0, in: item) },
                onResize: { [weak app] in app?.resize(item, to: $0) }))
    }

    var body: some View {
        let runner = runner.wrappedValue
        WebView(runner.page)
            .task(id: version) {
                do {
                    for try await event in runner.page.load(
                        URLRequest(url: MicroappScheme.url(of: runner.folder)))
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
    let folder: URL
    let dataURL: URL
    let onLoad: () -> Void
    private let onProblem: (String) -> Void
    private let onResize: (CGSize) -> Void

    init(
        folder: URL, dataURL: URL, onLoad: @escaping () -> Void,
        onProblem: @escaping (String) -> Void, onResize: @escaping (CGSize) -> Void
    ) {
        self.folder = folder
        self.dataURL = dataURL
        self.onLoad = onLoad
        self.onProblem = onProblem
        self.onResize = onResize
    }

    lazy var bridge = Bridge(dataURL: dataURL, onProblem: onProblem, onResize: onResize)

    lazy var page: WebPage = {
        var configuration = WebPage.Configuration()
        configuration.urlSchemeHandlers[URLScheme(MicroappScheme.scheme)!] = MicroappScheme(
            folder: folder)
        configuration.userContentController = bridge.controller()
        let page = WebPage(configuration: configuration, navigationDecider: StaysHome())
        page.isInspectable = true
        return page
    }()
}

/// Keeps a microapp's page where it is: a link leaving it opens in the
/// browser instead, while frames inside the page go anywhere.
struct StaysHome: WebPage.NavigationDeciding {
    func decidePolicy(
        for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        guard let url = action.request.url, action.target?.isMainFrame ?? true,
            url.scheme != MicroappScheme.scheme
        else { return .allow }
        if ["http", "https"].contains(url.scheme?.lowercased()) {
            NSWorkspace.shared.open(url)
        }
        return .cancel
    }
}
