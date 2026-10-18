//! Custom painting for the desktop background and the bubbles.
//!
//! Everything is drawn as vertex-colored meshes: each bubble is a stack of
//! concentric rounded-rectangle outlines
//! whose vertex colors come from a tiny lighting model (diffuse + specular,
//! plus a Fresnel rim for glass), which gives the 3D look without any custom
//! shaders.

use eframe::egui::{Align2, Color32, FontId, Mesh, Painter, Pos2, Rect, Vec2, pos2, vec2};

use crate::bubble::{Bubble, Shape};

const RINGS: usize = 28;
/// Points per quarter of an outline.
const ARC_POINTS: usize = 19;
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
        painter.add(shape_mesh(Shape::circle(center, radius), 0.0, |x, y| {
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

/// Paints a bubble's body and label. An opened bubble's content is drawn
/// separately by the caller, on top of this.
pub fn paint_bubble(painter: &Painter, bubble: &Bubble) {
    let r = bubble.radius * bubble.scale();
    let base = to_rgb(bubble.color);
    let shape = bubble.display_shape();
    let openness = bubble.openness();

    // Soft drop shadow, offset away from the light.
    let shadow_alpha = if bubble.glass { 0.18 } else { 0.14 };
    let shadow_rgb = if bubble.glass {
        base.map(|c| c * 0.4)
    } else {
        [0.05, 0.05, 0.1]
    };
    let mut shadow = shape.expand(r * 0.12);
    shadow.center += vec2(r * 0.12, r * 0.22);
    painter.add(shape_mesh(shadow, 0.0, |x, y| {
        let falloff = (1.0 - (x * x + y * y)).max(0.0).powi(2);
        [
            shadow_rgb[0],
            shadow_rgb[1],
            shadow_rgb[2],
            shadow_alpha * falloff,
        ]
    }));

    // Opened glass gets frosted so its content stays readable.
    let frost = 0.6 * openness.clamp(0.0, 1.0);
    painter.add(shape_mesh(shape, FEATHER_PX, |x, y| {
        if bubble.glass {
            let mut rgba = shade_glass(base, x, y);
            rgba[3] = rgba[3].max(frost);
            rgba
        } else {
            shade_solid(base, x, y)
        }
    }));

    // The label slides from the middle of the ball to the panel's title bar.
    let title_pos = pos2(shape.center.x, shape.rect().top() + 28.0);
    let label_pos = shape.center.lerp(title_pos, openness.clamp(0.0, 1.0));
    let closed_size = (r * 0.22).clamp(12.0, 28.0);
    painter.text(
        label_pos,
        Align2::CENTER_CENTER,
        &bubble.label,
        // Shrinks with a spawning bubble, so the label fits while it grows.
        FontId::proportional(
            ((closed_size + (20.0 - closed_size) * openness) * bubble.scale()).max(1.0),
        ),
        text_color(bubble),
    );
}

/// Color for text drawn on top of a bubble.
pub fn text_color(bubble: &Bubble) -> Color32 {
    let [r, g, b] = to_rgb(bubble.color);
    let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    if bubble.glass || luminance > 0.6 {
        Color32::from_rgba_unmultiplied(30, 40, 60, 220)
    } else {
        Color32::from_white_alpha(235)
    }
}

/// Opaque, nearly flat tile. The face keeps its true color; the narrow rim
/// only dims slightly as it turns away from the light, and a faint darker edge
/// keeps the outline crisp against light backgrounds.
fn shade_solid(base: [f32; 3], x: f32, y: f32) -> Rgba {
    let (n, _) = normal(x, y);
    let light = normalize(LIGHT);
    // Positive where the rim faces the light more than the flat face does.
    let tilt = dot(n, light).max(0.0) - light[2];
    let mut c = base.map(|b| (b * (1.0 + 0.07 * tilt)).min(1.0));

    let r = (x * x + y * y).sqrt();
    let edge = ((r - 0.92) / 0.08).clamp(0.0, 1.0);
    c = mix(c, base.map(|b| b * 0.9), edge * 0.5);
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

/// Builds a filled `shape` as nested outlines, each inset further from the
/// edge. `color_at` receives a point on the unit disk standing in for the
/// surface there: its direction is the outward direction of the edge, and its
/// length runs from 0 where the surface turns flat to 1 at the edge. It returns
/// unmultiplied RGBA in 0..=1. A positive `feather` adds an outer outline that
/// fades to transparent over that many pixels, which anti-aliases the edge.
fn shape_mesh(shape: Shape, feather: f32, color_at: impl Fn(f32, f32) -> Rgba) -> Mesh {
    // Each outline is (inset from the edge, position on the unit disk, alpha override).
    // The first is inset all the way, so it collapses to a line or point in the middle.
    let deepest = shape.half.min_elem();
    let mut outlines = vec![(deepest, 0.0, None)];
    for ring in 0..=RINGS {
        let t = ring as f32 / RINGS as f32;
        let inset = shape.bevel * (1.0 - t);
        if inset < deepest {
            outlines.push((inset, t, None));
        }
    }
    if feather > 0.0 {
        outlines.push((-feather, 1.0, Some(0.0)));
    }

    let mut mesh = Mesh::default();
    for &(inset, t, alpha) in &outlines {
        let half = shape.half - Vec2::splat(inset);
        let corner = (shape.corner - inset).max(0.0);
        let straight = (half - Vec2::splat(corner)).max(Vec2::ZERO);
        for quarter in 0..4 {
            // Quarters go clockwise on screen, starting at the bottom-right corner.
            let sign = [
                vec2(1.0, 1.0),
                vec2(-1.0, 1.0),
                vec2(-1.0, -1.0),
                vec2(1.0, -1.0),
            ][quarter];
            let corner_center = shape.center + straight * sign;
            for i in 0..ARC_POINTS {
                let angle = (quarter as f32 + i as f32 / (ARC_POINTS - 1) as f32)
                    * std::f32::consts::FRAC_PI_2;
                let (point, normal) = superellipse(angle, shape.exponent);
                let mut rgba = color_at(normal.x * t, normal.y * t);
                if let Some(alpha) = alpha {
                    rgba[3] = alpha;
                }
                mesh.colored_vertex(corner_center + point * corner, to_color32(rgba));
            }
        }
    }

    let points = (4 * ARC_POINTS) as u32;
    for outline in 1..outlines.len() as u32 {
        let inner = (outline - 1) * points;
        let outer = outline * points;
        for i in 0..points {
            let next = (i + 1) % points;
            mesh.add_triangle(inner + i, outer + i, outer + next);
            mesh.add_triangle(inner + i, outer + next, inner + next);
        }
    }
    mesh
}

/// A point on the unit superellipse |x|^n + |y|^n = 1 in the direction of
/// `angle`, and the outward unit normal there. With n = 2 it is a circle.
fn superellipse(angle: f32, n: f32) -> (Vec2, Vec2) {
    let (sin, cos) = angle.sin_cos();
    let curve = |c: f32, power: f32| c.signum() * c.abs().powf(power);
    let point = vec2(curve(cos, 2.0 / n), curve(sin, 2.0 / n));
    let normal = vec2(curve(point.x, n - 1.0), curve(point.y, n - 1.0)).normalized();
    (point, normal)
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
