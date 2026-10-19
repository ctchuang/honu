import Foundation
import Testing

@testable import Honu

/// What the views get from the shell, rather than from the microapps.
@MainActor
struct ShellTests {
    @Test func theMenuListsEveryMicroappInOrder() {
        #expect(makeShell().menuChoices.map(\.label) == ["Add Note", "Ask AI", "Open Web Page"])
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
