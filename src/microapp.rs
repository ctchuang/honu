//! Microapps: Notes, Ask AI, and whatever comes next. Each microapp keeps its
//! own data (the model) and the logic around it (the controller). Bubbles on
//! the desktop are only views: each one shows one item of one microapp and
//! points at it by id, so a microapp can have any number of bubbles.

use std::any::Any;

use eframe::egui::{self, Color32, Rect};

use crate::services::Services;
use crate::view::bubble::{BubbleId, Gesture};

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

/// What one bubble keeps for itself about the item it shows, such as a draft
/// or whether its text field still has to take the focus, apart from the
/// item's data. Each microapp makes its own kind (`MicroApp::new_view`).
pub type ViewState = Box<dyn Any>;

/// Where and how an item's content is drawn in an open bubble.
pub struct View<'a> {
    /// The bubble drawn in; salting widget ids with it keeps the widgets of
    /// two bubbles apart even when they show the same item.
    pub bubble: BubbleId,
    /// The panel's body, below its title.
    pub rect: Rect,
    pub text_color: Color32,
    /// Whether the content takes input; only the front bubble's does.
    pub interactive: bool,
    /// The bubble's own state, made by the microapp's `new_view`.
    pub state: &'a mut dyn Any,
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
    pub services: &'a mut Services,
}

impl<'a> Context<'a> {
    /// A context for `app`, collecting what it asks for in `effects`.
    pub fn new(app: AppId, effects: &'a mut Vec<Effect>, services: &'a mut Services) -> Self {
        Self {
            app,
            effects,
            services,
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

/// A microapp: it keeps its items and draws them in the bubbles showing them.
pub trait MicroApp {
    fn id(&self) -> AppId;

    /// The turtle's menu item that starts a new item.
    fn menu_label(&self) -> &'static str;

    /// Starts a new item.
    fn create(&mut self) -> ItemId;

    fn appearance(&self, item: ItemId) -> Appearance;

    /// The state a new bubble showing `item` starts with.
    fn new_view(&self, _item: ItemId) -> ViewState {
        Box::new(())
    }

    /// The label of the bubbles showing `item`.
    fn title(&self, item: ItemId) -> String;

    /// Whether `item` is being worked on, which makes its bubbles breathe.
    fn is_busy(&self, _item: ItemId) -> bool {
        false
    }

    /// Catches up on work done in the background. Called every frame.
    fn update(&mut self, _cx: &mut Context) {}

    /// Draws `item` in an open bubble. Returns the panel height that fits it,
    /// for a microapp that sizes its panels to their content.
    fn ui(&mut self, item: ItemId, ui: &mut egui::Ui, view: View, cx: &mut Context) -> Option<f32>;

    /// Deletes `item` for good.
    fn remove(&mut self, item: ItemId);
}

/// The microapps, in the order the turtle's menu lists them.
pub struct Registry {
    apps: Vec<Box<dyn MicroApp>>,
}

impl Registry {
    pub fn new(apps: Vec<Box<dyn MicroApp>>) -> Self {
        Self { apps }
    }

    pub fn iter(&self) -> impl Iterator<Item = &dyn MicroApp> {
        self.apps.iter().map(|app| app.as_ref())
    }

    pub fn get_mut(&mut self, id: AppId) -> Option<&mut (dyn MicroApp + 'static)> {
        self.apps
            .iter_mut()
            .find(|app| app.id() == id)
            .map(|app| app.as_mut())
    }

    fn get(&self, id: AppId) -> Option<&dyn MicroApp> {
        self.iter().find(|app| app.id() == id)
    }

    /// The label of the bubbles showing `target`.
    pub fn title(&self, target: ViewTarget) -> String {
        self.get(target.app)
            .map(|app| app.title(target.item))
            .unwrap_or_default()
    }

    pub fn is_busy(&self, target: ViewTarget) -> bool {
        self.get(target.app)
            .is_some_and(|app| app.is_busy(target.item))
    }

    /// Lets every microapp catch up, collecting what they ask for in `effects`.
    pub fn update(&mut self, effects: &mut Vec<Effect>, services: &mut Services) {
        for app in &mut self.apps {
            app.update(&mut Context::new(app.id(), effects, services));
        }
    }

    pub fn remove(&mut self, target: ViewTarget) {
        if let Some(app) = self.get_mut(target.app) {
            app.remove(target.item);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A microapp whose items are counters, busy while odd.
    #[derive(Default)]
    struct Counters {
        items: std::collections::BTreeMap<ItemId, u32>,
        ids: ItemIds,
    }

    impl MicroApp for Counters {
        fn id(&self) -> AppId {
            AppId("counters")
        }

        fn menu_label(&self) -> &'static str {
            "Count"
        }

        fn create(&mut self) -> ItemId {
            let id = self.ids.next();
            self.items.insert(id, 0);
            id
        }

        fn appearance(&self, _item: ItemId) -> Appearance {
            Appearance {
                color: Color32::WHITE,
                glass: false,
                radius: 50.0,
                panel_height: None,
            }
        }

        fn title(&self, item: ItemId) -> String {
            self.items
                .get(&item)
                .map_or_else(String::new, u32::to_string)
        }

        fn is_busy(&self, item: ItemId) -> bool {
            self.items.get(&item).is_some_and(|n| n % 2 == 1)
        }

        fn update(&mut self, cx: &mut Context) {
            for (&item, n) in &mut self.items {
                *n += 1;
                cx.play(item, Gesture::Rise);
            }
        }

        fn ui(&mut self, _: ItemId, _: &mut egui::Ui, _: View, _: &mut Context) -> Option<f32> {
            None
        }

        fn remove(&mut self, item: ItemId) {
            self.items.remove(&item);
        }
    }

    #[test]
    fn registry_routes_to_the_microapp_of_each_target() {
        let mut apps = Registry::new(vec![Box::new(Counters::default())]);
        let id = AppId("counters");
        let labels: Vec<_> = apps.iter().map(|app| app.menu_label()).collect();
        assert_eq!(labels, ["Count"]);

        let item = apps.get_mut(id).unwrap().create();
        let target = ViewTarget { app: id, item };
        assert_eq!(
            (apps.title(target).as_str(), apps.is_busy(target)),
            ("0", false)
        );

        let mut effects = Vec::new();
        apps.update(&mut effects, &mut Services::with_api_key(None));
        let rise = Effect::Gesture {
            target,
            gesture: Gesture::Rise,
        };
        assert_eq!(effects, vec![rise]);
        assert_eq!(
            (apps.title(target).as_str(), apps.is_busy(target)),
            ("1", true)
        );

        apps.remove(target);
        assert_eq!(apps.title(target), "");
        let unknown = ViewTarget {
            app: AppId("unknown"),
            item,
        };
        assert!(apps.get_mut(unknown.app).is_none());
        assert_eq!(apps.title(unknown), "");
    }
}
