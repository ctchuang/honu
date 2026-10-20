import Foundation
import Testing

@testable import Honu

struct EventParserTests {
    /// A line of `claude -p --output-format stream-json` passing on one
    /// event of the Messages API stream.
    private func apiEvent(_ event: String) -> String {
        #"{"type":"stream_event","event":\#(event),"session_id":"s"}"#
    }

    @Test func answerTextArrives() {
        let line = apiEvent(
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi 🐢"}}"#
        )
        #expect(EventParser.parse(line: line) == .text("Hi 🐢"))
    }

    @Test func aSuccessfulResultEndsTheAnswer() {
        let result =
            #"{"type":"result","subtype":"success","is_error":false,"result":"Salt.","session_id":"s"}"#
        #expect(EventParser.parse(line: result) == .done)
    }

    @Test func aFailedResultReportsWhy() {
        let notLoggedIn =
            #"{"type":"result","subtype":"success","is_error":true,"result":"Not logged in · Please run /login"}"#
        #expect(
            EventParser.parse(line: notLoggedIn) == .failed("Not logged in · Please run /login"))
        let errors =
            #"{"type":"result","subtype":"error_during_execution","is_error":true,"errors":["Overloaded"]}"#
        #expect(EventParser.parse(line: errors) == .failed("Overloaded"))
        let bare = #"{"type":"result","is_error":true}"#
        #expect(EventParser.parse(line: bare) == .failed("Claude Code reported an error."))
    }

    @Test func refusalsAndCutOffAnswersFail() {
        let refusal = apiEvent(#"{"type":"message_delta","delta":{"stop_reason":"refusal"}}"#)
        #expect(EventParser.parse(line: refusal) == .failed("Claude declined to answer this."))
        let maxTokens = apiEvent(#"{"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#)
        #expect(EventParser.parse(line: maxTokens)?.isFinal == true)
    }

    @Test func everythingButTheAnswerIsIgnored() {
        let ignored = [
            "",
            "not json",
            #"{"type":"system","subtype":"init","session_id":"s","tools":[]}"#,
            #"{"type":"system","subtype":"status","status":"requesting"}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Salt."}]}}"#,
            #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}"#,
            apiEvent(#"{"type":"message_start","message":{"content":[]}}"#),
            apiEvent(
                #"{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hmm"}}"#
            ),
            apiEvent(#"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#),
            apiEvent(#"{"type":"message_stop"}"#),
        ]
        for line in ignored {
            #expect(EventParser.parse(line: line) == nil, "\(line)")
        }
    }

    @Test func endingWithoutAResultFails() {
        #expect(
            EventParser.finish(status: 1, errors: "  Error: unknown option\n")
                == .failed("Error: unknown option"))
        #expect(EventParser.finish(status: 15, errors: "").isFinal)
    }
}

struct ClaudeCodeTests {
    @Test func theQuestionIsAnsweredQuicklyWithoutToolsOrASession() {
        let arguments = ClaudeCode.arguments(
            for: ClaudeRequest(prompt: "Why?", systemPrompt: "Answer.", effort: .medium))
        #expect(arguments.starts(with: ["-p"]))
        for (flag, value) in [
            ("--output-format", "stream-json"), ("--model", "claude-opus-5-5"),
            ("--effort", "medium"), ("--tools", ""), ("--system-prompt", "Answer."),
        ] {
            let index = arguments.firstIndex(of: flag)
            #expect(index.map { arguments[$0 + 1] } == value, "\(flag)")
        }
        for flag in ["--include-partial-messages", "--no-session-persistence"] {
            #expect(arguments.contains(flag), "\(flag)")
        }
    }

    @Test func claudeIsFoundInPathOrWhereItIsUsuallyInstalled() {
        let installed: Set = ["/usr/bin/claude", "/Users/me/.local/bin/claude"]
        func find(_ environment: [String: String]) -> String? {
            ClaudeCode.executable(environment: environment, isExecutable: installed.contains)?
                .path()
        }
        #expect(find(["PATH": "/bin:/usr/bin", "HOME": "/Users/me"]) == "/usr/bin/claude")
        #expect(find(["PATH": "/bin", "HOME": "/Users/me"]) == "/Users/me/.local/bin/claude")
        #expect(find(["HOME": "/Users/nobody"]) == nil)
    }

    @Test func claudeRunsInAFolderOfHonusOwn() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(ClaudeCode.workingDirectory.path() == home.path() + ".honu/")
    }

    /// Runs a stand-in for `claude`, the shell `script`, on a question, and
    /// returns what it streamed.
    private func answer(from script: String) async throws -> [ClaudeEvent] {
        let folder = temporaryDirectory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let executable = folder.appending(path: "claude")
        try ("#!/bin/sh\n" + script).write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: executable.path())
        let stream = AnswerStream()
        await ClaudeCode.receive(
            ClaudeRequest(prompt: "Why?", systemPrompt: "Answer."), from: executable, in: folder,
            into: stream)
        return stream.take().events
    }

    @Test func theAnswerStreamsInFromClaudeCode() async throws {
        let events = try await answer(
            from: #"""
                cat > /dev/null
                echo '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Salt."}}}'
                echo '{"type":"result","is_error":false}'
                """#)
        #expect(events == [.text("Salt."), .done])
    }

    @Test func aLotWrittenToStandardErrorDoesNotStallTheAnswer() async throws {
        // More than a pipe holds, so it blocks unless it is read as it comes.
        let events = try await answer(
            from: """
                head -c 200000 /dev/zero | tr '\\0' x >&2
                exit 3
                """)
        let failure = try #require(events.last)
        guard case .failed(let detail) = failure else {
            Issue.record("ended with \(failure)")
            return
        }
        #expect(detail.count == 200_000 && detail.allSatisfy { $0 == "x" })
    }

    @Test func anAPIKeyInTheEnvironmentIsNotPassedOn() {
        let environment = ClaudeCode.environment(["ANTHROPIC_API_KEY": "sk-ant-x", "HOME": "/h"])
        #expect(environment == ["HOME": "/h"])
    }
}
