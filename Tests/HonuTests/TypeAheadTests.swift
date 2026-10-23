import Foundation
import Testing

@testable import Honu

@MainActor
struct TypeAheadTests {
    private let claude = FakeClaude()

    private func shell() -> Shell {
        makeShell(claude: claude)
    }

    @Test func textTypedWhileANoteFliesOutGoesIntoIt() throws {
        let shell = shell()
        #expect(!shell.type("x"), "took text with no bubble to give it to")
        shell.start(AppID("notes"))
        let bubble = try #require(shell.stage.bubbles.last)
        #expect(shell.type("Gro"))
        #expect(shell.type("ceries"))
        #expect(shell.notes.notes[bubble.target.item] == "Groceries")

        // Once the note's field has the focus, typing goes there by itself.
        (bubble.viewState as? NoteViewState)?.focusPending = false
        #expect(!shell.type("!"))
        #expect(shell.notes.notes[bubble.target.item] == "Groceries")
    }

    @Test func onlyTheNewestBubbleTakesIt() throws {
        let shell = shell()
        shell.start(AppID("notes"))
        let first = try #require(shell.stage.bubbles.last)
        shell.start(AppID("notes"))
        let second = try #require(shell.stage.bubbles.last)
        #expect(shell.type("hi"))
        #expect(shell.notes.notes[first.target.item] == "")
        #expect(shell.notes.notes[second.target.item] == "hi")
    }

    @Test func anAskBubbleTakesItAsTheQuestion() throws {
        let shell = shell()
        shell.start(AppID("ask"))
        let question = try #require(shell.stage.bubbles.last)
        #expect(shell.type("Why?"))
        #expect(shell.asks.chats[question.target.item]?.question == "Why?")
    }

    @Test func aWebBubbleTakesItAsTheAddress() throws {
        let shell = shell()
        shell.start(AppID("web"))
        let bubble = try #require(shell.stage.bubbles.last)
        #expect(shell.type("en.wikipedia.org"))
        #expect((bubble.viewState as? AddressDraft)?.text == "en.wikipedia.org")
    }

    @Test func aSwallowedBubbleTakesNothing() throws {
        let shell = shell()
        shell.start(AppID("notes"))
        let bubble = try #require(shell.stage.bubbles.last)
        shell.stage.swallow(bubble, into: .zero)
        #expect(!shell.type("lost"))
    }
}
