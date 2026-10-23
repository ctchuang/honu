import Foundation
import SwiftUI
import Testing

@testable import Honu

struct JellyTests {
    private static let dt = 1.0 / 60
    private static let size = CGSize(width: 380, height: 300)
    /// Screen edges far from the ring.
    private static let open = CGRect(x: -5000, y: -5000, width: 10000, height: 10000)

    private func jelly() -> Jelly {
        Jelly(size: Self.size, cornerRadius: 30)
    }

    /// Runs `jelly` for `seconds`, calling `watch` after each frame.
    private func run(
        _ jelly: inout Jelly, _ seconds: Double, velocity: CGPoint = .zero,
        walls: CGRect = open, watch: (Jelly) -> Void = { _ in }
    ) {
        for _ in 0..<Int(seconds / Self.dt) {
            jelly.step(dt: Self.dt, velocity: velocity, walls: walls)
            watch(jelly)
        }
    }

    private func bounds(_ points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        return CGRect(
            x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!,
            height: ys.max()! - ys.min()!)
    }

    private func area(_ points: [CGPoint]) -> Double {
        var sum = 0.0
        for (a, b) in zip(points, points.dropFirst() + [points[0]]) {
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    @Test func restsOnTheRoundedRectangle() {
        let jelly = jelly()
        let box = bounds(jelly.rest)
        #expect(abs(box.width - Self.size.width) < 0.001)
        #expect(abs(box.height - Self.size.height) < 0.001)
        #expect(jelly.isSettled)
        // Nothing pokes past the rounded corners.
        let corner = CGPoint(x: Self.size.width / 2, y: Self.size.height / 2)
        #expect(jelly.rest.allSatisfy { ($0 - corner).length > 10 })
    }

    @Test func ringLeftAloneStaysAtRest() {
        var jelly = jelly()
        run(&jelly, 2)
        #expect(jelly.isSettled)
        #expect(jelly.contentTransform(margin: 6).isNearlyIdentity)
    }

    @Test func changeInVelocitySetsItWobblingAndItSettles() {
        var jelly = jelly()
        jelly.feel(CGPoint(x: 1200, y: 0))
        var widest = 0.0
        var swings = 0
        var last = 0.0
        run(&jelly, 0.8) {
            let width = bounds($0.points).width - Self.size.width
            widest = max(widest, abs(width))
            if width * last < 0 { swings += 1 }
            if abs(width) > 1 { last = width }
        }
        #expect(widest > 20, "deformed only \(widest) points")
        #expect(swings >= 2, "swung \(swings) times")
        run(&jelly, 3)
        #expect(jelly.isSettled)
    }

    @Test func hittingAWallFlattensThatSideAndBulgesTheOthers() {
        var jelly = jelly()
        let walls = CGRect(
            x: -5000, y: -5000, width: 5000 + Self.size.width / 2, height: 10000)
        // Moving right, it bounced off the right edge.
        jelly.feel(CGPoint(x: -1500, y: 0))
        var narrowest = Self.size.width
        var tallest = Self.size.height
        var farthest = -Double.infinity
        run(&jelly, 0.4, walls: walls) {
            let box = bounds($0.points)
            narrowest = min(narrowest, box.width)
            tallest = max(tallest, box.height)
            farthest = max(farthest, box.maxX)
        }
        #expect(narrowest < Self.size.width * 0.85, "narrowed only to \(narrowest)")
        #expect(tallest > Self.size.height * 1.08, "grew only to \(tallest)")
        #expect(farthest < walls.maxX + 15, "poked \(farthest - walls.maxX) past the wall")
    }

    @Test func keepsRoughlyItsArea() {
        var jelly = jelly()
        let restArea = area(jelly.rest)
        jelly.feel(CGPoint(x: 1500, y: -800))
        run(&jelly, 1.5) {
            let ratio = area($0.points) / restArea
            #expect(ratio > 0.8 && ratio < 1.2, "area went to \(ratio) of its rest")
        }
    }

    @Test func fastRingStretchesAlongItsVelocity() {
        var jelly = jelly()
        run(&jelly, 1.5, velocity: CGPoint(x: 0, y: 2500))
        let box = bounds(jelly.points)
        #expect(box.height > Self.size.height * 1.1, "stretched only to \(box.height)")
        #expect(box.width < Self.size.width * 0.93, "narrowed only to \(box.width)")
    }

    @Test func contentFollowsTheRingAndStaysInsideIt() {
        var jelly = jelly()
        let walls = CGRect(x: -Self.size.width / 2, y: -5000, width: 10000, height: 10000)
        jelly.feel(CGPoint(x: 1800, y: 600))
        // The content's rounded rectangle, 10 points inside the outline with
        // corners of radius 20: the middle of each side and of each corner.
        let (w, h) = (Self.size.width / 2 - 10, Self.size.height / 2 - 10)
        let bend = 20 * (1 - 1 / 2.squareRoot())
        let corners = [
            CGPoint(x: -w, y: 0), CGPoint(x: w, y: 0), CGPoint(x: 0, y: -h), CGPoint(x: 0, y: h),
            CGPoint(x: -w + bend, y: -h + bend), CGPoint(x: w - bend, y: -h + bend),
            CGPoint(x: w - bend, y: h - bend), CGPoint(x: -w + bend, y: h - bend),
        ]
        var squashed = 1.0
        run(&jelly, 1, walls: walls) { jelly in
            let transform = jelly.contentTransform(margin: 6)
            squashed = min(squashed, transform.a)
            let outline = Path { $0.addLines(jelly.points) }
            for corner in corners {
                let moved = corner.applying(transform)
                #expect(outline.contains(moved), "content corner \(moved) left the outline")
            }
        }
        #expect(squashed < 0.9, "content squashed only to \(squashed)")
    }
}

@MainActor
struct BubbleJellyTests {
    private static let dt = 1.0 / 60
    private let stage = Stage(size: CGSize(width: 2000, height: 1000))

    private func bubble(_ x: CGFloat, _ y: CGFloat = 500) -> Bubble {
        stage.add(
            target: ViewTarget(app: AppID("test"), item: ItemID(rawValue: 1)),
            center: CGPoint(x: x, y: y), appearance: Appearance(), viewState: nil)
    }

    /// Runs the stage for `seconds`, calling `watch` after each step.
    private func simulate(_ seconds: Double, watch: () -> Void = {}) {
        for _ in 0..<Int((seconds / Self.dt).rounded()) {
            stage.step(dt: Self.dt)
            watch()
        }
    }

    private func isAtRest(_ bubble: Bubble) -> Bool {
        bubble.outline == nil && bubble.contentTransform == .identity
    }

    @Test func bubbleLeftAloneNeverWobbles() {
        let bubble = bubble(500)
        simulate(2) { #expect(isAtRest(bubble)) }
    }

    @Test func bubbleThrownAtTheEdgeSquashesWobblesAndRests() {
        let bubble = bubble(1500)
        bubble.velocity = CGPoint(x: 2000, y: 0)
        var squashed = 1.0
        simulate(0.6) { squashed = min(squashed, bubble.contentTransform.a) }
        #expect(squashed < 0.85, "content squashed only to \(squashed)")
        simulate(4)
        #expect(isAtRest(bubble))
    }

    @Test func draggedBubbleTrailsThePointer() {
        let bubble = bubble(500)
        stage.startDrag(bubble)
        var wobbled = false
        for frame in 1...30 {
            stage.dragged(
                by: CGSize(width: 30 * Double(frame), height: 0),
                velocity: CGSize(width: 1800, height: 0), doomed: false)
            stage.step(dt: Self.dt)
            wobbled = wobbled || bubble.outline != nil
        }
        #expect(wobbled)
        // Moving right, it trails behind: its outline sits left of its center.
        let points = bubble.outline?.points ?? []
        let middle = points.reduce(0) { $0 + $1.x } / Double(max(points.count, 1))
        #expect(middle < -1, "outline centered at \(middle)")
        _ = stage.endDrag()
    }

    @Test func resizingOrChangingSizeBringsItToRest() {
        let bubble = bubble(1500)
        bubble.velocity = CGPoint(x: 2000, y: 0)
        simulate(0.3)
        #expect(!isAtRest(bubble))
        stage.startResize(bubble, edges: .left)
        simulate(Self.dt)
        #expect(isAtRest(bubble))
        stage.endResize()

        bubble.velocity = CGPoint(x: -2000, y: 0)
        simulate(0.2)
        #expect(!isAtRest(bubble))
        bubble.microappSize = CGSize(width: 500, height: 400)
        simulate(Self.dt)
        #expect(isAtRest(bubble))
    }

    @Test func spatOutBubbleSplatsWhenItLands() {
        let bubble = bubble(500)
        stage.spit(bubble, from: CGPoint(x: 100, y: 900))
        var splatted = false
        simulate(Bubble.spawnSeconds + 0.3) {
            if !bubble.isInFlight, let outline = bubble.outline {
                let xs = outline.points.map(\.x)
                splatted = splatted || xs.max()! - xs.min()! > bubble.size.width + 5
            }
        }
        #expect(splatted, "did not splat wider when it landed")
    }
}

extension CGAffineTransform {
    fileprivate var isNearlyIdentity: Bool {
        abs(a - 1) < 0.001 && abs(b) < 0.001 && abs(c) < 0.001 && abs(d - 1) < 0.001
            && abs(tx) < 0.01 && abs(ty) < 0.01
    }
}
