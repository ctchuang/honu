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
    /// Where it is flying to, or where it is.
    var destination: CGPoint
    var isOpen = false
    let closedSide: CGFloat
    let panelSize: CGSize
    /// What the bubble keeps for itself about its item, made by its microapp.
    @ObservationIgnored let viewState: AnyObject?
    /// Scale while flying out of the turtle or into the octopus.
    var scale: CGFloat = 1
    /// Flying out of the turtle or back from the octopus; it cannot be grabbed until it lands.
    var isInFlight = false
    /// Held over the octopus, where letting go deletes it; it shrinks.
    var isDoomed = false
    /// In the octopus's stomach, out of sight, until it is forgotten or spat back.
    var isSwallowed = false

    static let doomedScale: CGFloat = 0.6

    init(
        id: BubbleID, target: ViewTarget, center: CGPoint, appearance: Appearance,
        viewState: AnyObject?
    ) {
        self.id = id
        self.target = target
        self.center = center
        destination = center
        closedSide = appearance.closedSide
        panelSize = appearance.panelSize
        self.viewState = viewState
    }

    var size: CGSize {
        isOpen ? panelSize : CGSize(width: closedSide, height: closedSide)
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

    /// Whether the pointer can pick it up.
    var isGrabbable: Bool { !isInFlight && !isSwallowed }
}

/// Every bubble in back-to-front paint order (pressing on a bubble moves it
/// to the top), and how they are picked up, dragged, opened, and spat out.
/// Bubbles swallowed by the octopus stay here too, out of sight, until it
/// forgets them. The stage knows nothing of what a bubble shows.
@Observable
@MainActor
final class Stage {
    private(set) var bubbles: [Bubble] = []
    let size: CGSize
    @ObservationIgnored private var nextID = 1
    /// The bubble being dragged, always the top one, and where it was picked up.
    private(set) var drag: (bubble: Bubble, home: CGPoint)?

    /// How far a new panel steps aside from one already in its place.
    static let cascadeStep: CGFloat = 28
    /// Most steps aside a new panel takes before landing where it is.
    private static let cascadeLimit = 10
    /// Gap kept between a panel and the edges of the screen.
    private static let margin: CGFloat = 16

    init(size: CGSize) {
        self.size = size
    }

    var isDragging: Bool { drag != nil }

    /// Puts a new bubble on top, below a bubble being dragged, which must stay on top.
    @discardableResult
    func add(target: ViewTarget, center: CGPoint, appearance: Appearance, viewState: AnyObject?)
        -> Bubble
    {
        let bubble = Bubble(
            id: BubbleID(rawValue: nextID), target: target, center: center,
            appearance: appearance, viewState: viewState)
        nextID += 1
        putOnTop(bubble)
        return bubble
    }

    private func putOnTop(_ bubble: Bubble) {
        bubbles.insert(bubble, at: bubbles.count - (isDragging ? 1 : 0))
    }

    /// The topmost bubble under `point` that can be picked up.
    func bubble(at point: CGPoint) -> Bubble? {
        bubbles.last { $0.isGrabbable && $0.frame.insetBy(dx: -2, dy: -2).contains(point) }
    }

    /// Whether any bubble shows `target`, counting swallowed bubbles that
    /// can still be brought back.
    func shows(_ target: ViewTarget) -> Bool {
        bubbles.contains { $0.target == target }
    }

    /// Moves `bubble` to the top.
    func raise(_ bubble: Bubble) {
        guard let index = bubbles.firstIndex(where: { $0 === bubble }),
            index != bubbles.count - 1
        else { return }
        bubbles.append(bubbles.remove(at: index))
    }

    func remove(_ id: BubbleID) -> Bubble? {
        guard let index = bubbles.firstIndex(where: { $0.id == id }) else { return nil }
        return bubbles.remove(at: index)
    }

    func bubble(_ id: BubbleID) -> Bubble? {
        bubbles.first { $0.id == id }
    }

    /// Opens or closes `bubble` with a springy morph, nudging an open panel
    /// back on screen.
    func toggle(_ bubble: Bubble) {
        withAnimation(.bouncy(duration: 0.5, extraBounce: 0.15)) {
            bubble.isOpen.toggle()
            bubble.center = clamped(bubble.center, size: bubble.size)
            bubble.destination = bubble.center
        }
    }

    /// Keeps a bubble of `size` centered at `point` on screen.
    private func clamped(_ point: CGPoint, size bubbleSize: CGSize) -> CGPoint {
        let half = CGSize(
            width: bubbleSize.width / 2 + Self.margin, height: bubbleSize.height / 2 + Self.margin)
        return CGPoint(
            x: min(max(point.x, half.width), max(size.width - half.width, half.width)),
            y: min(max(point.y, half.height), max(size.height - half.height, half.height)))
    }

    // MARK: Dragging

    /// Picks up `bubble`, which moves to the top.
    func startDrag(_ bubble: Bubble) {
        raise(bubble)
        drag = (bubble, bubble.center)
    }

    /// How far the dragged bubble is from where it was picked up.
    var dragDistance: CGFloat? {
        guard let drag else { return nil }
        return hypot(drag.bubble.center.x - drag.home.x, drag.bubble.center.y - drag.home.y)
    }

    /// Moves the dragged bubble `translation` away from where it was picked
    /// up. A `doomed` bubble, held where letting go deletes it, shrinks.
    func dragged(by translation: CGSize, doomed: Bool) {
        guard let drag else { return }
        drag.bubble.center = CGPoint(
            x: drag.home.x + translation.width, y: drag.home.y + translation.height)
        drag.bubble.destination = drag.bubble.center
        if drag.bubble.isDoomed != doomed {
            withAnimation(.spring(duration: 0.25)) { drag.bubble.isDoomed = doomed }
        }
    }

    /// Lets go of the dragged bubble, returning it and where it was picked up.
    func endDrag() -> (bubble: Bubble, home: CGPoint)? {
        defer { drag = nil }
        return drag
    }

    // MARK: Flying in and out

    /// Has `bubble`, just added, pop out of `mouth` and fly to a place up and
    /// to the right of it, where it opens into its panel.
    func spitPanel(_ bubble: Bubble, from mouth: CGPoint) {
        // Land with the whole panel on screen.
        var place = clamped(
            CGPoint(
                x: mouth.x + bubble.panelSize.width / 2 + 40,
                y: mouth.y - bubble.panelSize.height / 2 - 20),
            size: bubble.panelSize)
        // Open panels don't push each other aside, so step down and to the
        // right of any panel already there, as windows cascade.
        for _ in 0..<Self.cascadeLimit {
            let taken = bubbles.contains {
                $0 !== bubble && ($0.isOpen || $0.isInFlight) && !$0.isSwallowed
                    && hypot($0.destination.x - place.x, $0.destination.y - place.y)
                        < Self.cascadeStep
            }
            if !taken { break }
            place = clamped(
                CGPoint(x: place.x + Self.cascadeStep, y: place.y + Self.cascadeStep),
                size: bubble.panelSize)
        }
        fly(bubble, from: mouth, to: place, openOnLanding: true)
    }

    /// Sends `bubble` into the octopus's `mouth`, where it stays out of sight.
    func swallow(_ bubble: Bubble, into mouth: CGPoint) {
        bubble.isInFlight = true
        bubble.destination = mouth
        withAnimation(.easeIn(duration: 0.3)) {
            bubble.center = mouth
            bubble.scale = 0.05
            bubble.isSwallowed = true
        }
    }

    /// Brings swallowed `bubble` back on top: it pops out of `mouth` and
    /// flies back to `home`, opening again there if it was open.
    func spitBack(_ bubble: Bubble, from mouth: CGPoint, to home: CGPoint) {
        guard let index = bubbles.firstIndex(where: { $0 === bubble }) else { return }
        bubbles.remove(at: index)
        putOnTop(bubble)
        let wasOpen = bubble.isOpen
        // Fly back closed, like any new bubble.
        bubble.isOpen = false
        bubble.isDoomed = false
        bubble.isSwallowed = false
        fly(bubble, from: mouth, to: home, openOnLanding: wasOpen)
    }

    /// Flies `bubble` from `start`, small, to `place`, growing on the way.
    private func fly(_ bubble: Bubble, from start: CGPoint, to place: CGPoint, openOnLanding: Bool)
    {
        bubble.isInFlight = true
        bubble.center = start
        bubble.destination = place
        bubble.scale = 0.15
        // Let the bubble show at the start first, so the flight animates from there.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
            withAnimation(.spring(duration: 0.8, bounce: 0.2)) {
                bubble.center = place
                bubble.scale = 1
            } completion: {
                bubble.isInFlight = false
                if openOnLanding && !bubble.isOpen && !bubble.isSwallowed {
                    self.toggle(bubble)
                }
            }
        }
    }
}
