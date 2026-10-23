# Built-in Microapps

A PRD and implementation plan for a folder of built-in microapps in the
launcher, some written in Swift into Honu itself, some as single web
pages shipped with it. It follows `UI.md` and extends `Launcher.md`.

## PRD

### Background

The launcher lists the built-in microapps (Note), then the microapps the
user had Claude make, then **+**, all in one grid. Built-in microapps are
Swift `MicroApp`s; every microapp Claude makes is a web page running in a
`WebView`, through the Maker.

Honu is to ship more built-in microapps, as examples of what a microapp
can be and as everyday tools. Many are easier to write as a web page than
in Swift, and a web page is the form Claude already writes microapps in.
As they grow in number, they should not crowd out the microapps the user
made.

### Goals

- The launcher's built-in microapps go into a **folder**, the **Reef**,
  a tile that opens to show them, so the top level is the user's own microapps.
- A built-in microapp can be **native** (Swift, in the Honu binary, as
  Note is) or **web** (a single-page web app shipped in Honu's resources,
  running in a `WebView`), and the user cannot tell them apart in the
  launcher.
- Web built-in microapps run as the microapps Claude makes do: every
  launch is a new instance with data of its own, kept across launches,
  with the same `window.honu` bridge.
- Adding a web built-in microapp is adding a folder with its page to the
  sources: no Swift.

### Non-goals

- Changing a built-in microapp with Claude, or uninstalling one. (Making
  an installed copy to change is in **Later**.)
- Migrating Note to a web page; its own PRD will decide (`TODO.md`).
- Folders of the user's own, or moving tiles between folders.
- Downloading built-in microapps, or updating them apart from Honu.

### Terms

- **Built-in microapp**: one shipped with Honu.
  - **Native**: a Swift `MicroApp` in the binary (Note).
  - **Web**: a page (`index.html`, and any files beside it) in Honu's
    resources.
- **Installed microapp**: one the user had Claude make (`Launcher.md`).
  It is always a web page.
- **Folder**: a launcher tile that opens to a page of tiles of its own.
- **Reef**: the folder of built-in microapps. It is named for the sea
  the turtle and the octopus live in, not for where its microapps come
  from; its tiles show what is inside.

So there are three kinds of microapps:

| | Runs as | Written by | Changed with Claude | Uninstalled | In the launcher |
|---|---|---|---|---|---|
| Built-in native | Swift `MicroApp` | Honu | No | No | Reef |
| Built-in web | Web page from Honu's resources | Honu | No | No | Reef |
| Installed | Web page in `microapps/` | Claude, from the user's description | Yes | Yes | Top level |

Microapps left off the launcher (Ask AI and Web Page, `isLaunchable`
false) stay registered so saved items load, and show in no folder.

### User stories

1. As a user, I click the turtle and see my own microapps and a
   **Reef** folder, so what I made is never buried.
2. As a user, I click the folder and see every built-in microapp, and
   click one to start it, as any other tile.
3. As a user, I go back from the folder to the top level with its back
   button or Escape.
4. As a user, I start a web built-in microapp twice and get two bubbles,
   each keeping its own data across launches, as with an installed
   microapp.

### Behavior

**Launcher, top level**

- Tiles, in order: the **Reef** folder, the installed microapps in
  the order they were installed, then **+**.
- The folder's tile shows up to four of its microapps' symbols in a
  small grid, and its name. It does not drag: it wobbles, as built-in
  tiles do.

**Launcher, in the folder**

- Clicking the folder shows its tiles in the same panel, in place of the
  top level, under a header with a back button (a chevron) and the
  folder's name. The panel resizes to fit and stays on screen, as it
  does now; past three rows it scrolls.
- Tiles, in order: the native built-in microapps in registry order, then
  the web ones by name.
- Clicking a tile starts it, as at the top level: the launcher closes
  and the turtle spits out a new instance's bubble. Built-in tiles do not
  drag (they wobble) and have no right-click menu.
- The back button, or Escape, returns to the top level. Escape there
  closes the launcher. A click outside closes the launcher from either
  level.
- The launcher opens at the top level every time.

**Web built-in microapps**

- A web built-in microapp is a folder of Honu's resources,
  `BuiltinApps/<name>/`, holding its `index.html` and any files it loads
  by relative links. `<name>` is its id: it names its data and its saved
  items, so it never changes once shipped.
- `<name>` is lowercase letters, digits, and hyphens (`a-z`, `0-9`, `-`),
  starting with a letter. It is the host of the page's URL, which
  ignores case, as the Mac's file system usually does, so two names that
  differ only in case would share an origin and a data folder; and it
  must be a valid host. A folder whose name breaks the rule is not
  loaded, and a test fails on it.
- Its page declares what an installed microapp's does, in its head
  (`PageMeta`): its `<title>` (the tile's name), `honu-size` (the size
  its bubble starts at), and `honu-symbol` (the tile's SF Symbol;
  `sparkles` if none, or none that exists).
- It runs as an installed microapp does: `window.honu` gives it `load`
  and `save` (its instance's state), `fetch`, and `resize`; its bubbles
  rise once the page loads. It has no change bar. Errors it reports are
  not sent to Claude; they wobble its bubbles, as a page that fails to
  load does, once until the page loads again, so a page that keeps
  failing does not keep them shaking.
- Each web built-in microapp has an origin of its own,
  `honu-builtin://<name>/`, apart from the installed microapps'
  `honu-app://`, so the two never share storage. The scheme serves only
  that folder of the resources, which are read-only.
- Each instance's data is kept apart from the resources:
  `builtin/<name>/instances/<instance UUID>.json` beside Honu's store
  (`~/.honu/`), or `<store name>.builtin/` beside the file `HONU_STORE`
  names, as installed microapps' folders are.
- If a later Honu no longer ships a web built-in microapp, its bubbles
  are dropped when the store is restored, and its data is left alone.

**Native built-in microapps**

- Unchanged, but listed in the folder rather than at the top level.

### Storage

```
<Honu resources>/BuiltinApps/<name>/index.html            the page (read-only)
~/.honu/builtin/<name>/instances/<instance UUID>.json     what each instance saves
```

The store keeps each web built-in microapp's instances under its own
app id (`builtin.<name>`), as it keeps every microapp's JSON: each
instance's data file and the size its page asked for.

### Later

- **Make a copy to change**: a web built-in tile's right-click menu
  offers to copy it into an installed microapp, which Claude can then
  change and the user can uninstall.
- More built-in microapps: web pages for popular sites (`TODO.md`).
- Note as a web page, if its own PRD decides so.
- A tile for Note at the top level too, since it is the most used and
  the folder costs it a click. For now it is only in the Reef.

### Success criteria

- Every item of the behavior above holds in the running app.
- A store saved before the folder loads unchanged.
- `swift build`, `swift test`, and `swift format lint --strict` pass at
  every step.

### Open questions

- The first web built-in microapp, to prove the path (a timer, a world
  clock, a calculator).

## Plan

Each step is one or more commits that build, pass the tests, and pass the
lint on their own.

### Step 1: The Reef, with the native microapps (done)

- `LauncherTile.Kind` gains `.folder(LauncherFolder)`; `LauncherFolder`
  is an enum with one case, `.builtIn`.
- `Popup.launcher(at:)` becomes `.launcher(at:folder:)`, the folder open,
  if any; `openFolder` and `closeFolder` change it. `launcherTiles` lists
  the open level's tiles, and `launcherFrame` sizes the panel for them
  and the header.
- `LauncherView` shows the header with the back button in a folder;
  `TileFace` draws a folder's small grid of symbols.
- `InputRouter`: Escape in a folder returns to the top level.
- Tests (`ShellTests`, `InputRouterTests`): the tiles at each level, in
  order; opening and leaving the folder; Escape twice; the launcher
  opening at the top level.

### Step 2: Run web pages apart from the Maker (done)

A refactor; no behavior changes.

- `MicroappView` and `MicroappRunner` take a small protocol (what to
  load, where the instance saves, and `loaded`, `report`, `resize`)
  instead of `MakerApp`, which conforms.
- `MicroappScheme` takes a scheme name and a read-only root, and refuses
  `instances/` as now.
- The existing tests pass unchanged.

### Step 3: Web built-in microapps (done)

- `BuiltinCatalog` lists the folders of `BuiltinApps/` and reads each
  page's `PageMeta`, skipping folders whose name breaks the name rule.
- `BundledWebApp`, a `MicroApp` per web built-in microapp (`AppID`
  `builtin.<name>`): an `ItemTable` of instances (data UUID and size),
  `appearance` from its meta and size, `content` through `MicroappView`
  with the `honu-builtin://` scheme, rise on load, wobble on errors.
  `MakerApp` becomes a `PageHost` too, so both run pages the same way.
- `Shell.init` registers one per catalog entry, after the native ones;
  their tiles go into the folder. It takes the pages, so tests run
  without what Honu ships.
- Restoring drops bubbles of an app id no microapp has (it already did).
- Tests: the catalog reads a page's meta; every folder in `BuiltinApps/`
  keeps the name rule, and the catalog skips one that does not; two
  instances save apart and come back after a relaunch; the scheme stays
  inside the folder and refuses `instances/`; a store naming a microapp
  no longer shipped loads without its bubbles.

### Step 4: The first web built-in microapp

- One small page in `BuiltinApps/`, declaring its title, size, and
  symbol, saving its state through `honu.save`.
- `Package.swift` copies `BuiltinApps/` into the resources (SwiftPM
  wants the folder to hold something).

### Step 5: Docs

- `CLAUDE.md`: the folder, the three kinds of microapps, `BundledWebApp`,
  `BuiltinCatalog`, the `honu-builtin://` scheme, and where its data
  goes.
- `README.md`: the Reef.
- `TODO.md`: check off built-in microapps in a subfolder.
