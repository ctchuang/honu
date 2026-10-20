import Foundation
import Testing

@testable import Honu

/// What the views get from the shell, rather than from the microapps.
@MainActor
struct ShellTests {
    @Test func everyBubbleKeepsItsOwnUndoHistory() {
        let shell = makeShell()
        let target = ViewTarget(app: AppID("notes"), item: ItemID(rawValue: 1))
        let first = shell.stage.add(
            target: target, center: CGPoint(x: 400, y: 300), appearance: Appearance(),
            viewState: nil)
        let second = shell.stage.add(
            target: target, center: CGPoint(x: 700, y: 300), appearance: Appearance(),
            viewState: nil)
        let history = shell.undoManager(for: first)
        #expect(shell.undoManager(for: first) === history)
        #expect(shell.undoManager(for: second) !== history)
    }

    @Test func theLauncherListsTheBuiltInMicroappsButAskAIThenPlus() {
        let tiles = makeShell().launcherTiles
        #expect(tiles.map(\.kind) == [.stock(AppID("notes")), .stock(AppID("web")), .make])
        #expect(tiles.map(\.label) == ["Note", "Web Page", "New Microapp"])
        #expect(tiles.last?.symbol == "plus")
    }

    @Test func choosingATileStartsAnItemAndClosesTheLauncher() throws {
        let shell = makeShell()
        shell.clickTurtle(at: shell.turtle.center)
        shell.choose(.make)
        #expect(shell.popup == nil)
        let bubble = try #require(shell.stage.bubbles.last)
        #expect(bubble.target.app == shell.maker.id)
        #expect(shell.maker.items == [bubble.target.item])

        shell.choose(.stock(AppID("notes")))
        #expect(shell.stage.bubbles.last?.target.app == AppID("notes"))
    }

    @Test func aMenuStaysOnScreen() {
        let screen = CGSize(width: 1200, height: 800)
        let size = CGSize(width: 190, height: 120)
        #expect(
            menuCorner(of: size, at: CGPoint(x: 100, y: 200), in: screen)
                == CGPoint(x: 100, y: 200))
        let corner = menuCorner(of: size, at: CGPoint(x: 1190, y: 790), in: screen)
        #expect(corner.x + size.width < screen.width)
        #expect(corner.y + size.height < screen.height)
    }

    @Test func aMicroappGetsATileOnceMadeWhichLaunchesItAgain() throws {
        let claude = FakeClaude()
        let shell = makeShell(claude: claude)
        shell.choose(.make)
        let item = try #require(shell.maker.items.first)
        let microapp = try #require(shell.maker.microapp(of: item))
        microapp.draft = "a clock"
        shell.maker.make(item)
        shell.tick(at: 1)
        #expect(shell.launcherTiles.count == 3, "a tile before the page was written")

        claude.streams[0].send(
            .text(
                """
                <!doctype html><html><head><title>Clock</title>
                <meta name="honu-symbol" content="clock"></head><body></body></html>
                """))
        claude.streams[0].send(.done)
        shell.tick(at: 2)
        let tiles = shell.launcherTiles
        #expect(tiles.map(\.label) == ["Note", "Web Page", "Clock", "New Microapp"])
        #expect(
            tiles[2]
                == LauncherTile(
                    kind: .installed(microapp.folder.name), label: "Clock", symbol: "clock"))

        shell.choose(tiles[2].kind)
        #expect(shell.maker.items.count == 2)
        let bubble = try #require(shell.stage.bubbles.last)
        #expect(shell.maker.microapp(of: bubble.target.item) === microapp)
        #expect(shell.title(of: bubble) == "Clock")
    }

    @Test func theLauncherGrowsWithItsTilesAndScrollsPastAFewRows() {
        let three = LauncherView.size(for: 3)
        let four = LauncherView.size(for: 4)
        #expect(four.width > three.width)
        #expect(four.height == three.height)
        #expect(LauncherView.size(for: 9).width == four.width)
        #expect(LauncherView.size(for: 9).height > four.height)
        #expect(LauncherView.size(for: 40) == LauncherView.size(for: 12))
    }

    @Test func aBubbleShowsWhatItsMicroappSays() throws {
        let shell = makeShell()
        shell.start(AppID("notes"))
        let bubble = try #require(shell.stage.bubbles.last)
        #expect(shell.title(of: bubble) == NotesApp.emptyLabel)
        #expect(shell.appearance(of: bubble).closedSide == 120)
        #expect(shell.content(of: bubble) != nil)

        shell.toggle(bubble)
        let opened = bubble.isOpen
        shell.toggle(bubble)
        #expect(bubble.isOpen != opened)
    }
}
