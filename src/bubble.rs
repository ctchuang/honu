//! Bubbles and their outline. A bubble is a rounded square, like a macOS app
//! icon, when closed and morphs into a larger panel that shows its content
//! when opened. A new bubble pops out small and grows as it flies to its place.
//! Bubbles also show what they are doing through motion: a busy bubble
//! breathes, and a short gesture marks a finished task or a call for attention.
//! A bubble held over the octopus shrinks, and one dropped there is swallowed:
//! it shrinks away into the octopus's mouth.

use eframe::egui::{Color32, Pos2, Rect, Vec2, vec2};

use crate::ask::Ask;

/// Corner radius of a closed bubble, as a fraction of its radius.
const CLOSED_CORNER: f32 = 0.28;
/// Width of a closed bubble's rounded, lit rim, as a fraction of its radius.
/// Keep it at most the corner radius: a wider rim makes its inner edge
/// square-cornered, which shows as diagonal creases at the corners.
const CLOSED_BEVEL: f32 = 0.2;
/// Superellipse exponent of the corners. 2 would be circular arcs; higher
/// values give the smoother, continuous-curvature corners of macOS shapes.
const CORNER_EXPONENT: f32 = 4.0;
/// Size of an opened bubble, unless its content asks for another height.
const PANEL_SIZE: Vec2 = vec2(380.0, 300.0);
/// How quickly an opened panel follows a new height (1/s); higher is snappier.
const PANEL_RESIZE_RATE: f32 = 10.0;
/// Corner radius of an opened bubble.
const PANEL_CORNER: f32 = 22.0;
/// Width of the rounded, lit rim of an opened bubble; at most `PANEL_CORNER`.
const PANEL_BEVEL: f32 = 14.0;
/// Seconds to open or close a bubble.
const MORPH_SECONDS: f32 = 0.35;
/// Seconds a new bubble takes to fly to its place.
const SPAWN_SECONDS: f32 = 1.6;
/// How far a busy bubble's outline swells at the height of each breath.
const BREATH_POINTS: f32 = 4.0;
/// Breaths per second while busy.
const BREATH_RATE: f32 = 0.8;
/// How quickly breathing fades in and out (1/s), so it never starts or stops abruptly.
const BREATH_FADE_RATE: f32 = 3.0;
/// Size, relative to full size, of a bubble held over the octopus.
const DOOMED_SCALE: f32 = 0.6;
/// How quickly a bubble shrinks over the octopus and grows back (1/s).
const SHRINK_RATE: f32 = 14.0;
/// Seconds a swallowed bubble takes to disappear into the octopus's mouth.
const SWALLOW_SECONDS: f32 = 0.3;

/// A short motion that marks a change in what the bubble is doing.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Gesture {
    /// Floats up a little and settles back: something finished.
    Rise,
    /// Shakes side to side: something needs the user.
    Wobble,
}

impl Gesture {
    fn seconds(self) -> f32 {
        match self {
            Gesture::Rise => 1.2,
            Gesture::Wobble => 0.6,
        }
    }

    /// How far the gesture moves the bubble `t` seconds in; back to zero by the end.
    fn offset(self, t: f32) -> Vec2 {
        let u = (t / self.seconds()).clamp(0.0, 1.0);
        match self {
            Gesture::Rise => vec2(0.0, -16.0 * (std::f32::consts::PI * u).sin()),
            Gesture::Wobble => {
                let shake = (std::f32::consts::TAU * 5.0 * t).sin();
                vec2(8.0 * shake * (1.0 - u).powi(2), 0.0)
            }
        }
    }
}

/// What an opened bubble shows.
pub enum Content {
    Notes(String),
    /// A question for Claude and its answer.
    Ask(Ask),
    Empty,
}

/// A new bubble's flight from where it popped out to its place.
struct Spawn {
    from: Pos2,
    to: Pos2,
    /// Linear progress of the flight, from 0 to 1.
    progress: f32,
}

/// A bubble's last trip, from where it was dropped into the octopus's mouth.
struct Swallow {
    from: Pos2,
    to: Pos2,
    /// How shrunk the bubble already was when dropped.
    from_shrink: f32,
    /// Linear progress of the trip, from 0 to 1.
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
    /// Whether to open as soon as the spawn flight lands.
    open_on_landing: bool,
    /// Size of the opened panel, easing towards `panel_target`.
    panel: Vec2,
    panel_target: Vec2,
    /// Whether the bubble is working on something, which makes it breathe.
    busy: bool,
    /// How strongly the bubble breathes, easing between 0 and 1 with `busy`.
    breath: f32,
    /// Seconds of breathing so far, for its rhythm.
    breath_time: f32,
    /// The gesture being played and how many seconds into it.
    gesture: Option<(Gesture, f32)>,
    /// Whether the bubble is held over the octopus, which makes it shrink.
    doomed: bool,
    /// Size relative to full size, shrinking over the octopus and to nothing
    /// when swallowed.
    shrink: f32,
    /// Set once the bubble has been dropped on the octopus.
    swallow: Option<Swallow>,
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
            open_on_landing: false,
            panel: PANEL_SIZE,
            panel_target: PANEL_SIZE,
            busy: false,
            breath: 0.0,
            breath_time: 0.0,
            gesture: None,
            doomed: false,
            shrink: 1.0,
            swallow: None,
        }
    }

    /// Shrinks the bubble while `doomed`, to show that letting go deletes it.
    pub fn set_doomed(&mut self, doomed: bool) {
        self.doomed = doomed;
    }

    /// Makes the bubble shrink away into `mouth`.
    pub fn swallow_into(&mut self, mouth: Pos2) {
        self.swallow = Some(Swallow {
            from: self.center,
            to: mouth,
            from_shrink: self.shrink,
            progress: 0.0,
        });
        self.velocity = Vec2::ZERO;
    }

    /// True once a swallowed bubble has disappeared.
    pub fn is_swallowed(&self) -> bool {
        self.swallow.as_ref().is_some_and(|s| s.progress == 1.0)
    }

    /// Brings a swallowed bubble back: it pops out of `from` and flies back to
    /// `home`, and reopens on landing if it was open.
    pub fn spit_back(&mut self, from: Pos2, home: Pos2) {
        self.swallow = None;
        self.doomed = false;
        self.shrink = 1.0;
        self.gesture = None;
        if self.open {
            // Fly back closed, like any new bubble, and open where it lands.
            self.open = false;
            self.progress = 0.0;
            self.open_on_landing = true;
        }
        self.center = home;
        self.spawn_from(from);
    }

    /// Makes the bubble breathe while `busy`, fading in and out.
    pub fn set_busy(&mut self, busy: bool) {
        self.busy = busy;
    }

    /// Plays `gesture`, replacing any gesture still playing.
    pub fn play(&mut self, gesture: Gesture) {
        self.gesture = Some((gesture, 0.0));
    }

    pub fn with_content(mut self, content: Content) -> Self {
        self.content = content;
        self
    }

    /// Opens the bubble as soon as it lands after spawning.
    pub fn open_on_landing(mut self) -> Self {
        self.open_on_landing = true;
        self
    }

    /// Size of the opened panel once it has finished resizing.
    pub fn panel_target(&self) -> Vec2 {
        self.panel_target
    }

    /// Makes the opened panel grow or shrink smoothly to `height`.
    pub fn set_panel_height(&mut self, height: f32) {
        self.panel_target.y = height;
    }

    /// Resizes the panel immediately, as for a bubble that starts out with
    /// a different height.
    pub fn with_panel_height(mut self, height: f32) -> Self {
        self.panel_target.y = height;
        self.panel.y = height;
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
        // Squaring the progress keeps the bubble small for longer as it leaves,
        // so it visibly grows on the way instead of all at once.
        self.spawn
            .as_ref()
            .map_or(1.0, |spawn| ease_out_back(spawn.progress.powi(2)))
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
        if let Some(swallow) = &mut self.swallow {
            swallow.progress = (swallow.progress + dt / SWALLOW_SECONDS).min(1.0);
            let t = swallow.progress * swallow.progress;
            self.center = swallow.from.lerp(swallow.to, t);
            self.shrink = swallow.from_shrink * (1.0 - t);
        } else {
            let target = if self.doomed { DOOMED_SCALE } else { 1.0 };
            self.shrink += (target - self.shrink) * (1.0 - (-SHRINK_RATE * dt).exp());
            if (self.shrink - target).abs() < 0.001 {
                // Settle exactly, so content shows again once full size.
                self.shrink = target;
            }
        }
        if let Some(spawn) = &mut self.spawn {
            spawn.progress = (spawn.progress + dt / SPAWN_SECONDS).min(1.0);
            self.center = spawn.from.lerp(spawn.to, ease_out_quad(spawn.progress));
            if spawn.progress == 1.0 {
                self.spawn = None;
                if self.open_on_landing {
                    self.open = true;
                    self.open_on_landing = false;
                }
            }
        }
        self.panel += (self.panel_target - self.panel) * (1.0 - (-PANEL_RESIZE_RATE * dt).exp());

        let target = if self.busy { 1.0 } else { 0.0 };
        self.breath += (target - self.breath) * (1.0 - (-BREATH_FADE_RATE * dt).exp());
        self.breath_time = if self.breath > 0.001 {
            self.breath_time + dt
        } else {
            0.0
        };
        if let Some((gesture, t)) = &mut self.gesture {
            *t += dt;
            if *t >= gesture.seconds() {
                self.gesture = None;
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

    /// True when fully open, at full size, and ready to show its content.
    pub fn is_fully_open(&self) -> bool {
        self.open && self.progress == 1.0 && self.shrink == 1.0
    }

    /// The bubble's outline, used for hit-testing, physics, and laying out its
    /// content. Gestures move it as a whole, so content moves along unchanged.
    pub fn shape(&self) -> Shape {
        let gesture = self
            .gesture
            .map_or(Vec2::ZERO, |(gesture, t)| gesture.offset(t));
        let t = self.openness();
        let r = self.radius * self.scale();
        let k = self.shrink;
        let half = (Vec2::splat(r) + (self.panel / 2.0 - Vec2::splat(r)) * t) * k;
        let half = half.max(Vec2::splat(1.0));
        let max_round = half.min_elem();
        Shape {
            center: self.center + gesture,
            half,
            corner: (lerp(CLOSED_CORNER * r, PANEL_CORNER, t) * k).clamp(0.0, max_round),
            bevel: (lerp(CLOSED_BEVEL * r, PANEL_BEVEL, t) * k).clamp(1.0, max_round),
            exponent: CORNER_EXPONENT,
        }
    }

    /// The outline as drawn: `shape` swelled by the current breath. Breathing
    /// only shows in the drawing, so content and hit-testing hold still.
    pub fn display_shape(&self) -> Shape {
        let swell = 0.5 - 0.5 * (std::f32::consts::TAU * BREATH_RATE * self.breath_time).cos();
        self.shape().expand(BREATH_POINTS * self.breath * swell)
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

/// Starts moving and slows to a smooth stop.
fn ease_out_quad(t: f32) -> f32 {
    1.0 - (1.0 - t).powi(2)
}

/// Eases out with a small overshoot, so bubbles pop open.
fn ease_out_back(t: f32) -> f32 {
    const C1: f32 = 1.0;
    const C3: f32 = C1 + 1.0;
    let u = t - 1.0;
    1.0 + C3 * u * u * u + C1 * u * u
}

#[cfg(test)]
mod tests {
    use super::*;
    use eframe::egui::pos2;

    const DT: f32 = 1.0 / 60.0;

    fn bubble() -> Bubble {
        Bubble::new("", pos2(500.0, 500.0), 80.0, Color32::WHITE, false)
    }

    fn run(bubble: &mut Bubble, seconds: f32, mut watch: impl FnMut(&Bubble)) {
        for _ in 0..(seconds / DT) as usize {
            bubble.animate(DT);
            watch(bubble);
        }
    }

    #[test]
    fn rounded_corners_are_not_hit() {
        let shape = bubble().shape();
        let rect = shape.rect();
        assert!(shape.contains(rect.center()));
        assert!(shape.contains(rect.left_center() + vec2(1.0, 0.0)), "edge");
        assert!(!shape.contains(rect.left_top() + vec2(1.0, 1.0)), "corner");
        assert!(
            !shape.contains(rect.right_bottom() + vec2(1.0, 1.0)),
            "outside"
        );
    }

    #[test]
    fn gestures_move_the_bubble_and_return_it() {
        for gesture in [Gesture::Rise, Gesture::Wobble] {
            let mut bubble = bubble();
            let rest = bubble.shape().center;
            bubble.play(gesture);
            let mut farthest = 0.0_f32;
            run(&mut bubble, 2.0, |b| {
                farthest = farthest.max((b.shape().center - rest).length());
            });
            assert!(farthest > 5.0, "{gesture:?} moved only {farthest:.1}");
            assert_eq!(bubble.shape().center, rest, "{gesture:?} did not settle");
            assert_eq!(bubble.center, rest, "{gesture:?} moved the bubble itself");
        }
    }

    #[test]
    fn swallowed_bubble_comes_back_whole() {
        let mut bubble = bubble();
        let home = bubble.center;
        let full = bubble.shape().half;
        bubble.open = true;
        run(&mut bubble, 1.0, |_| {});
        bubble.set_doomed(true);
        run(&mut bubble, 0.5, |_| {});
        assert!(!bubble.is_fully_open(), "content shows while shrunk");
        let mouth = pos2(100.0, 900.0);
        bubble.swallow_into(mouth);
        run(&mut bubble, 1.0, |_| {});
        assert!(bubble.is_swallowed());
        assert_eq!(bubble.center, mouth);
        assert!(
            bubble.shape().half.x <= 1.0,
            "still visible after swallowing"
        );

        bubble.spit_back(mouth, home);
        assert!(bubble.is_spawning() && !bubble.is_swallowed());
        run(&mut bubble, 3.0, |_| {});
        assert_eq!(bubble.center, home);
        assert!(bubble.is_fully_open(), "did not reopen on landing");
        bubble.open = false;
        run(&mut bubble, 1.0, |_| {});
        assert_eq!(bubble.shape().half, full);
    }

    #[test]
    fn breathing_swells_only_the_drawing_and_fades_out() {
        let mut bubble = bubble();
        let rest = bubble.shape().half;
        bubble.set_busy(true);
        let mut widest = 0.0_f32;
        run(&mut bubble, 3.0, |b| {
            assert_eq!(b.shape().half, rest, "breathing changed the hit area");
            widest = widest.max(b.display_shape().half.x - rest.x);
        });
        assert!(widest > BREATH_POINTS * 0.8, "swelled only {widest:.1}");
        bubble.set_busy(false);
        run(&mut bubble, 3.0, |_| {});
        assert!(bubble.display_shape().half.x - rest.x < 0.1);
    }
}
