# TODO

## Docs

- Once the connectors are ready, explain the interactive and
  fully-customizable microapps can show information from Slack, Uber
  Eats, Gmail, Google Calendar, etc.

## UI Tweaking

- [P2] Can we make the bubble look like bubble (jelly effect)?
- [P2] Fade-in effect of the speech bubble doesn't come from the
  octopus.
- [P2] **Physics shows status** (started): bubbles breathe when
  active. Rise when something finishes, and wobble when the user is
  needed (`MicroApp.isBusy`, `Context.play`). Ask AI and the Web
  microapp do all three (rises once it has, and wobbles if it
  fails). New kinds of bubbles should report their state the same way.

## Microapps

### Basic

- Type to filter the launcher's microapps by typing text directly
  (`docs/Launcher.md`, Later).

### More apps (TBD)

- Add a stock Facebook app.
- Migrate the existing YouTube app to Web-based.
- Migrate the existing Note app to Web-based (managed in the same way
  as other microapps).
- Add top 20 web sites as built-in microapps.
- Add more built-in apps in a subfolder as examples.

### Works with Claude (TBD)

- Read the user's services, such as a summary of Gmail or Slack, through
  their Claude connectors (draft PRD in `docs/Connectors.md`).
- Each generated microapp should have its own memory context.
- **The key step:** Find a way to feed the content of a running
  microapp to Claude.
  - Possible design 1: Drag a bubble to the turtle creates a request
    to Claude by sharing its memory context.
  - Possible design 2: Create a 'Ask Claude' button when a microapp is
    focused.
- **Every microapp is an MCP server**: each microapp offers its items
  and what can be done with them as MCP tools, so Claude can read and
  change them, and drive Honu through the same interface a microapp it
  generated would offer. (TBD: Lack obvious CUJs.)
- **Bumping and sticking bubbles together shares their context with
  Claude** (Gimmicks?): dragging one bubble into another hands both to
  Claude. The collision physics gives the gesture, and Liquid Glass
  already shows bubbles merging. Need to change it to bubble *sticking
  together*.

## Project

- Tests multiple displays.
- **Package Honu as a downloadable app**: today `swift build -c
  release` makes a bare executable, which opens a Terminal window from
  the Finder, has no Info.plist, icon, or bundle id, and stops at
  `Bundle.module` (the Dock icon in `AppDelegate`) when moved without
  its `Honu_Honu.bundle`.
  - Load the icon some other way than `Bundle.module`, such as an
    `.icns` in the app's `Contents/Resources` (`CFBundleIconFile`).
  - Add `scripts/package-app.sh`: a release build, assembled into
    `Honu.app` with an Info.plist and the icon, ad-hoc signed, and
    zipped.
  - Attach `Honu-<version>.zip` to the GitHub release (v0.1 has only
    the source).
  - Without notarization (an Apple Developer account), Gatekeeper
    warns of an unidentified developer on first launch: right-click
    and Open, or `xattr -d com.apple.quarantine`. Say so in the
    README.
- **Support iPad**: iPadOS has no desktop to float over, so the
  bubbles would live in Honu's own window there; the models and
  SwiftUI views could be shared, while the AppKit hosting
  (`FloatingWindow`, `ClickThrough`, the event monitor) needs a UIKit
  counterpart, and dragging and the turtle's menu need to work by
  touch.
- Integrates with Coding agents other than Claude Code, such as Codex
  CLI. (Antigravity may not be integrated due to license permission
  restrictions).
