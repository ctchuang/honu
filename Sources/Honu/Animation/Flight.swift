import Foundation

/// A bubble's trip along a path of its own.
struct Flight {
    enum Kind {
        /// Out of the turtle, or back out of the octopus.
        case spawn(openOnLanding: Bool)
        /// Into the octopus, from a bubble already drawn at `fromScale`.
        case swallow(fromScale: CGFloat)
    }

    let kind: Kind
    let from: CGPoint
    let to: CGPoint
    /// Linear progress, from 0 to 1.
    var progress: Double = 0

    /// The flight `elapsed` seconds after it started.
    func after(_ elapsed: Double) -> Flight {
        var flight = self
        flight.progress = min(max(elapsed / seconds, 0), 1)
        return flight
    }

    var seconds: Double {
        switch kind {
        case .spawn: Bubble.spawnSeconds
        case .swallow: Bubble.swallowSeconds
        }
    }

    var position: CGPoint {
        let t =
            switch kind {
            case .spawn: easeOutQuad(progress)
            // Speeding up as it goes down.
            case .swallow: progress * progress
            }
        return CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
    }

    var scale: CGFloat {
        switch kind {
        // Squaring the progress keeps the bubble small for longer as it
        // leaves, so it visibly grows on the way instead of all at once.
        case .spawn: easeOutBack(progress * progress)
        case .swallow(let fromScale): fromScale * (1 - progress * progress)
        }
    }
}
