import Foundation
import Testing

@testable import Honu

/// Honu moving to a screen of another size, as to another display.
@MainActor
struct ScreenTests {
    /// Moving from a 1200 by 800 screen to a 1000 by 700 one.
    private let smaller = CGSize(width: 1000, height: 700)

    @Test func bubblesKeepTheirPlaceInProportion() {
        let shell = makeShell()
        let bubble = shell.addNote(at: CGPoint(x: 600, y: 400))
        shell.resize(to: smaller)
        #expect(shell.stage.size == smaller)
        #expect(bubble.center == CGPoint(x: 500, y: 350))
    }

    @Test func bubblesStayOnScreen() {
        let shell = makeShell()
        let bubble = shell.addNote(at: CGPoint(x: 1000, y: 600))
        shell.resize(to: smaller)
        #expect(bubble.frame.maxX <= smaller.width)
        #expect(bubble.frame.maxY <= smaller.height)
    }

    @Test func resizedBubblesFitTheScreen() throws {
        let shell = makeShell()
        let bubble = shell.addNote(at: shell.stage.center)
        shell.stage.setUserSize(of: bubble, to: CGSize(width: 1100, height: 760), zoomed: false)
        shell.resize(to: smaller)
        let size = try #require(bubble.userSize)
        #expect(size.width <= smaller.width)
        #expect(size.height <= smaller.height)
    }

    @Test func spritesFollowTheScreen() {
        let shell = makeShell()
        shell.turtle.move(to: CGPoint(x: 1100, y: 100))
        shell.resize(to: smaller)
        #expect(shell.turtle.origin.x + shell.turtle.size.width <= smaller.width)
        #expect(shell.turtle.origin.y < 100)
        #expect(shell.octopus.origin.y + shell.octopus.size.height < smaller.height)
    }

    @Test func swallowedBubblesComeBackOnTheNewScreen() {
        let shell = makeShell()
        let bubble = shell.addNote(at: CGPoint(x: 900, y: 500))
        shell.drop(bubble)
        shell.resize(to: smaller)
        shell.undoDelete()
        #expect(bubble.destination.x + bubble.size.width / 2 <= smaller.width)
        #expect(bubble.destination.y + bubble.size.height / 2 <= smaller.height)
    }
}
