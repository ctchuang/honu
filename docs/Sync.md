# History and Sync

A PRD and implementation plan for keeping old versions of what Honu
saves, so the user can go back to them, and for syncing it across the
user's Macs.

**Status: draft.** Not yet agreed on or built; open questions remain.

## PRD

### Background

Honu keeps everything as it changes (principle 7 in `UI.md`, "Nothing to
save"): `Autosave` writes `~/.honu/state.json` at most once a second,
and each microapp Claude writes keeps a folder of its own under
`~/.honu/microapps/`, as each web built-in microapp's instances do under
`~/.honu/builtin/`. What it writes replaces what was there. The only
ways back are ⌘Z inside a bubble (for this launch), the octopus (for a
few seconds after a delete), and a Maker microapp's `history/` (its
pages before each change). A note emptied by mistake, a bubble swallowed
yesterday, or a store that came back unreadable (`state.unreadable.json`)
cannot be brought back.

Honu also lives on one Mac. A note written on a desktop Mac is not on the
laptop, and a microapp Claude wrote on one must be described again on
the other.

The two are planned together because they touch the same thing, how
Honu stores what it keeps, and because each makes the other safer: sync
can lose an edit when two Macs change the same item, and history is what
makes that recoverable.

What is in the way today:

- `ItemID` is an `Int` counted up per microapp (`ItemIDs`), so two Macs
  hand out the same ids for different items.
- Each microapp saves all its items as one JSON array (`ItemStore`,
  `SavedState.apps`), so a change to one note rewrites every note's
  record, and two Macs would overwrite each other's.
- Where a bubble is and how big depends on the screen; it is saved with
  which items exist, in the same file.
- Items no bubble shows are deleted on restore, so an item's life is
  tied to the bubbles of one Mac.
- A release build is a bare executable with no bundle id, entitlements,
  or signing team (`TODO.md`, packaging), so it cannot use CloudKit.

### Goals

- **Nothing is lost for good by accident.** Any item the user had in the
  last 90 days, deleted or changed since, can be brought back, along with
  the microapp that shows it.
- **Going back is safe.** It never destroys the present: bringing
  something back adds it, and returning everything to an earlier time
  first keeps the present, so going back can itself be undone.
- **The same Honu on every Mac.** Once sync is on, the items, the
  bubbles that show them, and the installed microapps are the same on
  every Mac signed in to the same account, within seconds while both are
  online, and after reconnecting otherwise.
- **Each Mac keeps its own desk.** Where bubbles sit, their sizes, the
  turtle's place, and Show on All Desktops belong to the Mac, since
  screens differ.
- **No edit is lost to a conflict.** When two Macs change the same item
  while apart, both versions survive.
- **Nothing new to learn.** History lives in the turtle's right-click
  menu, as other rare actions do (principle 3); sync is one checkmark
  there. No settings screen, accounts, or servers of Honu's own.

### Non-goals

- Real-time co-editing of one note on two Macs at once, character by
  character. Two Macs editing the same item at the same moment get the
  conflict rule below.
- Sharing with other people: sync is one user's own Macs.
- Syncing Ask AI's chats in flight, or the octopus's trash: what can
  still be undone with ⌘Z or the octopus stays on the Mac it happened on.
- Browsing history inside a microapp's page. A page sees only its
  current data (`honu.load`).
- Syncing Claude Code's own files in `~/.honu/` (its sessions and
  settings), or anything outside `~/.honu/`.
- A server of Honu's own.
- iPad (`TODO.md`); the design should not rule it out.

### Terms

- **Record**: one unit that syncs and is kept in history: one item of a
  microapp (with any files it owns), one installed microapp (its folder
  but not its instances), or the list of bubbles.
- **Layout**: what belongs to one Mac: where each bubble is, its size
  and zoom, the turtle's place, and Show on All Desktops.
- **Snapshot**: every record and the layout at one moment, kept locally.
- **Version**: a record's content at one moment, stamped with a hybrid
  logical clock (wall time, a counter, and the device id) and the version
  it was edited from (`base`).
- **Tombstone**: a version saying the record was deleted.
- **Device**: one install of Honu on one Mac, with a UUID it makes once
  and keeps in `~/.honu/device.json`, and the Mac's name.

### User stories

1. A user cleared a long note by mistake and quit Honu. The next day they
   open the turtle's menu, choose Go Back in Time, scrub to yesterday,
   and click the note as it was; the turtle spits it out beside today's.
2. A user swallowed a microapp's last bubble a week ago and wants it
   back. In the past, its bubble is there; clicking it brings back the
   instance with its data, and the microapp if it was uninstalled.
3. A change Claude made broke several things at once. The user returns
   everything to an hour ago; the present is kept as a snapshot, so
   Go Back in Time can return to it.
4. A user writes a note on their desktop Mac, then opens their laptop.
   The laptop's turtle spits the note out within seconds.
5. A user makes a microapp on the laptop on a plane. Back online, it
   appears in the desktop Mac's launcher, with its bubbles.
6. A user edits the same note on both Macs while one is offline. When
   they meet, the note shows the newer edit, and the turtle spits out the
   other as a second note, labeled with the Mac it came from.
7. A user drags a bubble to the octopus on one Mac. It goes on the
   other too, once the octopus there can no longer bring it back.

### Behavior

#### History

**What is kept.** Every record and the layout: the store, each installed
microapp's folder (its page, its `history/`, and its instances' data),
and each web built-in microapp's instances' data. Not Claude Code's
files, the history itself, or stores kept aside as unreadable (which are
already kept).

**When.** A snapshot is taken once a store write has changed something
and the last snapshot is at least five minutes old; when Honu quits, if
anything changed since the last one; before returning to an earlier time;
and before sync applies another Mac's changes that conflict with this
one's. Bubbles moving by themselves are no change, as for `Autosave`.

**How long.** Every snapshot for a day, then the last of each hour for a
week, then the last of each day for 90 days, then the last of each week
until the history passes 1 GB, when the oldest weekly ones go first.
Snapshots share unchanged content, so a snapshot that changed one note
costs about one note.

**Go Back in Time.** A new item in the turtle's right-click menu, above
Exit. Choosing it:

- Sends the present's bubbles down and fades them, and shows a glass
  strip above the turtle: a timeline of snapshots, newest at the right,
  labeled by time ("Today 14:05", "Yesterday", "Nov 3").
- Scrubbing the strip (dragging, or ← and →) shows the bubbles of that
  moment where they were, as ghosts: read-only glass with their titles and
  a still image of their content. Ghosts do not take clicks to their
  content, cannot be dragged, and do not push each other.
- Clicking a ghost brings that item back to the present as a new item
  (a copy, so the present's own is untouched; a note keeps its text,
  an instance its data and its microapp, installed again if it was
  uninstalled), and the turtle spits out its bubble. The time strip stays,
  so several can be brought back.
- **Return to This Time**, at the end of the strip, replaces the
  present with that snapshot, after keeping the present as a snapshot of
  its own, labeled "Before going back", at the right of the strip.
- Escape, or clicking outside the strip and the ghosts, returns to the
  present unchanged, the bubbles rising back.

With sync on, what Go Back in Time brings back is an ordinary change, and
syncs as one.

#### Sync

**Turning it on.** **Sync with iCloud Drive** in the turtle's right-click
menu, a checkmark as Show on All Desktops is. It is off until the user
turns it on, and shown only when iCloud Drive is set up on the Mac.
Turning it on on a second Mac that already has items merges the two:
nothing on either is replaced or deleted. A development run
(`HONU_STORE` set) never syncs.

**What syncs.** Records: the items of every microapp, the installed
microapps, and which items have bubbles. **What does not.** The layout,
the octopus's trash, chats being answered, and history.

**Arrivals.** A record that arrives from another Mac:

- A new item with a bubble: the turtle spits its bubble out, as for a new
  item, without the focus.
- A changed item: its bubbles show the new content and rise once. If
  one of them has the focus (a field being typed in), the change waits
  until the focus leaves it, then is applied by the conflict rule.
- A deleted item: its bubbles go to the octopus, which swallows them
  without the undo hint, since the deleting Mac already had its chance to
  undo; history still has it.
- A new or changed microapp: its tile appears in the launcher, and its
  instances' pages load the new page, as after a change made here.

**Conflicts.** Two versions of a record conflict when neither was edited
from the other (each has a `base` the other is not). The one with the
later clock wins and stays the record. The other:

- for an item with content of its own (a note, an instance's data),
  becomes a new item, a copy, whose title ends with the name of the Mac
  it came from, and the turtle spits out its bubble;
- for a microapp's page, goes into its `history/`, so undoing the last
  change in the change bar brings it back;
- for anything else (the list of bubbles), is dropped, and history has it.

A delete and a change conflicting keep the change.

**Deletes.** A bubble deleted with the octopus is deleted on the other
Macs only once the trash forgets it, so ⌘Z here never has to reach
another Mac. Tombstones are kept for 90 days, longer than any Mac is
likely to stay offline; a Mac away longer brings back what it had, as
new items, rather than deleting anything.

**Being offline.** Changes wait in the sync folder until iCloud Drive
uploads them; Honu does not need to know. Files iCloud Drive evicted to
save space are downloaded before being read.

### Design

#### Storage, split into records

The store becomes a folder of records, one file per record, replacing
the one `state.json` (which is read once, to migrate):

```
~/.honu/
  device.json                       this device's id and name
  layout.json                       this Mac's layout
  records/
    bubbles.json                    which items have bubbles
    items/<app id>/<item UUID>.json one item, as its microapp saves it
    microapps/<folder UUID>/        an installed microapp: index.html, history/, meta.json
    instances/<item UUID>.json      a microapp instance's page data
  history/                          snapshots (below)
```

Each record file carries its version (clock and `base`) beside its
content. `ItemID` becomes a UUID; items keep their order by the time they
were made, saved with them. `ItemStore` saves and loads one item at a
time (`ItemTable` already holds a value per item, so this is mostly
there), and tells the shell which items changed, so only those are
written. Microapps still decide the shape of their own items; Honu still
does not read it.

The bubbles record lists each bubble's target and an id of its own,
synced; the layout maps that id to where it is and how big, per Mac. A
bubble with no layout on this Mac (one that arrived) is spat out by the
turtle. Items stop being deleted on restore for having no bubble here;
they go with a tombstone, as any delete.

#### History store

History is a small content-addressed store, Honu's own:

```
~/.honu/history/
  objects/<2 hex>/<62 hex>          a file's content, compressed (LZFSE), named by its SHA-256
  snapshots/<time>-<device>.json    a snapshot: its time, why it was taken, and each path's object
```

A snapshot writes its objects first and its manifest last, atomically,
so a snapshot half written is no snapshot. Thinning deletes manifests,
then objects no manifest names. A history that cannot be read is moved
aside, as an unreadable store is, and a new one started.

Git was considered (`TODO.md`): it is the same idea, but needs
`/usr/bin/git`, which on a Mac without the Command Line Tools asks to
install them, so a downloaded Honu could not count on it. The store above
is a few hundred lines and needs nothing.

#### Sync folder

Sync goes through a folder in iCloud Drive
(`~/Library/Mobile Documents/com~apple~CloudDocs/Honu/`), not CloudKit,
for now: CloudKit needs a signed app with a bundle id and entitlements,
which a bare executable does not have. The folder is laid out so that no
two Macs ever write the same file, since iCloud Drive resolves those by
making copies of whole files:

```
<iCloud Drive>/Honu/
  devices/<device UUID>/
    device.json                     its name, and when it was last seen
    records/...                     every version this device wrote, laid out as ~/.honu/records/
```

Each Mac writes only into its own folder, the latest version of each
record it changed, and reads every other device's. A record's current
version is the newest by clock across all devices; one that is not based
on the newest, nor the newest on it, is a conflict. This is a
last-writer-wins map, a simple CRDT: every Mac that has read the same
files agrees, in whatever order they arrived. Honu watches the folder
(`NSFilePresenter`, with a poll every 30 seconds as a fallback), and
writes its own changes a few seconds after they settle, coalesced as
`Autosave` does.

Each record keeps its own clock, so moving to CloudKit later, once Honu is
a signed app, maps a record file to a CloudKit record one to one; the
sync folder would then be read once to migrate.

#### Privacy

The user's notes and microapps go to their own iCloud account. iCloud
Drive is end-to-end encrypted only with Advanced Data Protection on;
the menu item says nothing of this, but the README should.

### Open questions

- **Ghosts' content.** A note's ghost can show its text; a microapp
  instance's would need its page run on past data, read-only. A still
  image saved with each snapshot is simpler but costs space; a symbol and
  title only is cheapest. Which is enough to recognize an item?
- **Size and zoom.** Kept per Mac above. Should a size the user chose
  sync when both screens are alike?
- **Conflict copies for microapp data.** A page's data may not make sense
  split in two (a timer running on both Macs). Should a microapp say
  whether its conflicts copy or keep the newer?
- **The 1 GB cap.** Microapps that save a lot (images) would fill it
  fast; per-microapp limits may be needed.
- **Live pages.** A page that loaded its data with `honu.load` does not
  hear of a change from another Mac until it loads again. Reload it, or
  add `honu.onChange`?
- **Bubbles of the same item on two Macs.** If one Mac shows an item in
  two bubbles, should the other show two?

### Later

- CloudKit, once Honu is a signed app (`TODO.md`, packaging), for faster
  sync and the iPad.
- Going back in time for one bubble alone, from its title.
- A conflict shown as a bubble that wobbles until the user picks a side,
  if copies prove noisy.

### Success criteria

- A store saved before records migrates without losing an item, a
  bubble, or a size, and the old `state.json` is kept beside it.
- Deleting `~/.honu/records/` and returning to the last snapshot brings
  everything back.
- Two Macs with sync on, one offline, both changing the same note, end
  with the same two notes on both once reconnected.
- `swift build`, `swift test`, and `swift format lint --strict` pass at
  every step.

## Plan

Each step is one or more commits that build, pass the tests, and pass the
lint on their own. History comes first: it is useful alone, and it is
what makes the sync steps safe to try.

### Step 1: The history store

`HistoryStore` writes and reads snapshots of a folder (objects and
manifests as above), thins them, and collects unused objects. The shell
takes snapshots as described, of today's `state.json` and folders. Tests
on a temporary folder: a snapshot round trip, thinning by age, a manifest
half written being ignored, objects shared between snapshots.

### Step 2: Go Back in Time

The menu item, the time strip, ghosts (title and symbol first), bringing
an item back as a copy, and Return to This Time, which needs the shell to
restore at run time rather than only at launch. Update `UI.md`'s turtle
menu.

### Step 3: Item UUIDs and records

`ItemID` becomes a UUID, `ItemStore` saves one item at a time, and the
store becomes `records/` and `layout.json`, migrating `state.json`. Item
life no longer depends on bubbles on restore. History snapshots the new
layout.

### Step 4: Versions and the merge

Device ids, the hybrid logical clock, versions with `base`, tombstones,
and the merge of several devices' records into one, with the conflict
rule. Pure logic, tested without files or iCloud.

### Step 5: The sync folder

Writing this Mac's records into its device folder, watching and reading
the others', downloading evicted files, and the menu checkmark. Tests on
two temporary folders standing in for two Macs.

### Step 6: Arrivals

Applying merged changes live: spitting out new bubbles, rising changed
ones, deferring focused items, conflict copies, swallowing deletes,
reloading pages of changed microapps.

### Step 7: Docs

`CLAUDE.md`, `UI.md`, and the README (turning sync on, where history
lives, iCloud's encryption).
