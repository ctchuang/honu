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
    func newViewState(for item: ItemID, fresh: Bool) -> AnyObject? {
        ChatViewState(focusPending: fresh)
    }

    func content(of item: ItemID, viewState: AnyObject?) -> AnyView {
        guard let chat = chats[item] else { return AnyView(EmptyView()) }
        let state = viewState as? ChatViewState ?? ChatViewState(focusPending: false)
        return AnyView(ChatView(app: self, chat: chat, state: state))
    }

    /// Text typed before the chat's field took the focus goes to the field
    /// it shows first: the key's, or the question's.
    func typeAhead(_ text: String, into item: ItemID, viewState: AnyObject?) {
        guard let chat = chats[item] else { return }
        if services.apiKey.value == nil {
            (viewState as? ChatViewState)?.keyDraft += text
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

/// How an asked question came to an end, for the bubble to show.
enum Outcome: Equatable {
    /// The whole answer arrived.
    case answered
    /// The request failed or the key was refused; the user has to act.
    case needsAttention
}

/// One question for Claude and its answer.
@Observable
@MainActor
final class Chat {
    enum Status: Equatable {
        /// Waiting for a question, with why the last try failed, if it did.
        case typing(error: String?)
        /// Asked, with no words of the answer yet.
        case thinking
        case answering
        case done
        /// Stopped partway through the answer.
        case failed(String)
    }

    var question = ""
    /// The bubble's label, once a question has been asked.
    private(set) var title: String?
    private(set) var answer = ""
    private(set) var status = Status.typing(error: nil)
    @ObservationIgnored private(set) var stream: AnswerStream?
    /// Why the API refused the key, shown until another key is entered.
    var keyError: String?
    /// Set with `keyError` until the refused key has been forgotten.
    @ObservationIgnored var keyRejected = false
    /// Counts the times the chat needed the user to type again, after a
    /// failure or a refused key, so its views know to take the focus.
    private(set) var focusRequests = 0
    /// How tall the content is, as last laid out, for the panel to fit it.
    var contentHeight: CGFloat = 0

    init() {}

    /// A chat as it was saved. Without an answer, the question can simply
    /// be sent again.
    init(question: String, title: String?, answer: String, error: String?) {
        self.question = question
        self.title = title
        self.answer = answer
        status =
            answer.isEmpty
            ? .typing(error: error) : error.map(Status.failed) ?? .done
    }

    var isBusy: Bool {
        status == .thinking || status == .answering
    }

    /// Why the last try failed, as saved: a question still being answered
    /// when Honu quits is saved as interrupted.
    var savedError: String? {
        switch status {
        case .typing(let error): error
        case .thinking: "Honu quit before Claude answered."
        case .answering: "Honu quit before the answer was finished."
        case .done: nil
        case .failed(let message): message
        }
    }

    /// Sends the question to Claude through `claude`.
    func ask(_ claude: any ClaudeClient, apiKey: String) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        stream = claude.ask(apiKey: apiKey, question: question)
        status = .thinking
        title = shortLabel(question)
    }

    /// Takes in whatever the answer stream has delivered, and reports how
    /// the question ended if it just did.
    func poll() -> Outcome? {
        guard let stream else { return nil }
        let (events, isClosed) = stream.take()
        for event in events {
            switch event {
            case .text(let text):
                answer += text
                status = .answering
            case .done:
                status = .done
                self.stream = nil
                return .answered
            case .failed(let message):
                fail(message)
                return .needsAttention
            case .keyRejected(let message):
                keyError = message
                keyRejected = true
                status = .typing(error: nil)
                self.stream = nil
                focusRequests += 1
                return .needsAttention
            }
        }
        if isClosed {
            fail("The answer stopped unexpectedly.")
            return .needsAttention
        }
        return nil
    }

    /// Ends the stream with `message`. Before any answer arrived, the
    /// question can simply be sent again.
    private func fail(_ message: String) {
        stream = nil
        if answer.isEmpty {
            status = .typing(error: message)
            focusRequests += 1
        } else {
            status = .failed(message)
        }
    }
}

/// What one bubble showing a chat keeps for itself.
@MainActor
final class ChatViewState: FocusTaking {
    /// What is typed into the key field before it is entered.
    var keyDraft = ""
    /// Whether the next text field shown should take the keyboard focus.
    var focusPending: Bool
    /// The chat's `focusRequests` this view has answered.
    private var focusRequestsSeen = 0

    init(focusPending: Bool) {
        self.focusPending = focusPending
    }

    /// Notes any new request of the chat for the focus, and returns whether
    /// the field shown now should take it, which it then does.
    func focusDue(after focusRequests: Int) -> Bool {
        if focusRequestsSeen != focusRequests {
            focusRequestsSeen = focusRequests
            focusPending = true
        }
        defer { focusPending = false }
        return focusPending
    }
}

/// Shows a chat: a field for the API key if there is none, then one for the
/// question, then the answer as it streams in.
struct ChatView: View {
    let app: AskApp
    let chat: Chat
    let state: ChatViewState
    @FocusState private var focused: Bool

    private static let error = Color(red: 0.75, green: 0.24, blue: 0.2)
    private static let ink = Color(white: 0.12)

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    chat.contentHeight = $0
                }
        }
        .defaultScrollAnchor(.bottom)
        .scrollIndicators(.automatic)
        .onAppear(perform: takeFocusIfDue)
        .onChange(of: chat.focusRequests) { takeFocusIfDue() }
        .onChange(of: app.services.apiKey.value) { takeFocusIfDue(force: true) }
    }

    @ViewBuilder
    private var content: some View {
        if app.services.apiKey.value == nil {
            keyForm
        } else if case .typing(let error) = chat.status {
            questionForm(error: error)
        } else {
            answer
        }
    }

    private var keyForm: some View {
        let draft = Binding(get: { state.keyDraft }, set: { state.keyDraft = $0 })
        return VStack(alignment: .leading, spacing: 8) {
            if let error = chat.keyError {
                Text("That key didn't work: \(error)").foregroundStyle(Self.error)
            } else {
                Text("Paste a Claude API key to ask questions.").foregroundStyle(Self.ink)
            }
            SecureField("sk-ant-…", text: draft)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit {
                    app.setKey(state.keyDraft)
                    state.keyDraft = ""
                }
            Text("It is kept until Honu quits. To skip this, put ANTHROPIC_API_KEY in .env.")
                .font(.caption)
                .foregroundStyle(Self.ink.opacity(0.6))
        }
    }

    private func questionForm(error: String?) -> some View {
        let question = Binding(get: { chat.question }, set: { chat.question = $0 })
        return VStack(alignment: .leading, spacing: 8) {
            if let error {
                Text(error).foregroundStyle(Self.error)
            }
            TextField("Ask Claude…", text: question)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(Self.ink)
                .focused($focused)
                .onSubmit { app.ask(chat) }
        }
        .padding(.top, 4)
    }

    private var answer: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The title shows the question, unless it had to be shortened.
            if shortLabel(chat.question) != chat.question {
                Text(chat.question).foregroundStyle(Self.ink.opacity(0.6))
            }
            if !chat.answer.isEmpty {
                Text(verbatim: chat.answer)
                    .font(.system(size: 16))
                    .foregroundStyle(Self.ink)
                    .textSelection(.enabled)
            }
            switch chat.status {
            case .thinking:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Thinking…").foregroundStyle(Self.ink.opacity(0.6))
                }
            case .failed(let message):
                Text(message).foregroundStyle(Self.error)
            default:
                EmptyView()
            }
        }
    }

    private func takeFocusIfDue() {
        takeFocusIfDue(force: false)
    }

    /// Puts the cursor in the field shown, once per request for the focus.
    private func takeFocusIfDue(force: Bool) {
        if state.focusDue(after: chat.focusRequests) || force {
            focused = true
            placeCursorAtEnd()
        }
    }
}
