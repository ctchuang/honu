import Foundation

/// Bubble motion: momentum after a throw, soft pushing between crowded
/// bubbles, and bounces off the screen edges. Left alone, a bubble stays
/// where it is put, as a window does. Bubbles flying out of the turtle or
/// into the octopus follow their own path and are left alone.
enum Physics {
    /// Velocity decay rate (1/s); higher stops a thrown bubble sooner.
    static let friction = 4.0
    /// The room (points) bubbles keep between their outlines: closer, they
    /// push each other apart. It is wider than the gap a bubble on top cuts
    /// out of the glass below it (`StageView.gap`), so bubbles at rest never
    /// overlap; a bubble overlapping another at rest would have its side cut
    /// away all along, and look pressed flat for good.
    static let spacing = 4.0
    /// How deep (points) bubbles may come into each other's `spacing`
    /// before they push. Pushed apart, bubbles come to rest at its edge;
    /// without this they would rest a hair inside it, pushing ever more
    /// faintly for ever, and their jelly, pressed all the while, would
    /// never settle.
    static let slop = 0.5
    /// Spring stiffness of the push between crowded bubbles; a bubble of
    /// radius 100 pressed in by 1 point is pushed back at this many points/s².
    static let pushStiffness = 160.0
    /// Damping of that push relative to critical damping. It soaks up the
    /// impact when bubbles collide, so they bump and share momentum instead
    /// of jiggling.
    static let pushDamping = 0.45
    /// The deepest a bubble pushing another presses its jelly in, relative
    /// to how far the pressed one reaches from its center that way.
    static let dent = 0.125
    /// How much bubbles deep in each other are pushed along the other axis
    /// too, as far as their centers lie apart along it, so bubbles jammed
    /// between two screen edges slide past each other rather than push for
    /// ever.
    static let sideways = 0.25
    /// How deep (points) into each other's `spacing` bubbles must be for
    /// `sideways` to apply: a jam, rather than neighbors touching, which
    /// would otherwise creep sideways along a crowded row for ever.
    static let jamDepth = 20.0
    /// The least push (points/s²) that sets a bubble at rest moving, as
    /// static friction would: weaker pushes, from neighbors barely inside
    /// each other's spacing, leave it, and its jelly, alone.
    static let startPush = 200.0
    /// Fraction of speed kept after bouncing off a screen edge, low so a
    /// bubble thrown at the edge stays near it rather than coming back.
    static let bounce = 0.15
    /// Speed limit (points/s) for thrown bubbles.
    static let maxSpeed = 2500.0
    /// Speed (points/s) below which a bubble stops, so it comes to rest
    /// instead of creeping, and redrawing, for ever.
    static let restSpeed = 1.0
    /// Speed (points/s) below which a bubble hitting a screen edge stops
    /// there rather than bouncing, so one pushed against it rests.
    static let bounceSpeed = 50.0

    /// Advances `bubbles` by `dt` seconds inside `bounds`. The
    /// `held` bubble follows the pointer, so it pushes others but is not
    /// moved by any force itself.
    @MainActor
    static func step(
        _ bubbles: [Bubble], bounds: CGSize, held: Bubble?, dt: Double
    ) {
        var accel = [CGPoint](repeating: .zero, count: bubbles.count)
        var pushes: [(i: Int, j: Int, push: Double, direction: CGPoint)] = []

        for i in bubbles.indices where bubbles[i].isFree {
            for j in bubbles.indices where j > i && bubbles[j].isFree {
                let (a, b) = (bubbles[i], bubbles[j])
                let (dist, axis, lean) = separation(a, b)
                let minDist = roundness(a) + roundness(b) + spacing
                guard dist < minDist - slop else { continue }
                let deep = minDist - dist > jamDepth
                let leaning = axis + lean * sideways
                let dir = deep ? leaning * (1 / leaning.length) : axis
                let (ma, mb) = (mass(a), mass(b))
                let closingSpeed = (a.velocity - b.velocity).dot(dir)
                let damping = pushDamping * 2 * (pushStiffness * ma * mb / (ma + mb)).squareRoot()
                // Never pull: separating bubbles should not stick together.
                let push = max(pushStiffness * (minDist - dist) + damping * closingSpeed, 0)
                guard push > 0 else { continue }
                accel[i] = accel[i] - dir * (push / ma)
                accel[j] = accel[j] + dir * (push / mb)
                pushes.append((i, j, push, dir))
            }
        }

        // A screen edge a bubble touches pushes back as hard as it is pushed
        // into it.
        for index in bubbles.indices {
            accel[index] = walled(accel[index], bubbles[index], in: bounds)
        }
        // A bubble at rest stays at rest unless pushed hard enough; one held
        // moves with the pointer.
        let moving = bubbles.indices.map {
            bubbles[$0] === held || bubbles[$0].velocity != .zero
                || accel[$0].length >= startPush
        }

        for (i, j, push, dir) in pushes where moving[i] || moving[j] {
            let (a, b) = (bubbles[i], bubbles[j])
            // Their jelly feels the bump, and is pressed flat against the
            // other's edge while the push lasts.
            a.knock(dir * (-push / mass(a) * dt))
            b.knock(dir * (push / mass(b) * dt))
            let (edgeA, edgeB) = (reach(a, along: dir), reach(b, along: dir))
            let overlap = (a.center + dir * edgeA - (b.center - dir * edgeB)).dot(dir)
            b.press(
                at: b.center - dir * (edgeB - min(overlap, dent * edgeB)), toward: dir, by: a)
            a.press(
                at: a.center + dir * (edgeA - min(overlap, dent * edgeA)), toward: dir * -1,
                by: b)
        }

        for (index, bubble) in bubbles.enumerated() where bubble.isFree {
            // How fast it was going before this frame's pushes, which alone
            // can bounce it off an edge.
            let coasting = bubble.velocity
            if bubble !== held && moving[index] {
                var velocity = (bubble.velocity + accel[index] * dt) * exp(-friction * dt)
                let speed = velocity.length
                if speed > maxSpeed {
                    velocity = velocity * (maxSpeed / speed)
                } else if speed < restSpeed && accel[index].length < startPush {
                    velocity = .zero
                }
                if velocity != bubble.velocity {
                    bubble.velocity = velocity
                }
                if velocity != .zero {
                    bubble.center = bubble.center + velocity * dt
                }
            }
            confine(bubble, to: bounds, coasting: coasting)
        }
    }

    /// The corner radius of `bubble` as drawn, no more than half its side.
    @MainActor
    private static func roundness(_ bubble: Bubble) -> Double {
        let frame = bubble.frame
        return min(bubble.cornerRadius * bubble.drawnScale, min(frame.width, frame.height) / 2)
    }

    /// How far apart the cores of `a` and `b` are, and the direction from
    /// `a` to `b` to push them apart along. A bubble's core is its frame
    /// inset by its roundness, so two bubbles touch where the distance
    /// between their cores is the sum of their roundnesses. Cores that
    /// overlap are a negative distance apart, and are pushed apart along
    /// whichever axis frees them sooner.
    @MainActor
    private static func separation(_ a: Bubble, _ b: Bubble)
        -> (distance: Double, direction: CGPoint, lean: CGPoint)
    {
        let (ra, rb) = (roundness(a), roundness(b))
        // How far the cores reach from the center each way, together.
        let reach = CGPoint(
            x: a.frame.width / 2 - ra + b.frame.width / 2 - rb,
            y: a.frame.height / 2 - ra + b.frame.height / 2 - rb)
        let delta = b.center - a.center
        let sign = CGPoint(x: delta.x < 0 ? -1 : 1, y: delta.y < 0 ? -1 : 1)
        let gap = CGPoint(x: abs(delta.x) - reach.x, y: abs(delta.y) - reach.y)
        if gap.x > 0 && gap.y > 0 {
            // Corner to corner.
            let apart = CGPoint(x: gap.x * sign.x, y: gap.y * sign.y)
            let distance = apart.length
            return (distance, apart * (1 / distance), .zero)
        }
        // Edge to edge, or overlapping: pushed apart along the axis that
        // frees them sooner. How far their centers lie apart along the
        // other, relative to how far they could, is the way to lean if they
        // are jammed.
        return gap.x > gap.y
            ? (gap.x, CGPoint(x: sign.x, y: 0), CGPoint(x: 0, y: delta.y / max(reach.y, 1)))
            : (gap.y, CGPoint(x: 0, y: sign.y), CGPoint(x: delta.x / max(reach.x, 1), y: 0))
    }

    /// How far `bubble`'s frame reaches from its center along `direction`.
    @MainActor
    private static func reach(_ bubble: Bubble, along direction: CGPoint) -> Double {
        bubble.frame.width / 2 * abs(direction.x) + bubble.frame.height / 2 * abs(direction.y)
    }

    /// Bigger bubbles are heavier and get pushed around less.
    @MainActor
    private static func mass(_ bubble: Bubble) -> Double {
        bubble.frame.width * bubble.frame.height / 40000
    }

    /// `accel` without what pushes `bubble` into a screen edge it touches.
    @MainActor
    private static func walled(_ accel: CGPoint, _ bubble: Bubble, in bounds: CGSize) -> CGPoint {
        let frame = bubble.frame
        let touch = 0.5
        var accel = accel
        if (frame.minX <= touch && accel.x < 0)
            || (frame.maxX >= bounds.width - touch && accel.x > 0)
        {
            accel.x = 0
        }
        if (frame.minY <= touch && accel.y < 0)
            || (frame.maxY >= bounds.height - touch && accel.y > 0)
        {
            accel.y = 0
        }
        return accel
    }

    /// Keeps the whole bubble inside `bounds`. Hitting an edge, it bounces
    /// only as fast as it was `coasting` toward it before this frame's
    /// pushes, as one thrown there does: a bubble pushed into an edge stops
    /// against it, rather than gaining a frame's push each time it hits and
    /// bouncing for ever.
    @MainActor
    private static func confine(_ bubble: Bubble, to bounds: CGSize, coasting: CGPoint) {
        let half = CGPoint(x: bubble.frame.width / 2, y: bubble.frame.height / 2)
        var center = bubble.center
        var velocity = bubble.velocity
        func clamp(
            _ c: inout CGFloat, _ v: inout CGFloat, coasting: CGFloat, half: CGFloat,
            size: CGFloat
        ) {
            let (lo, hi) = (half, size - half)
            if lo > hi {
                // The screen is smaller than the bubble: just center it.
                c = size / 2
                v = 0
            } else if c < lo {
                c = lo
                v = -coasting < bounceSpeed ? 0 : -coasting * bounce
            } else if c > hi {
                c = hi
                v = coasting < bounceSpeed ? 0 : -coasting * bounce
            }
        }
        clamp(&center.x, &velocity.x, coasting: coasting.x, half: half.x, size: bounds.width)
        clamp(&center.y, &velocity.y, coasting: coasting.y, half: half.y, size: bounds.height)
        if center != bubble.center { bubble.center = center }
        if velocity != bubble.velocity { bubble.velocity = velocity }
    }
}
