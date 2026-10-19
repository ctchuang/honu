import Foundation

/// Everything kept for the next launch.
private struct SavedState: Codable {
    /// Where the turtle rests relative to the center of the screen, if it was dragged.
    var turtle: CGPoint?
    var bubbles: [SavedBubble] = []
    /// Each microapp's items, as the JSON it saved, by microapp id.
    var apps: [String: String] = [:]
}

private struct SavedBubble: Codable {
    var target: ViewTarget
    /// Where it was relative to the center of the screen, so it comes back in
    /// place on a screen of another size.
    var offset: CGPoint
    var isOpen: Bool
}

/// Keeps the turtle's place, the bubbles, and the microapps' items for the
/// next launch, in `~/Library/Application Support/Honu/state.json` (delete it
/// to reset). Each microapp saves its own items, so Honu never needs to know
/// their shape.
@MainActor
final class Autosave {
    static let defaultURL = URL.applicationSupportDirectory
        .appending(path: "Honu", directoryHint: .isDirectory)
        .appending(path: "state.json")
    /// How often to check for changes, in seconds.
    private static let interval: TimeInterval = 1

    /// Where it saves.
    private let url: URL
    private var lastSaved: Data?
    private var lastCheck = -TimeInterval.infinity

    init(url: URL) {
        self.url = url
    }

    /// Saves if a second has passed since the last check and anything changed.
    func tick(_ shell: Shell) {
        guard now() - lastCheck >= Self.interval else { return }
        save(shell)
    }

    /// Saves if anything changed since the last save.
    func save(_ shell: Shell) {
        lastCheck = now()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(state(of: shell)), data != lastSaved else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            lastSaved = data
        } catch {
            // Try again at the next check.
        }
    }

    private func state(of shell: Shell) -> SavedState {
        let center = Self.center(of: shell.stage.size)
        var state = SavedState()
        state.turtle = shell.turtle.rest.map {
            CGPoint(x: $0.x - center.x, y: $0.y - center.y)
        }
        // A bubble still in the octopus when Honu quits counts as deleted.
        state.bubbles = shell.stage.bubbles.filter { !$0.isSwallowed }.map {
            SavedBubble(
                target: $0.target,
                // Where it is going, so a bubble saved mid-flight comes back where it lands.
                offset: CGPoint(
                    x: $0.destination.x - center.x, y: $0.destination.y - center.y),
                isOpen: $0.isOpen)
        }
        for app in shell.registry.apps {
            if let data = app.save(), let json = String(data: data, encoding: .utf8) {
                state.apps[app.id.rawValue] = json
            }
        }
        return state
    }

    /// Puts back what was saved on the last launch, and deletes items no
    /// bubble showed, such as one still in the octopus.
    func restore(into shell: Shell) {
        guard let data = try? Data(contentsOf: url),
            let state = try? JSONDecoder().decode(SavedState.self, from: data)
        else { return }
        lastSaved = data
        let center = Self.center(of: shell.stage.size)
        if let offset = state.turtle {
            shell.turtle.move(to: CGPoint(x: center.x + offset.x, y: center.y + offset.y))
        }
        for app in shell.registry.apps {
            if let json = state.apps[app.id.rawValue] {
                app.load(Data(json.utf8))
            }
        }
        for saved in state.bubbles where shell.registry.has(saved.target) {
            guard let app = shell.registry.app(saved.target.app) else { continue }
            let item = saved.target.item
            let bubble = shell.stage.add(
                target: saved.target,
                center: CGPoint(x: center.x + saved.offset.x, y: center.y + saved.offset.y),
                appearance: app.appearance(of: item),
                viewState: app.newViewState(for: item, fresh: false))
            bubble.isOpen = saved.isOpen
        }
        for app in shell.registry.apps {
            for item in app.items where !shell.stage.shows(ViewTarget(app: app.id, item: item)) {
                app.remove(item)
            }
        }
    }

    private static func center(of size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }
}
