import SwiftUI

/// The turtle's launcher, opened where the turtle was clicked: a tile for
/// each thing it can start, which starts a new one there, and for each
/// folder, which shows its own tiles in their place, under a header that
/// goes back.
struct LauncherView: View {
    let shell: Shell

    static let tileSize: CGFloat = 76
    static let spacing: CGFloat = 4
    static let padding: CGFloat = 8
    static let columns = 4
    /// The most rows shown; more scroll.
    static let maxRows = 3
    /// How tall a folder's header is, above its tiles.
    static let headerHeight: CGFloat = 30
    /// How many of a folder's symbols its tile shows.
    static let previewCount = 4

    /// How big the launcher is with `count` tiles, and with a folder's
    /// header above them if `header`.
    static func size(for count: Int, header: Bool = false) -> CGSize {
        let columns = max(1, min(count, Self.columns))
        let rows = max(1, min((count + Self.columns - 1) / Self.columns, maxRows))
        return CGSize(
            width: CGFloat(columns) * tileSize + CGFloat(columns - 1) * spacing + 2 * padding,
            height: CGFloat(rows) * tileSize + CGFloat(rows - 1) * spacing + 2 * padding
                + (header ? headerHeight : 0))
    }

    var body: some View {
        let tiles = shell.launcherTiles
        let folder = shell.openFolder
        let size = Self.size(for: tiles.count, header: folder != nil)
        VStack(spacing: 0) {
            if let folder {
                FolderHeader(shell: shell, folder: folder)
            }
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
        }
        .frame(width: size.width, height: size.height)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// The header above a folder's tiles: a button back to the launcher's top
/// level, and the folder's name.
private struct FolderHeader: View {
    let shell: Shell
    let folder: LauncherFolder

    var body: some View {
        HStack(spacing: 4) {
            Button {
                shell.closeFolder()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(cornerRadius: 6)
            .help("Back")
            Text(folder.label)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LauncherView.padding)
        .padding(.top, LauncherView.padding)
        .frame(height: LauncherView.headerHeight, alignment: .bottom)
    }
}

/// One tile of the launcher, highlighted while hovered. Clicking it starts
/// what it starts. An installed microapp's tile can be dragged to the
/// octopus, to uninstall it; the others wobble, to show they stay. It also
/// has a menu, on a right click, for uninstalling its microapp.
private struct TileView: View {
    let shell: Shell
    let tile: LauncherTile
    // Spelled out instead of `@State`, whose macro ships only with Xcode.
    /// Counts the wobbles, each played once.
    private let wobbles = State(initialValue: 0)
    /// Whether the current drag has already been refused with a wobble.
    private let refused = State(initialValue: false)
    /// Where the tile's center is, in the stage's coordinates.
    private let center = State(initialValue: CGPoint.zero)

    init(shell: Shell, tile: LauncherTile) {
        self.shell = shell
        self.tile = tile
    }

    var body: some View {
        let dragged = shell.tileDrag?.tile == tile
        TileFace(tile: tile)
            .hoverHighlight(cornerRadius: 12)
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
            .contextMenu { menu }
            .onGeometryChange(for: CGPoint.self) { proxy in
                let frame = proxy.frame(in: .named(ShellView.space))
                return CGPoint(x: frame.midX, y: frame.midY)
            } action: {
                center.wrappedValue = $0
            }
    }

    /// The tile's menu: none but for an installed microapp's.
    @ViewBuilder private var menu: some View {
        if case .installed = tile.kind {
            Button("Uninstall") { shell.uninstall(tile, from: center.wrappedValue) }
        }
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

/// What a launcher tile shows: its symbol (or, for a folder, the symbols
/// of what it holds) over its label.
struct TileFace: View {
    let tile: LauncherTile

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if tile.preview.isEmpty {
                    Image(systemName: tile.symbol)
                        .font(.system(size: 24))
                } else {
                    FolderPreview(symbols: tile.preview)
                }
            }
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

/// A folder tile's picture: the first few symbols of what it holds, two to
/// a row, on a rounded square.
private struct FolderPreview: View {
    let symbols: [String]

    private static let cell: CGFloat = 11

    var body: some View {
        let cells = (0..<LauncherView.previewCount).map { $0 < symbols.count ? symbols[$0] : nil }
        VStack(spacing: 2) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<2, id: \.self) { column in
                        if let symbol = cells[row * 2 + column] {
                            Image(systemName: symbol)
                                .font(.system(size: 9))
                                .frame(width: Self.cell, height: Self.cell)
                        } else {
                            Color.clear.frame(width: Self.cell, height: Self.cell)
                        }
                    }
                }
            }
        }
        .padding(2)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
