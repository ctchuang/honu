mod ask;
mod bubble;
mod claude;
mod desktop;
mod note;
mod octopus;
mod physics;
mod render;
mod turtle;

use bubble::{Bubble, Content, Gesture};
use eframe::egui::{self, Align2, Color32, CursorIcon, FontId, Pos2, Sense, ViewportCommand};
use octopus::Octopus;
use turtle::Turtle;

/// Size of the window in `--windowed` mode. The app starts out laid out for it
/// and recenters on the real window in the first frame.
const WINDOWED_SIZE: egui::Vec2 = egui::vec2(1100.0, 750.0);
/// Seconds the turtle must be held, without dragging, to open its menu.
const LONG_PRESS_SECONDS: f64 = 0.5;
/// How far a bubble must be dragged before the octopus comes up, so nudging
/// a bubble into place does not call it.
const SUMMON_DISTANCE: f32 = 40.0;
/// A soft, slightly warm white for the opaque bubbles.
const PAPER: Color32 = Color32::from_rgb(250, 249, 246);
/// The pale yellow of a sticky note, for Note bubbles.
const NOTE_YELLOW: Color32 = Color32::from_rgb(255, 236, 150);
/// Size of a closed bubble the turtle spits out from its menu.
const SPAT_RADIUS: f32 = 60.0;
/// How far a new panel steps aside from one already in its place.
const CASCADE_STEP: f32 = 28.0;
/// Most steps aside a new panel takes before landing where it is.
const CASCADE_LIMIT: usize = 10;
/// Storage key for the Claude API key the web version asks for. The desktop
/// version reads `ANTHROPIC_API_KEY` from `.env` instead and stores nothing.
#[cfg(target_arch = "wasm32")]
const API_KEY_KEY: &str = "anthropic_api_key";

#[cfg(not(target_arch = "wasm32"))]
fn main() -> eframe::Result {
    // By default the bubbles float on the real desktop; `--windowed` shows them in
    // an ordinary window with its own wallpaper instead.
    let floating = !std::env::args().any(|arg| arg == "--windowed");
    let icon = eframe::icon_data::from_png_bytes(include_bytes!("../assets/icon.png"))
        .expect("the bundled app icon is a valid PNG");
    let base = egui::ViewportBuilder::default().with_icon(icon);
    let viewport = if floating {
        base.with_transparent(true)
            .with_decorations(false)
            .with_has_shadow(false)
            .with_window_level(egui::WindowLevel::AlwaysOnTop)
            .with_inner_size(WINDOWED_SIZE)
    } else {
        base.with_inner_size(WINDOWED_SIZE)
    };
    let options = eframe::NativeOptions {
        viewport,
        // Only the turtle's place is saved; the window is laid out on every launch.
        persist_window: false,
        ..Default::default()
    };
    eframe::run_native(
        "Honu",
        options,
        Box::new(move |cc| Ok(Box::new(HonuApp::new(floating, cc.storage)))),
    )
}

/// The web version runs in the `<canvas id="honu">` of `web/index.html`, like
/// `--windowed`: it paints its own wallpaper and cannot float on the desktop.
#[cfg(target_arch = "wasm32")]
fn main() {
    use eframe::wasm_bindgen::JsCast as _;

    wasm_bindgen_futures::spawn_local(async {
        let canvas = eframe::web_sys::window()
            .and_then(|window| window.document())
            .and_then(|document| document.get_element_by_id("honu"))
            .and_then(|element| {
                element
                    .dyn_into::<eframe::web_sys::HtmlCanvasElement>()
                    .ok()
            })
            .expect("web/index.html has a <canvas id=\"honu\">");
        eframe::WebRunner::new()
            .start(
                canvas,
                eframe::WebOptions::default(),
                Box::new(|cc| Ok(Box::new(HonuApp::new(false, cc.storage)))),
            )
            .await
            .expect("failed to start Honu");
    });
}

/// The turtle's menu, opened by a right-click or a long press on it.
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

struct HonuApp {
    /// Bubbles in back-to-front paint order; the last one is on top.
    bubbles: Vec<Bubble>,
    turtle: Turtle,
    /// Deletes the bubbles dropped on it.
    octopus: Octopus,
    /// True while the top bubble is being dragged.
    dragging: bool,
    /// Where the bubble being dragged was picked up, to return it there if the
    /// octopus has to spit it back.
    drag_home: Pos2,
    /// True while the turtle is being dragged.
    dragging_turtle: bool,
    /// When the primary button went down on the turtle, while it is still
    /// held and could become a long press.
    turtle_pressed_at: Option<f64>,
    /// Set when a long press opened the menu, so releasing the button does not
    /// also count as a click on the turtle.
    long_pressed: bool,
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
    fn new(floating: bool, storage: Option<&dyn eframe::Storage>) -> Self {
        let mut turtle = Turtle::new();
        let saved = storage.and_then(|storage| storage.get_string(turtle_key(floating)));
        if let Some(offset) = saved.as_deref().and_then(parse_offset) {
            // Start out laid out for the windowed size; the first frame moves
            // the turtle to the real window.
            turtle.set_offset_from((WINDOWED_SIZE / 2.0).to_pos2(), offset);
        }
        Self {
            bubbles: Vec::new(),
            turtle,
            octopus: Octopus::new(),
            dragging: false,
            drag_home: Pos2::ZERO,
            dragging_turtle: false,
            turtle_pressed_at: None,
            long_pressed: false,
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
        self.bubbles
            .iter()
            .rposition(|b| b.contains(p) && !b.is_spawning())
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
            || self.dragging
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

    /// Puts a new bubble on top, below a bubble being dragged, which must stay on top.
    fn add_bubble(&mut self, bubble: Bubble) {
        let index = self.bubbles.len() - usize::from(self.dragging);
        self.bubbles.insert(index, bubble);
    }

    /// Has the turtle spit out a new Note bubble, which opens for writing.
    fn spit_note_bubble(&mut self, canvas: egui::Rect, time: f64) {
        let bubble = Bubble::new("Note", Pos2::ZERO, SPAT_RADIUS, NOTE_YELLOW, false)
            .with_content(Content::Note(note::Note::new()));
        self.spit_panel(bubble, canvas, time);
    }

    /// Has the turtle spit out an Ask bubble, which opens into a panel for a question.
    fn spit_ask_bubble(&mut self, canvas: egui::Rect, time: f64) {
        let bubble = Bubble::new("Ask", Pos2::ZERO, SPAT_RADIUS, PAPER, false)
            .with_content(Content::Ask(ask::Ask::new()))
            .with_panel_height(ask::START_HEIGHT);
        self.spit_panel(bubble, canvas, time);
    }

    /// Has the turtle spit out `bubble`, which opens into its panel when it
    /// lands next to the turtle.
    fn spit_panel(&mut self, bubble: Bubble, canvas: egui::Rect, time: f64) {
        let mouth = self.turtle.spit(time);
        let mut bubble = bubble.open_on_landing();
        // Drift out of step with the other bubbles once closed.
        bubble.phase = (time % 100.0) as f32;
        // Land up and to the right of the mouth, with the whole panel on screen.
        let half = bubble.panel_target() / 2.0;
        let margin = egui::Vec2::splat(16.0);
        let lo = canvas.min + half + margin;
        let hi = (canvas.max - half - margin).max(lo);
        let mut place = (mouth + egui::vec2(half.x + 40.0, -half.y - 20.0)).clamp(lo, hi);
        // Open panels don't push each other aside, so step down and to the
        // right of any panel already landing there, as windows cascade.
        for _ in 0..CASCADE_LIMIT {
            let taken = self.bubbles.iter().any(|b| {
                b.is_or_will_be_open() && (b.destination() - place).length() < CASCADE_STEP
            });
            if !taken {
                break;
            }
            place = (place + egui::Vec2::splat(CASCADE_STEP)).clamp(lo, hi);
        }
        bubble.center = place;
        bubble.spawn_from(mouth);
        self.add_bubble(bubble);
    }

    /// Has the octopus spit back the bubble it swallowed last, if it still can.
    fn undo_delete(&mut self, time: f64) {
        if let Some(bubble) = self.octopus.spit_back(time) {
            self.add_bubble(bubble);
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

    /// Moves bubble `i` to the top of the stack.
    fn raise(&mut self, i: usize) {
        let bubble = self.bubbles.remove(i);
        self.bubbles.push(bubble);
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
                    for bubble in &mut self.bubbles {
                        bubble.translate(offset);
                    }
                    self.turtle.translate(offset);
                    self.octopus.translate(offset);
                    self.drag_home += offset;
                }
                self.last_canvas = Some(canvas);
                self.turtle.place(canvas, time);
                // The octopus comes up once a bubble has been dragged a little way.
                let summoned = self.dragging
                    && self.bubbles.last().is_some_and(|top| {
                        (top.center - self.drag_home).length() > SUMMON_DISTANCE
                    });
                self.octopus.summon(summoned);
                self.octopus.update(canvas, self.turtle.center(), time, dt);
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
                    self.raise(i);
                }

                // Right-clicking or long-pressing the turtle opens its menu.
                if pressed_at.is_some_and(|p| self.turtle.contains(p)) {
                    self.turtle_pressed_at = Some(time);
                }
                let (down, pointer) =
                    ui.input(|i| (i.pointer.primary_down(), i.pointer.latest_pos()));
                if let Some(start) = self.turtle_pressed_at {
                    if !down || self.dragging_turtle {
                        self.turtle_pressed_at = None;
                    } else if time - start >= LONG_PRESS_SECONDS {
                        self.turtle_pressed_at = None;
                        self.long_pressed = true;
                        if let Some(pos) = pointer {
                            self.menu = Some(TurtleMenu { pos, rect: None });
                        }
                    }
                }
                let right_clicked_at = response
                    .secondary_clicked()
                    .then(|| response.interact_pointer_pos())
                    .flatten();
                if let Some(pos) = right_clicked_at.filter(|&p| self.turtle.contains(p)) {
                    self.menu = Some(TurtleMenu { pos, rect: None });
                }

                if response.drag_started() {
                    let origin = ui.input(|i| i.pointer.press_origin());
                    if origin.is_some_and(|p| self.turtle.contains(p)) {
                        self.dragging_turtle = true;
                    } else if let Some(i) = origin.and_then(|p| self.hit_test(p)) {
                        self.raise(i);
                        self.dragging = true;
                        self.drag_home = self.bubbles[self.bubbles.len() - 1].center;
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
                if self.dragging {
                    // Holding a bubble over the octopus shrinks it, and letting go
                    // there deletes it. Where the pointer is decides, not where a
                    // thrown bubble ends up, so only a deliberate drop deletes.
                    let over_octopus = pointer.is_some_and(|p| self.octopus.in_reach(p));
                    self.octopus.set_eager(over_octopus);
                    if let Some(top) = self.bubbles.last_mut() {
                        top.center += response.drag_delta();
                        // Remember the throw so the bubble keeps gliding when released.
                        top.velocity = ui.input(|i| i.pointer.velocity());
                        top.set_doomed(over_octopus);
                    }
                    if response.drag_stopped() {
                        self.dragging = false;
                        self.octopus.set_eager(false);
                        if over_octopus && let Some(top) = self.bubbles.pop() {
                            self.octopus.swallow(top, self.drag_home);
                        }
                    }
                }

                let clicked_turtle = response.clicked()
                    && response
                        .interact_pointer_pos()
                        .is_some_and(|p| self.turtle.contains(p));
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
                if clicked_turtle && !self.long_pressed {
                    self.turtle.hop(time);
                }
                if ui.input(|i| i.pointer.primary_released()) {
                    self.long_pressed = false;
                }

                if response.double_clicked() {
                    let pos = response.interact_pointer_pos();
                    if let Some(i) = pos.and_then(|p| self.hit_test(p)) {
                        let bubble = &mut self.bubbles[i];
                        bubble.open = !bubble.open;
                    }
                }

                let held = self.dragging.then(|| self.bubbles.len() - 1);
                for bubble in &mut self.bubbles {
                    // Show what an Ask bubble is doing: it breathes while Claude
                    // works, floats up when the answer is in, and wobbles when
                    // something needs the user.
                    if let Content::Ask(ask) = &mut bubble.content {
                        let outcome = ask.poll();
                        let busy = ask.is_busy();
                        bubble.set_busy(busy);
                        match outcome {
                            Some(ask::Outcome::Answered) => bubble.play(Gesture::Rise),
                            Some(ask::Outcome::NeedsAttention) => bubble.play(Gesture::Wobble),
                            None => {}
                        }
                    }
                    bubble.animate(dt);
                }
                physics::step(&mut self.bubbles, canvas, held, time, dt);
                // Bubbles are always drifting, so keep animating.
                ui.ctx().request_repaint();

                let hovered = response.hover_pos().and_then(|p| self.hit_test(p));
                if self.dragging || self.dragging_turtle {
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
                let top = self.bubbles.len().saturating_sub(1);
                for (i, bubble) in self.bubbles.iter_mut().enumerate() {
                    render::paint_bubble(&painter, bubble);
                    if bubble.is_fully_open() {
                        // Only the front bubble's content takes input, so a bubble lying
                        // on top of another's content can still be grabbed.
                        let interactive = i == top && !self.dragging;
                        content_ui(ui, bubble, interactive, &mut self.api_key);
                    }
                }
                if self.api_key != key_before {
                    remember_api_key(frame, self.api_key.as_deref());
                }
                for bubble in self.octopus.swallowing() {
                    render::paint_bubble(&painter, bubble);
                }
                self.octopus.paint(&painter, time);
                self.turtle.paint(&painter);
                let chosen = self
                    .menu
                    .as_mut()
                    .and_then(|menu| turtle_menu_ui(ui.ctx(), menu));
                if let Some(item) = chosen {
                    self.menu = None;
                    match item {
                        MenuItem::AddNote => self.spit_note_bubble(canvas, time),
                        MenuItem::Ask => self.spit_ask_bubble(canvas, time),
                        #[cfg(not(target_arch = "wasm32"))]
                        MenuItem::Exit => ui.ctx().send_viewport_cmd(ViewportCommand::Close),
                    }
                }
            });
    }
}

/// An item of the turtle's menu.
enum MenuItem {
    AddNote,
    Ask,
    /// Quitting means nothing in a web page.
    #[cfg(not(target_arch = "wasm32"))]
    Exit,
}

/// Shows the turtle's menu and returns the item chosen this frame, if any.
fn turtle_menu_ui(ctx: &egui::Context, menu: &mut TurtleMenu) -> Option<MenuItem> {
    let area = egui::Area::new(egui::Id::unique("turtle_menu"))
        .order(egui::Order::Foreground)
        .fixed_pos(menu.pos)
        .show(ctx, |ui| {
            egui::Frame::menu(ui.style())
                .show(ui, |ui| {
                    // As wide as its text, with no button frame until hovered.
                    let item = |text| egui::Button::new(text).frame_when_inactive(false);
                    let mut chosen = None;
                    if ui.add(item("Add Note")).clicked() {
                        chosen = Some(MenuItem::AddNote);
                    }
                    if ui.add(item("Ask…")).clicked() {
                        chosen = Some(MenuItem::Ask);
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

/// Draws an opened bubble's content inside its panel, below the title.
fn content_ui(
    ui: &mut egui::Ui,
    bubble: &mut Bubble,
    interactive: bool,
    api_key: &mut Option<String>,
) {
    let body = bubble.shape().rect().shrink(22.0);
    let body = body.with_min_y(body.top() + 34.0);
    let color = render::text_color(bubble);
    match &mut bubble.content {
        Content::Note(note) => {
            note.ui(ui, body, color, interactive);
            bubble.label = note.label();
        }
        Content::Ask(ask) => {
            let response = ask.ui(ui, body, color, interactive, api_key);
            bubble.set_panel_height(response.height);
            if let Some(label) = response.asked {
                bubble.label = label;
            }
        }
        Content::Empty => {
            ui.painter().text(
                body.center(),
                Align2::CENTER_CENTER,
                "Nothing here yet",
                FontId::proportional(15.0),
                color.gamma_multiply(0.7),
            );
        }
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
