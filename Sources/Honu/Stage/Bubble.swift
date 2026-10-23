import SwiftUI

/// Names one bubble on the stage.
struct BubbleID: Hashable, Sendable {
    let rawValue: Int
}

/// One bubble: a view of one item of one microapp, showing the item under
/// its title.
@Observable
@MainActor
final class Bubble: Identifiable {
    let id: BubbleID
    let target: ViewTarget
    var center: CGPoint
    /// Speed and direction, in points per second.
    var velocity: CGPoint = .zero
    /// The size its microapp asks for, which may change, as an Ask chat
    /// grows with its answer.
    var microappSize: CGSize
    /// The size the user last resized it to, if any. It is kept while the
    /// bubble is zoomed to its microapp's size, so zooming can bring it back.
    var userSize: CGSize?
    /// Zoomed to its microapp's size though it has a user's size.
    var isZoomed = false
    /// The smallest the user can resize it to, as its microapp says.
    var minSize: CGSize
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
    /// How deep the rim is at the sides and bottom, around the content.
    static let rimWidth: CGFloat = 10
    /// How deep the rim is at the top, along the outer edge of the title.
    static let topRimWidth: CGFloat = 6
    /// How far from a corner the rim resizes both ways.
    static let cornerReach: CGFloat = 20
    /// Seconds a flight out of the turtle or back from the octopus lasts.
    nonisolated static let spawnSeconds: Double = 0.8
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
        microappSize = appearance.size
        minSize = appearance.minSize
        self.viewState = viewState
    }

    /// Its size at full scale: the user's size, unless it has none or is
    /// zoomed to its microapp's size.
    var size: CGSize {
        if let userSize, !isZoomed { return userSize }
        return microappSize
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

    /// The corner radius of its outline at full size, a little rounder than
    /// a window's.
    var cornerRadius: CGFloat { 30 }

    /// Whether `point` is inside its outline as drawn, so presses on the
    /// transparent area past its rounded corners go to whatever is below.
    func contains(_ point: CGPoint) -> Bool {
        let outline = RoundedRectangle(cornerRadius: cornerRadius * drawnScale, style: .continuous)
        return outline.path(in: frame).contains(point)
    }

    /// Which edges dragging from `point` resizes: those of the rim it is on,
    /// both of a corner within `cornerReach` of it, or none off the rim. The
    /// rim is the glass between the outline and the content, `rimWidth` deep
    /// at the sides and bottom, and only `topRimWidth` at the top, which
    /// leaves the rest of the title for moving the bubble.
    func rimEdges(at point: CGPoint) -> Edges {
        guard contains(point) else { return [] }
        let inner = CGRect(
            x: frame.minX + Self.rimWidth, y: frame.minY + Self.topRimWidth,
            width: frame.width - 2 * Self.rimWidth,
            height: frame.height - Self.topRimWidth - Self.rimWidth)
        let innerOutline = RoundedRectangle(
            cornerRadius: cornerRadius - Self.rimWidth, style: .continuous)
        guard !innerOutline.path(in: inner).contains(point) else { return [] }
        var edges: Edges = []
        if point.x < frame.minX + Self.cornerReach {
            edges.insert(.left)
        } else if point.x > frame.maxX - Self.cornerReach {
            edges.insert(.right)
        }
        if point.y < frame.minY + Self.cornerReach {
            edges.insert(.top)
        } else if point.y > frame.maxY - Self.cornerReach {
            edges.insert(.bottom)
        }
        return edges
    }

    /// Where it is drawn this frame, moved by the motion being played.
    var drawnFrame: CGRect {
        frame.offsetBy(dx: motionOffset.width, dy: motionOffset.height)
    }

    /// Where it is going to rest: where a flight ends, otherwise where it is.
    var destination: CGPoint { flight?.to ?? center }

    var isInFlight: Bool { flight != nil }

    /// Whether it is left to the physics: not following a path of its own.
    var isFree: Bool { !isInFlight && !isSwallowed }

    /// Whether the pointer can pick it up: only while it is free.
    var isGrabbable: Bool { isFree }

    /// Whether it is out of sight in the octopus's stomach.
    var isHidden: Bool { isSwallowed && !isInFlight }

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

    /// Flies from `start`, small, to `place`, growing on the way.
    func fly(from start: CGPoint, to place: CGPoint) {
        isSwallowed = false
        isDoomed = false
        velocity = .zero
        center = start
        flight = Flight(kind: .spawn, from: start, to: place)
    }

    /// Goes down into the octopus's `mouth`, shrinking to nothing.
    func swallow(into mouth: CGPoint) {
        flight = Flight(kind: .swallow(fromScale: drawnScale), from: center, to: mouth)
        isSwallowed = true
        isDoomed = false
        velocity = .zero
    }

    /// Advances the breathing, the motion, and the flight by `dt` seconds.
    func animate(dt: Double) {
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

        guard var flight else { return }
        flight.progress = min(flight.progress + dt / flight.seconds, 1)
        center = flight.position
        self.flight = flight.progress < 1 ? flight : nil
    }
}
