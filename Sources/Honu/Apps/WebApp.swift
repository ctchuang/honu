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
    private(set) var pages: [ItemID: String] = [:]
    @ObservationIgnored private var ids = ItemIDs()
    /// How many bubbles are loading each page, which makes them breathe.
    @ObservationIgnored private var loading: [ItemID: Int] = [:]
    /// Pages that finished loading since the last `update`, whose bubbles rise.
    @ObservationIgnored private var loaded: Set<ItemID> = []

    func create() -> ItemID {
        let id = ids.next()
        pages[id] = ""
        return id
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
    func newViewState(for item: ItemID, fresh: Bool) -> AnyObject? {
        AddressDraft(focusPending: fresh)
    }

    /// Text typed before the address field took the focus goes into it.
    func typeAhead(_ text: String, into item: ItemID, viewState: AnyObject?) {
        guard url(of: item) == nil else { return }
        (viewState as? AddressDraft)?.text += text
    }

    func content(of item: ItemID, viewState: AnyObject?) -> AnyView {
        AnyView(WebContent(app: self, item: item, draft: viewState as? AddressDraft))
    }

    /// Whether a bubble is still loading the page.
    func isBusy(_ item: ItemID) -> Bool {
        loading[item, default: 0] > 0
    }

    /// Has the bubbles of every page that finished loading rise.
    func update(_ context: Context) {
        for item in loaded.sorted() {
            context.play(.rise, for: item)
        }
        loaded.removeAll()
    }

    /// Notes that a bubble started loading the page.
    func startedLoading(_ item: ItemID) {
        loading[item, default: 0] += 1
    }

    /// Notes that a bubble stopped loading the page: `finished` it, or gave
    /// up, as when the load failed or the bubble closed.
    func stoppedLoading(_ item: ItemID, finished: Bool) {
        let count = loading[item, default: 0] - 1
        loading[item] = count > 0 ? count : nil
        if finished, pages[item] != nil {
            loaded.insert(item)
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
        pages[item] = text.contains("://") ? text : "https://" + text
    }

    func remove(_ item: ItemID) {
        pages[item] = nil
        loading[item] = nil
        loaded.remove(item)
    }

    var items: [ItemID] { pages.keys.sorted() }

    private struct SavedPage: Codable {
        var id: ItemID
        var url: String
    }

    func save() -> Data? {
        try? JSONEncoder().encode(items.map { SavedPage(id: $0, url: pages[$0] ?? "") })
    }

    func load(_ data: Data) {
        let saved = (try? JSONDecoder().decode([SavedPage].self, from: data)) ?? []
        for page in saved {
            ids.skip(past: page.id)
            pages[page.id] = page.url
        }
    }
}

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

/// What one bubble showing a page keeps for itself: the address being typed.
@Observable
@MainActor
final class AddressDraft: FocusTaking {
    var text = ""
    /// Whether the address field should take the keyboard focus when next shown.
    @ObservationIgnored var focusPending: Bool

    init(focusPending: Bool) {
        self.focusPending = focusPending
    }
}

struct WebContent: View {
    let app: WebApp
    let item: ItemID
    let draft: AddressDraft?
    @FocusState private var focused: Bool

    var body: some View {
        if let url = app.url(of: item) {
            PageView(app: app, item: item, source: PageSource(url))
        } else {
            addressField
        }
    }

    private var addressField: some View {
        let text = Binding(
            get: { draft?.text ?? "" },
            set: { draft?.text = $0 }
        )
        return VStack(spacing: 12) {
            Image(systemName: "safari")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            TextField("Paste a link, then press Return", text: text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { app.open(text.wrappedValue, in: item) }
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if let draft, draft.focusPending {
                draft.focusPending = false
                focused = true
                placeCursorAtEnd()
            }
        }
    }
}

/// What a page shows: a web page, or a YouTube video in its embedded player.
enum PageSource: Hashable {
    case web(URL)
    case video(id: String)

    init(_ url: URL) {
        self = youTubeID(url).map { .video(id: $0) } ?? .web(url)
    }
}

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
                let finished =
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
                app.stoppedLoading(item, finished: finished)
            }
    }

    /// Waits for a load to finish, returning whether it did. A failed load
    /// shows in the page itself, and one cut short is no longer wanted.
    private static func finishes(
        _ events: some AsyncSequence<WebPage.NavigationEvent, any Error>
    ) async -> Bool {
        do {
            for try await event in events where event == .finished {
                return true
            }
        } catch {}
        return false
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
