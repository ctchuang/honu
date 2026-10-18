# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Honu is a native desktop GUI app written in Rust (edition 2024) using **eframe/egui 0.37** — currently a simple list app: type text, press Enter or "Add", and it appears in a numbered, scrollable list. State is in-memory only (no persistence).

## Commands

```sh
cargo run                    # build and launch the app window
cargo build --release        # optimized build
cargo clippy --all-targets   # lint
cargo fmt                    # format (cargo fmt --check to verify)
cargo test                   # run tests (none exist yet)
cargo test <name>            # run a single test by name filter
```

## Architecture

Everything lives in `src/main.rs`:

- `main()` configures the window (`NativeOptions` / `ViewportBuilder`) and starts the event loop with `eframe::run_native`, constructing `HonuApp` via `Default`.
- `HonuApp` holds all app state as plain fields.
- `impl eframe::App for HonuApp` renders the UI. egui is **immediate mode**: `ui()` runs every frame and rebuilds the whole interface from the current state, so UI changes are made by mutating `HonuApp` fields, not by holding widget handles.

Note that egui 0.37's `App` trait uses `fn ui(&mut self, ui: &mut egui::Ui, frame: &mut eframe::Frame)`; older egui examples online use `fn update(&mut self, ctx: &egui::Context, ...)` and won't compile as-is.

## Conventions

- All user-facing UI text must be in English.
