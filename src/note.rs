//! A Note bubble: text typed straight into the panel. The bubble takes its
//! label from the note's first line, so closed notes can be told apart.

use std::sync::atomic::{AtomicU64, Ordering};

use eframe::egui::{self, Color32, FontId, Rect};

use crate::bubble::short_label;

/// The label of a note with nothing written in it yet.
const EMPTY_LABEL: &str = "Note";

pub struct Note {
    /// Keeps the panel's widget ids stable when bubbles change order.
    serial: u64,
    text: String,
    /// Whether the text field should take the keyboard focus when next shown.
    focus_pending: bool,
}

impl Note {
    pub fn new() -> Self {
        static NEXT_SERIAL: AtomicU64 = AtomicU64::new(0);
        Self {
            serial: NEXT_SERIAL.fetch_add(1, Ordering::Relaxed),
            text: String::new(),
            focus_pending: true,
        }
    }

    pub fn with_text(mut self, text: &str) -> Self {
        self.text = text.to_owned();
        self
    }

    /// A short label for the bubble: the first line with anything on it.
    pub fn label(&self) -> String {
        self.text
            .lines()
            .map(str::trim)
            .find(|line| !line.is_empty())
            .map_or_else(|| EMPTY_LABEL.to_owned(), short_label)
    }

    /// Shows the text for editing in `rect`.
    pub fn ui(&mut self, ui: &mut egui::Ui, rect: Rect, color: Color32, interactive: bool) {
        ui.scope_builder(
            egui::UiBuilder::new()
                .id_salt(("note", self.serial))
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
                    .show(ui, |ui| {
                        let response = ui.add(
                            egui::TextEdit::multiline(&mut self.text)
                                .frame(egui::Frame::NONE)
                                .hint_text("Write something…")
                                .text_color(color)
                                .font(FontId::proportional(16.0))
                                .desired_width(f32::INFINITY)
                                .interactive(interactive),
                        );
                        // A new note is for writing in, so start with the cursor in it.
                        if interactive && std::mem::take(&mut self.focus_pending) {
                            response.request_focus();
                        }
                    });
            },
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn label(text: &str) -> String {
        let mut note = Note::new();
        note.text = text.to_owned();
        note.label()
    }

    #[test]
    fn label_is_the_first_line_with_text() {
        assert_eq!(label(""), EMPTY_LABEL);
        assert_eq!(label(" \n\n"), EMPTY_LABEL);
        assert_eq!(label("\n  Groceries  \nmilk\neggs"), "Groceries");
        assert_eq!(
            label("Remember to call the aquarium about the turtle"),
            "Remember to call the aqu…"
        );
    }
}
