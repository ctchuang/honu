//! Bubbles and their outline. A bubble is a circle when closed and morphs
//! into a rounded panel that shows its content when opened.

use eframe::egui::{Color32, Pos2, Rect, Vec2, vec2};

/// Size of an opened bubble.
const PANEL_SIZE: Vec2 = vec2(380.0, 300.0);
/// Corner radius of an opened bubble.
const PANEL_CORNER: f32 = 36.0;
/// Width of the rounded, lit rim of an opened bubble. A closed bubble's rim
/// spans its whole radius, which is what makes it look like a ball.
const PANEL_BEVEL: f32 = 22.0;
/// Seconds to open or close a bubble.
const MORPH_SECONDS: f32 = 0.35;

/// What an opened bubble shows.
pub enum Content {
    Notes(String),
    Empty,
}

/// A draggable, window-like bubble on the desktop.
pub struct Bubble {
    pub label: String,
    pub center: Pos2,
    /// Radius when closed.
    pub radius: f32,
    pub color: Color32,
    /// Whether the bubble is see-through glass (true) or a solid, opaque ball (false).
    pub glass: bool,
    /// Current speed and direction, in points per second.
    pub velocity: Vec2,
    /// Offset (in seconds) into the idle float, so bubbles drift out of sync.
    pub phase: f32,
    pub content: Content,
    /// Whether the bubble is open (or opening).
    pub open: bool,
    /// Linear progress of the open/close morph, from 0 (closed) to 1 (open).
    progress: f32,
}

impl Bubble {
    pub fn new(label: &str, center: Pos2, radius: f32, color: Color32, glass: bool) -> Self {
        Self {
            label: label.to_owned(),
            center,
            radius,
            color,
            glass,
            velocity: Vec2::ZERO,
            phase: 0.0,
            content: Content::Empty,
            open: false,
            progress: 0.0,
        }
    }

    pub fn with_content(mut self, content: Content) -> Self {
        self.content = content;
        self
    }

    /// Moves the open/close morph `dt` seconds towards `open`.
    pub fn animate(&mut self, dt: f32) {
        let target = if self.open { 1.0 } else { 0.0 };
        let step = dt / MORPH_SECONDS;
        self.progress = if self.progress < target {
            (self.progress + step).min(target)
        } else {
            (self.progress - step).max(target)
        };
    }

    /// How open the bubble looks: 0 closed, 1 open, slightly above 1 while
    /// overshooting during the morph.
    pub fn openness(&self) -> f32 {
        ease_out_back(self.progress)
    }

    /// True when fully closed, so the bubble behaves like a free-floating ball.
    pub fn is_closed(&self) -> bool {
        self.progress == 0.0
    }

    /// True when fully open and ready to show its content.
    pub fn is_fully_open(&self) -> bool {
        self.open && self.progress == 1.0
    }

    pub fn shape(&self) -> Shape {
        let t = self.openness();
        let r = self.radius;
        let half = (Vec2::splat(r) + (PANEL_SIZE / 2.0 - Vec2::splat(r)) * t).max(Vec2::splat(1.0));
        let max_round = half.min_elem();
        Shape {
            center: self.center,
            half,
            corner: lerp(r, PANEL_CORNER, t).clamp(0.0, max_round),
            bevel: lerp(r, PANEL_BEVEL, t).clamp(1.0, max_round),
        }
    }

    pub fn contains(&self, p: Pos2) -> bool {
        self.shape().signed_distance(p) <= 0.0
    }
}

/// A rounded rectangle with a lit, rounded rim. With `half` equal to `corner`
/// and `bevel` on both axes it is a sphere.
#[derive(Clone, Copy)]
pub struct Shape {
    pub center: Pos2,
    /// Half of the width and height.
    pub half: Vec2,
    /// Corner radius, at most the smaller of `half`'s components.
    pub corner: f32,
    /// How far in from the edge the surface curves before it turns flat,
    /// at most the smaller of `half`'s components.
    pub bevel: f32,
}

impl Shape {
    pub fn circle(center: Pos2, radius: f32) -> Self {
        Self {
            center,
            half: Vec2::splat(radius),
            corner: radius,
            bevel: radius,
        }
    }

    pub fn rect(&self) -> Rect {
        Rect::from_center_size(self.center, self.half * 2.0)
    }

    /// The same shape grown by `amount` on every side (shrunk if negative).
    pub fn expand(&self, amount: f32) -> Self {
        Self {
            center: self.center,
            half: self.half + Vec2::splat(amount),
            corner: (self.corner + amount).max(0.0),
            bevel: (self.bevel + amount).max(1.0),
        }
    }

    /// Distance from `p` to the outline: negative inside, positive outside.
    pub fn signed_distance(&self, p: Pos2) -> f32 {
        let q = (p - self.center).abs() - (self.half - Vec2::splat(self.corner));
        let outside = q.max(Vec2::ZERO).length();
        let inside = q.max_elem().min(0.0);
        outside + inside - self.corner
    }
}

fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

/// Eases out with a small overshoot, so bubbles pop open.
fn ease_out_back(t: f32) -> f32 {
    const C1: f32 = 1.0;
    const C3: f32 = C1 + 1.0;
    let u = t - 1.0;
    1.0 + C3 * u * u * u + C1 * u * u
}
