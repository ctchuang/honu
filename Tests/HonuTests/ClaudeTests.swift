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
        let arguments = ClaudeCode.arguments
        #expect(arguments.starts(with: ["-p"]))
        for (flag, value) in [
            ("--output-format", "stream-json"), ("--model", "claude-opus-5-5"),
            ("--effort", "low"), ("--tools", ""),
        ] {
            let index = arguments.firstIndex(of: flag)
            #expect(index.map { arguments[$0 + 1] } == value, "\(flag)")
        }
        for flag in ["--include-partial-messages", "--no-session-persistence", "--system-prompt"] {
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

    @Test func anAPIKeyInTheEnvironmentIsNotPassedOn() {
        let environment = ClaudeCode.environment(["ANTHROPIC_API_KEY": "sk-ant-x", "HOME": "/h"])
        #expect(environment == ["HOME": "/h"])
    }
}
