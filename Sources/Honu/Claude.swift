import Foundation

// Asking Claude a question and streaming the answer back. Microapps ask
// through a `ClaudeClient`: `MessagesAPI`, or a stand-in in tests. There is
// no official Swift SDK, so `MessagesAPI` is raw HTTP over URLSession,
// parsing the server-sent events itself.

/// What an answer stream reports, in order: any number of `text` pieces,
/// then `done`, `failed`, or `keyRejected`.
enum ClaudeEvent: Equatable, Sendable {
    case text(String)
    case done
    case failed(String)
    /// The API key was refused (HTTP 401), with the API's explanation.
    case keyRejected(String)

    /// Whether it ends the answer.
    var isFinal: Bool {
        if case .text = self { return false }
        return true
    }
}

/// Asks Claude questions.
@MainActor
protocol ClaudeClient: AnyObject {
    /// Starts streaming Claude's answer to `question`. Take the events from
    /// the returned stream as they arrive.
    func ask(apiKey: String, question: String) -> AnswerStream
}

/// The events of one answer, handed from whatever receives them to the
/// main actor, which takes them many times a second.
final class AnswerStream: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [ClaudeEvent] = []
    private var isClosed = false
    private var task: Task<Void, Never>?

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
        lock.withLock { task }?.cancel()
    }
}

/// The Messages API.
@MainActor
final class MessagesAPI: ClaudeClient {
    private static let url = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-opus-5-5"
    /// Lets a refused request retry on the fallback model Anthropic
    /// recommends for the refusal's category, inside the same call.
    private static let fallbackBeta = "server-side-fallback-2026-07-01"
    private static let systemPrompt = """
        You answer questions inside a small floating panel on the user's desktop. \
        Keep answers short and to the point. Write plain text without Markdown, \
        since the panel shows the raw text.
        """

    func ask(apiKey: String, question: String) -> AnswerStream {
        let stream = AnswerStream()
        let request = Self.request(apiKey: apiKey, question: question)
        stream.run { stream in
            await Self.receive(request, into: stream)
        }
        return stream
    }

    static func request(apiKey: String, question: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 64000,
            "stream": true,
            "system": systemPrompt,
            // Quick questions don't need deep thinking, and a fast first word matters here.
            "output_config": ["effort": "low"],
            "fallbacks": "default",
            "messages": [["role": "user", "content": question]],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Sends `request` and feeds the answer into `stream` until it ends.
    nonisolated private static func receive(_ request: URLRequest, into stream: AnswerStream)
        async
    {
        var parser = EventParser()
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
                parser.httpError = status
            }
            var line = Data()
            for try await byte in bytes {
                line.append(byte)
                guard byte == UInt8(ascii: "\n") else { continue }
                if send(parser.feed(line), to: stream) { return }
                line.removeAll(keepingCapacity: true)
            }
            _ = send(parser.feed(line) + parser.finish(), to: stream)
        } catch is CancellationError {
            // Nobody wants the answer anymore.
        } catch let error as URLError where error.code == .cancelled {
            // Likewise.
        } catch {
            stream.send(.failed(error.localizedDescription))
        }
    }

    /// Sends `events` down `stream`, stopping at the end of the answer.
    /// Returns whether the answer ended.
    nonisolated private static func send(_ events: [ClaudeEvent], to stream: AnswerStream) -> Bool {
        for event in events {
            stream.send(event)
            if event.isFinal { return true }
        }
        return false
    }
}

/// Turns the raw bytes of a response into events.
struct EventParser {
    /// Bytes of the line still being received.
    private var pending = Data()
    /// The status of an unsuccessful response, whose body is an error object
    /// rather than an event stream.
    var httpError: Int?
    /// The whole body of an unsuccessful response.
    private var errorBody = Data()

    mutating func feed(_ chunk: Data) -> [ClaudeEvent] {
        if httpError != nil {
            errorBody.append(chunk)
            return []
        }
        pending.append(chunk)
        var events: [ClaudeEvent] = []
        // Split on whole lines only, so multi-byte characters never break apart.
        while let end = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let line = pending[pending.startIndex...end]
            pending.removeSubrange(pending.startIndex...end)
            if let event = Self.parse(line: String(decoding: line, as: UTF8.self)) {
                events.append(event)
            }
        }
        return events
    }

    /// Called when the body ends. A complete answer has already reported
    /// `done`, so ending here means something went wrong.
    mutating func finish() -> [ClaudeEvent] {
        guard let status = httpError else {
            return [.failed("The connection closed before the answer was finished.")]
        }
        let body = try? JSONSerialization.jsonObject(with: errorBody) as? [String: Any]
        let detail =
            (body?["error"] as? [String: Any])?["message"] as? String
            ?? String(decoding: errorBody, as: UTF8.self)
        if status == 401 {
            return [.keyRejected(detail)]
        }
        return [.failed("Request failed (\(status)): \(detail)")]
    }

    /// Reads one line of the server-sent event stream. Only `data:` lines
    /// carry anything; thinking, fallback markers, and pings are ignored.
    static func parse(line: String) -> ClaudeEvent? {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("data:") else { return nil }
        let data = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard
            let event = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
            let type = event["type"] as? String
        else { return nil }
        let delta = event["delta"] as? [String: Any]
        switch type {
        case "content_block_delta" where delta?["type"] as? String == "text_delta":
            return (delta?["text"] as? String).map(ClaudeEvent.text)
        case "message_delta":
            switch delta?["stop_reason"] as? String {
            case "refusal": return .failed("Claude declined to answer this.")
            case "max_tokens": return .failed("The answer was cut off because it got too long.")
            default: return nil
            }
        case "message_stop":
            return .done
        case "error":
            let message = (event["error"] as? [String: Any])?["message"] as? String
            return .failed(message ?? "Claude reported an error.")
        default:
            return nil
        }
    }
}
