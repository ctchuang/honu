import Foundation
import Testing

@testable import Honu

/// A folder of its own for a test, which does not exist yet.
func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "honu-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
}

/// A file of its own for a test to save to, which does not exist yet.
func temporaryStoreURL() -> URL {
    temporaryDirectory().appending(path: "state.json")
}

/// A shell on a screen of `size`, saving to `storeURL` (a store of its own
/// unless given one), whose microapps ask `claude`, so tests never run the
/// real Claude Code.
@MainActor
func makeShell(
    size: CGSize = CGSize(width: 1200, height: 800), storeURL: URL = temporaryStoreURL(),
    claude: FakeClaude = FakeClaude()
) -> Shell {
    Shell(size: size, storeURL: storeURL, services: Services(claude: claude))
}

/// What tests do to a shell over and over.
extension Shell {
    /// The built-in microapps, as their own types.
    var notes: NotesApp { registry.app(AppID("notes")) as! NotesApp }
    var asks: AskApp { registry.app(AppID("ask")) as! AskApp }
    var web: WebApp { registry.app(AppID("web")) as! WebApp }

    /// A bubble showing a new note, at rest at `center`.
    func addNote(at center: CGPoint = CGPoint(x: 600, y: 300)) -> Bubble {
        addBubble(showing: notes.create(), of: notes, at: center, fresh: false)
    }

    /// Drags `bubble` far enough to call the octopus up, then drops it there.
    func drop(_ bubble: Bubble) {
        dragBubble(bubble, by: CGSize(width: 60, height: 0), pointer: bubble.center)
        let mouth = octopus.middle
        dragBubble(bubble, by: CGSize(width: 60, height: 0), pointer: mouth)
        endBubbleDrag(pointer: mouth)
    }

    /// Has `claude` make a microapp whose page is called `title`, in a
    /// bubble the turtle spits out, catching up at `time`. Returns the
    /// bubble and the microapp.
    func makeMicroapp(
        _ title: String, claude: FakeClaude, at time: TimeInterval = 1
    ) throws -> (Bubble, GeneratedApp) {
        choose(.make)
        let bubble = try #require(stage.bubbles.last)
        let microapp = try #require(maker.microapp(of: bubble.target.item))
        microapp.draft = "a \(title)"
        maker.make(bubble.target.item)
        let stream = try #require(claude.streams.last)
        stream.send(.text("<!doctype html><html><head><title>\(title)</title></head></html>"))
        stream.send(.done)
        tick(at: time)
        return (bubble, microapp)
    }
}
