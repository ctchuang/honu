import Foundation
import Testing
import WebKit

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

    @Test func onlyTheTitleLineIsSetAsATitle() {
        func titleRuns(_ note: String) -> [String] {
            var text = AttributedString(note)
            text.font = NoteEditor.bodyFont  // Formatting from before goes.
            NoteEditor.style(&text)
            return text.runs.filter { $0.font == NoteEditor.titleFont }
                .map { String(text[$0.range].characters) }
        }
        #expect(titleRuns("") == [])
        #expect(titleRuns(" \n\n") == [])
        #expect(titleRuns("Groceries\nmilk") == ["Groceries"])
        #expect(titleRuns("\n  🐢 Groceries \nmilk\neggs") == ["  🐢 Groceries "])
        // The editor's runs go with every change of font, the body's included.
        var text = AttributedString("Groceries\nmilk")
        NoteEditor.style(&text)
        #expect(text.runs.count == 2)
        #expect(text.runs.first?.font == NoteEditor.titleFont)
        #expect(text.runs.last?.font == nil)
    }

    @Test func aNoteShowsItsOwnTitle() {
        let notes = NotesApp()
        #expect(!notes.appearance(of: notes.create()).showsTitle)
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
        let fresh = notes.newViewState(for: item, fresh: true)
        let restored = notes.newViewState(for: item, fresh: false)
        #expect(fresh.focusPending)
        #expect(!restored.focusPending)
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
        web.open("http://youtu.be/aqz-KE-bpKQ", in: item)
        #expect(web.url(of: item)?.absoluteString == "http://youtu.be/aqz-KE-bpKQ")

        let restored = WebApp()
        restored.load(try #require(web.save()))
        #expect(restored.url(of: item) == web.url(of: item))
        #expect(restored.create() > item)
    }
}

@MainActor
struct WebStatusTests {
    private func update(_ web: WebApp) -> [Effect] {
        let context = Context(app: web.id)
        web.update(context)
        return context.effects
    }

    @Test func aLoadingPageBreathesAndRisesWhenItHasLoaded() {
        let web = WebApp()
        let item = web.create()
        web.open("en.wikipedia.org", in: item)
        #expect(!web.isBusy(item))
        web.startedLoading(item)
        #expect(web.isBusy(item))
        #expect(update(web).isEmpty)
        web.stoppedLoading(item, .finished)
        #expect(!web.isBusy(item))
        #expect(update(web) == [.motion(ViewTarget(app: web.id, item: item), .rise)])
        #expect(update(web).isEmpty, "rose twice for one load")
    }

    @Test func aLoadCutShortDoesNotRise() {
        let web = WebApp()
        let item = web.create()
        web.open("en.wikipedia.org", in: item)
        web.startedLoading(item)
        web.stoppedLoading(item, .cancelled)
        #expect(!web.isBusy(item))
        #expect(update(web).isEmpty)
    }

    @Test func aFailedLoadWobbles() {
        let web = WebApp()
        let item = web.create()
        web.open("no-such-host.invalid", in: item)
        web.startedLoading(item)
        web.stoppedLoading(item, .failed)
        #expect(!web.isBusy(item))
        #expect(update(web) == [.motion(ViewTarget(app: web.id, item: item), .wobble)])
    }

    @Test func loadErrorsAreToldFromLoadsGivenUp() {
        #expect(LoadEnd(CancellationError()) == .cancelled)
        #expect(LoadEnd(URLError(.cancelled)) == .cancelled)
        #expect(LoadEnd(NSError(domain: "WebKitErrorDomain", code: 102)) == .cancelled)
        #expect(LoadEnd(URLError(.cannotFindHost)) == .failed)
        #expect(LoadEnd(URLError(.notConnectedToInternet)) == .failed)
        // As WebPage reports them, wrapped in its own error.
        let wrapped = WebPage.NavigationError.failedProvisionalNavigation
        #expect(LoadEnd(wrapped(URLError(.cancelled))) == .cancelled)
        #expect(LoadEnd(wrapped(URLError(.cannotFindHost))) == .failed)
        #expect(LoadEnd(WebPage.NavigationError.pageClosed) == .cancelled)
        #expect(LoadEnd(WebPage.NavigationError.invalidURL) == .failed)
    }

    @Test func aPageInTwoBubblesBreathesUntilBothHaveLoaded() {
        let web = WebApp()
        let item = web.create()
        web.open("en.wikipedia.org", in: item)
        web.startedLoading(item)
        web.startedLoading(item)
        web.stoppedLoading(item, .finished)
        #expect(web.isBusy(item))
        web.stoppedLoading(item, .finished)
        #expect(!web.isBusy(item))
        #expect(update(web).count == 1)
    }

    @Test func aDeletedPageNeitherBreathesNorRises() {
        let web = WebApp()
        let item = web.create()
        web.open("en.wikipedia.org", in: item)
        web.startedLoading(item)
        web.remove(item)
        #expect(!web.isBusy(item))
        web.stoppedLoading(item, .finished)
        #expect(update(web).isEmpty)
    }

    @Test func youTubeLinksPlayInTheEmbeddedPlayer() throws {
        let video = try #require(URL(string: "https://youtu.be/aqz-KE-bpKQ"))
        let page = try #require(URL(string: "https://en.wikipedia.org/wiki/Sea_turtle"))
        #expect(PageSource(video) == .video(id: "aqz-KE-bpKQ"))
        #expect(PageSource(page) == .web(page))
    }
}
