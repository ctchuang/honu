import Foundation
import Testing

@testable import Honu

private let screen = CGSize(width: 1000, height: 700)

@MainActor
struct SpriteTests {
    @Test func pixelAtStaysInsideTheGrid() {
        let grid = PixelGrid(["ab..", "cdef"])
        let origin = CGPoint(x: 100, y: 50)
        #expect(grid.size == CGSize(width: 4 * spritePixel, height: 2 * spritePixel))
        #expect(grid.pixel(at: origin, origin: origin)! == (0, 0))
        let inside = CGPoint(x: origin.x + 3.5 * spritePixel, y: origin.y + 1.5 * spritePixel)
        #expect(grid.pixel(at: inside, origin: origin)! == (3, 1))
        #expect(
            grid.pixel(at: CGPoint(x: origin.x + 4 * spritePixel, y: origin.y), origin: origin)
                == nil)
        #expect(grid.pixel(at: CGPoint(x: origin.x - 0.1, y: origin.y), origin: origin) == nil)
        #expect(grid.replacing([(2, 0)], with: "x").pixel(2, 0) == "x")
    }
}

@MainActor
struct TurtleTests {
    /// The middle of sprite pixel (`x`, `y`) of `turtle`.
    private func pixel(_ turtle: Turtle, _ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(
            x: turtle.origin.x + (x + 0.5) * spritePixel,
            y: turtle.origin.y + (y + 0.5) * spritePixel)
    }

    @Test func spriteRowsHaveEqualLength() {
        #expect(Turtle.grid.rows.allSatisfy { $0.count == Turtle.grid.columns })
    }

    @Test func hitTestIgnoresTransparentPixels() {
        let turtle = Turtle(stageSize: screen)
        #expect(turtle.contains(pixel(turtle, 8, 4)), "shell")
        #expect(!turtle.contains(pixel(turtle, 0, 0)), "empty corner")
        #expect(!turtle.contains(pixel(turtle, 30, 4)), "outside the sprite")
    }

    @Test func draggedTurtleStaysOnScreen() {
        let turtle = Turtle(stageSize: screen)
        let size = Turtle.grid.size
        let corner = CGPoint(x: Turtle.margin, y: screen.height - Turtle.margin - size.height)
        #expect(turtle.origin == corner)
        #expect(turtle.rest == nil)
        turtle.move(to: CGPoint(x: corner.x + 300, y: corner.y - 200))
        #expect(turtle.origin == CGPoint(x: corner.x + 300, y: corner.y - 200))
        turtle.move(to: CGPoint(x: 5000, y: 5000))
        #expect(
            turtle.origin == CGPoint(x: screen.width - size.width, y: screen.height - size.height))
    }

    @Test func openMouthIsOnTheHead() {
        for (x, y) in Turtle.openMouth {
            #expect(["K", "O"].contains(Turtle.grid.pixel(x, y)), "(\(x), \(y))")
        }
    }

    @Test func spittingOpensTheMouthForAMoment() {
        let turtle = Turtle(stageSize: screen)
        let mouth = turtle.spit()
        #expect(
            turtle.contains(CGPoint(x: mouth.x - 1, y: mouth.y + 1)), "mouth is not on the head")
        let time = now()
        #expect(turtle.grid(at: time).pixel(22, 7) == "E")
        #expect(turtle.grid(at: time + 1).pixel(22, 7) != "E")
    }
}

@MainActor
struct OctopusTests {
    private let turtle = CGPoint(x: 60, y: 650)

    @Test func spriteRowsHaveEqualLength() {
        let rows = Octopus.head + Octopus.tentacles.flatMap { $0 }
        #expect(rows.allSatisfy { $0.count == Octopus.head[0].count })
    }

    @Test func risesAwayFromTheTurtleOnlyWhileNeeded() {
        let octopus = Octopus(stageSize: screen)
        #expect(!octopus.contains(octopus.middle), "visible while idle")

        octopus.summon(true, turtle: turtle)
        let middle = octopus.middle
        #expect(octopus.contains(middle) && octopus.inReach(middle))
        #expect(middle.x > screen.width / 2, "not across from the turtle")
        #expect(octopus.origin.y + octopus.size.height <= screen.height)

        octopus.summon(false, turtle: turtle)
        #expect(!octopus.inReach(middle), "still there after the drag")
    }

    @Test func swallowedBubbleCanBeBroughtBackUntilItIsTooLate() {
        let octopus = Octopus(stageSize: screen)
        octopus.summon(true, turtle: turtle)
        let (bubble, home, time) = (BubbleID(rawValue: 7), CGPoint(x: 400, y: 300), 1000.0)
        octopus.swallow(bubble, home: home, at: time)
        octopus.summon(false, turtle: turtle)
        #expect(octopus.forget(at: time + 1).isEmpty && octopus.canUndo)
        #expect(octopus.inReach(octopus.middle), "hid while it could undo")
        // The hint above it takes clicks too, but only while it applies.
        #expect(octopus.contains(octopus.hintCenter), "hint does not take clicks")

        let spat = octopus.spitBack(at: time + 1)
        #expect(spat?.bubble == bubble && spat?.home == home)
        #expect(!octopus.contains(octopus.hintCenter), "hint takes clicks with nothing to undo")
        #expect(!octopus.canUndo)

        octopus.swallow(bubble, home: home, at: time + 2)
        #expect(octopus.forget(at: time + 2 + Octopus.undoSeconds + 1) == [bubble])
        #expect(!octopus.canUndo, "kept the bubble too long")
        #expect(octopus.spitBack(at: time + 10) == nil)
    }

    @Test func picksTheCornerOnlyWhileOutOfSight() {
        let octopus = Octopus(stageSize: screen)
        octopus.summon(true, turtle: CGPoint(x: 900, y: 650))
        #expect(!octopus.isRight)
        // The turtle crossing over while it is up does not move it.
        octopus.summon(true, turtle: turtle)
        #expect(!octopus.isRight)
    }
}
