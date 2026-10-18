# Honu

An experimental desktop GUI and Human-Computer-Interface project written in Rust with [egui](https://github.com/emilk/egui) / eframe.

> **Status:** experimental. This is a playground for trying out egui, not a finished application. Expect breaking changes.

## What it does

Omitted for now.

## Getting started

### 1. Install Rust

Honu needs a stable Rust toolchain that supports edition 2024 (Rust 1.85 or newer).
The easiest way to get one is [rustup](https://rustup.rs):

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup update stable   # if Rust is already installed
```

Honu is developed on macOS. It builds on other platforms too, but floating on the
desktop with click-through (see below) currently works only on macOS.

### 2. Add your Claude API key (optional for now)

Honu will use Claude for its LLM features. Keep your key in a local `.env` file,
which git ignores:

```sh
cp .env.example .env
```

Then open `.env` and paste your key after `ANTHROPIC_API_KEY=`. You can create a key
in the [Claude Console](https://console.anthropic.com/settings/keys). Never commit
`.env` or put your key anywhere else in the repository; only the empty template
`.env.example` is tracked.

No feature uses the key yet, so you can skip this step until one does.

### 3. Run

```sh
cargo run                # build and launch
cargo run -- --windowed  # launch in an ordinary window instead
cargo build --release    # optimized build
```

By default the bubbles float directly on your desktop, above other windows. Clicks
pass through to the apps below everywhere except on a bubble. The window has no close
button: click a bubble to focus Honu, then press <kbd>⌘</kbd><kbd>Q</kbd> to quit
(or quit it from the Dock).

`--windowed` shows the bubbles in a regular window with their own wallpaper, which is
handy during development.

### Using the bubbles

- **Drag** a bubble to move it, and **throw** it to let it glide.
- **Double-click** a bubble to open it into a panel; double-click its title or edge to
  close it again.

## Development

```sh
cargo clippy --all-targets  # lint
cargo fmt                   # format
cargo test                  # run tests
```

## License

[MIT](LICENSE)
