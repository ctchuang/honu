# Honu's UI

A PRD for how Honu looks and behaves: the principles every part of the UI
follows, and the behavior that comes from them. Changes to the UI should
keep to it; a change that departs from it updates this document first.
The launcher's own design is in `Launcher.md`, resizing bubbles in
`Resizing.md`, jelly bubbles in `Jelly.md`, and each built-in microapp's in `microapps/` (`Note.md`,
`WebPage.md`).

## Vision

Honu is an experiment in desktop UI that departs from macOS conventions on
purpose. It has no app window: its bubbles float on the real desktop,
behind the user's own apps until the user turns to them. Two pixel-art characters
take the place of chrome: a turtle that makes things and an octopus that
takes them away. Claude writes the microapps the bubbles show, so the UI
stays small while what it can do grows.

## Principles

1. **The desktop is the canvas, and the user's apps come first.** Honu
   draws on the desktop, not in a window, and is on every desktop (Space)
   unless turned off. While another app is in use, Honu sinks behind
   every window: it shows only where the desktop shows, and never takes
   another app's clicks or keys. Clicking a bubble or a character where it
   shows brings Honu to the front, and that click counts (it starts a
   drag, opens the launcher, and so on). Turning to another app sends
   Honu back behind it. Even in front, clicks pass through to the apps
   below everywhere except on something of Honu's. It never goes full
   screen, and Mission Control hides it: it shares the screen with the
   other apps rather than taking it over.
2. **Start empty, stay quiet.** Honu starts with only the turtle in the
   bottom-left corner. Anything else appears when needed and leaves when
   done: the octopus rises only while something is dragged toward it or
   can still be brought back.
3. **Characters, not chrome.** The turtle makes (click it for the
   launcher; it spits each new bubble out of its mouth), and the octopus
   takes away (drop a bubble or a microapp on it). There are no toolbars,
   title bars, or close buttons. What is rarely needed, or destructive,
   such as Exit, sits in the turtle's right-click menu, off the main
   surface.
4. **Bubbles are physical.** A bubble is Liquid Glass with weight: it can
   be thrown and glides to a stop, crowded ones push each other apart,
   and they bounce off the screen edges. It is soft, too: it squashes,
   stretches, and wobbles like cartoon jelly, what it shows and all, and
   springs back into shape. Left alone, a bubble stays where it is put. The bubble
   pressed last comes to the top and covers the others completely.
5. **Status shows through motion.** A bubble breathes while busy, rises
   once when something finishes, and wobbles when it needs the user.
   Honu shows no spinners, badges, alerts, or system notifications. A
   bubble behind another app's window cannot be seen, so the turtle shows
   for it: when bubbles out of sight finish or need the user, possibly
   many at once, the turtle shows it in a way of its own.
6. **Direct manipulation, as few dialogs as possible.** Things are done
   by dragging and clicking them rather than through forms and dialogs,
   wherever that can be done. Deleting asks nothing: every delete can be
   undone instead, for a few seconds, by clicking the octopus or pressing
   ⌘Z.
7. **Nothing to save.** Everything is kept as it changes: bubbles,
   their contents, the turtle's place, and settings come back where they
   were on the next launch.
8. **Plain language is the interface to Claude.** A microapp is made by
   describing it and changed by saying what to change, in the bar below
   it. The user never sees code.
9. **Keep the platform's basics.** Departing from conventions stops at
   what users rely on: ⌘Q quits, ⌘Z undoes, the Edit menu works in text
   fields and web pages, Escape or a click outside closes a menu, and
   menus behave like native ones.

## Elements

**Turtle.** Draggable anywhere; bobs while idle and hops when clicked.

| Input | Result |
|---|---|
| Click | Opens the launcher beside it. |
| Right click | Opens the system menu beside it: **Show on All Desktops** (checked while on, the default) and **Exit**. |
| Drag | Moves it; its place is kept. |

**Front and back.** Honu is either in front, while the user uses it, or
behind every other window.

| Input | Result |
|---|---|
| Click a bubble, the turtle, or the octopus where it shows | Honu comes to the front, and the click acts. |
| Click Honu's Dock icon, or switch to it with ⌘Tab | Honu comes to the front. |
| Click another app, or switch to it | Honu goes behind every window. |
| Click where Honu shows nothing | The click goes to whatever is below; if that is another app, Honu goes back. |

**Launcher.** A glass panel of microapps: Note, Web Page, each installed
microapp, and **+** for a new one. See `Launcher.md`.

**Bubbles.** Each shows one item: a note, a web page, or an instance of a
microapp, under its title (or, as a note does, with the title in its
content). There is one kind of bubble: it never shrinks into an icon or
closes, and it leaves only through the octopus. A new
bubble flies out of the turtle, growing on the way, and text typed
before its field has the focus goes into it. A bubble starts at the size
its microapp asks for; once the user resizes it, it keeps the user's
size, across launches too. See `Resizing.md`. It is jelly: it flattens
against an edge it hits, trails behind the pointer and stretches when
moved fast, splats when it lands, and wobbles back into shape within
about a second, its content squashing along. See `Jelly.md`.

| Input | Result |
|---|---|
| Drag the title | Moves it; let go while moving, it glides on. |
| Drag the rim (the glass around the content), or a corner | Resizes it, as a window: the opposite edge stays put, and the bubbles it grows into are pushed aside. The pointer shows the system's resize cursor there. |
| Double-click the title | Zooms it, as a window: from the size the user chose to the size its microapp asks for, and back. |
| Press anywhere on it | Brings it to the top, over every other bubble. |

**Octopus.** Rises from the bottom corner away from the turtle once a
bubble is dragged a little way, or a microapp is dragged out of
the launcher. Its speech bubble says what letting go will do. Letting go
with the pointer within its reach swallows the bubble (or uninstalls the
microapp, with all its bubbles). For five seconds it shows "Click to
undo"; clicking it, or ⌘Z, spits back what it swallowed, where it was.

## Non-goals

- Looking or behaving like a standard macOS app window.
- Staying above other apps' windows while they are in use.
- Notifications outside Honu's own bubbles.
- Settings screens: what little can be set lives in the turtle's menu.

## Open questions

- Reaching Honu when its windows are all covered: the Dock icon and ⌘Tab
  work, but the turtle could instead stay on top, in a small window of
  its own.

## Plan

1. Behind until used (done): `FloatingWindow` at the normal window
   level; sent behind every window when Honu stops being the active app,
   and to the front when it becomes active again; a first click on a
   bubble or character that brings Honu forward also acts. This fixes
   issue #5: in testing, a transparent window at the normal level, on
   every Space and ordered to the back, leaves every Space thumbnail
   intact.
2. The turtle shows covered bubbles' status (not done): what it does
   when one or many bubbles out of sight finish or need the user is yet
   to be designed.
3. One kind of bubble (done): bubbles no longer close into an icon,
   and double-clicking the title did nothing until `Resizing.md` gave
   it a meaning, zooming. `Bubble` loses `isOpen` and its icon size, along with
   the morph between bubble and icon (`Stage.toggle`) and opening on landing
   (`openOnLanding`); `Appearance` loses `closedSide`, and its
   `panelSize` becomes `size`. A store saved
   with bubbles shrunk into icons brings them back as any other. The idle float
   goes, so bubbles stay where they are put; collisions treat every
   bubble as a rectangle with rounded corners. The flight out of the
   turtle and the shrinking over the octopus stay, and so does
   `honu-symbol`, for the launcher's tiles.
