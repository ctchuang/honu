import Foundation
import Testing

@testable import Honu

@MainActor
struct NotesAppTests {
    private func title(_ text: String) -> String {
        let notes = NotesApp()
        let item = notes.create()
        notes.setText(text, of: item)
        return notes.title(of: item)
    }

    @Test func titleIsTheFirstLineWithText() {
        #expect(title("") == NotesApp.emptyLabel)
        #expect(title(" \n\n") == NotesApp.emptyLabel)
        #expect(title("\n  Groceries  \nmilk\neggs") == "Groceries")
        #expect(
            title("Remember to call the aquarium about the turtle") == "Remember to call the aqu…")
    }

    @Test func notesComeBackAfterARelaunch() throws {
        let notes = NotesApp()
        let a = notes.create()
        notes.setText("Groceries\nmilk", of: a)
        let restored = NotesApp()
        restored.load(try #require(notes.save()))
        #expect(restored.items == [a])
        #expect(restored.notes[a] == "Groceries\nmilk")
        #expect(restored.create() > a, "reused a restored id")
        // Anything unreadable is simply nothing to restore.
        let empty = NotesApp()
        empty.load(Data(#"{"not": "notes"}"#.utf8))
        #expect(empty.items.isEmpty)
    }

    @Test func notesAreKeptApartUntilRemoved() {
        let notes = NotesApp()
        let a = notes.create()
        let b = notes.create()
        #expect(a != b)
        notes.setText("a", of: a)
        #expect(notes.title(of: a) == "a")
        #expect(notes.title(of: b) == NotesApp.emptyLabel)
        notes.remove(a)
        #expect(notes.title(of: a) == NotesApp.emptyLabel)
        #expect(notes.items == [b])
        // Text for a removed note goes nowhere.
        notes.setText("gone", of: a)
        #expect(notes.items == [b])
    }

    @Test func onlyANewNoteTakesTheFocus() {
        let notes = NotesApp()
        let item = notes.create()
        let fresh = notes.newViewState(for: item, fresh: true) as? NoteViewState
        let restored = notes.newViewState(for: item, fresh: false) as? NoteViewState
        #expect(fresh?.focusPending == true)
        #expect(restored?.focusPending == false)
    }
}

@MainActor
struct WebAppTests {
    @Test func youTubeLinksAreRecognized() {
        let id = { (text: String) in URL(string: text).flatMap(youTubeID) }
        #expect(id("https://www.youtube.com/watch?v=aqz-KE-bpKQ") == "aqz-KE-bpKQ")
        #expect(id("https://youtube.com/watch?t=10&v=aqz-KE-bpKQ") == "aqz-KE-bpKQ")
        #expect(id("https://m.youtube.com/watch?v=aqz-KE-bpKQ") == "aqz-KE-bpKQ")
        #expect(id("https://youtu.be/aqz-KE-bpKQ") == "aqz-KE-bpKQ")
        #expect(id("https://www.youtube.com/embed/aqz-KE-bpKQ") == "aqz-KE-bpKQ")
        #expect(id("https://www.youtube.com/shorts/aqz-KE-bpKQ") == "aqz-KE-bpKQ")
        #expect(id("https://www.youtube.com/") == nil)
        #expect(id("https://notyoutube.com/watch?v=aqz-KE-bpKQ") == nil)
        #expect(id("https://en.wikipedia.org/wiki/Sea_turtle") == nil)
    }

    @Test func aPageOpensWhatWasTyped() throws {
        let web = WebApp()
        let item = web.create()
        #expect(web.url(of: item) == nil)
        #expect(web.title(of: item) == "Web Page")
        web.open("   ", in: item)
        #expect(web.url(of: item) == nil)
        web.open(" en.wikipedia.org/wiki/Sea_turtle\n", in: item)
        #expect(web.url(of: item)?.absoluteString == "https://en.wikipedia.org/wiki/Sea_turtle")
        #expect(web.title(of: item) == "en.wikipedia.org")
        #expect(web.appearance(of: item).symbol == "safari.fill")
        web.open("http://youtu.be/aqz-KE-bpKQ", in: item)
        #expect(web.url(of: item)?.absoluteString == "http://youtu.be/aqz-KE-bpKQ")
        #expect(web.appearance(of: item).symbol == "play.rectangle.fill")

        let restored = WebApp()
        restored.load(try #require(web.save()))
        #expect(restored.url(of: item) == web.url(of: item))
        #expect(restored.create() > item)
    }
}
