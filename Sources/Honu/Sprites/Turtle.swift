import SwiftUI

/// The pixel-art sea turtle that starts in the bottom-left corner of the
/// desktop and can be dragged anywhere. Clicking it opens its menu, and it
/// spits out the bubbles made from there.
@Observable
@MainActor
final class Turtle {
    /// The sprite, one character per pixel: Outline, Shell, Light shell spot,
    /// sKin, Rim, Eye, White highlight, Pink cheek, and `.` for transparent.
    static let grid = PixelGrid([
        "......OOOOOOO...........",
        "....OOSSSSSSSOO.........",
        "...OSSWWSSSSSSSO........",
        "..OSWWSSLLLLSSSSO..OOOO.",
        "..OSWSSLLLLLLSSSO.OKKKKO",
        ".OSSSSSLLLLLLSSSSOKKEWKO",
        ".OSLLSSSLLLLSSLLSOKKEEKO",
        ".OSLLSSSSSSSSSLLSOKPKKKO",
        "ORRRRRRRRRRRRRRRRROKKOKO",
        ".ORRRRRRRRRRRRRRRROOOOO.",
        "..OOOOOOOOOOOOOOOO......",
        "...OKKKO.......OKKKKO...",
        "...OKKO.........OKKKKO..",
        "....OO...........OOOO...",
    ])
    /// Pixels (column, row) that turn into the dark inside of the open mouth.
    static let openMouth = [(22, 7), (23, 7), (22, 8), (23, 8)]
    static let openMouthGrid = grid.replacing(openMouth, with: "E")
    /// Where bubbles come out, in sprite pixels: the front of the open mouth.
    private static let mouth = CGPoint(x: 24, y: 8)
    /// Seconds the mouth stays open after spitting.
    private static let mouthSeconds: TimeInterval = 0.3
    /// Gap between the turtle and the corner of the screen.
    static let margin: CGFloat = 24
    private static let hopSeconds: TimeInterval = 0.35
    /// Height of a hop, in sprite pixels.
    private static let hopPixels: Double = 3
    /// Idle bobs per second; the turtle rises one sprite pixel on every other one.
    private static let bobRate: Double = 1.5

    /// Top-left corner of the sprite at rest, or `nil` while it is still in
    /// the bottom-left corner, where it starts.
    var rest: CGPoint?
    /// When the last hop started, on the `now()` clock.
    private var hoppedAt = -TimeInterval.infinity
    /// When the turtle last spat out a bubble.
    private var spatAt = -TimeInterval.infinity
    let stageSize: CGSize

    init(stageSize: CGSize) {
        self.stageSize = stageSize
    }

    var size: CGSize { Self.grid.size }

    /// Top-left corner of the sprite at rest, kept inside the stage.
    var origin: CGPoint {
        let corner = CGPoint(x: Self.margin, y: stageSize.height - Self.margin - size.height)
        let point = rest ?? corner
        return CGPoint(
            x: min(max(point.x, 0), stageSize.width - size.width),
            y: min(max(point.y, 0), stageSize.height - size.height))
    }

    var center: CGPoint {
        CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    }

    /// Moves the turtle to rest with its top-left corner at `point`, as when dragged.
    func move(to point: CGPoint) {
        rest = point
        rest = origin
    }

    func hop() {
        hoppedAt = now()
    }

    /// Opens the mouth for a moment and returns where a bubble should come out.
    func spit() -> CGPoint {
        spatAt = now()
        return CGPoint(
            x: origin.x + Self.mouth.x * spritePixel, y: origin.y + Self.mouth.y * spritePixel)
    }

    /// How far the turtle is lifted at `time` by a hop or an idle bob, in
    /// whole sprite pixels, as pixel art moves.
    func lift(at time: TimeInterval) -> CGFloat {
        let hop = (time - hoppedAt) / Self.hopSeconds
        let lift =
            (0..<1).contains(hop)
            ? sin(.pi * hop) * Self.hopPixels
            : Double(Int(time * Self.bobRate) % 2)
        return lift.rounded() * spritePixel
    }

    func grid(at time: TimeInterval) -> PixelGrid {
        time - spatAt < Self.mouthSeconds ? Self.openMouthGrid : Self.grid
    }

    /// Whether `point` is on one of the turtle's visible pixels.
    func contains(_ point: CGPoint) -> Bool {
        guard let (x, y) = Self.grid.pixel(at: point, origin: origin) else { return false }
        return Self.grid.pixel(x, y) != "."
    }

    static func color(_ c: Character) -> Color? {
        switch c {
        case "O": Color(rgb: 47, 111, 70)
        case "S": Color(rgb: 95, 184, 120)
        case "L": Color(rgb: 127, 207, 147)
        case "K": Color(rgb: 143, 214, 160)
        case "R": Color(rgb: 244, 223, 160)
        case "E": Color(rgb: 31, 59, 44)
        case "W": .white
        case "P": Color(rgb: 255, 159, 178)
        default: nil
        }
    }
}
