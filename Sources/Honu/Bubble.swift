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
    /// Whether its item is being worked on, which makes it breathe.
    var isBusy = false
    /// How strongly it breathes, easing between 0 and 1 with `isBusy`.
    private(set) var breath: Double = 0
    /// Seconds of breathing so far, for its rhythm.
    private(set) var breathTime: Double = 0
    /// The motion being played and how many seconds into it.
    private(set) var motion: (motion: Motion, time: Double)?

    static let doomedScale: CGFloat = 0.6
    /// Seconds a flight out of the turtle or back from the octopus lasts.
    nonisolated static let spawnSeconds: Double = 1.6
    /// Seconds a bubble takes to go down into the octopus.
    nonisolated static let swallowSeconds: Double = 0.3
    /// How far a busy bubble's glass swells at the height of each breath.
    static let breathPoints: CGFloat = 4
    /// Breaths per second while busy.
    static let breathRate: Double = 0.8
    /// How quickly breathing fades in and out (1/s), so it never starts or stops abruptly.
    static let breathFadeRate: Double = 3

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

    /// How far the glass swells this frame from breathing. Only the glass
    /// swells, so the content and hit-testing hold still.
    var swell: CGFloat {
        Self.breathPoints * breath * (0.5 - 0.5 * cos(2 * .pi * Self.breathRate * breathTime))
    }

    /// How far the motion being played moves the whole bubble this frame.
    var motionOffset: CGSize {
        motion.map { $0.motion.offset(at: $0.time) } ?? .zero
    }

    /// Starts playing `motion`, replacing any motion being played.
    func play(_ motion: Motion) {
        self.motion = (motion, 0)
    }

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

    /// Advances the breathing, the motion, and the flight by `dt` seconds.
    /// Returns whether the bubble just landed and should open.
    func animate(dt: Double) -> Bool {
        let target: Double = isBusy ? 1 : 0
        if breath != target {
            breath += (target - breath) * (1 - exp(-Self.breathFadeRate * dt))
            if abs(breath - target) < 0.001 {
                breath = target
            }
        }
        if breath > 0 {
            breathTime += dt
        } else if breathTime != 0 {
            breathTime = 0
        }
        if let (motion, time) = motion {
            self.motion = time + dt < motion.seconds ? (motion, time + dt) : nil
        }

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

/// A short motion that marks a change in what a bubble is doing.
enum Motion: Equatable, Sendable {
    /// Floats up a little and settles back: something finished.
    case rise
    /// Shakes side to side: something needs the user.
    case wobble

    var seconds: Double {
        switch self {
        case .rise: 1.2
        case .wobble: 0.6
        }
    }

    /// How far the motion moves the bubble `time` seconds in; back to zero by the end.
    func offset(at time: Double) -> CGSize {
        let u = min(max(time / seconds, 0), 1)
        switch self {
        case .rise:
            return CGSize(width: 0, height: -16 * sin(.pi * u))
        case .wobble:
            let shake = sin(2 * .pi * 5 * time)
            return CGSize(width: 8 * shake * (1 - u) * (1 - u), height: 0)
        }
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
