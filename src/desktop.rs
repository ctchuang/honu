//! Floating on the real desktop: the window is transparent, borderless, and
//! always on top, and lets clicks through everywhere except on bubbles.

use eframe::egui::Pos2;

/// The mouse position in global screen points (origin at the top-left of the
/// main display). This works even while the window lets mouse events through,
/// when egui gets no pointer events of its own.
#[cfg(target_os = "macos")]
pub fn global_cursor() -> Option<Pos2> {
    use core_graphics::event::CGEvent;
    use core_graphics::event_source::{CGEventSource, CGEventSourceStateID};

    let source = CGEventSource::new(CGEventSourceStateID::CombinedSessionState).ok()?;
    let location = CGEvent::new(source).ok()?.location();
    Some(Pos2::new(location.x as f32, location.y as f32))
}

/// Not supported elsewhere yet, so the window never lets clicks through.
#[cfg(not(target_os = "macos"))]
pub fn global_cursor() -> Option<Pos2> {
    None
}
