# IMPLEMENTATION_PLAN.md

**Project:** `trading_app` — Flutter mobile trading / market-data application
**Status:** Technical specification and staged roadmap. Phase 1 complete; no feature code written yet.
**This document is the source of truth for the implementation.** It is a guide, not a contract — if reality proves a simpler approach is better, change the plan and note why.

---

## Table of contents

1. [Scope](#1-scope)
2. [Architecture overview](#2-architecture-overview)
3. [Project structure](#3-project-structure)
4. [Domain models and numeric handling](#4-domain-models-and-numeric-handling)
5. [WebSocket layer](#5-websocket-layer)
6. [Quotes: repository and state](#6-quotes-repository-and-state)
7. [Alerts: semantics, evaluator, coordinator](#7-alerts-semantics-evaluator-coordinator)
8. [Persistence (Hive)](#8-persistence-hive)
9. [State management (Cubits)](#9-state-management-cubits)
10. [Screens and navigation](#10-screens-and-navigation)
11. [Design system](#11-design-system)
12. [Error handling](#12-error-handling)
13. [Performance](#13-performance)
14. [App lifecycle](#14-app-lifecycle)
15. [Configuration](#15-configuration)
16. [Testing strategy](#16-testing-strategy)
17. [Dependencies](#17-dependencies)
18. [Implementation phases](#18-implementation-phases)
19. [Decision log](#19-decision-log)
20. [What we intentionally do not build](#20-what-we-intentionally-do-not-build)
21. [Assumptions and open questions](#21-assumptions-and-open-questions)
22. [Learning goal](#22-learning-goal)
23. [Simplicity principles](#23-simplicity-principles)
24. [Consistency checklist](#24-consistency-checklist)

---

## 1. Scope

A live list of financial instruments with Bid/Ask prices streamed over **one** application-wide WebSocket, an instrument detail screen, and price alerts (absolute and percentage) evaluated against that stream, persisted locally with Hive and announced globally when triggered.

| In scope | Out of scope |
| --- | --- |
| Live quotes list (all instruments) | Order placement, trading execution |
| Instrument details | Charts, historical data |
| Absolute + percentage alerts, Bid/Ask, Above/Below | Server-side alerts, push notifications |
| Crossing-based alert evaluation | Auth, user accounts |
| Hive persistence of active alerts + history | Offline quote replay / backfill |
| Auto-reconnect + auto-resubscribe | Background execution |
| Bottom navigation: Quotes / Alerts / History | Deep linking, i18n |
| Unit tests for business logic, selected widget tests | Arbitrary coverage targets |

---

## 2. Architecture overview

Feature-oriented with a light domain/data/presentation split. Three layers where three layers earn their place — not five.

```
  WebSocket server
        │
        ▼
  MarketDataSocket              core/network/ — connection, subscriptions,
        │                       reconnect, status, parsing (via quote_parser)
        │  Stream<Quote>  +  Stream<ConnectionStatus>
        ▼
  QuoteRepository               thin seam: keeps Cubits free of socket details
        │
        ├─────────────────────────────┐
        ▼                             ▼
  QuotesCubit                   AlertCoordinator
  Map<String,Quote> + status    holds previous quote per symbol
        │                             │  calls
        ▼                             ▼
  UI (BlocSelector per row)     AlertEvaluator  (pure function, no I/O)
                                      │  triggered alerts
                                      ▼
                                AlertsCubit ──► AlertRepository ──► Hive
                                      │
                                      ▼
                                AlertNotificationHost (above the Navigator)
```

**Why the WebSocket is application-wide, not owned by a screen**

- The quotes list needs every instrument; alerts must keep evaluating no matter which tab is open. A screen-owned socket would reconnect on every navigation and stop alert evaluation when the screen is popped.
- Connections are an expensive, server-rate-limited resource. One connection with N logical subscriptions is the only sane contract.

**Hard rule:** no widget, page or screen-scoped Cubit ever constructs, opens, closes or reconnects a socket. Screens read `QuotesCubit` state; that is all.

**Why `QuoteRepository` exists at all** (it is thin, so it needs a reason): it is the seam that keeps `QuotesCubit` free of socket internals, and it makes Cubit tests trivial — fake the repository instead of faking a transport and driving a reconnect state machine. It does **not** cache: the last-known map lives in `QuotesState`, so there is exactly one source of truth for the UI.

---

## 3. Project structure

```
lib/
  main.dart                      entry point → bootstrap()
  bootstrap.dart                 error zone, Hive init, dependencies, runApp

  app/
    app.dart                     MaterialApp.router + providers
    app_dependencies.dart        explicit composition root (no DI framework)
    alert_coordinator.dart       quote stream → AlertEvaluator → AlertsCubit
    router.dart                  go_router: shell + 3 branches + create route
    widgets/
      app_shell.dart             Scaffold + NavigationBar (Quotes/Alerts/History)
      alert_notification_host.dart   global banner above the whole shell

  core/
    app_config.dart              dart-define values
    errors.dart                  AppException + logError()
    theme/
      app_colors.dart
      app_typography.dart
      app_text_styles.dart
      app_spacing.dart
      app_theme.dart
    network/
      websocket_transport.dart   interface + real + fake implementation
      market_data_socket.dart    THE socket: connect, subscribe, reconnect, status
      quote_parser.dart          protocol-specific JSON → Quote (isolated on purpose)

  features/
    instruments/
      domain/instrument.dart
      data/instrument_repository.dart        reads assets/instruments.json
      presentation/
        instruments_cubit.dart
        instruments_state.dart
        instruments_page.dart                tab 0 — "Quotes"
        instrument_details_page.dart
        widgets/instrument_tile.dart

    quotes/
      domain/quote.dart                      Quote + QuoteSide
      data/quote_repository.dart
      presentation/
        quotes_cubit.dart
        quotes_state.dart
        widgets/price_text.dart
        widgets/connection_banner.dart

    alerts/
      domain/
        price_alert.dart                     model + enums + factories
        alert_evaluator.dart                 pure, no Flutter, no I/O
      data/
        alert_repository.dart                Hive box access
        hive_adapters.dart                   GenerateAdapters spec (+ .g.dart)
      presentation/
        alerts_cubit.dart
        alerts_state.dart
        alerts_page.dart                     tab 1 — active
        alert_history_page.dart              tab 2 — triggered
        create_alert_page.dart               full-screen form
        widgets/alert_tile.dart

assets/instruments.json
test/                            mirrors lib/, plus test/helpers/
```

**One repository class per feature.** No `XRepository` interface plus `XRepositoryImpl` plus `XLocalDataSource` plus DTO plus mapper. There is exactly one implementation of each repository, and `mocktail` mocks concrete classes, so the interface would buy nothing. If a second implementation ever appears, extracting an interface is a two-minute refactor.

**Where parsing lives:** `quote_parser.dart` holds the protocol-specific JSON handling in one small file, because the message format is an assumption (§21) that will likely change once the real endpoint is known. That is a current, concrete reason to isolate it — not speculation.

---

## 4. Domain models and numeric handling

### 4.1 Numeric type for prices

**Decision: use `double`, with percentage targets rounded once at creation.**

Reasoning, because this is the decision a fintech reviewer will probe:

- This app **displays** prices and **compares** them against thresholds. It does not sum, allocate, settle or accumulate money, which is where binary floating point actually breaks down. A `double` holds 15–17 significant digits — far more than any instrument's tick size needs.
- The one place float error is observable is percentage maths: `100 * (1 + 10 / 100) == 110.00000000000001`. A target price of `110.00000000000001` would never be reached by an incoming price of exactly `110.0`, so the alert would silently never fire. This is a real bug, and it is fixed with one line at alert creation:

```dart
// Percentage targets are rounded once, at creation, so the stored threshold is
// a clean decimal value. Without this, 100 * (1 + 10 / 100) =
// 110.00000000000001 and a quote of exactly 110.0 would never cross it.
double roundPrice(double value) => double.parse(value.toStringAsFixed(6));
```

The example matters more than it looks: the figure first written here (`200 * 1.05`) happens to be **exact** in IEEE-754, so it proved nothing. Scanning every price from 100.00 to 500.00 against ±5 % and +10 % turns up a drifting target roughly every other price, which is the actual justification for rounding.

- Crossing comparisons themselves need no epsilon: they compare two observed prices against a stored threshold, and any error is ~1e-13 against prices quoted to at most a few decimals.
- **What would change the decision:** if the app ever computed portfolio values, P&L or order sizes, `double` would be wrong and the right answer would be scaled integers (minor units) or `package:decimal`. Recorded in `NOTES.md` as a known boundary.

Using `double` also keeps JSON parsing and Hive serialisation direct, with no string conversion layer on either side.

### 4.2 Models

```dart
class Quote {
  final String symbol;
  final double bid;
  final double ask;
  final DateTime timestamp;      // server time, from the frame's `t` (Unix seconds)

  double priceFor(QuoteSide side) => side == QuoteSide.bid ? bid : ask;
}

enum QuoteSide { bid, ask }

class Instrument {
  final String symbol;           // "AAPL.US"
  final int contractType;        // raw protocol code; meaning undocumented (§21)
}

enum AlertDirection { above, below }
enum AlertKind { absolute, percentage }
enum AlertStatus { active, triggered }

class PriceAlert {
  final String id;
  final String symbol;
  final QuoteSide side;
  final AlertDirection direction;
  final AlertKind kind;
  final double targetPrice;      // absolute: user input; percentage: computed at creation
  final double? percentage;      // percentage alerts only
  final double? referencePrice;  // price of `side` when the alert was created
  final DateTime createdAt;
  final AlertStatus status;
  final DateTime? triggeredAt;
  final double? triggeredPrice;
}
```

All immutable, `Equatable`, with `copyWith`. `contractType` stays a raw `int`: the code meanings are not documented, and inventing an enum of guessed names would encode a guess into the domain. The UI renders it as a plain label.

Two named constructors on `PriceAlert` do the validation and the percentage maths, so no caller can build an inconsistent alert:

```dart
PriceAlert.absolute({symbol, side, direction, targetPrice, referencePrice});
PriceAlert.percentage({symbol, side, percentage, referencePrice});
  // direction  = percentage > 0 ? above : below
  // targetPrice = roundPrice(referencePrice * (1 + percentage / 100))
```

There is no separate `AlertTrigger` type: the evaluator returns the alerts that crossed, and the coordinator already holds the quote, so it knows the triggering price.

---

## 5. WebSocket layer

Three small files, not a networking framework.

### 5.0 Wire protocol (confirmed against the live server)

Endpoint: `wss://webquotes.geeksoft.pl/websocket/quotes`. Every frame is a JSON object with `p` (path), optional `d` (data) and optional `i` (request id).

| Direction | Frame |
| --- | --- |
| Subscribe | `{"p":"/subscribe/addlist","d":["BTCUSD"]}` |
| Unsubscribe | `{"p":"/subscribe/removelist","d":["BTCUSD"]}` |
| Quotes | `{"p":"/quotes/subscribed","d":[{"s":"BTCUSD","b":70010.5,"a":70020.5,"t":1770284465}]}` |
| Acknowledgement | `{"p":"/subscribe/addlist","i":0}` |

`s` symbol, `b` bid, `a` ask, `t` Unix seconds. Three consequences shape the code:

- **A frame carries a list, not one quote**, so `parseQuotes` returns `List<Quote>`.
- **A frame may cover only some subscribed symbols**, which the `Map<String,Quote>` in `QuotesState` already handles — each entry is updated independently.
- **Acknowledgements share the envelope with quotes**, so non-quote frames are dropped silently instead of logged (§5.4).

Verified by driving `MarketDataSocket` against the live endpoint during Phase 5: subscribe is accepted, quotes parse, `dispose()` closes cleanly. Note that only 24/7 instruments (`ADAUSD`, `BTCUSD`) tick outside exchange hours — the equities in `assets/instruments.json` stay at `—` over a weekend, which is correct behaviour, not a bug.

### 5.1 Three concepts that must not be conflated

| Concept | What it is | Cardinality |
| --- | --- | --- |
| **WebSocket connection** | One connection to the server, owned by `MarketDataSocket`. Can drop and be re-established. | **Exactly 1 per app** |
| **Logical subscription** | "I want updates for `AAPL.US`" — a protocol message over the existing connection. Replayed after reconnect. | N per connection |
| **Dart `Stream`** | In-process delivery of values already received. Listening never opens a connection. | Many |

Naming rule: *subscribe/unsubscribe* for the protocol, *listen/cancel* for Dart streams. Never mix the vocabulary.

### 5.2 `MarketDataSocket`

```dart
class MarketDataSocket {
  Stream<Quote> get quotes;                    // broadcast
  Stream<ConnectionStatus> get status;         // broadcast
  ConnectionStatus get currentStatus;

  Future<void> connect();
  void subscribe(Iterable<String> symbols);    // idempotent
  void unsubscribe(String symbol);
  void reconnectNow();                         // manual retry, resets backoff
  Future<void> dispose();
}

enum ConnectionStatus { disconnected, connecting, connected, reconnecting }
```

Responsibilities: open/close the connection, reconnect with backoff, track status, maintain `Set<String> _subscribedSymbols`, replay subscriptions after reconnect, decode incoming frames via `quote_parser`, expose quotes as a stream, survive bad messages.

It contains no UI logic, no `BuildContext`, no alert logic, no Cubit access and no Hive.

It emits `Stream<Quote>` directly rather than a `SocketEvent` union type. A union would only pay off if the protocol had several message kinds the app must react to differently — it does not, as far as we know (§21). Non-quote messages are logged and dropped.

### 5.3 Connection states and reconnect

```
 disconnected ──connect()──► connecting ──ok──► connected
      ▲                          │                  │ drop
      │ dispose()                │ fail             ▼
      └──────────────────── reconnecting ◄──────────┘
                                 │ ok
                                 └──────────────► connected
```

- `connecting` — first attempt. `reconnecting` — automatic recovery after a drop or failed attempt. The UI distinguishes them: "Connecting…" vs. "Reconnecting — showing last known prices".
- `disconnected` is reached only through explicit `dispose()`. The app never gives up on its own.
- Backoff: **1s → 2s → 4s → 8s → 16s → 30s (cap)**, a private method on the socket, reset once a connection has been stable for 10 s. No jitter and no injected `Random`: jitter matters for a server facing thousands of clients, and leaving it out keeps the reconnect tests deterministic. Noted in `NOTES.md` as a production consideration.

### 5.4 Bad messages

A single bad frame must never tear down the connection or push an error into a stream the UI listens to.

| Situation | Handling |
| --- | --- |
| Not valid JSON | Caught inside `parseQuotes`, frame skipped |
| Subscription acknowledgement (`{"p":"/subscribe/addlist","i":0}`) | Skipped **silently** — these arrive on every subscribe and logging them would be noise |
| Quote entry with missing/unparsable fields | Dropped; the other entries in the same frame are still delivered |
| Quote for a symbol we never subscribed to | Accept it; harmless |

`parseQuotes` returns a list and never throws, so the "bad message" path is ordinary control flow rather than exception handling. A frame carrying five quotes of which one is malformed yields four quotes, not zero.

### 5.5 Transport seam

```dart
abstract interface class WebSocketTransport {
  Future<void> connect(Uri uri);
  Stream<dynamic> get messages;
  void send(String data);
  Future<void> close();
}
```

This is the one abstraction in the networking layer that clearly earns its keep: without it, testing reconnect, resubscription and status transitions would need a real server. Two implementations:

- `WebSocketChannelTransport` — production, wraps `web_socket_channel`.
- `FakeTransport` — a **test-only** double that injects frames, simulates drops and records sent frames. It lives under `test/helpers/` and is written when the testing pause (§16) is lifted.

The app ships one transport. There is no fake feed and no offline demo mode: with no reachable `WS_URL` the socket simply keeps retrying under backoff, and the UI shows the reconnect banner. Generating plausible-looking prices in `lib/` would mean shipping a second, parallel source of truth that no requirement asks for.

---

## 6. Quotes: repository and state

### 6.1 `QuoteRepository`

```dart
class QuoteRepository {
  QuoteRepository(this._socket);
  Stream<Quote> get quotes => _socket.quotes;
  Stream<ConnectionStatus> get status => _socket.status;
  void subscribeAll(Iterable<String> symbols) => _socket.subscribe(symbols);
  void subscribe(String symbol) => _socket.subscribe([symbol]);
  void reconnectNow() => _socket.reconnectNow();
}
```

Deliberately thin, and deliberately without a cache — see §2 for why it exists.

### 6.2 `QuotesState` and `Map<String, Quote>`

```dart
class QuotesState {
  final Map<String, Quote> quotes;      // symbol → latest quote
  final ConnectionStatus status;
}
```

Keyed by symbol because updating on a tick is then `O(1)`. With a `List<Quote>` every tick would need an `indexWhere`; at 200 instruments and a busy feed that is thousands of wasted comparisons per second, for no benefit. Lookups from a row, the detail screen and the alert form are `O(1)` too.

The Cubit emits a new map per tick (copy-on-write) so state stays immutable and `Equatable` behaves. Copying a 200-entry map is cheap; §13 covers what to do if measurement ever says otherwise.

### 6.3 Behaviour while disconnected

| Requirement | Implementation |
| --- | --- |
| Keep showing last known Bid/Ask | The quote map is **never cleared** on disconnect |
| Don't pretend prices are current | `ConnectionBanner` driven by `status`, plus `Quote.timestamp` for "updated 12 s ago" |
| Automatic recovery | Socket reconnects and replays subscriptions; fresh quotes overwrite the map |
| Manual fallback | "Retry now" in the banner calls `reconnectNow()` |

Not done: greying out individual rows during a global outage (connection loss is a global condition, communicated once), and treating a quiet symbol as a failure (quiet markets exist; the protocol gives no per-symbol health signal).

---

## 7. Alerts: semantics, evaluator, coordinator

### 7.1 Crossing rule

```
above:  previous <  target  AND  current >= target
below:  previous >  target  AND  current <= target
```

`previous` and `current` are the **selected side** (bid or ask) of two consecutive observed quotes for that symbol. An alert fires on a transition, never because a condition happens to hold.

### 7.2 Baseline rule

**The first quote observed for a symbol establishes the baseline and can never trigger an alert.**

`AlertCoordinator` keeps `Map<String, Quote> _previous`. On a tick: if there is no previous quote for that symbol, store it and return; otherwise evaluate, then store.

This one rule covers both requirements:

- Creating an alert when the condition already holds does not fire it — the live quote the user just saw is already the baseline, so the next tick is evaluated as a transition from there.
- After a cold start, the first tick per symbol is absorbed, so alerts restored from Hive never fire on launch based on prices from hours ago.

`_previous` is intentionally not persisted.

### 7.3 Percentage alerts

At creation: `referencePrice` = current price of the **selected side**, `targetPrice = roundPrice(reference * (1 + pct/100))`, `direction` from the sign.

| Side | Bid | Ask | Pct | reference | target |
| --- | --- | --- | --- | --- | --- |
| Bid | 200 | 200.5 | +5% | 200 | 210 |
| Bid | 200 | 200.5 | −5% | 200 | 190 |
| Ask | 200 | 200.5 | +5% | 200.5 | 210.525 |

**The selected side is used for both the reference and every later evaluation.** Taking the reference from bid and evaluating on ask would shift the threshold by the spread. Enforced by routing every read through `quote.priceFor(alert.side)`.

A percentage alert cannot be created without a live price for that symbol — there would be no reference. The form disables Save and says why.

Once `targetPrice` is computed, a percentage alert evaluates exactly like an absolute one, so there is no extra branching in the hot path.

### 7.4 `AlertEvaluator` — pure

```dart
class AlertEvaluator {
  const AlertEvaluator();

  /// Pure: no I/O, no Flutter, no BuildContext, no persistence.
  List<PriceAlert> evaluate({
    required Quote previous,
    required Quote current,
    required Iterable<PriceAlert> alerts,
  });
}
```

Skips alerts for other symbols and alerts that are not `active`; applies §7.1 to the rest; returns everything that crossed (several alerts on one instrument can fire on the same tick).

Stateless by design — no previous-price map, no dedupe set. Every test is "given two quotes and some alerts, expect these results", with no setup or teardown. That is the whole reason this is a separate class.

### 7.5 `AlertCoordinator` and single-firing

Subscribes to `quoteRepository.quotes`, holds `_previous`, calls the evaluator, and for each triggered alert calls `alertsCubit.onTriggered(alert, price)`, which:

1. copies it with `status: triggered`, `triggeredAt`, `triggeredPrice`;
2. persists it through `AlertRepository` **before** the notification is shown, so a crash cannot lose the record;
3. emits state with the alert moved from active to triggered and appended to `pendingNotifications`.

**Repeat firing is prevented structurally:** a triggered alert is no longer in the active set the coordinator passes to the evaluator. `ACTIVE → TRIGGERED` is one-way; there is no re-arm. History is kept until the user deletes it.

### 7.6 Disconnection — intentional limitation

The app never guesses whether an alert should have fired while disconnected. No backfill, no gap reconstruction.

Within one session `_previous` survives the outage, so the first post-reconnect tick is compared against a genuinely observed earlier price. That is observation, not guessing: if bid went 200 → (gap) → 185 with a `below 190` alert, both endpoints were really seen and the crossing really happened. If instead the price dipped to 185 during the gap and recovered to 195, the alert does **not** fire — that miss is the accepted limitation. Reliable alerting across downtime needs server-side evaluation, which is out of scope. Documented in `NOTES.md`.

---

## 8. Persistence (Hive)

### 8.1 Storage shape

One box, `alerts`, typed as `Box<PriceAlert>` and keyed by alert id:

```dart
final box = await Hive.openBox<PriceAlert>('alerts');
await box.put(alert.id, alert);
```

Active and triggered alerts live in the same box, discriminated by the `status` field, so `ACTIVE → TRIGGERED` is a single atomic `put` rather than a delete-from-one-box/put-into-another pair that can half-fail. The repository exposes them separately, which is where the distinction actually matters.

### 8.2 Adapters without polluting the domain

Adapters are generated with `hive_ce`'s `GenerateAdapters` annotation, which — unlike classic Hive — does **not** require annotating the model classes themselves. The whole declaration lives in one file in the data layer:

```dart
// features/alerts/data/hive_adapters.dart
@GenerateAdapters([
  AdapterSpec<PriceAlert>(),
  AdapterSpec<QuoteSide>(),
  AdapterSpec<AlertDirection>(),
  AdapterSpec<AlertKind>(),
  AdapterSpec<AlertStatus>(),
])
class HiveAdapters {}
```

This gets the best of both options: real binary `TypeAdapter`s (idiomatic Hive, efficient, no hand-written serialisation), while `domain/price_alert.dart` stays free of `@HiveType`/`@HiveField` annotations and of any `hive` import. No separate persistence model and no mapper are needed, because there is nothing to translate — `double`, `String`, `DateTime` and enums are all handled natively.

Adapters are registered in `bootstrap.dart` through the generated registrar before the box is opened.

**Rules that keep stored data readable after a code change** (the real migration risk with generated adapters):

- typeIds are assigned by the **order of entries in `specs`** — never reorder or delete an entry; use the `reservedTypeIds` parameter when retiring one.
- field indexes follow the **order of fields in the class** — add new fields at the end only, and give them defaults so existing records still load.

### 8.3 Repository

```dart
class AlertRepository {
  AlertRepository(this._box);              // injected → tests use a temp-dir box
  Future<List<PriceAlert>> loadAll();
  Future<void> save(PriceAlert alert);
  Future<void> delete(String id);
}
```

One class is the whole data layer for alerts, and it is the boundary: no Cubit and no widget imports `hive`.

### 8.4 Initialisation and versioning

In `bootstrap.dart`: `Hive.initFlutter()`, register the generated adapters, open the box, hand it to `AppDependencies`. If opening throws (corruption), log it, `deleteBoxFromDisk`, reopen once, and carry on — alerts are valuable but the app must still start.

Versioning stays at the level a task this size warrants: the append-only field and typeId rules in §8.2 keep old records loadable, and new fields get defaults. No migration framework and no meta box — if a real migration is ever needed, it is a `reservedTypeIds` entry plus a new adapter.

---

## 9. State management (Cubits)

Cubits rather than Blocs: every interaction here is a direct method call ("create alert", "load instruments", "quote arrived"), with no event sourcing, replay or transformation that would justify event classes.

| Cubit | State | Owns | Does not own |
| --- | --- | --- | --- |
| `InstrumentsCubit` | `status`, `List<Instrument>`, `error?` | Loading the list; triggering `subscribeAll` once loaded | Quotes, connection, sockets |
| `QuotesCubit` | `Map<String,Quote>`, `ConnectionStatus` | Applying incoming quotes to state; `reconnectNow()` | Socket lifecycle, alert logic, persistence |
| `AlertsCubit` | `active`, `triggered`, `pendingNotifications`, `error?` | Alert CRUD, applying triggers, notification queue | Evaluating conditions (that is `AlertEvaluator`), touching Hive directly |

**Why `QuotesCubit` is separate from `InstrumentsCubit`** (the brief sketched one Cubit for both): the instrument list emits once and then stays still; quotes emit continuously. In one state object every tick would invalidate the state the list structure depends on, rebuilding the whole list. Separating them gives each Cubit one reason to change — this is the single most load-bearing state decision in the app.

No `AppCubit`, no `ConnectionCubit` (status belongs with the data it qualifies), no `AlertNotificationCubit` (the queue lives in `AlertsState`, produced by the same transition that creates it).

---

## 10. Screens and navigation

### 10.1 Screens

```
┌─────────────────────────────────────────────────────────┐
│ AlertNotificationHost                (above everything) │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ AppShell — StatefulShellRoute.indexedStack          │ │
│ │  /quotes          /alerts         /history          │ │
│ │  live list        active          triggered         │ │
│ │   └ /quotes/:symbol                                 │ │
│ │  [ Quotes ]       [ Alerts ]      [ History ]       │ │
│ └─────────────────────────────────────────────────────┘ │
│  /alerts/create — full screen above the shell           │
└─────────────────────────────────────────────────────────┘
```

| # | Screen | Route | Nav bar | State source |
| --- | --- | --- | --- | --- |
| 1 | Live quotes | `/quotes` (tab 0, initial) | yes | `InstrumentsCubit` + `QuotesCubit` |
| 2 | Instrument details | `/quotes/:symbol` | yes (stays in tab 0) | `QuotesCubit` + `AlertsCubit` |
| 3 | Active alerts | `/alerts` (tab 1) | yes | `AlertsState.active` |
| 4 | Create alert | `/alerts/create?symbol=` | no (covers it) | `AlertsCubit` + `QuotesCubit` |
| 5 | Alert history | `/history` (tab 2) | yes | `AlertsState.triggered` |

**Live quotes** — every instrument, each row showing symbol, Bid, Ask, and `—` before the first quote (not a spinner per row). `ListView.builder`, `ValueKey(symbol)`, `ConnectionBanner` pinned above. All instruments are subscribed once the list loads, because this screen shows live Bid/Ask for all of them — one batched subscribe over the one connection.

**Instrument details** — symbol, contract type, Bid, Ask, last-updated, status, this instrument's alerts, and a Create alert action that navigates to `/alerts/create?symbol=…`. Reads the existing `QuotesCubit`; creates no connection. Calls the idempotent `subscribe(symbol)` and does **not** unsubscribe on dispose, since the list behind it still needs that symbol. Pushed inside branch 0 so the nav bar stays visible.

**Active alerts** — `AlertsState.active` with delete; tapping a row opens that instrument; a create action opens the form with no symbol pre-selected.

**Create alert** — one screen serving both entry points. Fields: instrument (picker, locked when arriving from details), side, kind, direction, value. Shows the current live price of the selected side and, for percentage, a live preview of the computed target. Save is disabled for percentage alerts with no live price. Pushed on the root navigator (`parentNavigatorKey`), so it covers the nav bar: a validated multi-field form is a committed task, and the user should not wander into another tab mid-form.

**Alert history** — `AlertsState.triggered`, newest first, showing the target, the price that actually triggered it and `triggeredAt`. Delete removes permanently; nothing re-arms.

### 10.2 Routing

`go_router` with `StatefulShellRoute.indexedStack` in `app/router.dart`:

```dart
StatefulShellRoute.indexedStack(
  builder: (context, state, shell) => AppShell(shell: shell),
  branches: [ /* /quotes + /quotes/:symbol */, /* /alerts */, /* /history */ ],
),
GoRoute(path: '/alerts/create', parentNavigatorKey: rootNavigatorKey, ...),
```

`indexedStack` is used for one concrete reason: each tab keeps its own navigator, so scroll position in the quotes list and a pushed details screen survive tab switches. Doing that with a plain `BottomNavigationBar` means hand-managing navigator keys.

Routing knows nothing about the WebSocket — switching tabs never connects, subscribes or unsubscribes. Paths live in constants; no custom navigation abstraction on top of go_router.

### 10.3 Global alert notification

`AlertNotificationHost` goes in `MaterialApp.router`'s `builder`, i.e. above both navigators:

```dart
MaterialApp.router(
  routerConfig: router,
  theme: AppTheme.light,
  builder: (context, child) => AlertNotificationHost(child: child!),
);
```

A `BlocListener<AlertsCubit, AlertsState>` on `pendingNotifications` renders a banner over the routed content and calls `acknowledge(id)`. Because it sits above the shell, the notification appears on any tab, on details, and while the create form is open — and no page needs to know alerts exist. Several alerts firing at once are shown one after another, not stacked.

Visuals stay minimal (symbol, side, direction, target, triggered price, auto-dismiss, tap to open History). Phase 11 restyles it.

---

## 11. Design system

Placeholder styling now, but every visual value goes through a token layer so the Figma design can later be applied by editing `core/theme/` and a few widgets.

| File | Contents |
| --- | --- |
| `app_colors.dart` | Palette + semantic aliases (`priceUp`, `priceDown`, `statusWarning`) |
| `app_typography.dart` | Font family, weights, sizes |
| `app_text_styles.dart` | Named styles (`priceCell`, `symbolLabel`, `caption`) |
| `app_spacing.dart` | Small scale (`xs/sm/md/lg`) + radii |
| `app_theme.dart` | `ThemeData` assembly |

Rules: no hardcoded colours, text styles or repeated paddings inside feature widgets; a handful of reusable presentational widgets (`PriceText`, `ConnectionBanner`, `AlertTile`) carry the tokens. Do **not** pre-create tokens — add one when a second usage appears. The design system is a thin foundation, not a project of its own.

Separation to maintain: business logic in `domain/`, state in Cubits, data access in `data/` and `core/network/`, UI in pages/widgets, tokens in `core/theme/`. Phase 11 should touch only the last two.

---

## 12. Error handling

One exception type and one logging function, in `core/errors.dart`:

```dart
class AppException implements Exception {
  final String message;      // safe to show to the user
  final Object? cause;
}

void logError(Object error, [StackTrace? stackTrace, String? context]);
```

A hierarchy of network/storage/validation subclasses is not created, because nothing in the app branches on the exception *type* — the handling differs by *where* the failure happens, and that is already known at the catch site. Repositories translate low-level exceptions (`HiveError`, `FormatException`, socket errors) into `AppException` with a readable message; Cubits catch it and put a failure into state.

| Failure | Behaviour |
| --- | --- |
| Socket cannot connect / drops | Status → `reconnecting`, banner, backoff retry, last known prices kept. Never a blocking dialog |
| Malformed message | Logged and skipped; connection stays up; not surfaced to the user |
| `instruments.json` missing/invalid | `InstrumentsCubit` failure state with a Retry button — nothing works without it, so this one blocks |
| Empty instrument list | Empty state, not an error; no subscribe call |
| Hive open failure | Log, delete + recreate the box once, continue with an in-memory list and a warning |
| Hive write failure | Keep the in-memory change, show "could not save"; never crash |
| Invalid alert input | Handled by form validation; the named constructors assert invariants as a backstop |

Cross-cutting: no empty `catch {}` anywhere — every catch logs, translates, or both. `runZonedGuarded` + `FlutterError.onError` in `bootstrap.dart` route uncaught errors to `logError`. That is the entire error framework.

---

## 13. Performance

Done from the start, because they are free and structural:

- one WebSocket, N logical subscriptions;
- `Map<String, Quote>` for O(1) updates and lookups;
- `ListView.builder` with `ValueKey(symbol)` and `const` leaf widgets;
- `BlocSelector<QuotesCubit, QuotesState, Quote?>` per row, so only rows whose quote changed rebuild — the list itself is driven by `InstrumentsCubit` and does not rebuild on ticks;
- no parsing, sorting or formatting inside `build()`;
- quote handling entirely outside widgets.

**Not done up front:** throttling/coalescing of quote updates. It is an optimisation, not architecture, and adding a custom stream buffering helper before knowing the real tick rate would be solving an imaginary problem. Phase 10 includes a short verification pass driving `MarketDataSocket` from a fast test double and watching DevTools' rebuild counter; **if** it shows a problem, the fix is small and local — buffer in `QuotesCubit` and emit on a timer — and gets documented in `NOTES.md` with the measurement that justified it.

Also not done without evidence: isolates (frames are tiny; `compute` overhead would likely exceed the gain), immutable-collection packages, custom render objects.

---

## 14. App lifecycle

`AppLifecycleListener` in `App`, delegating to the socket:

| Event | Behaviour |
| --- | --- |
| Launch | `bootstrap()` opens Hive, builds dependencies, connects, loads instruments, subscribes to all |
| Background | Leave the connection alone; the OS suspends it anyway. Short backgrounding should not cost a reconnect |
| Resume | `reconnectNow()` if the socket is not connected; subscriptions replay automatically. Displayed prices stay last-known until fresh ticks arrive |
| Terminate | `dispose()`: cancel timers and subscriptions, close the sink and controllers, close the box |

That is the whole lifecycle story. No background execution, no connectivity plugin (the backoff loop already recovers; a connectivity signal would only call `reconnectNow()` sooner), no battery-saving disconnect timer.

---

## 15. Configuration

No credentials, tokens or endpoints in source. Everything through `--dart-define`, read in one place:

```dart
class AppConfig {
  static const wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'wss://webquotes.geeksoft.pl/websocket/quotes',
  );
  static const instrumentsAsset = 'assets/instruments.json';
}
```

The default is the endpoint given in the task — a public, unauthenticated address, not a secret — so `flutter run` works with no arguments. Pointing the app somewhere else is a launch-argument change and nothing else. An empty or unreachable `WS_URL` is not a special mode: the socket attempts it, fails, and retries under backoff while the banner says so. If auth turns out to be required (§21), the token arrives the same way and is never logged or persisted.

---

## 16. Testing strategy

> **Paused as of Phase 4.** No new tests are written until the developer says otherwise. The per-phase test lists below stay as the intended target set, but each phase is delivered without them and notes the gap. `test/` was deleted in Phase 5, once the Phase 3 tests stopped compiling against changed constructors — the whole suite is written in one pass when the pause is lifted. See `.cursor/rules/project-conventions.mdc`.

Priority: domain logic first, then socket behaviour, then Cubits, then a few widget tests for real user flows. Tools: `flutter_test`, `bloc_test`, `mocktail`, `fake_async`. No coverage target — tests exist to prove behaviour, not to move a number, and they assert on behaviour rather than on implementation details.

**Tests are written with the feature, never ahead of it.** Each phase adds tests for the behaviour that phase introduces, so every test has a real implementation to assert against. Do not write widget tests for screens that do not exist yet — a test against a placeholder only has to be rewritten later, and it hides which behaviour is genuinely covered.

`test/widget_test.dart` currently holds a **temporary bootstrap smoke test** asserting that `App` builds and renders the placeholder screen. It exists only so the suite is not empty during early phases. It is replaced or deleted in Phase 12, once the real screens and their tests exist.

**`AlertEvaluator`** (pure, no mocks — the highest-value tests in the project)

- absolute above: `249 → 251` with target 250 triggers; `251 → 252` does not;
- absolute below: `251 → 249` with target 250 triggers;
- boundary: `249 → 250.0` triggers (`>=`); `250 → 251` does not;
- bid-side alert ignores ask-only movement, and vice versa;
- percentage +5% (ref 200 → target 210) and −5% (→ 190) trigger on crossing;
- percentage on **ask** uses the ask for reference and evaluation (guards against side mixing);
- `roundPrice` makes `200 * 1.05` exactly `210.0`;
- several alerts on one instrument can fire on the same tick;
- a quote for an unrelated symbol triggers nothing;
- already-triggered alerts are skipped.

**`AlertCoordinator`**

- the first quote for a symbol sets the baseline and triggers nothing (covers both "condition already true at creation" and cold start);
- the second quote is evaluated against the first;
- a trigger produces exactly one Cubit call and one persisted write.

**`MarketDataSocket`** (with `FakeTransport` + `fake_async`)

- `disconnected → connecting → connected`;
- `connected → reconnecting → connected` after a drop;
- backoff delays follow 1/2/4/8/16/30 and reset after a stable period;
- **resubscription**: subscribe A+B, drop, reconnect → the resubscribe frame contains exactly A and B;
- `subscribe` is idempotent;
- valid frame parses into a `Quote`; malformed JSON is skipped and the stream stays open;
- `dispose()` closes the transport and stops emitting.

**Cubits** (`bloc_test`)

- `InstrumentsCubit`: load success, failure, empty; `subscribeAll` called with every symbol on success and not otherwise;
- `QuotesCubit`: applies an incoming quote; reacts to status changes; keeps the map while `reconnecting`;
- `AlertsCubit`: create absolute; create percentage (reference and target correct); reject percentage with no live price; delete; apply a trigger (moves active → triggered, enqueues notification); `acknowledge` dequeues.

**`AlertRepository`** (real Hive box in a temp directory, no mocks)

- save and load round-trip through the generated adapter, including enums and UTC dates;
- status update persists `triggeredAt` and `triggeredPrice`;
- delete removes; data survives close/reopen.

**Widget tests** — the target set, each added in the phase that builds the screen it covers (a handful, covering flows a reviewer would click through)

- quotes list renders rows, and updating one symbol updates only that row;
- connection banner appears while `reconnecting`;
- details screen shows the quote and navigates to the create form with the symbol pre-filled;
- creating an alert calls `AlertsCubit` with the expected arguments;
- all three tabs are reachable and the Quotes tab keeps its scroll position across a switch;
- a triggered alert shows its banner while a non-default tab is active (this one protects §10.3).

---

## 17. Dependencies

**Runtime:** `flutter_bloc`, `equatable`, `web_socket_channel`, `hive_ce`, `hive_ce_flutter`, `go_router`, `uuid`, `intl`.

**Dev:** `flutter_test`, `bloc_test`, `mocktail`, `fake_async`, `build_runner`, `hive_ce_generator`, `flutter_lints`.

`hive_ce` is the maintained community continuation of Hive 2 (original `hive` is unmaintained, the Isar-based Hive 4 line was abandoned). Same API, plus the `GenerateAdapters` annotation that §8.2 relies on. A dependency-hygiene choice, worth mentioning in `NOTES.md`.

**Removed after the phase-1 review:** `decimal` — §4.1 uses `double`.

**Not used:** `get_it`/`injectable` (an explicit composition root keeps the dependency graph visible in one file), `rxdart` (plain `Stream` covers everything, and coalescing is not being built — §13), `freezed` (`Equatable` plus hand-written `copyWith` for a handful of models beats a codegen loop), `connectivity_plus`, `dio`.

---

## 18. Implementation phases

Twelve phases. Each has one goal, leaves the app runnable, and can be reviewed on its own. Workflow per phase: implement → manual review → refactor → `flutter analyze` → next. The **Tests** line in each phase below is on hold (§16) and is skipped until the developer lifts the pause.

---

### Phase 1 — Project setup ✅ DONE

Dependencies, extra lints, `assets/instruments.json` registered, counter demo removed, `bootstrap()` with `runZonedGuarded` + `FlutterError.onError`, placeholder `App`, a **temporary** bootstrap smoke test (§16). `flutter analyze` clean, `flutter test` green.

**Follow-up from this review:** `decimal` removed from `pubspec.yaml` (§4.1 uses `double`). ✅

---

### Phase 2 — Core foundation: theme, config, errors, routing ✅ DONE

- **Goal:** the skeleton every later phase plugs into.
- **Files:** `core/theme/*`, `core/app_config.dart`, `core/errors.dart`, `app/router.dart`, `app/widgets/app_shell.dart`, `app/widgets/placeholder_page.dart`, `app/app.dart`.
- **Tasks:** design tokens with placeholder values; `AppException` + `logError` (and point `bootstrap`'s handlers at it); `AppConfig`; `go_router` with `StatefulShellRoute.indexedStack`, `AppShell` with the three-tab `NavigationBar`, and a single reusable `PlaceholderPage` behind all five routes.
- **Deviation:** `AppDependencies` moved to Phase 3. Nothing to compose yet — an empty class now would be an abstraction without a current reason (§23.2). It is created together with the first real dependency, `InstrumentRepository`.
- **Result:** themed app, working bottom navigation, all five routes reachable.
- **Tests:** none new — the screens are still placeholders, so navigation is verified by hand here. The tab-switching and state-preservation widget test lands in Phase 9, once all three tabs show real content.
- **Pitfalls:** inventing tokens nobody uses yet; logic creeping into theme files; forgetting `parentNavigatorKey` on `/alerts/create`, which would leave the nav bar visible over the form.

---

### Phase 3 — Instruments: model, repository, list screen ✅ DONE

- **Goal:** the Quotes tab renders the real instrument list (no live prices yet).
- **Files:** `features/instruments/**`, `app/app_dependencies.dart`, `app/router.dart`.
- **Tasks:** `Instrument`; `InstrumentRepository` reading and decoding the asset (throws `AppException` on malformed JSON, caches the parsed list); `AppDependencies` (created here, holding its first real dependency) and the provider wiring in `App`; `InstrumentsCubit` + state (loading/success/failure/empty); `InstrumentsPage` with `ListView.builder`, `ValueKey(symbol)`, and `—` placeholders for Bid/Ask; `InstrumentTile`; swap the `/quotes` placeholder for the real page.
- **Result:** a scrollable real list with empty/error/retry states.
- **Tests:** parsing valid JSON; unknown `contractType` preserved, not dropped; malformed JSON → `AppException`; empty array → empty list; Cubit load success/failure/empty.
- **Pitfalls:** inventing meanings for `contractType`; forgetting `TestWidgetsFlutterBinding` when a test touches `rootBundle`.
- **Deviations:** JSON decoding sits in the data layer (a private function in `InstrumentRepository`), not as a `fromJson` on the model, so the domain type stays free of protocol concerns — no DTO or mapper was added for it. Tests inject a mocked `AssetBundle` (`test/helpers/mock_asset_bundle.dart`) instead of reaching for `rootBundle`, which also makes the cache assertion possible via `verify`. The bootstrap smoke test now builds `App` with that mocked bundle, since `App` requires `AppDependencies` from this phase on. A wrong field type (`"contractType": "zero"`) is covered alongside malformed JSON, as both surface as `AppException`.

---

### Phase 4 — WebSocket: connection, subscriptions, reconnect ✅ DONE

- **Goal:** one robust app-wide socket. **The most important technical phase.**
- **Files:** `core/network/websocket_transport.dart`, `market_data_socket.dart`, `quote_parser.dart`, `features/quotes/domain/quote.dart`.
- **Tasks:** `Quote` + `QuoteSide` + `priceFor`; `parseQuotes` returning `List<Quote>`; `WebSocketTransport` plus its one production implementation; `MarketDataSocket` with connect/subscribe/unsubscribe/reconnectNow/dispose, `_subscribedSymbols`, status stream, private backoff, subscription replay after reconnect, per-message `try/catch`; buffer subscribe calls made while disconnected and flush them on connect.
- **Result:** a socket testable without a server, with observable state transitions.
- **Tests:** the `MarketDataSocket` list in §16.
- **Pitfalls:** overlapping reconnect timers (one `Timer?` plus an `_isDisposed` flag); not cancelling the previous transport subscription before reconnecting (duplicate handlers — the classic bug); resubscribing before the connection reports open; `addError` on a stream the UI listens to; a non-broadcast controller that only allows one listener.
- **Note:** frame formats live only in `_buildSubscriptionFrame` and `parseQuotes`, which is what made swapping the guessed protocol for the real one (§5.0) a two-function change.
- **Deviations:** subscribe and unsubscribe share one `_buildSubscriptionFrame(type, symbols)` instead of two near-identical builders; §21 updated. An `_isOpening` guard rejects a second connection attempt while one is in flight — without it, `reconnectNow()` during a pending `connect()` would leave two live transports. `_teardownConnection()` cancels the message subscription *before* closing the transport, so a planned teardown does not fire `onDone` and trigger a spurious reconnect. Backoff uses the failure count, which is reset both by `reconnectNow()` and by a connection that stays up for 10 s.
- **Simplification after review:** the parser takes `Object?` and accepts only `String` frames and JSON numbers; the pre-decoded-`Map` branch had no caller.
- **No fake feed:** a `FakeTransport` generating a random walk was written here and removed during Phase 5 — the app ships one transport and an unreachable endpoint is just a failed connection (§5.5, §15). The test double returns under `test/helpers/` when the testing pause is lifted.
- **Protocol rewritten in Phase 5:** the guessed `{"type":"subscribe","symbols":[…]}` / one-quote-per-frame shape was replaced by the real protocol once the endpoint was known (§5.0). `parseQuote` became `parseQuotes` returning a list, and `Quote.receivedAt` became `Quote.timestamp` carrying server time.
- **Verified against the live endpoint:** connect, subscribe, quote parsing and `dispose()` were exercised by driving `MarketDataSocket` directly (no UI). The reconnect and backoff paths are still unverified — they need a forced drop, which is what the test double will provide.

---

### Phase 5 — Live quotes end to end ✅ DONE

- **Goal:** real-time Bid/Ask on the first screen.
- **Files:** `features/quotes/data/quote_repository.dart`, `presentation/*`, `app/app_dependencies.dart`, `bootstrap.dart`, plus `InstrumentTile`.
- **Tasks:** `QuoteRepository`; `QuotesCubit` + `QuotesState`; connect the socket in bootstrap; call `subscribeAll` when the instrument list loads; `PriceText`; `BlocSelector` per row; `ConnectionBanner` with "Retry now".
- **Result:** the Quotes tab updates live; disconnecting shows the banner while keeping last known prices.
- **Tests:** `parseQuotes` valid/invalid/partial frame/acknowledgement; `QuotesCubit` applies quotes, reacts to status, keeps the map while reconnecting; widget test that updating one symbol rebuilds only that row.
- **Pitfalls:** `BlocBuilder` over the whole `QuotesState` in the page (rebuilds everything); clearing the map on disconnect; calling `subscribeAll` on every rebuild instead of once; formatting inside `build`.
- **Deviations:** `AppDependencies` builds `QuoteRepository` itself from the socket it is given, so no caller can wire a repository to a different socket than the one it disposes. `QuotesCubit` seeds its initial status from `QuoteRepository.currentStatus`, because `bootstrap()` connects before the widget tree exists and the status stream would otherwise not replay. `InstrumentsPage` splits into the page (banner + list) and a private `_InstrumentsList`, so the banner is not rebuilt by instrument-list states. The `NumberFormat` instances in `price_text.dart` are top-level finals rather than created per `build`; precision switches at a price of 10 and carries the §21.11 TODO.
- **`test/` removed here.** The Phase 3 tests stopped compiling once `InstrumentsCubit` took a second argument and `AppDependencies` required `marketDataSocket`. Rather than carry a broken suite through the testing pause (§16), the directory was deleted; the full set is written in one go when the pause is lifted. `flutter analyze` is clean again.

---

### Phase 6 — Instrument details ✅ DONE

- **Goal:** a detail screen consuming existing app-level state.
- **Files:** `features/instruments/presentation/instrument_details_page.dart`, route wiring.
- **Tasks:** `/quotes/:symbol` inside branch 0; read instrument + quote via `BlocSelector`; show Bid, Ask, last-updated, status; idempotent `subscribe(symbol)`, no unsubscribe on dispose, no socket creation; a Create alert button (target screen arrives in Phase 9).
- **Result:** a live detail view with the nav bar still visible.
- **Tests:** renders the quote; `FakeTransport.connectCount` stays 1 after navigating; unknown symbol shows a not-found state.
- **Pitfalls:** a screen-scoped quote source; unsubscribing on dispose and starving the list; declaring the route outside the branch.
- **Deviations:** `subscribe(symbol)` was added to `QuotesCubit` rather than letting the page reach for `QuoteRepository` directly, keeping the rule that screens talk only to cubits. The instrument lookup uses `BlocBuilder` over `InstrumentsCubit` (the list emits once, so there is nothing to optimise) while prices sit behind a `BlocSelector` keyed on the symbol. An unknown symbol is distinguished from a still-loading list by checking `InstrumentsStatus.success`, so a deep link resolves correctly either way. New token `AppTextStyles.priceHeadline`; `PriceText` gained an optional `style`.
- **Follow-up from review:** the detail screen used to spin forever when the instrument list failed to load — it now shows the error with a Retry button, same as the list. The message-with-optional-retry widget moved to `app/widgets/message_view.dart` on its second use. The `subscribe(symbol)` call in `initState` stays: `MarketDataSocket.subscribe` skips symbols already in `_subscribedSymbols`, so it sends a frame only when the symbol is genuinely missing.
- **Known limitation:** "Updated 12 s ago" is computed during `build`, so it only refreshes when a new quote arrives. While disconnected the label freezes at the last tick — acceptable because the banner already states the connection is down, and a per-second `Timer` purely to age a label is not worth the rebuild.

---

### Phase 7 — Alert domain logic ✅ DONE

- **Goal:** complete, fully tested alert logic — no UI, no persistence.
- **Files:** `features/alerts/domain/price_alert.dart`, `alert_evaluator.dart`, `app/alert_coordinator.dart`.
- **Tasks:** enums; `PriceAlert` with `copyWith` and the two named constructors carrying the validation and `roundPrice`; `AlertEvaluator.evaluate`; `AlertCoordinator` with `_previous` and the baseline rule (wired to a temporary in-memory sink until Phase 8).
- **Result:** alert logic proven by tests before any UI exists.
- **Tests:** the `AlertEvaluator` and `AlertCoordinator` lists in §16.
- **Pitfalls:** putting `_previous` inside the evaluator (destroys statelessness and testability); `>`/`<` instead of `>=`/`<=` on the current side; bid for reference and ask for evaluation; forgetting to filter by symbol or to skip already-triggered alerts; forgetting `roundPrice` on percentage targets.
- **Deviations:** instead of a general `copyWith`, `PriceAlert` exposes `markTriggered(price:, at:)`. `ACTIVE → TRIGGERED` is the only transition an alert has — there is no editing (§20) — so a setter-shaped `copyWith` would advertise mutations the domain forbids. `DateTime`s are stored in UTC at construction, closing the §8 local-time pitfall in the model rather than in the Hive layer. The two factories throw `ArgumentError`, not `AppException`: reaching them with a zero target or a zero percentage is a programming error, while user input is rejected by the form in Phase 9.
- **Coordinator wiring deferred:** `AlertCoordinator` takes an `activeAlerts` callback and an `onTriggered` callback rather than an `AlertsCubit`, so it stays free of the presentation layer and is constructed in Phase 8 with `() => alertsCubit.state.activeAlerts` and `alertsCubit.onTriggered`. The temporary in-memory sink this phase originally planned was skipped — it would have been code written to be deleted one phase later. Each `onTriggered` call is wrapped in `try/catch` + `logError`, so one failing persist cannot abort the remaining alerts that crossed on the same tick.
- **Verified without tests:** the testing pause holds, so the rules were exercised once through a throwaway script (since deleted) covering crossing up, exact-touch equality, no refire when already past the target, symbol filtering, side filtering, skipping triggered alerts, two alerts firing on one tick, the percentage target and direction for both signs, ask-side reference, and both validation throws. All passed.
- **Plan correction found while verifying:** §4.1 justified `roundPrice` with `200 * 1.05 = 210.00000000000003`, which is false — that product is exact in IEEE-754. The rounding is still necessary; §4.1 now cites `100 * (1 + 10 / 100) = 110.00000000000001` and records how the real cases were found.

---

### Phase 8 — Hive persistence and `AlertsCubit`

- **Goal:** alerts survive restarts, and the coordinator writes through a real repository.
- **Files:** `features/alerts/data/hive_adapters.dart` (+ generated), `alert_repository.dart`, `presentation/alerts_cubit.dart`, `alerts_state.dart`, `bootstrap.dart`.
- **Tasks:** `GenerateAdapters` spec and `dart run build_runner build`; Hive init, adapter registration and box opening with corruption recovery; `AlertRepository` (load/save/delete, `AppException` translation); `AlertsCubit` loading at startup, with create/delete/`onTriggered`/`acknowledge`; connect the coordinator to the Cubit.
- **Result:** creating an alert and restarting the app retains it; triggers persist.
- **Tests:** the `AlertRepository` and `AlertsCubit` lists in §16.
- **Pitfalls:** any `hive` import in `domain/`, a Cubit or a widget; registering adapters after opening the box; reordering `specs` entries or class fields later (§8.2); local-time `DateTime`s; showing a notification before persisting; a triggered alert still appearing in the active list.

---

### Phase 9 — Alert screens and global notification

- **Goal:** the full alert loop, visible from anywhere.
- **Files:** `features/alerts/presentation/*`, `app/widgets/alert_notification_host.dart`, `app/app.dart`.
- **Tasks:** `AlertsPage` (tab 1), `AlertHistoryPage` (tab 2), `CreateAlertPage` at `/alerts/create` with optional `symbol`, instrument picker, live target preview, percentage disabled without a live price; `AlertTile` shared by both lists; `AlertNotificationHost` in the router's `builder`, driven by `pendingNotifications`.
- **Result:** create → wait → trigger → banner → history works end to end against a live feed.
- **Tests:** the alert-related widget tests in §16, the cross-tab notification test, and — now that every tab has real content — the tab-reachability and scroll-preservation test deferred from Phase 2.
- **Pitfalls:** putting the listener inside a page (breaks the global requirement); re-showing a notification after a rebuild (the queue must be acknowledged); losing the pre-selected symbol when arriving from details.

---

### Phase 10 — Edge cases, error paths, performance check

- **Goal:** the app behaves under hostile conditions, and real-time updates are confirmed smooth.
- **Tasks:** audit every `catch` for silent swallowing; feed garbage frames end to end; exercise Hive failure paths; empty and failed instrument load; verify "Retry now" resets backoff without spawning duplicate loops; `AppLifecycleListener` (§14); then a **short** performance pass — a test double emitting at a high rate, DevTools rebuild counter and frame chart in profile mode, confirm the list does not rebuild wholesale and repeated navigation/reconnects do not grow subscription counts. Add throttling only if the measurement demands it, and record the numbers in `NOTES.md`.
- **Result:** no crashes under connection loss, bad data or storage failure; documented performance evidence.
- **Tests:** garbage-frame test; repeated drop/reconnect cycles do not duplicate listeners; storage-failure Cubit test.
- **Pitfalls:** profiling in debug mode; reconnect storms from overlapping timers; error state that never clears after recovery; optimising without a measurement.

---

### Phase 11 — Final UI pass (Figma)

- **Goal:** apply the real design by changing the design layer and presentational widgets only.
- **Files:** `core/theme/**` and widgets. **No** changes to `domain/`, `data/` or Cubit logic — the diff proving that is the point.
- **Tasks:** real colours, typography, spacing; restyle `PriceText`, tiles, banner, notification, form; price-direction flash if the design calls for it.
- **Tests:** update only the widget tests that asserted placeholder structure.
- **Pitfalls:** business logic sneaking into styled widgets; hardcoded colours instead of tokens; animations that rebuild the whole list on every tick.

---

### Phase 12 — Cleanup and NOTES

> `README.md` is written by the developer, not generated. No phase edits it.


- **Goal:** a repository a reviewer can understand in ten minutes.
- **Tasks:**
  1. Hand over the facts the developer needs for `README.md`: the exact run and test commands (including every `--dart-define`), the current project structure, and which defaults apply when `WS_URL` is unset.
  2. `NOTES.md`: architecture summary, key decisions and their rationale (§19), known limitations (§7.6, §14, §21), **how AI assistance was used** — which parts were AI-generated, how they were reviewed and what was changed by hand — and what would come next with more time.
  3. **Retire the temporary bootstrap smoke test** in `test/widget_test.dart` — delete it if the real screen tests already cover app startup, or rewrite it against the actual initial screen. Then review the widget-test set in §16 against the task requirements and fill any remaining gap.
  4. `flutter analyze` clean, `dart format .`, remove dead code, TODOs and debug prints.
  5. Re-verify §24.
- **Pitfalls:** committing env files; handing over run instructions that omit a required `--dart-define`.

---

## 19. Decision log

| # | Decision | Why |
| --- | --- | --- |
| 1 | Cubit, not Bloc | Every interaction is a direct method call; no event sourcing or transformation to justify event classes |
| 2 | One global WebSocket | Connections are expensive and rate-limited; the list needs all symbols; alerts must keep evaluating across navigation |
| 3 | Many logical subscriptions over one socket | How market-data protocols work. Subscriptions are protocol state (a `Set<String>`), distinct from Dart stream listeners |
| 4 | Subscribe to all instruments at startup | The first screen shows live Bid/Ask for every instrument, so all are needed immediately; one batched call avoids scroll-driven flicker |
| 5 | Exponential backoff 1→2→4→8→16→30 s, no jitter | Recovers without user action; leaving jitter out keeps tests deterministic and matters little for a single client. Noted as a production consideration |
| 6 | Automatic resubscription after reconnect | A new connection has no server-side subscription state; the socket owns the symbol set, so no other layer needs reconnect awareness |
| 7 | Keep last known prices while disconnected | Stale-but-labelled beats blank. The map is never cleared; the banner makes staleness explicit |
| 8 | Never guess alert triggers during a disconnect | The client cannot know what the market did. Evaluation resumes on observed quotes only |
| 9 | Crossing-based triggering | Users care about events, not about a condition that was already true when they set the alert |
| 10 | First observed quote is a baseline and never fires | One rule prevents both instant firing at creation and an alert storm on cold start |
| 11 | Reference price from the selected side, target precomputed | "+5%" needs an anchor; taking it from the selected side keeps the threshold honest, and precomputing keeps evaluation to one comparison |
| 12 | `double` with a rounded percentage target, not `Decimal` | The app compares and displays prices, it does not accumulate money. The one real float hazard is the percentage target, fixed by rounding once at creation. Scaled integers or `decimal` would be right if P&L were ever computed (§4.1) |
| 13 | Generated Hive `TypeAdapter`s via `GenerateAdapters`, declared in the data layer | Idiomatic, efficient binary storage with no hand-written serialisation — and because `hive_ce` generates from a spec list rather than from annotations on the classes, the domain model stays free of Hive imports without needing a separate persistence model plus mapper |
| 14 | One box for active + triggered, discriminated by `status` | Makes `ACTIVE → TRIGGERED` a single atomic write instead of a cross-box move that can half-fail |
| 15 | One concrete repository per feature — no interface + impl + data source | There is exactly one implementation and `mocktail` mocks concrete classes, so the extra layers add indirection and no testability |
| 16 | Separate `QuotesCubit` from `InstrumentsCubit` | Static list data and high-frequency quote data change at completely different rates; combining them rebuilds the list on every tick |
| 17 | Pure, stateless `AlertEvaluator` with a separate coordinator | Keeps the rules testable as plain input→output, while the mutable previous-quote state lives in exactly one place that needs it |
| 18 | Global alert host above the Navigator | `MaterialApp.router`'s `builder` makes notifications route-independent, so no page needs alert awareness |
| 19 | `StatefulShellRoute.indexedStack` for the three tabs | Each tab keeps its own navigator and state; hand-rolling that means managing navigator keys manually |
| 20 | Create alert as a full screen, not a bottom sheet | A validated multi-field form with an instrument picker deserves full height and an explicit Cancel/Save, with no nav bar to wander into |
| 21 | No coalescing/throttling until measured | It is an optimisation, not architecture; building a buffering helper before knowing the tick rate solves an imaginary problem (§13) |
| 22 | One `AppException` + one `logError`, no hierarchy | Nothing in the app branches on exception type; handling differs by catch site, which is already known there |
| 23 | Explicit composition root instead of a DI framework | The dependency graph stays visible in one readable file |

---

## 20. What we intentionally do not build

| Not built | Why |
| --- | --- |
| `UseCase`/`Interactor` per repository method | Cubits calling repositories directly is readable; wrapper classes would multiply files with no behaviour change |
| Repository interfaces with a single implementation | Indirection without testability gain; `mocktail` mocks concrete classes |
| Separate DTO + mapper layers | `InstrumentRepository` and `parseQuotes` produce domain objects directly; a mapper would just forward fields |
| A `SocketEvent` union type | Only quotes matter; other messages are logged and dropped |
| Custom stream coalescing helper | Optimisation without evidence (§13) |
| Exception hierarchy, logging framework | Nothing branches on error type |
| DI framework (`get_it`, `injectable`) | A composition root is clearer at this size |
| `rxdart`, `freezed` | Plain `Stream` and `Equatable` + `copyWith` are enough |
| Separate Hive persistence model + mapper | `GenerateAdapters` keeps the domain model annotation-free, so there is nothing to translate |
| Migration framework | Append-only fields and reserved typeIds cover a handful of small objects |
| Event bus | Dart `Stream`s already are the event system |
| One WebSocket per instrument | Explicitly wrong for this protocol shape |
| Isolates for JSON | Frames are tiny; overhead would likely exceed the gain |
| Offline quote cache, historical storage | Not required; last-known in-memory values suffice |
| Connectivity plugin, background execution | Backoff already recovers; the task needs no updates while suspended |
| i18n, search, sorting, watchlists, charts | Not in the task; easy to add on top of this structure |
| Pixel-perfect UI before the architecture works | Phase 11 exists for the real design |

The line throughout: invest in correctness and separation where the task is judged — real-time handling, alert semantics, testability — and keep everything else boring.

---

## 21. Assumptions and open questions

Nothing here is invented as fact. Each is isolated so that confirming it changes one small function.

**Items 1–6 are resolved.** The protocol is documented in §5.0 and was confirmed against the live endpoint in Phase 5: paths `/subscribe/addlist`, `/subscribe/removelist` and `/quotes/subscribed`, one frame carrying a list of `{s, b, a, t}` entries, batching supported, prices as JSON numbers, and `t` as Unix seconds — so `Quote.timestamp` now holds the **server** time rather than a local one. A partial frame is normal and needs no merging, because each entry carries both sides.

| # | Question | Working assumption | Isolated in |
| --- | --- | --- | --- |
| 7 | Authentication | Not required — the endpoint accepts anonymous connections. A token would arrive via `--dart-define` and never be logged | `AppConfig`, `MarketDataSocket.connect` |
| 8 | Heartbeat / ping-pong | None observed over a live session. If required, add a periodic ping and a pong timeout forcing reconnect — **TODO** | `MarketDataSocket` |
| 9 | Instrument source | Assumed a bundled asset. An HTTP endpoint would replace the body of `InstrumentRepository` only | `InstrumentRepository` |
| 10 | `contractType` code meanings | Unknown; the raw int is preserved and shown as-is | `Instrument` |
| 11 | Decimal places per instrument | Not provided by the feed. `PriceText` formats everything with two decimals — a deliberate simplification. Low-priced instruments lose precision on screen (`ADAUSD 0.2234` renders as `0.22`) and appear static between ticks; alert thresholds are stored and compared at full precision regardless | `PriceText` |
| 13 | Clock skew | "Updated N s ago" compares the server's `t` against the device clock. A badly set device clock would show nonsense; not compensated for | `Quote.timestamp` |
| 12 | Alert re-arming | Assumed one-way `ACTIVE → TRIGGERED`, per the brief | `AlertsCubit` |

`assets/instruments.json` currently holds only the five instruments given as an example in the task; replacing it with the full list needs no code change.

Items marked **TODO** must be resolved or explicitly recorded in `NOTES.md` before submission.

---

## 22. Learning goal

Alongside the functional requirements, this project is used to deepen hands-on experience with real-time data handling in Flutter: WebSocket lifecycle management, `Stream` composition, subscription management across reconnects, propagating high-frequency state through Cubits without over-rebuilding the UI, and expressing alert evaluation as pure, testable domain logic.

The emphasis is on validating design choices in practice — confirming that backoff and resubscription behave correctly under repeated failures, that crossing semantics hold under real tick sequences, and measuring whether the straightforward update path is fast enough before adding anything to it.

---

## 23. Simplicity principles

These govern every phase. When the plan and these rules disagree, these win.

1. **Use the simplest architecture that cleanly satisfies the current requirement.** Not the most sophisticated one that would also work.
2. **Add an abstraction when it solves a problem that exists now.** "Future-proofing", "clean architecture says so" or "it might be useful later" are not reasons. Every class must have an answer to "why does this exist?" that survives being asked in an interview.
3. **Prefer one component over two** when merging them does not make the code harder to read or test.
4. **Keep business logic independently testable** — the alert rules run with no Flutter, no I/O and no setup. That constraint is worth real design effort.
5. **Keep the WebSocket centralised and understandable.** One connection, one owner, one place where protocol details live.
6. **Measure before optimising.** Correct real-time updates first; optimisations only with a number attached, recorded in `NOTES.md`.
7. **Keep UI and design tokens separate from business logic**, so the final design lands in the theme layer and widgets, not in the domain.
8. **Review AI-generated code by hand and simplify it.** Generated code drifts toward extra layers; delete what does not earn its place. The plan itself can change whenever reality shows a simpler path — record the change and the reason.
9. **Write code that explains itself; keep comments out of it.** No doc comments, no narration of what a class does — naming and structure carry that. The only comments allowed are short `TODO`s for genuinely deferred work (a crash reporter, a placeholder to delete, values awaiting the Figma design) and the rare one-liner stating a constraint the code cannot show. Rationale belongs in this document and in `NOTES.md`, not in the source.

---

## 24. Consistency checklist

- [ ] **Exactly one** WebSocket connection: `MarketDataSocket` is built in one place, and a test asserts `FakeTransport.connectCount` stays 1 across navigation. *(§2, §5)*
- [ ] All instruments are subscribed once the list loads, because the first screen shows live Bid/Ask for all of them. *(§10.1)*
- [ ] No widget, page or screen-scoped Cubit creates or manages a socket — `grep` for `MarketDataSocket` outside `core/network/` and `AppDependencies` finds nothing. *(§2)*
- [ ] Reconnection restores all logical subscriptions, proven by a test. *(§5.2, §16)*
- [ ] Quotes feed both the UI and the alert path from the same single source. *(§2)*
- [ ] `AlertEvaluator` imports no Flutter, no Hive and no socket code, and is stateless. *(§7.4)*
- [ ] Hive is touched only in `features/alerts/data/` and `bootstrap.dart`. *(§8.2)*
- [ ] Cubits hold presentation state only — no socket lifecycle, no direct persistence, no condition evaluation. *(§9)*
- [ ] Last known prices stay visible while disconnected, with the status clearly exposed. *(§6.3)*
- [ ] No alert triggering is inferred for a disconnected period; the limitation is in `NOTES.md`. *(§7.6)*
- [ ] Alerts fire on crossings only, never on a condition already true at creation, and never twice. *(§7.1, §7.2, §7.5)*
- [ ] Percentage alerts use the selected side for both reference and evaluation, with the target rounded once. *(§7.3, §4.1)*
- [ ] All five screens exist; the nav bar has three tabs, each preserving its own stack. *(§10.1, §10.2)*
- [ ] The global notification appears above both navigators, verified from a non-default tab. *(§10.3)*
- [ ] Design tokens live in `core/theme/`; feature widgets contain no hardcoded colours or text styles, and Phase 11 can be done without touching `domain/` or `data/`. *(§11)*
- [ ] No credentials or endpoints hardcoded. *(§15)*
- [ ] No silently swallowed exceptions. *(§12)*
- [ ] `NOTES.md` exists and documents AI usage and key decisions. `README.md` is the developer's to write. *(Phase 12)*
- [ ] `flutter analyze` clean, `flutter test` green.
