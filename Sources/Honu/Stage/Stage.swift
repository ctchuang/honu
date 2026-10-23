import SwiftUI

/// Every bubble in back-to-front paint order (pressing on a bubble moves it
/// to the top), and how they are picked up, dragged, spat out, and set
/// moving.
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
    /// The bubble being resized, always the top one, the edges it moves, and
    /// its frame when resizing started.
    private var resize: (bubble: Bubble, edges: Edges, start: CGRect)?

    /// How far a new bubble steps aside from one already in its place.
    static let cascadeStep: CGFloat = 28
    /// Most steps aside a new bubble takes before landing where it is.
    private static let cascadeLimit = 10
    /// Gap kept between a bubble and the edges of the screen.
    private static let margin: CGFloat = 16

    init(size: CGSize) {
        self.size = size
    }

    var isDragging: Bool { drag != nil }

    /// The middle of the screen.
    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }

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
        bubbles.last { $0.isGrabbable && $0.contains(point) }
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
        guard !isResizing else { return }
        raise(bubble)
        drag = (bubble, bubble.center)
    }

    /// How far the dragged bubble is from where it was picked up.
    var dragDistance: CGFloat? {
        guard let drag else { return nil }
        return (drag.bubble.center - drag.home).length
    }

    /// Moves the dragged bubble `translation` away from where it was picked
    /// up, remembering the pointer's `velocity` so it keeps gliding when let
    /// go. A `doomed` bubble, held where letting go deletes it, shrinks.
    func dragged(by translation: CGSize, velocity: CGSize = .zero, doomed: Bool) {
        guard let drag else { return }
        drag.bubble.center = CGPoint(
            x: drag.home.x + translation.width, y: drag.home.y + translation.height)
        drag.bubble.velocity = CGPoint(x: velocity.width, y: velocity.height)
        if drag.bubble.isDoomed != doomed {
            withAnimation(.spring(duration: 0.25)) { drag.bubble.isDoomed = doomed }
        }
    }

    /// Lets go of the dragged bubble, returning it and where it was picked up.
    func endDrag() -> (bubble: Bubble, home: CGPoint)? {
        defer { drag = nil }
        return drag
    }

    // MARK: Resizing

    var isResizing: Bool { resize != nil }

    /// The edges of `bubble` being resized, if it is.
    func resizedEdges(of bubble: Bubble) -> Edges? {
        resize.flatMap { $0.bubble === bubble ? $0.edges : nil }
    }

    /// Starts resizing `bubble` by moving its `edges`, which brings it to the
    /// top and holds it still.
    func startResize(_ bubble: Bubble, edges: Edges) {
        guard !isDragging, !edges.isEmpty, bubble.isGrabbable else { return }
        raise(bubble)
        bubble.velocity = .zero
        resize = (bubble, edges, bubble.frame)
    }

    /// Moves the edges being resized `translation` away from where they
    /// were when resizing started. The opposite edges stay put, the size
    /// stays between the bubble's minimum and the screen, and the bubble
    /// stays on screen. The new size is the user's size.
    func resized(by translation: CGSize) {
        guard let (bubble, edges, start) = resize else { return }
        let (minX, maxX) = Self.resizedSpan(
            start.minX, start.maxX, by: translation.width,
            moving: (edges.contains(.left), edges.contains(.right)),
            min: bubble.minSize.width, within: size.width - Self.margin)
        let (minY, maxY) = Self.resizedSpan(
            start.minY, start.maxY, by: translation.height,
            moving: (edges.contains(.top), edges.contains(.bottom)),
            min: bubble.minSize.height, within: size.height - Self.margin)
        bubble.userSize = CGSize(width: maxX - minX, height: maxY - minY)
        bubble.isZoomed = false
        bubble.center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }

    /// One side of a resized frame: the span from `low` to `high`, with the
    /// `moving` ends moved `delta`, no shorter than `min`, and inside
    /// `margin` to `limit`.
    private static func resizedSpan(
        _ low: CGFloat, _ high: CGFloat, by delta: CGFloat, moving: (low: Bool, high: Bool),
        min shortest: CGFloat, within limit: CGFloat
    ) -> (CGFloat, CGFloat) {
        let shortest = Swift.min(shortest, limit - margin)
        var (low, high) = (low, high)
        if moving.low {
            low = Swift.min(Swift.max(low + delta, margin), high - shortest)
        }
        if moving.high {
            high = Swift.max(Swift.min(high + delta, limit), low + shortest)
        }
        return (low, high)
    }

    /// Stops resizing, returning the bubble that was resized.
    @discardableResult
    func endResize() -> Bubble? {
        defer { resize = nil }
        return resize?.bubble
    }

    /// Gives `bubble` the user's `size`, as when it was saved, fitting it
    /// between its minimum and the screen and keeping it on screen.
    func setUserSize(of bubble: Bubble, to size: CGSize, zoomed: Bool) {
        let largest = CGSize(
            width: self.size.width - 2 * Self.margin, height: self.size.height - 2 * Self.margin)
        bubble.userSize = CGSize(
            width: max(min(size.width, largest.width), min(bubble.minSize.width, largest.width)),
            height: max(
                min(size.height, largest.height), min(bubble.minSize.height, largest.height)))
        bubble.isZoomed = zoomed
        bubble.center = clamped(bubble.center, size: bubble.size)
    }

    /// Zooms `bubble` as a window zooms: from the user's size to its
    /// microapp's, or back, easing to the new size and keeping it on
    /// screen. A bubble never resized does not zoom. Returns whether it did.
    @discardableResult
    func zoom(_ bubble: Bubble) -> Bool {
        guard bubble.userSize != nil else { return false }
        withAnimation(.smooth(duration: 0.3)) {
            bubble.isZoomed.toggle()
            bubble.center = clamped(bubble.center, size: bubble.size)
        }
        return true
    }

    // MARK: Flying in and out

    /// Has `bubble`, just added, pop out of `mouth` and fly to a place up and
    /// to the right of it.
    func spit(_ bubble: Bubble, from mouth: CGPoint) {
        // Land with the whole bubble on screen.
        var place = clamped(
            CGPoint(
                x: mouth.x + bubble.size.width / 2 + 40,
                y: mouth.y - bubble.size.height / 2 - 20),
            size: bubble.size)
        // Step down and to the right of any bubble already there, as windows
        // cascade, so the two push apart diagonally rather than stacked.
        for _ in 0..<Self.cascadeLimit {
            let taken = bubbles.contains {
                $0 !== bubble && !$0.isSwallowed
                    && ($0.destination - place).length < Self.cascadeStep
            }
            if !taken { break }
            place = clamped(
                CGPoint(x: place.x + Self.cascadeStep, y: place.y + Self.cascadeStep),
                size: bubble.size)
        }
        bubble.fly(from: mouth, to: place)
    }

    /// Sends `bubble` into the octopus's `mouth`, where it stays out of sight.
    func swallow(_ bubble: Bubble, into mouth: CGPoint) {
        bubble.swallow(into: mouth)
    }

    /// Brings swallowed `bubble` back on top: it pops out of `mouth` and
    /// flies back to `home`.
    func spitBack(_ bubble: Bubble, from mouth: CGPoint, to home: CGPoint) {
        guard let index = bubbles.firstIndex(where: { $0 === bubble }) else { return }
        bubbles.remove(at: index)
        putOnTop(bubble)
        bubble.fly(from: mouth, to: home)
    }

    /// Advances every bubble's flight and motion by `dt` seconds. A dragged
    /// or resized bubble follows the pointer instead of the physics.
    func step(dt: Double) {
        for bubble in bubbles {
            bubble.animate(dt: dt)
        }
        Physics.step(bubbles, bounds: size, held: drag?.bubble ?? resize?.bubble, dt: dt)
    }
}
