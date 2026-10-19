# AI Finance

Honu as a desk for following US markets: live prices, news, and the economic and earnings
calendar, shown as bubbles, with Claude explaining and filtering rather than just
displaying. Everything here is written in Honu's terms (microapps, services, bubbles)
so it applies to the egui version and to the SwiftUI port alike.

This section merges two brainstorms: what finance bubbles could show and how to connect
the data, and a design for the *harness* around Claude (the deterministic code that
wakes it, feeds it, checks it, and limits it), from the doc "Financial information
harness: real-time quotes and news".

## Principles

Finance concentrates three things language models are weakest at: **time** (prices
change), **trust** (news can lie), and **numbers** (models miscalculate). So the harness
is not there to make Claude smarter; its job is to take numbers, time, and trust away
from the model and handle them with deterministic code.

- **Claude explains and filters; it never supplies numbers.** Every price, figure, and
  headline Claude talks about comes from a data source through a tool, with its time and
  source, and Honu checks that each number in an answer traces back to one (the numeric
  firewall below).
- **Claude is woken, it does not watch.** Honu's own code watches the streams and calls
  Claude only when something crosses a threshold.
- **Quiet until it matters.** Like the octopus, finance bubbles appear when needed: an
  event about to happen, a price crossing a level, news about something you hold.
  Bubbles show what happens through motion (rise, wobble, breathe), never through
  system notifications, and how often they may interrupt is capped.
- **Your attention is the scarce resource.** The measure of success is how few minutes a
  day you need, not how much data Honu processes.
- **Not investment advice**, and the bubbles say so where Claude gives an opinion.
- **Read-only.** Honu reads, analyzes, and alerts. Drafting or placing orders is out of
  scope, and could only come after the two-model split described under Control.

## What it shows

### Ticker bubbles (a watchlist microapp)

Each item is one symbol, such as `AAPL`.

- **Closed:** the symbol, the last price, and the change since the previous close. The
  bubble's color follows the change. Up and down colors are a setting: US convention is
  green for up, while Taiwan and other East Asian markets use red for up.
- **Open:** today's price as a sparkline, the day's range, the time of the last trade,
  and the item's thesis, if it has one (see Context).
- **Alerts:** the user sets price levels. Crossing one makes the bubble wobble and come
  to the front.
- **Status through motion:** a bubble could breathe faster when the price moves
  unusually fast, and rise when an alert clears.
- **Stale data looks stale:** during market hours, a price older than a few seconds is
  dimmed and shows its age.
- Only the watchlist and theses are saved; prices are not.

### News bubbles

- Only news about symbols on the watchlist, plus major market news, spat out as
  bubbles; everything else stays out of the way.
- Ten outlets writing the same story make one bubble, not ten (see the diff feed).
- Each news bubble carries a one-line summary from Claude, the source's credibility
  tier, and a link to the source.

### Calendar bubbles

- **Macro events:** CPI, nonfarm payrolls, FOMC decisions, and the like.
- **Earnings:** report dates for watchlist symbols, with EPS and revenue estimates.
- A countdown bubble rises from the bottom shortly before an event (for example 30
  minutes) and sits near the related ticker bubbles.
- After the release it shows the actual figure against the forecast, and the related
  ticker bubbles wobble.

### What Claude adds

- **Why it moved:** a line in the ticker bubble that explains today's move from the
  day's news and price data.
- **Narrative alerts:** not "TSMC down 3%", but "TSMC is down 3% because of X; this does
  not conflict with your thesis Y; your exposure is Z; no action needed unless W
  happens." The alert carries its own conclusion about whether to act.
- **Filtering:** of hundreds of headlines, the few that concern the watchlist.
- **Bump to explain:** dragging a news bubble into a ticker bubble asks Claude how that
  news bears on that company. This is the "bumping bubbles shares their context" idea
  in `TODO.md`, and the best demo of the lot.
- **Explain this range:** selecting an unusual stretch of an open ticker's sparkline
  makes Honu gather that window's news and price data, and Claude explains it with
  sources.
- **Around calendar events:** before, what to watch; after, what the figure means, and
  how prices actually reacted in the minutes since.
- Later, with bubbles saved by place: tickers kept together form a portfolio Claude can
  reason about as one.

## Data sources

| Source | Key | What it offers | Caveats |
|---|---|---|---|
| **Finnhub** (recommended) | Free sign-up | Real-time US trades over WebSocket; REST quote, company news, market news, earnings calendar, economic calendar, company profile | The free plan caps how many symbols stream at once (sources say 30 or 50; check the pricing page). Whether the economic calendar is on the free plan is unverified. Crypto symbols such as `BINANCE:BTCUSDT` stream on the same socket, which allows testing while US markets are closed. |
| Alpaca | Free account | Real-time WebSocket | The free feed covers only IEX trades, a small share of US volume: prices are fine, volumes are low. |
| Yahoo Finance | None | Near-real-time quotes through unofficial endpoints | Unofficial: may break or be blocked at any time, terms are unclear, and browsers are blocked by CORS. |
| Forex Factory JSON feed | None | This week's macro calendar (`nfs.faireconomy.media/ff_calendar_thisweek.json`) | Unofficial, no published terms. Forecast and previous only, no actual figure. Times are US/Eastern. Next week's file is sometimes not up yet (404). |
| Financial Modeling Prep | Free plan | Economic and earnings calendars | About 250 requests a day on the free plan. |
| SEC EDGAR | None | Filings and reported financials as JSON (`data.sec.gov/submissions/CIK##########.json`, `data.sec.gov/api/xbrl/companyfacts/CIK##########.json`), the primary documents to check news against | Requires a descriptive `User-Agent` with a contact; about 10 requests a second. Browser CORS unverified. |
| FRED | Free key | Treasury yields and other macro series, for a yield-curve bubble on FOMC days | Daily data, not real time. |
| Federal Reserve, BLS | None | Official FOMC and release schedules | Web pages rather than APIs; good for updating dates once a year. |

Real-time exchange data comes with license terms (redistribution, delayed-data labels).
Personal use is fine; sharing Honu with others means reading them first.

## Connecting the APIs

### Keys

- Keep `FINNHUB_API_KEY` next to `ANTHROPIC_API_KEY`: in `.env` during development (git
  ignores it) and in the Keychain in a macOS app. Never commit a key.
- A key in a web build is visible to whoever uses the page, which is acceptable only for
  personal use.

### Real-time trades over WebSocket (Finnhub)

- Connect to `wss://ws.finnhub.io?token=<key>`.
- Subscribe once per symbol by sending `{"type":"subscribe","symbol":"AAPL"}`, and
  `{"type":"unsubscribe","symbol":"AAPL"}` to stop.
- Trades arrive as `{"type":"trade","data":[{"s":"AAPL","p":231.5,"t":1760000000000,"v":100,"c":[...]}]}`:
  symbol, price, Unix time in milliseconds, volume, and trade conditions. The server also
  sends `{"type":"ping"}`.
- Check these message shapes against Finnhub's WebSocket docs before relying on them;
  they come from third-party clients, not the official docs.
- On disconnect, reconnect with backoff and subscribe to every symbol again.

Handling the stream:

- A busy symbol can trade hundreds of times a second. Receive in the background and fold
  trades into per-symbol state; the UI reads that state at most once a frame, never once
  a trade.
- Per symbol, keep: the last price and time, the previous close (from the REST quote),
  the day's high and low, and one-minute candles in a fixed ring buffer (390 covers a
  regular session).
- US regular hours are 9:30 to 16:00 US/Eastern. Outside them, use a crypto symbol or
  the fake feed below to see bubbles move.

Platform notes:

- **Swift:** `URLSessionWebSocketTask` (`send(.string(...))`, a `receive()` loop) running
  in a `Task`, publishing per-symbol state to the UI through an `@Observable` model on
  the main actor.
- **Rust/egui:** `ewebsock`, which works natively and in the browser (verify the
  version), drained in the microapp's `update` each frame, like the Ask chats' streams.

### REST snapshots (Finnhub)

Base URL `https://api.finnhub.io/api/v1`, with the key as the `token` query parameter:

| Need | Request |
|---|---|
| Quote, previous close | `GET /quote?symbol=AAPL` |
| Company news | `GET /company-news?symbol=AAPL&from=2026-10-12&to=2026-10-19` |
| Market news | `GET /news?category=general` |
| Earnings calendar | `GET /calendar/earnings?from=...&to=...&symbol=AAPL` |
| Economic calendar | `GET /calendar/economic?from=...&to=...` (plan coverage unverified) |
| IPO calendar | `GET /calendar/ipo?from=...&to=...` |
| Company profile, market cap | `GET /stock/profile2?symbol=AAPL` |

These paths and parameters are taken from Finnhub's official Python client. Third-party
sources put the free plan at 60 calls a minute, so poll news every few minutes and
calendars a few times a day, and cache what comes back.

### Macro calendar without a key (Forex Factory feed)

- Fetch `ff_calendar_thisweek.json` about once an hour. Each event has a title, country,
  date (ISO 8601 with a US/Eastern offset), impact, forecast, and previous.
- The free feed has no actual figure, so "actual versus forecast" needs a keyed source.

### Time zones

Event times are US/Eastern, which observes daylight saving time on different dates from
other places. Convert through the time zone database (`TimeZone` in Swift,
`chrono-tz` in Rust), never with a fixed offset.

### One interface per kind of source

Following how Honu reaches Claude through a swappable client in its services:

- A `MarketFeed` service: subscribe and unsubscribe symbols, and a stream of trades.
  Implementations: Finnhub, and a **fake feed** that plays scripted trades, for tests,
  previews, and building the UI with no key or open market. Alpaca or Yahoo can come
  later behind the same interface.
- A `NewsSource` and a `CalendarSource` in the same way, each with a fake.
- Every value these services hand out carries the time it was true and its source.
- A **clock** service too, so a fake feed with a fake clock can replay a past day (the
  flight simulator below) and tests can run a whole session in milliseconds.
- The watchlist, news, and calendar microapps only ever talk to these services.

## The harness

The four parts of the harness around Claude: what wakes it (perception), what it is
given (context), what it may call (tools), and what it may do (control); then how the
results reach the user, and how the harness may improve itself.

### Perception: wake Claude on events, never on ticks

A deterministic **watcher** in the services reads the streams and calls Claude only
when a rule fires. It saves money and noise, and is the first reason to have a harness.

- **Rules:**
  - Price: the z-score of the latest one-minute return against the session's (later,
    the last 20 days') volatility; a user's price level crossed.
  - Volume: a minute's volume against the average for that minute of the day.
  - News: a new story about a watched symbol (after clustering, below).
  - Calendar: a set time before a release, and the release itself.
  - The user: bumping bubbles, selecting a range, or asking.
- **Cooldowns:** per symbol, no second wake within, say, 10 minutes unless the move
  doubles. Thresholds and cooldowns are settings.
- Each wake carries its reason and a diff, and is unit-tested against the fake feed and
  clock, with no model involved.
- **The diff feed:** Honu remembers what it last told Claude about each symbol (price,
  time, stories seen), and a wake sends only what changed since: "since 10:42, 231.50 →
  226.10; one new story, one restating an earlier one; CPI in 25 minutes." Stories are
  clustered before they reach Claude (normalized titles with a word-overlap threshold
  within a day, or a batch handed to a small model to group), so the context budget is
  spent on what is new.
- **Structured input only:** the model gets tables and numbers, never raw material.
  Financials come from EDGAR's XBRL facts rather than PDFs; candles come as numbers
  rather than chart images. Transcribing earnings calls with speakers and tone marked is
  a later step, and needs a source for the audio or transcripts.
- **Source credibility:** each story enters the context with a tier from a fixed table
  (primary filings and wire services first, aggregators next, unknown sources last), and
  whether a primary document, such as an EDGAR filing in the same window, backs it.
  Detecting coordinated posting would need social feeds, which are out of scope for
  now.
- **Manipulation signal:** a low-tier source, a small company (market cap from the
  profile), and unusual volume together tag a story "possible pump". It is shown as
  such and kept out of the normal explanations.
- **Models:** a small, fast model classifies, groups, and summarizes headlines in
  batches; the larger one explains. Explanations are cached per symbol for a while.

### Context: organized by thesis, not by time

Memory is organized around what you believe, not the order things happened, so that
when it is compacted, details go and judgments stay.

- **Thesis ledger:** a ticker can carry a thesis: one sentence on why you hold or watch
  it, and what would prove it wrong. In Honu, a thesis is written in the ticker's open
  panel, or by bumping a note into the ticker bubble. Theses stay in every request, and
  the first question Claude answers about any related story is structured: does this
  break the thesis (yes, no, unclear), and which condition. A "yes" wobbles the ticker
  with a narrative alert.
- **Layered memory:** hot is today's compressed price path and what has happened so far;
  warm is this week's daily narratives; cold is the theses, past decisions, and the
  calibration ledger. Requests put the stable layers first so prompt caching covers
  them.
- **After-close job:** after the close (or at the next launch, if Honu was not running),
  Claude writes the day's narrative, proposes thesis updates for the user to accept
  (never rewriting a thesis on its own), and lists what to watch tomorrow, which feeds
  the watcher. The next morning starts from a clean context and a briefing bubble.
- **Dynamic budget:** the request is built from blocks, each with a priority and a size
  estimate, filled in priority order. On an ordinary day that might be 40% theses, 30%
  news, and 30% prices; on an FOMC day, the calendar switches priorities so rates come
  first and holdings news moves to the back.
- **As-of reasoning:** every value carries its time, and every request states the
  current time, so Claude reasons as of a moment ("known as of 10:42:13 ET") and cannot
  take a three-day-old price for today's. The same discipline keeps a replay or backtest
  from seeing the future.

### Tools: Claude does no arithmetic

Instead of guessing what to send, give Claude read-only tools and let it fetch what a
question needs, in a tool-use loop that Honu runs locally with the user's keys:

- `get_quote(symbol)`, `get_candles(symbol, range)`, `get_news(symbol, since)`,
  `get_calendar(from, to)`, and, for answers as bubbles, `create_bubble(...)`.
- Calculations are tools too: `change(symbol, from, to)`, `correlation(a, b, range)`,
  and later exposure and risk figures. Honu computes them; Claude interprets them.
- Arguments are checked before running: symbols against the watchlist or the symbol
  format, dates as dates. No tool takes a free-form URL or text.
- Honu executes each call against the services and returns the result, until Claude
  answers. "Why is NVDA down today?" then becomes a quote, a news lookup, and an answer
  with sources.
- This needs the Messages API's tools: send `tools` with the request, run each
  `tool_use` block when the response stops for `tool_use`, and answer with a
  `tool_result` carrying its `tool_use_id`. Today's `claude::Client` only streams text.

**The numeric firewall**, the base of trust in everything Claude says:

- Each tool result is given a short id (`q1`, `n3`) at the top of its content, and Honu
  keeps the result.
- The prompt requires a citation after every number in the answer (`226.10 [q1]`), and
  says to leave out any number it cannot cite.
- When the answer ends, Honu finds every number in it and checks that it has a citation
  and that the cited result holds that value, after normalizing the formatting (`$`,
  thousands separators, `%` against fractions, K/M/B, rounding to the digits shown).
  Dates, times, and counting words in prose are exempt; the exemptions stay narrow.
- Verified numbers show their source on hover. A number that fails is dimmed and marked,
  so it cannot pass as a fact.

Later tools:

- **Backtest as a tool:** Claude proposes a rule, Honu runs it over history and returns
  the results, and Claude iterates. The holdout data must stay out of Claude's reach, or
  it will fit the noise beautifully.
- **Paper trading:** a simulated account would give Claude a track record to learn from.
  It changes nothing outside Honu, but it comes after the calibration ledger, which
  measures much the same thing without the pull towards trading.

### Control: graded capabilities and the lethal trifecta

This is the part without which none of the rest should ship.

**Graded capabilities.** Permissions are budgets, not yes or no:

| Level | Example | In Honu |
|---|---|---|
| Read | quotes, news, filings | Free |
| Analyze | explanations, thesis checks | Free |
| Alert | a bubble wobbling to the front | Automatic, within a quota |
| Draft an order | | Out of scope; would need a confirmation bubble |
| Execute | | Out of scope; would need hard gates: amount limits, a time lock, a second confirmation |

- **Alert quota:** at most a few interruptions an hour (a wobble that brings a bubble to
  the front). Past the quota, alerts gather quietly in a digest bubble. Otherwise "AI
  makes you overtrade" comes before "AI makes you money".
- **No confidence cliff:** a run of good calls never raises Claude's quotas or
  capabilities by itself. Only the user changes them, in settings.

**The lethal trifecta.** News is untrusted content, the watchlist and theses (and any
positions) are private data, and anything that sends data out of the machine is an
outward action. An agent holding all three is a textbook attack surface: one fake story
with instructions planted in it can make the agent leak or act. Even read-only, Honu
keeps the three apart:

- The model that reads news has no tool that can send data anywhere: tool arguments are
  symbols and dates, checked as above.
- Links in bubbles come only from tool results (a story's source URL), never from text
  the model wrote; Honu drops any URL the model composes. Answers never load remote
  images.
- Sending requests to the Claude API and the data providers is accepted as going to
  trusted parties.

If orders were ever in scope, the design splits the work between two models:

1. Model A reads the news and the theses and holdings, and may only emit fields of a
   fixed schema: a symbol from the watchlist, a direction, a confidence, ids of the
   claims it relies on.
2. A data diode between them is Honu code that lets through only valid fields of that
   schema: enums, numbers, and known symbols, never free text.
3. Model B reviews proposed orders from those fields, the positions, and tool-computed
   numbers, and never sees any natural-language news.
4. A gate (limits, a time lock, the user's confirmation) stands between Model B and the
   broker.

No component holds all three legs. (The source doc had a diagram of this, six
components and one diode, that did not survive the export.)

### Interface: what matters now

- **A layout that fits the day:** in earnings season, a bubble comparing reported
  figures with estimates; on an FOMC day, a yield-curve bubble; on a quiet day, a thesis
  review checklist. The turtle spits out the day's bubbles in the morning briefing.
- **Narrative alerts** (above): the conclusion comes with the alert.
- **Glass-box audit:** every Claude request (the full context, each tool call and
  result) and its answer is appended to a local log, and a bubble's "Why?" replays what
  Claude saw and why it said what it said. It never holds keys, lives outside the app's
  saved state (it grows), and is pruned after a while.
- **Voice briefing:** for the SwiftUI port, a spoken briefing (`AVSpeechSynthesizer`)
  that can be interrupted with a question, answered from live data rather than a
  recording. Later.

### Learning from the user, carefully

Self-improvement stays in the harness: Claude may refine its prompts and Honu's alert
thresholds, never model weights or its own capabilities.

- **Calibration ledger:** every judgment Claude makes is stored as a checkable claim
  with a confidence and a date it resolves ("closes above X by Friday"). Honu resolves
  it from the data and scores it (a Brier score and a calibration curve). Once a month
  Claude reviews its record and proposes prompt changes, which the user accepts.
- **Alert rules evolve:** opening a bubble counts as useful, feeding it to the octopus
  quickly as noise; thresholds move within set bounds accordingly.
- **A/B summaries:** two ways of writing news summaries alternate between bubbles, and
  the one read more and fed to the octopus less wins.

Two traps to block first:

1. **Goal hijacking:** if the goal is "the user reacts to alerts", the agent learns to
   be alarmist; if it is "the paper account makes money", it overfits. The goal has to
   be out-of-sample results plus the user's time.
2. **Markets are not stationary:** they are adversarial, and yesterday's good rule can
   be today's trap. Everything learned keeps tracking its own hit rate and retires
   itself when it decays.

## Wilder directions

The parts exist; the whole is unproven.

- **News as code:** parse each story into falsifiable claims (the claim, what would
  falsify it, an expiry date) and track their survival, showing which market narratives
  are dying. Claims could be bubbles that shrink towards their expiry and sink when
  falsified: a view of narratives' lifetimes instead of a news stream.
- **Flight simulator:** replay a past day's full stream through the fake feed and clock,
  outcomes hidden, let Claude or you decide, then reveal. It trains the agent, and you.
- **Three things a day:** turn the goal around from "Claude knows more" to "you need to
  look at only three things today", measured in minutes.
- **Agents exchanging claims (A2A):** publish and subscribe to structured claims, and
  calibrate against other people's agents. The Moltbook lesson applies directly: one
  adversary can poison thousands of agents into a coordinated false consensus, so this
  waits for signed sources and reputation.
- **Thesis version control:** each thesis keeps its history, with branches for scenarios
  and merges when two theses join, so you can diff yourself now against three months
  ago.

## Suggested order

1. A fake feed and clock, and ticker bubbles: live-looking prices, colors, and alerts
   with no key, each value carrying its time from the start.
2. Finnhub: the WebSocket for trades and the REST quote for the previous close.
3. The open ticker panel with today's sparkline.
4. Calendar bubbles: earnings from Finnhub, macro events from the Forex Factory feed.
5. The watcher: event wakeups, cooldowns, and the diff feed, tested against the fake
   feed, before anything calls Claude.
6. News bubbles with Claude's one-line summaries, under the numeric firewall, the link
   rule, and the alert quota from the first call.
7. The tool-use loop with the finance tools; bump to explain, and explain this range.
8. Theses, narrative alerts, and the after-close job.
9. Later: the calibration ledger, the glass-box log, the day's layout, and the wilder
   directions.

If only three harness pieces get built, they are the event wakeups, the numeric
firewall, and keeping the trifecta apart: the rest stands on them.

## Open questions

- Up and down colors: US convention or East Asian, or follow the system locale?
- How many symbols the watchlist needs, against the free plan's streaming cap.
- Whether the web build matters, given keys in the page and CORS on unofficial sources.
- Whether a thesis belongs to the ticker item or is a note linked to it.
- Default alert quota and wake thresholds, and how far the learned ones may move.
- Where the glass-box log lives and how long it is kept.
- Whether orders ever come into scope, which decides whether the two-model split is
  built at all.
