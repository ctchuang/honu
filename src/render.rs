//! Custom painting for the desktop background and the bubbles.
//!
//! Everything is drawn as vertex-colored meshes: each bubble is a disk of
//! concentric rings whose vertex colors come from a tiny lighting model
//! (diffuse + specular, plus a Fresnel rim for glass), which gives the 3D look
//! without any custom shaders.

use eframe::egui::{Align2, Color32, FontId, Mesh, Painter, Pos2, Rect, Vec2, pos2, vec2};

use crate::Bubble;

const RINGS: usize = 28;
const SEGMENTS: usize = 72;
/// Width of the transparent outer ring that anti-aliases a disk's edge.
const FEATHER_PX: f32 = 1.5;

/// Direction towards the light: upper-left, in front of the screen.
/// Screen space has y pointing down; z points out of the screen.
const LIGHT: [f32; 3] = [-0.45, -0.6, 0.66];

type Rgba = [f32; 4];

pub fn paint_background(painter: &Painter, rect: Rect) {
    let top = Color32::from_rgb(222, 228, 240);
    let bottom = Color32::from_rgb(246, 236, 226);
    let mut mesh = Mesh::default();
    mesh.colored_vertex(rect.left_top(), top);
    mesh.colored_vertex(rect.right_top(), top);
    mesh.colored_vertex(rect.right_bottom(), bottom);
    mesh.colored_vertex(rect.left_bottom(), bottom);
    mesh.add_triangle(0, 1, 2);
    mesh.add_triangle(0, 2, 3);
    painter.add(mesh);

    // Large, faint color glows so translucent bubbles have something to show through.
    let glow = |center: Pos2, radius: f32, rgb: [f32; 3], strength: f32| {
        painter.add(radial_mesh(center, Vec2::splat(radius), 0.0, |x, y| {
            let falloff = (1.0 - (x * x + y * y)).max(0.0).powi(2);
            [rgb[0], rgb[1], rgb[2], strength * falloff]
        }));
    };
    let size = rect.size();
    glow(
        rect.min + size * vec2(0.85, 0.15),
        size.x * 0.45,
        [1.0, 0.75, 0.6],
        0.55,
    );
    glow(
        rect.min + size * vec2(0.1, 0.9),
        size.x * 0.4,
        [0.7, 0.65, 1.0],
        0.5,
    );

    // A subtle dot grid makes overlap and transparency easier to read.
    let dot = Color32::from_black_alpha(18);
    let spacing = 32.0;
    let mut y = rect.top() + spacing / 2.0;
    while y < rect.bottom() {
        let mut x = rect.left() + spacing / 2.0;
        while x < rect.right() {
            painter.circle_filled(pos2(x, y), 1.2, dot);
            x += spacing;
        }
        y += spacing;
    }
}

pub fn paint_bubble(painter: &Painter, bubble: &Bubble) {
    let r = bubble.radius;
    let base = to_rgb(bubble.color);

    // Soft drop shadow, offset away from the light.
    let shadow_alpha = if bubble.glass { 0.18 } else { 0.32 };
    let shadow_rgb = if bubble.glass {
        base.map(|c| c * 0.4)
    } else {
        [0.05, 0.05, 0.1]
    };
    let shadow_center = bubble.center + vec2(r * 0.12, r * 0.22);
    painter.add(radial_mesh(
        shadow_center,
        Vec2::splat(r * 1.12),
        0.0,
        |x, y| {
            let falloff = (1.0 - (x * x + y * y)).max(0.0).powi(2);
            [
                shadow_rgb[0],
                shadow_rgb[1],
                shadow_rgb[2],
                shadow_alpha * falloff,
            ]
        },
    ));

    let shade = if bubble.glass {
        shade_glass
    } else {
        shade_solid
    };
    painter.add(radial_mesh(
        bubble.center,
        Vec2::splat(r),
        FEATHER_PX,
        |x, y| shade(base, x, y),
    ));

    let text_color = if bubble.glass {
        Color32::from_rgba_unmultiplied(30, 40, 60, 210)
    } else {
        Color32::from_white_alpha(235)
    };
    painter.text(
        bubble.center,
        Align2::CENTER_CENTER,
        &bubble.label,
        FontId::proportional((r * 0.22).clamp(12.0, 28.0)),
        text_color,
    );
}

/// Opaque, glossy ball.
fn shade_solid(base: [f32; 3], x: f32, y: f32) -> Rgba {
    let (n, z) = normal(x, y);
    let diffuse = dot(n, normalize(LIGHT)).max(0.0);
    let half = half_vector();
    let n_dot_h = dot(n, half).max(0.0);

    let mut c = base.map(|b| b * (0.38 + 0.75 * diffuse));
    // Light bounced back from the floor brightens the lower rim a little.
    let bounce = (0.3 * x + 0.9 * y).max(0.0) * (1.0 - z).powi(2) * 0.35;
    c = mix(c, base.map(|b| (b * 1.3).min(1.0)), bounce);

    let spec = n_dot_h.powi(60) * 0.9 + n_dot_h.powi(8) * 0.12;
    c = mix(c, [1.0; 3], spec.min(1.0));
    [c[0], c[1], c[2], 1.0]
}

/// See-through glass: mostly clear in the middle, denser and more colored at
/// the rim (Fresnel), with a caustic glow opposite the light and a sharp highlight.
fn shade_glass(base: [f32; 3], x: f32, y: f32) -> Rgba {
    let (n, z) = normal(x, y);
    let fresnel = (1.0 - z).powi(2);
    let n_dot_h = dot(n, half_vector()).max(0.0);

    let mut c = mix(base, [1.0; 3], 0.35);
    let mut alpha = 0.10 + 0.6 * fresnel;

    // Crisp, darker edge so the outline reads clearly against anything behind.
    let r = (x * x + y * y).sqrt();
    let edge = ((r - 0.94) / 0.06).clamp(0.0, 1.0);
    c = mix(c, base.map(|b| b * 0.7), edge * 0.6);
    alpha += edge * 0.25;

    // Light focused through the ball pools on the side away from the light.
    let caustic = (0.35 * x + 0.85 * y).max(0.0).powi(5) * (1.0 - edge);
    c = mix(c, base.map(|b| (b * 1.25 + 0.15).min(1.0)), caustic);
    alpha += caustic * 0.35;

    let spec = n_dot_h.powi(80) + n_dot_h.powi(10) * 0.1;
    let spec = spec.min(1.0);
    c = mix(c, [1.0; 3], spec);
    alpha += spec * (1.0 - alpha);

    [c[0], c[1], c[2], alpha.min(1.0)]
}

/// Builds a filled ellipse as concentric rings of vertices. `color_at` receives
/// coordinates on the unit disk and returns unmultiplied RGBA in 0..=1.
/// A positive `feather` adds an outer ring that fades to transparent over that
/// many pixels, which anti-aliases the edge.
fn radial_mesh(
    center: Pos2,
    radius: Vec2,
    feather: f32,
    color_at: impl Fn(f32, f32) -> Rgba,
) -> Mesh {
    let mut mesh = Mesh::default();
    mesh.colored_vertex(center, to_color32(color_at(0.0, 0.0)));

    let ring_count = if feather > 0.0 { RINGS + 1 } else { RINGS };
    for ring in 1..=ring_count {
        let (t, fade) = if ring > RINGS {
            (1.0 + feather / radius.x.min(radius.y), true)
        } else {
            (ring as f32 / RINGS as f32, false)
        };
        for seg in 0..SEGMENTS {
            let angle = seg as f32 / SEGMENTS as f32 * std::f32::consts::TAU;
            let (sin, cos) = angle.sin_cos();
            // Sample the color on the disk edge for the feather ring.
            let (ux, uy) = if fade { (cos, sin) } else { (cos * t, sin * t) };
            let mut rgba = color_at(ux, uy);
            if fade {
                rgba[3] = 0.0;
            }
            let pos = center + vec2(cos * radius.x * t, sin * radius.y * t);
            mesh.colored_vertex(pos, to_color32(rgba));
        }
    }

    let segments = SEGMENTS as u32;
    for seg in 0..segments {
        let next = (seg + 1) % segments;
        mesh.add_triangle(0, 1 + seg, 1 + next);
    }
    for ring in 1..ring_count as u32 {
        let inner = 1 + (ring - 1) * segments;
        let outer = 1 + ring * segments;
        for seg in 0..segments {
            let next = (seg + 1) % segments;
            mesh.add_triangle(inner + seg, outer + seg, outer + next);
            mesh.add_triangle(inner + seg, outer + next, inner + next);
        }
    }
    mesh
}

/// Surface normal of a unit sphere seen from the front, and its z component.
fn normal(x: f32, y: f32) -> ([f32; 3], f32) {
    let z = (1.0 - x * x - y * y).max(0.0).sqrt();
    ([x, y, z], z)
}

/// Blinn-Phong half vector between the light and the viewer (looking along -z).
fn half_vector() -> [f32; 3] {
    let l = normalize(LIGHT);
    normalize([l[0], l[1], l[2] + 1.0])
}

fn normalize(v: [f32; 3]) -> [f32; 3] {
    let len = dot(v, v).sqrt();
    v.map(|c| c / len)
}

fn dot(a: [f32; 3], b: [f32; 3]) -> f32 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

fn mix(a: [f32; 3], b: [f32; 3], t: f32) -> [f32; 3] {
    [0, 1, 2].map(|i| a[i] + (b[i] - a[i]) * t)
}

fn to_rgb(color: Color32) -> [f32; 3] {
    [color.r(), color.g(), color.b()].map(|c| c as f32 / 255.0)
}

fn to_color32([r, g, b, a]: Rgba) -> Color32 {
    let byte = |c: f32| (c.clamp(0.0, 1.0) * 255.0).round() as u8;
    Color32::from_rgba_unmultiplied(byte(r), byte(g), byte(b), byte(a))
}
