import Foundation
import Testing

@testable import Honu

/// The squash, stretch, and shear a wobbling bubble's content takes. AppKit
/// views take it, and abort on one that is not finite, so beyond looking
/// right it must stay finite and well away from folding flat.
struct ContentTransformTests {
    private static let dt = 1.0 / 60
    private static let open = CGRect(x: -5000, y: -5000, width: 10000, height: 10000)

    /// The stretches of `map`'s symmetric part along its two main directions.
    private func stretches(_ map: CGAffineTransform) -> (Double, Double) {
        let shear = (map.b + map.c) / 2
        let middle = (map.a + map.d) / 2
        let spread = hypot((map.a - map.d) / 2, shear)
        return (middle + spread, middle - spread)
    }

    /// Whether `map` is finite, never turns, and stretches within the limits.
    private func isSafe(_ map: CGAffineTransform) -> Bool {
        let range = Jelly.contentStretch
        let (first, second) = stretches(map)
        return [map.a, map.b, map.c, map.d, map.tx, map.ty].allSatisfy(\.isFinite)
            && abs(map.b - map.c) < 1e-9
            && first <= range.upperBound + 1e-9 && second >= range.lowerBound - 1e-9
            && map.a * map.d - map.b * map.c >= range.lowerBound * range.lowerBound - 1e-9
    }

    @Test(arguments: [
        CGAffineTransform(a: 0.503, b: 0.513, c: 0.513, d: 0.529, tx: 0, ty: 0),  // nearly flat
        CGAffineTransform(a: 0, b: 0, c: 0, d: 0, tx: 0, ty: 0),
        CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 0, ty: 0),  // flipped
        CGAffineTransform(a: 4, b: 0, c: 0, d: 0.1, tx: 0, ty: 0),
        CGAffineTransform(a: 1, b: 3, c: -3, d: 1, tx: 0, ty: 0),
        CGAffineTransform(a: 1e9, b: -1e9, c: 1e9, d: 1e-9, tx: 0, ty: 0),
    ])
    func limitKeepsAnyMapSafe(map: CGAffineTransform) {
        #expect(isSafe(Jelly.limited(map)), "limited \(map) to \(Jelly.limited(map))")
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func limitTurnsWhatIsNotFiniteIntoTheIdentity(value: Double) {
        let map = CGAffineTransform(a: value, b: 0, c: 0, d: 1, tx: 0, ty: 0)
        #expect(Jelly.limited(map) == .identity)
    }

    @Test func limitLeavesModestSquashesAlone() {
        let map = CGAffineTransform(a: 0.85, b: 0.05, c: 0.05, d: 1.15, tx: 0, ty: 0)
        let limited = Jelly.limited(map)
        for (a, b) in zip([limited.a, limited.b, limited.c, limited.d], [0.85, 0.05, 0.05, 1.15]) {
            #expect(abs(a - b) < 1e-9)
        }
    }

    @Test func squashesAlongAHitAndWidensAcrossIt() {
        let size = CGSize(width: 380, height: 300)
        var jelly = Jelly(size: size, cornerRadius: 30)
        let walls = CGRect(x: -5000, y: -5000, width: 5000 + size.width / 2, height: 10000)
        // Moving right, it bounced off the right edge.
        jelly.feel(CGPoint(x: -1500, y: 0))
        var deepest = CGAffineTransform.identity
        for _ in 0..<30 {
            jelly.step(dt: Self.dt, velocity: .zero, walls: walls)
            let map = jelly.contentTransform
            if map.a < deepest.a { deepest = map }
        }
        #expect(deepest.a < 0.85, "squashed only to \(deepest.a)")
        #expect(deepest.d > 1.02, "widened only to \(deepest.d) as it squashed")
    }

    @Test func movesWithTheRing() {
        var jelly = Jelly(size: CGSize(width: 380, height: 300), cornerRadius: 30)
        // Sped up to the right, the ring lags behind, to the left.
        jelly.feel(CGPoint(x: 1000, y: 0))
        jelly.step(dt: Self.dt, velocity: .zero, walls: Self.open)
        let map = jelly.contentTransform
        #expect(map.tx < -1, "moved \(map.tx) points")
        #expect(abs(map.ty) < 0.5)
    }

    @Test func exaggeratesTheRing() {
        var jelly = Jelly(size: CGSize(width: 380, height: 300), cornerRadius: 30)
        jelly.splat(1)
        jelly.step(dt: Self.dt, velocity: .zero, walls: Self.open)
        let ring = Jelly.withoutRotation(jelly.fit().linear)
        let map = jelly.contentTransform
        #expect(abs((map.a - 1) - (ring.a - 1) * Jelly.contentExaggeration) < 1e-6)
        #expect(abs((map.d - 1) - (ring.d - 1) * Jelly.contentExaggeration) < 1e-6)
    }

    @Test(arguments: [
        CGSize(width: 1, height: 1), CGSize(width: 1, height: 500), CGSize(width: 12, height: 12),
        CGSize(width: 380, height: 300), CGSize(width: 2400, height: 1400),
    ])
    func staysSafeForAnySize(size: CGSize) {
        var jelly = Jelly(size: size, cornerRadius: 30)
        let walls = CGRect(
            x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        var random = SplitMix(seed: 7)
        for frame in 0..<240 {
            if frame % 20 == 0 {
                jelly.feel(
                    CGPoint(x: random.next(in: -6000...6000), y: random.next(in: -6000...6000)))
                jelly.splat(random.next(in: -8...8))
                jelly.inflate(random.next(in: -8...8))
            }
            let contact = Jelly.Contact(
                point: CGPoint(x: size.width / 4, y: 0), normal: CGPoint(x: -1, y: 0))
            jelly.step(
                dt: Self.dt, velocity: CGPoint(x: random.next(in: -3000...3000), y: 0),
                walls: walls, contacts: frame % 40 < 20 ? [contact] : [])
            let map = jelly.contentTransform
            #expect(isSafe(map), "frame \(frame): \(map)")
            if !isSafe(map) { return }
        }
    }

    /// Shakes a stage every way it can be shaken (throws, drags over the
    /// octopus, resizes, size changes, flights in and out, motions,
    /// breathing), with bubbles of any size, and checks every bubble's
    /// content transform, outline, and place each frame.
    @MainActor
    @Test(arguments: 0..<8)
    func staysSafeOnAShakenStage(seed: Int) {
        var random = SplitMix(seed: UInt64(seed + 1))
        let stage = Stage(size: CGSize(width: 1600, height: 1000))
        let target = ViewTarget(app: AppID("test"), item: ItemID(rawValue: 1))
        for _ in 0..<5 {
            let bubble = stage.add(
                target: target,
                center: CGPoint(x: random.next(in: 0...1600), y: random.next(in: 0...1000)),
                appearance: Appearance(
                    size: CGSize(width: random.next(in: 1...700), height: random.next(in: 1...600)),
                    minSize: CGSize(width: 1, height: 1)),
                viewState: nil)
            if random.next(in: 0...1) < 0.5 {
                stage.spit(bubble, from: CGPoint(x: 50, y: 950))
            }
        }
        for frame in 0..<400 {
            shake(stage, &random)
            stage.step(dt: random.next(in: 0.0001...(1.0 / 30)))
            for bubble in stage.bubbles {
                let map = bubble.contentTransform
                let points = bubble.outline?.points ?? []
                let safe =
                    [map.a, map.b, map.c, map.d, map.tx, map.ty].allSatisfy(\.isFinite)
                    && map.a * map.d - map.b * map.c >= 0.35
                    && points.allSatisfy { $0.x.isFinite && $0.y.isFinite }
                    && bubble.center.x.isFinite && bubble.center.y.isFinite
                #expect(safe, "frame \(frame): \(map), size \(bubble.size)")
                if !safe { return }
            }
        }
    }

    /// Does one random thing to `stage`.
    @MainActor
    private func shake(_ stage: Stage, _ random: inout SplitMix) {
        let bubbles = stage.bubbles
        let bubble = bubbles[Int(random.next(in: 0...Double(bubbles.count) - 0.001))]
        let idle = !stage.isDragging && !stage.isResizing
        switch Int(random.next(in: 0...11.999)) {
        case 0:
            bubble.velocity = CGPoint(
                x: random.next(in: -4000...4000), y: random.next(in: -4000...4000))
        case 1 where idle && bubble.isGrabbable:
            stage.startDrag(bubble)
        case 2 where stage.isDragging:
            stage.dragged(
                by: CGSize(width: random.next(in: -900...900), height: random.next(in: -900...900)),
                velocity: CGSize(width: random.next(in: -3000...3000), height: 0),
                doomed: random.next(in: 0...1) < 0.3)
        case 3 where stage.isDragging:
            _ = stage.endDrag()
        case 4 where idle && bubble.isGrabbable:
            stage.startResize(bubble, edges: [.right, .bottom])
        case 5 where stage.isResizing:
            stage.resized(
                by: CGSize(width: random.next(in: -800...800), height: random.next(in: -800...800)))
        case 6 where stage.isResizing:
            stage.endResize()
        case 7:
            bubble.microappSize = CGSize(
                width: random.next(in: 1...800), height: random.next(in: 1...700))
        case 8 where bubble.isFree && !stage.isDragging:
            stage.swallow(bubble, into: CGPoint(x: 1500, y: 980))
        case 9 where bubble.isSwallowed:
            stage.spitBack(bubble, from: CGPoint(x: 1500, y: 980), to: CGPoint(x: 800, y: 500))
        case 10:
            bubble.play(random.next(in: 0...1) < 0.5 ? .rise : .wobble)
        case 11:
            bubble.isBusy.toggle()
        default:
            break
        }
    }
}

/// A small, repeatable random number generator (SplitMix64).
private struct SplitMix {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        let unit = Double(z >> 11) / Double(UInt64(1) << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
