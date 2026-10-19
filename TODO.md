# TODO

## LLM integration

The guiding idea: Claude should work with the bubbles on the desktop, not live in a
chat window. Done so far: the turtle's menu has **Ask AI**, which spits out a bubble
whose answer streams in while the panel grows to fit it (`Sources/Honu/Apps/AskApp.swift`,
`Sources/Honu/Claude.swift`).

- **Spit out several bubbles at once** (next step): give Claude a `create_bubble` tool,
  so "give me five weekend ideas" becomes five bubbles the turtle spits out one by one.
  Reuses the spawn animation, tool use, and streaming.
  Several bubbles also give the octopus more to do: keep the ideas you like and feed
  it the rest.
- **Answers as UI, not paragraphs**: define a small set of `Content` kinds (list,
  checklist, card, button, progress) that Claude fills through tool use or structured
  output, and that Honu draws.
- **Bumping bubbles shares their context**: dragging one bubble into another hands
  both to Claude, to compare them or find what links them. The collision physics
  gives the gesture, and Liquid Glass already shows bubbles merging.
- **Physics shows status** (started): bubbles breathe while busy, rise when something
  finishes, and wobble when the user is needed (`MicroApp.isBusy`, `Context.play`). Ask AI
  and the Web microapp do all three (a page's bubble breathes while it loads, rises once
  it has, and wobbles if it fails). New kinds of bubbles should report their state the
  same way.
- **Space as memory**: bubbles that sit together belong to the same project, now that
  bubbles and where they sit are saved across launches (`Sources/Honu/Persistence.swift`).
- **Confirm before side effects**: before Claude sends mail, changes a file, or runs a
  command, the turtle spits out a confirmation bubble, and nothing happens until it is
  accepted. Each bubble should also show where it came from.

Smaller improvements:

- **Follow-up questions**: an Ask bubble answers only one question today; let it carry
  on as a multi-turn conversation.
