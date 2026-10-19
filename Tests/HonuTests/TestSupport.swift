import Foundation

@testable import Honu

/// A folder of its own for a test, which does not exist yet.
func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "honu-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
}

/// A file of its own for a test to save to, which does not exist yet.
func temporaryStoreURL() -> URL {
    temporaryDirectory().appending(path: "state.json")
}

/// A shell on a screen of `size`, saving to `storeURL` (a store of its own
/// unless given one), whose microapps ask `claude`, so tests never run the
/// real Claude Code.
@MainActor
func makeShell(
    size: CGSize = CGSize(width: 1200, height: 800), storeURL: URL = temporaryStoreURL(),
    claude: FakeClaude = FakeClaude()
) -> Shell {
    Shell(size: size, storeURL: storeURL, services: Services(claude: claude))
}
