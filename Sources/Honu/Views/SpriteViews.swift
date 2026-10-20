import SwiftUI

/// The pixel-art turtle: it bobs while idle, hops when clicked, and opens its
/// mouth to spit out a bubble.
struct TurtleView: View {
    let shell: Shell

    var body: some View {
        let turtle = shell.turtle
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            SpriteCanvas(grid: turtle.grid(at: time), color: Turtle.color)
                .offset(y: -turtle.lift(at: time))
        }
        .contentShape(PixelMask(grid: Turtle.grid))
        .gesture(drag.exclusively(before: click))
        .offset(x: turtle.origin.x, y: turtle.origin.y)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(ShellView.space))
            .onChanged { shell.dragTurtle(by: $0.translation) }
            .onEnded { _ in shell.endTurtleDrag() }
    }

    private var click: some Gesture {
        SpatialTapGesture(coordinateSpace: .named(ShellView.space))
            .onEnded { shell.clickTurtle(at: $0.location) }
    }
}

/// The pixel-art octopus, risen from the bottom edge while wanted, with a
/// speech bubble offering to recycle the dragged bubble, and its "Click to
/// undo" hint while a swallowed bubble can still come back.
struct OctopusView: View {
    let shell: Shell

    var body: some View {
        let octopus = shell.octopus
        // Out of sight it has nothing to animate, so it stops redrawing. What
        // shows above it stays out of this timeline, since a paused one keeps
        // its last frame, which would leave it hanging over the sunk octopus.
        TimelineView(.animation(minimumInterval: nil, paused: !octopus.isUp)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            SpriteCanvas(grid: octopus.grid(at: time), color: Octopus.color)
                .contentShape(PixelMask(grid: octopus.grid(at: time)))
                .offset(y: -octopus.lift(at: time))
        }
        .overlay(alignment: octopus.isRight ? .topTrailing : .topLeading) {
            if octopus.offersHelp {
                offer(eager: octopus.isEager, right: octopus.isRight)
                    .above(gap: Octopus.hintGap)
            }
        }
        .overlay(alignment: .top) {
            if octopus.showsUndoHint {
                TimelineView(.animation) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    hint.opacity(octopus.hintOpacity(at: time))
                        .offset(y: -octopus.lift(at: time))
                }
                .above(gap: Octopus.hintGap)
            }
        }
        .onTapGesture { shell.undoDelete() }
        .allowsHitTesting(octopus.isUp)
        .offset(x: octopus.origin.x, y: octopus.origin.y + (octopus.isUp ? 0 : octopus.hiddenDrop))
    }

    /// A comic speech bubble whose tail points down at the octopus's middle,
    /// lined up with its side nearer the screen edge so it stays on screen.
    private func offer(eager: Bool, right: Bool) -> some View {
        let tail = shell.octopus.size.width / 2
        return Text(eager ? "Let go, I'll recycle it!" : "Drop it on me to recycle!")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(rgb: 48, 22, 40))
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .padding(.bottom, SpeechBubble.tailHeight)
            .background {
                let shape = SpeechBubble(tail: tail, fromRight: right)
                shape.fill(.white)
                shape.stroke(Octopus.color("O") ?? .black, lineWidth: 2)
            }
            .allowsHitTesting(false)
            .transition(
                .scale(scale: 0.2, anchor: right ? .bottomTrailing : .bottomLeading)
                    .combined(with: .opacity))
    }

    private var hint: some View {
        Text("Click to undo")
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .fixedSize()
            // As big as the octopus takes clicks on it.
            .frame(width: Octopus.hintSize.width, height: Octopus.hintSize.height)
            .background(Capsule().fill(Color(rgb: 40, 20, 34).opacity(0.8)))
    }
}

/// A rounded speech bubble with a tail at the bottom, `tail` points in from
/// its left side (or its right, `fromRight`), its tip leaning toward that side.
struct SpeechBubble: Shape {
    static let tailHeight: CGFloat = 10
    private static let tailWidth: CGFloat = 12
    private static let radius: CGFloat = 10

    let tail: CGFloat
    let fromRight: Bool

    func path(in rect: CGRect) -> Path {
        let (r, half) = (Self.radius, Self.tailWidth / 2)
        let bottom = rect.maxY - Self.tailHeight
        let x = fromRight ? rect.maxX - tail : rect.minX + tail
        let lean: CGFloat = fromRight ? half : -half
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: bottom), radius: r)
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: bottom),
            tangent2End: CGPoint(x: rect.minX, y: bottom), radius: r)
        path.addLine(to: CGPoint(x: x + half, y: bottom))
        path.addLine(to: CGPoint(x: x + lean, y: rect.maxY))
        path.addLine(to: CGPoint(x: x - half, y: bottom))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: bottom),
            tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: r)
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: r)
        path.closeSubpath()
        return path
    }
}

extension View {
    /// Sets this view `gap` above the top of the view it overlays (with a
    /// top alignment), growing upward from there.
    fileprivate func above(gap: CGFloat) -> some View {
        frame(height: 0, alignment: .bottom).offset(y: -gap)
    }
}
