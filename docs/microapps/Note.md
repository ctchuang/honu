# Note

A PRD for the Note microapp, built into Honu: a sticky note on the
desktop. It follows `../UI.md`.

## Behavior

- The **Note** tile in the launcher has the turtle spit out a new, empty
  note. It takes the keyboard focus, so the user can start writing at
  once; text typed before it has the focus goes into it.
- A note is yellow-tinted glass with dark text, written in directly:
  there is nothing to save, and no formatting beyond its title.
- A note's title is its first line with text. The note shows it larger
  and bold, so the bubble shows no title above it, only a strip of glass
  to drag it by, tall enough to grab easily below the rim that resizes
  it. A note with nothing in it yet is titled "Note".
- Formatting pasted in, or typed with ⌘B and the like, is dropped: a note
  is plain text, and is kept as plain text.
- ⌘Z undoes typing in the note, each note with an undo history of its
  own.
- Dropped on the octopus, a note is deleted, and comes back with ⌘Z or a
  click on the octopus for a few seconds.

## Non-goals

- Rich text, lists, links, or images in a note.
- A title field apart from the text: the first line is the title, as in
  Apple Notes.
