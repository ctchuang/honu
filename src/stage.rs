//! The stage: the bubbles on the desktop in paint order, and how they are
//! picked up, dragged, opened, and set moving. It knows nothing of what a
//! bubble shows; that is up to the microapps.

use eframe::egui::{Pos2, Rect, Vec2, vec2};

use crate::microapp::ViewTarget;
use crate::view::bubble::{Bubble, Gesture};
use crate::view::physics;

/// How far a new panel steps aside from one already in its place.
const CASCADE_STEP: f32 = 28.0;
/// Most steps aside a new panel takes before landing where it is.
const CASCADE_LIMIT: usize = 10;

pub struct Stage {
    /// Back-to-front paint order; the last one is on top.
    bubbles: Vec<Bubble>,
    /// Where the bubble being dragged, always the top one, was picked up.
    drag_home: Option<Pos2>,
}

impl Stage {
    pub fn new() -> Self {
        Self {
            bubbles: Vec::new(),
            drag_home: None,
        }
    }

    /// The bubbles in back-to-front paint order.
    #[cfg(test)]
    pub fn bubbles(&self) -> &[Bubble] {
        &self.bubbles
    }

    pub fn bubbles_mut(&mut self) -> &mut [Bubble] {
        &mut self.bubbles
    }

    /// Whether any bubble shows `target`.
    pub fn shows(&self, target: ViewTarget) -> bool {
        self.bubbles.iter().any(|b| b.target == target)
    }

    /// Has every bubble showing `target` play `gesture`.
    pub fn play(&mut self, target: ViewTarget, gesture: Gesture) {
        for bubble in &mut self.bubbles {
            if bubble.target == target {
                bubble.play(gesture);
            }
        }
    }

    /// Index of the topmost bubble under `p`, if any. Bubbles still flying
    /// out of the turtle cannot be grabbed.
    pub fn hit_test(&self, p: Pos2) -> Option<usize> {
        self.bubbles
            .iter()
            .rposition(|b| b.contains(p) && !b.is_spawning())
    }

    /// Moves bubble `i` to the top.
    pub fn raise(&mut self, i: usize) {
        let bubble = self.bubbles.remove(i);
        self.bubbles.push(bubble);
    }

    pub fn toggle_open(&mut self, i: usize) {
        let bubble = &mut self.bubbles[i];
        bubble.open = !bubble.open;
    }

    /// Puts a new bubble on top, below a bubble being dragged, which must stay on top.
    pub fn add(&mut self, bubble: Bubble) {
        let index = self.bubbles.len() - usize::from(self.is_dragging());
        self.bubbles.insert(index, bubble);
    }

    /// Adds `bubble`, popping out of `mouth` at `time` and flying to a place up
    /// and to the right of it inside `canvas`, where it opens into its panel.
    pub fn spit_panel(&mut self, bubble: Bubble, mouth: Pos2, canvas: Rect, time: f64) {
        let mut bubble = bubble.open_on_landing();
        // Drift out of step with the other bubbles once closed.
        bubble.phase = (time % 100.0) as f32;
        // Land with the whole panel on screen.
        let half = bubble.panel_target() / 2.0;
        let margin = Vec2::splat(16.0);
        let lo = canvas.min + half + margin;
        let hi = (canvas.max - half - margin).max(lo);
        let mut place = (mouth + vec2(half.x + 40.0, -half.y - 20.0)).clamp(lo, hi);
        // Open panels don't push each other aside, so step down and to the
        // right of any panel already landing there, as windows cascade.
        for _ in 0..CASCADE_LIMIT {
            let taken = self.bubbles.iter().any(|b| {
                b.is_or_will_be_open() && (b.destination() - place).length() < CASCADE_STEP
            });
            if !taken {
                break;
            }
            place = (place + Vec2::splat(CASCADE_STEP)).clamp(lo, hi);
        }
        bubble.center = place;
        bubble.spawn_from(mouth);
        self.add(bubble);
    }

    /// Moves every bubble, and where a dragged one was picked up, by `offset`.
    pub fn translate(&mut self, offset: Vec2) {
        for bubble in &mut self.bubbles {
            bubble.translate(offset);
        }
        if let Some(home) = &mut self.drag_home {
            *home += offset;
        }
    }

    pub fn is_dragging(&self) -> bool {
        self.drag_home.is_some()
    }

    /// Picks up bubble `i`, which moves to the top.
    pub fn start_drag(&mut self, i: usize) {
        self.raise(i);
        self.drag_home = self.bubbles.last().map(|b| b.center);
    }

    /// How far the dragged bubble is from where it was picked up.
    pub fn drag_distance(&self) -> Option<f32> {
        let home = self.drag_home?;
        self.bubbles.last().map(|b| (b.center - home).length())
    }

    /// Moves the dragged bubble by `delta`, remembering the pointer's
    /// `velocity` so it keeps gliding when let go. A `doomed` bubble, held
    /// where letting go deletes it, shrinks.
    pub fn drag(&mut self, delta: Vec2, velocity: Vec2, doomed: bool) {
        if !self.is_dragging() {
            return;
        }
        if let Some(top) = self.bubbles.last_mut() {
            top.center += delta;
            top.velocity = velocity;
            top.set_doomed(doomed);
        }
    }

    /// Lets go of the dragged bubble. If `take` is set, it is taken off the
    /// stage and returned with where it was picked up.
    pub fn end_drag(&mut self, take: bool) -> Option<(Bubble, Pos2)> {
        let home = self.drag_home.take()?;
        if take {
            self.bubbles.pop().map(|bubble| (bubble, home))
        } else {
            None
        }
    }

    /// Advances every bubble's animations and motion by `dt` seconds. A
    /// dragged bubble follows the pointer instead of the physics.
    pub fn step(&mut self, canvas: Rect, time: f64, dt: f32) {
        for bubble in &mut self.bubbles {
            bubble.animate(dt);
        }
        let held = self.is_dragging().then(|| self.bubbles.len() - 1);
        physics::step(&mut self.bubbles, canvas, held, time, dt);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use eframe::egui::{Color32, pos2};

    fn bubble(x: f32) -> Bubble {
        Bubble::new(
            ViewTarget::TEST,
            pos2(x, 300.0),
            50.0,
            Color32::WHITE,
            false,
        )
    }

    #[test]
    fn dragged_bubble_stays_on_top_and_can_be_taken() {
        let mut stage = Stage::new();
        stage.add(bubble(100.0));
        stage.add(bubble(400.0));
        let first = stage.hit_test(pos2(100.0, 300.0)).unwrap();
        stage.start_drag(first);
        assert_eq!(stage.bubbles().last().unwrap().center.x, 100.0);
        stage.add(bubble(700.0));
        assert_eq!(
            stage.bubbles().last().unwrap().center.x,
            100.0,
            "new bubble went on top"
        );

        stage.drag(vec2(50.0, 0.0), Vec2::ZERO, false);
        assert_eq!(stage.drag_distance(), Some(50.0));
        let (taken, home) = stage.end_drag(true).unwrap();
        assert_eq!((taken.center.x, home.x), (150.0, 100.0));
        assert!(!stage.is_dragging());
        assert_eq!(stage.bubbles().len(), 2);
    }

    #[test]
    fn new_panels_step_aside_from_each_other() {
        let canvas = Rect::from_min_size(Pos2::ZERO, vec2(1200.0, 800.0));
        let mut stage = Stage::new();
        let mouth = pos2(100.0, 700.0);
        stage.spit_panel(bubble(0.0), mouth, canvas, 0.0);
        stage.spit_panel(bubble(0.0), mouth, canvas, 0.0);
        let [a, b] = stage.bubbles() else {
            panic!("expected two bubbles");
        };
        assert_eq!(b.destination() - a.destination(), Vec2::splat(CASCADE_STEP));
    }
}
