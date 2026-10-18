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

## LLM integration

The guiding idea: Claude should work with the bubbles on the desktop, not live in a
chat window. Done so far: the turtle's menu has **Ask…**, which spits out a bubble
whose answer streams in while the panel grows to fit it (`src/ask.rs`, `src/claude.rs`).

- **Spit out several bubbles at once** (next step): give Claude a `create_bubble` tool,
  so "give me five weekend ideas" becomes five bubbles the turtle spits out one by one.
  Reuses the spawn animation, tool use, and streaming that already exist.
- **Answers as UI, not paragraphs**: define a small set of `Content` kinds (list,
  checklist, card, button, progress) that Claude fills through tool use or structured
  output, and that Honu draws.
- **Bumping bubbles shares their context**: dragging one bubble into another hands
  both to Claude, to compare them or find what links them. The collision physics
  already provides the gesture.
- **Physics shows status** (started): Ask bubbles breathe while Claude works, float up
  when the answer is in, and wobble when something needs the user (`Bubble::set_busy`,
  `Gesture`). New kinds of bubbles should report their state the same way.
- **Space as memory**: bubbles that sit together belong to the same project. Needs the
  bubbles saved to disk; only the turtle's place persists today, so Ask bubbles vanish
  when Honu quits.
- **Confirm before side effects**: before Claude sends mail, changes a file, or runs a
  command, the turtle spits out a confirmation bubble, and nothing happens until it is
  accepted. Each bubble should also show where it came from.

Smaller improvements:

- **Follow-up questions**: an Ask bubble answers only one question today; let it carry
  on as a multi-turn conversation.
