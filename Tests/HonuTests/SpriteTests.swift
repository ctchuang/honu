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

    @Test func onlyVisiblePixelsAreHit() {
        let grid = PixelGrid(["ab..", "cdef"])
        let origin = CGPoint(x: 100, y: 50)
        let at = { (x: CGFloat, y: CGFloat) in
            PixelGrid.point(CGPoint(x: x + 0.5, y: y + 0.5), origin: origin)
        }
        #expect(PixelGrid.point(.zero, origin: origin) == origin)
        #expect(grid.isOpaque(at: at(1, 0), origin: origin))
        #expect(!grid.isOpaque(at: at(2, 0), origin: origin), "hit a transparent pixel")
        #expect(grid.isOpaque(at: at(3, 1), origin: origin))
        #expect(!grid.isOpaque(at: at(4, 1), origin: origin), "hit past the edge")
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

    @Test func itBobsWhileIdleAndHopsWhenClicked() {
        let turtle = Turtle(stageSize: screen)
        // Idle, it rises a sprite pixel on every other bob.
        let bobs = Set(stride(from: 0.0, to: 4, by: 0.1).map { turtle.lift(at: $0) })
        #expect(bobs == [0, spritePixel])

        turtle.hop(at: 10)
        let peak = turtle.lift(at: 10 + Turtle.hopSeconds / 2)
        let height = CGFloat(Turtle.hopPixels) * spritePixel
        #expect(peak == height)
        let hop = stride(from: 10.0, to: 10 + Turtle.hopSeconds, by: 0.01).map {
            turtle.lift(at: $0)
        }
        #expect(hop.allSatisfy { $0 >= 0 && $0 <= peak })
        #expect(hop.allSatisfy { $0.truncatingRemainder(dividingBy: spritePixel) == 0 })
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

        #expect(octopus.offersHelp, "does not offer to recycle while summoned")

        octopus.summon(false, turtle: turtle)
        #expect(!octopus.inReach(middle), "still there after the drag")
        #expect(!octopus.offersHelp)
    }

    @Test func onlyThePixelsDrawnAtTheTimeAreHit() throws {
        let octopus = Octopus(stageSize: screen)
        octopus.summon(true, turtle: turtle)
        // A pixel visible in one frame of the swaying tentacles but not in the other.
        let (a, b) = (octopus.grid(at: 0), octopus.grid(at: 0.6))
        let rows = 0..<a.rows.count
        let columns = 0..<a.columns
        let pixel = try #require(
            rows.lazy.flatMap { y in columns.lazy.map { x in (x, y) } }
                .first { (a.pixel($0.0, $0.1) == ".") != (b.pixel($0.0, $0.1) == ".") })
        let point = PixelGrid.point(
            CGPoint(x: Double(pixel.0) + 0.5, y: Double(pixel.1) + 0.5), origin: octopus.origin)
        #expect(octopus.contains(point, at: 0) == (a.pixel(pixel.0, pixel.1) != "."))
        #expect(octopus.contains(point, at: 0.6) == (b.pixel(pixel.0, pixel.1) != "."))
    }

    @Test func swallowedBubbleCanBeBroughtBackUntilItIsTooLate() {
        let octopus = Octopus(stageSize: screen)
        octopus.summon(true, turtle: turtle)
        let (bubble, home, time) = (BubbleID(rawValue: 7), CGPoint(x: 400, y: 300), 1000.0)
        octopus.swallow(bubble, home: home, at: time)
        octopus.summon(false, turtle: turtle)
        #expect(octopus.forget(at: time + 1).isEmpty && octopus.canUndo)
        #expect(octopus.inReach(octopus.middle), "hid while it could undo")
        #expect(octopus.showsUndoHint && !octopus.offersHelp)
        // The hint above it takes clicks too, but only while it applies.
        let hint = octopus.hintCenter(at: time + 1)
        #expect(octopus.contains(hint, at: time + 1), "hint does not take clicks")

        let spat = octopus.spitBack(at: time + 1)
        #expect(spat?.morsels == [Octopus.Swallowed.Morsel(bubble: bubble, home: home)])
        #expect(!octopus.contains(hint, at: time + 1), "hint takes clicks with nothing to undo")
        #expect(!octopus.canUndo)

        octopus.swallow(bubble, home: home, at: time + 2)
        #expect(
            octopus.forget(at: time + 2 + Octopus.undoSeconds + 1).flatMap(\.bubbles) == [bubble])
        #expect(!octopus.canUndo, "kept the bubble too long")
        #expect(octopus.spitBack(at: time + 10) == nil)
    }

    @Test func aMicroappIsSwallowedWithItsBubblesInOneGulp() {
        let octopus = Octopus(stageSize: screen)
        octopus.summon(true, turtle: turtle, offer: .microapp)
        #expect(octopus.offer == .microapp)
        let morsels = [
            Octopus.Swallowed.Morsel(bubble: BubbleID(rawValue: 1), home: CGPoint(x: 1, y: 1)),
            Octopus.Swallowed.Morsel(bubble: BubbleID(rawValue: 2), home: CGPoint(x: 2, y: 2)),
        ]
        octopus.swallow(morsels, microapp: "A1", at: 1000)
        octopus.summon(false, turtle: turtle)
        #expect(octopus.canUndo)
        let spat = octopus.spitBack(at: 1001)
        #expect(spat?.morsels == morsels && spat?.microapp == "A1")

        // Even a microapp with no bubble left can be brought back.
        octopus.swallow([], microapp: "B2", at: 1002)
        #expect(octopus.canUndo)
        let gone = octopus.forget(at: 1002 + Octopus.undoSeconds + 1)
        #expect(gone.map(\.microapp) == ["B2"] && gone.flatMap(\.bubbles).isEmpty)
    }

    @Test func gulpsComeBackLastFirstAndAreForgottenTogether() {
        let octopus = Octopus(stageSize: screen)
        let (a, b) = (BubbleID(rawValue: 1), BubbleID(rawValue: 2))
        let kept = Bubble.swallowSeconds + Octopus.undoSeconds
        octopus.swallow(a, home: .zero, at: 1000)
        // A gulp keeps the one before it for as long as itself.
        octopus.swallow(b, home: .zero, at: 1000 + Octopus.undoSeconds)
        #expect(octopus.forget(at: 1000 + kept + 1).isEmpty, "forgot the first gulp alone")

        let time = 1000 + Octopus.undoSeconds + 1
        #expect(octopus.spitBack(at: time)?.bubbles == [b])
        // Spitting one back leaves time to bring back the one before it.
        #expect(octopus.forget(at: time + Octopus.undoSeconds - 1).isEmpty)
        #expect(octopus.spitBack(at: time + 1)?.bubbles == [a])
        #expect(!octopus.canUndo)

        octopus.swallow(a, home: .zero, at: 2000)
        octopus.swallow(b, home: .zero, at: 2001)
        #expect(octopus.forget(at: 2001 + kept).flatMap(\.bubbles) == [a, b])
        #expect(!octopus.canUndo)
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
