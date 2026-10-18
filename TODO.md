# TODO

## Real refractive glass (wgpu shader)

Glass bubbles currently fake transparency by layering translucent vertex colors.
Real Liquid Glass–style glass would blur, magnify, and distort whatever is behind it.

- Needs custom WGSL shaders hooked into egui through its wgpu paint callbacks.
- The hard part is reading what is behind a bubble: egui callbacks draw into the
  frame being rendered and cannot sample it. Options:
  - **Background only**: render the wallpaper to a texture first and refract just that.
    Smaller (a few hundred lines), but overlapping bubbles would not refract each other.
  - **Full scene**: draw all bubbles in our own wgpu pass, copying the frame to a texture
    before each glass layer. Refracts everything, but replaces most of `render.rs` and
    decouples bubble drawing from egui.
- Refracting egui content inside open bubbles would also require rendering that content
  to a texture, so settle how bubble content is drawn before choosing an option.
- wgpu has breaking API changes in most releases and egui upgrades pull in new wgpu
  versions, so custom wgpu code adds upkeep on every egui upgrade.
- Keep it behind a switch so the CPU-shaded rendering stays available as a fallback.
