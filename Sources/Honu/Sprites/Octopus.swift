import SwiftUI

/// The pixel-art octopus that deletes bubbles, and uninstalls microapps. It
/// rises from the bottom edge while a bubble or a launcher tile is being
/// dragged, in the corner away from the turtle, and stays out of sight the
/// rest of the time, offering in a speech bubble to take what is dragged. A
/// bubble dropped on it is swallowed; a tile dropped on it is swallowed with
/// every bubble of its microapp. For a few seconds afterwards the octopus
/// waits with them still inside, and clicking it (or pressing ⌘Z) spits them
/// back to where they were, so a slip of the hand loses nothing. What it
/// holds is kept in the `Trash`; the octopus shows it.
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
    /// Seconds a bubble takes to go down, and the gulp afterwards lasts.
    private static let swallowSeconds = Bubble.swallowSeconds
    private static let gulpSeconds: TimeInterval = 0.3
    /// Tentacle sways per second while idle and while eagerly waiting for a drop.
    private static let swayRate: Double = 2
    private static let eagerSwayRate: Double = 6
    /// The size of the "Click to undo" hint, which takes clicks too.
    nonisolated static let hintSize = CGSize(width: 112, height: 26)
    /// The gap between the hint and the top of the octopus.
    nonisolated static let hintGap: CGFloat = 6

    /// What is being dragged to it, which its speech bubble names.
    enum Offer {
        case bubble
        case microapp
    }

    let stageSize: CGSize
    /// What it has swallowed that can still come back, which keeps it up.
    let trash: Trash
    /// Whether it is up, in view, rather than hidden below the bottom edge.
    private(set) var isUp = false
    /// Whether it sits in the bottom-right corner rather than the bottom-left.
    private(set) var isRight = true
    /// Whether a bubble or a tile is being dragged, which calls the octopus up.
    private(set) var isSummoned = false
    /// What it offers to take while summoned.
    private(set) var offer = Offer.bubble
    /// Whether a bubble is held over it, ready to be dropped.
    var isEager = false
    private var spatAt = -TimeInterval.infinity

    init(stageSize: CGSize, trash: Trash) {
        self.stageSize = stageSize
        self.trash = trash
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

    /// Whether it says it can take what is dragged: while summoned, in place
    /// of the undo hint.
    var offersHelp: Bool { isUp && isSummoned }

    /// Whether it shows the "Click to undo" hint, which takes clicks.
    var showsUndoHint: Bool { trash.canUndo && !isSummoned }

    /// Where swallowed bubbles go in and spat-out ones come out.
    var mouth: CGPoint {
        PixelGrid.point(Self.mouth, origin: origin)
    }

    /// Calls the octopus up while `summoned`, as while a bubble is dragged,
    /// rising in the corner farther from the turtle at `turtle`, offering to
    /// take `offer`.
    func summon(_ summoned: Bool, turtle: CGPoint, offer: Offer = .bubble) {
        if summoned {
            self.offer = offer
        }
        if summoned != isSummoned {
            withAnimation(.spring(duration: 0.35, bounce: 0.4)) { isSummoned = summoned }
        }
        if !isUp {
            // Only pick a corner while out of sight, so it never jumps sideways.
            isRight = turtle.x < stageSize.width / 2
        }
        riseOrSink()
    }

    /// Rises or sinks to match what it is wanted for: while summoned, or
    /// while the trash holds something it can spit back.
    func riseOrSink() {
        let wanted = isSummoned || trash.canUndo
        if wanted != isUp {
            withAnimation(.easeOut(duration: 0.3)) { isUp = wanted }
        }
    }

    /// Whether a bubble dropped with the pointer at `point` would be swallowed.
    func inReach(_ point: CGPoint) -> Bool {
        isUp && (point - middle).length < Self.reach
    }

    /// Top-left corner of the sprite as drawn at `time`, lifted while
    /// gulping or eager.
    func drawnOrigin(at time: TimeInterval) -> CGPoint {
        CGPoint(x: origin.x, y: origin.y - lift(at: time))
    }

    /// Where the "Click to undo" hint is drawn at `time`, above the octopus.
    func hintCenter(at time: TimeInterval) -> CGPoint {
        CGPoint(x: middle.x, y: drawnOrigin(at: time).y - Self.hintGap - Self.hintSize.height / 2)
    }

    /// Whether `point` is on one of the octopus's visible pixels or on its
    /// undo hint, as they are drawn at `time`: the sprite of that moment,
    /// with its tentacles swayed, lifted if it is.
    func contains(_ point: CGPoint, at time: TimeInterval = now()) -> Bool {
        guard isUp else { return false }
        let hint = hintCenter(at: time)
        if showsUndoHint && abs(point.x - hint.x) < Self.hintSize.width / 2
            && abs(point.y - hint.y) < Self.hintSize.height / 2
        {
            return true
        }
        return grid(at: time).isOpaque(at: point, origin: drawnOrigin(at: time))
    }

    /// Spits something back out of the trash at `time`, with a gulp.
    func spit(at time: TimeInterval) {
        spatAt = time
        riseOrSink()
    }

    /// How far it is lifted at `time`: a sprite pixel while gulping or eager.
    func lift(at time: TimeInterval) -> CGFloat {
        let gulp = { (since: TimeInterval) in (0..<Self.gulpSeconds).contains(time - since) }
        let gulping = gulp(spatAt) || trash.gulps.contains { gulp($0.at + Self.swallowSeconds) }
        return gulping || isEager ? spritePixel : 0
    }

    /// The sprite at `time`, with the tentacles swaying and the mouth open
    /// while eager or swallowing.
    func grid(at time: TimeInterval) -> PixelGrid {
        let rate = isEager ? Self.eagerSwayRate : Self.swayRate
        let frame = Int(time * rate) % 2
        let swallowing = trash.gulps.contains { time - $0.at < Self.swallowSeconds }
        return isEager || swallowing ? Self.openFrames[frame] : Self.frames[frame]
    }

    /// How visible the undo hint is at `time`, fading out over its last second.
    func hintOpacity(at time: TimeInterval) -> Double {
        showsUndoHint ? min(max(trash.undoUntil - time, 0), 1) : 0
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
