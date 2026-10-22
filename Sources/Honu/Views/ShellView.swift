import SwiftUI

/// Paints everything back to front: the bubbles, the octopus, the turtle,
/// and the turtle's launcher or menu.
struct ShellView: View {
    let shell: Shell

    /// The coordinate space everything is laid out in: the window's, from its top-left corner.
    nonisolated static let space = "stage"

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
                case .launcher:
                    let corner = shell.launcherFrame?.origin ?? .zero
                    LauncherView(shell: shell)
                        .offset(x: corner.x, y: corner.y)
                case .system(let point):
                    let size = CGSize(width: SystemMenu.width, height: SystemMenu.estimatedHeight)
                    let corner = menuCorner(of: size, at: point, in: shell.stage.size)
                    SystemMenu(shell: shell)
                        .offset(x: corner.x, y: corner.y)
                }
            }
            if let (tile, pointer) = shell.tileDrag {
                // The dragged tile follows the pointer, above everything.
                LooseTile(tile: tile)
                    .scaleEffect(shell.octopus.isEager ? Shell.eagerTileScale : 1)
                    .animation(.spring(duration: 0.25), value: shell.octopus.isEager)
                    .position(pointer)
            }
            if let (tile, flight, start) = shell.swallowedTile {
                // A tile dropped on the octopus goes down its mouth, as a
                // bubble does.
                TimelineView(.animation) { context in
                    let flight = flight.after(context.date.timeIntervalSinceReferenceDate - start)
                    LooseTile(tile: tile)
                        .scaleEffect(flight.scale)
                        .position(flight.position)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coordinateSpace(.named(Self.space))
    }
}

/// A launcher tile out of the launcher, on glass of its own, which takes no
/// clicks.
private struct LooseTile: View {
    let tile: LauncherTile

    var body: some View {
        TileFace(tile: tile)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .allowsHitTesting(false)
    }
}
