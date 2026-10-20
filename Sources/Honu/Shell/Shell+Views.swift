import SwiftUI

/// What the views ask of the shell, so they never reach into the microapps.
extension Shell {
    /// The turtle's launcher tiles: a tile for each built-in microapp it
    /// lists, then **+** for making a new microapp.
    var launcherTiles: [LauncherTile] {
        let stock = registry.apps.filter { $0.isLaunchable && $0.id != maker.id }.map {
            LauncherTile(kind: .stock($0.id), label: $0.launcherLabel, symbol: $0.launcherSymbol)
        }
        return stock
            + [
                LauncherTile(
                    kind: .make, label: maker.launcherLabel, symbol: maker.launcherSymbol)
            ]
    }

    /// How `bubble` looks, as its microapp says.
    func appearance(of bubble: Bubble) -> Appearance {
        registry.appearance(of: bubble.target) ?? Appearance()
    }

    func title(of bubble: Bubble) -> String {
        registry.title(of: bubble.target)
    }

    /// What an open `bubble` shows, made by its microapp.
    func content(of bubble: Bubble) -> AnyView? {
        registry.app(bubble.target.app)?.anyContent(
            of: bubble.target.item, viewState: bubble.viewState)
    }

    /// Opens a closed bubble into its panel, or closes an open one.
    func toggle(_ bubble: Bubble) {
        stage.toggle(bubble)
    }
}
