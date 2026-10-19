import Foundation

/// Everything kept for the next launch. The shell makes it (`Shell.snapshot`)
/// and puts it back (`Shell.restore`); `Autosave` only decides when to write it.
struct SavedState: Codable {
    /// Where the turtle rests relative to the center of the screen, if it was dragged.
    var turtle: CGPoint?
    var bubbles: [SavedBubble] = []
    /// Each microapp's items, as the JSON it saved, by microapp id.
    var apps: [String: String] = [:]

    /// The same without where the bubbles are, to tell real changes from drifting.
    var unplaced: SavedState {
        var state = self
        state.bubbles = bubbles.map {
            var bubble = $0
            bubble.offset = .zero
            return bubble
        }
        return state
    }
}

struct SavedBubble: Codable {
    var target: ViewTarget
    /// Where it was relative to the center of the screen, so it comes back in
    /// place on a screen of another size.
    var offset: CGPoint
    var isOpen: Bool
}

/// Writes the shell's `SavedState` for the next launch, in
/// `~/.honu/state.json` (delete it to reset), and
/// reads it back. It decides when and where to write, and leaves what to the
/// shell. Each microapp saves its own items, so Honu never needs to know their
/// shape.
@MainActor
final class Autosave {
    /// Where Honu saves: `HONU_STORE` if set, so a development run can keep
    /// its own bubbles, otherwise Honu's own folder.
    static var storeURL: URL {
        ProcessInfo.processInfo.environment["HONU_STORE"].map { URL(filePath: $0) } ?? defaultURL
    }

    static let defaultURL = Services.folder.appending(path: "state.json")
    /// How often to check for changes, in seconds.
    private static let interval: TimeInterval = 1

    /// Where it saves.
    private let url: URL
    /// What was last saved, apart from where the bubbles are.
    private var lastSaved: Data?
    private var lastCheck = -TimeInterval.infinity
    /// Whether a bubble was moved on purpose since the last save. Bubbles
    /// drifting idly are not a change worth writing, but a dragged one is.
    private var isMoved = false

    init(url: URL) {
        self.url = url
    }

    /// Notes that a bubble was dragged somewhere, so its place is saved.
    func moved() {
        isMoved = true
    }

    /// Saves the state `snapshot` makes if a second has passed since the last
    /// check and anything changed. `snapshot` runs only when a check is due.
    func tick(_ snapshot: () -> SavedState) {
        guard now() - lastCheck >= Self.interval else { return }
        save(snapshot())
    }

    /// Saves `state` if anything changed since the last save.
    func save(_ state: SavedState) {
        lastCheck = now()
        let state = Self.canonical(state)
        guard let data = try? Self.encode(state),
            let unplaced = try? Self.encode(state.unplaced),
            unplaced != lastSaved || isMoved
        else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            lastSaved = unplaced
            isMoved = false
        } catch {
            // Try again at the next check.
        }
    }

    /// What was saved on the last launch, if anything was, which counts as
    /// saved already.
    func restore() -> SavedState? {
        guard let data = try? Data(contentsOf: url),
            let state = try? JSONDecoder().decode(SavedState.self, from: data)
        else { return nil }
        lastSaved = try? Self.encode(Self.canonical(state).unplaced)
        return state
    }

    private static func encode(_ state: SavedState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(state)
    }

    /// `state` with each microapp's JSON in canonical form.
    private static func canonical(_ state: SavedState) -> SavedState {
        var state = state
        state.apps = state.apps.compactMapValues { json in
            canonical(Data(json.utf8)).flatMap { String(data: $0, encoding: .utf8) }
        }
        return state
    }

    /// `json` with its object keys sorted. `JSONEncoder` may order keys
    /// differently from one call to the next, which would look like a change.
    static func canonical(_ json: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: json, options: .fragmentsAllowed)
        else { return json }
        return try? JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
    }
}
