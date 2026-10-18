//! Microapps: Notes, Ask AI, and whatever comes next. Each microapp keeps its
//! own data (the model) and the logic around it (the controller). Bubbles on
//! the desktop are only views: each one shows one item of one microapp and
//! points at it by id, so a microapp can have any number of bubbles.

use eframe::egui::{Color32, Rect};

use crate::bubble::Gesture;

/// Names a microapp.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct AppId(pub &'static str);

/// One item of a microapp's data, such as one note; unique within the app.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct ItemId(pub u64);

/// What a bubble shows: one item of one microapp.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct ViewTarget {
    pub app: AppId,
    pub item: ItemId,
}

#[cfg(test)]
impl ViewTarget {
    /// A target for bubbles in tests, which show nothing.
    pub const TEST: Self = Self {
        app: AppId("test"),
        item: ItemId(0),
    };
}

/// How the bubbles of a microapp's item look.
pub struct Appearance {
    pub color: Color32,
    /// Whether they are see-through glass rather than opaque.
    pub glass: bool,
    /// Half the side of a closed bubble.
    pub radius: f32,
    /// Height of the opened panel, if not the usual one.
    pub panel_height: Option<f32>,
}

/// Hands out a microapp's item ids.
#[derive(Default)]
pub struct ItemIds {
    next: u64,
}

impl ItemIds {
    pub fn next(&mut self) -> ItemId {
        self.next += 1;
        ItemId(self.next)
    }
}

/// Where and how an item's content is drawn in an open bubble.
pub struct View {
    /// The panel's body, below its title.
    pub rect: Rect,
    pub text_color: Color32,
    /// Whether the content takes input; only the front bubble's does.
    pub interactive: bool,
}

/// Something a microapp asks of the bubbles showing its items.
#[derive(Debug, PartialEq)]
pub enum Effect {
    /// Every bubble showing `target` plays `gesture`.
    Gesture {
        target: ViewTarget,
        gesture: Gesture,
    },
}

/// What a microapp gets to work with: the shared services, and a way to ask
/// things of the bubbles showing its items.
pub struct Context<'a> {
    app: AppId,
    effects: &'a mut Vec<Effect>,
    /// The key for asking Claude, once known. A microapp may ask the user for
    /// one and set it here, or clear one the API refused.
    pub api_key: &'a mut Option<String>,
}

impl<'a> Context<'a> {
    /// A context for `app`, collecting what it asks for in `effects`.
    pub fn new(app: AppId, effects: &'a mut Vec<Effect>, api_key: &'a mut Option<String>) -> Self {
        Self {
            app,
            effects,
            api_key,
        }
    }

    /// Has every bubble showing `item` play `gesture`.
    pub fn play(&mut self, item: ItemId, gesture: Gesture) {
        let target = ViewTarget {
            app: self.app,
            item,
        };
        self.effects.push(Effect::Gesture { target, gesture });
    }
}
