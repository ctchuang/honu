import Foundation

/// Bubble motion: momentum after a throw, soft pushing between crowded
/// bubbles, and bounces off the screen edges. Left alone, a bubble stays
/// where it is put, as a window does. Bubbles flying out of the turtle or
/// into the octopus follow their own path and are left alone.
enum Physics {
    /// Velocity decay rate (1/s); higher stops a thrown bubble sooner.
    static let friction = 4.0
    /// Bubbles only push each other once they overlap by more than
    /// `1 - personalSpace` of the sum of their corner radii, so slight
    /// overlaps (which show off the glass) are left alone.
    static let personalSpace = 0.8
    /// Spring stiffness of the push between crowded bubbles; a bubble of
    /// radius 100 pressed in by 1 point is pushed back at this many points/s².
    static let pushStiffness = 160.0
    /// Damping of that push relative to critical damping. It soaks up the
    /// impact when bubbles collide, so they bump and share momentum instead
    /// of jiggling.
    static let pushDamping = 0.45
    /// The deepest a bubble pushing another presses its jelly in, relative
    /// to how far the pressed one reaches from its center that way.
    static let dent = 0.25
    /// Fraction of speed kept after bouncing off a screen edge.

    static let bounce = 0.5
    /// Speed limit (points/s) for thrown bubbles.
    static let maxSpeed = 2500.0
    /// Speed (points/s) below which a bubble stops, so it comes to rest
    /// instead of creeping, and redrawing, for ever.
    static let restSpeed = 1.0

    /// Advances `bubbles` by `dt` seconds inside `bounds`. The
    /// `held` bubble follows the pointer, so it pushes others but is not
    /// moved by any force itself.
    @MainActor
    static func step(
        _ bubbles: [Bubble], bounds: CGSize, held: Bubble?, dt: Double
    ) {
        var accel = [CGPoint](repeating: .zero, count: bubbles.count)

        for i in bubbles.indices where bubbles[i].isFree {
            for j in bubbles.indices where j > i && bubbles[j].isFree {
                let (a, b) = (bubbles[i], bubbles[j])
                let (dist, dir) = separation(a, b)
                let minDist = personalSpace * (roundness(a) + roundness(b))
                guard dist < minDist else { continue }
                let (ma, mb) = (mass(a), mass(b))
                let closingSpeed = (a.velocity - b.velocity).dot(dir)
                let damping = pushDamping * 2 * (pushStiffness * ma * mb / (ma + mb)).squareRoot()
                // Never pull: separating bubbles should not stick together.
                let push = max(pushStiffness * (minDist - dist) + damping * closingSpeed, 0)
                accel[i] = accel[i] - dir * (push / ma)
                accel[j] = accel[j] + dir * (push / mb)
                // Their jelly feels the bump, and is pressed flat against the
                // other's edge while the push lasts.
                a.knock(dir * (-push / ma * dt))
                b.knock(dir * (push / mb * dt))
                if push > 0 {
                    let (edgeA, edgeB) = (reach(a, along: dir), reach(b, along: dir))
                    let overlap = (a.center + dir * edgeA - (b.center - dir * edgeB)).dot(dir)
                    b.press(
                        at: b.center - dir * (edgeB - min(overlap, dent * edgeB)), toward: dir)
                    a.press(
                        at: a.center + dir * (edgeA - min(overlap, dent * edgeA)),
                        toward: dir * -1)
                }
            }
        }

        for (bubble, accel) in zip(bubbles, accel) where bubble.isFree {
            if bubble !== held {
                var velocity = (bubble.velocity + accel * dt) * exp(-friction * dt)
                let speed = velocity.length
                if speed > maxSpeed {
                    velocity = velocity * (maxSpeed / speed)
                } else if speed < restSpeed && accel == .zero {
                    velocity = .zero
                }
                if velocity != bubble.velocity {
                    bubble.velocity = velocity
                }
                if velocity != .zero {
                    bubble.center = bubble.center + velocity * dt
                }
            }
            confine(bubble, to: bounds)
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
        -> (distance: Double, direction: CGPoint)
    {
        let (ra, rb) = (roundness(a), roundness(b))
        // How far the cores reach from the center each way, together.
        let reach = CGPoint(
            x: a.frame.width / 2 - ra + b.frame.width / 2 - rb,
            y: a.frame.height / 2 - ra + b.frame.height / 2 - rb)
        let delta = b.center - a.center
        let sign = CGPoint(x: delta.x < 0 ? -1 : 1, y: delta.y < 0 ? -1 : 1)
        let gap = CGPoint(x: abs(delta.x) - reach.x, y: abs(delta.y) - reach.y)
        if gap.x > 0 || gap.y > 0 {
            let apart = CGPoint(x: max(gap.x, 0) * sign.x, y: max(gap.y, 0) * sign.y)
            let distance = apart.length
            return (distance, apart * (1 / distance))
        }
        return gap.x > gap.y
            ? (gap.x, CGPoint(x: sign.x, y: 0)) : (gap.y, CGPoint(x: 0, y: sign.y))
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

    /// Keeps the whole bubble inside `bounds`, bouncing it off any edge it hits.
    @MainActor
    private static func confine(_ bubble: Bubble, to bounds: CGSize) {
        let half = CGPoint(x: bubble.frame.width / 2, y: bubble.frame.height / 2)
        var center = bubble.center
        var velocity = bubble.velocity
        func clamp(_ c: inout CGFloat, _ v: inout CGFloat, half: CGFloat, size: CGFloat) {
            let (lo, hi) = (half, size - half)
            if lo > hi {
                // The screen is smaller than the bubble: just center it.
                c = size / 2
                v = 0
            } else if c < lo {
                c = lo
                v = abs(v) * bounce
            } else if c > hi {
                c = hi
                v = -abs(v) * bounce
            }
        }
        clamp(&center.x, &velocity.x, half: half.x, size: bounds.width)
        clamp(&center.y, &velocity.y, half: half.y, size: bounds.height)
        if center != bubble.center { bubble.center = center }
        if velocity != bubble.velocity { bubble.velocity = velocity }
    }
}
