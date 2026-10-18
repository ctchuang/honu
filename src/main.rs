mod render;

use eframe::egui::{self, Color32, CursorIcon, Pos2, Sense, pos2};

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

/// A draggable, window-like bubble on the desktop.
pub struct Bubble {
    pub label: String,
    pub center: Pos2,
    pub radius: f32,
    pub color: Color32,
    /// Whether the bubble is see-through glass (true) or a solid, opaque ball (false).
    pub glass: bool,
}

impl Bubble {
    fn new(label: &str, center: Pos2, radius: f32, color: Color32, glass: bool) -> Self {
        Self {
            label: label.to_owned(),
            center,
            radius,
            color,
            glass,
        }
    }

    fn contains(&self, p: Pos2) -> bool {
        self.center.distance(p) <= self.radius
    }
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
        Self {
            bubbles: vec![
                Bubble::new("Notes", pos2(250.0, 260.0), 95.0, rgb(240, 110, 100), false),
                Bubble::new("Files", pos2(820.0, 520.0), 85.0, rgb(90, 200, 150), false),
                Bubble::new("Photos", pos2(560.0, 560.0), 75.0, rgb(245, 185, 70), false),
                Bubble::new("Music", pos2(420.0, 360.0), 120.0, rgb(70, 190, 210), true),
                Bubble::new("Mail", pos2(720.0, 260.0), 105.0, rgb(150, 110, 230), true),
                Bubble::new("Clock", pos2(300.0, 540.0), 70.0, rgb(110, 160, 250), true),
            ],
            dragging: false,
        }
    }
}

impl HonuApp {
    /// Index of the topmost bubble under `p`, if any.
    fn hit_test(&self, p: Pos2) -> Option<usize> {
        self.bubbles.iter().rposition(|b| b.contains(p))
    }
}

impl eframe::App for HonuApp {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        egui::CentralPanel::default()
            .frame(egui::Frame::NONE)
            .show(ui, |ui| {
                let (response, painter) = ui.allocate_painter(ui.available_size(), Sense::drag());
                let canvas = response.rect;

                if response.drag_started() {
                    let origin = ui.input(|i| i.pointer.press_origin());
                    if let Some(i) = origin.and_then(|p| self.hit_test(p)) {
                        // Bring the grabbed bubble to the front.
                        let bubble = self.bubbles.remove(i);
                        self.bubbles.push(bubble);
                        self.dragging = true;
                    }
                }
                if self.dragging {
                    if let Some(top) = self.bubbles.last_mut() {
                        top.center += response.drag_delta();
                        top.center = canvas.clamp(top.center);
                    }
                    if response.drag_stopped() {
                        self.dragging = false;
                    }
                }

                let hovered = response.hover_pos().and_then(|p| self.hit_test(p));
                if self.dragging {
                    ui.ctx().set_cursor_icon(CursorIcon::Grabbing);
                } else if hovered.is_some() {
                    ui.ctx().set_cursor_icon(CursorIcon::Grab);
                }

                render::paint_background(&painter, canvas);
                for bubble in &self.bubbles {
                    render::paint_bubble(&painter, bubble);
                }
            });
    }
}
