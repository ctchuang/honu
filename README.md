# Honu

An experimental desktop GUI project written in Rust with [egui](https://github.com/emilk/egui) / eframe.

> **Status:** experimental. This is a playground for trying out egui, not a finished application. Expect breaking changes.

## What it does

Right now Honu is a minimal list app: type some text and press **Enter** or click **Add**, and it appears in a numbered, scrollable list. Items are kept in memory only and are lost when the window closes.

## Getting started

Requires a recent stable Rust toolchain (edition 2024).

```sh
cargo run              # build and launch the app
cargo build --release  # optimized build
```

## Development

```sh
cargo clippy --all-targets  # lint
cargo fmt                   # format
cargo test                  # run tests
```

## License

[MIT](LICENSE)
