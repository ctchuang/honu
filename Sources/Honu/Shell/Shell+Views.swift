import SwiftUI

/// What the views ask of the shell, so they never reach into the microapps.
extension Shell {
    /// One item of the turtle's menu, which starts a new item in a microapp.
    struct MenuChoice: Identifiable {
        let id: AppID
        let label: String
    }

    /// The turtle's menu items, one per microapp.
    var menuChoices: [MenuChoice] {
        registry.apps.map { MenuChoice(id: $0.id, label: $0.menuLabel) }
    }

    /// How `bubble` looks, as its microapp says.
    func appearance(of bubble: Bubble) -> Appearance {
        registry.app(bubble.target.app)?.appearance(of: bubble.target.item) ?? Appearance()
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
