//! The Notes microapp: any number of notes, each typed straight into its
//! bubble. A note's bubble takes its label from the note's first line, so
//! closed notes can be told apart.

use std::collections::BTreeMap;

use eframe::egui::{self, Color32, FontId};

use crate::microapp::{
    AppId, Appearance, Context, ItemId, ItemIds, MicroApp, View, ViewState, focus_at_end,
};
use crate::view::bubble::short_label;

const ID: AppId = AppId("notes");
/// The label of a note with nothing written in it yet.
const EMPTY_LABEL: &str = "Note";
/// The pale yellow of a sticky note.
const NOTE_YELLOW: Color32 = Color32::from_rgb(255, 236, 150);

/// One note.
/// One note: the model.
struct Note {
    text: String,
}

/// What one bubble showing a note keeps for itself: the view state.
struct NoteView {
    /// Whether the text field should take the keyboard focus when next shown.
    focus_pending: bool,
}

pub struct NotesApp {
    notes: BTreeMap<ItemId, Note>,
    ids: ItemIds,
}

impl NotesApp {
    pub fn new() -> Self {
        Self {
            notes: BTreeMap::new(),
            ids: ItemIds::default(),
        }
    }
}

impl MicroApp for NotesApp {
    fn id(&self) -> AppId {
        ID
    }

    fn menu_label(&self) -> &'static str {
        "Add Note"
    }

    fn create(&mut self) -> ItemId {
        let id = self.ids.next();
        self.notes.insert(
            id,
            Note {
                text: String::new(),
            },
        );
        id
    }

    fn appearance(&self, _item: ItemId) -> Appearance {
        Appearance {
            color: NOTE_YELLOW,
            glass: false,
            radius: 60.0,
            panel_height: None,
        }
    }

    /// A note is for writing in, so a new bubble starts with the cursor in it.
    fn new_view(&self, _item: ItemId) -> ViewState {
        Box::new(NoteView {
            focus_pending: true,
        })
    }

    /// A short label for a note's bubble: its first line with anything on it.
    fn title(&self, item: ItemId) -> String {
        self.notes
            .get(&item)
            .and_then(|note| note.text.lines().map(str::trim).find(|l| !l.is_empty()))
            .map_or_else(|| EMPTY_LABEL.to_owned(), short_label)
    }

    /// Shows a note's text for editing.
    fn ui(
        &mut self,
        item: ItemId,
        ui: &mut egui::Ui,
        view: View,
        _cx: &mut Context,
    ) -> Option<f32> {
        let note = self.notes.get_mut(&item)?;
        let state = view.state.downcast_mut::<NoteView>()?;
        let (rect, color, interactive) = (view.rect, view.text_color, view.interactive);
        note.text.push_str(&view.typed_ahead);
        ui.scope_builder(
            egui::UiBuilder::new().id_salt(view.bubble).max_rect(rect),
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
                            egui::TextEdit::multiline(&mut note.text)
                                .frame(egui::Frame::NONE)
                                .hint_text("Write something…")
                                .text_color(color)
                                .font(FontId::proportional(16.0))
                                .desired_width(f32::INFINITY)
                                .interactive(interactive),
                        );
                        if interactive && std::mem::take(&mut state.focus_pending) {
                            focus_at_end(ui, &response, &note.text);
                        }
                    });
            },
        );
        // Notes keep the usual panel size.
        None
    }

    fn remove(&mut self, item: ItemId) {
        self.notes.remove(&item);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn title(text: &str) -> String {
        let mut notes = NotesApp::new();
        let item = notes.create();
        notes.notes.get_mut(&item).unwrap().text = text.to_owned();
        notes.title(item)
    }

    #[test]
    fn title_is_the_first_line_with_text() {
        assert_eq!(title(""), EMPTY_LABEL);
        assert_eq!(title(" \n\n"), EMPTY_LABEL);
        assert_eq!(title("\n  Groceries  \nmilk\neggs"), "Groceries");
        assert_eq!(
            title("Remember to call the aquarium about the turtle"),
            "Remember to call the aqu…"
        );
    }

    #[test]
    fn notes_are_kept_apart_until_removed() {
        let mut notes = NotesApp::new();
        let a = notes.create();
        let b = notes.create();
        assert_ne!(a, b);
        notes.notes.get_mut(&a).unwrap().text = "a".to_owned();
        assert_eq!(
            (notes.title(a).as_str(), notes.title(b).as_str()),
            ("a", EMPTY_LABEL)
        );
        notes.remove(a);
        assert_eq!(notes.title(a), EMPTY_LABEL);
        assert_eq!(notes.notes.len(), 1);
    }
}
