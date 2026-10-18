use eframe::egui;

fn main() -> eframe::Result {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default().with_inner_size([400.0, 500.0]),
        ..Default::default()
    };
    eframe::run_native(
        "Honu",
        options,
        Box::new(|_cc| Ok(Box::<HonuApp>::default())),
    )
}

#[derive(Default)]
struct HonuApp {
    input: String,
    items: Vec<String>,
}

impl HonuApp {
    fn add_item(&mut self) {
        let text = self.input.trim();
        if !text.is_empty() {
            self.items.push(text.to_owned());
            self.input.clear();
        }
    }
}

impl eframe::App for HonuApp {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        egui::CentralPanel::default().show(ui, |ui| {
            ui.horizontal(|ui| {
                let response = ui.text_edit_singleline(&mut self.input);
                let enter_pressed =
                    response.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter));
                if ui.button("Add").clicked() || enter_pressed {
                    self.add_item();
                    response.request_focus();
                }
            });

            ui.separator();

            egui::ScrollArea::vertical().show(ui, |ui| {
                for (i, item) in self.items.iter().enumerate() {
                    ui.label(format!("{}. {}", i + 1, item));
                }
            });
        });
    }
}
