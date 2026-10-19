import Foundation
import Testing

@testable import Honu

/// What the views get from the shell, rather than from the microapps.
@MainActor
struct ShellTests {
    @Test func everyBubbleKeepsItsOwnUndoHistory() {
        let shell = makeShell()
        let target = ViewTarget(app: AppID("notes"), item: ItemID(rawValue: 1))
        let first = shell.stage.add(
            target: target, center: CGPoint(x: 400, y: 300), appearance: Appearance(),
            viewState: nil)
        let second = shell.stage.add(
            target: target, center: CGPoint(x: 700, y: 300), appearance: Appearance(),
            viewState: nil)
        let history = shell.undoManager(for: first)
        #expect(shell.undoManager(for: first) === history)
        #expect(shell.undoManager(for: second) !== history)
    }

    @Test func theMenuListsEveryMicroappInOrder() {
        #expect(
            makeShell().menuChoices.map(\.label) == [
                "Add Note", "Ask AI", "Open Web Page", "Microapp Probe",
            ])
    }

    @Test func theMenuStaysOnScreen() {
        let screen = CGSize(width: 1200, height: 800)
        #expect(
            TurtleMenu.corner(at: CGPoint(x: 100, y: 200), in: screen) == CGPoint(x: 100, y: 200))
        let corner = TurtleMenu.corner(at: CGPoint(x: 1190, y: 790), in: screen)
        #expect(corner.x + TurtleMenu.width < screen.width)
        #expect(corner.y + TurtleMenu.estimatedHeight < screen.height)
    }

    @Test func aBubbleShowsWhatItsMicroappSays() throws {
        let shell = makeShell()
        shell.start(AppID("notes"))
        let bubble = try #require(shell.stage.bubbles.last)
        #expect(shell.title(of: bubble) == NotesApp.emptyLabel)
        #expect(shell.appearance(of: bubble).closedSide == 120)
        #expect(shell.content(of: bubble) != nil)

        shell.toggle(bubble)
        let opened = bubble.isOpen
        shell.toggle(bubble)
        #expect(bubble.isOpen != opened)
    }
}
