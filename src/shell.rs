//! The shell: the whole app inside the window. It routes input between the
//! stage of bubbles, the turtle and its menu, the octopus, and the
//! microapps, and paints them all.

use eframe::egui::{self, CursorIcon, Pos2, Sense, ViewportCommand};

use crate::apps::ask::AskApp;
use crate::apps::notes::NotesApp;
use crate::desktop;
use crate::microapp::{AppId, Context, Effect, Registry, View, ViewTarget};
use crate::sprite::octopus::Octopus;
use crate::sprite::turtle::Turtle;
use crate::stage::Stage;
use crate::view::bubble::Bubble;
use crate::view::render;

/// Size of the window in `--windowed` mode. The app starts out laid out for it
/// and recenters on the real window in the first frame.
pub const WINDOWED_SIZE: egui::Vec2 = egui::vec2(1100.0, 750.0);
/// How far a bubble must be dragged before the octopus comes up, so nudging
/// a bubble into place does not call it.
const SUMMON_DISTANCE: f32 = 40.0;
/// Storage key for the Claude API key the web version asks for. The desktop
/// version reads `ANTHROPIC_API_KEY` from `.env` instead and stores nothing.
#[cfg(target_arch = "wasm32")]
const API_KEY_KEY: &str = "anthropic_api_key";

/// The turtle's menu, opened by clicking it with either button.
struct TurtleMenu {
    /// Top-left corner, where the pointer was when it opened.
    pos: Pos2,
    /// Where it was drawn last frame, for telling presses on it from presses outside.
    rect: Option<egui::Rect>,
}

impl TurtleMenu {
    fn contains(&self, p: Pos2) -> bool {
        self.rect.is_some_and(|rect| rect.contains(p))
    }
}

pub struct HonuApp {
    /// The bubbles, each showing an item of one of the microapps below.
    stage: Stage,
    apps: Registry,
    turtle: Turtle,
    /// Deletes the bubbles dropped on it.
    octopus: Octopus,
    /// True while the turtle is being dragged.
    dragging_turtle: bool,
    /// Set when pressing the turtle closed its menu, so the click that press
    /// ends in does not open the menu again.
    menu_dismissed: bool,
    /// The turtle's menu, while open.
    menu: Option<TurtleMenu>,
    /// The key for asking Claude, once known.
    api_key: Option<String>,
    /// Whether the window floats on the real desktop rather than showing a wallpaper.
    floating: bool,
    /// Whether clicks currently pass through the window to the apps below.
    passthrough: bool,
    /// The canvas in the previous frame, used to keep the bubbles centered when
    /// the window changes size.
    last_canvas: Option<egui::Rect>,
}

impl HonuApp {
    pub fn new(floating: bool, storage: Option<&dyn eframe::Storage>) -> Self {
        let mut turtle = Turtle::new();
        let saved = storage.and_then(|storage| storage.get_string(turtle_key(floating)));
        if let Some(offset) = saved.as_deref().and_then(parse_offset) {
            // Start out laid out for the windowed size; the first frame moves
            // the turtle to the real window.
            turtle.set_offset_from((WINDOWED_SIZE / 2.0).to_pos2(), offset);
        }
        Self {
            stage: Stage::new(),
            apps: Registry::new(vec![Box::new(NotesApp::new()), Box::new(AskApp::new())]),
            turtle,
            octopus: Octopus::new(),
            dragging_turtle: false,
            menu_dismissed: false,
            menu: None,
            api_key: initial_api_key(storage),
            floating,
            passthrough: false,
            last_canvas: None,
        }
    }

    /// Index of the topmost bubble under `p`, if any. The turtle and the
    /// octopus sit above all bubbles, and bubbles still flying out of the
    /// turtle cannot be grabbed.
    fn hit_test(&self, p: Pos2) -> Option<usize> {
        if self.turtle.contains(p) || self.octopus.contains(p) {
            return None;
        }
        self.stage.hit_test(p)
    }

    /// Lets clicks through to the apps below unless the mouse is on a bubble
    /// or the turtle.
    fn update_passthrough(&mut self, ui: &egui::Ui) {
        let Some(window) = ui.input(|i| i.viewport().inner_rect) else {
            return;
        };
        let Some(cursor) = desktop::global_cursor() else {
            return;
        };
        let p = cursor - window.min.to_vec2();
        // An open menu takes every click, like a native menu: a click outside
        // it only closes it.
        let on_bubble = self.menu.is_some()
            || self.stage.is_dragging()
            || self.dragging_turtle
            || self.hit_test(p).is_some()
            || self.turtle.contains(p)
            || self.octopus.contains(p);
        if self.passthrough == on_bubble {
            self.passthrough = !on_bubble;
            ui.ctx()
                .send_viewport_cmd(ViewportCommand::MousePassthrough(self.passthrough));
        }
    }

    /// Starts a new item in microapp `id` and has the turtle spit out a
    /// bubble showing it, which opens into its panel when it lands.
    fn start(&mut self, id: AppId, canvas: egui::Rect, time: f64) {
        let Some(app) = self.apps.get_mut(id) else {
            return;
        };
        let item = app.create();
        let look = app.appearance(item);
        let target = ViewTarget { app: id, item };
        let mut bubble = Bubble::new(target, Pos2::ZERO, look.radius, look.color, look.glass);
        if let Some(height) = look.panel_height {
            bubble = bubble.with_panel_height(height);
        }
        bubble.label = app.title(item);
        bubble.state = app.new_view(item);
        let mouth = self.turtle.spit(time);
        self.stage.spit_panel(bubble, mouth, canvas, time);
    }

    /// Has the octopus spit back the bubble it swallowed last, if it still can.
    fn undo_delete(&mut self, time: f64) {
        if let Some((bubble, home)) = self.octopus.spit_back(time) {
            self.stage.spit_back(bubble, self.octopus.mouth(), home);
        }
    }

    /// Deletes an item for good once no bubble shows it anymore.
    fn delete_if_unseen(&mut self, target: ViewTarget) {
        if !self.stage.shows(target) {
            self.apps.remove(target);
        }
    }

    /// Carries out what the microapps asked of their bubbles.
    fn apply(&mut self, effects: Vec<Effect>) {
        for effect in effects {
            match effect {
                Effect::Gesture { target, gesture } => self.stage.play(target, gesture),
            }
        }
    }

    /// Records where the turtle rests, if it has been dragged.
    fn store_turtle(&self, storage: &mut dyn eframe::Storage) {
        let offset = self
            .last_canvas
            .and_then(|canvas| self.turtle.offset_from(canvas.center()));
        if let Some(offset) = offset {
            storage.set_string(
                turtle_key(self.floating),
                format!("{} {}", offset.x, offset.y),
            );
        }
    }
}

impl eframe::App for HonuApp {
    fn save(&mut self, storage: &mut dyn eframe::Storage) {
        self.store_turtle(storage);
    }

    fn persist_egui_memory(&self) -> bool {
        false
    }

    fn clear_color(&self, visuals: &egui::Visuals) -> [f32; 4] {
        if self.floating {
            [0.0; 4]
        } else {
            visuals.panel_fill.to_normalized_gamma_f32()
        }
    }

    fn ui(&mut self, ui: &mut egui::Ui, frame: &mut eframe::Frame) {
        egui::CentralPanel::default()
            .frame(egui::Frame::NONE)
            .show(ui, |ui| {
                let (response, painter) =
                    ui.allocate_painter(ui.available_size(), Sense::click_and_drag());
                let canvas = response.rect;
                let (time, dt) = ui.input(|i| (i.time, i.stable_dt.min(1.0 / 30.0)));

                if self.last_canvas.is_none() && self.floating {
                    // Fill the screen except the menu bar and Dock. Asking for this when
                    // the window is created has no effect on a borderless window on macOS.
                    ui.ctx().send_viewport_cmd(ViewportCommand::Maximized(true));
                }
                // Keep everything centered when the window changes size, starting
                // from the windowed size the app is first laid out for.
                let last_center = self
                    .last_canvas
                    .map_or((WINDOWED_SIZE / 2.0).to_pos2(), |rect| rect.center());
                let offset = canvas.center() - last_center;
                if offset != egui::Vec2::ZERO {
                    self.stage.translate(offset);
                    self.turtle.translate(offset);
                    self.octopus.translate(offset);
                }
                self.last_canvas = Some(canvas);
                self.turtle.place(canvas, time);
                // The octopus comes up once a bubble has been dragged a little way.
                let summoned = self
                    .stage
                    .drag_distance()
                    .is_some_and(|distance| distance > SUMMON_DISTANCE);
                self.octopus.summon(summoned);
                for gone in self.octopus.update(canvas, self.turtle.center(), time, dt) {
                    if let Some(bubble) = self.stage.remove(gone) {
                        self.delete_if_unseen(bubble.target);
                    }
                }
                if self.floating {
                    self.update_passthrough(ui);
                    // A borderless window has no close button, so handle ⌘Q ourselves.
                    if ui.input(|i| i.modifiers.command && i.key_pressed(egui::Key::Q)) {
                        ui.ctx().send_viewport_cmd(ViewportCommand::Close);
                    }
                }

                // Pressing anywhere outside the menu, or Escape, closes it.
                let any_pressed_at = ui.input(|i| {
                    i.pointer
                        .any_pressed()
                        .then(|| i.pointer.interact_pos())
                        .flatten()
                });
                if let Some(menu) = &self.menu {
                    let outside = any_pressed_at.is_some_and(|p| !menu.contains(p));
                    if outside || ui.input(|i| i.key_pressed(egui::Key::Escape)) {
                        self.menu = None;
                        // Clicking the turtle again closes the menu, like a toggle.
                        self.menu_dismissed =
                            any_pressed_at.is_some_and(|p| self.turtle.contains(p));
                    }
                }
                let on_menu = |p: Pos2| self.menu.as_ref().is_some_and(|menu| menu.contains(p));

                // Any press on a bubble brings it to the front, including presses on
                // an opened bubble's content, which the canvas response never sees.
                let pressed_at = ui
                    .input(|i| {
                        i.pointer
                            .primary_pressed()
                            .then(|| i.pointer.interact_pos())
                            .flatten()
                    })
                    .filter(|&p| !on_menu(p));
                if let Some(i) = pressed_at.and_then(|p| self.hit_test(p)) {
                    self.stage.raise(i);
                }

                let pointer = ui.input(|i| i.pointer.latest_pos());

                if response.drag_started() {
                    let origin = ui.input(|i| i.pointer.press_origin());
                    if origin.is_some_and(|p| self.turtle.contains(p)) {
                        self.dragging_turtle = true;
                    } else if let Some(i) = origin.and_then(|p| self.hit_test(p)) {
                        self.stage.start_drag(i);
                    }
                }
                if self.dragging_turtle {
                    self.turtle.move_by(response.drag_delta());
                    // Place it again so it follows the pointer this frame.
                    self.turtle.place(canvas, time);
                    if response.drag_stopped() {
                        self.dragging_turtle = false;
                        // Save right away: quitting with ⌘Q or from the Dock ends the
                        // app without calling `save`.
                        if let Some(storage) = frame.storage_mut() {
                            self.store_turtle(storage);
                            storage.flush();
                        }
                    }
                }
                if self.stage.is_dragging() {
                    // Holding a bubble over the octopus shrinks it, and letting go
                    // there deletes it. Where the pointer is decides, not where a
                    // thrown bubble ends up, so only a deliberate drop deletes.
                    let over_octopus = pointer.is_some_and(|p| self.octopus.in_reach(p));
                    self.octopus.set_eager(over_octopus);
                    let velocity = ui.input(|i| i.pointer.velocity());
                    self.stage
                        .drag(response.drag_delta(), velocity, over_octopus);
                    if response.drag_stopped() {
                        self.octopus.set_eager(false);
                        if let Some((bubble, home)) = self.stage.end_drag()
                            && over_octopus
                        {
                            let mouth = self.octopus.swallow(bubble, home, time);
                            self.stage.swallow(bubble, mouth);
                        }
                    }
                }

                // Clicking the turtle with either button opens its menu where the
                // pointer is. A tap counts too, so it works on touch screens.
                let turtle_clicked_at = (response.clicked() || response.secondary_clicked())
                    .then(|| response.interact_pointer_pos())
                    .flatten()
                    .filter(|&p| self.turtle.contains(p));
                let clicked_octopus = response.clicked()
                    && response
                        .interact_pointer_pos()
                        .is_some_and(|p| self.octopus.contains(p));
                // ⌘Z (Ctrl+Z elsewhere) also undoes, unless a text field wants it.
                let undo_key = ui.input(|i| i.modifiers.command && i.key_pressed(egui::Key::Z))
                    && ui.memory(|m| m.focused().is_none());
                if clicked_octopus || undo_key {
                    self.undo_delete(time);
                }
                if let Some(pos) = turtle_clicked_at
                    && !self.menu_dismissed
                {
                    self.turtle.hop(time);
                    self.menu = Some(TurtleMenu { pos, rect: None });
                }
                if ui.input(|i| i.pointer.any_released()) {
                    self.menu_dismissed = false;
                }

                if response.double_clicked() {
                    let pos = response.interact_pointer_pos();
                    if let Some(i) = pos.and_then(|p| self.hit_test(p)) {
                        self.stage.toggle_open(i);
                    }
                }

                // Let the microapps catch up, then show on each bubble what its
                // item is doing: an Ask bubble breathes while Claude works.
                let mut effects = Vec::new();
                self.apps.update(&mut effects, &mut self.api_key);
                for bubble in self.stage.bubbles_mut() {
                    bubble.label = self.apps.title(bubble.target);
                    bubble.set_busy(self.apps.is_busy(bubble.target));
                }
                self.apply(effects);
                self.stage.step(canvas, time, dt);
                // Bubbles are always drifting, so keep animating.
                ui.ctx().request_repaint();

                let hovered = response.hover_pos().and_then(|p| self.hit_test(p));
                if self.stage.is_dragging() || self.dragging_turtle {
                    ui.ctx().set_cursor_icon(CursorIcon::Grabbing);
                } else if hovered.is_some() {
                    ui.ctx().set_cursor_icon(CursorIcon::Grab);
                } else if response.hover_pos().is_some_and(|p| {
                    self.turtle.contains(p) || (self.octopus.can_undo() && self.octopus.contains(p))
                }) {
                    ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
                }

                if !self.floating {
                    render::paint_background(&painter, canvas);
                }
                let key_before = self.api_key.clone();
                let mut effects = Vec::new();
                let dragging = self.stage.is_dragging();
                let front = self.stage.front();
                for (i, bubble) in self.stage.bubbles_mut().iter_mut().enumerate() {
                    if bubble.is_swallowed() {
                        // Out of sight in the octopus's stomach.
                        continue;
                    }
                    render::paint_bubble(&painter, bubble);
                    if bubble.is_fully_open() {
                        // Only the front bubble's content takes input, so a bubble lying
                        // on top of another's content can still be grabbed.
                        let interactive = Some(i) == front && !dragging;
                        let cx = (&mut effects, &mut self.api_key);
                        content_ui(ui, bubble, interactive, &mut self.apps, cx);
                    }
                }
                self.apply(effects);
                if self.api_key != key_before {
                    remember_api_key(frame, self.api_key.as_deref());
                }
                self.octopus.paint(&painter, time);
                self.turtle.paint(&painter);
                let chosen = self
                    .menu
                    .as_mut()
                    .and_then(|menu| turtle_menu_ui(ui.ctx(), menu, &self.apps));
                if let Some(item) = chosen {
                    self.menu = None;
                    match item {
                        MenuItem::Start(id) => self.start(id, canvas, time),
                        #[cfg(not(target_arch = "wasm32"))]
                        MenuItem::Exit => ui.ctx().send_viewport_cmd(ViewportCommand::Close),
                    }
                }
            });
    }
}

/// An item of the turtle's menu.
enum MenuItem {
    /// Starts a new item in a microapp.
    Start(AppId),
    /// Quitting means nothing in a web page.
    #[cfg(not(target_arch = "wasm32"))]
    Exit,
}

/// Shows the turtle's menu and returns the item chosen this frame, if any.
/// Each microapp in `apps` gets an item, and Exit comes last.
fn turtle_menu_ui(ctx: &egui::Context, menu: &mut TurtleMenu, apps: &Registry) -> Option<MenuItem> {
    let area = egui::Area::new(egui::Id::unique("turtle_menu"))
        .order(egui::Order::Foreground)
        .fixed_pos(menu.pos)
        .show(ctx, |ui| {
            egui::Frame::menu(ui.style())
                .show(ui, |ui| {
                    // As wide as its text, with no button frame until hovered.
                    let item = |text| egui::Button::new(text).frame_when_inactive(false);
                    let mut chosen = None;
                    for app in apps.iter() {
                        if ui.add(item(app.menu_label())).clicked() {
                            chosen = Some(MenuItem::Start(app.id()));
                        }
                    }
                    #[cfg(not(target_arch = "wasm32"))]
                    if ui.add(item("Exit")).clicked() {
                        chosen = Some(MenuItem::Exit);
                    }
                    chosen
                })
                .inner
        });
    menu.rect = Some(area.response.rect);
    area.inner
}

/// The desktop version takes the key from `ANTHROPIC_API_KEY`, which may be
/// set in a `.env` file in or above the working directory.
#[cfg(not(target_arch = "wasm32"))]
fn initial_api_key(_storage: Option<&dyn eframe::Storage>) -> Option<String> {
    dotenvy::dotenv().ok();
    std::env::var("ANTHROPIC_API_KEY")
        .ok()
        .filter(|key| !key.trim().is_empty())
}

/// The web version uses the key pasted into an Ask bubble earlier, kept in
/// the browser's local storage.
#[cfg(target_arch = "wasm32")]
fn initial_api_key(storage: Option<&dyn eframe::Storage>) -> Option<String> {
    storage.and_then(|storage| storage.get_string(API_KEY_KEY))
}

/// Saves a key just pasted into an Ask bubble, or forgets one the API
/// refused. Only the web version keeps it; the desktop version forgets it on
/// quit, so it never lands in a file.
#[cfg(target_arch = "wasm32")]
fn remember_api_key(frame: &mut eframe::Frame, key: Option<&str>) {
    let Some(storage) = frame.storage_mut() else {
        return;
    };
    match key {
        Some(key) => storage.set_string(API_KEY_KEY, key.to_owned()),
        None => storage.remove_string(API_KEY_KEY),
    }
    storage.flush();
}

#[cfg(not(target_arch = "wasm32"))]
fn remember_api_key(_frame: &mut eframe::Frame, _key: Option<&str>) {}

/// Storage key for where the turtle rests, kept apart for the desktop and
/// for `--windowed`, whose windows differ in size.
fn turtle_key(floating: bool) -> &'static str {
    if floating {
        "turtle_offset"
    } else {
        "turtle_offset_windowed"
    }
}

/// Parses an offset saved as "x y".
fn parse_offset(text: &str) -> Option<egui::Vec2> {
    let mut parts = text.split_whitespace().map(str::parse::<f32>);
    match (parts.next(), parts.next(), parts.next()) {
        (Some(Ok(x)), Some(Ok(y)), None) if x.is_finite() && y.is_finite() => {
            Some(egui::vec2(x, y))
        }
        _ => None,
    }
}

/// Draws an opened bubble's content inside its panel, below the title, from
/// the microapp that keeps it. What the microapp asks for goes into `effects`.
fn content_ui(
    ui: &mut egui::Ui,
    bubble: &mut Bubble,
    interactive: bool,
    apps: &mut Registry,
    (effects, api_key): (&mut Vec<Effect>, &mut Option<String>),
) {
    let ViewTarget { app, item } = bubble.target;
    let Some(microapp) = apps.get_mut(app) else {
        return;
    };
    let body = bubble.shape().rect().shrink(22.0);
    let view = View {
        bubble: bubble.id,
        rect: body.with_min_y(body.top() + 34.0),
        text_color: render::text_color(bubble),
        interactive,
        state: bubble.state.as_mut(),
    };
    let mut cx = Context::new(app, effects, api_key);
    if let Some(height) = microapp.ui(item, ui, view, &mut cx) {
        bubble.set_panel_height(height);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn saved_offset_round_trips() {
        let offset = egui::vec2(-412.5, 230.0);
        let text = format!("{} {}", offset.x, offset.y);
        assert_eq!(parse_offset(&text), Some(offset));
        assert_eq!(parse_offset("1 2 3"), None);
        assert_eq!(parse_offset("NaN 2"), None);
        assert_eq!(parse_offset(""), None);
    }
}
