import Foundation

/// What the shell keeps for the next launch, which `Autosave` writes.
extension Shell {
    /// What to keep for the next launch: places relative to the center of the
    /// screen, so they come back in place on a screen of another size.
    func snapshot() -> SavedState {
        let center = stage.center
        var state = SavedState()
        state.turtle = turtle.rest.map { $0 - center }
        state.allDesktops = isOnAllDesktops
        // A bubble still in the octopus when Honu quits counts as deleted.
        state.bubbles = stage.bubbles.filter { !$0.isSwallowed }.map {
            // Where it is going, so a bubble saved mid-flight comes back where it lands.
            SavedBubble(
                target: $0.target, offset: $0.destination - center, size: $0.userSize,
                isZoomed: $0.userSize == nil ? nil : $0.isZoomed)
        }
        for app in registry.apps {
            if let data = app.save(), let json = String(data: data, encoding: .utf8) {
                state.apps[app.id.rawValue] = json
            }
        }
        return state
    }

    /// Puts back what was saved on the last launch, without the focus, and
    /// deletes items no bubble showed, such as one still in the octopus.
    func restore(_ state: SavedState) {
        let center = stage.center
        if let offset = state.turtle {
            turtle.move(to: center + offset)
        }
        isOnAllDesktops = state.allDesktops ?? true
        for app in registry.apps {
            if let json = state.apps[app.id.rawValue] {
                app.load(Data(json.utf8))
            }
        }
        for saved in state.bubbles where registry.has(saved.target) {
            guard let app = registry.app(saved.target.app) else { continue }
            let bubble = addBubble(
                showing: saved.target.item, of: app, at: center + saved.offset, fresh: false)
            if let size = saved.size {
                stage.setUserSize(of: bubble, to: size, zoomed: saved.isZoomed ?? false)
            }
        }
        for app in registry.apps {
            for item in app.items where !stage.shows(ViewTarget(app: app.id, item: item)) {
                app.remove(item)
            }
        }
    }
}
