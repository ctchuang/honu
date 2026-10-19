import SwiftUI
import WebKit

/// Shows a page, telling its microapp while it loads, so the bubble breathes,
/// and when it has finished, so the bubble rises.
struct PageView: View {
    let app: WebApp
    let item: ItemID
    let source: PageSource
    // Spelled out instead of `@State`, whose macro ships only with Xcode.
    private let player = State(initialValue: Player())

    private var page: WebPage { player.wrappedValue.page }

    var body: some View {
        WebView(page)
            .task(id: source) {
                app.startedLoading(item)
                let end =
                    switch source {
                    case .web(let url):
                        await Self.finishes(page.load(URLRequest(url: url)))
                    case .video(let id):
                        // The player refuses to play without a referring origin, so it
                        // is loaded from an HTML page with a base URL, not from its URL.
                        await Self.finishes(
                            page.load(
                                html: Self.player(id), baseURL: URL(string: "https://honu.example")!
                            ))
                    }
                app.stoppedLoading(item, Task.isCancelled ? .cancelled : end)
            }
    }

    /// Waits for a load to end, returning how it did.
    private static func finishes(
        _ events: some AsyncSequence<WebPage.NavigationEvent, any Error>
    ) async -> LoadEnd {
        do {
            for try await event in events where event == .finished {
                return .finished
            }
            // Ending without finishing or failing, the load was given up.
            return .cancelled
        } catch {
            return LoadEnd(error)
        }
    }

    private static func player(_ id: String) -> String {
        """
        <!doctype html>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
          iframe { border: 0; width: 100%; height: 100%; }
        </style>
        <iframe src="https://www.youtube.com/embed/\(id)?playsinline=1&rel=0"
          allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
          referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>
        """
    }
}

/// Creates its page only when first used, since SwiftUI builds a new
/// initial value every time the view is recreated and keeps only the first.
@MainActor
final class Player {
    lazy var page = WebPage()
}
