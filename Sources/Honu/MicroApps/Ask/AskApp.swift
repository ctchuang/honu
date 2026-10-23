import SwiftUI

/// The Ask AI microapp: any number of chats with Claude. In a chat's bubble
/// you type a question, and Claude's answer streams into the bubble, which
/// grows to fit it.
@Observable
@MainActor
final class AskApp: MicroApp {
    let id = AppID("ask")
    let launcherLabel = "Ask AI"
    let launcherSymbol = "bubble.left.and.text.bubble.right"
    /// Asking Claude is to become feeding a bubble to the turtle, so Ask AI
    /// leaves the menu; chats already made stay.
    let isLaunchable = false

    /// The model: each chat.
    private(set) var chats = ItemTable<Chat>()
    @ObservationIgnored let services: Services

    /// The label of a chat with no question asked yet.
    static let emptyLabel = "Ask"
    static let width: CGFloat = 400
    /// The bubble's height while asking for a question.
    static let startHeight: CGFloat = 150
    /// The tallest the bubble grows; longer answers scroll.
    static let maxHeight: CGFloat = 560
    /// The bubble's height not taken by the content: the title bar and the margins.
    static let chromeHeight: CGFloat = 70
    /// The near-black a chat is written in, on its pale glass.
    static let ink = Color(white: 0.12)

    init(services: Services) {
        self.services = services
    }

    /// Starts a chat with no question yet.
    func create() -> ItemID {
        chats.insert(Chat())
    }

    /// A bubble tall enough for what the chat shows, within limits.
    func appearance(of item: ItemID) -> Appearance {
        let content = chats[item]?.contentHeight ?? 0
        let height = min(max(content + Self.chromeHeight, Self.startHeight), Self.maxHeight)
        return Appearance(
            tint: Color(white: 0.98).opacity(0.55),
            size: CGSize(width: Self.width, height: height),
            textColor: Self.ink
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
        for (item, chat) in chats.entries {
            switch chat.poll() {
            case .answered: context.play(.rise, for: item)
            case .needsAttention: context.play(.wobble, for: item)
            case nil: break
            }
        }
    }

    /// A new chat is for asking, so its bubble starts with the cursor in it.
    func newViewState(for item: ItemID, fresh: Bool) -> FocusRequestState {
        FocusRequestState(focusPending: fresh)
    }

    func content(of item: ItemID, viewState: FocusRequestState) -> some View {
        if let chat = chats[item] {
            ChatView(app: self, chat: chat, state: viewState)
        }
    }

    /// Text typed before the chat's field took the focus goes into its question.
    func typeAhead(_ text: String, into item: ItemID, viewState: FocusRequestState) {
        guard let chat = chats[item], case .typing = chat.status else { return }
        chat.question += text
    }

    /// Sends `chat`'s question to Claude, if there is one.
    func ask(_ chat: Chat) {
        chat.ask(services.claude)
    }

    /// Forgets a chat, which also stops its answer from streaming in.
    func remove(_ item: ItemID) {
        chats[item]?.stream?.cancel()
        chats.remove(item)
    }

    var items: [ItemID] { chats.items }

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
        chats.save {
            SavedChat(
                id: $0, question: $1.question, title: $1.title, answer: $1.answer,
                error: $1.savedError)
        }
    }

    func load(_ data: Data) {
        chats.load(data, as: SavedChat.self) {
            (
                $0.id,
                Chat(question: $0.question, title: $0.title, answer: $0.answer, error: $0.error)
            )
        }
    }
}
