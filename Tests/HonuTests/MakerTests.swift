import Foundation
import Testing

@testable import Honu

/// A page as Claude might write one, wrapped in a Markdown fence it was
/// told to leave out.
private func answer(_ title: String, size: String = "300x400", symbol: String = "timer")
    -> String
{
    """
    ```html
    <!doctype html>
    <html><head><title>\(title)</title>
    <meta content="\(size)" name="honu-size"><meta name='honu-symbol' content='\(symbol)'>
    </head><body>\(title)</body></html>
    ```
    """
}

struct AppSourceTests {
    @Test func thePageIsFoundInTheAnswerAndACutOffOneIsNot() {
        let page = AppSource.page(from: "Here it is:\n" + answer("Timer"))
        #expect(page?.hasPrefix("<!doctype html>") == true)
        #expect(page?.hasSuffix("</html>") == true)
        #expect(AppSource.page(from: "<!doctype html><html><body>Tim") == nil)
        #expect(AppSource.page(from: "I can't help with that.") == nil)
    }

    @Test func thePageSaysWhatItIsCalledHowBigItIsAndItsSymbol() throws {
        let page = try #require(AppSource.page(from: answer("Tea &amp; Toast")))
        #expect(
            AppSource.meta(of: page)
                == PageMeta(
                    title: "Tea & Toast", size: CGSize(width: 300, height: 400), symbol: "timer"))
        #expect(AppSource.meta(of: "<html></html>") == PageMeta())
    }

    @Test func sizesStayWithinLimits() {
        #expect(AppSource.size(from: "5000x10") == CGSize(width: 1000, height: 160))
        #expect(AppSource.size(from: " 320 X 240 ") == CGSize(width: 320, height: 240))
        #expect(AppSource.size(from: "wide") == nil)
    }
}

struct AppFolderTests {
    @Test func aChangedPageCanBeTakenBack() throws {
        let folder = AppFolder(url: temporaryDirectory())
        defer { try? FileManager.default.removeItem(at: folder.url) }
        #expect(folder.page() == nil)
        try folder.write("one")
        #expect(folder.versions.isEmpty)
        try folder.write("two")
        try folder.write("three")
        #expect(folder.versions == [1, 2])
        #expect(try folder.revert())
        #expect(folder.page() == "two")
        #expect(try folder.revert())
        #expect(folder.page() == "one")
        #expect(try !folder.revert())
        #expect(folder.page() == "one")
    }
}

@MainActor
struct MakerTests {
    private let claude = FakeClaude()
    private let root = temporaryDirectory()

    private func app() -> MakerApp {
        MakerApp(root: root, services: Services(claude: claude))
    }

    /// Runs `update` on `maker` and returns what it asked of the bubbles.
    private func update(_ maker: MakerApp) -> [Effect] {
        let context = Context(app: maker.id)
        maker.update(context)
        return context.effects
    }

    /// A new microapp in `maker` that Claude has made from `description`,
    /// answering with the page `answer`.
    private func made(_ maker: MakerApp, _ description: String, _ answer: String) -> ItemID {
        let item = maker.create()
        maker.microapps[item]!.draft = description
        maker.make(item)
        claude.streams.last!.send(.text(answer))
        claude.streams.last!.send(.done)
        _ = update(maker)
        return item
    }

    @Test func microappsAreKeptBesideTheStore() {
        #expect(
            MakerApp.root(for: Autosave.defaultURL)
                == Services.folder.appending(path: "microapps", directoryHint: .isDirectory))
        #expect(
            MakerApp.root(for: URL(filePath: "/tmp/honu.json")).path() == "/tmp/honu.microapps")
    }

    @Test func theSchemeServesOnlyTheMicroappsOwnFolder() {
        let folder = URL(filePath: "/tmp/microapps/A1", directoryHint: .isDirectory)
        let scheme = MicroappScheme(folder: folder)
        #expect(MicroappScheme.url(of: folder).absoluteString == "honu-app://A1/index.html")
        #expect(
            scheme.file(at: URL(string: "honu-app://A1/")!)?.path()
                == "/tmp/microapps/A1/index.html")
        #expect(
            scheme.file(at: URL(string: "honu-app://A1/img/a.png")!)?.path()
                == "/tmp/microapps/A1/img/a.png")
        #expect(scheme.file(at: URL(string: "honu-app://A1/../B2/data.json")!) == nil)
        #expect(scheme.file(at: URL(string: "honu-app://A1/%2E%2E/B2/data.json")!) == nil)
        // What the instances saved stays out of reach of the page.
        #expect(scheme.file(at: URL(string: "honu-app://A1/instances/X.json")!) == nil)
        #expect(scheme.file(at: URL(string: "honu-app://A1/Instances/X.json")!) == nil)
        #expect(scheme.file(at: URL(string: "honu-app://A1/img/../instances/X.json")!) == nil)
        #expect(scheme.file(at: URL(string: "honu-app://A1/instances")!) == nil)
        #expect(scheme.file(at: URL(string: "honu-app://A1/instances-list.js")!) != nil)
        #expect(
            scheme.file(at: URL(string: "honu-app://A1/a%20b.png")!)?.path(percentEncoded: false)
                == "/tmp/microapps/A1/a b.png")
    }

    @Test func pagesFetchOnlyFromTheWeb() {
        #expect(Bridge.fetchable("https://example.com/a") != nil)
        #expect(Bridge.fetchable("HTTP://example.com") != nil)
        #expect(Bridge.fetchable("file:///etc/passwd") == nil)
        #expect(Bridge.fetchable("honu-app://A1/data.json") == nil)
    }

    @Test func claudeMakesTheMicroappDescribedAndItRisesOnceLoaded() throws {
        let maker = app()
        let item = maker.create()
        let microapp = try #require(maker.microapps[item])
        #expect(maker.title(of: item) == "Microapp")
        microapp.draft = "  a pomodoro timer "
        maker.make(item)
        let request = try #require(claude.requests.last)
        #expect(request.prompt.hasSuffix("a pomodoro timer"))
        #expect(request.systemPrompt == MakerPrompt.system)
        #expect(request.effort == .medium)
        #expect(maker.isBusy(item))
        #expect(maker.title(of: item) == "a pomodoro timer")

        claude.streams[0].send(.text(answer("Pomodoro")))
        #expect(update(maker).isEmpty)
        #expect(microapp.written.contains("Pomodoro"))
        claude.streams[0].send(.done)
        #expect(update(maker).isEmpty, "rose before the page loaded")
        #expect(microapp.status == .running)
        #expect(!maker.isBusy(item))
        #expect(microapp.folder.page()?.hasPrefix("<!doctype html>") == true)
        #expect(maker.title(of: item) == "Pomodoro")
        #expect(maker.appearance(of: item).symbol == "timer")
        #expect(
            maker.appearance(of: item).panelSize
                == CGSize(width: 300, height: 400) + MakerApp.chrome)

        let target = ViewTarget(app: maker.id, item: item)
        maker.loaded(item)
        #expect(update(maker) == [.motion(target, .rise)])
        maker.loaded(item)
        #expect(update(maker).isEmpty, "rose again for the same page")
    }

    @Test func aMicroappNotMadeCanBeDescribedAgain() throws {
        let maker = app()
        let item = maker.create()
        let microapp = try #require(maker.microapps[item])
        microapp.draft = "a clock"
        maker.make(item)
        claude.streams[0].send(.text("Sorry, I can't."))
        claude.streams[0].send(.done)
        let target = ViewTarget(app: maker.id, item: item)
        #expect(update(maker) == [.motion(target, .wobble)])
        #expect(microapp.status == .describing(error: "Claude's answer wasn't a complete page."))
        #expect(microapp.focusRequests == 1)
        #expect(microapp.draft == "a clock")

        maker.make(item)
        claude.streams[1].send(.failed("Rate limited."))
        #expect(update(maker) == [.motion(target, .wobble)])
        #expect(microapp.status == .describing(error: "Rate limited."))
    }

    @Test func aChangeCanBeAskedForAndTakenBack() throws {
        let maker = app()
        let item = made(maker, "a clock", answer("Clock"))
        let microapp = try #require(maker.microapps[item])
        #expect(!microapp.canRevert)
        let first = microapp.version

        microapp.draft = "make it blue"
        maker.change(item)
        let prompt = try #require(claude.asked.last)
        #expect(prompt.contains("<title>Clock</title>"))
        #expect(prompt.contains("make it blue"))
        #expect(prompt.contains("a clock"))
        #expect(maker.isBusy(item))

        claude.streams[1].send(.text(answer("Blue Clock")))
        claude.streams[1].send(.done)
        _ = update(maker)
        #expect(maker.title(of: item) == "Blue Clock")
        #expect(microapp.draft.isEmpty)
        #expect(microapp.canRevert)
        #expect(microapp.version > first)

        maker.revert(item)
        #expect(maker.title(of: item) == "Clock")
        #expect(!microapp.canRevert)
    }

    @Test func aFailedChangeLeavesThePageAsItWas() throws {
        let maker = app()
        let item = made(maker, "a clock", answer("Clock"))
        let microapp = try #require(maker.microapps[item])
        microapp.draft = "make it blue"
        maker.change(item)
        claude.streams[1].send(.text("<!doctype html><html><body>Blu"))
        claude.streams[1].close()
        #expect(update(maker) == [.motion(ViewTarget(app: maker.id, item: item), .wobble)])
        #expect(microapp.status == .running)
        #expect(microapp.notice == "Claude stopped before the page was finished.")
        #expect(microapp.draft == "make it blue")
        #expect(maker.title(of: item) == "Clock")
        #expect(!microapp.canRevert)
    }

    @Test func errorsAsANewPageStartsAreFixedOnceWithoutAsking() throws {
        let maker = app()
        let item = made(maker, "a clock", answer("Clock"))
        let microapp = try #require(maker.microapps[item])
        microapp.report("error: x is not defined", at: 100)
        microapp.report("error: y is not defined", at: 100.5)
        #expect(microapp.problems.count == 2)
        #expect(microapp.poll(claude, at: 100.9) == nil)
        #expect(claude.requests.count == 1, "fixed before the errors had all come in")
        _ = microapp.poll(claude, at: 101.1)
        #expect(claude.requests.count == 2)
        #expect(microapp.status == .writing(.fixing))
        #expect(claude.asked[1].contains("x is not defined"))
        #expect(claude.asked[1].contains("y is not defined"))

        claude.streams[1].send(.text(answer("Clock")))
        claude.streams[1].send(.done)
        _ = microapp.poll(claude, at: 130)
        #expect(microapp.problems.isEmpty)
        // A fix that still fails is left to the user.
        _ = microapp.loaded(at: 131)
        microapp.report("error: z is not defined", at: 131)
        _ = microapp.poll(claude, at: 140)
        #expect(claude.requests.count == 2)
        #expect(microapp.problems == ["error: z is not defined"])
        maker.fix(item)
        #expect(claude.requests.count == 3)
    }

    @Test func laterErrorsWaitForTheUser() throws {
        let maker = app()
        let item = made(maker, "a clock", answer("Clock"))
        let microapp = try #require(maker.microapps[item])
        _ = microapp.loaded(at: 100)
        microapp.report("error: x is not defined", at: 100 + GeneratedApp.fixWindow + 1)
        _ = microapp.poll(claude, at: 200)
        #expect(claude.requests.count == 1)
        #expect(microapp.problems.count == 1)
    }

    @Test func microappsComeBackAfterARelaunch() throws {
        let maker = app()
        let clock = made(maker, "a clock", answer("Clock"))
        maker.resize(clock, to: CGSize(width: 500, height: 5000))
        let unfinished = maker.create()
        maker.microapps[unfinished]!.draft = "a timer"
        maker.make(unfinished)
        let blank = maker.create()
        maker.microapps[blank]!.draft = "a half-typed descr"
        // A folder no microapp has, as of one deleted while Honu was not running.
        let stray = AppFolder(url: root.appending(path: UUID().uuidString))
        try stray.write("stray")

        let restored = app()
        restored.load(try #require(maker.save()))
        #expect(restored.items == [clock, unfinished, blank])
        let back = try #require(restored.microapps[clock])
        #expect(back.status == .running)
        #expect(back.description == "a clock")
        #expect(back.size == CGSize(width: 500, height: 800))
        #expect(restored.title(of: clock) == "Clock")
        #expect(
            restored.microapps[unfinished]?.status
                == .describing(error: "Honu quit before the microapp was finished."))
        #expect(restored.microapps[unfinished]?.draft == "a timer")
        #expect(restored.microapps[blank]?.draft == "a half-typed descr")
        #expect(!FileManager.default.fileExists(atPath: stray.url.path()))
        #expect(back.folder.page() != nil)
    }

    @Test func aDeletedMicroappsFolderGoesToTheTrash() throws {
        let maker = app()
        let item = made(maker, "a clock", answer("Clock"))
        let folder = try #require(maker.microapps[item]?.folder)
        #expect(FileManager.default.fileExists(atPath: folder.url.path()))
        maker.remove(item)
        #expect(!FileManager.default.fileExists(atPath: folder.url.path()))
        #expect(maker.items.isEmpty)
    }
}

extension CGSize {
    fileprivate static func + (a: CGSize, b: CGSize) -> CGSize {
        CGSize(width: a.width + b.width, height: a.height + b.height)
    }
}
