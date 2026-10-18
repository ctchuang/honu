//! The pixel-art octopus that deletes bubbles. It rises from the bottom edge
//! while a bubble is being dragged, in the corner away from the turtle, and
//! stays out of sight the rest of the time. A bubble dropped on it is
//! swallowed. For a few seconds afterwards the octopus waits with the bubble
//! still inside, and clicking it (or pressing ⌘Z) spits the bubble back to
//! where it was picked up, so a slip of the hand loses nothing.

use eframe::egui::{
    Align2, Color32, CornerRadius, FontId, Mesh, Painter, Pos2, Rect, Vec2, pos2, vec2,
};

use crate::bubble::Bubble;

/// The head and body, one character per pixel: Outline, Body, White
/// highlight, Eye (also the mouth), Pink cheek, and `.` for transparent.
const HEAD: [&str; 11] = [
    "......OOOOOO......",
    "....OOBBBBBBOO....",
    "...OBBWWBBBBBBO...",
    "..OBBWBBBBBBBBBO..",
    "..OBBBBBBBBBBBBO..",
    "..OBBWEBBBBWEBBO..",
    "..OBBEEBBBBEEBBO..",
    "..OBBBBBBBBBBBBO..",
    "..OBPBBBEEBBBPBO..",
    "..OBBBBBBBBBBBBO..",
    ".OBBBBBBBBBBBBBBO.",
];
/// The tentacles below the head, in two frames that sway them left and right.
const TENTACLES: [[&str; 4]; 2] = [
    [
        ".OBBOBBOBBOBBOBBO.",
        ".OBBOBBOBBOBBOBBO.",
        "OBBOBBOBBOBBOBBO..",
        ".OO.OO.OO.OO.OO...",
    ],
    [
        ".OBBOBBOBBOBBOBBO.",
        ".OBBOBBOBBOBBOBBO.",
        "..OBBOBBOBBOBBOBBO",
        "...OO.OO.OO.OO.OO.",
    ],
];
/// Pixels (column, row) that turn dark when the mouth opens wide.
const OPEN_MOUTH: [(usize, usize); 2] = [(8, 9), (9, 9)];
/// Where swallowed bubbles go in and spat-out ones come out, in sprite pixels.
const MOUTH: Vec2 = vec2(9.0, 9.0);
/// Size of one sprite pixel, in points, matching the turtle.
const PIXEL: f32 = 5.0;
/// Gap between the octopus and the corner of the window.
const MARGIN: f32 = 24.0;
/// How far from the octopus's middle the pointer may be for a dropped bubble
/// to be swallowed. Wider than the sprite, so dropping on it takes no aim.
const REACH: f32 = 80.0;
/// How quickly the octopus rises into view and sinks away (1/s).
const SHOW_RATE: f32 = 12.0;
/// Seconds a swallowed bubble can still be brought back.
const UNDO_SECONDS: f64 = 5.0;
/// Seconds the gulp after swallowing lasts.
const GULP_SECONDS: f64 = 0.3;
/// Tentacle sways per second while idle and while eagerly waiting for a drop.
const SWAY_RATE: f64 = 2.0;
const EAGER_SWAY_RATE: f64 = 6.0;

/// A swallowed bubble and where it was picked up, to return it there.
struct Swallowed {
    bubble: Bubble,
    home: Pos2,
}

pub struct Octopus {
    /// Top-left corner of the sprite this frame.
    origin: Pos2,
    /// Whether it sits in the bottom-right corner rather than the bottom-left.
    right: bool,
    /// How far it has risen into view, from 0 (hidden) to 1.
    shown: f32,
    /// Whether a bubble is being dragged, which calls the octopus up.
    summoned: bool,
    /// Whether a bubble is held over it, ready to be dropped.
    eager: bool,
    /// When it last gulped down or spat out a bubble, in seconds of app time.
    gulped_at: f64,
    /// Until when swallowed bubbles can be brought back.
    undo_until: f64,
    /// Bubbles on their way into the mouth.
    swallowing: Vec<Swallowed>,
    /// Bubbles swallowed recently enough to be brought back, the latest last.
    stomach: Vec<Swallowed>,
    /// Where the "Click to undo" hint was drawn last frame. It takes clicks
    /// like the octopus itself, since it looks like a button.
    hint: Option<Rect>,
}

impl Octopus {
    pub fn new() -> Self {
        Self {
            origin: Pos2::ZERO,
            right: true,
            shown: 0.0,
            summoned: false,
            eager: false,
            gulped_at: f64::NEG_INFINITY,
            undo_until: f64::NEG_INFINITY,
            swallowing: Vec::new(),
            stomach: Vec::new(),
            hint: None,
        }
    }

    /// Calls the octopus up while `summoned`, as while a bubble is dragged.
    pub fn summon(&mut self, summoned: bool) {
        self.summoned = summoned;
    }

    /// Opens its mouth while a bubble is held over it.
    pub fn set_eager(&mut self, eager: bool) {
        self.eager = eager;
    }

    /// Whether a bubble dropped with the pointer at `p` would be swallowed.
    pub fn in_reach(&self, p: Pos2) -> bool {
        self.shown > 0.5 && (p - self.middle()).length() < REACH
    }

    /// Whether `p` is on one of the octopus's visible pixels or on its undo hint.
    pub fn contains(&self, p: Pos2) -> bool {
        if self.shown == 0.0 {
            return false;
        }
        if self.can_undo() && self.hint.is_some_and(|hint| hint.contains(p)) {
            return true;
        }
        let rel = (p - self.origin) / PIXEL;
        if rel.x < 0.0 || rel.y < 0.0 {
            return false;
        }
        self.pixel(rel.x as usize, rel.y as usize, 0.0)
            .is_some_and(|c| c != '.')
    }

    /// Swallows `bubble`, which was picked up at `home`.
    pub fn swallow(&mut self, mut bubble: Bubble, home: Pos2) {
        bubble.swallow_into(self.mouth());
        self.swallowing.push(Swallowed { bubble, home });
    }

    /// Whether a swallowed bubble can still be brought back.
    pub fn can_undo(&self) -> bool {
        !self.stomach.is_empty()
    }

    /// Spits the latest swallowed bubble back towards where it was picked up.
    pub fn spit_back(&mut self, time: f64) -> Option<Bubble> {
        let Swallowed { mut bubble, home } = self.stomach.pop()?;
        bubble.spit_back(self.mouth(), home);
        self.gulped_at = time;
        // Leave time to bring back the one swallowed before it, too.
        self.undo_until = time + UNDO_SECONDS;
        Some(bubble)
    }

    /// Bubbles on their way into the mouth, to be painted below the octopus.
    pub fn swallowing(&self) -> impl Iterator<Item = &Bubble> {
        self.swallowing.iter().map(|s| &s.bubble)
    }

    /// Every bubble inside: those being swallowed and those that can still
    /// be brought back.
    pub fn contents(&self) -> impl Iterator<Item = &Bubble> {
        self.swallowing
            .iter()
            .chain(&self.stomach)
            .map(|s| &s.bubble)
    }

    /// Moves the bubbles inside along with the others when the window changes size.
    pub fn translate(&mut self, offset: Vec2) {
        for swallowed in self.swallowing.iter_mut().chain(&mut self.stomach) {
            swallowed.bubble.translate(offset);
            swallowed.home += offset;
        }
    }

    /// Advances swallowing, forgets bubbles too old to bring back, and rises
    /// or sinks in the bottom corner of `canvas` farther from `turtle`. Call
    /// once per frame before hit-testing or painting. Returns the bubbles
    /// forgotten this frame, which are now deleted for good.
    pub fn update(&mut self, canvas: Rect, turtle: Pos2, time: f64, dt: f32) -> Vec<Bubble> {
        for swallowed in &mut self.swallowing {
            swallowed.bubble.animate(dt);
        }
        let (done, going): (Vec<_>, Vec<_>) = std::mem::take(&mut self.swallowing)
            .into_iter()
            .partition(|s| s.bubble.is_swallowed());
        self.swallowing = going;
        if !done.is_empty() {
            self.stomach.extend(done);
            self.gulped_at = time;
            self.undo_until = time + UNDO_SECONDS;
        }
        let gone = if time >= self.undo_until {
            std::mem::take(&mut self.stomach)
                .into_iter()
                .map(|s| s.bubble)
                .collect()
        } else {
            Vec::new()
        };

        let wanted = self.summoned || !self.swallowing.is_empty() || self.can_undo();
        let target = if wanted { 1.0 } else { 0.0 };
        self.shown += (target - self.shown) * (1.0 - (-SHOW_RATE * dt).exp());
        if (self.shown - target).abs() < 0.01 {
            self.shown = target;
        }
        if self.shown == 0.0 {
            // Only pick a corner while out of sight, so it never jumps sideways.
            self.right = turtle.x < canvas.center().x;
        }

        let size = sprite_size();
        let x = if self.right {
            canvas.right() - MARGIN - size.x
        } else {
            canvas.left() + MARGIN
        };
        // Rise from below the bottom edge, slowing as it arrives.
        let hidden = (1.0 - self.shown).powi(2) * (size.y + MARGIN);
        let gulp = (time - self.gulped_at) / GULP_SECONDS;
        let lift = if (0.0..1.0).contains(&gulp) || self.eager {
            PIXEL
        } else {
            0.0
        };
        self.origin = pos2(x, canvas.bottom() - MARGIN - size.y + hidden - lift).round();
        gone
    }

    pub fn paint(&mut self, painter: &Painter, time: f64) {
        self.hint = None;
        if self.shown == 0.0 {
            return;
        }
        // One mesh of square, unblended pixels keeps the edges crisp.
        let mut mesh = Mesh::default();
        for y in 0..HEAD.len() + TENTACLES[0].len() {
            for x in 0..HEAD[0].len() {
                if let Some(color) = self.pixel(x, y, time).and_then(color) {
                    let min = self.origin + vec2(x as f32, y as f32) * PIXEL;
                    mesh.add_colored_rect(Rect::from_min_size(min, Vec2::splat(PIXEL)), color);
                }
            }
        }
        painter.add(mesh);

        if self.can_undo() {
            // Fade the hint out over the last second it applies.
            let fade = ((self.undo_until - time) as f32).clamp(0.0, 1.0);
            let text = painter.layout_no_wrap(
                "Click to undo".to_owned(),
                FontId::proportional(13.0),
                Color32::WHITE.gamma_multiply(fade),
            );
            let center = pos2(self.middle().x, self.origin.y - 18.0);
            let pill = Rect::from_center_size(center, text.size() + vec2(16.0, 8.0));
            let fill = Color32::from_rgba_unmultiplied(40, 20, 34, 200).gamma_multiply(fade);
            painter.rect_filled(pill, CornerRadius::same(255), fill);
            self.hint = Some(pill);
            painter.galley(
                Align2::CENTER_CENTER
                    .align_size_within_rect(text.size(), pill)
                    .min,
                text,
                Color32::WHITE,
            );
        }
    }

    /// The sprite pixel at (`x`, `y`) at `time`, with the tentacles swaying
    /// and the mouth open while eager or swallowing.
    fn pixel(&self, x: usize, y: usize, time: f64) -> Option<char> {
        let mouth_open = self.eager || !self.swallowing.is_empty();
        if mouth_open && OPEN_MOUTH.contains(&(x, y)) {
            return Some('E');
        }
        let row = match HEAD.get(y) {
            Some(row) => row,
            None => {
                let rate = if self.eager {
                    EAGER_SWAY_RATE
                } else {
                    SWAY_RATE
                };
                let frame = (time * rate) as usize % 2;
                TENTACLES[frame].get(y - HEAD.len())?
            }
        };
        row.chars().nth(x)
    }

    fn middle(&self) -> Pos2 {
        self.origin + sprite_size() / 2.0
    }

    fn mouth(&self) -> Pos2 {
        self.origin + MOUTH * PIXEL
    }
}

fn sprite_size() -> Vec2 {
    vec2(
        HEAD[0].len() as f32,
        (HEAD.len() + TENTACLES[0].len()) as f32,
    ) * PIXEL
}

fn color(c: char) -> Option<Color32> {
    let rgb = Color32::from_rgb;
    Some(match c {
        'O' => rgb(118, 46, 90),
        'B' => rgb(236, 120, 158),
        'W' => Color32::WHITE,
        'E' => rgb(48, 22, 40),
        'P' => rgb(255, 182, 204),
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::microapp::ViewTarget;

    const DT: f32 = 1.0 / 60.0;

    fn canvas() -> Rect {
        Rect::from_min_size(Pos2::ZERO, vec2(1000.0, 700.0))
    }

    /// Runs the octopus and any bubbles it swallowed for `seconds` from
    /// `start`. Returns the time reached and the bubbles deleted for good.
    fn run(octopus: &mut Octopus, turtle: Pos2, start: f64, seconds: f64) -> (f64, Vec<Bubble>) {
        let mut time = start;
        let mut gone = Vec::new();
        while time < start + seconds {
            gone.extend(octopus.update(canvas(), turtle, time, DT));
            time += f64::from(DT);
        }
        (time, gone)
    }

    #[test]
    fn sprite_rows_have_equal_length() {
        let rows = HEAD.iter().chain(TENTACLES.iter().flatten());
        assert!(rows.into_iter().all(|row| row.len() == HEAD[0].len()));
    }

    #[test]
    fn rises_away_from_the_turtle_only_while_needed() {
        let mut octopus = Octopus::new();
        let turtle = pos2(60.0, 650.0);
        run(&mut octopus, turtle, 0.0, 1.0);
        assert!(!octopus.contains(octopus.middle()), "visible while idle");

        octopus.summon(true);
        run(&mut octopus, turtle, 1.0, 1.0);
        let middle = octopus.middle();
        assert!(octopus.contains(middle) && octopus.in_reach(middle));
        assert!(middle.x > canvas().center().x, "not across from the turtle");
        assert!(canvas().contains(octopus.origin + sprite_size()));

        octopus.summon(false);
        run(&mut octopus, turtle, 2.0, 1.0);
        assert!(!octopus.in_reach(middle), "still there after the drag");
    }

    #[test]
    fn swallowed_bubble_can_be_brought_back_until_it_is_too_late() {
        let mut octopus = Octopus::new();
        let turtle = pos2(60.0, 650.0);
        octopus.summon(true);
        let (time, _) = run(&mut octopus, turtle, 0.0, 1.0);
        octopus.summon(false);
        let home = pos2(400.0, 300.0);
        let bubble = Bubble::new(
            ViewTarget::TEST,
            octopus.middle(),
            80.0,
            Color32::WHITE,
            false,
        );
        octopus.swallow(bubble, home);
        let (time, _) = run(&mut octopus, turtle, time, 1.0);
        assert!(octopus.can_undo());
        assert!(
            octopus.in_reach(octopus.middle()),
            "hid while it could undo"
        );

        // The hint above it takes clicks too, but only while it applies.
        let hint = Rect::from_center_size(octopus.origin - vec2(0.0, 18.0), vec2(90.0, 24.0));
        octopus.hint = Some(hint);
        assert!(octopus.contains(hint.center()), "hint does not take clicks");

        let mut bubble = octopus.spit_back(time).expect("nothing to spit back");
        assert!(
            !octopus.contains(hint.center()),
            "hint takes clicks with nothing to undo"
        );
        assert!(!octopus.can_undo());
        for _ in 0..200 {
            bubble.animate(DT);
        }
        assert_eq!(bubble.center, home);

        octopus.swallow(bubble, home);
        let (_, gone) = run(&mut octopus, turtle, time, UNDO_SECONDS + 1.0);
        assert!(!octopus.can_undo(), "kept the bubble too long");
        assert_eq!(gone.len(), 1, "did not report the deleted bubble");
        assert_eq!(octopus.contents().count(), 0);
        assert!(octopus.spit_back(time).is_none());
    }
}
