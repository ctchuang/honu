#!/bin/bash
# Prepares a Claude Code cloud session to build, lint, and test Honu natively
# and for the web (see CLAUDE.md for the commands).
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"
rustup component add clippy rustfmt
rustup target add wasm32-unknown-unknown
# Download the crates now, so later builds need no network.
cargo fetch
