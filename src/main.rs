mod bubble;
mod physics;
mod render;

use bubble::{Bubble, Content};
use eframe::egui::{self, Align2, Color32, CursorIcon, FontId, Pos2, Sense, pos2};

fn main() -> eframe::Result {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default().with_inner_size([1100.0, 750.0]),
        ..Default::default()
    };
    eframe::run_native(
        "Honu",
        options,
        Box::new(|_cc| Ok(Box::<HonuApp>::default())),
    )
}

struct HonuApp {
    /// Bubbles in back-to-front paint order; the last one is on top.
    bubbles: Vec<Bubble>,
    /// True while the top bubble is being dragged.
    dragging: bool,
}

impl Default for HonuApp {
    fn default() -> Self {
        let rgb = Color32::from_rgb;
        let notes = Content::Notes(
            "Double-click a bubble to open it, and double-click its edge or title to close it."
                .to_owned(),
        );
        let mut bubbles = vec![
            Bubble::new("Notes", pos2(250.0, 260.0), 95.0, rgb(240, 110, 100), false)
                .with_content(notes),
            Bubble::new("Files", pos2(820.0, 520.0), 85.0, rgb(90, 200, 150), false),
            Bubble::new("Photos", pos2(560.0, 560.0), 75.0, rgb(245, 185, 70), false),
            Bubble::new("Music", pos2(420.0, 360.0), 120.0, rgb(70, 190, 210), true),
            Bubble::new("Mail", pos2(720.0, 260.0), 105.0, rgb(150, 110, 230), true),
            Bubble::new("Clock", pos2(300.0, 540.0), 70.0, rgb(110, 160, 250), true),
        ];
        for (i, bubble) in bubbles.iter_mut().enumerate() {
            bubble.phase = i as f32 * 1.7;
        }
        Self {
            bubbles,
            dragging: false,
        }
    }
}

impl HonuApp {
    /// Index of the topmost bubble under `p`, if any.
    fn hit_test(&self, p: Pos2) -> Option<usize> {
        self.bubbles.iter().rposition(|b| b.contains(p))
    }

    /// Moves bubble `i` to the top of the stack.
    fn raise(&mut self, i: usize) {
        let bubble = self.bubbles.remove(i);
        self.bubbles.push(bubble);
    }
}

impl eframe::App for HonuApp {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        egui::CentralPanel::default()
            .frame(egui::Frame::NONE)
            .show(ui, |ui| {
                let (response, painter) =
                    ui.allocate_painter(ui.available_size(), Sense::click_and_drag());
                let canvas = response.rect;

                // Any press on a bubble brings it to the front, including presses on
                // an opened bubble's content, which the canvas response never sees.
                let pressed_at = ui.input(|i| {
                    i.pointer
                        .primary_pressed()
                        .then(|| i.pointer.interact_pos())
                        .flatten()
                });
                if let Some(i) = pressed_at.and_then(|p| self.hit_test(p)) {
                    self.raise(i);
                }

                if response.drag_started() {
                    let origin = ui.input(|i| i.pointer.press_origin());
                    if let Some(i) = origin.and_then(|p| self.hit_test(p)) {
                        self.raise(i);
                        self.dragging = true;
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

                if response.double_clicked() {
                    let pos = response.interact_pointer_pos();
                    if let Some(i) = pos.and_then(|p| self.hit_test(p)) {
                        let bubble = &mut self.bubbles[i];
                        bubble.open = !bubble.open;
                    }
                }

                let held = self.dragging.then(|| self.bubbles.len() - 1);
                let (time, dt) = ui.input(|i| (i.time, i.stable_dt.min(1.0 / 30.0)));
                for bubble in &mut self.bubbles {
                    bubble.animate(dt);
                }
                physics::step(&mut self.bubbles, canvas, held, time, dt);
                // Bubbles are always drifting, so keep animating.
                ui.ctx().request_repaint();

                let hovered = response.hover_pos().and_then(|p| self.hit_test(p));
                if self.dragging {
                    ui.ctx().set_cursor_icon(CursorIcon::Grabbing);
                } else if hovered.is_some() {
                    ui.ctx().set_cursor_icon(CursorIcon::Grab);
                }

                render::paint_background(&painter, canvas);
                let top = self.bubbles.len() - 1;
                for (i, bubble) in self.bubbles.iter_mut().enumerate() {
                    render::paint_bubble(&painter, bubble);
                    if bubble.is_fully_open() {
                        // Only the front bubble's content takes input, so a bubble lying
                        // on top of another's content can still be grabbed.
                        let interactive = i == top && !self.dragging;
                        content_ui(ui, bubble, interactive);
                    }
                }
            });
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
