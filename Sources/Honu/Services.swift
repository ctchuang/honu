import Foundation

/// What the microapps share: the client that asks Claude.
@MainActor
final class Services {
    let claude: any ClaudeClient

    /// Honu's own folder, `~/.honu/`: where it saves and where Claude Code runs.
    nonisolated static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".honu", directoryHint: .isDirectory)

    init(claude: any ClaudeClient) {
        self.claude = claude
    }

    /// The services Honu runs with: Claude Code.
    static func live() -> Services {
        Services(claude: ClaudeCode())
    }
}
