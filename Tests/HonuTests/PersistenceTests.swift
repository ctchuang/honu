import Foundation
import Testing

@testable import Honu

@MainActor
struct PersistenceTests {
    private let size = CGSize(width: 1200, height: 800)

    @Test func bubblesAndItemsComeBackInPlace() throws {
        let url = temporaryStoreURL()
        let shell = makeShell(size: size, storeURL: url)
        shell.turtle.move(to: CGPoint(x: 500, y: 400))
        shell.start(AppID("notes"))
        let bubble = try #require(shell.stage.bubbles.first)
        shell.notes.setText("Groceries\nmilk", of: bubble.target.item)
        shell.save()

        // On a screen 200 points wider and taller, everything moves with its center.
        let bigger = CGSize(width: size.width + 200, height: size.height + 200)
        let restored = makeShell(size: bigger, storeURL: url)
        let back = try #require(restored.stage.bubbles.first)
        #expect(restored.stage.bubbles.count == 1)
        #expect(back.target == bubble.target)
        #expect(
            back.center == CGPoint(x: bubble.destination.x + 100, y: bubble.destination.y + 100))
        #expect(restored.notes.notes[back.target.item] == "Groceries\nmilk")
        #expect(restored.turtle.origin == CGPoint(x: 600, y: 500))
        // A restored note does not grab the focus.
        #expect((back.viewState as? NoteViewState)?.focusPending == false)
    }

    @Test func bubblesSavedClosedComeBackAsAnyOther() throws {
        let url = temporaryStoreURL()
        let shell = makeShell(size: size, storeURL: url)
        shell.start(AppID("notes"))
        shell.save()
        // A store from when bubbles could close into an icon says whether each was open.
        var state = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let bubbles = try #require(state["bubbles"] as? [[String: Any]])
        state["bubbles"] = bubbles.map { $0.merging(["isOpen": false]) { $1 } }
        try JSONSerialization.data(withJSONObject: state).write(to: url)

        let restored = makeShell(size: size, storeURL: url)
        let back = try #require(restored.stage.bubbles.first)
        #expect(back.size == Appearance().size)
        #expect(restored.content(of: back) != nil)
    }

    @Test func showingOnAllDesktopsComesBack() throws {
        let url = temporaryStoreURL()
        let shell = makeShell(size: size, storeURL: url)
        #expect(shell.isOnAllDesktops, "on every desktop until turned off")
        shell.rightClickTurtle(at: shell.turtle.center)
        shell.toggleAllDesktops()
        #expect(!shell.isOnAllDesktops)
        #expect(shell.popup == nil, "the menu closes")
        #expect(!makeShell(size: size, storeURL: url).isOnAllDesktops)

        shell.toggleAllDesktops()
        #expect(makeShell(size: size, storeURL: url).isOnAllDesktops)

        // A store from before the setting counts as on every desktop.
        let old = temporaryStoreURL()
        try FileManager.default.createDirectory(
            at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"apps":{},"bubbles":[],"turtle":[0,0]}"#.utf8).write(to: old)
        let restored = makeShell(size: size, storeURL: old)
        #expect(restored.turtle.origin == CGPoint(x: 600, y: 400), "the old store was read")
        #expect(restored.isOnAllDesktops)
    }

    @Test func bubblesOfItemsNoLongerThereDoNotComeBack() throws {
        let url = temporaryStoreURL()
        let notes = NotesApp()
        let kept = notes.create()
        notes.setText("kept", of: kept)
        let bubble = { (app: String, item: ItemID) in
            SavedBubble(target: ViewTarget(app: AppID(app), item: item), offset: .zero)
        }
        var state = SavedState()
        state.apps["notes"] = String(decoding: try #require(notes.save()), as: UTF8.self)
        // A note that is gone, and a microapp Honu no longer has.
        state.bubbles = [
            bubble("notes", ItemID(rawValue: 99)), bubble("notes", kept), bubble("gone", kept),
        ]
        Autosave(url: url).save(state)

        let shell = makeShell(size: size, storeURL: url)
        #expect(shell.stage.bubbles.map(\.target) == [ViewTarget(app: AppID("notes"), item: kept)])
        #expect(shell.notes.items == [kept] && shell.notes.notes[kept] == "kept")
    }

    @Test func swallowedBubblesAndTheirItemsCountAsDeleted() throws {
        let url = temporaryStoreURL()
        let shell = makeShell(size: size, storeURL: url)
        shell.start(AppID("notes"))
        shell.start(AppID("notes"))
        let doomed = try #require(shell.stage.bubbles.first)
        shell.drop(doomed)
        #expect(doomed.isSwallowed && shell.octopus.canUndo)
        shell.save()

        let restored = makeShell(size: size, storeURL: url)
        #expect(restored.stage.bubbles.count == 1)
        #expect(restored.notes.items.count == 1, "kept the swallowed bubble's note")
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
        shell.notes.setText("changed", of: bubble.target.item)
        shell.save()
        #expect(FileManager.default.fileExists(atPath: url.path()))
    }

    @Test func undoBringsTheBubbleBackBeforeItIsForgotten() throws {
        let shell = makeShell(size: size)
        shell.start(AppID("notes"))
        let bubble = try #require(shell.stage.bubbles.first)
        shell.drop(bubble)
        shell.undoDelete()
        #expect(!bubble.isSwallowed && !shell.octopus.canUndo)
        #expect(shell.stage.bubbles.last === bubble)
    }
}

@MainActor
struct AutosaveMoveTests {
    @Test func movingByItselfIsNotAChangeButDraggingIs() throws {
        let url = temporaryStoreURL()
        let shell = makeShell(storeURL: url)
        shell.start(AppID("notes"))
        let bubble = try #require(shell.stage.bubbles.first)
        // Let it land and be saved.
        for frame in 0...120 {
            shell.tick(at: 1000 + Double(frame) / 60)
        }
        shell.save()
        try FileManager.default.removeItem(at: url)

        bubble.center.x += 3
        shell.save()
        #expect(!FileManager.default.fileExists(atPath: url.path()), "saved a push")

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

    @Test func changesAreCheckedForOnceASecond() {
        let url = temporaryStoreURL()
        let autosave = Autosave(url: url)
        var state = SavedState()
        var checks = 0
        let snapshot = {
            checks += 1
            return state
        }
        autosave.tick(at: 100, snapshot)
        #expect(checks == 1 && FileManager.default.fileExists(atPath: url.path()))

        state.allDesktops = false
        autosave.tick(at: 100.5, snapshot)
        #expect(checks == 1, "checked again within a second")
        autosave.tick(at: 101, snapshot)
        #expect(checks == 2)
        #expect(Autosave(url: url).restore()?.allDesktops == false)
    }

    @Test func aStoreThatCannotBeReadIsKeptAsideNotWrittenOver() throws {
        let url = temporaryStoreURL()
        let unreadable = Data(#"{"bubbles": "not bubbles"}"#.utf8)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try unreadable.write(to: url)

        let shell = makeShell(storeURL: url)
        #expect(shell.stage.bubbles.isEmpty)
        let aside = Autosave(url: url).unreadableURL
        #expect(aside.lastPathComponent == "state.unreadable.json")
        #expect(try Data(contentsOf: aside) == unreadable)

        shell.start(AppID("notes"))
        shell.save()
        #expect(try Data(contentsOf: aside) == unreadable, "wrote over the unreadable store")
        #expect(makeShell(storeURL: url).stage.bubbles.count == 1)
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
