import Foundation
import Testing

@testable import Honu

/// A stand-in for Claude Code: it records the questions asked and keeps each
/// answer stream, for the test to answer.
@MainActor
final class FakeClaude: ClaudeClient {
    private(set) var requests: [ClaudeRequest] = []
    private(set) var streams: [AnswerStream] = []
    /// The prompts asked, in order.
    var asked: [String] { requests.map(\.prompt) }

    func ask(_ request: ClaudeRequest) -> AnswerStream {
        requests.append(request)
        let stream = AnswerStream()
        streams.append(stream)
        return stream
    }
}

@MainActor
struct AskAppTests {
    private let claude = FakeClaude()

    private func app() -> AskApp {
        AskApp(services: Services(claude: claude))
    }

    /// A new chat in `asks` that has asked `question`.
    private func ask(_ asks: AskApp, _ question: String) -> ItemID {
        let item = asks.create()
        let chat = asks.chats[item]!
        chat.question = question
        asks.ask(chat)
        return item
    }

    /// Runs `update` on `asks` and returns what it asked of the bubbles.
    private func update(_ asks: AskApp) -> [Effect] {
        let context = Context(app: asks.id)
        asks.update(context)
        return context.effects
    }

    @Test func finishedAnswersAndFailuresReachTheBubbles() {
        let asks = app()
        let item = ask(asks, "  Why is the sea salty? ")
        #expect(claude.asked == ["Why is the sea salty?"])
        #expect(asks.title(of: item) == "Why is the sea salty?")
        #expect(asks.isBusy(item))

        claude.streams[0].send(.text("Salt."))
        #expect(update(asks).isEmpty)
        claude.streams[0].send(.done)
        let target = ViewTarget(app: asks.id, item: item)
        #expect(update(asks) == [.motion(target, .rise)])
        #expect(!asks.isBusy(item))
        #expect(asks.chats[item]?.answer == "Salt.")

        // A chat whose stream breaks off before any answer needs the user.
        let other = ask(asks, "And why is it wet?")
        claude.streams[1].close()
        #expect(update(asks) == [.motion(ViewTarget(app: asks.id, item: other), .wobble)])
        #expect(asks.chats[other]?.status == .typing(error: "The answer stopped unexpectedly."))
    }

    @Test func nothingIsAskedWithoutAQuestion() {
        let blank = app()
        _ = ask(blank, "   ")
        #expect(claude.asked.isEmpty)
    }

    @Test func chatsComeBackAfterARelaunchWithInterruptedAnswersFailed() throws {
        let asks = app()
        let done = ask(asks, "Why is the sea salty?")
        let thinking = ask(asks, "Why is it wet?")
        let answering = ask(asks, "Why is it blue?")
        claude.streams[0].send(.text("Salt."))
        claude.streams[0].send(.done)
        claude.streams[2].send(.text("Light"))
        _ = update(asks)

        let restored = app()
        restored.load(try #require(asks.save()))
        #expect(restored.items == [done, thinking, answering])
        #expect(restored.chats[done]?.status == .done)
        #expect(restored.chats[done]?.answer == "Salt.")
        #expect(restored.title(of: done) == "Why is the sea salty?")
        // No answer yet: the question can be sent again.
        if case .typing(let error) = restored.chats[thinking]?.status {
            #expect(error != nil)
        } else {
            Issue.record("an unanswered question cannot be sent again")
        }
        #expect(restored.chats[thinking]?.question == "Why is it wet?")
        // Part of an answer: kept, marked as cut off.
        if case .failed = restored.chats[answering]?.status {
        } else {
            Issue.record("a cut-off answer was not marked as failed")
        }
        #expect(restored.chats[answering]?.answer == "Light")
        #expect(!restored.isBusy(answering))
        #expect(restored.create() > answering)
    }

    @Test func everyViewTakesTheFocusOncePerRequest() {
        let asks = app()
        let item = ask(asks, "Why?")
        let chat = asks.chats[item]!
        let (a, b) = (ChatViewState(focusPending: false), ChatViewState(focusPending: false))
        #expect(!a.focusDue(after: chat.focusRequests), "took the focus with nothing new")

        claude.streams[0].send(.failed("Overloaded"))
        _ = update(asks)
        #expect(a.focusDue(after: chat.focusRequests) && b.focusDue(after: chat.focusRequests))
        #expect(!a.focusDue(after: chat.focusRequests), "took the focus twice for one request")
        // A new chat's own view takes it once to begin with.
        let fresh = ChatViewState(focusPending: true)
        #expect(fresh.focusDue(after: 0) && !fresh.focusDue(after: 0))
    }

    @Test func thePanelGrowsWithTheAnswerUpToALimit() {
        let asks = app()
        let item = asks.create()
        #expect(asks.appearance(of: item).panelSize.height == AskApp.startHeight)
        asks.chats[item]?.contentHeight = 300
        #expect(asks.appearance(of: item).panelSize.height == 300 + AskApp.chromeHeight)
        asks.chats[item]?.contentHeight = 5000
        #expect(asks.appearance(of: item).panelSize.height == AskApp.maxHeight)
    }

    @Test func deletingAChatStopsItsAnswer() {
        let asks = app()
        let item = ask(asks, "Why?")
        asks.remove(item)
        #expect(asks.items.isEmpty)
        #expect(update(asks).isEmpty)
    }
}
