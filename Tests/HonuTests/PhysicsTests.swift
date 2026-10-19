import Foundation
import Testing

@testable import Honu

@MainActor
struct PhysicsTests {
    private static let dt = 1.0 / 60
    private let stage = Stage(size: CGSize(width: 4000, height: 1000))

    /// A closed bubble 160 points across at (`x`, 500).
    private func ball(_ x: CGFloat) -> Bubble {
        stage.add(
            target: ViewTarget(app: AppID("test"), item: ItemID(rawValue: 1)),
            center: CGPoint(x: x, y: 500), appearance: Appearance(closedSide: 160),
            viewState: nil)
    }

    /// Runs the stage for `seconds`, calling `watch` after each step.
    private func simulate(_ seconds: Double, watch: () -> Void = {}) {
        for frame in 0..<Int(seconds / Self.dt) {
            stage.step(time: Double(frame) * Self.dt, dt: Self.dt)
            watch()
        }
    }

    @Test func thrownBubbleGlidesAShortWay() {
        let bubble = ball(500)
        bubble.velocity = CGPoint(x: 1500, y: 0)
        simulate(3)
        let travel = bubble.center.x - 500
        #expect(travel > 200 && travel < 450, "glided \(travel) points")
        #expect(bubble.velocity.length < 20)
    }

    @Test func thrownBubbleKnocksAnotherInsteadOfPassingThrough() {
        let (a, b) = (ball(500), ball(700))
        a.velocity = CGPoint(x: 1500, y: 0)
        var closest = Double.infinity
        simulate(3) { closest = min(closest, b.center.x - a.center.x) }
        let knocked = b.center.x - 700
        #expect(closest > 100, "centers came within \(closest) points")
        #expect(knocked > 100, "only knocked \(knocked) points")
    }

    @Test func spawnedBubbleLandsWhereItWasPlacedAndOpens() {
        _ = ball(500)
        let bubble = ball(900)
        let place = bubble.center
        bubble.fly(from: CGPoint(x: 100, y: 900), to: place, openOnLanding: true)
        #expect(bubble.scale < 0.5 && !bubble.isGrabbable)
        var frame = 0
        while bubble.isInFlight {
            stage.step(time: Double(frame) * Self.dt, dt: Self.dt)
            frame += 1
        }
        #expect((bubble.center - place).length < 1, "landed away from its place")
        #expect(bubble.scale == 1 && bubble.isOpen && bubble.isGrabbable)
        #expect(Double(frame) * Self.dt < Bubble.spawnSeconds + 0.1)
    }

    @Test func restingPartialOverlapIsKept() {
        let (a, b) = (ball(500), ball(650))
        // Drifting in step, so only a push could change the gap.
        b.phase = a.phase
        simulate(3)
        let gap = b.center.x - a.center.x
        #expect(abs(gap - 150) < 1, "pushed apart to \(gap) points")
    }

    @Test func crowdedBubblesArePushedApart() {
        let (a, b) = (ball(500), ball(510))
        simulate(3)
        let gap = b.center.x - a.center.x
        #expect(gap > 100, "still \(gap) points apart")
    }

    @Test func bubblesBounceOffTheEdges() {
        let bubble = ball(3800)
        bubble.velocity = CGPoint(x: 2000, y: 0)
        simulate(1)
        #expect(bubble.frame.maxX <= stage.size.width)
        #expect(bubble.velocity.x <= 0, "did not bounce back")
    }

    @Test func idleBubblesDriftButOpenOnesStayPut() {
        let (closed, open) = (ball(500), ball(2000))
        stage.toggle(open)
        simulate(3)
        #expect((closed.center - CGPoint(x: 500, y: 500)).length > 1, "did not drift")
        #expect(open.center == CGPoint(x: 2000, y: 500))
    }

    @Test func aHeldBubbleFollowsThePointerNotThePhysics() {
        let (held, other) = (ball(500), ball(520))
        stage.startDrag(held)
        stage.dragged(by: .zero, velocity: CGSize(width: 1000, height: 0), doomed: false)
        simulate(1)
        #expect(held.center == CGPoint(x: 500, y: 500))
        #expect(other.center.x > 600, "the held bubble did not push")
        // Let go, it keeps the pointer's speed.
        _ = stage.endDrag()
        simulate(0.1)
        #expect(held.center.x > 520)
    }

    @Test func swallowedBubbleShrinksIntoTheMouthAndStaysThere() {
        let bubble = ball(500)
        bubble.isDoomed = true
        let mouth = CGPoint(x: 3900, y: 990)
        stage.swallow(bubble, into: mouth)
        #expect(bubble.drawnScale == Bubble.doomedScale)
        simulate(1)
        #expect(bubble.center == mouth && bubble.scale == 0 && bubble.isHidden)
    }
}
