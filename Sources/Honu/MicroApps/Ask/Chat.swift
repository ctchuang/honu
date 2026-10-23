import Foundation
import Observation

/// How an asked question came to an end, for the bubble to show.
enum Outcome: Equatable {
    /// The whole answer arrived.
    case answered
    /// The request failed; the user has to act.
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
    /// Counts the times the chat needed the user to type again, after a
    /// failure, so its views know to take the focus.
    private(set) var focusRequests = 0
    /// How tall the content is, as last laid out, for the bubble to fit it.
    var contentHeight: CGFloat = 0

    /// What Claude is told about answering in a chat's bubble.
    static let systemPrompt = """
        You answer questions inside a small floating bubble on the user's desktop. \
        Keep answers short and to the point. Write plain text without Markdown, \
        since the bubble shows the raw text.
        """

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
    func ask(_ claude: any ClaudeClient) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        stream = claude.ask(ClaudeRequest(prompt: question, systemPrompt: Self.systemPrompt))
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
