# The Launcher

A PRD and implementation plan for replacing the turtle's menu with an app
launcher.

## PRD

### Background

Clicking the turtle today opens a menu with one item per microapp (Add
Note, Ask AI, Open Web Page, Make a Microapp) and Exit; right-clicking it
does the same. Microapps Claude makes are items of the Maker microapp:
each lives only in its bubble, and once its bubble is gone, so is the
microapp. There is no way to run a microapp again, or to run two of it.

Asking Claude is to move from a menu item to a gesture (feeding a bubble
to the turtle), so Ask AI no longer needs a place in the menu. That
gesture is out of scope here.

### Goals

- Clicking the turtle opens a **launcher**: a glass panel of tiles, one
  per app, built in or made by Claude, and a **+** tile that makes a new
  one.
- A microapp Claude makes is **installed**: it stays in the launcher after
  its bubbles are gone, and can be launched any number of times.
- Every launch opens a **new instance** with data of its own, for built-in
  apps and made ones alike.
- Rarely used and destructive commands (Exit) move off the main surface,
  to the turtle's right-click menu.
- Installed microapps can be modified and uninstalled from the launcher.

### Non-goals

- Asking Claude by feeding a bubble to the turtle, or any other way of
  asking Claude. Ask AI leaves the launcher; its code stays so saved
  chats still load.
- Reopening an existing instance from the launcher (single-instance apps).
- Migrating Notes and Web to web-based microapps.
- Installing microapps from elsewhere, sharing them, or ordering tiles by
  hand.

### Terms

- **App**: what a tile launches. Built-in apps (Notes, Web) are
  microapps in the code; an **installed app** is one Claude made: its
  description, its page, and the pages before each change.
- **Instance**: one launch of an app, an item with data of its own,
  shown by a bubble.
- **Launcher**: the panel the turtle opens on a left click.
- **System menu**: the menu the turtle opens on a right click.

### User stories

1. As a user, I click the turtle and see every app I can open, so I can
   start one in one more click.
2. As a user, I click **+**, describe a microapp, and once Claude has
   written it, it has a tile in the launcher from then on.
3. As a user, I click a tile twice and get two bubbles, each keeping its
   own data.
4. As a user, I ask for a change in one bubble of a microapp, and every
   open bubble of it shows the new version, keeping its own data.
5. As a user, I right-click a tile to modify or uninstall that microapp.
6. As a user, I drag a tile onto the octopus to uninstall it, as I drag a
   bubble onto it to delete it.
7. As a user, I right-click the turtle to quit Honu.

### Behavior

**Turtle**

| Input | Result |
|---|---|
| Left click | The turtle hops and the launcher opens beside it. |
| Right click | The system menu opens beside it: Exit. |
| Drag | Moves the turtle (unchanged). |
| Click, Escape, or right click outside an open launcher or menu | Closes it. |

**Launcher**

- Tiles, in order: the built-in apps (Notes, Web), then the installed
  apps in the order they were installed, then **+**. Ask AI has no tile.
- A tile shows the app's SF Symbol and name. An installed app's symbol
  is its page's `honu-symbol` (`sparkles` if none, or none that exists);
  its name is its page's `<title>`, or else its description, shortened.
- The panel grows with the tiles and is kept on screen; past a few rows
  it scrolls.
- Clicking a tile closes the launcher, and the turtle spits out a new
  instance's bubble, which opens on landing.
  - Notes and Web: as their menu items do today.
  - An installed app: its page runs at once (no description step).
  - **+**: a new microapp waiting for its description, as Make a
    Microapp does today.
- Right-clicking an installed app's tile opens a small menu:
  - **Modify…**: launches a new instance with the cursor in its change
    field, to ask Claude for a change.
  - **Uninstall**: asks to confirm, then uninstalls (below).
- Dragging an installed app's tile out of the launcher calls up the
  octopus, whose speech bubble offers to uninstall it; letting go with the
  pointer within its reach uninstalls it; elsewhere the tile goes back.
  Built-in tiles and **+** do not drag: they wobble, to show they cannot
  be removed.

**Installed apps**

- A microapp is installed when its first page has been written and runs.
  Until then (describing, or Claude writing the first page) it is only
  that one instance, and has no tile; deleting that bubble discards it.
- Changing, fixing, or undoing a change in any instance changes the
  installed app. Every open instance loads the new page; each keeps its
  own data.
- While Claude rewrites an installed app, all its instances show it
  writing and breathe. The change bar is shared, as the page is.
- Deleting an instance's bubble (feeding it to the octopus) deletes only
  that instance's data, once the octopus forgets it. The app stays
  installed.
- Uninstalling an app has the octopus swallow it and every open bubble
  of it, and its tile leaves the launcher. As with a deleted bubble, the
  octopus keeps them for `undoSeconds`: clicking it or ⌘Z spits the
  bubbles back where they were and puts the tile back. Once the octopus
  forgets, the instances are deleted and the folder goes to the Trash.
  Quitting before then finishes the uninstall.

**Storage**

```
microapps/<app UUID>/index.html                     the page
                    /history/<n>.html               the pages before each change
                    /instances/<instance UUID>.json what each instance saves
```

An instance's UUID is made when the instance is, and saved in the store
with it, so its data comes back on the next launch; it goes when the
instance is deleted. It is a UUID rather than the item id, which
restarts with a new store, as app folders are.

`honu.load` and `honu.save` read and write the instance's own file. The
store keeps the microapps (folder, description, draft) in order, and
each instance (its microapp, its data file, the size its page asked
for). A store saved before the launcher loads as one installed app per
microapp, each with one instance holding the old `data.json`, moved
to `instances/` in its folder.

All instances of an app share one origin (`honu-app://<app UUID>/`), and
so share `localStorage`; the Maker's system prompt tells pages to keep
their state through `honu.save` only.

`honu-app://` serves the app's own folder, but answers requests under
`instances/` with "not found", so a page reaches no instance's data but
its own, through `honu.load`. The scheme handler is the only way a page
reads files, so refusing there covers every way of asking (`fetch`,
`<iframe>`, `<img>`), which a Content Security Policy would have to list
one by one, and could break pages that load from elsewhere.

### Later

Typing to filter the launcher, after the rest has shipped: typing while
the launcher is open filters the tiles by name (case- and
diacritic-insensitive); Delete removes the last character. Return opens
the first tile left; with none left, it acts as **+** with the typed text
as the description draft. Escape clears the filter, then closes the
launcher.

### Success criteria

- Every item of the behavior above holds in the running app.
- Saved stores from before the launcher load with their microapps
  installed and their data in place.
- `swift build`, `swift test`, and `swift format lint --strict` pass at
  every step.

## Plan

Each step is one or more commits that build, pass the tests, and pass the
lint on their own.

### Step 1: Split the turtle's clicks; drop Ask AI from the menu (done)

- `Shell.menu: CGPoint?` becomes `popup: Popup?`, with `.launcher(at:)`
  and `.system(at:)`. Rename `Hit.menu`, `takesEveryClick`,
  `clickTurtle`, `closeMenu`, and the views to match.
- `InputRouter`: a right click on the turtle opens `.system`; elsewhere
  it closes any popup, as now.
- `TurtleMenu` loses Exit; a new `SystemMenu` holds it.
- `MicroApp` gains `isLaunchable` (default `true`; `false` for
  `AskApp`), and `menuChoices` leaves out those that are not. `AskApp`
  stays registered, so saved chats load.
- Tests: `InputRouterTests` (right click opens the system menu, left
  click the launcher), `ShellTests` (no Ask AI choice).

### Step 2: The launcher panel, with built-in apps and + (done)

- `Views/LauncherView.swift` replaces `TurtleMenu`: a glass panel of
  tiles (symbol and label), in a grid with a fixed column count.
- `Shell+Views.swift`: `MenuChoice` becomes `LauncherTile` (`id`,
  `label`, `symbol`, and `kind`: `.stock(AppID)`, `.installed(String)`,
  `.make`); `menuChoices` becomes `launcherTiles`. `MicroApp` gains
  `launcherSymbol`.
- `choose` takes a tile. `.stock` and `.make` call `start` as today.
- The panel's corner is computed from its real size (rows × tile height)
  rather than `estimatedHeight`.
- Tests: tile order and kinds; choosing a tile starts an item and a
  bubble.

### Step 3: Split the Maker's model into installed apps and instances (done)

**3a. Data per instance**

- `AppFolder` gains `dataURL(for: UUID)` (`instances/<uuid>.json`).
- `MicroappScheme` refuses paths under `instances/`.
- `Bridge` takes the data URL instead of reading `folder/data.json`;
  `MicroappView` passes the instance's.
- `MakerPrompt.system`: keep state with `honu.save`, not `localStorage`.
- Tests: two instances of one app save and load apart; the scheme
  refuses `instances/`.

**3b. `GeneratedApp` and `Instance`**

- `GeneratedApp` stays the microapp: `folder`, `description`, `draft`
  (shared, as the change bar is), `meta`, `version`, `status`, the
  Claude stream, `written`, `notice`, `problems`, `canRevert`, and the
  fixing timers. `hasPage` says whether its first page is written.
- `Instance` (new, the item): its `GeneratedApp`, its data UUID
  (`dataURL`), and the size its page asked for, which a new page resets.
- `MakerApp` keeps `apps` (every microapp, oldest first) and
  `ItemTable<Instance>`; `library` is the apps with a page, the installed
  ones. `appearance`, `title`, `isBusy`, and `update` go through an
  instance to its microapp; `update` polls each microapp once and plays a
  motion for every instance of one whose page loaded or whose writing
  failed.
- `remove(item)` deletes the instance's data file; it trashes the folder
  only for a microapp never installed, with its last instance.
- The saved JSON becomes `{ apps: [...], instances: [...] }`.
- Tests (`MakerTests`): installing on the first page; removing an
  instance keeps the app, also after a relaunch.

**3c. Loading old stores**

- Loading the old array form: each microapp becomes one with one
  instance, keeping its item id; its `data.json` moves to
  `instances/<new uuid>.json` in its folder.
- Loading trashes folders no microapp has, and deletes data files no
  instance has.
- Tests (`MakerTests`): old form migrates with its data; stray data
  files go.

**3d. Launching an installed app**

- `MakerApp.launch(_ name: String) -> ItemID?`: a new instance of the
  installed microapp in the folder `name`, running.
- `Shell.launch(_:)` and `Shell.start(_:)` both spit a bubble through
  `spit`. A new instance of a microapp already made takes no type-ahead,
  having no field for it.
- Tests: launching twice gives two instances with their own data; a
  change reaches every instance and they all rise.

### Step 4: Installed apps in the launcher (done)

- `launcherTiles` lists the Maker's library between the built-in apps
  and **+**, with each app's symbol and name.
- Tests: a tile appears once the first page is written, and not before;
  choosing it launches an instance.

### Step 5: Modify and Uninstall from a tile

- Right-clicking an installed tile opens a small menu (Modify…,
  Uninstall). Try SwiftUI's `contextMenu` in the floating window first;
  if it misbehaves, route the right click through `InputRouter` to a
  `Popup.tileMenu`.
- Modify…: `launch`, with the instance's view state asking to focus the
  change field.
- Uninstall: a confirmation, then `Shell.uninstall(_:)` (from step 6).
- Tests (`ShellTests`): uninstalling clears the app, its instances,
  their bubbles, and its tile.

### Step 6: Drag a tile to the octopus to uninstall

- `Octopus`: a `Swallowed` holds the bubbles swallowed together, each
  with its home, and the microapp uninstalled with them, if any.
  `forget` returns what it forgets.
- `MakerApp`: `withdraw(_:)` takes a microapp out of the library while
  the octopus keeps it, `reinstate(_:)` puts it back, and `uninstall(_:)`
  deletes it, its instances, and its folder. A withdrawn microapp is not
  saved, so quitting finishes the uninstall.
- `Shell.uninstall(_:)`: withdraws the microapp and has the octopus
  swallow it with every bubble of it. `undoDelete` reinstates it and
  spits the bubbles back; `tick` uninstalls it once the octopus forgets.
- `Shell.dragTile` and `endTileDrag`: dragging an installed tile beyond
  `summonDistance` summons the octopus, whose speech bubble says it will
  uninstall; the tile follows the pointer above the launcher. Letting go
  within `reach` uninstalls and closes the launcher; elsewhere the tile
  goes back. Built-in tiles and **+** wobble instead.
- Tests: a drop in reach uninstalls, one outside does not; undo brings
  back the tile and the bubbles; forgetting deletes the folder; quitting
  while withdrawn finishes the uninstall.

### Step 7: Docs

- `CLAUDE.md`: the launcher, `Popup`, the system menu, `GeneratedApp`
  and `Instance`, the new folder layout, and `InputRouter`'s new rules.
- `README.md`: how to use the turtle.
- `TODO.md`: check off the launcher and modifying and uninstalling
  microapps.

### Later: Type to filter the launcher

- `Shell.launcherQuery`, cleared when the launcher opens.
- `InputRouter`: while the launcher is open, printable keys, Delete, and
  Return go to it instead of `shell.type`; Escape clears the query
  before closing.
- `launcherTiles` filters by the query (`localizedStandardContains`).
  Return chooses the first tile, or, with none, starts **+** with the
  query as the draft.
- Tests (`InputRouterTests`, `TypeAheadTests`): filtering, Return,
  Return with no match, Escape.
- Docs: `CLAUDE.md` and `README.md`.
