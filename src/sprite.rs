//! The pixel-art sprites on the desktop: the turtle that spits out bubbles
//! and the octopus that deletes them. Both are drawn from character grids,
//! one character per pixel, through a shared `Grid`.

use eframe::egui::{Color32, Mesh, Painter, Pos2, Rect, Vec2, vec2};

pub mod octopus;
pub mod turtle;

/// Size of one sprite pixel, in points.
pub const PIXEL: f32 = 5.0;

/// The pixel grid of a sprite: how many pixels across and down.
#[derive(Clone, Copy)]
pub struct Grid {
    cols: usize,
    rows: usize,
}

impl Grid {
    pub const fn new(cols: usize, rows: usize) -> Self {
        Self { cols, rows }
    }

    /// Size of the whole sprite, in points.
    pub fn size(self) -> Vec2 {
        vec2(self.cols as f32, self.rows as f32) * PIXEL
    }

    /// The pixel (column, row) under `p`, for a sprite whose top-left corner
    /// is at `origin`.
    pub fn pixel_at(self, origin: Pos2, p: Pos2) -> Option<(usize, usize)> {
        let rel = (p - origin) / PIXEL;
        let inside =
            (0.0..self.cols as f32).contains(&rel.x) && (0.0..self.rows as f32).contains(&rel.y);
        inside.then_some((rel.x as usize, rel.y as usize))
    }

    /// Paints the sprite with its top-left corner at `origin`, each pixel in
    /// the color `color` gives it, or not at all if transparent.
    pub fn paint(
        self,
        painter: &Painter,
        origin: Pos2,
        color: impl Fn(usize, usize) -> Option<Color32>,
    ) {
        // One mesh of square, unblended pixels keeps the edges crisp.
        let mut mesh = Mesh::default();
        for y in 0..self.rows {
            for x in 0..self.cols {
                if let Some(color) = color(x, y) {
                    let min = origin + vec2(x as f32, y as f32) * PIXEL;
                    mesh.add_colored_rect(Rect::from_min_size(min, Vec2::splat(PIXEL)), color);
                }
            }
        }
        painter.add(mesh);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use eframe::egui::pos2;

    #[test]
    fn pixel_at_stays_inside_the_grid() {
        let grid = Grid::new(4, 2);
        let origin = pos2(100.0, 50.0);
        assert_eq!(grid.size(), vec2(4.0, 2.0) * PIXEL);
        assert_eq!(grid.pixel_at(origin, origin), Some((0, 0)));
        assert_eq!(
            grid.pixel_at(origin, origin + vec2(3.5, 1.5) * PIXEL),
            Some((3, 1))
        );
        assert_eq!(grid.pixel_at(origin, origin + vec2(4.0, 0.0) * PIXEL), None);
        assert_eq!(grid.pixel_at(origin, origin - vec2(0.1, 0.0)), None);
    }
}
