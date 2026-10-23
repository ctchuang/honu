import SwiftUI

/// What the views ask of the shell, so they never reach into the microapps.
extension Shell {
    /// The tiles the launcher shows: those of the folder open, if any, or
    /// else those of its top level.
    var launcherTiles: [LauncherTile] {
        launcherTiles(in: openFolder)
    }

    /// The tiles in `folder`, or at the launcher's top level if none: there,
    /// the Reef (if it holds anything), then a tile for each installed
    /// microapp, in the order they were made, then **+** for making a new
    /// microapp.
    func launcherTiles(in folder: LauncherFolder?) -> [LauncherTile] {
        if let folder {
            return switch folder {
            case .builtIn: builtInTiles
            }
        }
        let reef = LauncherFolder.builtIn
        let builtIn = builtInTiles
        let folders =
            builtIn.isEmpty
            ? []
            : [
                LauncherTile(
                    kind: .folder(reef), label: reef.label, symbol: reef.symbol,
                    preview: builtIn.prefix(LauncherView.previewCount).map(\.symbol))
            ]
        let installed = maker.library.map {
            LauncherTile(
                kind: .installed($0.folder.name), label: MakerApp.name(of: $0),
                symbol: MakerApp.symbol(of: $0))
        }
        return folders + installed
            + [
                LauncherTile(
                    kind: .make, label: maker.launcherLabel, symbol: maker.launcherSymbol)
            ]
    }

    /// A tile for each built-in microapp the launcher lists, in the Reef.
    private var builtInTiles: [LauncherTile] {
        registry.apps.filter { $0.isLaunchable && $0.id != maker.id }.map {
            LauncherTile(kind: .stock($0.id), label: $0.launcherLabel, symbol: $0.launcherSymbol)
        }
    }

    /// Where the launcher is, while it is open: at the point the turtle was
    /// clicked, moved as far as it takes to keep it on screen, and sized for
    /// the tiles it shows (and, in a folder, the folder's header).
    var launcherFrame: CGRect? {
        guard case .launcher(let point, let folder) = popup else { return nil }
        let size = LauncherView.size(for: launcherTiles.count, header: folder != nil)
        return CGRect(origin: menuCorner(of: size, at: point, in: stage.size), size: size)
    }

    /// How `bubble` looks, as its microapp says.
    func appearance(of bubble: Bubble) -> Appearance {
        registry.appearance(of: bubble.target) ?? Appearance()
    }

    func title(of bubble: Bubble) -> String {
        registry.title(of: bubble.target)
    }

    /// What `bubble` shows, made by its microapp.
    func content(of bubble: Bubble) -> AnyView? {
        registry.app(bubble.target.app)?.anyContent(
            of: bubble.target.item, viewState: bubble.viewState)
    }
}
