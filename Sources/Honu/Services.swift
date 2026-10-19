import Foundation

/// What the microapps share: the key for asking Claude, and the client that asks.
@MainActor
final class Services {
    let apiKey: ApiKey
    let claude: any ClaudeClient

    init(apiKey: ApiKey, claude: any ClaudeClient) {
        self.apiKey = apiKey
        self.claude = claude
    }

    /// The services Honu runs with: the key from the environment, and the Messages API.
    static func live() -> Services {
        Services(apiKey: ApiKey(ApiKey.fromEnvironment()), claude: MessagesAPI())
    }
}

/// The key for asking Claude, once known. A key pasted into an Ask bubble is
/// kept only until Honu quits, so it never lands in a file.
@Observable
@MainActor
final class ApiKey {
    var value: String?

    init(_ value: String?) {
        self.value = value
    }

    /// The key in `ANTHROPIC_API_KEY`, which may also be set in a `.env` file
    /// in or above the working directory.
    nonisolated static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        directory: URL = URL(filePath: FileManager.default.currentDirectoryPath)
    ) -> String? {
        let key = environment["ANTHROPIC_API_KEY"] ?? dotEnv(above: directory)["ANTHROPIC_API_KEY"]
        guard let key = key?.trimmingCharacters(in: .whitespaces), !key.isEmpty else { return nil }
        return key
    }

    /// The variables in the nearest `.env` file in or above `directory`.
    nonisolated static func dotEnv(above directory: URL) -> [String: String] {
        var directory = directory.standardizedFileURL
        while true {
            if let text = try? String(
                contentsOf: directory.appending(path: ".env"), encoding: .utf8)
            {
                return parseDotEnv(text)
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path() == directory.path() { return [:] }
            directory = parent
        }
    }

    /// Reads `NAME=value` lines, skipping blank lines and `#` comments, and
    /// taking quotes off quoted values.
    nonisolated static func parseDotEnv(_ text: String) -> [String: String] {
        var variables: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            var line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst("export ".count)) }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let name = line[..<equals].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let quote = value.first, quote == "\"" || quote == "'",
                value.last == quote
            {
                value = String(value.dropFirst().dropLast())
            }
            if !name.isEmpty {
                variables[name] = value
            }
        }
        return variables
    }
}
