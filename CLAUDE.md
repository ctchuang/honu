# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Honu is a native desktop GUI app written in Rust (edition 2024) using **eframe/egui 0.37** — an experiment in desktop GUI design that departs from Windows/macOS conventions. It currently renders draggable, window-like bubbles (some opaque, some translucent glass) that float directly on the real macOS desktop, above all other windows. Only the turtle's place persists across launches, through eframe's `persistence` feature (`~/Library/Application Support/Honu/app.ron` on macOS; delete it to reset); everything else is in-memory.

## Commands

```sh
cargo run                    # build and launch; bubbles float on the real desktop (quit with ⌘Q)
cargo run -- --windowed      # launch in an ordinary window with its own wallpaper instead
cargo build --release        # optimized build
cargo clippy --all-targets   # lint
cargo fmt                    # format (cargo fmt --check to verify)
cargo test                   # run tests (physics simulations in src/physics.rs)
cargo test <name>            # run a single test by name filter
```

## Architecture

- `src/main.rs`: `main()` configures the window (`NativeOptions` / `ViewportBuilder`): by default transparent, borderless, and always on top, maximized after the first frame to cover the screen except the menu bar and Dock; with `--windowed`, an ordinary window that paints its own wallpaper. The window and Dock icon is `assets/icon.png`, embedded at compile time and rendered at 512×512 from its source `assets/icon.svg` (the README illustration lives separately in `docs/images/`). It then starts the event loop with `eframe::run_native`, constructing `HonuApp` via `Default`. `HonuApp` holds all state; `bubbles` is kept in back-to-front paint order, and pressing on a bubble moves it to the end (top). The app starts with only the turtle on screen: the starting bubbles wait in `pending`, and clicking the turtle makes it spit them out one at a time. `impl eframe::App for HonuApp` allocates one full-window painter, handles drag, double-click, and hit-testing on it, then paints each bubble followed by its content (if open), so content stacks correctly, and paints the turtle last, above everything. `save` and the end of each turtle drag store the turtle's offset from the window center, under separate keys for floating and `--windowed`; the drag-end save matters because quitting with ⌘Q or from the Dock exits without calling `save`. Window and egui-memory persistence are turned off. Right-clicking or long-pressing (`LONG_PRESS_SECONDS`) the turtle opens `TurtleMenu`, a foreground `egui::Area` with an Exit item; while it is open the floating window takes every click, and a press outside it or Escape closes it. Only the top bubble's content takes input, so bubbles lying over another's content can still be grabbed.
- `src/desktop.rs`: reads the global mouse position (CoreGraphics on macOS). While floating, the window lets mouse events through (`ViewportCommand::MousePassthrough`) except when the mouse is on a bubble or the turtle; since a pass-through window gets no pointer events, this global position is polled every frame to decide.
- `src/bubble.rs`: `Bubble` and its outline `Shape`, a rounded rectangle with superellipse corners and a lit rim. A closed bubble is a rounded square like a macOS app icon; double-clicking toggles `open`, and the bubble then morphs (with a small overshoot) into a larger panel that shows its `Content`. A released bubble comes out of the turtle's mouth small and grows (`scale()`) as it flies to its place along its own path (`spawn_from`).
- `src/physics.rs`: per-frame motion, stepped from `ui()` before painting. Released bubbles keep the pointer's velocity and slow down with friction, idle bubbles drift with a slow per-bubble float, crowded bubbles push each other apart with a damped soft collision that passes momentum on (partial overlaps are allowed so the glass stays visible), and bubbles bounce off the window edges. Open bubbles can be thrown but neither float nor push, and spawning bubbles are left out of the simulation until they land. The app repaints continuously.
- `src/turtle.rs`: the pixel-art sea turtle, which starts in the bottom-left corner and can be dragged anywhere inside the window, drawn from a character-grid sprite as one mesh of square pixels. It bobs while idle, hops when clicked, and briefly opens its mouth (`spit`) for each bubble; hit-testing ignores its transparent pixels.
- `src/render.rs`: all custom drawing. Bubbles are vertex-colored meshes of nested rounded-rectangle outlines with superellipse (continuous-curvature) corners shaded on the CPU by a small lighting model (diffuse/specular, Fresnel rim for glass); there are no custom shaders, so true background blur/refraction is not implemented (planned in `TODO.md`).

egui is **immediate mode**: `ui()` runs every frame and rebuilds the whole interface from the current state, so UI changes are made by mutating `HonuApp` fields, not by holding widget handles.

Note that egui 0.37's `App` trait uses `fn ui(&mut self, ui: &mut egui::Ui, frame: &mut eframe::Frame)`; older egui examples online use `fn update(&mut self, ctx: &egui::Context, ...)` and won't compile as-is.

## Conventions

- Everything in the repository must be in English: identifiers, comments, UI strings, docs, and commit messages — even when the conversation is in Chinese.
- After changing Rust code, run `cargo clippy --all-targets` and `cargo fmt --check` before reporting the work as done, and fix any warnings they raise.
- The Claude API key lives in `.env` at the repository root as `ANTHROPIC_API_KEY` (the name the Anthropic SDKs read). `.env` and `.env.*` are git-ignored; only the empty template `.env.example` is committed. Never read, print, or commit `.env`, and never put a key anywhere else in the repository.
