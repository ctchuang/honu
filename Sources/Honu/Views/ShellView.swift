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
                let corner = TurtleMenu.corner(at: point, in: shell.stage.size)
                TurtleMenu(shell: shell)
                    .offset(x: corner.x, y: corner.y)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coordinateSpace(.named(Self.space))
    }
}
