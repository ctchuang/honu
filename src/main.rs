mod bubble;
mod desktop;
mod physics;
mod render;
mod turtle;

use bubble::{Bubble, Content};
use eframe::egui::{
    self, Align2, Color32, CursorIcon, FontId, Pos2, Sense, ViewportCommand, WindowLevel, pos2,
};
use turtle::Turtle;

/// Size of the window in `--windowed` mode, which the starting layout is designed for.
const WINDOWED_SIZE: egui::Vec2 = egui::vec2(1100.0, 750.0);
/// Seconds the turtle must be held, without dragging, to open its menu.
const LONG_PRESS_SECONDS: f64 = 0.5;
/// Seconds between bubbles coming out of the turtle's mouth.
const RELEASE_INTERVAL: f64 = 0.5;

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
            .with_window_level(WindowLevel::AlwaysOnTop)
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
    /// Bubbles the turtle has yet to release, at their places, in reverse
    /// order: the last one comes out next.
    pending: Vec<Bubble>,
    /// When the next pending bubble pops out, while the turtle is releasing them.
    next_release: Option<f64>,
    turtle: Turtle,
    /// True while the top bubble is being dragged.
    dragging: bool,
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
        let rgb = Color32::from_rgb;
        // A soft, slightly warm white for the opaque bubbles.
        let white = rgb(250, 249, 246);
        let notes = Content::Notes(
            "Double-click a bubble to open it, and double-click its edge or title to close it."
                .to_owned(),
        );
        let mut pending = vec![
            Bubble::new("Notes", pos2(250.0, 260.0), 95.0, white, false).with_content(notes),
            Bubble::new("Files", pos2(820.0, 520.0), 85.0, white, false),
            Bubble::new("Photos", pos2(560.0, 560.0), 75.0, white, false),
            Bubble::new("Music", pos2(420.0, 360.0), 120.0, rgb(70, 190, 210), true),
            Bubble::new("Mail", pos2(720.0, 260.0), 105.0, rgb(150, 110, 230), true),
            Bubble::new("Clock", pos2(300.0, 540.0), 70.0, rgb(110, 160, 250), true),
        ];
        for (i, bubble) in pending.iter_mut().enumerate() {
            bubble.phase = i as f32 * 1.7;
        }
        pending.reverse();
        let mut turtle = Turtle::new();
        let saved = storage.and_then(|storage| storage.get_string(turtle_key(floating)));
        if let Some(offset) = saved.as_deref().and_then(parse_offset) {
            // Like the starting bubbles, start out laid out for the windowed size;
            // the first frame moves everything to the real window.
            turtle.set_offset_from((WINDOWED_SIZE / 2.0).to_pos2(), offset);
        }
        Self {
            bubbles: Vec::new(),
            pending,
            next_release: None,
            turtle,
            dragging: false,
            dragging_turtle: false,
            turtle_pressed_at: None,
            long_pressed: false,
            menu: None,
            floating,
            passthrough: false,
            last_canvas: None,
        }
    }

    /// Index of the topmost bubble under `p`, if any. The turtle sits above
    /// all bubbles, and bubbles still flying out of it cannot be grabbed.
    fn hit_test(&self, p: Pos2) -> Option<usize> {
        if self.turtle.contains(p) {
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
            || self.turtle.contains(p);
        if self.passthrough == on_bubble {
            self.passthrough = !on_bubble;
            ui.ctx()
                .send_viewport_cmd(ViewportCommand::MousePassthrough(self.passthrough));
        }
    }

    /// Spits out the pending bubbles that are due by `time`, one at a time.
    fn release_due(&mut self, time: f64) {
        while let Some(at) = self.next_release.filter(|&at| time >= at) {
            if let Some(mut bubble) = self.pending.pop() {
                bubble.spawn_from(self.turtle.spit(time));
                // A dragged bubble must stay on top.
                let index = self.bubbles.len() - usize::from(self.dragging);
                self.bubbles.insert(index, bubble);
            }
            self.next_release = (!self.pending.is_empty()).then_some(at + RELEASE_INTERVAL);
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
                // Keep the bubbles centered when the window changes size. The starting
                // layout is designed for the windowed size.
                let last_center = self
                    .last_canvas
                    .map_or((WINDOWED_SIZE / 2.0).to_pos2(), |rect| rect.center());
                let offset = canvas.center() - last_center;
                if offset != egui::Vec2::ZERO {
                    for bubble in self.bubbles.iter_mut().chain(&mut self.pending) {
                        bubble.translate(offset);
                    }
                    self.turtle.translate(offset);
                }
                self.last_canvas = Some(canvas);
                self.turtle.place(canvas, time);
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
                    if let Some(top) = self.bubbles.last_mut() {
                        top.center += response.drag_delta();
                        // Remember the throw so the bubble keeps gliding when released.
                        top.velocity = ui.input(|i| i.pointer.velocity());
                    }
                    if response.drag_stopped() {
                        self.dragging = false;
                    }
                }

                let clicked_turtle = response.clicked()
                    && response
                        .interact_pointer_pos()
                        .is_some_and(|p| self.turtle.contains(p));
                if clicked_turtle && !self.long_pressed {
                    self.turtle.hop(time);
                    if self.next_release.is_none() && !self.pending.is_empty() {
                        self.next_release = Some(time);
                    }
                }
                if ui.input(|i| i.pointer.primary_released()) {
                    self.long_pressed = false;
                }
                self.release_due(time);

                if response.double_clicked() {
                    let pos = response.interact_pointer_pos();
                    if let Some(i) = pos.and_then(|p| self.hit_test(p)) {
                        let bubble = &mut self.bubbles[i];
                        bubble.open = !bubble.open;
                    }
                }

                let held = self.dragging.then(|| self.bubbles.len() - 1);
                for bubble in &mut self.bubbles {
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
                } else if response
                    .hover_pos()
                    .is_some_and(|p| self.turtle.contains(p))
                {
                    ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
                }

                if !self.floating {
                    render::paint_background(&painter, canvas);
                }
                let top = self.bubbles.len().saturating_sub(1);
                for (i, bubble) in self.bubbles.iter_mut().enumerate() {
                    render::paint_bubble(&painter, bubble);
                    if bubble.is_fully_open() {
                        // Only the front bubble's content takes input, so a bubble lying
                        // on top of another's content can still be grabbed.
                        let interactive = i == top && !self.dragging;
                        content_ui(ui, bubble, interactive);
                    }
                }
                self.turtle.paint(&painter);
                if let Some(menu) = &mut self.menu {
                    turtle_menu_ui(ui.ctx(), menu);
                }
            });
    }
}

/// Shows the turtle's menu and carries out the chosen item.
fn turtle_menu_ui(ctx: &egui::Context, menu: &mut TurtleMenu) {
    let area = egui::Area::new(egui::Id::unique("turtle_menu"))
        .order(egui::Order::Foreground)
        .fixed_pos(menu.pos)
        .show(ctx, |ui| {
            egui::Frame::menu(ui.style())
                .show(ui, |ui| {
                    // As wide as its text, with no button frame until hovered.
                    let item = |text| egui::Button::new(text).frame_when_inactive(false);
                    ui.add(item("Exit")).clicked()
                })
                .inner
        });
    menu.rect = Some(area.response.rect);
    if area.inner {
        ctx.send_viewport_cmd(ViewportCommand::Close);
    }
}

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
fn content_ui(ui: &mut egui::Ui, bubble: &mut Bubble, interactive: bool) {
    let body = bubble.shape().rect().shrink(22.0);
    let body = body.with_min_y(body.top() + 34.0);
    let color = render::text_color(bubble);
    match &mut bubble.content {
        Content::Notes(text) => {
            ui.scope_builder(egui::UiBuilder::new().max_rect(body), |ui| {
                // No drag-to-scroll, so dragging the panel body moves the bubble.
                let scroll_source = egui::scroll_area::ScrollSource {
                    scroll_bar: true,
                    mouse_wheel: true,
                    ..egui::scroll_area::ScrollSource::NONE
                };
                egui::ScrollArea::vertical()
                    .id_salt(&bubble.label)
                    .scroll_source(scroll_source)
                    .show(ui, |ui| {
                        ui.add(
                            egui::TextEdit::multiline(text)
                                .frame(egui::Frame::NONE)
                                .text_color(color)
                                .font(FontId::proportional(16.0))
                                .desired_width(f32::INFINITY)
                                .interactive(interactive),
                        );
                    });
            });
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
