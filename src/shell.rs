//! The shell: the whole app inside the window. It routes input between the
//! stage of bubbles, the turtle and its menu, the octopus, and the
//! microapps, and paints them all.

use eframe::egui::{self, CursorIcon, Pos2, Sense, ViewportCommand};

use crate::apps::ask::AskApp;
use crate::apps::notes::NotesApp;
use crate::desktop;
use crate::microapp::{AppId, Context, Effect, Registry, View, ViewTarget};
use crate::services::Services;
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

/// What the user is in the middle of doing with the pointer.
enum Interaction {
    Idle,
    DraggingTurtle,
    /// Dragging a bubble, which the stage keeps on top.
    DraggingBubble,
    /// The turtle's menu is open.
    Menu(TurtleMenu),
    /// A press on the turtle just closed its menu, so the click it ends in
    /// must not open the menu again.
    MenuDismissed,
}

/// What is under the pointer, from the top layer down.
#[derive(Clone, Copy, Debug, PartialEq)]
enum Hit {
    Menu,
    Turtle,
    Octopus,
    /// The bubble at this index on the stage.
    Bubble(usize),
    Nothing,
}

pub struct HonuApp {
    /// The bubbles, each showing an item of one of the microapps below.
    stage: Stage,
    apps: Registry,
    turtle: Turtle,
    /// Deletes the bubbles dropped on it.
    octopus: Octopus,
    interaction: Interaction,
    /// What the microapps share, such as the key for asking Claude.
    services: Services,
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
        Self::with_services(floating, storage, Services::load(storage))
    }

    fn with_services(
        floating: bool,
        storage: Option<&dyn eframe::Storage>,
        services: Services,
    ) -> Self {
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
            interaction: Interaction::Idle,
            services,
            floating,
            passthrough: false,
            last_canvas: None,
        }
    }

    /// What is under `p`. The open menu is on top, then the turtle and the
    /// octopus, then the bubbles; bubbles flying out of the turtle or into
    /// the octopus cannot be grabbed.
    fn hit(&self, p: Pos2) -> Hit {
        if let Interaction::Menu(menu) = &self.interaction
            && menu.contains(p)
        {
            Hit::Menu
        } else if self.turtle.contains(p) {
            Hit::Turtle
        } else if self.octopus.contains(p) {
            Hit::Octopus
        } else if let Some(i) = self.stage.hit_test(p) {
            Hit::Bubble(i)
        } else {
            Hit::Nothing
        }
    }

    /// Keeps everything centered when the window changes size, starting from
    /// the windowed size the app is first laid out for, and places the turtle.
    fn lay_out(&mut self, ui: &egui::Ui, canvas: egui::Rect, time: f64) {
        if self.last_canvas.is_none() && self.floating {
            // Fill the screen except the menu bar and Dock. Asking for this when
            // the window is created has no effect on a borderless window on macOS.
            ui.ctx().send_viewport_cmd(ViewportCommand::Maximized(true));
        }
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
    }

    /// Calls the octopus up once a bubble has been dragged a little way, and
    /// deletes for good the bubbles it forgets.
    fn update_octopus(&mut self, canvas: egui::Rect, time: f64, dt: f32) {
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
    }

    /// Lets clicks through to the apps below unless the mouse is on something
    /// of Honu's, or the user is in the middle of something.
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
        let capture = !matches!(self.interaction, Interaction::Idle) || self.hit(p) != Hit::Nothing;
        if self.passthrough == capture {
            self.passthrough = !capture;
            ui.ctx()
                .send_viewport_cmd(ViewportCommand::MousePassthrough(self.passthrough));
        }
    }

    /// Routes this frame's presses, drags, and clicks on the canvas.
    fn handle_input(
        &mut self,
        ui: &egui::Ui,
        response: &egui::Response,
        frame: &mut eframe::Frame,
        canvas: egui::Rect,
        time: f64,
    ) {
        let pressed_at = |primary_only: bool| {
            ui.input(|i| {
                let pressed = if primary_only {
                    i.pointer.primary_pressed()
                } else {
                    i.pointer.any_pressed()
                };
                pressed.then(|| i.pointer.interact_pos()).flatten()
            })
        };

        // Pressing anywhere outside the menu, or Escape, closes it. Pressing
        // the turtle closes it too, like a toggle.
        if let Interaction::Menu(menu) = &self.interaction {
            let pressed_at = pressed_at(false);
            let outside = pressed_at.is_some_and(|p| !menu.contains(p));
            if outside || ui.input(|i| i.key_pressed(egui::Key::Escape)) {
                self.interaction = if pressed_at.is_some_and(|p| self.turtle.contains(p)) {
                    Interaction::MenuDismissed
                } else {
                    Interaction::Idle
                };
            }
        }

        // Any press on a bubble brings it to the front, including presses on
        // an opened bubble's content, which the canvas response never sees.
        if let Some(Hit::Bubble(i)) = pressed_at(true).map(|p| self.hit(p)) {
            self.stage.raise(i);
        }

        if response.drag_started()
            && matches!(
                self.interaction,
                Interaction::Idle | Interaction::MenuDismissed
            )
        {
            match ui.input(|i| i.pointer.press_origin()).map(|p| self.hit(p)) {
                Some(Hit::Turtle) => self.interaction = Interaction::DraggingTurtle,
                Some(Hit::Bubble(i)) => {
                    self.stage.start_drag(i);
                    self.interaction = Interaction::DraggingBubble;
                }
                _ => {}
            }
        }
        match self.interaction {
            Interaction::DraggingTurtle => self.drag_turtle(response, frame, canvas, time),
            Interaction::DraggingBubble => self.drag_bubble(ui, response, time),
            _ => {}
        }

        // Clicking the turtle with either button opens its menu where the
        // pointer is. A tap counts too, so it works on touch screens.
        let clicked_at = (response.clicked() || response.secondary_clicked())
            .then(|| response.interact_pointer_pos())
            .flatten();
        match clicked_at.map(|p| (p, self.hit(p))) {
            Some((pos, Hit::Turtle)) if matches!(self.interaction, Interaction::Idle) => {
                self.turtle.hop(time);
                self.interaction = Interaction::Menu(TurtleMenu { pos, rect: None });
            }
            Some((_, Hit::Octopus)) if response.clicked() => self.undo_delete(time),
            _ => {}
        }
        // ⌘Z (Ctrl+Z elsewhere) also undoes, unless a text field wants it.
        let undo_key = ui.input(|i| i.modifiers.command && i.key_pressed(egui::Key::Z))
            && ui.memory(|m| m.focused().is_none());
        if undo_key {
            self.undo_delete(time);
        }
        if matches!(self.interaction, Interaction::MenuDismissed)
            && ui.input(|i| i.pointer.any_released())
        {
            self.interaction = Interaction::Idle;
        }

        if response.double_clicked()
            && let Some(Hit::Bubble(i)) = response.interact_pointer_pos().map(|p| self.hit(p))
        {
            self.stage.toggle_open(i);
        }
    }

    fn drag_turtle(
        &mut self,
        response: &egui::Response,
        frame: &mut eframe::Frame,
        canvas: egui::Rect,
        time: f64,
    ) {
        self.turtle.move_by(response.drag_delta());
        // Place it again so it follows the pointer this frame.
        self.turtle.place(canvas, time);
        if response.drag_stopped() {
            self.interaction = Interaction::Idle;
            // Save right away: quitting with ⌘Q or from the Dock ends the app
            // without calling `save`.
            if let Some(storage) = frame.storage_mut() {
                self.store_turtle(storage);
                storage.flush();
            }
        }
    }

    /// Moves the dragged bubble. Holding it over the octopus shrinks it, and
    /// letting go there deletes it. Where the pointer is decides, not where a
    /// thrown bubble ends up, so only a deliberate drop deletes.
    fn drag_bubble(&mut self, ui: &egui::Ui, response: &egui::Response, time: f64) {
        let pointer = ui.input(|i| i.pointer.latest_pos());
        let over_octopus = pointer.is_some_and(|p| self.octopus.in_reach(p));
        self.octopus.set_eager(over_octopus);
        let velocity = ui.input(|i| i.pointer.velocity());
        self.stage
            .drag(response.drag_delta(), velocity, over_octopus);
        if response.drag_stopped() {
            self.interaction = Interaction::Idle;
            self.octopus.set_eager(false);
            if let Some((bubble, home)) = self.stage.end_drag()
                && over_octopus
            {
                let mouth = self.octopus.swallow(bubble, home, time);
                self.stage.swallow(bubble, mouth);
            }
        }
    }

    /// Lets the microapps catch up, shows on each bubble what its item is
    /// doing (an Ask bubble breathes while Claude works), and moves the bubbles.
    fn update_bubbles(&mut self, canvas: egui::Rect, time: f64, dt: f32) {
        let mut effects = Vec::new();
        self.apps.update(&mut effects, &mut self.services);
        for bubble in self.stage.bubbles_mut() {
            bubble.label = self.apps.title(bubble.target);
            bubble.set_busy(self.apps.is_busy(bubble.target));
        }
        self.apply(effects);
        self.stage.step(canvas, time, dt);
    }

    fn update_cursor(&self, ui: &egui::Ui, response: &egui::Response) {
        let hovered = response.hover_pos().map(|p| self.hit(p));
        let icon = match (&self.interaction, hovered) {
            (Interaction::DraggingTurtle | Interaction::DraggingBubble, _) => CursorIcon::Grabbing,
            (_, Some(Hit::Bubble(_))) => CursorIcon::Grab,
            (_, Some(Hit::Turtle)) => CursorIcon::PointingHand,
            (_, Some(Hit::Octopus)) if self.octopus.can_undo() => CursorIcon::PointingHand,
            _ => return,
        };
        ui.ctx().set_cursor_icon(icon);
    }

    /// Paints everything back to front: the wallpaper, each bubble followed by
    /// its content, the octopus, the turtle, and the turtle's menu, carrying
    /// out the menu item chosen.
    fn paint(
        &mut self,
        ui: &mut egui::Ui,
        painter: &egui::Painter,
        frame: &mut eframe::Frame,
        canvas: egui::Rect,
        time: f64,
    ) {
        if !self.floating {
            render::paint_background(painter, canvas);
        }
        let mut effects = Vec::new();
        let dragging = matches!(self.interaction, Interaction::DraggingBubble);
        let front = self.stage.front();
        for (i, bubble) in self.stage.bubbles_mut().iter_mut().enumerate() {
            if bubble.is_swallowed() {
                // Out of sight in the octopus's stomach.
                continue;
            }
            render::paint_bubble(painter, bubble);
            if bubble.is_fully_open() {
                // Only the front bubble's content takes input, so a bubble lying
                // on top of another's content can still be grabbed.
                let interactive = Some(i) == front && !dragging;
                let cx = (&mut effects, &mut self.services);
                content_ui(ui, bubble, interactive, &mut self.apps, cx);
            }
        }
        self.apply(effects);
        self.services.store(frame.storage_mut());
        self.octopus.paint(painter, time);
        self.turtle.paint(painter);

        let chosen = match &mut self.interaction {
            Interaction::Menu(menu) => turtle_menu_ui(ui.ctx(), menu, &self.apps),
            _ => None,
        };
        if let Some(item) = chosen {
            self.interaction = Interaction::Idle;
            match item {
                MenuItem::Start(id) => self.start(id, canvas, time),
                #[cfg(not(target_arch = "wasm32"))]
                MenuItem::Exit => ui.ctx().send_viewport_cmd(ViewportCommand::Close),
            }
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

                self.lay_out(ui, canvas, time);
                self.update_octopus(canvas, time, dt);
                if self.floating {
                    self.update_passthrough(ui);
                    // A borderless window has no close button, so handle ⌘Q ourselves.
                    if ui.input(|i| i.modifiers.command && i.key_pressed(egui::Key::Q)) {
                        ui.ctx().send_viewport_cmd(ViewportCommand::Close);
                    }
                }
                self.handle_input(ui, &response, frame, canvas, time);
                self.update_bubbles(canvas, time, dt);
                // Bubbles are always drifting, so keep animating.
                ui.ctx().request_repaint();
                self.update_cursor(ui, &response);
                self.paint(ui, &painter, frame, canvas, time);
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
    (effects, services): (&mut Vec<Effect>, &mut Services),
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
    let mut cx = Context::new(app, effects, services);
    if let Some(height) = microapp.ui(item, ui, view, &mut cx) {
        bubble.set_panel_height(height);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::claude;
    use eframe::egui::{Rect, pos2, vec2};

    /// An app laid out in the windowed size, asking a stand-in for Claude.
    fn app() -> (HonuApp, Rect) {
        let services = Services::fake(None, claude::Fake::default());
        let mut app = HonuApp::with_services(false, None, services);
        let canvas = Rect::from_min_size(Pos2::ZERO, WINDOWED_SIZE);
        app.turtle.place(canvas, 0.0);
        app.last_canvas = Some(canvas);
        (app, canvas)
    }

    #[test]
    fn the_menu_and_the_turtle_are_hit_before_bubbles() {
        let (mut app, _) = app();
        let turtle = app.turtle.center();
        let target = ViewTarget::TEST;
        let white = egui::Color32::WHITE;
        app.stage
            .add(Bubble::new(target, turtle, 80.0, white, false));
        app.stage
            .add(Bubble::new(target, pos2(600.0, 300.0), 80.0, white, false));
        assert_eq!(app.hit(turtle), Hit::Turtle);
        assert_eq!(app.hit(pos2(600.0, 300.0)), Hit::Bubble(1));
        assert_eq!(app.hit(turtle + vec2(0.0, -70.0)), Hit::Bubble(0));
        assert_eq!(app.hit(pos2(1000.0, 100.0)), Hit::Nothing);

        let rect = Rect::from_min_size(pos2(550.0, 250.0), vec2(120.0, 80.0));
        app.interaction = Interaction::Menu(TurtleMenu {
            pos: rect.min,
            rect: Some(rect),
        });
        assert_eq!(app.hit(pos2(600.0, 300.0)), Hit::Menu);
    }

    #[test]
    fn every_menu_item_starts_an_item_shown_in_a_new_bubble() {
        let (mut app, canvas) = app();
        let ids: Vec<_> = app.apps.iter().map(|a| a.id()).collect();
        for &id in &ids {
            app.start(id, canvas, 0.0);
        }
        let bubbles = app.stage.bubbles_mut();
        assert_eq!(bubbles.len(), ids.len());
        for (bubble, &id) in bubbles.iter().zip(&ids) {
            assert_eq!(bubble.target.app, id);
            assert!(bubble.is_spawning() && bubble.is_or_will_be_open());
            assert!(!bubble.label.is_empty());
        }
    }

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
