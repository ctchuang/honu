import SwiftUI

/// Shows a chat: a field for the question, then the answer as it streams in.
struct ChatView: View {
    let app: AskApp
    let chat: Chat
    let state: FocusRequestState
    @FocusState private var focused: Bool

    private static let error = Color(red: 0.75, green: 0.24, blue: 0.2)
    private static let ink = AskApp.ink

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
        .takesFocus(state, requests: chat.focusRequests, $focused)
    }

    @ViewBuilder
    private var content: some View {
        if case .typing(let error) = chat.status {
            questionForm(error: error)
        } else {
            answer
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
}
