import SwiftUI

/// Paints everything back to front: the bubbles, the octopus, the turtle,
/// and the turtle's launcher or menu.
struct ShellView: View {
    let shell: Shell

    /// The coordinate space everything is laid out in: the window's, from its top-left corner.
    static let space = "stage"

    var body: some View {
        ZStack(alignment: .topLeading) {
            StageView(shell: shell)
            OctopusView(shell: shell)
            TurtleView(shell: shell)
            if let popup = shell.popup {
                // Pressing anywhere outside the menu closes it.
                Color.black.opacity(0.001)
                    .onTapGesture { shell.closePopup() }
                switch popup {
                case .launcher(let point):
                    let size = LauncherView.size(for: shell.launcherTiles.count)
                    let corner = menuCorner(of: size, at: point, in: shell.stage.size)
                    LauncherView(shell: shell)
                        .offset(x: corner.x, y: corner.y)
                case .system(let point):
                    let size = CGSize(width: SystemMenu.width, height: SystemMenu.estimatedHeight)
                    let corner = menuCorner(of: size, at: point, in: shell.stage.size)
                    SystemMenu()
                        .offset(x: corner.x, y: corner.y)
                }
            }
            if let (tile, pointer) = shell.tileDrag {
                // The dragged tile follows the pointer, above everything.
                TileFace(tile: tile)
                    .glassEffect(
                        .regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .scaleEffect(shell.octopus.isEager ? 0.7 : 1)
                    .animation(.spring(duration: 0.25), value: shell.octopus.isEager)
                    .position(pointer)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coordinateSpace(.named(Self.space))
    }
}
