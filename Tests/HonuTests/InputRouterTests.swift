import Foundation
import Testing

@testable import Honu

@MainActor
struct InputRouterTests {
    private func shell() -> Shell {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "honu-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "state.json")
        return Shell(size: CGSize(width: 1200, height: 800), storeURL: url)
    }

    private func key(_ text: String, command: Bool = false, control: Bool = false) -> InputEvent {
        .key(text: text, unmodified: text, command: command, control: control)
    }

    @Test func rightClickingTheTurtleOpensTheMenuAndEscapeClosesIt() throws {
        let shell = shell()
        let router = InputRouter(shell: shell)
        let turtle = shell.turtle.center
        try #require(shell.turtle.contains(turtle))
        #expect(!router.handle(.escape, typing: false), "took Escape with no menu open")

        #expect(router.handle(.rightPress(at: turtle), typing: false))
        #expect(shell.menu != nil)
        #expect(router.handle(.escape, typing: false))
        #expect(shell.menu == nil)

        // Right-clicking elsewhere closes the menu, and is taken only then.
        #expect(router.handle(.rightPress(at: turtle), typing: false))
        #expect(router.handle(.rightPress(at: CGPoint(x: 900, y: 100)), typing: false))
        #expect(shell.menu == nil)
        #expect(!router.handle(.rightPress(at: CGPoint(x: 900, y: 100)), typing: false))
    }

    @Test func aPressRaisesTheBubbleButGoesOn() {
        let shell = shell()
        let target = ViewTarget(app: AppID("notes"), item: ItemID(rawValue: 1))
        let below = shell.stage.add(
            target: target, center: CGPoint(x: 400, y: 300), appearance: Appearance(),
            viewState: nil)
        shell.stage.add(
            target: target, center: CGPoint(x: 700, y: 300), appearance: Appearance(),
            viewState: nil)
        #expect(!InputRouter(shell: shell).handle(.press(at: below.center), typing: false))
        #expect(shell.stage.bubbles.last === below)
    }

    @Test func textGoesToTheNewBubbleOnlyWhenNothingElseTakesIt() throws {
        let shell = shell()
        let router = InputRouter(shell: shell)
        shell.start(AppID("notes"))
        let bubble = try #require(shell.stage.bubbles.last)
        let notes = try #require(shell.registry.app(AppID("notes")) as? NotesApp)

        #expect(!router.handle(key("a"), typing: true), "took text a field has")
        #expect(!router.handle(key("a", command: true), typing: false), "took a shortcut")
        #expect(!router.handle(key("a", control: true), typing: false), "took a shortcut")
        #expect(!router.handle(key("\r"), typing: false), "took Return")
        #expect(router.handle(key("hi"), typing: false))
        #expect(notes.notes[bubble.target.item] == "hi")
    }

    @Test func commandZUndoesADeleteUnlessAFieldWantsIt() throws {
        let shell = shell()
        let router = InputRouter(shell: shell)
        #expect(!router.handle(key("z", command: true), typing: false), "nothing to undo")
        shell.start(AppID("notes"))
        let bubble = try #require(shell.stage.bubbles.last)
        shell.dragBubble(bubble, by: CGSize(width: 60, height: 0), pointer: bubble.center)
        let mouth = shell.octopus.middle
        shell.dragBubble(bubble, by: CGSize(width: 60, height: 0), pointer: mouth)
        shell.endBubbleDrag(pointer: mouth)
        #expect(bubble.isSwallowed)

        #expect(!router.handle(key("z", command: true), typing: true))
        #expect(bubble.isSwallowed)
        #expect(router.handle(key("z", command: true), typing: false))
        #expect(!bubble.isSwallowed)
    }
}
