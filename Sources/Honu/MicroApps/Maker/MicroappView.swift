import AppKit
import SwiftUI
import WebKit

/// Runs a microapp: its folder's page, served at `honu-app://`, with
/// `window.honu` to save its state.
struct MicroappView: View {
    // Spelled out instead of `@State`, whose macro ships only with Xcode.
    private let runner: State<MicroappRunner>

    init(folder: URL) {
        runner = State(initialValue: MicroappRunner(folder: folder))
    }

    var body: some View {
        let runner = runner.wrappedValue
        WebView(runner.page)
            .task(id: runner.folder) {
                do {
                    for try await _ in runner.page.load(
                        URLRequest(url: MicroappScheme.url(of: runner.folder)))
                    {}
                } catch {
                    print("Microapp \(runner.folder.lastPathComponent) failed to load: \(error)")
                }
            }
    }
}

/// Creates its page only when first used, since SwiftUI builds a new
/// initial value every time the view is recreated and keeps only the first.
@MainActor
final class MicroappRunner {
    let folder: URL

    init(folder: URL) {
        self.folder = folder
    }

    lazy var bridge = Bridge(folder: folder)

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
