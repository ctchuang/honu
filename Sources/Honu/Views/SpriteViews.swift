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

/// The pixel-art octopus, risen from the bottom edge while wanted, with its
/// "Click to undo" hint while a swallowed bubble can still come back.
struct OctopusView: View {
    let shell: Shell

    var body: some View {
        let octopus = shell.octopus
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            SpriteCanvas(grid: octopus.grid(at: time), color: Octopus.color)
                .contentShape(PixelMask(grid: octopus.grid(at: time)))
                .overlay(alignment: .top) {
                    if octopus.canUndo {
                        hint.opacity(octopus.hintOpacity(at: time))
                            .alignmentGuide(.top) { $0[.bottom] + 6 }
                    }
                }
                .offset(y: -octopus.lift(at: time))
        }
        .onTapGesture { shell.undoDelete() }
        .allowsHitTesting(octopus.isUp)
        .offset(x: octopus.origin.x, y: octopus.origin.y + (octopus.isUp ? 0 : octopus.hiddenDrop))
    }

    private var hint: some View {
        Text("Click to undo")
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(rgb: 40, 20, 34).opacity(0.8)))
            .fixedSize()
    }
}
