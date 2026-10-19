import Foundation

/// Bubble motion: momentum after a throw, an idle float, soft pushing between
/// crowded bubbles, and bounces off the screen edges. Open bubbles act like
/// windows: they can still be thrown, but they neither float nor push.
/// Bubbles flying out of the turtle or into the octopus follow their own
/// path and are left alone.
enum Physics {
    /// Velocity decay rate (1/s); higher stops a thrown bubble sooner.
    static let friction = 4.0
    /// Peak acceleration (points/s²) of the idle float.
    static let floatAcceleration = 14.0
    /// Bubbles only push each other once their centers are closer than this
    /// fraction of the sum of their radii, so partial overlaps (which show
    /// off the glass) are left alone.
    static let personalSpace = 0.8
    /// Spring stiffness of the push between crowded bubbles; a bubble of
    /// radius 100 pressed in by 1 point is pushed back at this many points/s².
    static let pushStiffness = 160.0
    /// Damping of that push relative to critical damping. It soaks up the
    /// impact when bubbles collide, so they bump and share momentum instead
    /// of jiggling.
    static let pushDamping = 0.45
    /// Fraction of speed kept after bouncing off a screen edge.
    static let bounce = 0.5
    /// Speed limit (points/s) for thrown bubbles.
    static let maxSpeed = 2500.0

    /// Advances `bubbles` by `dt` seconds at `time` inside `bounds`. The
    /// `held` bubble follows the pointer, so it pushes others but is not
    /// moved by any force itself.
    @MainActor
    static func step(
        _ bubbles: [Bubble], bounds: CGSize, held: Bubble?, time: Double, dt: Double
    ) {
        let floating = { (b: Bubble) in b.isFree && !b.isOpen }
        var accel = bubbles.map { floating($0) ? floatAccel($0, time: time) : .zero }

        for i in bubbles.indices {
            for j in bubbles.indices where j > i {
                let (a, b) = (bubbles[i], bubbles[j])
                guard floating(a), floating(b) else { continue }
                let delta = b.center - a.center
                let dist = delta.length
                let minDist = personalSpace * (radius(a) + radius(b))
                guard dist < minDist else { continue }
                let dir = dist > 1e-3 ? delta * (1 / dist) : CGPoint(x: 1, y: 0)
                let (ma, mb) = (mass(a), mass(b))
                let closingSpeed = (a.velocity - b.velocity).dot(dir)
                let damping = pushDamping * 2 * (pushStiffness * ma * mb / (ma + mb)).squareRoot()
                // Never pull: separating bubbles should not stick together.
                let push = max(pushStiffness * (minDist - dist) + damping * closingSpeed, 0)
                accel[i] = accel[i] - dir * (push / ma)
                accel[j] = accel[j] + dir * (push / mb)
            }
        }

        for (bubble, accel) in zip(bubbles, accel) where bubble.isFree {
            if bubble !== held {
                var velocity = (bubble.velocity + accel * dt) * exp(-friction * dt)
                let speed = velocity.length
                if speed > maxSpeed {
                    velocity = velocity * (maxSpeed / speed)
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

    /// A slow, per-bubble wobble so idle bubbles drift instead of sitting still.
    @MainActor
    private static func floatAccel(_ bubble: Bubble, time: Double) -> CGPoint {
        let t = time + bubble.phase
        return CGPoint(x: sin(t * 0.6), y: cos(t * 0.45)) * floatAcceleration
    }

    @MainActor
    private static func radius(_ bubble: Bubble) -> Double {
        bubble.closedSide / 2
    }

    /// Bigger bubbles are heavier and get pushed around less.
    @MainActor
    private static func mass(_ bubble: Bubble) -> Double {
        pow(radius(bubble) / 100, 2)
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
