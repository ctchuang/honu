//! Bubble motion: momentum after a throw, an idle float, soft pushing between
//! crowded bubbles, and bounces off the window edges.

use eframe::egui::{Rect, Vec2, vec2};

use crate::Bubble;

/// Velocity decay rate (1/s); higher stops a thrown bubble sooner.
const FRICTION: f32 = 2.5;
/// Peak acceleration (px/s²) of the idle float.
const FLOAT_ACCEL: f32 = 14.0;
/// Bubbles only push each other once their centers are closer than this
/// fraction of the sum of their radii, so partial overlaps (which show off
/// the glass) are left alone.
const PERSONAL_SPACE: f32 = 0.7;
/// Spring stiffness (1/s²) of the push between crowded bubbles.
const PUSH_STIFFNESS: f32 = 25.0;
/// Fraction of speed kept after bouncing off a window edge.
const BOUNCE: f32 = 0.6;
/// Speed limit (px/s) for thrown bubbles.
const MAX_SPEED: f32 = 2500.0;

/// Advances all bubbles by `dt` seconds. The `held` bubble follows the pointer,
/// so it pushes others but is not moved by any force itself.
pub fn step(bubbles: &mut [Bubble], bounds: Rect, held: Option<usize>, time: f64, dt: f32) {
    let mut accel: Vec<Vec2> = bubbles.iter().map(|b| float_accel(b, time)).collect();

    for i in 0..bubbles.len() {
        for j in i + 1..bubbles.len() {
            let (a, b) = (&bubbles[i], &bubbles[j]);
            let delta = b.center - a.center;
            let dist = delta.length();
            let min_dist = PERSONAL_SPACE * (a.radius + b.radius);
            if dist >= min_dist {
                continue;
            }
            let dir = if dist > 1e-3 { delta / dist } else { Vec2::X };
            let force = dir * PUSH_STIFFNESS * (min_dist - dist);
            accel[i] -= force / mass(a);
            accel[j] += force / mass(b);
        }
    }

    for (i, (bubble, accel)) in bubbles.iter_mut().zip(accel).enumerate() {
        if Some(i) != held {
            bubble.velocity += accel * dt;
            bubble.velocity *= (-FRICTION * dt).exp();
            let speed = bubble.velocity.length();
            if speed > MAX_SPEED {
                bubble.velocity *= MAX_SPEED / speed;
            }
            bubble.center += bubble.velocity * dt;
        }
        confine(bubble, bounds);
    }
}

/// A slow, per-bubble wobble so idle bubbles drift instead of sitting still.
fn float_accel(bubble: &Bubble, time: f64) -> Vec2 {
    let t = time + f64::from(bubble.phase);
    FLOAT_ACCEL * vec2((t * 0.6).sin() as f32, (t * 0.45).cos() as f32)
}

/// Bigger bubbles are heavier and get pushed around less.
fn mass(bubble: &Bubble) -> f32 {
    (bubble.radius / 100.0).powi(2)
}

/// Keeps the whole bubble inside `bounds`, bouncing it off any edge it hits.
fn confine(bubble: &mut Bubble, bounds: Rect) {
    let r = bubble.radius;
    for axis in 0..2 {
        let (lo, hi) = (bounds.min[axis] + r, bounds.max[axis] - r);
        if lo > hi {
            // The window is smaller than the bubble: just center it.
            bubble.center[axis] = (bounds.min[axis] + bounds.max[axis]) / 2.0;
            bubble.velocity[axis] = 0.0;
        } else if bubble.center[axis] < lo {
            bubble.center[axis] = lo;
            bubble.velocity[axis] = bubble.velocity[axis].abs() * BOUNCE;
        } else if bubble.center[axis] > hi {
            bubble.center[axis] = hi;
            bubble.velocity[axis] = -bubble.velocity[axis].abs() * BOUNCE;
        }
    }
}
