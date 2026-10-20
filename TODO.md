# TODO

## Documentations

- **Sample screenshot** - create a few microapps and put it in README
- **Demo video** - show how to bump bubbles to the 'Ask Claude' bubble
  in README.
- Explain how to login in Claud Code in README.

### Misc

- Remove mention of Liquid Glass in README

## UI Tweaking

- Allow bubble resizing.
- Remove the minimized mode.
- Fade-in effect of the speech bubble doesn't come from the octopus.
- **Physics shows status** (started): bubbles breathe when
  active. Rise when something finishes, and wobble when the user is
  needed (`MicroApp.isBusy`, `Context.play`). Ask AI and the Web
  microapp do all three (rises once it has, and wobbles if it
  fails). New kinds of bubbles should report their state the same way.

## Microapps

### Basic

- Add a launcher with stock apps: in progress, following the plan in
  `docs/Launcher.md`, whose steps are marked (done) as they land.
- Rename the 'Ask AI' to an always-on 'Ask Claude' bubble, migrate it
  to Web-based.
- Migrate the existing YouTube app to Web-based.
- Add a stock Facebook app.
- Migrate the existing Note app to Web-based (managed in the same way
  as other microspps).
- Uninstall and modify a microapp from the launcher (planned in
  `docs/Launcher.md`).
- Add more stock apps in a subfolder as examples.

### Memory

- Each generated microapp should have its own memory context to be
  shared with Claude.
- **Bumping and sticking bubbles together shares their context with
  Claude**: dragging one bubble into another hands both to Claude. The
  collision physics gives the gesture, and Liquid Glass already shows
  bubbles merging. Need to change it to bubble *sticking together*.

### Advanced

- **Install microapps from some place**: let a microapp be installed
  separately, without rebuilding Honu.
- **Every microapp is an MCP server**: each microapp offers its items
  and what can be done with them as MCP tools, so Claude can read and
  change them, and drive Honu through the same interface a microapp it
  generated would offer.

## Project

- **A web page for Honu**, hosted on GitHub Pages: a page that shows
  what Honu is (bubbles on the desktop, the turtle and the octopus)
  with a short demo video, and how to build and run it.
- **Support iPad**: iPadOS has no desktop to float over, so the
  bubbles would live in Honu's own window there; the models and
  SwiftUI views could be shared, while the AppKit hosting
  (`FloatingWindow`, `ClickThrough`, the event monitor) needs a UIKit
  counterpart, and dragging and the turtle's menu need to work by
  touch.
