//! An Ask bubble: type a question, and Claude's answer streams into the
//! panel, which grows to fit it.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc;

use eframe::egui::{self, Color32, FontId, Rect, RichText};

use crate::claude;

/// Panel height while asking for a key or a question.
pub const START_HEIGHT: f32 = 150.0;
/// The tallest the panel grows; longer answers scroll.
const MAX_HEIGHT: f32 = 560.0;
/// Panel height not taken by the content: the title bar and the margins.
const CHROME_HEIGHT: f32 = 78.0;
/// Longest label a bubble gets from its question, in characters.
const LABEL_CHARS: usize = 24;

#[cfg(target_arch = "wasm32")]
const KEY_NOTE: &str = "It is saved in this browser only and sent only to Anthropic.";
#[cfg(not(target_arch = "wasm32"))]
const KEY_NOTE: &str = "It is kept until Honu quits. To skip this, put ANTHROPIC_API_KEY in .env.";

enum Status {
    /// Waiting for a question, with why the last try failed, if it did.
    Typing {
        error: Option<String>,
    },
    /// Asked, with no words of the answer yet.
    Thinking,
    Answering,
    Done,
    /// Stopped partway through the answer.
    Failed(String),
}

pub struct Ask {
    /// Keeps the panel's widget ids stable when bubbles change order.
    serial: u64,
    question: String,
    answer: String,
    status: Status,
    stream: Option<mpsc::Receiver<claude::Event>>,
    /// What is typed into the key field before it is saved.
    key_draft: String,
    /// Why the API refused the key, until the panel next shows and drops it.
    key_rejected: Option<String>,
    /// Shown in the key field's place after a key was refused.
    key_error: Option<String>,
    /// Whether the next text field shown should take the keyboard focus.
    focus_pending: bool,
}

/// How an asked question came to an end, for the bubble to show.
#[derive(Debug, PartialEq)]
pub enum Outcome {
    /// The whole answer arrived.
    Answered,
    /// The request failed or the key was refused; the user has to act.
    NeedsAttention,
}

/// What happened in the panel this frame.
pub struct Response {
    /// Panel height that fits the content.
    pub height: f32,
    /// A short label for the bubble, once a question has been asked.
    pub asked: Option<String>,
}

impl Ask {
    pub fn new() -> Self {
        static NEXT_SERIAL: AtomicU64 = AtomicU64::new(0);
        Self {
            serial: NEXT_SERIAL.fetch_add(1, Ordering::Relaxed),
            question: String::new(),
            answer: String::new(),
            status: Status::Typing { error: None },
            stream: None,
            key_draft: String::new(),
            key_rejected: None,
            key_error: None,
            focus_pending: true,
        }
    }

    /// Whether Claude is still working on the answer.
    pub fn is_busy(&self) -> bool {
        matches!(self.status, Status::Thinking | Status::Answering)
    }

    /// Takes in whatever the answer stream has delivered, and reports how the
    /// question ended if it just did. Call every frame, whether or not the
    /// panel is open.
    pub fn poll(&mut self) -> Option<Outcome> {
        let Some(stream) = &self.stream else {
            return None;
        };
        loop {
            match stream.try_recv() {
                Ok(claude::Event::Text(text)) => {
                    self.answer.push_str(&text);
                    self.status = Status::Answering;
                }
                Ok(claude::Event::Done) => {
                    self.status = Status::Done;
                    self.stream = None;
                    return Some(Outcome::Answered);
                }
                Ok(claude::Event::Failed(message)) => {
                    self.fail(message);
                    return Some(Outcome::NeedsAttention);
                }
                Ok(claude::Event::KeyRejected(message)) => {
                    // Ask for another key, then let the same question be sent again.
                    self.key_rejected = Some(message);
                    self.status = Status::Typing { error: None };
                    self.stream = None;
                    self.focus_pending = true;
                    return Some(Outcome::NeedsAttention);
                }
                Err(mpsc::TryRecvError::Empty) => return None,
                Err(mpsc::TryRecvError::Disconnected) => {
                    self.fail("The answer stopped unexpectedly.".to_owned());
                    return Some(Outcome::NeedsAttention);
                }
            }
        }
    }

    /// Ends the stream with `message`. Before any answer arrived, the question
    /// can simply be sent again.
    fn fail(&mut self, message: String) {
        self.stream = None;
        if self.answer.is_empty() {
            self.status = Status::Typing {
                error: Some(message),
            };
            self.focus_pending = true;
        } else {
            self.status = Status::Failed(message);
        }
    }

    /// Shows the panel's content in `rect`. Without an `api_key` it first asks
    /// for one and stores it there; a key the API refused is cleared from it.
    pub fn ui(
        &mut self,
        ui: &mut egui::Ui,
        rect: Rect,
        color: Color32,
        interactive: bool,
        api_key: &mut Option<String>,
    ) -> Response {
        if let Some(message) = self.key_rejected.take() {
            *api_key = None;
            self.key_error = Some(message);
        }
        let mut asked = None;
        let content_height = ui
            .scope_builder(
                egui::UiBuilder::new()
                    .id_salt(("ask", self.serial))
                    .max_rect(rect),
                |ui| {
                    // No drag-to-scroll, so dragging the panel body moves the bubble.
                    let scroll_source = egui::scroll_area::ScrollSource {
                        scroll_bar: true,
                        mouse_wheel: true,
                        ..egui::scroll_area::ScrollSource::NONE
                    };
                    egui::ScrollArea::vertical()
                        .scroll_source(scroll_source)
                        .stick_to_bottom(true)
                        .show(ui, |ui| match api_key {
                            None => self.key_ui(ui, color, interactive, api_key),
                            Some(key) if matches!(self.status, Status::Typing { .. }) => {
                                asked = self.question_ui(ui, color, interactive, key);
                            }
                            Some(_) => self.answer_ui(ui, color),
                        })
                        .content_size
                        .y
                },
            )
            .inner;
        Response {
            height: (content_height + CHROME_HEIGHT).clamp(START_HEIGHT, MAX_HEIGHT),
            asked,
        }
    }

    fn key_ui(
        &mut self,
        ui: &mut egui::Ui,
        color: Color32,
        interactive: bool,
        api_key: &mut Option<String>,
    ) {
        match &self.key_error {
            Some(error) => {
                ui.add(
                    egui::Label::new(error_text(&format!("That key didn't work: {error}"))).wrap(),
                );
            }
            None => {
                ui.label(RichText::new("Paste a Claude API key to ask questions.").color(color));
            }
        }
        let response = ui.add(
            egui::TextEdit::singleline(&mut self.key_draft)
                .password(true)
                .hint_text("sk-ant-…")
                .desired_width(f32::INFINITY)
                .interactive(interactive),
        );
        self.take_focus(&response, interactive);
        ui.add(egui::Label::new(RichText::new(KEY_NOTE).color(color.gamma_multiply(0.6))).wrap());
        let key = self.key_draft.trim();
        if submitted(ui, &response) && !key.is_empty() {
            *api_key = Some(key.to_owned());
            self.key_draft.clear();
            self.key_error = None;
            // Move straight on to the question field.
            self.focus_pending = true;
        }
    }

    fn question_ui(
        &mut self,
        ui: &mut egui::Ui,
        color: Color32,
        interactive: bool,
        api_key: &str,
    ) -> Option<String> {
        if let Status::Typing { error: Some(error) } = &self.status {
            ui.add(egui::Label::new(error_text(error)).wrap());
        }
        let response = ui.add(
            egui::TextEdit::singleline(&mut self.question)
                .hint_text("Ask Claude…")
                .text_color(color)
                .font(FontId::proportional(16.0))
                .desired_width(f32::INFINITY)
                .interactive(interactive),
        );
        self.take_focus(&response, interactive);
        let question = self.question.trim();
        if !submitted(ui, &response) || question.is_empty() {
            return None;
        }
        self.stream = Some(claude::ask(api_key, question));
        self.status = Status::Thinking;
        Some(label_for(question))
    }

    fn answer_ui(&self, ui: &mut egui::Ui, color: Color32) {
        // The title shows the question, unless it had to be shortened.
        if label_for(&self.question) != self.question {
            let question = RichText::new(&self.question).color(color.gamma_multiply(0.6));
            ui.add(egui::Label::new(question).wrap());
            ui.add_space(6.0);
        }
        if !self.answer.is_empty() {
            ui.add(
                egui::Label::new(RichText::new(&self.answer).color(color).size(16.0))
                    .wrap()
                    .selectable(true),
            );
        }
        match &self.status {
            Status::Thinking => {
                ui.horizontal(|ui| {
                    ui.spinner();
                    ui.label(RichText::new("Thinking…").color(color.gamma_multiply(0.6)));
                });
            }
            Status::Failed(message) => {
                ui.add(egui::Label::new(error_text(message)).wrap());
            }
            Status::Typing { .. } | Status::Answering | Status::Done => {}
        }
    }

    fn take_focus(&mut self, response: &egui::Response, interactive: bool) {
        if interactive && std::mem::take(&mut self.focus_pending) {
            response.request_focus();
        }
    }
}

fn error_text(message: &str) -> RichText {
    RichText::new(message).color(Color32::from_rgb(190, 60, 50))
}

/// Whether Enter was pressed in the single-line field of `response`.
fn submitted(ui: &egui::Ui, response: &egui::Response) -> bool {
    response.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter))
}

/// A short bubble label for `question`.
fn label_for(question: &str) -> String {
    let mut chars = question.chars();
    let label: String = chars.by_ref().take(LABEL_CHARS).collect();
    if chars.next().is_some() {
        format!("{}…", label.trim_end())
    } else {
        label
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn long_questions_get_short_labels() {
        assert_eq!(label_for("Why is the sea salty?"), "Why is the sea salty?");
        let label = label_for("How far can a green sea turtle swim in one day?");
        assert_eq!(label, "How far can a green sea…");
        // Counted in characters, so multi-byte ones are never cut in half.
        let turtles = "🐢".repeat(30);
        assert_eq!(label_for(&turtles), format!("{}…", "🐢".repeat(24)));
    }
}
