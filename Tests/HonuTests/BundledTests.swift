import Foundation
import Testing

@testable import Honu

/// Writes a page into `root/name/index.html` for each of `pages`, by name,
/// and returns `root`.
@discardableResult
func writePages(_ pages: [String: String], in root: URL = temporaryDirectory()) throws -> URL {
    for (name, page) in pages {
        let folder = root.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(page.utf8).write(to: folder.appending(path: "index.html"))
    }
    return root
}

/// A page with `title`, and the size and symbol it asks for, if any.
func page(_ title: String, size: String? = nil, symbol: String? = nil) -> String {
    let size = size.map { #"<meta name="honu-size" content="\#($0)">"# } ?? ""
    let symbol = symbol.map { #"<meta name="honu-symbol" content="\#($0)">"# } ?? ""
    return "<!doctype html><html><head><title>\(title)</title>\(size)\(symbol)</head></html>"
}

/// The microapps built into Honu as web pages.
@MainActor
struct BundledTests {
    /// Two pages built in: a timer and a world clock.
    private func pages() throws -> [BundledPage] {
        let root = try writePages([
            "timer": page("Timer", size: "300x200", symbol: "timer"),
            "world-clock": page("World Clock", symbol: "no.such.symbol"),
        ])
        return BuiltinCatalog.pages(in: root)
    }

    private func app(_ shell: Shell, _ name: String) throws -> BundledWebApp {
        try #require(shell.registry.app(AppID("builtin.\(name)")) as? BundledWebApp)
    }

    // MARK: The catalog

    @Test(arguments: ["timer", "world-clock", "a", "a1", "x-2-y"])
    func validNames(name: String) {
        #expect(BuiltinCatalog.isValidName(name))
    }

    @Test(arguments: [
        "", "Timer", "TIMER", "1timer", "-timer", "world_clock", "world.clock", "world clock",
        "café", "timer/", "海",
    ])
    func invalidNames(name: String) {
        #expect(!BuiltinCatalog.isValidName(name))
    }

    @Test func theCatalogReadsWhatEachPageSaysAboutItself() throws {
        let pages = try pages()
        #expect(pages.map(\.name) == ["timer", "world-clock"])
        let timer = try #require(pages.first)
        #expect(timer.label == "Timer")
        #expect(timer.meta.size == CGSize(width: 300, height: 200))
        #expect(timer.meta.symbol == "timer")
        #expect(timer.folder.lastPathComponent == "timer")
    }

    @Test func theCatalogSkipsWhatIsNoPageOrBadlyNamed() throws {
        let root = try writePages([
            "good": page("Good"),
            "Bad": page("Bad"),
            "also_bad": page("Also Bad"),
        ])
        // A folder without a page, and a file that is no folder.
        try FileManager.default.createDirectory(
            at: root.appending(path: "empty"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appending(path: "stray.html"))
        #expect(BuiltinCatalog.pages(in: root).map(\.name) == ["good"])
    }

    @Test func theCatalogOrdersByLabelThenName() throws {
        let root = try writePages([
            "b": page("Zebra"),
            "a": page("apple"),
            "d": page("Same"),
            "c": page("Same"),
            "untitled": "<!doctype html><html><head></head></html>",
        ])
        let pages = BuiltinCatalog.pages(in: root)
        #expect(pages.map(\.name) == ["a", "c", "d", "untitled", "b"])
        #expect(pages.first { $0.name == "untitled" }?.label == "untitled")
    }

    @Test func noFolderIsNoPages() {
        #expect(BuiltinCatalog.pages(in: temporaryDirectory()).isEmpty)
    }

    // MARK: In the launcher

    @Test func theReefListsThemAfterTheNativeMicroapps() throws {
        let shell = makeShell(pages: try pages())
        let tiles = shell.launcherTiles(in: .builtIn)
        #expect(
            tiles.map(\.kind) == [
                .stock(AppID("notes")), .stock(AppID("builtin.timer")),
                .stock(AppID("builtin.world-clock")),
            ])
        #expect(tiles.map(\.label) == ["Note", "Timer", "World Clock"])
        // A symbol that does not exist falls back to the default.
        #expect(tiles.map(\.symbol) == ["note.text", "timer", MakerApp.defaultSymbol])
        let reef = try #require(shell.launcherTiles.first)
        #expect(reef.preview == tiles.map(\.symbol))
        // The top level is the same with them or without.
        #expect(shell.launcherTiles.map(\.kind) == [.folder(.builtIn), .make])
    }

    @Test func theReefsTileShowsOnlyTheFirstFew() throws {
        let names = ["a", "b", "c", "d", "e"]
        let root = try writePages(
            Dictionary(uniqueKeysWithValues: names.map { ($0, page($0.uppercased())) }))
        let shell = makeShell(pages: BuiltinCatalog.pages(in: root))
        #expect(shell.launcherTiles(in: .builtIn).count == 6)
        let reef = try #require(shell.launcherTiles.first)
        #expect(reef.preview.count == LauncherView.previewCount)
    }

    @Test func theirTilesDoNotDragAndCannotBeUninstalled() throws {
        let shell = makeShell(pages: try pages())
        shell.clickTurtle(at: shell.turtle.center)
        shell.open(.builtIn)
        for tile in shell.launcherTiles {
            #expect(!shell.dragTile(tile, from: .zero, to: CGPoint(x: 500, y: 500)))
            shell.uninstall(tile, from: .zero)
        }
        #expect(shell.swallowedTile == nil && shell.tileDrag == nil)
        #expect(shell.launcherTiles(in: .builtIn).count == 3)
    }

    @Test func choosingOneSpitsOutABubbleOfItsPage() throws {
        let shell = makeShell(pages: try pages())
        shell.clickTurtle(at: shell.turtle.center)
        shell.choose(.folder(.builtIn))
        shell.choose(.stock(AppID("builtin.timer")))
        #expect(shell.popup == nil)
        let bubble = try #require(shell.stage.bubbles.last)
        let timer = try app(shell, "timer")
        let item = try #require(timer.items.first)
        #expect(bubble.target == ViewTarget(app: timer.id, item: item))
        #expect(shell.title(of: bubble) == "Timer")
        #expect(bubble.size == CGSize(width: 300, height: 200) + BundledWebApp.chrome)
        #expect(shell.content(of: bubble) != nil)
        #expect(
            !InputRouter(shell: shell).handle(
                .key(text: "a", unmodified: "a", command: false, control: false), typing: false),
            "a page took type-ahead")
    }

    @Test func aPageThatSaysNoSizeGetsTheDefault() throws {
        let shell = makeShell(pages: try pages())
        shell.start(AppID("builtin.world-clock"))
        let bubble = try #require(shell.stage.bubbles.last)
        #expect(bubble.size == MakerApp.defaultPageSize + BundledWebApp.chrome)
        #expect(
            shell.appearance(of: bubble).minSize == AppSource.minSize + BundledWebApp.chrome)
    }

    // MARK: Running

    @Test func itsPagesAreServedApartFromTheMicroappsClaudeMakes() throws {
        let timer = try app(makeShell(pages: try pages()), "timer")
        #expect(timer.site.scheme == BuiltinCatalog.scheme)
        #expect(timer.site.scheme != MicroappScheme.scheme)
        #expect(timer.site.pageURL.absoluteString == "honu-builtin://timer/index.html")
        #expect(
            timer.site.file(at: timer.site.pageURL)
                == timer.page.folder.appending(path: "index.html").standardizedFileURL)
        #expect(
            timer.site.file(at: URL(string: "honu-builtin://timer/../world-clock/index.html")!)
                == nil)
    }

    @Test func aPageThatLoadsRisesAndOneThatFailsWobblesOnce() throws {
        let shell = makeShell(pages: try pages())
        shell.start(AppID("builtin.timer"))
        let bubble = try #require(shell.stage.bubbles.last)
        let timer = try app(shell, "timer")
        let item = bubble.target.item

        timer.loaded(item)
        shell.tick(at: 1)
        #expect(bubble.motion?.motion == .rise)

        timer.report("error: boom", in: item)
        shell.tick(at: 5)
        #expect(bubble.motion?.motion == .wobble)
        // More errors from the same load leave it be.
        var context = Context(app: timer.id)
        timer.report("error: again", in: item)
        timer.update(context)
        #expect(context.effects.isEmpty)

        // After loading again, an error wobbles again.
        timer.loaded(item)
        timer.report("error: boom", in: item)
        context = Context(app: timer.id)
        timer.update(context)
        #expect(
            context.effects == [
                .motion(bubble.target, .rise), .motion(bubble.target, .wobble),
            ])
    }

    @Test func whatHappensToNoInstanceIsIgnored() throws {
        let timer = try app(makeShell(pages: try pages()), "timer")
        let nobody = ItemID(rawValue: 99)
        timer.loaded(nobody)
        timer.report("error", in: nobody)
        timer.resize(nobody, to: CGSize(width: 500, height: 500))
        let context = Context(app: timer.id)
        timer.update(context)
        #expect(context.effects.isEmpty)
        #expect(timer.items.isEmpty)
        #expect(timer.dataURL(of: nobody) == nil)
    }

    @Test func aPageResizesItsBubbleWithinLimits() throws {
        let shell = makeShell(pages: try pages())
        shell.start(AppID("builtin.timer"))
        let bubble = try #require(shell.stage.bubbles.last)
        let timer = try app(shell, "timer")
        timer.resize(bubble.target.item, to: CGSize(width: 500, height: 400))
        shell.tick(at: 1)
        #expect(bubble.size == CGSize(width: 500, height: 400) + BundledWebApp.chrome)

        timer.resize(bubble.target.item, to: CGSize(width: 5, height: 5000))
        #expect(
            timer.appearance(of: bubble.target.item).size == CGSize(
                width: AppSource.minSize.width, height: AppSource.maxSize.height)
                + BundledWebApp.chrome)
    }

    // MARK: Data

    @Test func theirDataIsKeptBesideTheStoreApartFromTheMicroapps() {
        #expect(
            BundledWebApp.root(for: Autosave.defaultURL)
                == Services.folder.appending(path: "builtin", directoryHint: .isDirectory))
        #expect(
            BundledWebApp.root(for: URL(filePath: "/tmp/honu.json")).path()
                == "/tmp/honu.builtin")
        #expect(
            BundledWebApp.root(for: URL(filePath: "/tmp/honu.json"))
                != MakerApp.root(for: URL(filePath: "/tmp/honu.json")))
    }

    @Test func twoInstancesSaveApart() async throws {
        let url = temporaryStoreURL()
        let shell = makeShell(storeURL: url, pages: try pages())
        let timer = try app(shell, "timer")
        shell.start(timer.id)
        shell.start(timer.id)
        let items = timer.items
        try #require(items.count == 2)
        let files = try items.map { try #require(timer.dataURL(of: $0)) }
        #expect(files[0] != files[1])
        let instances = BundledWebApp.root(for: url).appending(
            path: "timer/instances", directoryHint: .isDirectory)
        for file in files {
            #expect(
                file.deletingLastPathComponent().standardizedFileURL
                    == instances.standardizedFileURL)
        }

        for (file, state) in zip(files, ["1", "2"]) {
            let (_, error) = await Bridge(dataURL: file).reply(to: ["op": "save", "state": state])
            #expect(error == nil)
        }
        for (file, state) in zip(files, ["1", "2"]) {
            let (value, _) = await Bridge(dataURL: file).reply(to: ["op": "load"])
            #expect(value as? String == state)
        }
    }

    @Test func instancesComeBackAfterARelaunchWithTheirDataAndSize() async throws {
        let url = temporaryStoreURL()
        let pages = try pages()
        let shell = makeShell(storeURL: url, pages: pages)
        let timer = try app(shell, "timer")
        shell.start(timer.id)
        let item = try #require(timer.items.first)
        timer.resize(item, to: CGSize(width: 400, height: 260))
        let file = try #require(timer.dataURL(of: item))
        _ = await Bridge(dataURL: file).reply(to: ["op": "save", "state": "{\"left\":42}"])
        shell.save()

        let again = makeShell(storeURL: url, pages: pages)
        let restored = try app(again, "timer")
        #expect(restored.items == [item])
        #expect(restored.dataURL(of: item) == file)
        #expect(
            restored.appearance(of: item).size == CGSize(width: 400, height: 260)
                + BundledWebApp.chrome)
        let bubble = try #require(again.stage.bubbles.first)
        #expect(bubble.target == ViewTarget(app: restored.id, item: item))
        let (value, _) = await Bridge(dataURL: file).reply(to: ["op": "load"])
        #expect(value as? String == "{\"left\":42}")

        // New instances get ids after the restored one.
        again.start(restored.id)
        #expect(restored.items.count == 2 && restored.items.last! > item)
    }

    @Test func deletingAnInstanceDeletesItsData() async throws {
        let shell = makeShell(pages: try pages())
        let timer = try app(shell, "timer")
        let bubble = shell.addBubble(
            showing: timer.create(), of: timer, at: CGPoint(x: 600, y: 300), fresh: false)
        let file = try #require(timer.dataURL(of: bubble.target.item))
        _ = await Bridge(dataURL: file).reply(to: ["op": "save", "state": "1"])
        #expect(FileManager.default.fileExists(atPath: file.path()))

        shell.drop(bubble)
        #expect(bubble.isSwallowed)
        #expect(timer.items.count == 1, "deleted before the octopus forgot it")
        shell.tick(at: now() + Bubble.swallowSeconds + Trash.undoSeconds + 1)
        #expect(timer.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path()))
    }

    @Test func loadingDeletesTheFilesOfInstancesNoLongerKept() async throws {
        let url = temporaryStoreURL()
        let pages = try pages()
        let shell = makeShell(storeURL: url, pages: pages)
        let timer = try app(shell, "timer")
        shell.start(timer.id)
        let item = try #require(timer.items.first)
        let kept = try #require(timer.dataURL(of: item))
        _ = await Bridge(dataURL: kept).reply(to: ["op": "save", "state": "1"])
        let stray = timer.instancesURL.appending(path: "\(UUID().uuidString).json")
        try Data("2".utf8).write(to: stray)
        shell.save()

        _ = makeShell(storeURL: url, pages: pages)
        #expect(FileManager.default.fileExists(atPath: kept.path()))
        #expect(!FileManager.default.fileExists(atPath: stray.path()))
    }

    @Test func aPageNoLongerShippedLoadsWithoutItsBubblesAndLeavesItsDataAlone() async throws {
        let url = temporaryStoreURL()
        let pages = try pages()
        let shell = makeShell(storeURL: url, pages: pages)
        let timer = try app(shell, "timer")
        shell.start(timer.id)
        _ = shell.addNote()
        let item = try #require(timer.items.first)
        let file = try #require(timer.dataURL(of: item))
        _ = await Bridge(dataURL: file).reply(to: ["op": "save", "state": "1"])
        shell.save()

        let without = makeShell(storeURL: url, pages: pages.filter { $0.name != "timer" })
        #expect(without.registry.app(timer.id) == nil)
        #expect(without.stage.bubbles.map(\.target.app) == [AppID("notes")])
        #expect(FileManager.default.fileExists(atPath: file.path()))
        #expect(without.snapshot().apps[timer.id.rawValue] == nil)

        // Shipped again once that has been saved, the page is there with
        // nothing open.
        without.save()
        let back = makeShell(storeURL: url, pages: pages)
        #expect(try app(back, "timer").items.isEmpty)
    }

    @Test func eachPageKeepsItsInstancesToItself() throws {
        let url = temporaryStoreURL()
        let pages = try pages()
        let shell = makeShell(storeURL: url, pages: pages)
        shell.start(AppID("builtin.timer"))
        shell.start(AppID("builtin.world-clock"))
        shell.start(AppID("builtin.world-clock"))
        shell.save()

        let again = makeShell(storeURL: url, pages: pages)
        #expect(try app(again, "timer").items.count == 1)
        #expect(try app(again, "world-clock").items.count == 2)
        #expect(again.stage.bubbles.count == 3)
    }

    // MARK: What Honu ships

    /// The folder of the pages Honu ships, in its sources.
    private static let sources = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/Honu/BuiltinApps", directoryHint: .isDirectory)

    @Test func everyPageHonuShipsIsWellNamedAndHasAPage() throws {
        let names =
            (try? FileManager.default.contentsOfDirectory(atPath: Self.sources.path()))?
            .filter { !$0.hasPrefix(".") } ?? []
        for name in names {
            #expect(BuiltinCatalog.isValidName(name), "\(name) breaks the name rule")
            let page = Self.sources.appending(path: "\(name)/index.html")
            #expect(FileManager.default.fileExists(atPath: page.path()), "\(name) has no page")
        }
        #expect(BuiltinCatalog.shipped.map(\.name).sorted() == names.sorted())
    }

    @Test func everyPageHonuShipsSaysWhatItIsCalledAndItsSymbol() {
        for page in BuiltinCatalog.shipped {
            #expect(page.meta.title != nil, "\(page.name) has no title")
            #expect(
                MakerApp.symbol(named: page.meta.symbol) == page.meta.symbol,
                "\(page.name) has no symbol that exists")
        }
    }
}
