import SwiftUI

/// The Ask AI microapp: any number of chats with Claude. In a chat's bubble
/// you type a question, and Claude's answer streams into the panel, which
/// grows to fit it.
@Observable
@MainActor
final class AskApp: MicroApp {
    let id = AppID("ask")
    let menuLabel = "Ask AI"

    /// The model: each chat.
    private(set) var chats: [ItemID: Chat] = [:]
    @ObservationIgnored private var ids = ItemIDs()
    @ObservationIgnored let services: Services

    /// The label of a chat with no question asked yet.
    static let emptyLabel = "Ask"
    static let panelWidth: CGFloat = 400
    /// Panel height while asking for a key or a question.
    static let startHeight: CGFloat = 150
    /// The tallest the panel grows; longer answers scroll.
    static let maxHeight: CGFloat = 560
    /// Panel height not taken by the content: the title bar and the margins.
    static let chromeHeight: CGFloat = 70

    init(services: Services) {
        self.services = services
    }

    /// Starts a chat with no question yet.
    func create() -> ItemID {
        let id = ids.next()
        chats[id] = Chat()
        return id
    }

    /// A panel tall enough for what the chat shows, within limits.
    func appearance(of item: ItemID) -> Appearance {
        let content = chats[item]?.contentHeight ?? 0
        let height = min(max(content + Self.chromeHeight, Self.startHeight), Self.maxHeight)
        return Appearance(
            tint: Color(white: 0.98).opacity(0.55),
            closedSide: 120,
            panelSize: CGSize(width: Self.panelWidth, height: height),
            textColor: Color(white: 0.12)
        )
    }

    /// A short label for a chat's bubble: its question, once asked.
    func title(of item: ItemID) -> String {
        chats[item]?.title ?? Self.emptyLabel
    }

    /// Whether Claude is still working on a chat's answer.
    func isBusy(_ item: ItemID) -> Bool {
        chats[item]?.isBusy ?? false
    }

    /// Takes in whatever the answer streams have delivered. A chat's bubbles
    /// rise when its answer is in, and wobble when something needs the user.
    func update(_ context: Context) {
        for (item, chat) in chats {
            switch chat.poll() {
            case .answered: context.play(.rise, for: item)
            case .needsAttention: context.play(.wobble, for: item)
            case nil: break
            }
            // Ask for another key, then let the same question be sent again.
            if chat.keyError != nil, chat.keyRejected {
                chat.keyRejected = false
                services.apiKey.value = nil
            }
        }
    }

    /// A new chat is for asking, so its bubble starts with the cursor in it.
    func newViewState(for item: ItemID, fresh: Bool) -> ChatViewState {
        ChatViewState(focusPending: fresh)
    }

    func content(of item: ItemID, viewState: ChatViewState) -> some View {
        if let chat = chats[item] {
            ChatView(app: self, chat: chat, state: viewState)
        }
    }

    /// Text typed before the chat's field took the focus goes to the field
    /// it shows first: the key's, or the question's.
    func typeAhead(_ text: String, into item: ItemID, viewState: ChatViewState) {
        guard let chat = chats[item] else { return }
        if services.apiKey.value == nil {
            viewState.keyDraft += text
        } else if case .typing = chat.status {
            chat.question += text
        }
    }

    /// Sends `chat`'s question to Claude, if there is a key and a question.
    func ask(_ chat: Chat) {
        guard let key = services.apiKey.value else { return }
        chat.ask(services.claude, apiKey: key)
    }

    /// Takes a key the user entered, which clears a refused key's error.
    func setKey(_ key: String) {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        services.apiKey.value = key
        for chat in chats.values {
            chat.keyError = nil
        }
    }

    /// Forgets a chat, which also stops its answer from streaming in.
    func remove(_ item: ItemID) {
        chats[item]?.stream?.cancel()
        chats[item] = nil
    }

    var items: [ItemID] { chats.keys.sorted() }

    /// A chat as saved between launches. A stream cannot be saved, so a
    /// question still being answered is saved as interrupted.
    private struct SavedChat: Codable {
        var id: ItemID
        var question: String
        var title: String?
        var answer: String
        /// Why the last try failed, if it did.
        var error: String?
    }

    func save() -> Data? {
        let saved = items.compactMap { id in
            chats[id].map {
                SavedChat(
                    id: id, question: $0.question, title: $0.title, answer: $0.answer,
                    error: $0.savedError)
            }
        }
        return try? JSONEncoder().encode(saved)
    }

    func load(_ data: Data) {
        let saved = (try? JSONDecoder().decode([SavedChat].self, from: data)) ?? []
        for chat in saved {
            ids.skip(past: chat.id)
            chats[chat.id] = Chat(
                question: chat.question, title: chat.title, answer: chat.answer, error: chat.error)
        }
    }
}
