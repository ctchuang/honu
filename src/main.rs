mod apps;
mod claude;
mod desktop;
mod microapp;
mod persistence;
mod services;
mod shell;
mod sprite;
mod stage;
mod view;

use shell::HonuApp;

#[cfg(not(target_arch = "wasm32"))]
fn main() -> eframe::Result {
    // By default the bubbles float on the real desktop; `--windowed` shows them in
    // an ordinary window with its own wallpaper instead.
    let floating = !std::env::args().any(|arg| arg == "--windowed");
    let icon = eframe::icon_data::from_png_bytes(include_bytes!("../assets/icon.png"))
        .expect("the bundled app icon is a valid PNG");
    let base = eframe::egui::ViewportBuilder::default().with_icon(icon);
    let viewport = if floating {
        base.with_transparent(true)
            .with_decorations(false)
            .with_has_shadow(false)
            .with_window_level(eframe::egui::WindowLevel::AlwaysOnTop)
            .with_inner_size(shell::WINDOWED_SIZE)
    } else {
        base.with_inner_size(shell::WINDOWED_SIZE)
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
