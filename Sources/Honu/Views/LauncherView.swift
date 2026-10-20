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
                    TileView(tile: tile) { shell.choose(tile.kind) }
                }
            }
            .padding(Self.padding)
        }
        .scrollIndicators(.never)
        .frame(width: size.width, height: size.height)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// One tile of the launcher: its symbol over its label, highlighted while
/// hovered.
private struct TileView: View {
    let tile: LauncherTile
    let action: () -> Void
    // Spelled out instead of `@State`, whose macro ships only with Xcode.
    private let hovered = State(initialValue: false)

    var body: some View {
        Button(action: action) {
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
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hovered.wrappedValue ? Color.accentColor.opacity(0.35) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tile.label)
        .onHover { hovered.wrappedValue = $0 }
    }
}
