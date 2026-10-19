import Foundation
import Testing

@testable import Honu

@MainActor
struct TypeAheadTests {
    private let claude = FakeClaude()

    private func shell(key: String? = "sk-ant-test") -> Shell {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "honu-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "state.json")
        return Shell(
            size: CGSize(width: 1200, height: 800), storeURL: url,
            services: Services(apiKey: ApiKey(key), claude: claude))
    }

    @Test func textTypedWhileANoteFliesOutGoesIntoIt() throws {
        let shell = shell()
        #expect(!shell.type("x"), "took text with no bubble to give it to")
        shell.start(AppID("notes"))
        let bubble = try #require(shell.stage.bubbles.last)
        #expect(shell.type("Gro"))
        #expect(shell.type("ceries"))
        let notes = try #require(shell.registry.app(AppID("notes")) as? NotesApp)
        #expect(notes.notes[bubble.target.item] == "Groceries")

        // Once the note's field has the focus, typing goes there by itself.
        (bubble.viewState as? NoteViewState)?.focusPending = false
        #expect(!shell.type("!"))
        #expect(notes.notes[bubble.target.item] == "Groceries")
    }

    @Test func onlyTheNewestBubbleTakesIt() throws {
        let shell = shell()
        shell.start(AppID("notes"))
        let first = try #require(shell.stage.bubbles.last)
        shell.start(AppID("notes"))
        let second = try #require(shell.stage.bubbles.last)
        #expect(shell.type("hi"))
        let notes = try #require(shell.registry.app(AppID("notes")) as? NotesApp)
        #expect(notes.notes[first.target.item] == "")
        #expect(notes.notes[second.target.item] == "hi")
    }

    @Test func anAskBubbleTakesItAsTheKeyOrTheQuestion() throws {
        let withKey = shell()
        withKey.start(AppID("ask"))
        let question = try #require(withKey.stage.bubbles.last)
        #expect(withKey.type("Why?"))
        let asks = try #require(withKey.registry.app(AppID("ask")) as? AskApp)
        #expect(asks.chats[question.target.item]?.question == "Why?")

        let withoutKey = shell(key: nil)
        withoutKey.start(AppID("ask"))
        let key = try #require(withoutKey.stage.bubbles.last)
        #expect(withoutKey.type("sk-ant-"))
        #expect((key.viewState as? ChatViewState)?.keyDraft == "sk-ant-")
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
