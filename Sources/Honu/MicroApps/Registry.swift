import Foundation

/// The microapps, in the order the turtle's menu lists them.
@MainActor
final class Registry {
    let apps: [any MicroApp]

    init(_ apps: [any MicroApp]) {
        self.apps = apps
    }

    func app(_ id: AppID) -> (any MicroApp)? {
        apps.first { $0.id == id }
    }

    func title(of target: ViewTarget) -> String {
        app(target.app)?.title(of: target.item) ?? ""
    }

    /// Whether the microapp of `target` keeps its item.
    func has(_ target: ViewTarget) -> Bool {
        app(target.app)?.items.contains(target.item) ?? false
    }

    func remove(_ target: ViewTarget) {
        app(target.app)?.remove(target.item)
    }

    func isBusy(_ target: ViewTarget) -> Bool {
        app(target.app)?.isBusy(target.item) ?? false
    }

    /// Lets every microapp catch up, returning what they ask of their bubbles.
    func update() -> [Effect] {
        apps.flatMap { app in
            let context = Context(app: app.id)
            app.update(context)
            return context.effects
        }
    }
}
