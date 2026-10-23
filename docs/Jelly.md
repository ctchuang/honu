# Jelly Bubbles

A PRD and implementation plan for bubbles that squash, stretch, and
wobble like jelly, with what they show squashing along.

## PRD

### Background

A bubble is Liquid Glass with weight (`UI.md`, principle 4): it can be
thrown, it glides to a stop, crowded bubbles push each other apart, and
bubbles bounce off the screen edges. But it stays a rigid rounded
rectangle through all of it. It moves like a window that slides, not
like the bubble it is named for.

Breathing (`swell`) already changes a bubble's glass without touching
its content. Jelly goes further: the whole bubble, glass and content,
gives under the forces on it and springs back, as a cartoon would draw
it.

### Goals

- A bubble looks soft and alive: it squashes when it hits something,
  stretches when it moves fast, lags behind when dragged, and wobbles a
  few times before it settles.
- The effect is plain to see, closer to a cartoon than to a subtle
  physical simulation, without getting in the way of using a bubble.
- What a bubble shows deforms with its glass, so the bubble reads as one
  soft object, not a rigid card behind a wobbling pane.
- A bubble at rest looks exactly as it does today, and costs nothing.

### Non-goals

- Bubbles sticking together or merging (a separate idea in `TODO.md`).
- Deforming the turtle, the octopus, or the launcher.
- Non-linear deformation of the content (bending text or a web page
  along a curve): only the glass bends; the content squashes,
  stretches, and shears.
- Letting the user turn the effect off or tune it. It may come later,
  for Reduce Motion.

### Terms

- **Outline**: the shape of a bubble's glass. At rest, the rounded
  rectangle it has today; while wobbling, a smooth closed curve through
  a ring of points.
- **Ring**: the points the outline runs through, each with where it
  sits at rest, on the rounded rectangle.
- **Content transform**: the squash, stretch, and shear the bubble's
  content (its title and its microapp's view) takes while the outline
  wobbles: the linear map that best fits the ring's points from where
  they rest to where they are.
- **At rest**: a bubble whose ring has settled; it has no ring, its
  outline is the rounded rectangle, and its content transform is the
  identity.

### User stories

1. As a user, I throw a bubble at the edge of the screen; it flattens
   against the edge, bulges sideways, and wobbles back into shape as it
   bounces off.
2. As a user, I drag a bubble around quickly; it stretches along the way
   it moves and trails behind the pointer, and when I stop, it
   overshoots and jiggles.
3. As a user, I knock one bubble into another; both jiggle.
4. As a user, I click the turtle; the new bubble lands with a splat and
   wobbles into shape.
5. As a user, a bubble that rises or wobbles to show its status
   jiggles as it does.
6. As a user, I read, type, or click a link in a bubble at rest, and
   nothing about it has changed.

### Behavior

**What makes a bubble wobble**

A bubble's ring is a soft body that lags behind the bubble: whenever the
bubble's speed or direction changes, the ring feels the opposite, as
jelly in a jar would. That one rule covers every case:

| What happens | What the ring feels | What it looks like |
|---|---|---|
| Bouncing off a screen edge | The bubble reverses at once | The side that hit flattens against the edge, the rest bulges out, then it wobbles. |
| Being dragged | The pointer's starts, stops, and turns | It trails behind the pointer, and overshoots when the pointer stops. |
| Being thrown and gliding | Friction slows it | It leans back a little as it slows. |
| Being pushed by another bubble | The push | It jiggles. |
| Rising or wobbling for its status | The motion, which moves the drawn bubble | It jiggles along. |

On top of that, a fast bubble stretches along the way it moves and
narrows across it, keeping its area, as cartoons draw speed. A bubble
also splats when it lands after flying out of the turtle (or back out of
the octopus): it flattens and widens, then wobbles back.

**How it looks**

- The glass takes the outline: flattened where it touches a screen
  edge, bulging or caving in elsewhere, with corners that stay round.
- The content takes the content transform, about the bubble's center:
  it squashes, stretches, and shears with the glass, and moves with it.
  It never pokes out past the glass: where the outline caves in more
  than the rim, the content shrinks a little more.
- The deformation is large enough to see from across the screen: a hard
  bounce squashes a bubble by up to about a quarter, and it wobbles
  about three times a second for around a second before it settles.
- Breathing still swells the glass, along the outline.
- A bubble on top still covers the ones below completely: the glass and
  content cut away from a bubble below follow the outline of the one
  above.

**What it does not change**

- Where a bubble is, how it moves, and how it collides (the physics in
  `Physics.swift`) stay as they are. The jelly follows the bubble; it
  never pushes it.
- Hit-testing, the rim that resizes, and the cursor follow the bubble at
  rest. A wobble lasts about a second; presses during it land on the
  content as AppKit maps them through the content transform.
- A bubble being resized, flying, or swallowed does not wobble, and a
  bubble whose size changes (resizing, zooming, its microapp asking for
  another size) comes to rest at once.
- A bubble at rest is drawn exactly as today, and nothing about it is
  computed each frame.

### Success criteria

- Every item of the behavior above holds in the running app.
- Typing, selecting, scrolling, and clicking links in a bubble at rest
  behave as before.
- With one or two bubbles wobbling at a time, Honu keeps the display's
  frame rate.
- `swift build`, `swift test`, and `swift format lint --strict` pass at
  every step.

## Design

### What the experiments showed

A throwaway app tried the approach before this plan (October 2026):

- **Content can deform.** A SwiftUI `transformEffect` with different x
  and y scales and a shear squashes a `WKWebView` (`WebView`) and an
  `NSTextView` (`TextEditor`) correctly: grid lines stay straight, text
  stays sharp, CSS animations keep running. AppKit's hit-testing follows
  the transform.
- **Glass takes any shape.** `glassEffect(in:)` renders a smooth closed
  curve through a ring of points, concave or convex, tinted, inside the
  `GlassEffectContainer`, without artifacts.
- **Non-linear content is out.** SwiftUI's shaders cannot draw AppKit
  views, and the Command Line Tools have no Metal compiler, so the
  content is limited to linear maps (squash, stretch, shear).
- **The soft body needs two things.** Clamping the ring's points to a
  wall leaves sharp ears at the corners; a stiff spring on whatever
  pokes past the wall, and a bending force that keeps each point where
  it rests relative to its neighbors, keep the corners round.
- **The cost is in drawing, not the physics.** The physics took 0.1 to
  0.6 ms a frame for 16 bubbles. With 8 bubbles all wobbling at once:
  moving without deforming took 38% CPU, deforming only the glass 40%,
  deforming the content too 90%, and everything with cut-aways 122%;
  16 bubbles all wobbling at once dropped frames. Only bubbles that
  wobble may pay for it.

### The model

`Jelly` (`Stage/Jelly.swift`) is a ring of points around a bubble's
center, at full scale, pure value code that tests can drive:

- **Rest shape**: points on the bubble's rounded rectangle, a few on
  each corner and the rest spread along the sides, with their outward
  normals. It is rebuilt when the size changes.
- **Shape matching**: each point is pulled by a spring toward a goal:
  where it rests, mapped through the area-keeping part of the linear map
  that best fits the ring now (so it can squash and bulge without losing
  area), blended with the identity, and stretched along the bubble's
  velocity.
- **Bending**: each point is pulled toward where it rests relative to
  the midpoint of its two neighbors, keeping the outline smooth.
- **Inertia**: each frame, the ring's points feel the opposite of the
  change in the bubble's smoothed velocity (of where it is drawn, so
  status motions count), capped so a hard hit stays a cartoon squash
  rather than a collapse.
- **Walls**: a stiff spring pushes back whatever pokes past the screen
  edges.
- **Splat**: an impulse on the ring's points that widens and flattens
  it.
- **Settling**: once every point is within a fraction of a point of its
  rest, nearly still, and the bubble is slow, the ring is dropped.
- Low stiffness and damping make it wobble slowly and a few times; it
  runs in substeps, since the walls are stiff.

The **content transform** is the best-fit linear map and the ring's
offset, about the center, shrunk where the outline caves in past the
rim.

`Bubble` owns its jelly while it wobbles, and publishes only what views
read: the outline's points (none at rest) and the content transform
(the identity at rest), written only when they change. `Stage.step` steps
every free bubble's jelly after the physics.

### The view

- `BubbleView`: the content takes `transformEffect(contentTransform)`;
  the glass and the clip take the outline (the rounded rectangle at
  rest, the smooth curve through the ring otherwise), swollen by
  breathing along the normals.
- `StageView.cuts`: a cut is the outline of the bubble above, mapped
  into the one below, grown by the gap: the rounded rectangle as today
  for a bubble at rest, the curve for one wobbling.

## Plan

Each step is one or more commits that build, pass the tests, and pass the
lint on their own.

### Step 1: The PRD (done)

- This document; `TODO.md` marks the jelly effect as started.

### Step 2: The jelly model

- `Jelly`: the rest shape, shape matching, bending, inertia, walls,
  stretch, splat, settling, and the content transform.
- Tests (`JellyTests`): a ring left alone stays at rest; a change in
  velocity sets it wobbling and it settles exactly; a hit on a wall
  flattens the side that hit and bulges the others; area is roughly
  kept; a fast ring stretches along its velocity; the content stays
  inside the outline.

### Step 3: Bubbles wobble

- `Bubble` tracks where it is drawn and its smoothed velocity, creates
  its jelly when something sets it wobbling, drops it once it settles,
  and comes to rest when its size changes or it is resized, flying, or
  swallowed. It publishes the outline and the content transform.
- `Stage.step` steps the jelly of every bubble after the physics; a
  landing after a flight splats.
- Tests (`JellyTests`, `PhysicsTests`): a bubble thrown at the edge
  wobbles and then rests with no outline and the identity transform; a
  bubble left alone never gets a ring; resizing or zooming brings it to
  rest; a spawned bubble splats when it lands.

### Step 4: The view

- `BubbleView`: the content transform, and the glass and clip along the
  outline.
- `StageView.cuts` and `Cut`: cuts follow the outline of a wobbling
  bubble above.
- Tune the stiffness, damping, caps, and stretch in the running app
  until the look is cartoon-like but readable.

### Step 5: Docs

- `UI.md`: jelly in principle 4 and in **Bubbles**; `CLAUDE.md`: the
  architecture; `TODO.md`: the jelly effect is off the list; the steps
  here are marked (done).
