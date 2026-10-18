//! The pixel-art sea turtle that starts in the bottom-left corner of the
//! desktop and can be dragged anywhere. Clicking it makes it spit out the
//! bubbles.

use eframe::egui::{Color32, Mesh, Painter, Pos2, Rect, Vec2, pos2, vec2};

/// The sprite, one character per pixel: Outline, Shell, Light shell spot,
/// sKin, Rim, Eye, White highlight, Pink cheek, and `.` for transparent.
const SPRITE: [&str; 14] = [
    "......OOOOOOO...........",
    "....OOSSSSSSSOO.........",
    "...OSSWWSSSSSSSO........",
    "..OSWWSSLLLLSSSSO..OOOO.",
    "..OSWSSLLLLLLSSSO.OKKKKO",
    ".OSSSSSLLLLLLSSSSOKKEWKO",
    ".OSLLSSSLLLLSSLLSOKKEEKO",
    ".OSLLSSSSSSSSSLLSOKPKKKO",
    "ORRRRRRRRRRRRRRRRROKKOKO",
    ".ORRRRRRRRRRRRRRRROOOOO.",
    "..OOOOOOOOOOOOOOOO......",
    "...OKKKO.......OKKKKO...",
    "...OKKO.........OKKKKO..",
    "....OO...........OOOO...",
];
/// Pixels (column, row) that turn into the dark inside of the open mouth.
const OPEN_MOUTH: [(usize, usize); 4] = [(22, 7), (23, 7), (22, 8), (23, 8)];
/// Where bubbles come out, in sprite pixels: the front of the open mouth.
const MOUTH: Vec2 = vec2(24.0, 8.0);
/// Seconds the mouth stays open after spitting.
const MOUTH_SECONDS: f64 = 0.3;
/// Size of one sprite pixel, in points.
const PIXEL: f32 = 5.0;
/// Gap between the turtle and the corner of the window.
const MARGIN: f32 = 24.0;
/// Seconds a hop lasts.
const HOP_SECONDS: f64 = 0.35;
/// Height of a hop, in sprite pixels.
const HOP_PIXELS: f64 = 3.0;
/// Idle bobs per second; the turtle rises one sprite pixel on every other one.
const BOB_RATE: f64 = 1.5;

pub struct Turtle {
    /// Top-left corner of the sprite this frame.
    origin: Pos2,
    /// Top-left corner of the sprite at rest, before any hop or bob.
    rest: Pos2,
    /// Whether the turtle has been dragged; until then it stays in the
    /// bottom-left corner.
    moved: bool,
    /// When the last hop started, in seconds of app time.
    hopped_at: f64,
    /// When the turtle last spat out a bubble, in seconds of app time.
    spat_at: f64,
    /// Whether the mouth is open this frame.
    mouth_open: bool,
}

impl Turtle {
    pub fn new() -> Self {
        Self {
            origin: Pos2::ZERO,
            rest: Pos2::ZERO,
            moved: false,
            hopped_at: f64::NEG_INFINITY,
            spat_at: f64::NEG_INFINITY,
            mouth_open: false,
        }
    }

    /// Starts a little hop at `time`.
    pub fn hop(&mut self, time: f64) {
        self.hopped_at = time;
    }

    /// Opens the mouth for a moment at `time` and returns where a bubble
    /// should come out.
    pub fn spit(&mut self, time: f64) -> Pos2 {
        self.spat_at = time;
        self.mouth_open = true;
        self.origin + MOUTH * PIXEL
    }

    /// Moves the turtle by `delta`, as when dragged.
    pub fn move_by(&mut self, delta: Vec2) {
        self.rest += delta;
        self.moved = true;
    }

    /// Moves a dragged turtle along with the bubbles when the window changes
    /// size; one still in its corner follows the corner instead.
    pub fn translate(&mut self, offset: Vec2) {
        if self.moved {
            self.rest += offset;
        }
    }

    /// Places the turtle inside `canvas` (in the bottom-left corner until it
    /// is dragged), lifted by a hop or an idle bob. Call once per frame before
    /// hit-testing or painting.
    pub fn place(&mut self, canvas: Rect, time: f64) {
        let hop = (time - self.hopped_at) / HOP_SECONDS;
        let lift = if (0.0..1.0).contains(&hop) {
            (std::f64::consts::PI * hop).sin() * HOP_PIXELS
        } else {
            ((time * BOB_RATE) as i64 % 2) as f64
        };
        // Move in whole sprite pixels, as pixel art does.
        let lift = lift.round() as f32 * PIXEL;
        self.mouth_open = time - self.spat_at < MOUTH_SECONDS;
        let size = sprite_size();
        if !self.moved {
            self.rest = pos2(canvas.left() + MARGIN, canvas.bottom() - MARGIN - size.y);
        }
        self.rest = self
            .rest
            .clamp(canvas.min, (canvas.max - size).max(canvas.min));
        self.origin = (self.rest - vec2(0.0, lift)).round();
    }

    /// Whether `p` is on one of the turtle's visible pixels.
    pub fn contains(&self, p: Pos2) -> bool {
        let rel = (p - self.origin) / PIXEL;
        if rel.x < 0.0 || rel.y < 0.0 {
            return false;
        }
        SPRITE
            .get(rel.y as usize)
            .and_then(|row| row.as_bytes().get(rel.x as usize))
            .is_some_and(|&c| c != b'.')
    }

    pub fn paint(&self, painter: &Painter) {
        // One mesh of square, unblended pixels keeps the edges crisp.
        let mut mesh = Mesh::default();
        for (y, row) in SPRITE.iter().enumerate() {
            for (x, c) in row.chars().enumerate() {
                let c = if self.mouth_open && OPEN_MOUTH.contains(&(x, y)) {
                    'E'
                } else {
                    c
                };
                if let Some(color) = color(c) {
                    let min = self.origin + vec2(x as f32, y as f32) * PIXEL;
                    mesh.add_colored_rect(Rect::from_min_size(min, Vec2::splat(PIXEL)), color);
                }
            }
        }
        painter.add(mesh);
    }
}

fn sprite_size() -> Vec2 {
    vec2(SPRITE[0].len() as f32, SPRITE.len() as f32) * PIXEL
}

fn color(c: char) -> Option<Color32> {
    let rgb = Color32::from_rgb;
    Some(match c {
        'O' => rgb(47, 111, 70),
        'S' => rgb(95, 184, 120),
        'L' => rgb(127, 207, 147),
        'K' => rgb(143, 214, 160),
        'R' => rgb(244, 223, 160),
        'E' => rgb(31, 59, 44),
        'W' => Color32::WHITE,
        'P' => rgb(255, 159, 178),
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sprite_rows_have_equal_length() {
        assert!(SPRITE.iter().all(|row| row.len() == SPRITE[0].len()));
    }

    #[test]
    fn hit_test_ignores_transparent_pixels() {
        let mut turtle = Turtle::new();
        turtle.place(Rect::from_min_size(Pos2::ZERO, vec2(800.0, 600.0)), 0.0);
        let pixel = |x: f32, y: f32| turtle.origin + vec2(x + 0.5, y + 0.5) * PIXEL;
        assert!(turtle.contains(pixel(8.0, 4.0)), "shell");
        assert!(!turtle.contains(pixel(0.0, 0.0)), "empty corner");
        assert!(!turtle.contains(pixel(30.0, 4.0)), "outside the sprite");
    }

    #[test]
    fn dragged_turtle_stays_inside_the_window() {
        let canvas = Rect::from_min_size(Pos2::ZERO, vec2(800.0, 600.0));
        let mut turtle = Turtle::new();
        turtle.place(canvas, 0.0);
        turtle.move_by(vec2(300.0, -200.0));
        turtle.place(canvas, 0.0);
        assert_eq!(
            turtle.rest,
            pos2(MARGIN + 300.0, 600.0 - MARGIN - sprite_size().y - 200.0)
        );
        turtle.move_by(vec2(5000.0, 5000.0));
        turtle.place(canvas, 0.0);
        assert_eq!(turtle.rest, canvas.max - sprite_size());
    }

    #[test]
    fn open_mouth_is_on_the_head() {
        for (x, y) in OPEN_MOUTH {
            assert!(matches!(SPRITE[y].as_bytes()[x], b'K' | b'O'), "({x}, {y})");
        }
    }
}
