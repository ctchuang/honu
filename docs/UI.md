# Honu's UI

A PRD for how Honu looks and behaves: the principles every part of the UI
follows, and the behavior that comes from them. Changes to the UI should
keep to it; a change that departs from it updates this document first.
The launcher's own design is in `Launcher.md`.

## Vision

Honu is an experiment in desktop UI that departs from macOS conventions on
purpose. It has no app window: its bubbles float on the real desktop,
above other windows, among the user's own apps. Two pixel-art characters
take the place of chrome: a turtle that makes things and an octopus that
takes them away. Claude writes the microapps the bubbles show, so the UI
stays small while what it can do grows.

## Principles

1. **The desktop is the canvas.** Honu draws on the desktop, not in a
   window. Clicks pass through to the apps below everywhere except on
   something of Honu's, and Honu is on every desktop (Space) unless
   turned off. It never goes full screen: it shares the screen with the
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
   be thrown and glides to a stop, idle bubbles drift, crowded ones push
   each other apart, and they bounce off the screen edges. The bubble
   pressed last comes to the top and covers the others completely.
5. **Status shows through motion.** A bubble breathes while busy, rises
   once when something finishes, and wobbles when it needs the user.
   Honu shows no spinners, badges, alerts, or system notifications.
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

**Launcher.** A glass panel of microapps: Note, Web Page, each installed
microapp, and **+** for a new one. See `Launcher.md`.

**Bubbles.** Each shows one item: a note, a web page, or an instance of a
microapp. Closed, a bubble shows its title or symbol; double-clicking it
opens it into a panel, and double-clicking the title closes it again. A
new bubble flies out of the turtle and opens on landing, and text typed
before its field has the focus goes into it.

**Octopus.** Rises from the bottom corner away from the turtle once a
bubble is dragged a little way, or a microapp is dragged out of
the launcher. Its speech bubble says what letting go will do. Letting go
with the pointer within its reach swallows the bubble (or uninstalls the
microapp, with all its bubbles). For five seconds it shows "Click to
undo"; clicking it, or ⌘Z, spits back what it swallowed, where it was.

## Non-goals

- Looking or behaving like a standard macOS app window.
- Notifications outside Honu's own bubbles.
- Settings screens: what little can be set lives in the turtle's menu.

## Open questions

- Whether bubbles keep their closed (minimized) form: double-clicking
  shrinks a bubble, which can be annoying.
- Resizing bubbles by hand.
