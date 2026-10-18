//! Bubbles and their outline. A bubble is a rounded square, like a macOS app
//! icon, when closed and morphs into a larger panel that shows its content
//! when opened. A new bubble pops out small and grows as it flies to its place.

use eframe::egui::{Color32, Pos2, Rect, Vec2, vec2};

/// Corner radius of a closed bubble, as a fraction of its radius.
const CLOSED_CORNER: f32 = 0.28;
/// Width of a closed bubble's rounded, lit rim, as a fraction of its radius.
/// Keep it at most the corner radius: a wider rim makes its inner edge
/// square-cornered, which shows as diagonal creases at the corners.
const CLOSED_BEVEL: f32 = 0.2;
/// Superellipse exponent of the corners. 2 would be circular arcs; higher
/// values give the smoother, continuous-curvature corners of macOS shapes.
const CORNER_EXPONENT: f32 = 4.0;
/// Size of an opened bubble.
const PANEL_SIZE: Vec2 = vec2(380.0, 300.0);
/// Corner radius of an opened bubble.
const PANEL_CORNER: f32 = 22.0;
/// Width of the rounded, lit rim of an opened bubble; at most `PANEL_CORNER`.
const PANEL_BEVEL: f32 = 14.0;
/// Seconds to open or close a bubble.
const MORPH_SECONDS: f32 = 0.35;
/// Seconds a new bubble takes to fly to its place.
const SPAWN_SECONDS: f32 = 0.6;

/// What an opened bubble shows.
pub enum Content {
    Notes(String),
    Empty,
}

/// A new bubble's flight from where it popped out to its place.
struct Spawn {
    from: Pos2,
    to: Pos2,
    /// Linear progress of the flight, from 0 to 1.
    progress: f32,
}

/// A draggable, window-like bubble on the desktop.
pub struct Bubble {
    pub label: String,
    pub center: Pos2,
    /// Half the side of the closed square.
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
    /// Set while the bubble is still flying to its place after popping out.
    spawn: Option<Spawn>,
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
            spawn: None,
        }
    }

    pub fn with_content(mut self, content: Content) -> Self {
        self.content = content;
        self
    }

    /// Makes the bubble pop out at `from` and fly to where it is now, growing
    /// to full size on the way.
    pub fn spawn_from(&mut self, from: Pos2) {
        self.spawn = Some(Spawn {
            from,
            to: self.center,
            progress: 0.0,
        });
        self.center = from;
        self.velocity = Vec2::ZERO;
    }

    /// True while the bubble is flying to its place after popping out.
    pub fn is_spawning(&self) -> bool {
        self.spawn.is_some()
    }

    /// Size relative to full size: smaller (and briefly larger, overshooting)
    /// while spawning, otherwise 1.
    pub fn scale(&self) -> f32 {
        self.spawn
            .as_ref()
            .map_or(1.0, |spawn| ease_out_back(spawn.progress))
    }

    /// Moves the bubble, including where it is flying to, by `offset`.
    pub fn translate(&mut self, offset: Vec2) {
        self.center += offset;
        if let Some(spawn) = &mut self.spawn {
            spawn.from += offset;
            spawn.to += offset;
        }
    }

    /// Advances the spawn flight and the open/close morph by `dt` seconds.
    pub fn animate(&mut self, dt: f32) {
        if let Some(spawn) = &mut self.spawn {
            spawn.progress = (spawn.progress + dt / SPAWN_SECONDS).min(1.0);
            self.center = spawn.from.lerp(spawn.to, ease_out_cubic(spawn.progress));
            if spawn.progress == 1.0 {
                self.spawn = None;
            }
        }

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
        let r = self.radius * self.scale();
        let half = (Vec2::splat(r) + (PANEL_SIZE / 2.0 - Vec2::splat(r)) * t).max(Vec2::splat(1.0));
        let max_round = half.min_elem();
        Shape {
            center: self.center,
            half,
            corner: lerp(CLOSED_CORNER * r, PANEL_CORNER, t).clamp(0.0, max_round),
            bevel: lerp(CLOSED_BEVEL * r, PANEL_BEVEL, t).clamp(1.0, max_round),
            exponent: CORNER_EXPONENT,
        }
    }

    pub fn contains(&self, p: Pos2) -> bool {
        self.shape().contains(p)
    }
}

/// A rounded rectangle with a lit, rounded rim. With `half` equal to `corner`
/// and `bevel` on both axes and an `exponent` of 2 it is a sphere.
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
    /// Superellipse exponent of the corners; 2 makes them circular arcs.
    pub exponent: f32,
}

impl Shape {
    pub fn circle(center: Pos2, radius: f32) -> Self {
        Self {
            center,
            half: Vec2::splat(radius),
            corner: radius,
            bevel: radius,
            exponent: 2.0,
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
            exponent: self.exponent,
        }
    }

    pub fn contains(&self, p: Pos2) -> bool {
        // Offset from the center of the nearest corner, inside the square of that corner.
        let q = (p - self.center).abs() - (self.half - Vec2::splat(self.corner));
        if q.x > self.corner || q.y > self.corner {
            return false;
        }
        if q.x <= 0.0 || q.y <= 0.0 || self.corner <= 0.0 {
            return true;
        }
        let q = q / self.corner;
        q.x.powf(self.exponent) + q.y.powf(self.exponent) <= 1.0
    }
}

fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

/// Starts fast and slows to a smooth stop.
fn ease_out_cubic(t: f32) -> f32 {
    1.0 - (1.0 - t).powi(3)
}

/// Eases out with a small overshoot, so bubbles pop open.
fn ease_out_back(t: f32) -> f32 {
    const C1: f32 = 1.0;
    const C3: f32 = C1 + 1.0;
    let u = t - 1.0;
    1.0 + C3 * u * u * u + C1 * u * u
}
