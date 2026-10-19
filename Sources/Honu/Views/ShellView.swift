import SwiftUI

/// Paints everything back to front: the bubbles, the octopus, the turtle,
/// and the turtle's menu.
struct ShellView: View {
    let shell: Shell

    /// The coordinate space everything is laid out in: the window's, from its top-left corner.
    static let space = "stage"

    var body: some View {
        ZStack(alignment: .topLeading) {
            StageView(shell: shell)
            OctopusView(shell: shell)
            TurtleView(shell: shell)
            if let point = shell.menu {
                // Pressing anywhere outside the menu closes it.
                Color.black.opacity(0.001)
                    .onTapGesture { shell.closeMenu() }
                TurtleMenu(shell: shell)
                    .offset(x: point.x, y: point.y)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coordinateSpace(.named(Self.space))
    }
}

/// Every bubble as Liquid Glass. Bubbles sharing one container blend into
/// each other when they come close.
struct StageView: View {
    let shell: Shell
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 24) {
            ZStack {
                ForEach(shell.stage.bubbles) { bubble in
                    BubbleView(bubble: bubble, shell: shell, glass: glass)
                        .frame(width: bubble.size.width, height: bubble.size.height)
                        .scaleEffect(bubble.drawnScale)
                        .opacity(bubble.isHidden ? 0 : 1)
                        .allowsHitTesting(bubble.isGrabbable)
                        .position(bubble.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

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
