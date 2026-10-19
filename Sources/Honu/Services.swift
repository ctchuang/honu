import Foundation

/// What the microapps share: the client that asks Claude.
@MainActor
final class Services {
    let claude: any ClaudeClient

    init(claude: any ClaudeClient) {
        self.claude = claude
    }

    /// The services Honu runs with: Claude Code.
    static func live() -> Services {
        Services(claude: ClaudeCode())
    }
}
