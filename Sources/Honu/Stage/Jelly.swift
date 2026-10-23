import Foundation

/// A bubble's outline as a soft ring of points around its center, at full
/// scale, that lags behind the bubble: it squashes, stretches, and wobbles
/// back to the bubble's rounded rectangle, as cartoon jelly would.
///
/// Each point is pulled toward a goal: where it rests, mapped through the
/// area-keeping part of the linear map that best fits the ring now (so the
/// ring can squash and bulge without losing area), blended with a stretch
/// along the bubble's velocity. A bending force keeps the outline smooth,
/// and a stiff spring keeps it off the screen edges.
struct Jelly {
    /// Pull toward the goal (1/s²); with `shapeKeeping`, it sets how fast
    /// the ring wobbles (about three times a second).
    static let stiffness = 900.0
    /// Damping relative to critical damping, low so the ring wobbles a few
    /// times before it settles.
    static let dampingRatio = 0.2
    /// How much of its current deformation the goal keeps rather than
    /// springing back to rest; the rest is the pull back to its shape.
    static let shapeKeeping = 0.6
    /// Pull of each point toward where it rests relative to its neighbors
    /// (1/s²), which keeps corners round and sides smooth.
    static let bending = 4 * stiffness
    /// Push back on whatever pokes past the edge of a bubble pushing this
    /// one (1/s²).
    static let contactStiffness = 6 * stiffness
    /// Push back on whatever pokes past a screen edge (1/s²).
    static let wallStiffness = 25 * stiffness
    /// How much more the ring feels a change in the bubble's velocity than
    /// real jelly would, for a cartoon squash.
    static let inertia = 3.0
    /// The most change in velocity (points/s) the ring feels within about
    /// `kickMemory` seconds: kicks add up toward it ever more slowly, so a
    /// hard hit squashes a lot rather than collapsing the ring.
    static let kickLimit = 5000.0
    static let kickMemory = 0.2
    /// How much less of a kick the side the ring is flung toward feels than
    /// the middle, and how much more the side behind it does.
    static let squash = 0.6
    /// How much more the content squashes, stretches, and shears than the
    /// ring does; where it would poke out, the glass grows to cover it.
    static let contentExaggeration = 1.3
    /// The least and most the content squashes or stretches along any
    /// direction.
    static let contentStretch = 0.6...1.6
    /// How much a fast bubble stretches along its velocity at most, and
    /// the speed (points/s) at which it does.
    static let stretch = 0.2
    static let stretchSpeed = 2000.0
    /// The farthest a point strays from where it rests, relative to the
    /// shorter side.
    static let strainLimit = 0.3
    /// Distance between points along the sides, at rest.
    static let spacing: CGFloat = 40
    /// Points on each rounded corner, besides the one starting the next side.
    static let cornerPoints = 5
    /// Steps each frame is cut into, since the walls are stiff.
    static let substeps = 8
    /// Within this distance (points) of its rest, and slower than
    /// `settleSpeed` (points/s), a point has settled.
    static let settleDistance: CGFloat = 0.1
    static let settleSpeed: CGFloat = 2

    /// The size whose rounded rectangle the ring rests on.
    let size: CGSize
    /// Where each point rests, relative to the center.
    let rest: [CGPoint]
    /// Each point's outward normal at rest.
    let normals: [CGPoint]
    /// Where each point is, relative to the bubble's center.
    private(set) var points: [CGPoint]
    /// Each point's velocity relative to the bubble, in points per second.
    private var speeds: [CGPoint]
    /// The kicks of the last moments, as felt and before they were limited,
    /// fading over `kickMemory`.
    private var felt = 0.0
    private var kicked = 0.0
    /// The inverse of the sum of `p pᵀ` over the rest points, for fitting.
    private let restInverse: CGAffineTransform

    /// A ring at rest on the rounded rectangle of `size` with `cornerRadius`.
    init(size: CGSize, cornerRadius: CGFloat) {
        self.size = size
        (rest, normals) = Self.ring(size: size, cornerRadius: cornerRadius)
        points = rest
        speeds = Array(repeating: .zero, count: rest.count)
        var sum = CGAffineTransform(a: 0, b: 0, c: 0, d: 0, tx: 0, ty: 0)
        for p in rest {
            sum.a += p.x * p.x
            sum.c += p.x * p.y
            sum.b += p.x * p.y
            sum.d += p.y * p.y
        }
        restInverse = sum.inverted()
    }

    /// Points on the rounded rectangle of `size`, clockwise from the top
    /// left, a few on each corner and the rest spread along the sides, with
    /// their outward normals.
    private static func ring(size: CGSize, cornerRadius: CGFloat)
        -> (points: [CGPoint], normals: [CGPoint])
    {
        let (w, h) = (size.width / 2, size.height / 2)
        let r = min(cornerRadius, w, h)
        var points: [CGPoint] = []
        var normals: [CGPoint] = []
        func side(from start: CGPoint, to end: CGPoint, normal: CGPoint) {
            let steps = Int(((end - start).length / spacing).rounded(.up))
            for step in 0..<steps {
                points.append(start + (end - start) * (Double(step) / Double(steps)))
                normals.append(normal)
            }
        }
        func corner(around center: CGPoint, from angle: Double) {
            for step in 0..<cornerPoints {
                let a = angle + .pi / 2 * Double(step) / Double(cornerPoints)
                let normal = CGPoint(x: cos(a), y: sin(a))
                points.append(center + normal * r)
                normals.append(normal)
            }
        }
        let (left, right, top, bottom) = (-w + r, w - r, -h + r, h - r)
        side(
            from: CGPoint(x: left, y: -h), to: CGPoint(x: right, y: -h),
            normal: CGPoint(x: 0, y: -1))
        corner(around: CGPoint(x: right, y: top), from: -.pi / 2)
        side(from: CGPoint(x: w, y: top), to: CGPoint(x: w, y: bottom), normal: CGPoint(x: 1, y: 0))
        corner(around: CGPoint(x: right, y: bottom), from: 0)
        side(from: CGPoint(x: right, y: h), to: CGPoint(x: left, y: h), normal: CGPoint(x: 0, y: 1))
        corner(around: CGPoint(x: left, y: bottom), from: .pi / 2)
        side(
            from: CGPoint(x: -w, y: bottom), to: CGPoint(x: -w, y: top),
            normal: CGPoint(x: -1, y: 0))
        corner(around: CGPoint(x: left, y: top), from: .pi)
        return (points, normals)
    }

    /// Whether every point is back where it rests and nearly still.
    var isSettled: Bool {
        zip(points, rest).allSatisfy { ($0 - $1).length < Self.settleDistance }
            && speeds.allSatisfy { $0.length < Self.settleSpeed }
    }

    /// The bubble's velocity changed by `change`: the ring, lagging behind,
    /// feels the opposite. The side it is flung toward feels less of it and
    /// the side behind more, so it squashes against where it is going, as a
    /// cartoon ball does when it stops short.
    mutating func feel(_ change: CGPoint) {
        let raw = change.length * Self.inertia
        guard raw > 0 else { return }
        kicked += raw
        let limited = Self.kickLimit * tanh(kicked / Self.kickLimit)
        let kick = change * (-(limited - felt) / change.length)
        felt = limited
        let toward = change * (-1 / change.length)
        for i in speeds.indices {
            speeds[i] = speeds[i] + kick * (1 - Self.squash * normals[i].dot(toward))
        }
    }

    /// Swells the ring outward at `rate` (1/s), or draws it in if negative.
    mutating func inflate(_ rate: Double) {
        guard rate != 0 else { return }
        for (i, p) in rest.enumerated() {
            speeds[i] = speeds[i] + p * rate
        }
    }

    /// Flattens and widens the ring by `strength` (1/s), as when it lands.
    mutating func splat(_ strength: Double) {
        for (i, p) in rest.enumerated() {
            speeds[i] = speeds[i] + CGPoint(x: p.x * strength, y: -p.y * strength)
        }
    }

    /// Advances the ring by `dt` seconds while the bubble moves at
    /// `velocity`, keeping it inside `walls` (relative to the center).
    mutating func step(dt: Double, velocity: CGPoint, walls: CGRect, contacts: [Contact] = []) {
        let fade = exp(-dt / Self.kickMemory)
        felt *= fade
        kicked = Self.kickLimit * atanh(min(felt / Self.kickLimit, 0.999))
        let stretch = Self.stretching(velocity)
        let h = dt / Double(Self.substeps)
        for _ in 0..<Self.substeps {
            substep(h, stretch: stretch, walls: walls, contacts: contacts)
        }
    }

    private mutating func substep(
        _ dt: Double, stretch: CGAffineTransform, walls: CGRect, contacts: [Contact]
    ) {
        let k = Self.stiffness
        let damping = 2 * Self.dampingRatio * k.squareRoot()
        let goal = Self.blend(
            Self.keepingArea(Self.withoutRotation(fit().linear)), stretch, Self.shapeKeeping)
        let limit = Self.strainLimit * min(size.width, size.height)
        let count = points.count
        var pulls = [CGPoint](repeating: .zero, count: count)
        for i in 0..<count {
            let (p, q, u) = (rest[i], points[i], speeds[i])
            var pull = (p.applying(goal) - q) * k - u * damping
            let (before, after) = ((i - 1 + count) % count, (i + 1) % count)
            let middle = (points[before] + points[after]) * 0.5
            let restMiddle = (rest[before] + rest[after]) * 0.5
            pull = pull + (middle - q - (restMiddle - p)) * Self.bending
            pull.x += Self.push(q.x, u.x, within: walls.minX, walls.maxX)
            pull.y += Self.push(q.y, u.y, within: walls.minY, walls.maxY)
            for contact in contacts {
                pull = pull + contact.push(q, u)
            }
            pulls[i] = pull
        }
        for i in 0..<count {
            speeds[i] = speeds[i] + pulls[i] * dt
            var q = points[i] + speeds[i] * dt
            let strain = q - rest[i]
            if strain.length > limit {
                q = rest[i] + strain * (limit / strain.length)
            }
            points[i] = q
        }
    }

    /// The edge of a bubble pushing this one, relative to its center: a
    /// soft wall the ring is pressed flat against, as long as the push lasts.
    struct Contact: Equatable {
        /// A point on the edge.
        var point: CGPoint
        /// The way the push goes, away from the pushing bubble; the ring
        /// stays on this side of the edge.
        var normal: CGPoint

        /// Pull (1/s²) on a point at `position`, moving at `speed`, that
        /// pokes past the edge: softer than the screen's edges, so the ring
        /// gives a little before it flattens.
        func push(_ position: CGPoint, _ speed: CGPoint) -> CGPoint {
            let depth = -(position - point).dot(normal)
            guard depth > 0 else { return .zero }
            let stiffness = Jelly.contactStiffness
            let closing = min(speed.dot(normal), 0)
            let damping = 2 * 0.7 * stiffness.squareRoot()
            return normal * (stiffness * depth - damping * closing)
        }
    }

    /// The push back on a point at `position`, moving at `speed`, along an
    /// axis whose walls are at `low` and `high`: a stiff, damped spring on
    /// however far it pokes past one.
    private static func push(
        _ position: Double, _ speed: Double, within low: Double, _ high: Double
    )
        -> Double
    {
        let damping = 2 * 0.7 * wallStiffness.squareRoot()
        if position < low {
            return wallStiffness * (low - position) - damping * min(speed, 0)
        }
        if position > high {
            return -wallStiffness * (position - high) - damping * max(speed, 0)
        }
        return 0
    }

    /// The linear map that best fits the ring now from where it rests, and
    /// how far its centroid has moved.
    func fit() -> (linear: CGAffineTransform, offset: CGPoint) {
        var centroid = CGPoint.zero
        for q in points {
            centroid = centroid + q
        }
        centroid = centroid * (1 / Double(points.count))
        var sum = CGAffineTransform(a: 0, b: 0, c: 0, d: 0, tx: 0, ty: 0)
        for (p, q) in zip(rest, points) {
            let moved = q - centroid
            // In `CGAffineTransform`, x' = a x + c y and y' = b x + d y.
            sum.a += moved.x * p.x
            sum.c += moved.x * p.y
            sum.b += moved.y * p.x
            sum.d += moved.y * p.y
        }
        return (restInverse.concatenating(sum), centroid)
    }

    /// `map` without the rotation in it, so a bubble never turns: what is
    /// left only squashes, stretches, and shears.
    static func withoutRotation(_ map: CGAffineTransform) -> CGAffineTransform {
        // In `CGAffineTransform`, x' = a x + c y and y' = b x + d y.
        let angle = atan2(map.b - map.c, map.a + map.d)
        let (cos, sin) = (Foundation.cos(angle), Foundation.sin(angle))
        return CGAffineTransform(
            a: cos * map.a + sin * map.b, b: -sin * map.a + cos * map.b,
            c: cos * map.c + sin * map.d, d: -sin * map.c + cos * map.d, tx: 0, ty: 0)
    }

    /// `map` scaled to keep area, or the identity if it folds the ring.
    private static func keepingArea(_ map: CGAffineTransform) -> CGAffineTransform {
        let area = map.a * map.d - map.b * map.c
        guard area > 0.2 else { return .identity }
        let scale = 1 / area.squareRoot()
        return CGAffineTransform(
            a: map.a * scale, b: map.b * scale, c: map.c * scale, d: map.d * scale, tx: 0, ty: 0)
    }

    /// `share` of `a` and the rest of `b`.
    private static func blend(_ a: CGAffineTransform, _ b: CGAffineTransform, _ share: Double)
        -> CGAffineTransform
    {
        CGAffineTransform(
            a: a.a * share + b.a * (1 - share), b: a.b * share + b.b * (1 - share),
            c: a.c * share + b.c * (1 - share), d: a.d * share + b.d * (1 - share), tx: 0, ty: 0)
    }

    /// The stretch of a ring moving at `velocity`: longer along it and
    /// narrower across it, keeping area.
    static func stretching(_ velocity: CGPoint) -> CGAffineTransform {
        let speed = velocity.length
        guard speed > 0 else { return .identity }
        let long = 1 + stretch * min(speed / stretchSpeed, 1)
        let along = velocity * (1 / speed)
        // long along the velocity, 1 / long across it.
        let (xx, xy, yy) = (along.x * along.x, along.x * along.y, along.y * along.y)
        let across = 1 / long
        return CGAffineTransform(
            a: long * xx + across * yy, b: (long - across) * xy,
            c: (long - across) * xy, d: long * yy + across * xx, tx: 0, ty: 0)
    }

    /// The squash, stretch, and shear of the content, relative to the
    /// center: the map that best fits the ring, exaggerated by
    /// `contentExaggeration` for a cartoon look, moved with the ring, and
    /// kept within `contentStretch` (`limited`).
    var contentTransform: CGAffineTransform {
        let (fitted, offset) = fit()
        let linear = Self.withoutRotation(fitted)
        let more = Self.contentExaggeration
        var map = Self.limited(
            CGAffineTransform(
                a: 1 + (linear.a - 1) * more, b: linear.b * more, c: linear.c * more,
                d: 1 + (linear.d - 1) * more, tx: 0, ty: 0))
        if offset.x.isFinite && offset.y.isFinite {
            map.tx = offset.x
            map.ty = offset.y
        }
        return map
    }

    /// `map`'s squash and stretch, kept within `contentStretch` along each
    /// of its two main directions, or the identity if it is not finite.
    /// AppKit views take the content's transform, and abort on one that is
    /// not finite; SwiftUI inverts it for views nested in others (a web
    /// page in its bubble's undo scope), so one close to folding flat must
    /// never reach them either.
    static func limited(_ map: CGAffineTransform) -> CGAffineTransform {
        let entries = [map.a, map.b, map.c, map.d]
        guard entries.allSatisfy(\.isFinite) else { return .identity }
        // Its symmetric part: its stretch along two perpendicular
        // directions. In `CGAffineTransform`, x' = a x + c y and y' = b x + d y.
        let shear = (map.b + map.c) / 2
        let middle = (map.a + map.d) / 2
        let spread = hypot((map.a - map.d) / 2, shear)
        let angle = atan2(2 * shear, map.a - map.d) / 2
        let range = contentStretch
        let first = min(max(middle + spread, range.lowerBound), range.upperBound)
        let second = min(max(middle - spread, range.lowerBound), range.upperBound)
        let (cos, sin) = (Foundation.cos(angle), Foundation.sin(angle))
        let along = first - second
        return CGAffineTransform(
            a: second + along * cos * cos, b: along * cos * sin, c: along * cos * sin,
            d: second + along * sin * sin, tx: 0, ty: 0)
    }

    /// The outline the glass takes: the ring, pushed out wherever it caves
    /// in more than `margin` past where the content follows it, so the rim
    /// grows a little there rather than the content poking out past it.
    func outline(margin: CGFloat) -> Outline {
        let map = contentTransform
        let points = zip(rest, zip(self.points, normals)).map { rest, pointAndNormal in
            let (point, normal) = pointAndNormal
            let dent = (rest.applying(map) - point).dot(normal) - margin
            return dent > 0 ? point + normal * dent : point
        }
        return Outline(points: points, normals: normals)
    }
}

/// A wobbling bubble's outline: a ring of points relative to its center, at
/// full scale, and each one's outward normal at rest.
struct Outline: Equatable {
    var points: [CGPoint]
    var normals: [CGPoint]
}
