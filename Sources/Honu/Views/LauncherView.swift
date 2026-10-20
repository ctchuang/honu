import SwiftUI

/// The turtle's launcher, opened where the turtle was clicked: a tile for
/// each thing it can start, which starts a new one there.
struct LauncherView: View {
    let shell: Shell

    static let tileSize: CGFloat = 76
    static let spacing: CGFloat = 4
    static let padding: CGFloat = 8
    static let columns = 4
    /// The most rows shown; more scroll.
    static let maxRows = 3

    /// How big the launcher is with `count` tiles.
    static func size(for count: Int) -> CGSize {
        let columns = max(1, min(count, Self.columns))
        let rows = max(1, min((count + Self.columns - 1) / Self.columns, maxRows))
        return CGSize(
            width: CGFloat(columns) * tileSize + CGFloat(columns - 1) * spacing + 2 * padding,
            height: CGFloat(rows) * tileSize + CGFloat(rows - 1) * spacing + 2 * padding)
    }

    var body: some View {
        let tiles = shell.launcherTiles
        let size = Self.size(for: tiles.count)
        ScrollView {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(Self.tileSize), spacing: Self.spacing),
                    count: max(1, min(tiles.count, Self.columns))),
                spacing: Self.spacing
            ) {
                ForEach(tiles) { tile in
                    TileView(shell: shell, tile: tile)
                }
            }
            .padding(Self.padding)
        }
        .scrollIndicators(.never)
        .frame(width: size.width, height: size.height)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// One tile of the launcher, highlighted while hovered. Clicking it starts
/// what it starts. An installed microapp's tile can be dragged to the
/// octopus, to uninstall it; the others wobble, to show they stay.
private struct TileView: View {
    let shell: Shell
    let tile: LauncherTile
    // Spelled out instead of `@State`, whose macro ships only with Xcode.
    private let hovered = State(initialValue: false)
    /// Counts the wobbles, each played once.
    private let wobbles = State(initialValue: 0)
    /// Whether the current drag has already been refused with a wobble.
    private let refused = State(initialValue: false)

    init(shell: Shell, tile: LauncherTile) {
        self.shell = shell
        self.tile = tile
    }

    var body: some View {
        let dragged = shell.tileDrag?.tile == tile
        TileFace(tile: tile)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hovered.wrappedValue ? Color.accentColor.opacity(0.35) : .clear)
            )
            .opacity(dragged ? 0.3 : 1)
            .contentShape(Rectangle())
            .keyframeAnimator(initialValue: 0.0, trigger: wobbles.wrappedValue) { face, angle in
                face.rotationEffect(.degrees(angle))
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-8, duration: 0.07)
                    CubicKeyframe(7, duration: 0.1)
                    CubicKeyframe(-4, duration: 0.09)
                    CubicKeyframe(0, duration: 0.08)
                }
            }
            .gesture(drag.exclusively(before: TapGesture().onEnded { shell.choose(tile.kind) }))
            .help(tile.label)
            .onHover { hovered.wrappedValue = $0 }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(ShellView.space))
            .onChanged { value in
                let moves = shell.dragTile(tile, from: value.startLocation, to: value.location)
                if !moves && !refused.wrappedValue {
                    refused.wrappedValue = true
                    wobbles.wrappedValue += 1
                }
            }
            .onEnded { value in
                refused.wrappedValue = false
                shell.endTileDrag(at: value.location)
            }
    }
}

/// What a launcher tile shows: its symbol over its label.
struct TileFace: View {
    let tile: LauncherTile

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: tile.symbol)
                .font(.system(size: 24))
                .frame(height: 28)
            Text(tile.label)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(4)
        .frame(width: LauncherView.tileSize, height: LauncherView.tileSize)
    }
}
