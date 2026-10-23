# Resizing Bubbles

A PRD and implementation plan for resizing bubbles by hand.

## PRD

### Background

A bubble's size is what its microapp decides: a note and a web page have
a fixed size, an Ask AI chat grows with its answer, and a microapp Claude
writes declares its size in its page (`honu-size`) and can change it
(`honu.resize`). The user has no say: a web page too small to read, or a
note too big for what it holds, stays that way.

This builds on there being one kind of bubble (step 3 of the plan in
`UI.md`): bubbles no longer close into an icon, and double-clicking the
title is free for what macOS gives it, zooming.

### Goals

- The user can resize any bubble by dragging its edges and corners, as
  with a window, but without chrome: no handles, grips, or buttons.
- A size the user chose sticks: the microapp no longer changes it, and it
  comes back on the next launch.
- The user can drop a size they chose by double-clicking the title, as
  zooming a window does on macOS: the bubble eases back to the size its
  microapp wants, and the microapp decides its size again from then on.
  Double-clicking the title once more goes back to the size they chose.

### Non-goals

- Resizing anything but bubbles: the turtle and the octopus keep their
  pixel-art size, and the launcher sizes itself to its tiles.
- Resizing several bubbles at once, snapping to other bubbles or to the
  screen edges, or zooming the content.
- Double-clicking an edge to stretch that side to the edge of the
  screen, as macOS does for windows. It may come later.
- Resizing by keyboard or from a menu, or undoing a resize with ⌘Z.

### Terms

- **Rim**: the band of glass around a bubble's content, outside it and
  inside the outline: the 10 points at the sides and bottom, and the
  outer edge of the title at the top.
- **Microapp's size**: the size the microapp asks for
  (`Appearance.size`).
- **User's size**: the size the user last dragged a bubble to, if any.
  It is kept even while the bubble is zoomed to the microapp's size, so
  zooming can bring it back.

### User stories

1. As a user, I drag the right edge of a web page's bubble to widen it,
   and its left edge stays where it was.
2. As a user, I drag a corner to change both the width and the height.
3. As a user, I widen a chat, and it keeps that width as its answer
   grows; I quit and relaunch, and it is still that size.
4. As a user, I double-click a bubble's title, and it goes back to the
   size its microapp wants; I double-click it again, and it goes back to
   the size I chose.
5. As a user, I enlarge a bubble next to others, and they are pushed out
   of its way.

### Behavior

**Where to grab**

| Pointer over | Cursor | Dragging |
|---|---|---|
| The rim, along an edge | The system's resize cursor for that edge | Resizes along that edge. |
| The rim, within a corner's reach (about 20 points of it) | The system's diagonal resize cursor | Resizes both ways. |
| The title, away from the rim | The arrow | Moves the bubble, as now. |
| The content | Whatever the content shows | Goes to the content, as now. |

The rim belongs to Honu, not to the content, so web pages and text
fields keep every press inside them. The cursors are AppKit's
frame-resize cursors (`NSCursor.frameResize(position:directions:)`),
the ones windows use. Hit-testing follows the rounded outline, so a press
past a rounded corner still goes to whatever is below.

**While resizing**

- The opposite edge or corner stays put, as with a window: dragging the
  right edge moves only the right edge, so the bubble's center moves by
  half as much.
- The bubble is held: it pushes the bubbles it grows into aside, as a
  dragged bubble does, but is not pushed itself. Once let go, it is
  physical again.
- Its size stays between the microapp's minimum (`minSize`, about 240 by
  160 points unless the microapp says otherwise) and the screen, less a
  margin, and the whole bubble stays on screen.
- The bubble comes to the top, as with any press.
- The content follows the size as it changes: a web page lays out again,
  and a microapp's page gets the browser's `resize` event.

**Whose size counts**

- Once the user resizes a bubble, it takes the user's size: changes to
  the microapp's size (a chat's growing answer, a page's `honu.resize`)
  no longer resize it, unless it is zoomed to the microapp's size.
- The size belongs to the bubble, not the item, as where it is does: two
  bubbles of one item can have different sizes.
- Double-clicking the title zooms:

  | The bubble is at | Double-clicking the title |
  |---|---|
  | The user's size | Eases to the microapp's size, which follows the microapp from then on. |
  | The microapp's size, with a user's size kept | Eases back to the user's size. |
  | The microapp's size, never resized | Does nothing. |

  Resizing a bubble zoomed to the microapp's size makes the new size the
  user's size.
- A microapp can drop the user's size when what the bubble shows changes
  in kind (an `Effect`): the Maker does when a description becomes a
  microapp's first page, since the size given to the description box
  says nothing about the page. A change to an existing page keeps it.

**Saving**

The user's size, and whether the bubble is zoomed to the microapp's
size instead, are saved with each bubble and come back on the next
launch, the size clamped to the screen of that launch, so zooming back
works after a relaunch too. A store from before
resizing has no sizes and loads as it did. Resizing counts as moving a
bubble on purpose, so it is saved within a second.

### Success criteria

- Every item of the behavior above holds in the running app.
- Presses inside a bubble's content (typing, selecting, clicking links)
  behave as before.
- Stores from before resizing load unchanged.
- `swift build`, `swift test`, and `swift format lint --strict` pass at
  every step.

## Plan

Each step is one or more commits that build, pass the tests, and pass the
lint on their own. Step 3 of the plan in `UI.md`, one kind of bubble,
comes first.

### Step 1: The PRD (done)

- This document; `UI.md` points here from its open questions, and
  `TODO.md` marks resizing as started.

### Step 2: Resizing on the stage (done)

- `Bubble` gains `userSize: CGSize?`, `isZoomed` (at the microapp's size
  though it has a user's size), and `minSize`; its microapp's size is
  `microappSize`, which the shell sets, and `size` uses the user's size
  when there is one and it is not zoomed.
- `Stage` gains `startResize(_:edges:)`, `resized(by:)`, and
  `endResize()`, with the edges being resized (`Edges`, an `OptionSet`
  of left, right, top, and bottom), keeping the opposite edges put, the
  size within limits, and the bubble on screen; and `zoom(_:)`, which
  switches between the user's size and the microapp's, easing to the new
  size. A bubble cannot be dragged while one is resized.
- `Physics` holds the bubble being resized, as the dragged one.
- Tests (`ResizeTests`, `PhysicsTests`): the opposite edge stays put, the
  limits hold, a corner resizes both ways, zooming goes back and forth,
  and a growing bubble pushes its neighbor aside without moving itself.

### Step 3: The shell (done)

- `Shell.tick` keeps every bubble's `microappSize` up to date; a bubble
  with a user's size, not zoomed, does not show it.
- `Appearance` gains `minSize` (240 by 160 points; a microapp's page,
  the smallest a page may ask for plus the bubble around it); the shell
  hands it to the bubble.
- `Effect` gains `resetSize(ViewTarget)` (`Context.resetSize(for:)`);
  the Maker asks for it when a microapp's first page is written.
- `Shell` gains `resizeBubble`, `endBubbleResize` (which tells autosave
  the bubble moved), and `zoom` for the views.
- Tests (`ShellResizeTests`, `MakerTests`): a chat's growing answer does
  not resize a resized bubble, zooming brings the microapp's size back
  and goes back again, a bubble takes its microapp's minimum, and the
  Maker resets the size of a description that becomes a page but not of
  a page that changes.

### Step 4: Saving (done)

- `SavedBubble` gains `size: CGSize?` and `isZoomed: Bool?`, written
  only when there is a user's size; `Shell.snapshot` and `Shell.restore`
  carry them, and `Stage.setUserSize(of:to:zoomed:)` fits the size
  between the bubble's minimum and the screen of the launch.
- Tests (`PersistenceTests`): sizes, zoomed or not, survive a relaunch,
  and zooming back works after one; a size too big for a smaller screen
  shrinks to fit it; a store without sizes loads.

### Step 5: The rim and the title in the view (done)

- `Bubble.rimEdges(at:)`: which edges a point on the rim resizes, if
  any, as a pure function of the outline, so it is tested without views.
  The rim is 10 points deep at the sides and bottom (`rimWidth`), but
  only 6 at the top (`topRimWidth`), so most of the title still moves
  the bubble; corners reach 20 points (`cornerReach`).
- `Shell.dragBubble(_:from:by:velocity:pointer:)`: a drag that starts on
  the rim resizes, any other moves, and `endBubbleDrag` ends either.
- `BubbleView`: its one drag gesture goes through it; a hover sets the
  system's resize cursor (`pointerStyle(.frameResize(position:))`, kept
  while resizing), and a double-click on the title zooms.
- `ClickThrough` and `InputRouter` needed no change: the rim is inside
  the outline, so presses on it are Honu's, and the content's AppKit
  views still take the presses inside them.
- Tests (`ResizeTests`): edges and corners are found where the table
  above says, the title, the content, and past the outline are not rim,
  dragging the rim resizes while dragging the title moves, and resizing
  over the octopus does not delete.

### Step 6: Microapp pages that fit any size

- `MakerPrompt`: a page fills the size it is given and lays out again
  when it changes, rather than only fitting the size it declares; the
  size it declares is where it starts.
- `honu.resize` keeps working while the user has not resized the bubble,
  and is ignored after.

### Step 7: Docs (done but for `TODO.md`, which waits for step 6)

- `UI.md`: resizing in **Bubbles**, and out of the open questions;
  `CLAUDE.md`: the architecture; `TODO.md`: check off resizing; mark the
  steps here (done).
