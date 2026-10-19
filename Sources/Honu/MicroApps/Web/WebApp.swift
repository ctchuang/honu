import SwiftUI
import WebKit

/// The Web microapp: any number of web pages, each shown in its bubble. A new
/// one asks for a link first; YouTube links play in YouTube's embedded player.
@Observable
@MainActor
final class WebApp: MicroApp {
    let id = AppID("web")
    let menuLabel = "Open Web Page"

    /// The model: each page's address, empty until one is entered.
    private(set) var pages = ItemTable<String>()
    /// How many bubbles are loading each page, which makes them breathe.
    @ObservationIgnored private var loading: [ItemID: Int] = [:]
    /// Pages that finished loading since the last `update`, whose bubbles
    /// rise, or failed to, whose bubbles wobble.
    @ObservationIgnored private var ended: [ItemID: Motion] = [:]

    func create() -> ItemID {
        pages.insert("")
    }

    func appearance(of item: ItemID) -> Appearance {
        let video = url(of: item).flatMap(youTubeID) != nil
        return Appearance(
            symbol: video ? "play.rectangle.fill" : "safari.fill",
            panelSize: CGSize(width: 600, height: 440)
        )
    }

    func title(of item: ItemID) -> String {
        guard let url = url(of: item) else { return "Web Page" }
        return shortLabel(url.host() ?? url.absoluteString)
    }

    /// A new page asks for a link, so its bubble starts with the cursor in the field.
    func newViewState(for item: ItemID, fresh: Bool) -> AddressDraft {
        AddressDraft(focusPending: fresh)
    }

    /// Text typed before the address field took the focus goes into it.
    func typeAhead(_ text: String, into item: ItemID, viewState: AddressDraft) {
        guard url(of: item) == nil else { return }
        viewState.text += text
    }

    func content(of item: ItemID, viewState: AddressDraft) -> WebContent {
        WebContent(app: self, item: item, draft: viewState)
    }

    /// Whether a bubble is still loading the page.
    func isBusy(_ item: ItemID) -> Bool {
        loading[item, default: 0] > 0
    }

    /// Has the bubbles of every page that finished loading rise, and those of
    /// every page that failed to wobble.
    func update(_ context: Context) {
        for (item, motion) in ended.sorted(by: { $0.key < $1.key }) {
            context.play(motion, for: item)
        }
        ended.removeAll()
    }

    /// Notes that a bubble started loading the page.
    func startedLoading(_ item: ItemID) {
        loading[item, default: 0] += 1
    }

    /// Notes that a bubble stopped loading the page, and how the load ended.
    func stoppedLoading(_ item: ItemID, _ end: LoadEnd) {
        let count = loading[item, default: 0] - 1
        loading[item] = count > 0 ? count : nil
        guard pages[item] != nil else { return }
        switch end {
        case .finished: ended[item] = .rise
        case .failed: ended[item] = .wobble
        case .cancelled: break
        }
    }

    /// The page's address, if one has been entered.
    func url(of item: ItemID) -> URL? {
        guard let text = pages[item], !text.isEmpty else { return nil }
        return URL(string: text)
    }

    /// Takes what the user typed as the page's address, adding `https://`
    /// when it has no scheme.
    func open(_ text: String, in item: ItemID) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pages[item] != nil, !text.isEmpty else { return }
        pages.update(item, to: text.contains("://") ? text : "https://" + text)
    }

    func remove(_ item: ItemID) {
        pages.remove(item)
        loading[item] = nil
        ended[item] = nil
    }

    var items: [ItemID] { pages.items }

    private struct SavedPage: Codable {
        var id: ItemID
        var url: String
    }

    func save() -> Data? {
        pages.save { SavedPage(id: $0, url: $1) }
    }

    func load(_ data: Data) {
        pages.load(data, as: SavedPage.self) { ($0.id, $0.url) }
    }
}

/// How a page's load ended.
enum LoadEnd: Equatable {
    case finished
    /// The page could not be loaded, as when the address is wrong or the
    /// network is down; the user is needed.
    case failed
    /// Nobody wants the page anymore: its bubble closed, or a new load,
    /// such as a link followed, replaced it.
    case cancelled

    /// How a load that threw `error` ended.
    init(_ error: any Error) {
        // WebPage wraps what went wrong in a navigation error of its own.
        if let error = error as? WebPage.NavigationError {
            switch error {
            case .failedProvisionalNavigation(let underlying): self.init(underlying)
            case .pageClosed: self = .cancelled
            case .webContentProcessTerminated, .invalidURL: self = .failed
            @unknown default: self = .failed
            }
            return
        }
        let error = error as NSError
        let cancelled =
            error is CancellationError
            || (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            // WebKit's "frame load interrupted", when a new navigation replaces the load.
            || (error.domain == "WebKitErrorDomain" && error.code == 102)
        self = cancelled ? .cancelled : .failed
    }
}
