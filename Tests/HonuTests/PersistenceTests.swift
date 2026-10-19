import Foundation
import Testing

@testable import Honu

@MainActor
struct PersistenceTests {
    private let size = CGSize(width: 1200, height: 800)

    private func notes(_ shell: Shell) -> NotesApp {
        shell.registry.app(AppID("notes")) as! NotesApp
    }

    @Test func bubblesAndItemsComeBackInPlace() throws {
        let url = temporaryStoreURL()
        let shell = makeShell(size: size, storeURL: url)
        shell.turtle.move(to: CGPoint(x: 500, y: 400))
        shell.start(AppID("notes"))
        let bubble = try #require(shell.stage.bubbles.first)
        notes(shell).setText("Groceries\nmilk", of: bubble.target.item)
        shell.save()

        // On a screen 200 points wider and taller, everything moves with its center.
        let bigger = CGSize(width: size.width + 200, height: size.height + 200)
        let restored = makeShell(size: bigger, storeURL: url)
        let back = try #require(restored.stage.bubbles.first)
        #expect(restored.stage.bubbles.count == 1)
        #expect(back.target == bubble.target)
        #expect(
            back.center == CGPoint(x: bubble.destination.x + 100, y: bubble.destination.y + 100))
        #expect(notes(restored).notes[back.target.item] == "Groceries\nmilk")
        #expect(restored.turtle.origin == CGPoint(x: 600, y: 500))
        // A restored note does not grab the focus.
        #expect((back.viewState as? NoteViewState)?.focusPending == false)
    }

    @Test func swallowedBubblesAndTheirItemsCountAsDeleted() throws {
        let url = temporaryStoreURL()
        let shell = makeShell(size: size, storeURL: url)
        shell.start(AppID("notes"))
        shell.start(AppID("notes"))
        let doomed = try #require(shell.stage.bubbles.first)
        // Drag it onto the octopus, which comes up once it has moved a little way.
        shell.dragBubble(doomed, by: CGSize(width: 60, height: 0), pointer: doomed.center)
        let mouth = shell.octopus.middle
        shell.dragBubble(doomed, by: CGSize(width: 60, height: 0), pointer: mouth)
        #expect(doomed.isDoomed)
        shell.endBubbleDrag(pointer: mouth)
        #expect(doomed.isSwallowed && shell.octopus.canUndo)
        shell.save()

        let restored = makeShell(size: size, storeURL: url)
        #expect(restored.stage.bubbles.count == 1)
        #expect(notes(restored).items.count == 1, "kept the swallowed bubble's note")
        #expect(!restored.stage.shows(doomed.target))
    }

    @Test func onlyChangesAreWritten() throws {
        let url = temporaryStoreURL()
        let shell = makeShell(size: size, storeURL: url)
        shell.start(AppID("notes"))
        shell.save()
        #expect(FileManager.default.fileExists(atPath: url.path()))

        try FileManager.default.removeItem(at: url)
        shell.save()
        #expect(!FileManager.default.fileExists(atPath: url.path()), "wrote with nothing changed")

        let bubble = try #require(shell.stage.bubbles.first)
        notes(shell).setText("changed", of: bubble.target.item)
        shell.save()
        #expect(FileManager.default.fileExists(atPath: url.path()))
    }

    @Test func undoBringsTheBubbleBackBeforeItIsForgotten() throws {
        let shell = makeShell(size: size)
        shell.start(AppID("notes"))
        let bubble = try #require(shell.stage.bubbles.first)
        shell.dragBubble(bubble, by: CGSize(width: 60, height: 0), pointer: bubble.center)
        let mouth = shell.octopus.middle
        shell.dragBubble(bubble, by: CGSize(width: 60, height: 0), pointer: mouth)
        shell.endBubbleDrag(pointer: mouth)
        shell.undoDelete()
        #expect(!bubble.isSwallowed && !shell.octopus.canUndo)
        #expect(shell.stage.bubbles.last === bubble)
    }
}

@MainActor
struct AutosaveDriftTests {
    @Test func driftingIsNotAChangeButDraggingIs() throws {
        let url = temporaryStoreURL()
        let shell = makeShell(storeURL: url)
        shell.start(AppID("notes"))
        let bubble = try #require(shell.stage.bubbles.first)
        // Let it land, open, and be saved.
        for frame in 0...120 {
            shell.tick(at: 1000 + Double(frame) / 60)
        }
        shell.save()
        try FileManager.default.removeItem(at: url)

        bubble.center.x += 3
        shell.save()
        #expect(!FileManager.default.fileExists(atPath: url.path()), "saved a drift")

        shell.dragBubble(bubble, by: CGSize(width: 100, height: 0), pointer: bubble.center)
        shell.endBubbleDrag(pointer: bubble.center)
        shell.save()
        #expect(FileManager.default.fileExists(atPath: url.path()), "lost a drag")
    }
}

@MainActor
struct AutosaveTests {
    @Test func aStateComesBackAsSavedWithoutAShell() throws {
        let url = temporaryStoreURL()
        var state = SavedState()
        state.turtle = CGPoint(x: -100, y: 50)
        state.apps["notes"] = #"{"b":1,"a":2}"#
        Autosave(url: url).save(state)

        let autosave = Autosave(url: url)
        let restored = try #require(autosave.restore())
        #expect(restored.turtle == state.turtle)
        #expect(restored.apps["notes"] == #"{"a":2,"b":1}"#)
        // What was restored counts as saved, whatever order the keys come in.
        try FileManager.default.removeItem(at: url)
        autosave.save(state)
        #expect(!FileManager.default.fileExists(atPath: url.path()), "wrote with nothing changed")
    }
}

struct CanonicalJSONTests {
    @Test @MainActor func keyOrderDoesNotCount() throws {
        let a = try #require(Autosave.canonical(Data(#"[{"text":"","id":{"rawValue":1}}]"#.utf8)))
        let b = try #require(Autosave.canonical(Data(#"[{"id":{"rawValue":1},"text":""}]"#.utf8)))
        #expect(a == b)
        #expect(Autosave.canonical(Data("not json".utf8)) == Data("not json".utf8))
    }
}
