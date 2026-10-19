import SwiftUI

// The pixel-art sprites on the desktop: the turtle that spits out bubbles
// and the octopus that deletes them. Both are drawn from character grids,
// one character per pixel.

/// Size of one sprite pixel, in points.
let spritePixel: CGFloat = 5

/// A pixel-art picture: rows of characters, one per pixel, with `.` for transparent.
struct PixelGrid {
    let rows: [[Character]]

    init(_ rows: [String]) {
        self.rows = rows.map(Array.init)
    }

    var columns: Int { rows.first?.count ?? 0 }

    /// Size of the whole sprite, in points.
    var size: CGSize {
        CGSize(width: CGFloat(columns) * spritePixel, height: CGFloat(rows.count) * spritePixel)
    }

    func pixel(_ x: Int, _ y: Int) -> Character {
        guard rows.indices.contains(y), rows[y].indices.contains(x) else { return "." }
        return rows[y][x]
    }

    /// The pixel (column, row) under `point`, for a sprite whose top-left
    /// corner is at `origin`.
    func pixel(at point: CGPoint, origin: CGPoint) -> (x: Int, y: Int)? {
        let x = (point.x - origin.x) / spritePixel
        let y = (point.y - origin.y) / spritePixel
        guard x >= 0, y >= 0, x < CGFloat(columns), y < CGFloat(rows.count) else { return nil }
        return (Int(x), Int(y))
    }

    /// Whether `point` is on a visible pixel, for a sprite whose top-left
    /// corner is at `origin`.
    func isOpaque(at point: CGPoint, origin: CGPoint) -> Bool {
        guard let (x, y) = pixel(at: point, origin: origin) else { return false }
        return pixel(x, y) != "."
    }

    /// Where `pixel`, in sprite pixels from the top-left corner, lies on
    /// screen for a sprite whose top-left corner is at `origin`.
    static func point(_ pixel: CGPoint, origin: CGPoint) -> CGPoint {
        origin + pixel * spritePixel
    }

    /// The grid with some pixels replaced.
    func replacing(_ pixels: [(Int, Int)], with c: Character) -> PixelGrid {
        var grid = self
        var rows = grid.rows
        for (x, y) in pixels { rows[y][x] = c }
        grid = PixelGrid(rows: rows)
        return grid
    }

    private init(rows: [[Character]]) {
        self.rows = rows
    }
}

/// Paints a pixel grid as crisp, unblended squares.
struct SpriteCanvas: View {
    let grid: PixelGrid
    let color: (Character) -> Color?

    var body: some View {
        Canvas { context, _ in
            for (y, row) in grid.rows.enumerated() {
                for (x, c) in row.enumerated() {
                    guard let color = color(c) else { continue }
                    let rect = CGRect(
                        x: CGFloat(x) * spritePixel, y: CGFloat(y) * spritePixel,
                        width: spritePixel, height: spritePixel)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: grid.size.width, height: grid.size.height)
    }
}

/// The visible pixels of a grid, so hit-testing skips transparent ones.
struct PixelMask: Shape {
    let grid: PixelGrid

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (y, row) in grid.rows.enumerated() {
            for (x, c) in row.enumerated() where c != "." {
                path.addRect(
                    CGRect(
                        x: rect.minX + CGFloat(x) * spritePixel,
                        y: rect.minY + CGFloat(y) * spritePixel,
                        width: spritePixel, height: spritePixel))
            }
        }
        return path
    }
}
