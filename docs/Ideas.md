# AI Finance

Honu as a desk for following US markets: live prices, news, and the economic and earnings
calendar, shown as bubbles, with Claude explaining and filtering rather than just
displaying. Everything here is written in Honu's terms (microapps, services, bubbles)
so it applies to the egui version and to the SwiftUI port alike.

Principles:

- **Claude explains and filters; it never supplies numbers.** Every price, figure, and
  headline Claude talks about comes from a data source and is passed to it, with its
  time and source, which the bubble shows too.
- **Quiet until it matters.** Like the octopus, finance bubbles appear when needed: an
  event about to happen, a price crossing a level, news about something you hold.
  Bubbles show what happens through motion (rise, wobble, breathe), never through
  system notifications.
- **Not investment advice**, and the bubbles say so where Claude gives an opinion.
- **Read-only.** No trading, and no tool that changes anything outside Honu.

## What it shows

### Ticker bubbles (a watchlist microapp)

Each item is one symbol, such as `AAPL`.

- **Closed:** the symbol, the last price, and the change since the previous close. The
  bubble's color follows the change. Up and down colors are a setting: US convention is
  green for up, while Taiwan and other East Asian markets use red for up.
- **Open:** today's price as a sparkline, the day's range, and the time of the last
  trade.
- **Alerts:** the user sets price levels. Crossing one makes the bubble wobble and come
  to the front.
- **Status through motion:** a bubble could breathe faster when the price moves
  unusually fast, and rise when an alert clears.
- Only the watchlist is saved; prices are not.

### News bubbles

- Only news about symbols on the watchlist, plus major market news, spat out as
  bubbles; everything else stays out of the way.
- Each news bubble carries a one-line summary from Claude and links to the source.

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
- **Filtering:** of hundreds of headlines, the few that concern the watchlist.
- **Bump to explain:** dragging a news bubble into a ticker bubble asks Claude how that
  news bears on that company. This is the "bumping bubbles shares their context" idea
  in `TODO.md`, and the best demo of the lot.
- **Around calendar events:** before, what to watch; after, what the figure means, and
  how prices actually reacted in the minutes since.
- Later, with bubbles saved by place: tickers kept together form a portfolio Claude can
  reason about as one.

## Data sources

| Source | Key | What it offers | Caveats |
|---|---|---|---|
| **Finnhub** (recommended) | Free sign-up | Real-time US trades over WebSocket; REST quote, company news, market news, earnings calendar, economic calendar | The free plan caps how many symbols stream at once (sources say 30 or 50; check the pricing page). Whether the economic calendar is on the free plan is unverified. Crypto symbols such as `BINANCE:BTCUSDT` stream on the same socket, which allows testing while US markets are closed. |
| Alpaca | Free account | Real-time WebSocket | The free feed covers only IEX trades, a small share of US volume: prices are fine, volumes are low. |
| Yahoo Finance | None | Near-real-time quotes through unofficial endpoints | Unofficial: may break or be blocked at any time, terms are unclear, and browsers are blocked by CORS. |
| Forex Factory JSON feed | None | This week's macro calendar (`nfs.faireconomy.media/ff_calendar_thisweek.json`) | Unofficial, no published terms. Forecast and previous only, no actual figure. Times are US/Eastern. Next week's file is sometimes not up yet (404). |
| Financial Modeling Prep | Free plan | Economic and earnings calendars | About 250 requests a day on the free plan. |
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
- The watchlist, news, and calendar microapps only ever talk to these services.

## Claude integration

### Context, not memory

Each request carries what Claude needs, with times and sources: the symbol's recent price
path, today's headlines about it, and upcoming or just-released events. The prompt tells
Claude to use only the numbers given and to say when they are not enough.

### Claude as an agent with finance tools

Instead of guessing what to send, give Claude read-only tools and let it fetch what a
question needs, in a tool-use loop that Honu runs locally with the user's keys:

- `get_quote(symbol)`, `get_candles(symbol, range)`, `get_news(symbol, since)`,
  `get_calendar(from, to)`, and, for answers as bubbles, `create_bubble(...)`.
- Honu executes each tool call against the services above and returns the result, until
  Claude answers. "Why is NVDA down today?" then becomes a quote, a news lookup, and an
  answer with sources.
- Only read-only tools. Anything with a side effect would need the confirmation bubble
  from `TODO.md`, and trading is out of scope.

### When to ask, and with which model

- Ask on events, never on ticks: a move beyond a threshold, news about a watched symbol,
  a calendar release, or the user bumping or asking.
- Use a small, fast model for classifying and filtering headlines, and a larger one for
  explanations. Batch headlines, and cache an explanation per symbol for a while.

## Suggested order

1. A fake feed and ticker bubbles: live-looking prices, colors, and alerts with no key.
2. Finnhub: the WebSocket for trades and the REST quote for the previous close.
3. The open ticker panel with today's sparkline.
4. Calendar bubbles: earnings from Finnhub, macro events from the Forex Factory feed.
5. News bubbles with Claude's one-line summaries.
6. Bump to explain, and Claude's finance tools.

## Open questions

- Up and down colors: US convention or East Asian, or follow the system locale?
- How many symbols the watchlist needs, against the free plan's streaming cap.
- Whether the web build matters, given keys in the page and CORS on unofficial sources.
