import Foundation
import Testing

@testable import Honu

/// The Reef: the launcher's folder of built-in microapps.
@MainActor
struct LauncherFolderTests {
    /// A shell with its launcher open, where the turtle is.
    private func shellWithLauncher() -> (Shell, CGPoint) {
        let shell = makeShell()
        let point = shell.turtle.center
        shell.clickTurtle(at: point)
        return (shell, point)
    }

    @Test func theReefsTileShowsTheSymbolsOfWhatItHolds() throws {
        let shell = makeShell()
        let reef = try #require(shell.launcherTiles.first)
        #expect(reef.kind == .folder(.builtIn))
        #expect(reef.label == LauncherFolder.builtIn.label)
        #expect(reef.preview == shell.launcherTiles(in: .builtIn).map(\.symbol))
        #expect(reef.preview == ["note.text"])
        #expect(reef.preview.count <= LauncherView.previewCount)
    }

    @Test func choosingTheReefOpensItInPlaceOfTheTopLevel() {
        let (shell, point) = shellWithLauncher()
        shell.choose(.folder(.builtIn))
        #expect(shell.popup == .launcher(at: point, folder: .builtIn))
        #expect(shell.openFolder == .builtIn)
        #expect(shell.launcherTiles == shell.launcherTiles(in: .builtIn))
        #expect(shell.stage.bubbles.isEmpty, "a folder started something")
    }

    @Test func choosingATileInTheReefStartsItAndClosesTheLauncher() throws {
        let (shell, _) = shellWithLauncher()
        shell.choose(.folder(.builtIn))
        let note = try #require(shell.launcherTiles.first)
        shell.choose(note.kind)
        #expect(shell.popup == nil)
        #expect(shell.openFolder == nil)
        #expect(shell.stage.bubbles.last?.target.app == AppID("notes"))
    }

    @Test func goingBackFromTheReefShowsTheTopLevelWhereItWas() {
        let (shell, point) = shellWithLauncher()
        #expect(!shell.closeFolder(), "went back from the top level")
        #expect(shell.popup == .launcher(at: point))

        shell.open(.builtIn)
        #expect(shell.closeFolder())
        #expect(shell.popup == .launcher(at: point))
        #expect(shell.launcherTiles == shell.launcherTiles(in: nil))
    }

    @Test func theLauncherOpensAtItsTopLevelEveryTime() {
        let (shell, point) = shellWithLauncher()
        shell.open(.builtIn)
        shell.closePopup()
        #expect(shell.openFolder == nil)
        shell.clickTurtle(at: point)
        #expect(shell.popup == .launcher(at: point))

        // Clicking the turtle again while in the folder starts over too.
        shell.open(.builtIn)
        shell.clickTurtle(at: point)
        #expect(shell.openFolder == nil)
    }

    @Test func aFolderOpensOnlyInAnOpenLauncher() {
        let shell = makeShell()
        shell.open(.builtIn)
        #expect(shell.popup == nil)
        shell.choose(.folder(.builtIn))
        #expect(shell.popup == nil)

        shell.rightClickTurtle(at: shell.turtle.center)
        shell.open(.builtIn)
        #expect(shell.popup == .system(at: shell.turtle.center))
        #expect(!shell.closeFolder())
        #expect(shell.openFolder == nil)
    }

    @Test func rightClickingTheTurtleInTheReefOpensTheSystemMenu() {
        let (shell, point) = shellWithLauncher()
        shell.open(.builtIn)
        shell.rightClickTurtle(at: point)
        #expect(shell.popup == .system(at: point))
        #expect(shell.openFolder == nil)
    }

    @Test func theLauncherIsSizedForTheReefsTilesAndHeader() throws {
        let (shell, point) = shellWithLauncher()
        let top = try #require(shell.launcherFrame)
        #expect(top.size == LauncherView.size(for: shell.launcherTiles(in: nil).count))

        shell.open(.builtIn)
        let reef = try #require(shell.launcherFrame)
        let count = shell.launcherTiles(in: .builtIn).count
        #expect(reef.size == LauncherView.size(for: count, header: true))
        #expect(reef.origin == menuCorner(of: reef.size, at: point, in: shell.stage.size))
    }

    @Test func theHeaderAddsItsHeightAndNoWidth() {
        for count in [1, 3, 4, 9, 40] {
            let plain = LauncherView.size(for: count)
            let header = LauncherView.size(for: count, header: true)
            #expect(header.width == plain.width)
            #expect(header.height == plain.height + LauncherView.headerHeight)
        }
    }

    @Test func theReefStaysOnScreen() throws {
        let shell = makeShell()
        let screen = CGRect(origin: .zero, size: shell.stage.size)
        for corner in [
            CGPoint(x: 1190, y: 790), CGPoint(x: 1190, y: 10), CGPoint(x: 10, y: 790),
            CGPoint(x: 10, y: 10),
        ] {
            shell.clickTurtle(at: corner)
            shell.open(.builtIn)
            let frame = try #require(shell.launcherFrame)
            #expect(screen.contains(frame), "off screen when opened at \(corner)")
        }
    }

    @Test func theReefDoesNotDragButWobbles() throws {
        let (shell, _) = shellWithLauncher()
        let reef = try #require(shell.launcherTiles.first { $0.kind == .folder(.builtIn) })
        #expect(!shell.dragTile(reef, from: .zero, to: CGPoint(x: 500, y: 500)))
        #expect(shell.tileDrag == nil && !shell.octopus.isSummoned)

        shell.open(.builtIn)
        for tile in shell.launcherTiles {
            #expect(!shell.dragTile(tile, from: .zero, to: CGPoint(x: 500, y: 500)))
        }
        #expect(shell.tileDrag == nil && !shell.octopus.isSummoned)
    }

    @Test func uninstallingTheReefDoesNothing() throws {
        let (shell, _) = shellWithLauncher()
        let reef = try #require(shell.launcherTiles.first)
        shell.uninstall(reef, from: CGPoint(x: 100, y: 100))
        #expect(shell.swallowedTile == nil)
        #expect(shell.popup != nil)
        #expect(shell.launcherTiles.first == reef)
    }

    @Test func escapeLeavesTheReefThenClosesTheLauncher() {
        let (shell, point) = shellWithLauncher()
        let router = InputRouter(shell: shell)
        shell.open(.builtIn)
        #expect(router.handle(.escape, typing: false))
        #expect(shell.popup == .launcher(at: point))
        #expect(router.handle(.escape, typing: false))
        #expect(shell.popup == nil)
        #expect(!router.handle(.escape, typing: false))
    }

    @Test func rightClickingTheReefGoesOnToItsTiles() throws {
        let (shell, point) = shellWithLauncher()
        let router = InputRouter(shell: shell)
        shell.open(.builtIn)
        let frame = try #require(shell.launcherFrame)
        #expect(
            !router.handle(.rightPress(at: CGPoint(x: frame.midX, y: frame.midY)), typing: false))
        #expect(shell.popup == .launcher(at: point, folder: .builtIn))

        // Outside it, a right click closes the launcher, folder and all.
        let outside = CGPoint(x: frame.maxX + 300, y: frame.minY)
        try #require(!frame.contains(outside) && !shell.turtle.contains(outside))
        #expect(router.handle(.rightPress(at: outside), typing: false))
        #expect(shell.popup == nil)
    }

    @Test func theReefTakesEveryClickAsTheLauncherDoes() {
        let (shell, _) = shellWithLauncher()
        shell.open(.builtIn)
        #expect(shell.takesEveryClick)
        #expect(shell.takesClick(at: CGPoint(x: 900, y: 100)))
    }

    @Test func typingInTheReefIsNotTypeAhead() throws {
        let (shell, _) = shellWithLauncher()
        shell.choose(.folder(.builtIn))
        shell.choose(.stock(AppID("notes")))
        let bubble = try #require(shell.stage.bubbles.last)
        #expect(
            InputRouter(shell: shell).handle(
                .key(text: "hi", unmodified: "hi", command: false, control: false), typing: false))
        #expect(shell.notes.notes[bubble.target.item] == "hi", "a note from the Reef took no text")
    }
}
