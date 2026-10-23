import Foundation
import Testing

@testable import Honu

extension Hit {
    /// Which layer was hit, to compare.
    fileprivate var layer: String {
        switch self {
        case .popup: "popup"
        case .turtle: "turtle"
        case .octopus: "octopus"
        case .bubble: "bubble"
        case .nothing: "nothing"
        }
    }

    fileprivate var bubble: Bubble? {
        if case .bubble(let bubble) = self { bubble } else { nil }
    }
}

/// What the views get from the shell, rather than from the microapps.
@MainActor
struct ShellTests {
    /// A note's bubble in `shell`, at rest at `center`.
    private func note(in shell: Shell, at center: CGPoint) -> Bubble {
        let notes = shell.registry.app(AppID("notes"))!
        return shell.addBubble(showing: notes.create(), of: notes, at: center, fresh: false)
    }

    @Test func whatIsUnderAPointGoesFromTheTopLayerDown() throws {
        let shell = makeShell()
        let empty = CGPoint(x: 600, y: 100)
        #expect(shell.hit(empty).layer == "nothing")
        #expect(!shell.takesClick(at: empty), "kept a click from the apps below")

        let bubble = note(in: shell, at: CGPoint(x: 600, y: 300))
        #expect(shell.hit(bubble.center).bubble === bubble)
        #expect(shell.takesClick(at: bubble.center))

        // The sprites are above the bubbles.
        let turtle = shell.turtle.center
        try #require(shell.turtle.contains(turtle))
        _ = note(in: shell, at: turtle)
        #expect(shell.hit(turtle).layer == "turtle")
        shell.octopus.summon(true, turtle: turtle)
        let octopus = shell.octopus.middle
        _ = note(in: shell, at: octopus)
        #expect(shell.hit(octopus).layer == "octopus")
        #expect(shell.takesClick(at: octopus))
        shell.octopus.summon(false, turtle: turtle)

        // An open menu takes every click, as a native one does.
        shell.clickTurtle(at: turtle)
        for point in [empty, bubble.center, octopus] {
            #expect(shell.hit(point).layer == "popup")
            #expect(shell.takesClick(at: point))
        }
        shell.closePopup()
        #expect(!shell.takesClick(at: empty))
    }

    @Test func aDragTakesEveryClickUntilLetGo() {
        let shell = makeShell()
        let empty = CGPoint(x: 600, y: 100)
        let bubble = note(in: shell, at: CGPoint(x: 600, y: 300))
        shell.dragBubble(bubble, by: CGSize(width: 10, height: 0), pointer: bubble.center)
        #expect(shell.takesEveryClick && shell.takesClick(at: empty))
        shell.endBubbleDrag(pointer: bubble.center)
        #expect(!shell.takesEveryClick && !shell.takesClick(at: empty))

        shell.dragTurtle(by: CGSize(width: 50, height: -50))
        #expect(shell.takesEveryClick)
        shell.endTurtleDrag()
        #expect(!shell.takesEveryClick)
    }

    @Test func aDraggedTurtleStaysWhereItWasLeftAfterARelaunch() {
        let url = temporaryStoreURL()
        let shell = makeShell(storeURL: url)
        let start = shell.turtle.origin
        // Each step of a drag is how far it is from where the drag began.
        shell.dragTurtle(by: CGSize(width: 300, height: -200))
        shell.dragTurtle(by: CGSize(width: 400, height: -300))
        let place = CGPoint(x: start.x + 400, y: start.y - 300)
        #expect(shell.turtle.origin == place)
        shell.endTurtleDrag()
        #expect(makeShell(storeURL: url).turtle.origin == place)

        // The next drag starts where this one ended.
        shell.dragTurtle(by: CGSize(width: 10, height: 0))
        #expect(shell.turtle.origin == CGPoint(x: place.x + 10, y: place.y))
    }

    @Test func aLongPauseMovesNothingFar() {
        let shell = makeShell()
        let bubble = note(in: shell, at: CGPoint(x: 600, y: 400))
        let start = bubble.center
        bubble.velocity = CGPoint(x: 600, y: 0)
        shell.tick(at: 100)
        #expect(bubble.center == start, "moved on the first tick")
        // As when the Mac wakes from sleep an hour later.
        shell.tick(at: 100 + 3600)
        #expect((bubble.center - start).length <= 600.0 / 30 + 1)
    }

    @Test func bubblesShowWhatTheirItemIsDoing() throws {
        let shell = makeShell()
        let web = try #require(shell.registry.app(AppID("web")) as? WebApp)
        shell.start(web.id)
        let bubble = try #require(shell.stage.bubbles.last)
        let item = bubble.target.item
        web.open("en.wikipedia.org", in: item)
        web.startedLoading(item)
        shell.tick(at: 1)
        #expect(bubble.isBusy)
        web.stoppedLoading(item, .finished)
        shell.tick(at: 2)
        #expect(!bubble.isBusy)
        #expect(bubble.motion?.motion == .rise)
    }

    @Test func anOpenPanelTakesTheSizeItsMicroappAsksFor() throws {
        let claude = FakeClaude()
        let shell = makeShell(claude: claude)
        shell.choose(.make)
        let bubble = try #require(shell.stage.bubbles.last)
        let item = bubble.target.item
        shell.maker.microapp(of: item)?.draft = "a clock"
        shell.maker.make(item)
        claude.streams[0].send(
            .text("<!doctype html><html><head><title>Clock</title></head></html>"))
        claude.streams[0].send(.done)
        shell.tick(at: 1)

        shell.maker.resize(item, to: CGSize(width: 500, height: 300))
        shell.tick(at: 2)
        #expect(bubble.panelSize == CGSize(width: 500, height: 300) + MakerApp.chrome)
    }
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
