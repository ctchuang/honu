import Foundation
import Testing

@testable import Honu

/// Uninstalling a microapp through the octopus, and taking it back.
@MainActor
struct UninstallTests {
    private let claude = FakeClaude()

    /// A shell with a microapp Claude has made, called `title`, shown in one
    /// bubble, returning the shell and the microapp.
    private func shellWithMicroapp(_ title: String = "Clock") throws -> (Shell, GeneratedApp) {
        let shell = makeShell(claude: claude)
        shell.choose(.make)
        let item = try #require(shell.maker.items.last)
        let microapp = try #require(shell.maker.microapp(of: item))
        microapp.draft = "a \(title)"
        shell.maker.make(item)
        claude.streams.last!.send(
            .text("<!doctype html><html><head><title>\(title)</title></head></html>"))
        claude.streams.last!.send(.done)
        shell.tick(at: 1)
        return (shell, microapp)
    }

    /// The bubbles showing an instance of `microapp`.
    private func bubbles(of microapp: GeneratedApp, in shell: Shell) -> [Bubble] {
        shell.stage.bubbles.filter { shell.maker.microapp(of: $0.target.item) === microapp }
    }

    /// Whether the launcher has a tile for the microapp in the folder `name`.
    private func hasTile(_ name: String, in shell: Shell) -> Bool {
        shell.launcherTiles.map(\.kind).contains(.installed(name))
    }

    @Test func anUninstalledMicroappCanBeTakenBackWithItsBubbles() throws {
        let (shell, microapp) = try shellWithMicroapp()
        let name = microapp.folder.name
        shell.launch(name)
        let shown = bubbles(of: microapp, in: shell)
        #expect(shown.count == 2)

        shell.uninstall(name, at: 10)
        #expect(!hasTile(name, in: shell))
        #expect(shown.allSatisfy { $0.isSwallowed })
        #expect(shell.octopus.canUndo)

        shell.undoDelete()
        #expect(hasTile(name, in: shell))
        #expect(shown.allSatisfy { !$0.isSwallowed })
        #expect(shell.maker.items.count == 2)
    }

    @Test func anUninstalledMicroappIsDeletedOnceTheOctopusForgetsIt() throws {
        let (shell, microapp) = try shellWithMicroapp()
        let name = microapp.folder.name
        shell.uninstall(name, at: 10)
        shell.tick(at: 11)
        #expect(FileManager.default.fileExists(atPath: microapp.folder.url.path()))

        shell.tick(at: 10 + Bubble.swallowSeconds + Octopus.undoSeconds + 1)
        #expect(shell.maker.apps.isEmpty && shell.maker.items.isEmpty)
        #expect(bubbles(of: microapp, in: shell).isEmpty)
        #expect(shell.stage.bubbles.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: microapp.folder.url.path()))
    }

    @Test func droppingATileOnTheOctopusUninstallsItsMicroapp() throws {
        let (shell, microapp) = try shellWithMicroapp()
        let name = microapp.folder.name
        let tile = try #require(shell.launcherTiles.first { $0.kind == .installed(name) })
        let start = CGPoint(x: 200, y: 600)
        shell.clickTurtle(at: shell.turtle.center)

        #expect(shell.dragTile(tile, from: start, to: CGPoint(x: 210, y: 600)))
        #expect(!shell.octopus.isSummoned, "came up for a nudge")
        #expect(shell.dragTile(tile, from: start, to: CGPoint(x: 600, y: 600)))
        #expect(shell.octopus.isSummoned && shell.octopus.offer == .microapp)
        #expect(shell.dragTile(tile, from: start, to: shell.octopus.middle))
        #expect(shell.octopus.isEager)

        shell.endTileDrag(at: shell.octopus.middle, time: 10)
        #expect(shell.tileDrag == nil && shell.popup == nil)
        // The tile goes down the octopus's mouth, then is gone.
        let swallowed = try #require(shell.swallowedTile)
        #expect(swallowed.tile == tile && swallowed.flight.to == shell.octopus.mouth)
        #expect(swallowed.flight.after(0).scale == Shell.eagerTileScale)
        #expect(swallowed.flight.after(1).scale == 0)
        shell.tick(at: 10 + Bubble.swallowSeconds)
        #expect(shell.swallowedTile == nil)
        #expect(!hasTile(name, in: shell))
        #expect(shell.octopus.canUndo)
        #expect(bubbles(of: microapp, in: shell).allSatisfy { $0.isSwallowed })
    }

    @Test func uninstallingFromATilesMenuSwallowsTheTile() throws {
        let (shell, microapp) = try shellWithMicroapp()
        let name = microapp.folder.name
        let tile = try #require(shell.launcherTiles.first { $0.kind == .installed(name) })
        shell.clickTurtle(at: shell.turtle.center)
        let center = CGPoint(x: 200, y: 600)

        shell.uninstall(tile, from: center, at: 10)
        #expect(shell.popup == nil)
        let swallowed = try #require(shell.swallowedTile)
        #expect(swallowed.tile == tile && swallowed.flight.from == center)
        #expect(swallowed.flight.after(0).scale == 1)
        #expect(!hasTile(name, in: shell))
        #expect(bubbles(of: microapp, in: shell).allSatisfy { $0.isSwallowed })

        shell.undoDelete()
        #expect(hasTile(name, in: shell))
    }

    @Test func modifyingLaunchesAnInstanceThatTakesTheFocusAndTypeAhead() throws {
        let (shell, microapp) = try shellWithMicroapp()
        shell.clickTurtle(at: shell.turtle.center)
        shell.modify(microapp.folder.name)
        #expect(shell.popup == nil)
        let shown = bubbles(of: microapp, in: shell)
        #expect(shown.count == 2)
        let state = try #require(shown.last?.viewState as? FocusRequestState)
        #expect(state.focusPending)
        #expect(shell.type("make it blue"))
        #expect(microapp.draft == "make it blue")

        // A plain launch leaves the focus alone.
        shell.launch(microapp.folder.name)
        let plain = try #require(bubbles(of: microapp, in: shell).last?.viewState)
        #expect((plain as? FocusRequestState)?.focusPending == false)
    }

    @Test func aTileDroppedElsewhereGoesBack() throws {
        let (shell, microapp) = try shellWithMicroapp()
        let name = microapp.folder.name
        let tile = try #require(shell.launcherTiles.first { $0.kind == .installed(name) })
        shell.clickTurtle(at: shell.turtle.center)
        #expect(shell.dragTile(tile, from: CGPoint(x: 200, y: 600), to: CGPoint(x: 600, y: 300)))
        shell.endTileDrag(at: CGPoint(x: 600, y: 300))
        #expect(shell.tileDrag == nil && !shell.octopus.isSummoned)
        #expect(hasTile(name, in: shell))
        #expect(shell.popup != nil)
    }

    @Test func builtInTilesDoNotDrag() throws {
        let shell = makeShell()
        for tile in shell.launcherTiles {
            #expect(!shell.dragTile(tile, from: .zero, to: CGPoint(x: 500, y: 500)))
        }
        #expect(shell.tileDrag == nil && !shell.octopus.isSummoned)
    }

    @Test func uninstallingLeavesOtherMicroappsAlone() throws {
        let (shell, clock) = try shellWithMicroapp("Clock")
        shell.choose(.make)
        let item = try #require(shell.maker.items.last)
        let timer = try #require(shell.maker.microapp(of: item))
        timer.draft = "a timer"
        shell.maker.make(item)
        claude.streams.last!.send(
            .text("<!doctype html><html><head><title>Timer</title></head></html>"))
        claude.streams.last!.send(.done)
        shell.tick(at: 2)

        shell.uninstall(clock.folder.name, at: 10)
        shell.tick(at: 10 + Bubble.swallowSeconds + Octopus.undoSeconds + 1)
        #expect(shell.maker.library.map { $0 === timer } == [true])
        #expect(bubbles(of: timer, in: shell).count == 1)
        #expect(bubbles(of: timer, in: shell).allSatisfy { !$0.isSwallowed })
    }
}
