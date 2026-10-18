//! Microapps: Notes, Ask AI, and whatever comes next. Each microapp keeps its
//! own data (the model) and the logic around it (the controller). Bubbles on
//! the desktop are only views: each one shows one item of one microapp and
//! points at it by id, so a microapp can have any number of bubbles.

use eframe::egui::Color32;

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
