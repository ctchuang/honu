//! Asking Claude a question and streaming the answer back. Microapps ask
//! through a `Client`: `Api`, the Messages API, or a stand-in in tests.
//! There is no official Rust SDK, so `Api` is raw HTTP over `ehttp`, which
//! streams both natively (on a background thread) and in the browser (with
//! `fetch`).

use std::ops::ControlFlow;
use std::sync::{Mutex, mpsc};

const API_URL: &str = "https://api.anthropic.com/v1/messages";
const MODEL: &str = "claude-opus-5-5";
/// Lets a refused request retry on the fallback model Anthropic recommends
/// for the refusal's category, inside the same call.
const FALLBACK_BETA: &str = "server-side-fallback-2026-07-01";
const SYSTEM_PROMPT: &str = "You answer questions inside a small floating panel on the user's \
desktop. Keep answers short and to the point. Write plain text without Markdown, since the \
panel shows the raw text.";

/// What the stream reports, in order: any number of `Text` pieces, then
/// `Done`, `Failed`, or `KeyRejected`.
#[derive(Debug, PartialEq)]
pub enum Event {
    Text(String),
    Done,
    Failed(String),
    /// The API key was refused (HTTP 401), with the API's explanation.
    KeyRejected(String),
}

/// Asks Claude questions.
pub trait Client {
    /// Starts streaming Claude's answer to `question`. Events arrive on the
    /// returned channel; poll it every frame.
    fn ask(&self, api_key: &str, question: &str) -> mpsc::Receiver<Event>;
}

/// The Messages API.
pub struct Api;

impl Client for Api {
    fn ask(&self, api_key: &str, question: &str) -> mpsc::Receiver<Event> {
        ask(api_key, question)
    }
}

/// A stand-in for the API in tests. It records the questions asked and
/// keeps the sending end of each answer stream, for the test to answer;
/// clones share them.
#[cfg(test)]
#[derive(Clone, Default)]
pub struct Fake {
    streams: std::rc::Rc<std::cell::RefCell<Vec<FakeStream>>>,
}

/// A question asked of the `Fake`, and the sending end of its answer stream
/// until hung up.
#[cfg(test)]
type FakeStream = (String, Option<mpsc::Sender<Event>>);

#[cfg(test)]
impl Fake {
    /// The questions asked so far, in order.
    pub fn asked(&self) -> Vec<String> {
        self.streams
            .borrow()
            .iter()
            .map(|(q, _)| q.clone())
            .collect()
    }

    /// Sends `event` down the answer stream of the `i`th question.
    pub fn answer(&self, i: usize, event: Event) {
        let streams = self.streams.borrow();
        let tx = streams[i].1.as_ref().expect("that stream was hung up");
        tx.send(event).expect("nobody listens to that stream");
    }

    /// Breaks off the answer stream of the `i`th question.
    pub fn hang_up(&self, i: usize) {
        self.streams.borrow_mut()[i].1 = None;
    }
}

#[cfg(test)]
impl Client for Fake {
    fn ask(&self, _api_key: &str, question: &str) -> mpsc::Receiver<Event> {
        let (tx, rx) = mpsc::channel();
        self.streams
            .borrow_mut()
            .push((question.to_owned(), Some(tx)));
        rx
    }
}

/// Starts streaming Claude's answer to `question` from the Messages API.
fn ask(api_key: &str, question: &str) -> mpsc::Receiver<Event> {
    let (tx, rx) = mpsc::channel();
    let body = serde_json::json!({
        "model": MODEL,
        "max_tokens": 64000,
        "stream": true,
        "system": SYSTEM_PROMPT,
        // Quick questions don't need deep thinking, and a fast first word matters here.
        "output_config": {"effort": "low"},
        "fallbacks": "default",
        "messages": [{"role": "user", "content": question}],
    });
    let request = match ehttp::Request::post_json(API_URL, &body) {
        Ok(request) => request,
        Err(err) => {
            let _ = tx.send(Event::Failed(err.to_string()));
            return rx;
        }
    };
    let request = request
        .with_header("x-api-key", api_key)
        .with_header("anthropic-version", "2023-06-01")
        .with_header("anthropic-beta", FALLBACK_BETA);
    // Browsers only allow the call with this opt-in, since a key in a web page
    // is visible to whoever uses it.
    #[cfg(target_arch = "wasm32")]
    let request = request.with_header("anthropic-dangerous-direct-browser-access", "true");

    let stream = Mutex::new(Stream::default());
    ehttp::streaming::fetch(request, move |part| {
        let mut stream = stream
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let events = match part {
            Ok(ehttp::streaming::Part::Response(response)) => {
                if !response.ok {
                    stream.http_error = Some(response.status);
                }
                Vec::new()
            }
            Ok(ehttp::streaming::Part::Chunk(chunk)) if chunk.is_empty() => stream.finish(),
            Ok(ehttp::streaming::Part::Chunk(chunk)) => stream.feed(&chunk),
            Err(err) => vec![Event::Failed(err)],
        };
        for event in events {
            let finished = !matches!(event, Event::Text(_));
            // Stop reading once the answer is over or nobody listens anymore.
            if tx.send(event).is_err() || finished {
                return ControlFlow::Break(());
            }
        }
        ControlFlow::Continue(())
    });
    rx
}

/// Turns the raw response bytes into events.
#[derive(Default)]
struct Stream {
    /// Bytes of the line still being received.
    pending: Vec<u8>,
    /// The status of an unsuccessful response, whose body is an error object
    /// rather than an event stream.
    http_error: Option<u16>,
    /// The whole body of an unsuccessful response.
    error_body: Vec<u8>,
}

impl Stream {
    fn feed(&mut self, chunk: &[u8]) -> Vec<Event> {
        if self.http_error.is_some() {
            self.error_body.extend_from_slice(chunk);
            return Vec::new();
        }
        self.pending.extend_from_slice(chunk);
        let mut events = Vec::new();
        // Split on whole lines only, so multi-byte characters never break apart.
        while let Some(end) = self.pending.iter().position(|&b| b == b'\n') {
            let line: Vec<u8> = self.pending.drain(..=end).collect();
            events.extend(parse_line(&String::from_utf8_lossy(&line)));
        }
        events
    }

    /// Called when the body ends. A complete answer has already reported
    /// `Done`, so ending here means something went wrong.
    fn finish(&mut self) -> Vec<Event> {
        let Some(status) = self.http_error else {
            let message = "The connection closed before the answer was finished.";
            return vec![Event::Failed(message.to_owned())];
        };
        let detail = serde_json::from_slice::<serde_json::Value>(&self.error_body)
            .ok()
            .and_then(|body| body["error"]["message"].as_str().map(str::to_owned))
            .unwrap_or_else(|| String::from_utf8_lossy(&self.error_body).into_owned());
        if status == 401 {
            vec![Event::KeyRejected(detail)]
        } else {
            vec![Event::Failed(format!(
                "Request failed ({status}): {detail}"
            ))]
        }
    }
}

/// Reads one line of the server-sent event stream. Only `data:` lines carry
/// anything; thinking, fallback markers, and pings are ignored.
fn parse_line(line: &str) -> Option<Event> {
    let data = line.trim_end().strip_prefix("data:")?.trim_start();
    let event: serde_json::Value = serde_json::from_str(data).ok()?;
    match event["type"].as_str()? {
        "content_block_delta" if event["delta"]["type"] == "text_delta" => {
            Some(Event::Text(event["delta"]["text"].as_str()?.to_owned()))
        }
        "message_delta" => match event["delta"]["stop_reason"].as_str()? {
            "refusal" => Some(Event::Failed("Claude declined to answer this.".to_owned())),
            "max_tokens" => Some(Event::Failed(
                "The answer was cut off because it got too long.".to_owned(),
            )),
            _ => None,
        },
        "message_stop" => Some(Event::Done),
        "error" => Some(Event::Failed(
            event["error"]["message"]
                .as_str()
                .unwrap_or("Claude reported an error.")
                .to_owned(),
        )),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn text_arrives_across_chunk_boundaries() {
        let mut stream = Stream::default();
        let line = "data: {\"type\":\"content_block_delta\",\"index\":0,\
                    \"delta\":{\"type\":\"text_delta\",\"text\":\"Hi 🐢\"}}\n";
        // Split in the middle of the turtle emoji's bytes.
        let split = line.find('🐢').unwrap() + 2;
        assert!(stream.feed(&line.as_bytes()[..split]).is_empty());
        let events = stream.feed(&line.as_bytes()[split..]);
        assert_eq!(events, vec![Event::Text("Hi 🐢".to_owned())]);
    }

    #[test]
    fn stream_ends_with_done() {
        let mut stream = Stream::default();
        let body = "event: message_delta\n\
                    data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"}}\n\n\
                    event: message_stop\n\
                    data: {\"type\":\"message_stop\"}\n\n";
        assert_eq!(stream.feed(body.as_bytes()), vec![Event::Done]);
    }

    #[test]
    fn refusal_and_errors_fail() {
        let refusal = "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"refusal\"}}";
        assert!(matches!(parse_line(refusal), Some(Event::Failed(_))));
        let error = "data: {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\
                     \"message\":\"Overloaded\"}}";
        assert_eq!(
            parse_line(error),
            Some(Event::Failed("Overloaded".to_owned()))
        );
    }

    #[test]
    fn everything_but_answer_text_is_ignored() {
        let ignored = [
            "event: content_block_delta",
            "",
            ": comment",
            "data: {\"type\":\"ping\"}",
            "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"thinking_delta\",\
             \"thinking\":\"hmm\"}}",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"}}",
            "data: not json",
        ];
        for line in ignored {
            assert_eq!(parse_line(line), None, "{line}");
        }
    }

    #[test]
    fn crlf_line_endings_are_accepted() {
        let mut stream = Stream::default();
        let body = "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\
                    \"text\":\"ok\"}}\r\n\r\n";
        assert_eq!(
            stream.feed(body.as_bytes()),
            vec![Event::Text("ok".to_owned())]
        );
    }

    #[test]
    fn cut_off_answers_fail() {
        let max_tokens =
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"max_tokens\"}}";
        assert!(matches!(parse_line(max_tokens), Some(Event::Failed(_))));
        // The body ending without `message_stop` means the connection dropped.
        let mut stream = Stream::default();
        assert!(matches!(stream.finish().as_slice(), [Event::Failed(_)]));
    }

    #[test]
    fn http_errors_report_the_api_message() {
        let error_stream = |status, message: &str| {
            let mut stream = Stream {
                http_error: Some(status),
                ..Stream::default()
            };
            let body = format!("{{\"type\":\"error\",\"error\":{{\"message\":\"{message}\"}}}}");
            assert!(stream.feed(body.as_bytes()).is_empty());
            stream.finish()
        };
        assert_eq!(
            error_stream(401, "invalid x-api-key"),
            vec![Event::KeyRejected("invalid x-api-key".to_owned())]
        );
        assert_eq!(
            error_stream(429, "rate limited"),
            vec![Event::Failed(
                "Request failed (429): rate limited".to_owned()
            )]
        );
    }
}
