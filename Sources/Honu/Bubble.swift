import SwiftUI

/// Names one bubble on the stage.
struct BubbleID: Hashable, Sendable {
    let rawValue: Int
}

/// One bubble: a view of one item of one microapp. A glass square when
/// closed, a panel showing the item when open.
@Observable
@MainActor
final class Bubble: Identifiable {
    let id: BubbleID
    let target: ViewTarget
    var center: CGPoint
    /// Speed and direction, in points per second.
    var velocity: CGPoint = .zero
    /// Offset in seconds into the idle float, so bubbles drift out of step.
    @ObservationIgnored var phase: Double
    var isOpen = false
    let closedSide: CGFloat
    let panelSize: CGSize
    /// What the bubble keeps for itself about its item, made by its microapp.
    @ObservationIgnored let viewState: AnyObject?
    /// Held over the octopus, where letting go deletes it; it shrinks.
    var isDoomed = false
    /// Dropped on the octopus: on its way into the mouth or out of sight in
    /// the stomach, until it is forgotten or spat back.
    private(set) var isSwallowed = false
    /// The path it is following out of the turtle, back from the octopus,
    /// or into it, rather than the physics or the pointer.
    private(set) var flight: Flight?

    static let doomedScale: CGFloat = 0.6
    /// Seconds a flight out of the turtle or back from the octopus lasts.
    nonisolated static let spawnSeconds: Double = 1.6
    /// Seconds a bubble takes to go down into the octopus.
    nonisolated static let swallowSeconds: Double = 0.3

    init(
        id: BubbleID, target: ViewTarget, center: CGPoint, appearance: Appearance,
        viewState: AnyObject?
    ) {
        self.id = id
        self.target = target
        self.center = center
        phase = Double(id.rawValue) * 37.3
        closedSide = appearance.closedSide
        panelSize = appearance.panelSize
        self.viewState = viewState
    }

    var size: CGSize {
        isOpen ? panelSize : CGSize(width: closedSide, height: closedSide)
    }

    /// Size relative to full size: small, growing (with a little overshoot)
    /// while flying out, and shrinking to nothing on the way into the octopus.
    var scale: CGFloat {
        if let flight { return flight.scale }
        return isSwallowed ? 0 : 1
    }

    /// The scale it is drawn at.
    var drawnScale: CGFloat {
        scale * (isDoomed ? Self.doomedScale : 1)
    }

    /// Where it is drawn, for hit-testing.
    var frame: CGRect {
        let size = CGSize(width: size.width * drawnScale, height: size.height * drawnScale)
        return CGRect(
            x: center.x - size.width / 2, y: center.y - size.height / 2,
            width: size.width, height: size.height)
    }

    /// Where it is going to rest: where a flight ends, otherwise where it is.
    var destination: CGPoint { flight?.to ?? center }

    var isInFlight: Bool { flight != nil }

    /// Whether the pointer can pick it up.
    var isGrabbable: Bool { !isInFlight && !isSwallowed }

    /// Whether it is out of sight in the octopus's stomach.
    var isHidden: Bool { isSwallowed && !isInFlight }

    /// Whether it is left to the physics: not following a path of its own.
    var isFree: Bool { !isInFlight && !isSwallowed }

    /// Flies from `start`, small, to `place`, growing on the way, and opens
    /// on landing if `openOnLanding`.
    func fly(from start: CGPoint, to place: CGPoint, openOnLanding: Bool) {
        isSwallowed = false
        isDoomed = false
        isOpen = false
        velocity = .zero
        center = start
        flight = Flight(kind: .spawn(openOnLanding: openOnLanding), from: start, to: place)
    }

    /// Goes down into the octopus's `mouth`, shrinking to nothing.
    func swallow(into mouth: CGPoint) {
        flight = Flight(kind: .swallow(fromScale: drawnScale), from: center, to: mouth)
        isSwallowed = true
        isDoomed = false
        velocity = .zero
    }

    /// Advances the flight by `dt` seconds. Returns whether the bubble just
    /// landed and should open.
    func animate(dt: Double) -> Bool {
        guard var flight else { return false }
        flight.progress = min(flight.progress + dt / flight.seconds, 1)
        center = flight.position
        if flight.progress < 1 {
            self.flight = flight
            return false
        }
        self.flight = nil
        if case .spawn(let openOnLanding) = flight.kind {
            return openOnLanding
        }
        return false
    }
}

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

/// Starts moving and slows to a smooth stop.
func easeOutQuad(_ t: Double) -> Double {
    1 - (1 - t) * (1 - t)
}

/// Eases out with a small overshoot, so bubbles pop out.
func easeOutBack(_ t: Double) -> Double {
    let u = t - 1
    return 1 + 2 * u * u * u + u * u
}
