import SwiftUI

/// The pixel-art octopus that deletes bubbles. It rises from the bottom edge
/// while a bubble is being dragged, in the corner away from the turtle, and
/// stays out of sight the rest of the time. A bubble dropped on it is
/// swallowed. For a few seconds afterwards the octopus waits with the bubble
/// still inside, and clicking it (or pressing ⌘Z) spits the bubble back to
/// where it was picked up, so a slip of the hand loses nothing.
@Observable
@MainActor
final class Octopus {
    /// The head and body, one character per pixel: Outline, Body, White
    /// highlight, Eye (also the mouth), Pink cheek, and `.` for transparent.
    static let head = [
        "......OOOOOO......",
        "....OOBBBBBBOO....",
        "...OBBWWBBBBBBO...",
        "..OBBWBBBBBBBBBO..",
        "..OBBBBBBBBBBBBO..",
        "..OBBWEBBBBWEBBO..",
        "..OBBEEBBBBEEBBO..",
        "..OBBBBBBBBBBBBO..",
        "..OBPBBBEEBBBPBO..",
        "..OBBBBBBBBBBBBO..",
        ".OBBBBBBBBBBBBBBO.",
    ]
    /// The tentacles below the head, in two frames that sway them left and right.
    static let tentacles = [
        [
            ".OBBOBBOBBOBBOBBO.",
            ".OBBOBBOBBOBBOBBO.",
            "OBBOBBOBBOBBOBBO..",
            ".OO.OO.OO.OO.OO...",
        ],
        [
            ".OBBOBBOBBOBBOBBO.",
            ".OBBOBBOBBOBBOBBO.",
            "..OBBOBBOBBOBBOBBO",
            "...OO.OO.OO.OO.OO.",
        ],
    ]
    private static let frames = tentacles.map { PixelGrid(head + $0) }
    /// Pixels (column, row) that turn dark when the mouth opens wide.
    static let openMouth = [(8, 9), (9, 9)]
    private static let openFrames = frames.map { $0.replacing(openMouth, with: "E") }
    /// Where swallowed bubbles go in and spat-out ones come out, in sprite pixels.
    private static let mouth = CGPoint(x: 9, y: 9)
    /// Gap between the octopus and the corner of the screen.
    private static let margin: CGFloat = 24
    /// How far from the octopus's middle the pointer may be for a dropped
    /// bubble to be swallowed. Wider than the sprite, so dropping takes no aim.
    private static let reach: CGFloat = 80
    /// Seconds a swallowed bubble can still be brought back.
    static let undoSeconds: TimeInterval = 5
    /// Seconds a bubble takes to go down, and the gulp afterwards lasts.
    private static let swallowSeconds = Bubble.swallowSeconds
    private static let gulpSeconds: TimeInterval = 0.3
    /// Tentacle sways per second while idle and while eagerly waiting for a drop.
    private static let swayRate: Double = 2
    private static let eagerSwayRate: Double = 6

    /// A bubble the octopus swallowed, and where it was picked up, to return
    /// it there. The bubble itself stays on the stage, out of sight.
    struct Swallowed {
        let bubble: BubbleID
        let home: CGPoint
        let at: TimeInterval
    }

    let stageSize: CGSize
    /// Whether it is up, in view, rather than hidden below the bottom edge.
    private(set) var isUp = false
    /// Whether it sits in the bottom-right corner rather than the bottom-left.
    private(set) var isRight = true
    /// Whether a bubble is being dragged, which calls the octopus up.
    private var isSummoned = false
    /// Whether a bubble is held over it, ready to be dropped.
    var isEager = false
    private var spatAt = -TimeInterval.infinity
    /// Until when swallowed bubbles can be brought back.
    private(set) var undoUntil = -TimeInterval.infinity
    /// Bubbles swallowed recently enough to be brought back, the latest last.
    private(set) var stomach: [Swallowed] = []

    init(stageSize: CGSize) {
        self.stageSize = stageSize
    }

    var size: CGSize { Self.frames[0].size }

    /// Top-left corner of the sprite when up.
    var origin: CGPoint {
        CGPoint(
            x: isRight ? stageSize.width - Self.margin - size.width : Self.margin,
            y: stageSize.height - Self.margin - size.height)
    }

    /// How far below `origin` it hides when not up.
    var hiddenDrop: CGFloat { size.height + Self.margin }

    var middle: CGPoint {
        CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    }

    var canUndo: Bool { !stomach.isEmpty }

    /// Where swallowed bubbles go in and spat-out ones come out.
    var mouth: CGPoint {
        CGPoint(
            x: origin.x + Self.mouth.x * spritePixel, y: origin.y + Self.mouth.y * spritePixel)
    }

    /// Calls the octopus up while `summoned`, as while a bubble is dragged,
    /// rising in the corner farther from the turtle at `turtle`.
    func summon(_ summoned: Bool, turtle: CGPoint) {
        isSummoned = summoned
        if !isUp {
            // Only pick a corner while out of sight, so it never jumps sideways.
            isRight = turtle.x < stageSize.width / 2
        }
        rise()
    }

    /// Rises or sinks to match what it is wanted for.
    private func rise() {
        let wanted = isSummoned || canUndo
        if wanted != isUp {
            withAnimation(.easeOut(duration: 0.3)) { isUp = wanted }
        }
    }

    /// Whether a bubble dropped with the pointer at `point` would be swallowed.
    func inReach(_ point: CGPoint) -> Bool {
        isUp && hypot(point.x - middle.x, point.y - middle.y) < Self.reach
    }

    /// Where the "Click to undo" hint is drawn, above the octopus.
    var hintCenter: CGPoint {
        CGPoint(x: middle.x, y: origin.y - 18)
    }

    /// Whether `point` is on one of the octopus's visible pixels or on its undo hint.
    func contains(_ point: CGPoint) -> Bool {
        guard isUp else { return false }
        if canUndo && abs(point.x - hintCenter.x) < 56 && abs(point.y - hintCenter.y) < 14 {
            return true
        }
        let grid = Self.frames[0]
        guard let (x, y) = grid.pixel(at: point, origin: origin) else { return false }
        return grid.pixel(x, y) != "."
    }

    /// Swallows `bubble`, which was picked up at `home`, at `time`.
    func swallow(_ bubble: BubbleID, home: CGPoint, at time: TimeInterval = now()) {
        stomach.append(Swallowed(bubble: bubble, home: home, at: time))
        undoUntil = time + Self.swallowSeconds + Self.undoSeconds
        rise()
    }

    /// Spits out the latest swallowed bubble, returning it; it should fly
    /// back to where it was picked up from `mouth`.
    func spitBack(at time: TimeInterval = now()) -> Swallowed? {
        guard let swallowed = stomach.popLast() else { return nil }
        spatAt = time
        // Leave time to bring back the one swallowed before it, too.
        undoUntil = time + Self.undoSeconds
        rise()
        return swallowed
    }

    /// Forgets bubbles too old to bring back at `time`, returning them; they
    /// are now deleted for good.
    func forget(at time: TimeInterval = now()) -> [BubbleID] {
        guard canUndo, time >= undoUntil else { return [] }
        let gone = stomach.map(\.bubble)
        stomach = []
        rise()
        return gone
    }

    /// How far it is lifted at `time`: a sprite pixel while gulping or eager.
    func lift(at time: TimeInterval) -> CGFloat {
        let gulp = { (since: TimeInterval) in (0..<Self.gulpSeconds).contains(time - since) }
        let gulping = gulp(spatAt) || stomach.contains { gulp($0.at + Self.swallowSeconds) }
        return gulping || isEager ? spritePixel : 0
    }

    /// The sprite at `time`, with the tentacles swaying and the mouth open
    /// while eager or swallowing.
    func grid(at time: TimeInterval) -> PixelGrid {
        let rate = isEager ? Self.eagerSwayRate : Self.swayRate
        let frame = Int(time * rate) % 2
        let swallowing = stomach.contains { time - $0.at < Self.swallowSeconds }
        return isEager || swallowing ? Self.openFrames[frame] : Self.frames[frame]
    }

    /// How visible the undo hint is at `time`, fading out over its last second.
    func hintOpacity(at time: TimeInterval) -> Double {
        canUndo ? min(max(undoUntil - time, 0), 1) : 0
    }

    static func color(_ c: Character) -> Color? {
        switch c {
        case "O": Color(rgb: 118, 46, 90)
        case "B": Color(rgb: 236, 120, 158)
        case "W": .white
        case "E": Color(rgb: 48, 22, 40)
        case "P": Color(rgb: 255, 182, 204)
        default: nil
        }
    }
}
