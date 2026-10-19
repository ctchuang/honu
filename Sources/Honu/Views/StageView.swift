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
        return bubbles[(index + 1)...].compactMap { cover in
            guard !cover.isHidden else { return nil }
            // Its glass swells while it breathes.
            let grow = gap + cover.swell * cover.drawnScale
            let outline = cover.drawnFrame.insetBy(dx: -grow, dy: -grow)
            guard outline.intersects(frame) else { return nil }
            let rect = CGRect(
                x: (outline.minX - center.x) / scale + bubble.size.width / 2,
                y: (outline.minY - center.y) / scale + bubble.size.height / 2,
                width: outline.width / scale, height: outline.height / scale)
            return Cut(
                rect: rect, cornerRadius: (cover.cornerRadius * cover.drawnScale + grow) / scale)
        }
    }
}

/// The outline of a bubble above another, to cut away from the one below.
struct Cut: Equatable {
    var rect: CGRect
    var cornerRadius: CGFloat
}

/// `shape`, grown by `swell` on every side (past the view's own bounds),
/// with the outlines of the bubbles above cut away.
struct CutAway: Shape {
    let shape: RoundedRectangle
    var swell: CGFloat = 0
    let cuts: [Cut]

    func path(in rect: CGRect) -> Path {
        var path = shape.inset(by: -swell).path(in: rect)
        for cut in cuts {
            let outline = RoundedRectangle(cornerRadius: cut.cornerRadius, style: .continuous)
            path = path.subtracting(outline.path(in: cut.rect))
        }
        return path
    }
}
