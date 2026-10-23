import Foundation
import Testing

@testable import Honu

@MainActor
struct PhysicsTests {
    private static let dt = 1.0 / 60
    private let stage = Stage(size: CGSize(width: 4000, height: 1000))

    /// A bubble 160 points square at (`x`, 500).
    private func small(_ x: CGFloat) -> Bubble {
        bubble(x, size: CGSize(width: 160, height: 160))
    }

    /// A bubble of `size`, the default 380 by 300 points, at (`x`, `y`).
    private func bubble(
        _ x: CGFloat, _ y: CGFloat = 500, size: CGSize = Appearance().size
    ) -> Bubble {
        stage.add(
            target: ViewTarget(app: AppID("test"), item: ItemID(rawValue: 1)),
            center: CGPoint(x: x, y: y), appearance: Appearance(size: size), viewState: nil)
    }

    /// Runs the stage for `seconds`, calling `watch` after each step.
    private func simulate(_ seconds: Double, watch: () -> Void = {}) {
        for _ in 0..<Int(seconds / Self.dt) {
            stage.step(dt: Self.dt)
            watch()
        }
    }

    @Test func thrownBubbleGlidesAShortWayAndStops() {
        let bubble = small(500)
        bubble.velocity = CGPoint(x: 1500, y: 0)
        simulate(3)
        let travel = bubble.center.x - 500
        #expect(travel > 200 && travel < 450, "glided \(travel) points")
        #expect(bubble.velocity == .zero)
    }

    @Test func bubblesLeftAloneStayPut() {
        let bubble = small(500)
        simulate(3)
        #expect(bubble.center == CGPoint(x: 500, y: 500) && bubble.velocity == .zero)
    }

    @Test func thrownBubbleKnocksAnotherInsteadOfPassingThrough() {
        let (a, b) = (small(500), small(700))
        a.velocity = CGPoint(x: 1500, y: 0)
        var closest = Double.infinity
        simulate(3) { closest = min(closest, b.center.x - a.center.x) }
        let knocked = b.center.x - 700
        #expect(closest > 100, "centers came within \(closest) points")
        #expect(knocked > 100, "only knocked \(knocked) points")
    }

    @Test func spawnedBubbleLandsWhereItWasPlaced() {
        _ = small(500)
        let bubble = small(900)
        let place = bubble.center
        bubble.fly(from: CGPoint(x: 100, y: 900), to: place)
        #expect(bubble.scale < 0.5 && !bubble.isGrabbable)
        var frame = 0
        while bubble.isInFlight {
            stage.step(dt: Self.dt)
            frame += 1
        }
        #expect((bubble.center - place).length < 1, "landed away from its place")
        #expect(bubble.scale == 1 && bubble.isGrabbable)
        #expect(Double(frame) * Self.dt < Bubble.spawnSeconds + 0.1)
    }

    @Test func aSlightOverlapIsKept() {
        // 10 points of overlap, less than their rounded corners allow.
        let (a, b) = (small(500), small(650))
        simulate(3)
        #expect(a.center.x == 500 && b.center.x == 650)
    }

    @Test func crowdedBubblesArePushedApartAndComeToRest() {
        let (a, b) = (bubble(1000), bubble(1150, 520))
        simulate(4)
        let gap = b.center.x - a.center.x
        // Side by side, overlapping by no more than their rounded corners allow.
        #expect(gap > 360, "still \(gap) points apart")
        #expect(abs(b.center.y - a.center.y - 20) < 1, "pushed sideways, not up or down")
        #expect(a.velocity == .zero && b.velocity == .zero, "still creeping")
    }

    @Test func bubblesCornerToCornerArePushedApartDiagonally() {
        let (a, b) = (bubble(1000, 300), bubble(1340, 550))
        simulate(3)
        let apart = b.center - a.center
        #expect(apart.x > 340 && apart.y > 250, "only \(apart) apart")
    }

    @Test func aSmallBubbleIsPushedOffABigOneMoreThanTheBigOneMoves() {
        let (big, small) = (bubble(1000), small(1170))
        simulate(3)
        let bigMoved = 1000 - big.center.x
        let smallMoved = small.center.x - 1170
        #expect(small.frame.minX > big.frame.maxX - 30, "still on the big one")
        #expect(smallMoved > bigMoved * 2, "big moved \(bigMoved), small \(smallMoved)")
    }

    @Test func bubblesBounceOffTheEdges() {
        let bubble = small(3800)
        bubble.velocity = CGPoint(x: 2000, y: 0)
        simulate(1)
        #expect(bubble.frame.maxX <= stage.size.width)
        #expect(bubble.velocity.x <= 0, "did not bounce back")
    }

    @Test func aHeldBubbleFollowsThePointerNotThePhysics() {
        let (held, other) = (small(500), small(520))
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

    @Test func aHeldBubblePushesABigOneAside() {
        let (held, big) = (small(1000), bubble(1150))
        stage.startDrag(held)
        simulate(2)
        #expect(held.center == CGPoint(x: 1000, y: 500))
        #expect(big.frame.minX > held.frame.maxX - 30, "the big one was not pushed aside")
    }

    @Test func aGrowingBubblePushesItsNeighborAsideWithoutMoving() {
        let (growing, neighbor) = (bubble(1000), bubble(1450))
        stage.startResize(growing, edges: .right)
        stage.resized(by: CGSize(width: 150, height: 0))
        let center = growing.center
        simulate(2)
        #expect(growing.center == center && growing.velocity == .zero)
        #expect(neighbor.frame.minX > growing.frame.maxX - 30, "the neighbor was not pushed")
        stage.endResize()
    }

    @Test func swallowedBubbleShrinksIntoTheMouthAndStaysThere() {
        let bubble = small(500)
        bubble.isDoomed = true
        let mouth = CGPoint(x: 3900, y: 990)
        stage.swallow(bubble, into: mouth)
        #expect(bubble.drawnScale == Bubble.doomedScale)
        simulate(1)
        #expect(bubble.center == mouth && bubble.scale == 0 && bubble.isHidden)
    }
}
