//! The Ask AI microapp: any number of chats with Claude. In a chat's bubble
//! you type a question, and Claude's answer streams into the panel, which
//! grows to fit it.

use std::collections::BTreeMap;
use std::sync::mpsc;

use eframe::egui::{self, Color32, FontId, Rect, RichText};

use crate::bubble::{Gesture, short_label};
use crate::claude;
use crate::microapp::{AppId, Appearance, Context, ItemId, ItemIds, MicroApp, View};

const ID: AppId = AppId("ask");
/// A soft, slightly warm white, like paper.
const PAPER: Color32 = Color32::from_rgb(250, 249, 246);
/// The label of a chat with no question asked yet.
const EMPTY_LABEL: &str = "Ask";

/// Panel height while asking for a key or a question.
const START_HEIGHT: f32 = 150.0;
/// The tallest the panel grows; longer answers scroll.
const MAX_HEIGHT: f32 = 560.0;
/// Panel height not taken by the content: the title bar and the margins.
const CHROME_HEIGHT: f32 = 78.0;

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

/// One question for Claude and its answer.
struct Chat {
    question: String,
    /// The bubble's label, once a question has been asked.
    title: Option<String>,
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
enum Outcome {
    /// The whole answer arrived.
    Answered,
    /// The request failed or the key was refused; the user has to act.
    NeedsAttention,
}

pub struct AskApp {
    chats: BTreeMap<ItemId, Chat>,
    ids: ItemIds,
}

impl AskApp {
    pub fn new() -> Self {
        Self {
            chats: BTreeMap::new(),
            ids: ItemIds::default(),
        }
    }
}

impl MicroApp for AskApp {
    fn id(&self) -> AppId {
        ID
    }

    fn menu_label(&self) -> &'static str {
        "Ask AI"
    }

    /// Starts a chat with no question yet.
    fn create(&mut self) -> ItemId {
        let id = self.ids.next();
        self.chats.insert(id, Chat::new());
        id
    }

    fn appearance(&self, _item: ItemId) -> Appearance {
        Appearance {
            color: PAPER,
            glass: false,
            radius: 60.0,
            panel_height: Some(START_HEIGHT),
        }
    }

    /// A short label for a chat's bubble: its question, once asked.
    fn title(&self, item: ItemId) -> String {
        self.chats
            .get(&item)
            .and_then(|chat| chat.title.clone())
            .unwrap_or_else(|| EMPTY_LABEL.to_owned())
    }

    /// Whether Claude is still working on a chat's answer.
    fn is_busy(&self, item: ItemId) -> bool {
        self.chats.get(&item).is_some_and(Chat::is_busy)
    }

    /// Takes in whatever the answer streams have delivered. A chat's bubbles
    /// float up when its answer is in, and wobble when something needs the
    /// user. Call every frame.
    fn update(&mut self, cx: &mut Context) {
        for (&item, chat) in &mut self.chats {
            match chat.poll() {
                Some(Outcome::Answered) => cx.play(item, Gesture::Rise),
                Some(Outcome::NeedsAttention) => cx.play(item, Gesture::Wobble),
                None => {}
            }
        }
    }

    /// Shows a chat and returns the panel height that fits it. Without an
    /// API key it first asks for one and stores it in `cx`; a key the API
    /// refused is cleared from it.
    fn ui(
        &mut self,
        item: ItemId,
        ui: &mut egui::Ui,
        view: &View,
        cx: &mut Context,
    ) -> Option<f32> {
        let chat = self.chats.get_mut(&item)?;
        let (rect, color, interactive) = (view.rect, view.text_color, view.interactive);
        Some(chat.ui(ui, item, rect, color, interactive, cx.api_key))
    }

    /// Forgets a chat, which also stops its answer from streaming in.
    fn remove(&mut self, item: ItemId) {
        self.chats.remove(&item);
    }
}

impl Chat {
    fn new() -> Self {
        Self {
            question: String::new(),
            title: None,
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
    fn is_busy(&self) -> bool {
        matches!(self.status, Status::Thinking | Status::Answering)
    }

    /// Takes in whatever the answer stream has delivered, and reports how the
    /// question ended if it just did. Call every frame, whether or not the
    /// panel is open.
    fn poll(&mut self) -> Option<Outcome> {
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

    /// Shows the panel's content in `rect` and returns the panel height that
    /// fits it. `item` keeps the widget ids apart from other chats'.
    fn ui(
        &mut self,
        ui: &mut egui::Ui,
        item: ItemId,
        rect: Rect,
        color: Color32,
        interactive: bool,
        api_key: &mut Option<String>,
    ) -> f32 {
        if let Some(message) = self.key_rejected.take() {
            *api_key = None;
            self.key_error = Some(message);
        }
        let content_height = ui
            .scope_builder(
                egui::UiBuilder::new().id_salt((ID, item)).max_rect(rect),
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
                                self.question_ui(ui, color, interactive, key);
                            }
                            Some(_) => self.answer_ui(ui, color),
                        })
                        .content_size
                        .y
                },
            )
            .inner;
        (content_height + CHROME_HEIGHT).clamp(START_HEIGHT, MAX_HEIGHT)
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

    fn question_ui(&mut self, ui: &mut egui::Ui, color: Color32, interactive: bool, api_key: &str) {
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
            return;
        }
        self.stream = Some(claude::ask(api_key, question));
        self.status = Status::Thinking;
        self.title = Some(short_label(question));
    }

    fn answer_ui(&self, ui: &mut egui::Ui, color: Color32) {
        // The title shows the question, unless it had to be shortened.
        if short_label(&self.question) != self.question {
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::microapp::{Effect, ViewTarget};

    /// Runs `update` on `asks` and returns what it asked of the bubbles.
    fn update(asks: &mut AskApp) -> Vec<Effect> {
        let mut effects = Vec::new();
        asks.update(&mut Context::new(ID, &mut effects, &mut None));
        effects
    }

    #[test]
    fn finished_answers_and_failures_reach_the_bubbles() {
        let mut asks = AskApp::new();
        let item = asks.create();
        let (tx, rx) = mpsc::channel();
        let chat = asks.chats.get_mut(&item).unwrap();
        chat.stream = Some(rx);
        chat.status = Status::Thinking;
        assert!(asks.is_busy(item));

        tx.send(claude::Event::Text("Salt.".to_owned())).unwrap();
        assert!(update(&mut asks).is_empty());
        tx.send(claude::Event::Done).unwrap();
        let target = ViewTarget { app: ID, item };
        let rise = Effect::Gesture {
            target,
            gesture: Gesture::Rise,
        };
        assert_eq!(update(&mut asks), vec![rise]);
        assert!(!asks.is_busy(item));

        // A chat whose stream breaks off before any answer needs the user.
        let other = asks.create();
        let (tx, rx) = mpsc::channel::<claude::Event>();
        asks.chats.get_mut(&other).unwrap().stream = Some(rx);
        drop(tx);
        let target = ViewTarget {
            app: ID,
            item: other,
        };
        let wobble = Effect::Gesture {
            target,
            gesture: Gesture::Wobble,
        };
        assert_eq!(update(&mut asks), vec![wobble]);
    }
}
