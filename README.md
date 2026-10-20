# Honu

<p align="center">
  <img src="docs/images/honu.svg" alt="Honu, a little green sea turtle" width="240">
</p>

An experiment in having Claude Code create microapps on the fly, right
on your macOS desktop.

> **Status:** experimental prototype. Expect breaking changes.
>
> **Safety:** there is no protection against prompt injection.

## What it does

Microapp bubbles float right on your desktop. A little turtle spits
them out; drag a bubble to the octopus to remove it.

Describe a new microapp to the turtle, and Claude makes it in moments.
To change a microapp, type what you want into the bar at its bottom.

![Three microapps Claude made floating on the desktop (a world clock, a
Pomodoro timer, and a habit tracker with a change request typed into its
bar) beside the turtle's launcher](docs/images/demo.jpg)

> **TODO:** drag bubbles onto the turtle to give Claude their contents as context.

## Quick start in 30 seconds

If you already have Claude Code installed, start `claude` in this folder
and ask it to run Honu. Claude will make sure everything works.

## Getting started (longer version)

### Install Claude Code (for making microapps)

Honu asks Claude through [Claude Code](https://claude.com/claude-code), running it
headless (`claude -p`) for each request, so it needs no API key: install Claude Code and
run `claude` once in Terminal to sign in with your Claude account. Honu finds `claude` in
your `PATH` or where it is usually installed, and leaves out any `ANTHROPIC_API_KEY` in its
environment, so answers always come through your account.

### Build and run

Honu needs **macOS 26** or newer and a Swift 6.2 toolchain. Xcode is not required: the
Command Line Tools are enough.

```sh
xcode-select --install   # if you have neither Xcode nor the Command Line Tools
swift run                # build and launch
```

### Floating on the desktop

Clicks pass through to the apps below everywhere except on a bubble. The window has no
close button: click a bubble to focus Honu, then press <kbd>⌘</kbd><kbd>Q</kbd> to quit
(or quit it from the Dock).

### Using the bubbles

- Honu starts with just a little pixel turtle in the bottom-left corner. **Drag** it to
  move it anywhere.
- **Click** the turtle for its launcher, a panel of tiles. Click a tile and the turtle
  spits out a new bubble for it: **Note**, a note to write in (a closed note shows its
  first line); **Web Page**, a bubble that asks for a link and then shows the page
  (YouTube links play the video); any microapp Claude has made for you; and **+**, a new
  microapp: describe what you want, such as a pomodoro timer, and Claude writes it (the
  bubble breathes while Claude works, rises when it is done, and wobbles when something
  needs you). Each click opens a new one, with its own data.
- A microapp Claude has made gets a tile of its own and stays in the launcher. Ask
  Claude to change it in the bar below it (press Return or the **Go** button), and every
  open bubble of it changes. To uninstall it, drag its tile to the octopus, or
  **right-click** its tile and choose **Uninstall**; the built-in tiles stay put.
- **Right-click** the turtle for **Exit**, which quits Honu.
- **Drag** a bubble to move it, and **throw** it to let it glide. Idle bubbles drift, and
  crowded ones push each other apart. The bubble you press or drag comes to the top and
  covers the others.
- To delete a bubble, drag it to the pixel octopus that comes up in a bottom corner
  while you drag, and let go. Changed your mind? For a few seconds afterwards,
  **click** the octopus (or press <kbd>⌘</kbd><kbd>Z</kbd>) and it spits the bubble back,
  or the microapp you uninstalled, with its bubbles.
- **Double-click** a bubble to open it into a panel, and double-click its title to close it.
- The turtle, bubbles, notes, pages, and microapps are saved as you go, so quitting and
  reopening Honu brings them back where you left them. A bubble or microapp still in the
  octopus when you quit is gone.

## Development

Work happens on the `dev` branch; `main` is kept stable. Please open pull requests
against `dev`, not `main`.

```sh
swift test                                           # run the tests
swift format lint --strict -r Sources Tests Package.swift   # lint
swift format -i -r Sources Tests Package.swift     # format
git config core.hooksPath .githooks                  # lint and test before each push
```

The pre-push hook in `.githooks/` runs the lint and the tests when a push changes
Swift code (`git push --no-verify` skips it). Claude Code also lints each Swift file
it edits, through the hook in `.claude/settings.json`.

```sh
swift build -c release   # optimized build
```

## License

[MIT](LICENSE)
