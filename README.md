# Honu

<p align="center">
  <img src="docs/images/honu.svg" alt="Honu, a little green sea turtle" width="240">
</p>

An experimental desktop GUI and Human-Computer-Interface project for macOS, written in
Swift with SwiftUI and Liquid Glass.

> **Status:** experimental prototype. Expect breaking changes. The first version was
> written in Rust with [egui](https://github.com/emilk/egui) and lives in the git history.

## What it does

Liquid Glass bubbles float directly on your desktop, above other windows. A little
pixel turtle spits them out: notes to write in, questions for Claude whose answers stream
in, and web pages, which can also play YouTube videos. The bubble you press comes to the
top and covers the others.

## Getting started

Honu needs **macOS 26** or newer and a Swift 6.2 toolchain. Xcode is not required: the
Command Line Tools are enough.

```sh
xcode-select --install   # if you have neither Xcode nor the Command Line Tools
swift run                # build and launch
swift build -c release   # optimized build
```

### Install Claude Code (for Ask AI)

Honu asks Claude through [Claude Code](https://claude.com/claude-code), running it
headless (`claude -p`) for each question, so it needs no API key: install Claude Code and
run `claude` once in Terminal to sign in with your Claude account. Honu finds `claude` in
your `PATH` or where it is usually installed, and leaves out any `ANTHROPIC_API_KEY` in its
environment, so answers always come through your account.

### Floating on the desktop

Clicks pass through to the apps below everywhere except on a bubble. The window has no
close button: click a bubble to focus Honu, then press <kbd>⌘</kbd><kbd>Q</kbd> to quit
(or quit it from the Dock).

### Using the bubbles

- Honu starts with just a little pixel turtle in the bottom-left corner. **Drag** it to
  move it anywhere.
- **Click** or **right-click** the turtle for its menu: **Add Note** makes it spit out
  a note to write in, **Ask AI** a bubble where you ask Claude a question and watch the
  answer stream in (it breathes while Claude works, rises when the answer is in, and
  wobbles when something needs you), **Open Web Page** a bubble that asks for a link and then shows the
  page (YouTube links play the video), and **Exit** quits Honu. A closed note shows its
  first line.
- **Drag** a bubble to move it, and **throw** it to let it glide. Idle bubbles drift, and
  crowded ones push each other apart. The bubble you press or drag comes to the top and
  covers the others.
- To delete a bubble, drag it to the pixel octopus that comes up in a bottom corner
  while you drag, and let go. Changed your mind? For a few seconds afterwards,
  **click** the octopus (or press <kbd>⌘</kbd><kbd>Z</kbd>) and it spits the bubble back.
- **Double-click** a bubble to open it into a panel, and double-click its title to close it.
- The turtle, bubbles, notes, and pages are saved as you go, so quitting and reopening
  Honu brings them back where you left them. A bubble still in the octopus when you quit
  is gone.

## Development

```sh
swift test                                           # run the tests
swift format lint --strict -r Sources Tests Package.swift   # lint
swift format -i -r Sources Tests Package.swift     # format
```

## License

[MIT](LICENSE)
