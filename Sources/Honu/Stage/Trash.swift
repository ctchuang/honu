import Foundation

/// What was deleted recently enough to be brought back: the bubbles the
/// octopus swallowed, and the microapps uninstalled with them, gulp by gulp.
/// For a few seconds after each gulp, the latest can be spat back; after
/// that, everything in it is forgotten, deleted for good. The octopus only
/// shows what it holds.
@Observable
@MainActor
final class Trash {
    /// What was swallowed in one gulp: bubbles, each with where it was, to
    /// return it there, and the microapp uninstalled with them, if any. The
    /// bubbles themselves stay on the stage, out of sight.
    struct Swallowed {
        struct Morsel: Equatable {
            let bubble: BubbleID
            let home: CGPoint
        }

        let morsels: [Morsel]
        /// The folder name of the microapp uninstalled.
        let microapp: String?
        let at: TimeInterval

        var bubbles: [BubbleID] { morsels.map(\.bubble) }
    }

    /// Seconds a swallowed bubble can still be brought back.
    static let undoSeconds: TimeInterval = 5
    /// Seconds a bubble takes to go down, before the undo time starts.
    static let swallowSeconds = Bubble.swallowSeconds

    /// What can still be brought back, the latest last.
    private(set) var gulps: [Swallowed] = []
    /// Until when what was swallowed can be brought back.
    private(set) var undoUntil = -TimeInterval.infinity

    var canUndo: Bool { !gulps.isEmpty }

    /// Swallows `bubble`, which was picked up at `home`, at `time`.
    func swallow(_ bubble: BubbleID, home: CGPoint, at time: TimeInterval = now()) {
        swallow([Swallowed.Morsel(bubble: bubble, home: home)], at: time)
    }

    /// Swallows `morsels` in one gulp at `time`, with the microapp whose
    /// folder is named `microapp`, if it is uninstalling one.
    func swallow(
        _ morsels: [Swallowed.Morsel], microapp: String? = nil, at time: TimeInterval = now()
    ) {
        gulps.append(Swallowed(morsels: morsels, microapp: microapp, at: time))
        undoUntil = time + Self.swallowSeconds + Self.undoSeconds
    }

    /// Takes out what was swallowed last at `time`, returning it; its
    /// bubbles should fly back to where they were.
    func spitBack(at time: TimeInterval = now()) -> Swallowed? {
        guard let swallowed = gulps.popLast() else { return nil }
        // Leave time to bring back the one swallowed before it, too.
        undoUntil = time + Self.undoSeconds
        return swallowed
    }

    /// Forgets what is too old to bring back at `time`, returning it; it is
    /// now deleted for good.
    func forget(at time: TimeInterval = now()) -> [Swallowed] {
        guard canUndo, time >= undoUntil else { return [] }
        let gone = gulps
        gulps = []
        return gone
    }
}
