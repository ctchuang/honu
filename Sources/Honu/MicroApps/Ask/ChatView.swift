import SwiftUI

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
