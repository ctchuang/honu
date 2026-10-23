import SwiftUI

/// What the views ask of the shell, so they never reach into the microapps.
extension Shell {
    /// The turtle's launcher tiles: a tile for each built-in microapp it
    /// lists, then one for each installed microapp, in the order they were
    /// made, then **+** for making a new microapp.
    var launcherTiles: [LauncherTile] {
        let stock = registry.apps.filter { $0.isLaunchable && $0.id != maker.id }.map {
            LauncherTile(kind: .stock($0.id), label: $0.launcherLabel, symbol: $0.launcherSymbol)
        }
        let installed = maker.library.map {
            LauncherTile(
                kind: .installed($0.folder.name), label: MakerApp.name(of: $0),
                symbol: MakerApp.symbol(of: $0))
        }
        return stock + installed
            + [
                LauncherTile(
                    kind: .make, label: maker.launcherLabel, symbol: maker.launcherSymbol)
            ]
    }

    /// Where the launcher is, while it is open: at the point the turtle was
    /// clicked, moved as far as it takes to keep it on screen.
    var launcherFrame: CGRect? {
        guard case .launcher(let point) = popup else { return nil }
        let size = LauncherView.size(for: launcherTiles.count)
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
