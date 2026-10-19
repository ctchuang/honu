import Foundation

/// Starts moving and slows to a smooth stop.
func easeOutQuad(_ t: Double) -> Double {
    1 - (1 - t) * (1 - t)
}

/// Eases out with a small overshoot, so bubbles pop out.
func easeOutBack(_ t: Double) -> Double {
    let u = t - 1
    return 1 + 2 * u * u * u + u * u
}
