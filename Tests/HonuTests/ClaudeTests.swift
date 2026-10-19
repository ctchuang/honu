import Foundation
import Testing

@testable import Honu

struct EventParserTests {
    @Test func textArrivesAcrossChunkBoundaries() {
        var parser = EventParser()
        let line =
            Data(
                #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi 🐢"}}"#
                    .utf8) + Data("\n".utf8)
        // Split in the middle of the turtle emoji's bytes.
        let split = line.firstIndex(of: 0xF0)! + 2
        #expect(parser.feed(line[..<split]).isEmpty)
        #expect(parser.feed(line[split...]) == [.text("Hi 🐢")])
    }

    @Test func streamEndsWithDone() {
        var parser = EventParser()
        let body = """
            event: message_delta
            data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}

            event: message_stop
            data: {"type":"message_stop"}


            """
        #expect(parser.feed(Data(body.utf8)) == [.done])
    }

    @Test func refusalAndErrorsFail() {
        let refusal = #"data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}"#
        #expect(EventParser.parse(line: refusal) == .failed("Claude declined to answer this."))
        let error =
            #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        #expect(EventParser.parse(line: error) == .failed("Overloaded"))
    }

    @Test func everythingButAnswerTextIsIgnored() {
        let ignored = [
            "event: content_block_delta",
            "",
            ": comment",
            #"data: {"type":"ping"}"#,
            #"data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hmm"}}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#,
            "data: not json",
        ]
        for line in ignored {
            #expect(EventParser.parse(line: line) == nil, "\(line)")
        }
    }

    @Test func crlfLineEndingsAreAccepted() {
        var parser = EventParser()
        let body =
            #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"ok"}}"#
        #expect(parser.feed(Data((body + "\r\n\r\n").utf8)) == [.text("ok")])
    }

    @Test func cutOffAnswersFail() {
        let maxTokens = #"data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#
        #expect(EventParser.parse(line: maxTokens)?.isFinal == true)
        // The body ending without `message_stop` means the connection dropped.
        var parser = EventParser()
        #expect(parser.finish().count == 1)
        #expect(parser.finish().first?.isFinal == true)
    }

    @Test func httpErrorsReportTheAPIMessage() {
        func error(_ status: Int, _ message: String) -> [ClaudeEvent] {
            var parser = EventParser()
            parser.httpError = status
            #expect(
                parser.feed(Data(#"{"type":"error","error":{"message":"\#(message)"}}"#.utf8))
                    .isEmpty)
            return parser.finish()
        }
        #expect(error(401, "invalid x-api-key") == [.keyRejected("invalid x-api-key")])
        #expect(error(429, "rate limited") == [.failed("Request failed (429): rate limited")])
    }

    @Test @MainActor func theRequestAsksForAQuickStreamedAnswer() throws {
        let request = MessagesAPI.request(apiKey: "sk-ant-test", question: "Why is the sea salty?")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(
            request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01"
        )
        let data = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: data)
        let body = try #require(json as? [String: Any])
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["stream"] as? Bool == true)
        #expect(body["fallbacks"] as? String == "default")
        #expect((body["output_config"] as? [String: String])?["effort"] == "low")
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages == [["role": "user", "content": "Why is the sea salty?"]])
    }
}

struct ApiKeyTests {
    @Test func dotEnvFilesAreRead() {
        let text = """
            # A comment
            ANTHROPIC_API_KEY="sk-ant-quoted"

            export OTHER = 'single'
            BROKEN
            EMPTY=
            """
        #expect(
            ApiKey.parseDotEnv(text) == [
                "ANTHROPIC_API_KEY": "sk-ant-quoted", "OTHER": "single", "EMPTY": "",
            ])
    }

    @Test func theEnvironmentComesBeforeTheNearestDotEnv() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "honu-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let inner = root.appending(path: "a/b", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try "ANTHROPIC_API_KEY=sk-ant-file\n".write(
            to: root.appending(path: ".env"), atomically: true, encoding: .utf8)
        #expect(ApiKey.fromEnvironment([:], directory: inner) == "sk-ant-file")
        #expect(
            ApiKey.fromEnvironment(["ANTHROPIC_API_KEY": "sk-ant-env"], directory: inner)
                == "sk-ant-env")
        #expect(ApiKey.fromEnvironment(["ANTHROPIC_API_KEY": "  "], directory: inner) == nil)
    }
}
