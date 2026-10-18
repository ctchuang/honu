//! Bubble motion: momentum after a throw, an idle float, soft pushing between
//! crowded bubbles, and bounces off the window edges. Opened bubbles act like
//! windows: they can still be thrown, but they neither float nor push.
//! Bubbles flying out of the turtle or into the octopus follow their own
//! path and are left alone.

use eframe::egui::{Rect, Vec2, vec2};

use crate::view::bubble::Bubble;

/// Velocity decay rate (1/s); higher stops a thrown bubble sooner.
const FRICTION: f32 = 4.0;
/// Peak acceleration (px/s²) of the idle float.
const FLOAT_ACCEL: f32 = 14.0;
/// Bubbles only push each other once their centers are closer than this
/// fraction of the sum of their radii, so partial overlaps (which show off
/// the glass) are left alone.
const PERSONAL_SPACE: f32 = 0.8;
/// Spring stiffness of the push between crowded bubbles; a bubble of radius
/// 100 pressed in by 1px is pushed back at this many px/s².
const PUSH_STIFFNESS: f32 = 160.0;
/// Damping of that push relative to critical damping. It soaks up the impact
/// when bubbles collide, so they bump and share momentum instead of jiggling.
const PUSH_DAMPING: f32 = 0.45;
/// Fraction of speed kept after bouncing off a window edge.
const BOUNCE: f32 = 0.5;
/// Speed limit (px/s) for thrown bubbles.
const MAX_SPEED: f32 = 2500.0;

/// Advances all bubbles by `dt` seconds. The `held` bubble follows the pointer,
/// so it pushes others but is not moved by any force itself.
pub fn step(bubbles: &mut [Bubble], bounds: Rect, held: Option<usize>, time: f64, dt: f32) {
    let mut accel: Vec<Vec2> = bubbles
        .iter()
        .map(|b| {
            if b.is_closed() && !b.is_in_flight() {
                float_accel(b, time)
            } else {
                Vec2::ZERO
            }
        })
        .collect();

    for i in 0..bubbles.len() {
        for j in i + 1..bubbles.len() {
            let (a, b) = (&bubbles[i], &bubbles[j]);
            if !a.is_closed() || !b.is_closed() || a.is_in_flight() || b.is_in_flight() {
                continue;
            }
            let delta = b.center - a.center;
            let dist = delta.length();
            let min_dist = PERSONAL_SPACE * (a.radius + b.radius);
            if dist >= min_dist {
                continue;
            }
            let dir = if dist > 1e-3 { delta / dist } else { Vec2::X };
            let (ma, mb) = (mass(a), mass(b));
            let closing_speed = (a.velocity - b.velocity).dot(dir);
            let damping = PUSH_DAMPING * 2.0 * (PUSH_STIFFNESS * ma * mb / (ma + mb)).sqrt();
            // Never pull: separating bubbles should not stick together.
            let push = (PUSH_STIFFNESS * (min_dist - dist) + damping * closing_speed).max(0.0);
            accel[i] -= dir * push / ma;
            accel[j] += dir * push / mb;
        }
    }

    for (i, (bubble, accel)) in bubbles.iter_mut().zip(accel).enumerate() {
        if Some(i) != held && !bubble.is_in_flight() {
            bubble.velocity += accel * dt;
            bubble.velocity *= (-FRICTION * dt).exp();
            let speed = bubble.velocity.length();
            if speed > MAX_SPEED {
                bubble.velocity *= MAX_SPEED / speed;
            }
            bubble.center += bubble.velocity * dt;
        }
        // A bubble going into the octopus may dip below the edge with it.
        if !bubble.is_swallowing() {
            confine(bubble, bounds);
        }
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
    let half = bubble.shape().half;
    for axis in 0..2 {
        let (lo, hi) = (bounds.min[axis] + half[axis], bounds.max[axis] - half[axis]);
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::microapp::ViewTarget;
    use eframe::egui::{Color32, Pos2, pos2};

    const DT: f32 = 1.0 / 60.0;

    fn ball(x: f32, radius: f32) -> Bubble {
        Bubble::new(
            ViewTarget::TEST,
            pos2(x, 500.0),
            radius,
            Color32::WHITE,
            false,
        )
    }

    /// Runs the simulation for `seconds` in a large window, calling `watch` after each step.
    fn simulate(bubbles: &mut [Bubble], seconds: f32, mut watch: impl FnMut(&[Bubble])) {
        let bounds = Rect::from_min_max(Pos2::ZERO, pos2(4000.0, 1000.0));
        for frame in 0..(seconds / DT) as usize {
            step(bubbles, bounds, None, f64::from(frame as f32 * DT), DT);
            watch(bubbles);
        }
    }

    #[test]
    fn thrown_bubble_glides_a_short_way() {
        let mut bubbles = [ball(500.0, 80.0)];
        bubbles[0].velocity = vec2(1500.0, 0.0);
        simulate(&mut bubbles, 3.0, |_| {});
        let travel = bubbles[0].center.x - 500.0;
        eprintln!("glide travel: {travel:.0}px");
        assert!(travel < 450.0, "glided {travel:.0}px");
        assert!(bubbles[0].velocity.length() < 20.0);
    }

    #[test]
    fn thrown_bubble_knocks_another_instead_of_passing_through() {
        let mut bubbles = [ball(500.0, 80.0), ball(700.0, 80.0)];
        bubbles[0].velocity = vec2(1500.0, 0.0);
        let mut closest = f32::INFINITY;
        simulate(&mut bubbles, 3.0, |b| {
            closest = closest.min(b[1].center.x - b[0].center.x);
        });
        let knocked = bubbles[1].center.x - 700.0;
        eprintln!("closest: {closest:.0}px, knocked: {knocked:.0}px");
        assert!(closest > 100.0, "centers came within {closest:.0}px");
        assert!(knocked > 100.0, "only knocked {knocked:.0}px");
    }

    #[test]
    fn spawned_bubble_lands_where_it_was_placed() {
        let mut bubbles = [ball(500.0, 80.0), ball(900.0, 80.0)];
        let place = bubbles[1].center;
        bubbles[1].spawn_from(pos2(100.0, 900.0));
        let bounds = Rect::from_min_max(Pos2::ZERO, pos2(4000.0, 1000.0));
        let mut frame = 0;
        while bubbles[1].is_spawning() {
            bubbles[1].animate(DT);
            step(&mut bubbles, bounds, None, f64::from(frame as f32 * DT), DT);
            frame += 1;
        }
        let miss = (bubbles[1].center - place).length();
        assert!(miss < 1.0, "landed {miss:.1}px away");
        assert_eq!(bubbles[1].scale(), 1.0);
    }

    #[test]
    fn resting_partial_overlap_is_kept() {
        let mut bubbles = [ball(500.0, 80.0), ball(650.0, 80.0)];
        simulate(&mut bubbles, 3.0, |_| {});
        let gap = bubbles[1].center.x - bubbles[0].center.x;
        eprintln!("resting gap: {gap:.0}px");
        assert!(gap < 160.0, "pushed apart to {gap:.0}px");
    }
}
