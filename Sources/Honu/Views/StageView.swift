import SwiftUI

/// Every bubble as Liquid Glass, back to front, in one `GlassEffectContainer`
/// (Liquid Glass renders untinted and gray without one). The container blends
/// glass shapes that touch, which would merge overlapping bubbles, so each
/// bubble's glass and content are cut away wherever a bubble above it lies,
/// with a small gap: the one on top covers the others completely, however
/// see-through its glass.
struct StageView: View {
    let shell: Shell
    @Namespace private var glass

    /// The gap between a bubble on top and the glass cut away below it.
    static let gap: CGFloat = 2

    var body: some View {
        let bubbles = shell.stage.bubbles
        GlassEffectContainer(spacing: 0) {
            ZStack {
                ForEach(Array(bubbles.enumerated()), id: \.element.id) { index, bubble in
                    BubbleView(
                        bubble: bubble, shell: shell, glass: glass,
                        cuts: Self.cuts(of: index, in: bubbles)
                    )
                    .frame(width: bubble.size.width, height: bubble.size.height)
                    .scaleEffect(bubble.drawnScale)
                    .opacity(bubble.isHidden ? 0 : 1)
                    .allowsHitTesting(bubble.isGrabbable)
                    .position(bubble.center)
                    .offset(bubble.motionOffset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The outlines of the bubbles drawn above the one at `index` that overlap
    /// it, in its own coordinates, before its scale.
    static func cuts(of index: Int, in bubbles: [Bubble]) -> [Cut] {
        let bubble = bubbles[index]
        let frame = bubble.drawnFrame
        let scale = max(bubble.drawnScale, 0.01)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let bounds = bubble.drawnBounds
        // From the stage's coordinates to the bubble's own, before its scale.
        func local(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: (point.x - center.x) / scale + bubble.size.width / 2,
                y: (point.y - center.y) / scale + bubble.size.height / 2)
        }
        return bubbles[(index + 1)...].compactMap { cover in
            guard !cover.isHidden else { return nil }
            // Its glass swells while it breathes.
            let grow = gap + cover.swell * cover.drawnScale
            if let outline = cover.drawnOutline(grownBy: grow) {
                guard CGRect(around: outline).intersects(bounds) else { return nil }
                return Cut(rect: .zero, cornerRadius: 0, outline: outline.map(local))
            }
            let outline = cover.drawnFrame.insetBy(dx: -grow, dy: -grow)
            guard outline.intersects(bounds) else { return nil }
            let corner = local(outline.origin)
            let rect = CGRect(
                x: corner.x, y: corner.y, width: outline.width / scale,
                height: outline.height / scale)
            return Cut(
                rect: rect, cornerRadius: (cover.cornerRadius * cover.drawnScale + grow) / scale)
        }
    }
}

/// The outline of a bubble above another, to cut away from the one below:
/// a rounded rectangle, or the curve through the points of a wobbling one.
struct Cut: Equatable {
    var rect: CGRect
    var cornerRadius: CGFloat
    var outline: [CGPoint]? = nil

    var path: Path {
        if let outline {
            return Path(smoothlyClosedThrough: outline)
        }
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
    }
}

/// A bubble's glass: `shape`, or the curve along its wobbling `outline`,
/// grown by `swell` on every side (past the view's own bounds), with the
/// outlines of the bubbles above cut away. The outline and the cuts are in
/// the coordinates of a bubble of `size`, and are fitted to the rectangle the
/// shape is drawn in, which Liquid Glass hands over already scaled while the
/// bubble is.
struct CutAway: Shape {
    let shape: RoundedRectangle
    let size: CGSize
    var outline: Outline? = nil
    var swell: CGFloat = 0
    let cuts: [Cut]

    func path(in rect: CGRect) -> Path {
        let fit = CGAffineTransform(
            a: rect.width / max(size.width, 1), b: 0, c: 0, d: rect.height / max(size.height, 1),
            tx: rect.minX, ty: rect.minY)
        var path: Path
        if let outline {
            let middle = CGPoint(x: size.width / 2, y: size.height / 2)
            path = Path(
                smoothlyClosedThrough: zip(outline.points, outline.normals).map {
                    middle + $0 + $1 * swell
                }
            ).applying(fit)
        } else {
            path = shape.inset(by: -swell).path(in: rect)
        }
        for cut in cuts {
            path = path.subtracting(cut.path.applying(fit))
        }
        return path
    }
}

extension Path {
    /// A smooth closed curve through `points` (a Catmull-Rom spline).
    init(smoothlyClosedThrough points: [CGPoint]) {
        self.init()
        let count = points.count
        guard count > 2 else { return }
        move(to: points[0])
        for i in 0..<count {
            let (before, from) = (points[(i - 1 + count) % count], points[i])
            let (to, after) = (points[(i + 1) % count], points[(i + 2) % count])
            addCurve(
                to: to, control1: from + (to - before) * (1.0 / 6),
                control2: to - (after - from) * (1.0 / 6))
        }
        closeSubpath()
    }
}
