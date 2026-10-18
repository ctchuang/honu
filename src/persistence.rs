//! Keeping the bubbles and the microapps' items across launches, in eframe's
//! storage: a file on the desktop, local storage on the web. Each microapp
//! saves its own items (`MicroApp::save`) under a key of its own; this module
//! saves which bubbles show which items, where, and whether they are open.

use std::collections::HashMap;

use eframe::egui::{Pos2, vec2};
use serde::{Deserialize, Serialize};

use crate::microapp::{AppId, ItemId, Registry, ViewTarget};
use crate::stage::Stage;

/// Storage key for the bubbles.
const BUBBLES_KEY: &str = "bubbles";
/// Seconds between checks for changes to save. Quitting with ⌘Q or from the
/// Dock skips eframe's own save, so at most this much work can be lost.
const SAVE_INTERVAL: f64 = 1.0;

/// Storage key for a microapp's items.
fn app_key(app: AppId) -> String {
    format!("app.{}", app.0)
}

/// A bubble as saved between launches.
#[derive(Serialize, Deserialize)]
struct SavedBubble {
    /// The microapp, as its `AppId` spells it.
    app: String,
    item: u64,
    /// Where the bubble was, relative to the window's center, so it comes
    /// back in place in a window of another size.
    x: f32,
    y: f32,
    open: bool,
}

/// Puts back the items and bubbles saved on a previous launch, laying the
/// bubbles out around `center`. Items no bubble showed, such as one still in
/// the octopus, are deleted.
pub fn restore(
    storage: Option<&dyn eframe::Storage>,
    apps: &mut Registry,
    stage: &mut Stage,
    center: Pos2,
) {
    let Some(storage) = storage else {
        return;
    };
    let ids: Vec<AppId> = apps.iter().map(|app| app.id()).collect();
    for &id in &ids {
        let saved = storage.get_string(&app_key(id));
        let saved = saved.and_then(|json| serde_json::from_str(&json).ok());
        if let (Some(saved), Some(app)) = (saved, apps.get_mut(id)) {
            app.load(saved);
        }
    }

    let saved = storage.get_string(BUBBLES_KEY);
    let bubbles: Vec<SavedBubble> = saved
        .and_then(|json| serde_json::from_str(&json).ok())
        .unwrap_or_default();
    for (i, saved) in bubbles.into_iter().enumerate() {
        let Some(app) = apps.find(&saved.app) else {
            continue;
        };
        let target = ViewTarget {
            app,
            item: ItemId(saved.item),
        };
        if !apps.has(target) {
            continue;
        }
        let Some(mut bubble) = apps.bubble_for(target, false) else {
            continue;
        };
        bubble.center = center + vec2(saved.x, saved.y);
        // Drift out of step with each other.
        bubble.phase = i as f32 * 1.7;
        if saved.open {
            bubble = bubble.opened();
        }
        stage.add(bubble);
    }

    for id in ids {
        let Some(app) = apps.get_mut(id) else {
            continue;
        };
        for item in app.items() {
            if !stage.shows(ViewTarget { app: id, item }) {
                app.remove(item);
            }
        }
    }
}

/// Saves what changed, checking once every `SAVE_INTERVAL`.
pub struct Autosave {
    /// What was last written under each key.
    written: HashMap<String, String>,
    /// Which bubbles were last saved, and whether open, but not where: idle
    /// bubbles drift all the time, and saving that would write every check.
    written_layout: String,
    /// Set when a bubble was moved on purpose, so where it is gets saved.
    moved: bool,
    /// When the next check is due, in seconds of app time.
    next_check: f64,
}

impl Autosave {
    pub fn new() -> Self {
        Self {
            written: HashMap::new(),
            written_layout: String::new(),
            moved: false,
            next_check: 0.0,
        }
    }

    /// Notes that a bubble was put somewhere on purpose, as by a drag.
    pub fn moved(&mut self) {
        self.moved = true;
    }

    /// Saves what changed since the last save, if a check is due at `time`.
    pub fn tick(
        &mut self,
        time: f64,
        storage: Option<&mut (dyn eframe::Storage + 'static)>,
        apps: &Registry,
        stage: &Stage,
        center: Pos2,
    ) {
        if time < self.next_check {
            return;
        }
        self.next_check = time + SAVE_INTERVAL;
        if let Some(storage) = storage {
            self.save(storage, apps, stage, center);
        }
    }

    /// Saves what changed since the last save, now.
    pub fn save(
        &mut self,
        storage: &mut dyn eframe::Storage,
        apps: &Registry,
        stage: &Stage,
        center: Pos2,
    ) {
        let mut changed = false;
        for app in apps.iter() {
            changed |= self.write(storage, app_key(app.id()), app.save().to_string());
        }
        // Bubbles in the octopus count as deleted.
        let bubbles: Vec<_> = stage
            .bubbles()
            .iter()
            .filter(|b| !b.is_swallowing())
            .map(|b| SavedBubble {
                app: b.target.app.0.to_owned(),
                item: b.target.item.0,
                x: b.destination().x - center.x,
                y: b.destination().y - center.y,
                open: b.is_or_will_be_open(),
            })
            .collect();
        let layout: Vec<_> = bubbles.iter().map(|b| (&b.app, b.item, b.open)).collect();
        let layout = serde_json::to_string(&layout).unwrap_or_default();
        if changed || std::mem::take(&mut self.moved) || layout != self.written_layout {
            let json = serde_json::to_string(&bubbles).unwrap_or_default();
            changed |= self.write(storage, BUBBLES_KEY.to_owned(), json);
            self.written_layout = layout;
        }
        if changed {
            storage.flush();
        }
    }

    /// Writes `value` under `key` unless it is already there. Returns whether
    /// it wrote.
    fn write(&mut self, storage: &mut dyn eframe::Storage, key: String, value: String) -> bool {
        if self.written.get(&key) == Some(&value) {
            return false;
        }
        storage.set_string(&key, value.clone());
        self.written.insert(key, value);
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::apps::ask::AskApp;
    use crate::apps::notes::NotesApp;
    use eframe::egui::{Rect, Vec2, pos2};

    /// Storage kept in memory, counting how often it is flushed.
    #[derive(Default)]
    struct Memory {
        strings: HashMap<String, String>,
        flushes: usize,
    }

    impl eframe::Storage for Memory {
        fn get_string(&self, key: &str) -> Option<String> {
            self.strings.get(key).cloned()
        }

        fn set_string(&mut self, key: &str, value: String) {
            self.strings.insert(key.to_owned(), value);
        }

        fn remove_string(&mut self, key: &str) {
            self.strings.remove(key);
        }

        fn flush(&mut self) {
            self.flushes += 1;
        }
    }

    fn apps() -> Registry {
        Registry::new(vec![Box::new(NotesApp::new()), Box::new(AskApp::new())])
    }

    /// Starts an item in the microapp named `name` and shows it on `stage`.
    fn show(apps: &mut Registry, stage: &mut Stage, name: &str, at: Pos2) -> ViewTarget {
        let app = apps.find(name).unwrap();
        let item = apps.get_mut(app).unwrap().create();
        let target = ViewTarget { app, item };
        let mut bubble = apps.bubble_for(target, true).unwrap();
        bubble.center = at;
        stage.add(bubble);
        target
    }

    #[test]
    fn bubbles_and_items_come_back_in_place() {
        let center = pos2(550.0, 375.0);
        let (mut apps, mut stage) = (apps(), Stage::new());
        let note = show(&mut apps, &mut stage, "notes", pos2(300.0, 200.0));
        let chat = show(&mut apps, &mut stage, "ask", pos2(700.0, 500.0));
        stage.toggle_open(1);
        let mut storage = Memory::default();
        Autosave::new().save(&mut storage, &apps, &stage, center);

        // A bigger window: everything keeps its place relative to the center.
        let (mut restored_apps, mut restored) = (self::apps(), Stage::new());
        let new_center = pos2(800.0, 500.0);
        restore(
            Some(&storage),
            &mut restored_apps,
            &mut restored,
            new_center,
        );
        let bubbles = restored.bubbles();
        assert_eq!(bubbles.len(), 2);
        assert_eq!((bubbles[0].target, bubbles[1].target), (note, chat));
        assert_eq!(
            bubbles[0].center,
            new_center + (pos2(300.0, 200.0) - center)
        );
        assert!(!bubbles[0].open && bubbles[1].is_fully_open());
        assert!(restored_apps.has(note) && restored_apps.has(chat));
    }

    #[test]
    fn swallowed_bubbles_and_their_items_count_as_deleted() {
        let center = pos2(550.0, 375.0);
        let (mut apps, mut stage) = (apps(), Stage::new());
        let kept = show(&mut apps, &mut stage, "notes", pos2(300.0, 200.0));
        let eaten = show(&mut apps, &mut stage, "notes", pos2(600.0, 200.0));
        let eaten_bubble = stage.bubbles()[1].id;
        stage.swallow(eaten_bubble, pos2(1000.0, 700.0));
        let mut storage = Memory::default();
        Autosave::new().save(&mut storage, &apps, &stage, center);

        let (mut restored_apps, mut restored) = (self::apps(), Stage::new());
        restore(Some(&storage), &mut restored_apps, &mut restored, center);
        assert_eq!(restored.bubbles().len(), 1);
        assert!(restored_apps.has(kept));
        assert!(!restored_apps.has(eaten), "kept an item no bubble showed");
    }

    #[test]
    fn only_changes_are_written_and_drifting_is_not_one() {
        let center = pos2(550.0, 375.0);
        let canvas = Rect::from_center_size(center, Vec2::splat(2000.0));
        let (mut apps, mut stage) = (apps(), Stage::new());
        show(&mut apps, &mut stage, "notes", pos2(300.0, 200.0));
        let mut storage = Memory::default();
        let mut autosave = Autosave::new();
        autosave.save(&mut storage, &apps, &stage, center);
        assert_eq!(storage.flushes, 1);

        for frame in 0..120 {
            stage.step(canvas, f64::from(frame) / 60.0, 1.0 / 60.0);
        }
        autosave.save(&mut storage, &apps, &stage, center);
        assert_eq!(storage.flushes, 1, "saved a bubble drifting");

        autosave.moved();
        autosave.save(&mut storage, &apps, &stage, center);
        assert_eq!(storage.flushes, 2, "did not save a bubble moved on purpose");

        show(&mut apps, &mut stage, "ask", pos2(700.0, 500.0));
        autosave.save(&mut storage, &apps, &stage, center);
        assert_eq!(storage.flushes, 3, "did not save a new bubble");
    }
}
