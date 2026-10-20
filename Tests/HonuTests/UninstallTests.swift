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
