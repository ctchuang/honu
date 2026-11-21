# TODO

## Docs

- Once connectors are ready, show that microapps can display
  information from Slack, Uber Eats, Gmail, Google Calendar, etc.

## UI

- [P2] The speech bubble's fade-in doesn't come from the octopus.
- [P2] **Physics shows status** (started): bubbles breathe while busy,
  rise when done, and wobble when the user is needed (`MicroApp.isBusy`,
  `Context.play`). Ask AI and Web do all three; new kinds of bubbles
  should too.

## Microapps

- Type to filter the launcher (`docs/Launcher.md`, Later).

### More apps (TBD)

- A stock Facebook app.
- A YouTube app in the Reef, in place of the Web microapp's special case
  for YouTube links (`PageSource`), which is off the launcher.
- The top 20 web sites as built-in microapps.
- More apps in the Reef (`docs/BuiltinApps.md`); a web one needs only
  `Sources/Honu/BuiltinApps/<name>/`, no Swift.

### Works with Claude (TBD)

- Read the user's services (Gmail, Slack, ...) through their Claude
  connectors (draft: `docs/Connectors.md`).
- Give each generated microapp its own memory context.
- **Key step:** feed a running microapp's content to Claude, either by
  dragging its bubble to the turtle, or with an "Ask Claude" button on
  the focused microapp.
- **Every microapp is an MCP server**, offering its items and actions as
  tools, so Claude can read, change, and drive them. (No obvious CUJs
  yet.)
- **Stick bubbles together to share their context with Claude**
  (gimmick?): drag one into another to hand both to Claude. Needs
  bubbles that stick, not just collide.

## Project

- Test multiple displays.
- **Restore old versions of data safely**, perhaps by keeping `~/.honu/`
  in a local git repository (a commit per autosave that changed
  something, or per hour).
- **Sync across devices**, perhaps through iCloud. Never put a git
  repository in iCloud Drive, which syncs `.git` file by file and
  corrupts it; keep history local and sync apart from it (CloudKit
  records per item, rather than one `state.json` that two Macs
  overwrite). Needs a PRD in `docs/`.
- **Package Honu as a downloadable app.** A release build is a bare
  executable: no Info.plist, icon, or bundle id, it opens Terminal from
  the Finder, and `Bundle.module` fails without `Honu_Honu.bundle`.
  - Load the icon from an `.icns` in `Contents/Resources`
    (`CFBundleIconFile`), not `Bundle.module`.
  - `scripts/package-app.sh`: build, assemble `Honu.app`, ad-hoc sign,
    zip.
  - Attach `Honu-<version>.zip` to GitHub releases.
  - Without notarization, Gatekeeper warns on first launch; document
    right-click > Open or `xattr -d com.apple.quarantine` in the README.
- **Support iPad**: bubbles live in Honu's own window; share the models
  and SwiftUI views, replace the AppKit hosting (`FloatingWindow`,
  `ClickThrough`, the event monitor) with UIKit, and make dragging and
  the turtle's menu work by touch.
- Support coding agents other than Claude Code, such as Codex CLI
  (Antigravity's license may not allow it).
