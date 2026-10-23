# Web Page

A PRD for the Web Page microapp, built into Honu: one web page, or one
YouTube video, in a bubble. It follows `../UI.md`.

## Behavior

- The **Web Page** tile in the launcher has the turtle spit out a new
  page, which asks for a link ("Paste a link, then press Return"). The
  field takes the keyboard focus; text typed before it has the focus goes
  into it.
- A link without a scheme is taken as `https://`. Return opens it, and
  the bubble is titled with the page's host.
- YouTube links (`youtube.com/watch`, `/shorts`, `/live`, `/embed`, and
  `youtu.be`) play in YouTube's embedded player rather than YouTube's
  whole page.
- While the page first loads, its bubble breathes; it rises once the page
  has loaded, and wobbles if it failed. Following links within the page
  does not count. A load given up, as when the bubble is deleted, does
  neither.
- The link is kept, so the page loads again on the next launch.
- Dropped on the octopus, a page is deleted, and comes back with ⌘Z or a
  click on the octopus for a few seconds.

## Non-goals

- A browser: no address bar once a page is open, no tabs, back and
  forward buttons, or bookmarks.
