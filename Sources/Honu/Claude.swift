import Foundation

// Asking Claude a question and streaming the answer back. Microapps ask
// through a `ClaudeClient`: `ClaudeCode`, or a stand-in in tests.
// `ClaudeCode` runs the Claude Code CLI headless (`claude -p`), which signs
// in with the user's own Claude account, so Honu needs no API key.

/// What an answer stream reports, in order: any number of `text` pieces,
/// then `done` or `failed`.
enum ClaudeEvent: Equatable, Sendable {
    case text(String)
    case done
    case failed(String)

    /// Whether it ends the answer.
    var isFinal: Bool {
        if case .text = self { return false }
        return true
    }
}

/// What to ask Claude, and how.
struct ClaudeRequest: Equatable, Sendable {
    /// How hard Claude thinks before answering.
    enum Effort: String, Sendable {
        case low, medium, high
    }

    /// What is asked, sent on standard input.
    var prompt: String
    /// What Claude is told about its task.
    var systemPrompt: String
    var effort = Effort.low
}

/// Asks Claude questions.
@MainActor
protocol ClaudeClient: AnyObject {
    /// Starts streaming Claude's answer to `request`. Take the events from
    /// the returned stream as they arrive.
    func ask(_ request: ClaudeRequest) -> AnswerStream
}

/// The events of one answer, handed from whatever receives them to the
/// main actor, which takes them many times a second.
final class AnswerStream: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [ClaudeEvent] = []
    private var isClosed = false
    private var task: Task<Void, Never>?
    private var cancelled = false

    /// Whether the answer is no longer wanted.
    var isCancelled: Bool { lock.withLock { cancelled } }

    /// Adds an event for the next `take`.
    func send(_ event: ClaudeEvent) {
        lock.withLock { events.append(event) }
    }

    /// Notes that no more events will come, as when the sender goes away.
    func close() {
        lock.withLock { isClosed = true }
    }

    /// The events received since the last call, and whether the stream has
    /// closed since, so nothing more will come.
    func take() -> (events: [ClaudeEvent], isClosed: Bool) {
        lock.withLock {
            defer { events.removeAll() }
            return (events, isClosed)
        }
    }

    /// Runs `work`, which feeds the stream, until it finishes or the stream
    /// is cancelled; the stream closes after it either way.
    func run(_ work: @escaping @Sendable (AnswerStream) async -> Void) {
        let task = Task.detached { [self] in
            await work(self)
            close()
        }
        lock.withLock { self.task = task }
    }

    /// Stops receiving the answer, as when its chat is deleted.
    func cancel() {
        lock.withLock {
            cancelled = true
            return task
        }?.cancel()
    }
}

/// Claude Code's CLI, run once per question.
/// Only asking runs on the main actor (`ClaudeClient`); running `claude` and
/// reading its answer happen off it.
final class ClaudeCode {
    private static let model = "claude-opus-5-5"
    /// Where `claude` is usually installed, for when Honu runs without a
    /// shell's `PATH`, as an app opened from the Finder does.
    private static let installFolders = [
        "~/.local/bin", "~/.claude/local", "/opt/homebrew/bin", "/usr/local/bin",
    ]

    /// Where `claude` runs: Honu's own folder, away from any project, so no
    /// project's CLAUDE.md comes along.
    static let workingDirectory = Services.folder

    /// The arguments for answering `request`, whose prompt is read from
    /// standard input: streamed as JSON lines, with no tools, and nothing
    /// saved to resume.
    static func arguments(for request: ClaudeRequest) -> [String] {
        [
            "-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
            "--model", model, "--effort", request.effort.rawValue, "--tools", "",
            "--strict-mcp-config", "--no-session-persistence",
            "--system-prompt", request.systemPrompt,
        ]
    }

    /// The `claude` executable: the first in `PATH`, or else in a folder it
    /// is usually installed in.
    static func executable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)
    ) -> URL? {
        let path = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        let home = environment["HOME"] ?? NSHomeDirectory()
        let folders =
            path
            + installFolders.map {
                $0.hasPrefix("~/") ? home + $0.dropFirst() : $0
            }
        return folders.map { $0 + "/claude" }.first(where: isExecutable).map {
            URL(filePath: $0)
        }
    }

    /// The environment `claude` runs in: Honu's own, without an API key, so
    /// Claude Code always signs in with the user's Claude account.
    static func environment(_ environment: [String: String]) -> [String: String] {
        environment.filter { $0.key != "ANTHROPIC_API_KEY" }
    }

    /// Runs `executable` (`claude`) in `directory` on `request` and feeds its
    /// answer into `stream` until it ends, stopping it if the stream is
    /// cancelled first.
    static func receive(
        _ request: ClaudeRequest, from executable: URL, in directory: URL = workingDirectory,
        into stream: AnswerStream
    ) async {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments(for: request)
        process.environment = environment(ProcessInfo.processInfo.environment)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        process.currentDirectoryURL = directory
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        // Set before it runs, so its exit cannot be missed; waited for
        // without holding a thread.
        let exit = AsyncStream<Int32> { exited in
            process.terminationHandler = {
                exited.yield($0.terminationStatus)
                exited.finish()
            }
        }
        do {
            try process.run()
        } catch {
            stream.send(.failed("Couldn't start Claude Code: \(error.localizedDescription)"))
            return
        }
        try? input.fileHandleForWriting.write(contentsOf: Data(request.prompt.utf8))
        try? input.fileHandleForWriting.close()

        await withTaskCancellationHandler {
            // Standard error is read alongside the answer: left unread, a full
            // pipe would stop `claude` mid-answer, and the answer would never end.
            async let errorOutput = readToEnd(errors.fileHandleForReading)
            do {
                for try await line in output.fileHandleForReading.bytes.lines {
                    if Task.isCancelled { return }
                    if let event = EventParser.parse(line: line) {
                        stream.send(event)
                        if event.isFinal { return }
                    }
                }
            } catch {
                // The output broke off; report it below like any early end.
            }
            if Task.isCancelled { return }
            var status: Int32 = -1
            for await code in exit {
                status = code
            }
            let detail = String(decoding: await errorOutput, as: UTF8.self)
            stream.send(EventParser.finish(status: status, errors: detail))
        } onCancel: {
            process.terminate()
        }
    }

    /// Everything `handle` gives until it ends, read on a thread of its own,
    /// apart from the one reading the answer.
    private static func readToEnd(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { read in
            DispatchQueue.global().async {
                read.resume(returning: handle.readDataToEndOfFile())
            }
        }
    }
}

extension ClaudeCode: ClaudeClient {
    func ask(_ request: ClaudeRequest) -> AnswerStream {
        let stream = AnswerStream()
        let executable = Self.executable()
        stream.run { stream in
            guard let executable else {
                stream.send(
                    .failed(
                        "Claude Code isn't installed. Install it from claude.com/claude-code, "
                            + "then run claude once in Terminal to sign in."))
                return
            }
            await Self.receive(request, from: executable, into: stream)
        }
        return stream
    }
}

/// Turns the JSON lines `claude -p --output-format stream-json` writes into
/// events.
struct EventParser {
    /// Reads one line. Only the answer's text and how it ended matter; the
    /// session's setup, status, and rate limits are ignored.
    static func parse(line: String) -> ClaudeEvent? {
        guard
            let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
            let message = json as? [String: Any]
        else { return nil }
        switch message["type"] as? String {
        case "stream_event":
            return parse(apiEvent: message["event"] as? [String: Any] ?? [:])
        case "result":
            if message["is_error"] as? Bool == false {
                return .done
            }
            let errors = (message["errors"] as? [String])?.joined(separator: " ")
            let result = message["result"] as? String
            let detail = [result, errors].compactMap { $0 }.first { !$0.isEmpty }
            return .failed(detail ?? "Claude Code reported an error.")
        default:
            return nil
        }
    }

    /// Reads one event of the Messages API stream that Claude Code passes on.
    private static func parse(apiEvent event: [String: Any]) -> ClaudeEvent? {
        let delta = event["delta"] as? [String: Any]
        switch event["type"] as? String {
        case "content_block_delta" where delta?["type"] as? String == "text_delta":
            return (delta?["text"] as? String).map(ClaudeEvent.text)
        case "message_delta":
            switch delta?["stop_reason"] as? String {
            case "refusal": return .failed("Claude declined to answer this.")
            case "max_tokens": return .failed("The answer was cut off because it got too long.")
            default: return nil
            }
        default:
            return nil
        }
    }

    /// Called when `claude` exits without reporting a result, with its exit
    /// status and what it wrote to standard error.
    static func finish(status: Int32, errors: String) -> ClaudeEvent {
        let detail = errors.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty {
            return .failed(detail)
        }
        return .failed(
            "Claude Code stopped before the answer was finished (exit status \(status)).")
    }
}
