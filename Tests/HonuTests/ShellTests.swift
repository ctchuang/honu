import Foundation
import Testing

@testable import Honu

/// What the views get from the shell, rather than from the microapps.
@MainActor
struct ShellTests {
    private func shell() -> Shell {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "honu-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "state.json")
        return Shell(size: CGSize(width: 1200, height: 800), storeURL: url)
    }

    @Test func theMenuListsEveryMicroappInOrder() {
        #expect(shell().menuChoices.map(\.label) == ["Add Note", "Ask AI", "Open Web Page"])
    }

    @Test func aBubbleShowsWhatItsMicroappSays() throws {
        let shell = shell()
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
