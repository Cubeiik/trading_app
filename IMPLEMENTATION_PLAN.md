# IMPLEMENTATION_PLAN.md

**Project:** `trading_app` — Flutter mobile trading / market-data application
**Status:** Technical specification & implementation roadmap (no application code written yet)
**Audience:** Implementer (human + AI-assisted), reviewer
**This document is the source of truth for the implementation.**

---

## Table of contents

1. [Purpose and scope](#1-purpose-and-scope)
2. [Goals and non-goals](#2-goals-and-non-goals)
3. [High-level architecture](#3-high-level-architecture)
4. [Real-time data flow](#4-real-time-data-flow)
5. [Project structure](#5-project-structure)
6. [Domain models and numeric types](#6-domain-models-and-numeric-types)
7. [WebSocket design](#7-websocket-design)
8. [Quote state, caching and disconnection behaviour](#8-quote-state-caching-and-disconnection-behaviour)
9. [Alerts: model, engine and semantics](#9-alerts-model-engine-and-semantics)
10. [Local persistence (Hive)](#10-local-persistence-hive)
11. [State management (Cubits)](#11-state-management-cubits)
12. [Screens and global alert UI](#12-screens-and-global-alert-ui)
13. [Routing](#13-routing)
14. [Design-system preparation](#14-design-system-preparation)
15. [Error handling](#15-error-handling)
16. [Performance](#16-performance)
17. [Application lifecycle](#17-application-lifecycle)
18. [Configuration and secrets](#18-configuration-and-secrets)
19. [Testing strategy](#19-testing-strategy)
20. [Dependencies](#20-dependencies)
21. [Implementation phases](#21-implementation-phases)
22. [Decision log](#22-decision-log)
23. [Trade-offs — what stays intentionally simple](#23-trade-offs--what-stays-intentionally-simple)
24. [Open questions and assumptions](#24-open-questions-and-assumptions)
25. [Learning goal](#25-learning-goal)
26. [Consistency checklist](#26-consistency-checklist)

---

## 1. Purpose and scope

The application displays a list of financial instruments with live **Bid** and **Ask** prices delivered over a WebSocket, lets the user open an instrument detail screen, and lets the user define **price alerts** (absolute and percentage-based) that are evaluated against the live quote stream, persisted locally and surfaced globally when triggered.

The scope of the implementation is:

| In scope | Out of scope |
| --- | --- |
| Live quotes list with Bid/Ask | Order placement / trading execution |
| Instrument details screen | User accounts, authentication flows |
| Bottom navigation: Quotes / Alerts / History | Deep linking, web URL support |
| Absolute + percentage price alerts | Server-side alerts, push notifications |
| Alert evaluation engine (crossing-based) | Historical charts / candles |
| Local persistence of alerts and history | Backend implementation |
| One application-wide WebSocket with auto-reconnect | Offline quote replay / backfill |
| Unit + selected widget tests | Full visual design (arrives later, see Phase 14) |

---

## 2. Goals and non-goals

**Engineering goals**

- Clean separation of **data / domain / presentation** inside feature modules.
- Business logic (alert evaluation, connection handling) lives outside widgets and is unit-testable without Flutter bindings.
- A single, application-wide WebSocket connection with logical per-instrument subscriptions.
- Real-time updates that do not cause whole-screen rebuilds.
- A design-system layer so the final Figma design can be applied without touching business logic.

**Explicit non-goals**

- No abstraction created "just in case" (no `UseCase` class per repository method, no custom DI framework, no event bus).
- No premature optimisation (no isolates, no custom render objects) before profiling shows a need.
- No speculative features beyond the task description.

---

## 3. High-level architecture

Feature-oriented, Clean-Architecture-inspired, three layers per feature. Dependencies point inwards: `presentation → domain ← data`.

```
┌──────────────────────────────────────────────────────────────────────┐
│ PRESENTATION                                                         │
│   Widgets ── BlocBuilder / BlocSelector / BlocListener ──┐           │
│   InstrumentsCubit    QuotesCubit    AlertsCubit  <──────┘           │
└───────────────┬──────────────────────────────────────────────────────┘
                │ (reads state, calls methods — never touches sockets/Hive)
┌───────────────▼──────────────────────────────────────────────────────┐
│ DOMAIN (pure Dart, no Flutter, no Hive, no web_socket_channel)       │
│   Entities: Instrument, Quote, PriceAlert, AlertTrigger              │
│   Services: AlertEngine (pure, stateless)                            │
│   Repository interfaces: InstrumentRepository, QuoteRepository,      │
│                          AlertRepository                             │
└───────────────▲──────────────────────────────────────────────────────┘
                │ (implements)
┌───────────────┴──────────────────────────────────────────────────────┐
│ DATA                                                                 │
│   InstrumentLocalDataSource (assets/instruments.json)                │
│   QuoteSocketDataSource  ──uses──> MarketDataSocket (core/networking)│
│   AlertLocalDataSource   ──uses──> Hive boxes (core/storage)         │
│   DTOs + mappers                                                     │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│ APPLICATION WIRING (app/)                                            │
│   AppDependencies  – builds sockets, repositories, cubits            │
│   AlertCoordinator – bridges quote stream → AlertEngine → AlertsCubit│
│   AppRouter        – go_router                                       │
│   AlertNotificationHost – overlay above the Navigator                │
└──────────────────────────────────────────────────────────────────────┘
```

**Why the WebSocket is application-wide and not owned by a screen**

- The instrument list needs quotes for *all* instruments; the detail screen needs a subset. If a screen owned the connection, navigating would tear down and re-establish the socket, losing the last known prices and producing a visible gap.
- Alerts must keep evaluating no matter which screen is visible — even the alerts-history screen. A screen-owned socket would stop alert evaluation the moment the user navigates away.
- Sockets are an expensive, rate-limited resource. One connection with N logical subscriptions is the only sane server-side contract.
- Screen lifecycles are unpredictable (back-navigation, tab switching, hot reload). Connection lifecycle must be tied to the *application*, not to a `State` object.

**Consequence (hard rule):** no widget, screen, route or screen-scoped Cubit ever constructs, opens, closes or reconnects a WebSocket. Screens only read `QuotesCubit` state and (optionally) request additional logical subscriptions through the repository.

---

## 4. Real-time data flow

```
   WebSocket server
          │  raw frames (String / List<int>)
          ▼
   MarketDataSocket                    core/networking
   • connect / disconnect / reconnect (exponential backoff)
   • owns Set<String> subscribedSymbols, resubscribes after reconnect
   • json.decode + message classification
          │  Stream<SocketEvent>   (QuoteEvent | ServerErrorEvent | UnknownEvent)
          │  Stream<ConnectionStatus>
          ▼
   QuoteSocketDataSource + QuoteMapper       features/quotes/data
   • DTO → domain Quote, drops invalid payloads (logged, never thrown to UI)
          │  Stream<Quote>
          ▼
   QuoteRepository (impl)                    features/quotes/data
   • keeps Map<String, Quote> latestQuotes (last known values)
   • exposes: Stream<Quote> quotes            (raw, every tick)
   •          Stream<Map<String,Quote>> snapshots (coalesced, ~10 Hz)
   •          Stream<ConnectionStatus> connectionStatus
   •          subscribeAll(symbols) / subscribe(symbol) / unsubscribe(symbol)
          │
          ├──────────────────────────────┐
          ▼ (coalesced snapshots)        ▼ (raw, every tick)
   QuotesCubit                      AlertCoordinator ──► AlertEngine (pure)
   • QuotesState(quotes, status)                │  List<AlertTrigger>
          │                                     ▼
          ▼                              AlertsCubit
   UI (BlocSelector per row)            • marks alert TRIGGERED
                                        • AlertRepository ──► Hive
                                        • enqueues notification in state
                                                 │
                                                 ▼
                                        AlertNotificationHost (root overlay)
```

**Two consumers, two different needs — an important design point:**

| Consumer | Stream used | Why |
| --- | --- | --- |
| `QuotesCubit` → UI | **coalesced** snapshot stream (~10 Hz) | The human eye cannot use 50 updates/s; coalescing cuts rebuild work dramatically. |
| `AlertCoordinator` → `AlertEngine` | **raw** per-tick stream | Crossing detection compares consecutive observed prices. Dropping intermediate ticks could hide a crossing that reverted within the coalescing window. Alert correctness outranks CPU savings. |

Both subscribe to the *same* repository fed by the *same* single socket. No second connection exists anywhere.

---

## 5. Project structure

```
lib/
  main.dart                          # runApp(bootstrap())
  bootstrap.dart                     # Hive init, error zone, AppDependencies build

  app/
    app.dart                         # MaterialApp.router + MultiBlocProvider
    app_dependencies.dart            # explicit composition root (no DI framework)
    alert_coordinator.dart           # quote stream → AlertEngine → AlertsCubit
    router/
      app_router.dart                # go_router: StatefulShellRoute + 3 branches
      routes.dart                    # route name/path constants
    widgets/
      app_shell.dart                 # Scaffold + NavigationBar (Quotes/Alerts/History)
      alert_notification_host.dart   # global overlay above the whole shell

  core/
    config/
      app_config.dart                # dart-define backed configuration
    theme/
      app_colors.dart
      app_typography.dart            # font families, weights, base sizes
      app_text_styles.dart           # named semantic styles
      app_spacing.dart               # spacing + radii scale (small, on demand)
      app_theme.dart                 # ThemeData assembly + ThemeExtension
    networking/
      websocket/
        market_data_socket.dart      # THE single socket service
        websocket_transport.dart     # thin interface over web_socket_channel
        connection_status.dart
        reconnect_policy.dart        # exponential backoff + jitter
        socket_event.dart            # QuoteEvent | ServerErrorEvent | UnknownEvent
    storage/
      hive_initializer.dart          # box opening, adapter registration
      hive_boxes.dart                # box name + typeId constants
    errors/
      app_exception.dart             # small sealed-ish exception family
      error_logger.dart              # single logging entry point
    utils/
      decimal_x.dart                 # Decimal parsing + percentage maths helpers
      price_formatter.dart           # cached NumberFormat instances (intl)
      stream_x.dart                  # coalescing helper (no rxdart)

  features/
    instruments/
      data/
        datasources/instrument_local_data_source.dart
        dto/instrument_dto.dart
        repositories/instrument_repository_impl.dart
      domain/
        entities/instrument.dart
        entities/contract_type.dart
        repositories/instrument_repository.dart
      presentation/
        cubit/instruments_cubit.dart
        cubit/instruments_state.dart
        pages/instruments_page.dart      # tab 0 — labelled "Quotes" in the nav bar
        pages/instrument_details_page.dart
        widgets/instrument_list_tile.dart
        widgets/connection_status_banner.dart

    quotes/
      data/
        datasources/quote_socket_data_source.dart
        datasources/fake_quote_socket_data_source.dart
        dto/quote_message_dto.dart
        mappers/quote_mapper.dart
        repositories/quote_repository_impl.dart
      domain/
        entities/quote.dart
        entities/quote_side.dart
        repositories/quote_repository.dart
      presentation/
        cubit/quotes_cubit.dart
        cubit/quotes_state.dart
        widgets/price_text.dart       # formatting-only widget (uses PriceFormatter)

    alerts/
      data/
        datasources/alert_local_data_source.dart   # Hive
        models/alert_hive_model.dart               # persistence model + adapter
        mappers/alert_mapper.dart
        repositories/alert_repository_impl.dart
      domain/
        entities/price_alert.dart
        entities/alert_enums.dart     # AlertKind, AlertDirection, AlertStatus
        entities/alert_trigger.dart
        services/alert_engine.dart    # PURE, no Flutter, no I/O
        repositories/alert_repository.dart
      presentation/
        cubit/alerts_cubit.dart
        cubit/alerts_state.dart
        pages/alerts_page.dart          # tab 1 — active alerts
        pages/alert_history_page.dart   # tab 2 — triggered history
        pages/create_alert_page.dart    # full-screen form above the shell
        widgets/alert_form.dart         # form body, kept testable apart from the page
        widgets/alert_list_tile.dart    # shared by the active and history lists

assets/
  instruments.json                   # provided static instrument list

test/
  unit/                              # mirrors lib/ structure
  widget/
  helpers/                           # fakes, builders, fixtures
```

**Why a separate `quotes` feature instead of putting quotes inside `instruments`:**
instrument metadata (symbol, contract type) is static and loaded once; quotes are high-frequency, volatile and consumed by *two* independent features (`instruments` UI and `alerts` logic). Keeping them separate prevents the alerts feature from depending on the instruments feature and keeps the high-churn code isolated. This is the one deliberate deviation from the structure sketched in the task brief, and it is what makes the `InstrumentsCubit` / `QuotesCubit` split (Section 11) natural.

**Directory responsibilities**

| Path | Responsibility |
| --- | --- |
| `app/` | Composition root, routing, root-level UI shell. The only place that knows about *all* features. |
| `core/networking/websocket/` | Transport concerns only. Knows nothing about alerts, Cubits or widgets. |
| `core/storage/` | Hive bootstrap and box name constants. No business rules. |
| `core/theme/` | Design tokens and `ThemeData`. Contains zero logic. |
| `features/*/domain/` | Pure Dart. No `package:flutter`, no `package:hive`, no `web_socket_channel` imports. Enforced by review and by the fact that domain tests run under plain `test`. |
| `features/*/data/` | DTOs, mappers, data sources, repository implementations. The only layer allowed to import Hive or socket packages. |
| `features/*/presentation/` | Cubits, pages, widgets. Holds presentation state only. |

---

## 6. Domain models and numeric types

### 6.1 Numeric type for prices — decision

**Decision: represent prices as `Decimal` (package `decimal`) in the domain layer, as `String` on the wire and in persistence, and convert to `double`/`String` only for display formatting.**

Rationale:

- `double` cannot exactly represent typical decimal price values (`0.1 + 0.2 != 0.3`). For a *display-only* app this is mostly cosmetic, but this app performs **comparisons against thresholds** and **percentage arithmetic**, where binary rounding is observable: `Decimal` guarantees `200 * 1.05 == 210` exactly, whereas `double` yields `210.00000000000003`.
- Exact arithmetic makes alert unit tests deterministic and removes any need for epsilon tolerances in crossing comparisons. Epsilon logic in financial threshold checks is a well-known source of subtle bugs.
- It signals correct instincts for a fintech codebase without introducing a money/currency framework.

Implementation notes:

- Parse from JSON via `Decimal.parse(value.toString())` — never `Decimal.parse(doubleValue.toStringAsFixed(n))` and never construct from an already-lossy `double` when the raw payload is a string.
- Percentage maths needs division: use `Rational` and `toDecimal(scaleOnInfinitePrecision: 10)`, wrapped in `core/utils/decimal_x.dart` so the rounding scale is defined in exactly one place.
- Persist and transport as `String` (`decimal.toString()`), never as `double`.
- Formatting for the UI happens in a `PriceFormatter` (uses `intl`), not inside widgets.

**Cost and fallback:** each `Decimal` allocates `BigInt`s, so a tick costs more than a `double` tick. At the expected rate (tens of updates per second) this is irrelevant. *If* profiling (Phase 13) ever shows it matters, the documented fallback is scaled integers (`int` minor units + per-instrument decimal places) behind the same `Price` helpers — not a switch back to `double`.

### 6.2 `Quote`

```dart
class Quote {
  final String symbol;
  final Decimal bid;
  final Decimal ask;
  final DateTime? serverTimestamp; // null when the backend does not send one (see §24)
  final DateTime receivedAt;       // always set locally, used for staleness reasoning
}
```

- Immutable, `Equatable`, with `copyWith`.
- `serverTimestamp` is nullable **on purpose**: the protocol is not confirmed (Section 24). The UI must never depend on it being present; use `receivedAt` for "last updated" displays and mark the distinction in code comments.
- No `spread` field stored — derive it (`ask - bid`) in a getter if the UI needs it. Storing derived values invites inconsistency.

### 6.3 `Instrument` and `ContractType`

```dart
class Instrument {
  final String symbol;            // "AAPL.US"
  final ContractType contractType;
}

/// Wraps the raw protocol code. Deliberately NOT an enum of guessed names:
/// the meaning of the numeric codes is not documented in the task.
class ContractType {
  final int code;                 // 0, 4, ... as delivered by the backend
  const ContractType(this.code);

  /// Human-readable label, filled in once the codes are confirmed (see §24).
  String get label => _labels[code] ?? 'Type $code';
  static const Map<int, String> _labels = {}; // TODO: populate when documented
}
```

- The meaning of `contractType` numeric codes is **not documented in the task**, so nothing is invented — no `stock` / `crypto` enum values. The raw `int` is preserved verbatim, unknown codes render as `Type 4` rather than throwing or being dropped, and the display label becomes a one-map change once the codes are confirmed. Recorded as an assumption in Section 24.
- A real enum is the right model *later*, once the code set is known and closed; introducing one now would encode a guess into the domain layer.
- Source: `assets/instruments.json`, parsed once at startup. Unknown/extra JSON fields are ignored, not rejected.

### 6.4 `PriceAlert`

```dart
enum QuoteSide { bid, ask }
enum AlertDirection { above, below }
enum AlertKind { absolute, percentage }
enum AlertStatus { active, triggered }

class PriceAlert {
  final String id;                 // uuid v4
  final String symbol;
  final QuoteSide side;            // which price drives the alert
  final AlertDirection direction;
  final AlertKind kind;
  final Decimal targetPrice;       // absolute: user input; percentage: computed at creation
  final Decimal? percentage;       // only for AlertKind.percentage, e.g. 5 or -5
  final Decimal? referencePrice;   // price of `side` captured at creation; required for percentage
  final DateTime createdAt;
  final AlertStatus status;
  final DateTime? triggeredAt;
  final Decimal? triggeredPrice;
}
```

`targetPrice` is **precomputed and stored** for percentage alerts so that evaluation is a single comparison and so that the alert's threshold is stable and inspectable (it is shown in the UI and in tests).

### 6.5 `AlertTrigger`

```dart
class AlertTrigger {
  final PriceAlert alert;     // the alert as it was when it fired (status still active)
  final Decimal price;        // the price that crossed the threshold
  final DateTime occurredAt;
}
```

Returned by `AlertEngine`; consumed by `AlertCoordinator` / `AlertsCubit`. The engine never mutates the alert itself — it reports facts.

---

## 7. WebSocket design

### 7.1 Three concepts that must not be conflated

| Concept | What it is | Cardinality |
| --- | --- | --- |
| **WebSocket connection** | One TCP/TLS connection to the server, managed by `MarketDataSocket`. Can drop and be re-established. | **Exactly 1 per app process** |
| **Logical subscription** | An application-level statement "I want updates for `AAPL.US`", expressed as a protocol message over the existing connection. Survives reconnects (it is replayed). | N per connection |
| **Dart `Stream`** | An in-process delivery mechanism for values already received. Creating/cancelling a stream subscription never opens or closes a network connection. | Many per app |

The code must make this obvious: `MarketDataSocket.subscribe(symbols)` sends a protocol frame and mutates `_subscribedSymbols`; `repository.quotes.listen(...)` only attaches a Dart listener. Naming rule: use *subscribe/unsubscribe* for the protocol and *listen/cancel* for Dart streams — never mix the vocabulary.

### 7.2 `MarketDataSocket` responsibilities

Is responsible for:

- opening and closing the connection;
- reconnecting with exponential backoff;
- tracking and exposing `Stream<ConnectionStatus>` plus a synchronous `status` getter;
- sending subscribe / unsubscribe frames and maintaining `Set<String> _subscribedSymbols`;
- replaying all subscriptions after a successful reconnect;
- decoding and classifying inbound frames;
- exposing `Stream<SocketEvent>` (broadcast);
- surviving malformed and unexpected messages without crashing or closing the connection;
- clean `dispose()` (cancel timers, close sink, close controllers).

Is **not** responsible for and must not contain:

- any UI logic, `BuildContext`, widget or `Navigator` reference;
- any alert business logic;
- any direct Cubit access or state mutation;
- any knowledge of Hive.

### 7.3 Connection state machine

```dart
enum ConnectionStatus { disconnected, connecting, connected, reconnecting }
```

```
                     connect()
   disconnected ─────────────────► connecting
        ▲                              │ open ok
        │ dispose()/close()            ▼
        │                          connected ◄────────────┐
        │                              │ error/done       │ open ok
        │                              ▼                  │
        └───────── giveUp (n/a) ──── reconnecting ─────────┘
                                       │ backoff tick → attempt
                                       └──► (stays reconnecting while retrying)
```

- `connecting` = first attempt after an explicit `connect()`.
- `reconnecting` = automatic recovery after an established connection dropped (or after a failed attempt). The UI distinguishes these: `connecting` shows a neutral "Connecting…", `reconnecting` shows "Reconnecting… showing last known prices".
- `disconnected` is only reached through an explicit `close()`/`dispose()` — the app never gives up automatically. A carried `Object? lastError` field is exposed for the banner/diagnostics.

### 7.4 Reconnect policy

Suggested sequence **1s → 2s → 4s → 8s → 16s → 30s (cap)** is adopted, with three adjustments:

1. **Full jitter**: actual delay = `Random().nextInt(computedDelayMs)` clamped to a 250 ms floor, or at minimum ±20% jitter. Deterministic backoff makes every client retry in lockstep after a server restart (thundering herd).
2. **Attempt counter reset** after the connection has been stable for ≥ 10 s, so a long-lived session that blips once does not start its next recovery at 30 s.
3. **First retry is immediate-ish** (250 ms) when the drop happens while the device reports connectivity — optional, only if it does not complicate the code.

Encapsulated in `ReconnectPolicy`:

```dart
class ReconnectPolicy {
  const ReconnectPolicy({this.initial = const Duration(seconds: 1), this.max = const Duration(seconds: 30)});
  Duration delayForAttempt(int attempt); // 1,2,4,8,16,30,30... + jitter
}
```

Injecting `ReconnectPolicy` and a `Random` seed makes backoff unit-testable with `fake_async` (no real waiting).

### 7.5 Malformed and unexpected messages

Rules, in order of application inside the inbound handler:

| Situation | Handling |
| --- | --- |
| Frame is not valid JSON | Catch `FormatException`, log at warning with a truncated payload, emit `UnknownEvent`, **continue** |
| JSON is valid but shape is unrecognised (no known type discriminator) | Emit `UnknownEvent`, log once per distinct shape (rate-limited), continue |
| Known quote message with a missing/unparsable `bid`/`ask`/`symbol` | Drop the quote in `QuoteMapper`, increment a counter, log at warning, continue |
| Quote for a symbol we never subscribed to | Accept and cache it (harmless), but log at debug — it is a protocol-drift signal |
| Explicit server error message | Emit `ServerErrorEvent`; repository maps it to an app-level error surfaced in the banner. Does **not** force a reconnect unless the socket actually closes |
| Binary frame when text is expected | Attempt UTF-8 decode, otherwise treat as unknown |

Hard rule: **a single bad message never tears down the connection and never propagates an error into a Dart stream that the UI listens to.** The inbound handler wraps per-message processing in `try/catch`; errors are converted into events or dropped, never rethrown into `StreamController.addError` on the quote stream. (Adding an error to a broadcast stream that the UI listens to would risk an unhandled-error crash.)

### 7.6 Transport abstraction

```dart
abstract interface class WebSocketTransport {
  Future<void> connect(Uri uri);
  Stream<dynamic> get messages;
  void send(String data);
  Future<void> close();
}
```

Two implementations: `WebSocketChannelTransport` (production, `web_socket_channel`) and `FakeTransport` (tests — lets tests inject frames, simulate drops, and assert on sent frames). This thin seam is the single abstraction worth having here: without it, socket lifecycle tests would need a real server.

A `FakeQuoteSocketDataSource` (a local random-walk generator behind the same data-source interface) lets the app run end-to-end before the real endpoint is known, selected purely by configuration (Section 18). This is a development affordance, not a parallel architecture.

---

## 8. Quote state, caching and disconnection behaviour

### 8.1 Why `Map<String, Quote>`

The latest quote per symbol is stored as `Map<String, Quote>` keyed by symbol.

- Updating on a tick is `map[symbol] = quote` — **O(1)**. With a `List<Quote>` every tick would require `indexWhere` (**O(n)**); at 200 instruments and 50 ticks/s that is 10 000 comparisons per second of pure waste.
- Reading a single instrument's quote (detail screen, list row, alert evaluation) is also O(1).
- The map is the natural shape for "last known value" semantics: one entry per symbol, always the newest.

`QuotesState` exposes an **unmodifiable** map and a new map instance is created on each emission (copy-on-write) so `Equatable`/identity checks behave correctly and state remains immutable.

> On copy cost: copying a 200-entry map at 10 Hz is trivial. If profiling ever shows otherwise, the documented next step is `package:fast_immutable_collections` or emitting a wrapper with a monotonically increasing `version` counter — **not** mutating shared state in place.

### 8.2 Instrument metadata vs. quote data

They stay conceptually and structurally separate:

- `InstrumentsState` — `List<Instrument>`, loaded once, changes almost never.
- `QuotesState` — `Map<String, Quote>` + `ConnectionStatus`, changes constantly.

A list row composes the two: the instrument comes from the (rarely rebuilt) list, the quote from a `BlocSelector` scoped to that symbol. Merging them into one "InstrumentWithQuote" list would force the entire list to rebuild on every tick — exactly the thing to avoid.

### 8.3 Behaviour while disconnected

| Requirement | Implementation |
| --- | --- |
| Keep showing last known Bid/Ask | The repository's `Map<String, Quote>` is **never cleared** on disconnect. |
| Do not pretend prices are current | `QuotesState.connectionStatus` drives a persistent banner ("Reconnecting — showing last known prices"), and `Quote.receivedAt` allows showing "updated 12 s ago". |
| Expose connection status to UI | `ConnectionStatusBanner` reads `BlocSelector<QuotesCubit, QuotesState, ConnectionStatus>`. |
| Automatic recovery | `MarketDataSocket` reconnects and replays subscriptions; new quotes flow in and overwrite the cache. |
| No manual reload needed | Auto-reconnect is the primary mechanism. |
| Manual retry fallback | A "Retry now" action in the banner calls `repository.reconnectNow()`, which resets the backoff counter and attempts immediately. Purely a convenience. |

**Explicitly not done:**

- No per-instrument greying-out when the whole connection is down. Connection loss is a *global* condition and must be communicated once, globally. Greying 200 rows individually is visual noise that misrepresents the cause.
- A missing update for a single symbol is **not** treated as a failure. Markets are quiet sometimes, and the protocol does not provide per-symbol health signals. Per-symbol staleness marking is deferred until the protocol is confirmed (Section 24).
- No second connection is opened for an individual instrument, ever — including on the detail screen.

---

## 9. Alerts: model, engine and semantics

### 9.1 Crossing semantics (the core rule)

An alert fires only on a **transition across the threshold**, never merely because the condition currently holds.

```
direction == above:   previous <  target  AND  current >= target
direction == below:   previous >  target  AND  current <= target
```

Where `previous` and `current` are the values of the **selected side** (`bid` or `ask`) from two consecutive observed quotes for that symbol.

Consequence, as required: creating an alert `AAPL.US / Bid / Above / 250` while the bid is already 255 does **not** fire. It fires only after the bid drops below 250 and crosses back up (or, more precisely, after any observed transition from `< 250` to `>= 250`).

### 9.2 Baseline rule (how `previous` is established)

**Rule: the first quote observed for a symbol after the alert becomes evaluable establishes the baseline and can never trigger an alert.**

Concretely, `AlertCoordinator` keeps an in-memory `Map<String, Quote> _previousQuotes`:

- On a tick for symbol `S`: if `_previousQuotes[S] == null`, store it and **return without evaluating**. Otherwise evaluate `(previous, current)` and then store.
- When an alert is created, the current live quote is already in `_previousQuotes` (it is what the user saw), so the alert immediately participates in crossing evaluation from the next tick — with no risk of instant firing.
- After a cold start, `_previousQuotes` is empty, so the first tick per symbol is absorbed as a baseline. Alerts restored from Hive therefore never fire on the very first tick after launch.

This single rule satisfies both requirements — "no immediate trigger when the condition already holds" and "no guessing about what happened while we were not receiving data" — without any special-casing.

`_previousQuotes` is deliberately **not persisted**. See Section 9.6.

### 9.3 Absolute alerts

- User input: `targetPrice`, `direction`, `side`.
- `referencePrice` is also captured at creation (the current price of the selected side) for display ("created when bid was 248.30"). It is informational for absolute alerts; evaluation uses only the baseline rule above.
- Validation: `targetPrice > 0`; reject non-numeric input at the form level.

### 9.4 Percentage alerts

- User input: `percentage` (signed, e.g. `+5` / `-5`), `side`. Direction is implied by sign but is still stored explicitly as `AlertDirection` so evaluation code has one uniform path.
- At creation time:

```
referencePrice = current price of the SELECTED side
targetPrice    = referencePrice * (1 + percentage / 100)
direction      = percentage > 0 ? above : below
```

- Worked examples:

| Side | Current bid | Current ask | Percentage | referencePrice | targetPrice | direction |
| --- | --- | --- | --- | --- | --- | --- |
| Bid | 200 | 200.5 | +5% | **200** (bid) | **210** | above |
| Bid | 200 | 200.5 | −5% | **200** (bid) | **190** | below |
| Ask | 200 | 200.5 | +5% | **200.5** (ask) | **210.525** | above |

- **The selected side matters throughout**: if the alert uses Ask, the reference price is the Ask at creation *and* every subsequent evaluation compares Ask values. Mixing sides (reference from bid, evaluation on ask) would produce thresholds the user never asked for. This is enforced by the fact that `AlertEngine` resolves the price via a single `quote.priceFor(alert.side)` helper used for both `previous` and `current`.
- Once `targetPrice` is computed it behaves exactly like an absolute alert — the same crossing comparison applies. Percentage handling therefore adds no branching to the evaluation hot path.
- Validation: a percentage alert **cannot be created without a live price** for the selected side. If no quote is available yet, the create button is disabled and the reason is shown. Creating one anyway would mean an undefined reference price.
- Rounding: `targetPrice` is computed via `Rational` and rounded to a fixed scale (10 decimals) in `decimal_x.dart`, then stored. The stored value — not a recomputed one — is used forever after, so the threshold never drifts.

### 9.5 `AlertEngine` — pure and stateless

```dart
class AlertEngine {
  const AlertEngine();

  /// Pure function. No I/O, no Flutter, no BuildContext, no persistence.
  List<AlertTrigger> evaluate({
    required Quote previous,
    required Quote current,
    required Iterable<PriceAlert> activeAlerts,
  });
}
```

Behaviour:

1. Ignore alerts whose `symbol != current.symbol` (a quote for an unrelated instrument never triggers anything).
2. Ignore alerts whose `status != AlertStatus.active`.
3. For each remaining alert, resolve `previousPrice`/`currentPrice` from the alert's `side` and apply the crossing comparison from Section 9.1.
4. Return one `AlertTrigger` per matching alert (multiple alerts on the same instrument can fire on the same tick — all of them are returned).

The engine is **stateless**: it holds no map, no last-seen prices, no dedupe set. All mutable state lives in `AlertCoordinator` (previous quotes) and `AlertsCubit`/Hive (alert statuses). This is what makes the engine trivially unit-testable — every test is "given two quotes and a list of alerts, expect these triggers", with no setup or teardown.

The engine must not: touch UI, show SnackBars, import `package:flutter`, reference `BuildContext`, write to Hive, or call a Cubit.

### 9.6 Trigger handling and single-firing

On `AlertTrigger` the `AlertCoordinator` calls `alertsCubit.onAlertTriggered(trigger)`, which:

1. Produces `alert.copyWith(status: triggered, triggeredAt:, triggeredPrice:)`.
2. Persists it through `AlertRepository` (Hive) — persistence happens *before* the notification is considered delivered, so a crash cannot lose the record.
3. Emits new state with the alert moved from `activeAlerts` to `triggeredAlerts` **and** appended to a `pendingNotifications` queue.
4. `AlertNotificationHost` renders the head of the queue and calls `alertsCubit.acknowledgeNotification(id)` when dismissed/shown.

**Repeated triggering is prevented structurally, not by a flag check:** once status is `triggered`, the alert is no longer in the active set that `AlertCoordinator` passes to the engine. `ACTIVE → TRIGGERED` is one-way for this task; there is no re-arm. Triggered alerts are retained as history and are only removed by explicit user deletion.

### 9.7 Alerts during disconnection — intentional limitation

**The application does not attempt to determine whether an alert "should have" fired while the connection was down.**

- No backfill request, no gap reconstruction, no inference from the reconnect gap length.
- After reconnect, evaluation simply resumes on incoming quotes, using the baseline rule from Section 9.2.
- Within a single app session the last pre-disconnect quote remains in `_previousQuotes`, so the first post-reconnect tick is compared against a genuinely observed earlier price. This is *observation*, not guessing: if bid went 200 → (gap) → 185 with a `below 190` alert, both endpoints were really observed and the crossing really happened, so firing is correct. Conversely, if the price dipped to 185 during the gap and recovered to 195, **the alert will not fire** — that miss is the accepted limitation.
- After an app restart, `_previousQuotes` is empty, so the first tick per symbol is a baseline and nothing fires. This avoids an alert storm on launch based on prices that may be days old.

Document this in `NOTES.md` as a client-side limitation: reliable alerting across downtime requires server-side evaluation, which is out of scope.

---

## 10. Local persistence (Hive)

### 10.1 Package choice

Use **`hive_ce` / `hive_ce_flutter` / `hive_ce_generator`** — the actively maintained community continuation of Hive 2. The original `hive` 2.x is unmaintained and the Isar-based Hive 4 line was abandoned. The API is the same, so this is a dependency-hygiene decision, not an architectural one. Note it in the README so the reviewer sees it was deliberate. (If the reviewer's environment mandates plain `hive: ^2.2.3`, swapping is a pubspec change plus imports.)

### 10.2 Boxes

| Box | Key | Value | Purpose |
| --- | --- | --- | --- |
| `alerts` | alert `id` (String) | `AlertHiveModel` | **Both** active and triggered alerts, discriminated by the `status` field |
| `app_meta` | fixed keys | primitives | `schemaVersion`, and room for future small flags |

**One box for both active and triggered alerts** rather than two: the `ACTIVE → TRIGGERED` transition becomes a single atomic `put` instead of a delete-from-one-box + put-into-another pair that can half-fail. The repository exposes them separately (`watchActive()` / `watchTriggered()`), so the split is preserved where it matters — in the API — without duplicating storage or models.

### 10.3 Persistence model separate from the domain entity

`AlertHiveModel` is a **separate class** in `features/alerts/data/models/`, annotated for Hive, with:

- `Decimal` fields stored as `String`;
- enums stored as their `int` index **via explicit mapping constants**, never `Enum.index` directly (reordering an enum would silently corrupt data);
- `DateTime` stored as `millisecondsSinceEpoch` UTC int.

`AlertMapper` converts `AlertHiveModel ↔ PriceAlert`. This keeps the domain entity free of Hive annotations and generated code, and means a storage change never touches the domain. The mapper is unit-tested round-trip.

### 10.4 Initialisation

`bootstrap.dart`, before `runApp`:

```
await Hive.initFlutter();
Hive.registerAdapter(AlertHiveModelAdapter());
final alertsBox = await Hive.openBox<AlertHiveModel>(HiveBoxes.alerts);
final metaBox   = await Hive.openBox(HiveBoxes.appMeta);
await HiveInitializer.runMigrations(metaBox, alertsBox);
```

If box opening throws (corruption, disk full), catch it, log it, `deleteBoxFromDisk`, reopen once, and surface a non-blocking "saved alerts could not be restored" message. The app must still start — alerts are valuable but not essential to launching.

### 10.5 Versioning and migration

- `app_meta['schemaVersion']` holds an int, currently `1`.
- `typeId`s are declared as constants in `core/storage/hive_boxes.dart` with a comment: **never reuse or renumber a typeId**.
- Rule for evolution: add new fields with `@HiveField(n)` using the next free index and a non-null default in the mapper; never remove or renumber existing fields.
- `runMigrations` is a simple `switch` on the stored version. For v1 it is a no-op placeholder — present so that the first real migration has an obvious home, not an elaborate framework.

### 10.6 Access rule

```
Widget  ──►  Cubit  ──►  AlertRepository (domain interface)
                              │
                              ▼
                      AlertLocalDataSource  ──►  Hive Box
```

Neither widgets nor Cubits import `hive`. `AlertRepository` (domain) exposes `Future<List<PriceAlert>> loadAll()`, `Future<void> save(PriceAlert)`, `Future<void> delete(String id)`, and `Stream<List<PriceAlert>> watchAll()`. The `Stream` is backed by `box.watch()` inside the data source — an implementation detail the Cubit is unaware of.

---

## 11. State management (Cubits)

Cubits, not Blocs: the interactions here are direct method calls ("create alert", "load instruments", "quote arrived"), with no event sourcing, transformation or debouncing needs that would justify event classes. Where a full Bloc's `EventTransformer` would genuinely help (throttling quote updates), the throttling belongs in the repository layer anyway — it is a data concern, not a presentation concern.

| Cubit | State | Owns | Does **not** own |
| --- | --- | --- | --- |
| `InstrumentsCubit` | `status`, `List<Instrument>`, `failure?` | Loading the instrument list; asking the quote repository to subscribe to all symbols once the list is known | Quotes, connection state, sockets |
| `QuotesCubit` | `Map<String, Quote>`, `ConnectionStatus`, `lastError?` | Mirroring repository snapshots into presentation state; exposing `reconnectNow()` | Socket lifecycle, alert logic, persistence |
| `AlertsCubit` | `List<PriceAlert> active`, `List<PriceAlert> triggered`, `Queue<PriceAlert> pendingNotifications`, `failure?` | Alert CRUD, applying triggers, exposing notification queue | Evaluating conditions (that is `AlertEngine`), talking to Hive directly |

**Deviation from the brief, and why:** the brief suggested a single `InstrumentsCubit` carrying instruments + quotes + connection state. Splitting `QuotesCubit` out is the key performance decision: the instrument list emits once and then stays still, while quotes emit ~10×/s. Keeping them in one state object would mean every tick invalidates the state that the list structure depends on, and every `BlocBuilder` on instruments would rebuild. Separation gives each Cubit one reason to change. This also keeps `AlertCoordinator` independent of the instruments feature.

There is deliberately **no** `AppCubit`, no `ConnectionCubit` (status lives with the data it qualifies), and no `AlertNotificationCubit` (the queue lives in `AlertsState`, since it is derived from the same transition that creates it).

### 11.1 Propagating quote updates without excessive rebuilds

1. **Coalesce at the source.** `QuoteRepositoryImpl` buffers incoming quotes into a pending map and flushes a snapshot every ~100 ms (`Timer.periodic`, only when dirty). One state emission per frame-ish interval instead of one per tick. Implemented in `core/utils/stream_x.dart` as a small `coalesce` helper — no rxdart.
2. **Immutable state + `Equatable`.** Identical snapshots do not emit (`Cubit` drops equal states), so a quiet market costs nothing.
3. **Selective consumption.** Each list row uses:

```dart
BlocSelector<QuotesCubit, QuotesState, Quote?>(
  selector: (state) => state.quotes[symbol],
  builder: (context, quote) => ...,
)
```

Only rows whose quote actually changed rebuild. The selector itself runs for every row on every emission, but it is an O(1) map lookup — cheap and measured in Phase 13.

4. **The list itself never rebuilds on a tick.** `ListView.builder` is driven by `InstrumentsCubit` only.
5. **No work in `build()`.** Formatting is done by a `PriceFormatter` with cached `NumberFormat` instances; no parsing, sorting or filtering inside `build`.
6. **Quote logic stays out of widgets.** Widgets receive a `Quote` and render it. Nothing more.

---

## 12. Screens and global alert UI

### 12.0 Screen inventory and navigation shape

Five screens, organised around a **bottom navigation bar with three tabs**:

```
┌─────────────────────────────────────────────────────────────┐
│  AlertNotificationHost              (above everything)      │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │  AppShell — StatefulShellRoute.indexedStack             │ │
│ │  ┌───────────────┬───────────────┬───────────────────┐  │ │
│ │  │ Branch 0      │ Branch 1      │ Branch 2          │  │ │
│ │  │ /quotes       │ /alerts       │ /history          │  │ │
│ │  │ Live quotes   │ Active alerts │ Triggered history │  │ │
│ │  │   └ /quotes/  │               │                   │  │ │
│ │  │     :symbol   │               │                   │  │ │
│ │  │     details   │               │                   │  │ │
│ │  └───────────────┴───────────────┴───────────────────┘  │ │
│ │  [ Quotes ]      [ Alerts ]      [ History ]   ← NavBar │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                             │
│   /alerts/create   — full-screen, pushed ABOVE the shell    │
│                      (no nav bar, reachable from tab 1      │
│                       and from the details screen)          │
└─────────────────────────────────────────────────────────────┘
```

| # | Screen | Route | Nav bar visible | Primary state source |
| --- | --- | --- | --- | --- |
| 1 | Live quotes list | `/quotes` (tab 0, initial) | yes | `InstrumentsCubit` + `QuotesCubit` |
| 2 | Instrument details | `/quotes/:symbol` | yes (stays in tab 0) | `QuotesCubit` + `AlertsCubit` |
| 3 | Active alerts | `/alerts` (tab 1) | yes | `AlertsCubit.activeAlerts` |
| 4 | Create alert | `/alerts/create` (pushed above shell) | no | `AlertsCubit` + `QuotesCubit` |
| 5 | Alert history | `/history` (tab 2) | yes | `AlertsCubit.triggeredAlerts` |

Two structural points worth stating up front:

- **Active alerts and triggered history are separate screens**, not two sections of one page. They are driven by two distinct fields of the same `AlertsState`, so the split costs nothing in state management and gives each tab one clear job.
- **Create alert is a real screen**, not a bottom sheet. It is pushed onto the root navigator (`parentNavigatorKey: rootNavigatorKey`) so it covers the nav bar: the form is a focused, committed task with explicit Cancel/Save, and the user cannot half-fill it and wander into another tab. The path stays `/alerts/create` so the URL hierarchy still reads correctly.

### 12.1 Live quotes list (`/quotes`, tab 0)

Shows every instrument from `assets/instruments.json`, each row rendering symbol, Bid, Ask, and a per-row placeholder when no quote has arrived yet ("—" rather than a spinner, to avoid a flickering wall of spinners).

- Loading state: skeleton/spinner while the instrument list loads (fast — it is a bundled asset).
- Empty instrument list: explicit empty state with a retry action (Section 15).
- A `ConnectionStatusBanner` pinned above the list reflects `ConnectionStatus`.
- `ListView.builder` + `const` sub-widgets + `ValueKey(symbol)` on rows for stable identity.
- **All instruments are subscribed** once the list loads (`quoteRepository.subscribeAll(symbols)`), because this screen must show live Bid/Ask for all of them. This is a single batched subscribe over the one existing connection.

### 12.2 Instrument details (`/quotes/:symbol`, inside tab 0)

Shows symbol, contract type, current Bid, current Ask, last-updated time, connection/data status, the alerts already defined for this instrument, and a "Create alert" action.

- Reads from the **existing** `QuotesCubit` via `BlocSelector` on that symbol. It creates **no** WebSocket, opens **no** connection, and does not call `connect()`.
- Since the app already subscribes to all instruments, the detail screen normally needs no extra subscription. The code still calls `quoteRepository.subscribe(symbol)` (idempotent — a no-op if already subscribed) so the screen remains correct if the subscribe-all strategy is ever narrowed to visible rows.
- The screen does **not** unsubscribe on dispose, because the list screen behind it still needs that symbol.
- It is pushed **inside** branch 0, so the nav bar stays visible and the user can jump to Alerts and back without losing their place in the list.
- "Create alert" navigates to `/alerts/create?symbol=<symbol>` with the symbol pre-selected.

### 12.3 Active alerts (`/alerts`, tab 1)

Lists `AlertsState.activeAlerts` — alerts still waiting to trigger.

- Each row: symbol, side (Bid/Ask), direction, target price, and for percentage alerts the reference price and percentage. Swipe or trailing action to delete.
- Tapping a row opens that instrument's details (`/quotes/:symbol`), switching to tab 0.
- Primary action (`FloatingActionButton` / app-bar action): **Create alert** → `/alerts/create` with no pre-selected symbol, so the form starts with an instrument picker.
- Empty state: "No active alerts" plus the same create action.
- Reads `AlertsCubit` only. No quote subscriptions, no socket access.

### 12.4 Create alert (`/alerts/create`, full screen above the shell)

The single place where alerts are created, reached from two entry points: the Alerts tab (no symbol pre-selected) and the instrument details screen (symbol pre-selected via the `symbol` query parameter).

Form fields:

| Field | Options | Notes |
| --- | --- | --- |
| Instrument | searchable picker | Skipped/locked when arriving from details |
| Side | Bid / Ask | Drives both reference price and evaluation (§9.4) |
| Kind | Absolute / Percentage | Switches the value field below |
| Direction | Above / Below | For percentage, implied by the sign but still stored explicitly |
| Value | price or percentage | Validated: absolute > 0; percentage ≠ 0 |

- Shows the **current live price of the selected side** and, for percentage alerts, a live preview of the computed `targetPrice` — so the user sees exactly what will be stored.
- The reference price is captured when the form is submitted, from the latest quote for the selected side. The preview updates as quotes arrive, so preview and stored value agree.
- **Percentage alerts are blocked when no live price exists** for that symbol yet — Save is disabled with a visible reason (§9.4).
- Save calls `AlertsCubit.createAlert(...)` and pops back to the caller; a confirmation is shown by the existing notification host rather than a bespoke snackbar.
- Cancel pops without side effects. Unsaved-changes handling stays minimal (a plain back gesture discards).

### 12.5 Alert history (`/history`, tab 2)

Lists `AlertsState.triggeredAlerts`, newest first.

- Each row: symbol, side, direction, target price, the price that actually triggered it, and `triggeredAt`.
- Delete removes an entry permanently; nothing re-arms an alert (`ACTIVE → TRIGGERED` is one-way, §9.6).
- Empty state: "No triggered alerts yet".
- Optional, if it stays simple: a badge on the History tab counting alerts triggered since the tab was last opened. Implementable from `AlertsState` alone — skip it if it starts requiring extra persisted state.

### 12.6 Global alert notification

Requirement: a triggered alert must be visible regardless of the current screen.

**Design: `AlertNotificationHost` is installed in `MaterialApp.router`'s `builder`, i.e. *above* the `Navigator` in the widget tree.**

```dart
MaterialApp.router(
  routerConfig: appRouter,
  theme: AppTheme.light,
  builder: (context, child) => AlertNotificationHost(child: child!),
);
```

```
MaterialApp.router
   └── AlertNotificationHost              ← BlocListener<AlertsCubit>, owns an Overlay/banner
         └── root Navigator (router)      ← /alerts/create pushes here
               └── AppShell + NavigationBar
                     └── branch Navigator (Quotes | Alerts | History)
                           └── current page
```

- It is a `BlocListener<AlertsCubit, AlertsState>` reacting to `pendingNotifications`, rendering a banner in a `Stack`/`OverlayEntry` above the routed content, then calling `acknowledgeNotification(id)`.
- Because it sits above **both** navigators, the notification appears on any tab, on the details screen, and even while the create-alert screen is open. No page needs to know alerts exist.
- Visual treatment stays intentionally minimal (a coloured banner with symbol, side, direction, target and triggered price, auto-dismiss after a few seconds, tap to open the History tab). Phase 14 replaces the visuals only.
- Queue semantics: if several alerts fire on one tick, they are shown sequentially rather than stacked, so the UI cannot be flooded.

**Not chosen:** a global `ScaffoldMessengerKey` + `SnackBar`. It works, but it ties presentation to Material's messenger, behaves awkwardly with bottom sheets and route transitions, and is harder to restyle for a custom design. A root-level host is more explicit and design-system friendly. (A `ScaffoldMessenger` at the root remains a valid fallback if the overlay proves fiddly — documented, not implemented twice.)

---

## 13. Routing

**`go_router`** with `StatefulShellRoute.indexedStack`, configured once in `app/router/app_router.dart`.

| Path | Screen | Placement |
| --- | --- | --- |
| `/quotes` | Live quotes list | Branch 0 (initial) |
| `/quotes/:symbol` | Instrument details | Branch 0, pushed |
| `/alerts` | Active alerts | Branch 1 |
| `/history` | Alert history | Branch 2 |
| `/alerts/create?symbol=` | Create alert | Root navigator, above the shell |

```dart
StatefulShellRoute.indexedStack(
  builder: (context, state, shell) => AppShell(shell: shell),   // Scaffold + NavigationBar
  branches: [
    StatefulShellBranch(routes: [ /* /quotes  + /quotes/:symbol */ ]),
    StatefulShellBranch(routes: [ /* /alerts                    */ ]),
    StatefulShellBranch(routes: [ /* /history                   */ ]),
  ],
),
GoRoute(path: '/alerts/create', parentNavigatorKey: rootNavigatorKey, builder: ...),
```

Rationale:

- `StatefulShellRoute.indexedStack` gives each tab **its own navigator and its own preserved state**, so scroll position in the quotes list and a pushed details screen survive tab switches. A plain `IndexedStack` + `BottomNavigationBar` would need manual navigator keys to achieve the same.
- Declarative and URL-shaped, which keeps deep-linking a triggered alert to `/quotes/:symbol` a one-liner later.
- `MaterialApp.router`'s `builder` gives a clean insertion point for the global alert layer *above* the whole shell (§12.6).
- `/alerts/create` declares `parentNavigatorKey: rootNavigatorKey`, which is what makes it cover the nav bar while keeping a hierarchical path.

Constraints:

- Routing knows nothing about the WebSocket. Switching tabs or pushing a screen never connects, disconnects, reconnects, subscribes or unsubscribes.
- Tabs are **not** rebuilt from scratch on switch, and inactive branches keep listening to `QuotesCubit` — which is harmless because state lives above the router, not in the pages.
- The router and `rootNavigatorKey` are created once and held by `AppDependencies`.
- Route paths and names live in `routes.dart` constants — no string literals scattered in widgets.

---

## 14. Design-system preparation

The first implementation uses **placeholder styling**, but all visual values go through a token layer so the final Figma design can be applied by editing `core/theme/` and a handful of reusable widgets.

| File | Contents |
| --- | --- |
| `app_colors.dart` | Raw palette + semantic aliases (`surface`, `priceUp`, `priceDown`, `alertTriggered`, `statusWarning`). Semantic names — not `blue500` — at the usage site. |
| `app_typography.dart` | Font family, weights, base sizes. |
| `app_text_styles.dart` | Named semantic styles (`priceLarge`, `priceCell`, `symbolLabel`, `caption`). |
| `app_spacing.dart` | A **small** scale (`xs/sm/md/lg/xl`) plus radii. Nothing more until a real design demands it. |
| `app_theme.dart` | Assembles `ThemeData` and registers a `ThemeExtension` for tokens Material does not model (e.g. price-direction colours). |

Rules:

- No hardcoded `Color(0xFF...)`, `TextStyle(...)`, or repeated magic paddings inside feature widgets. They read from `Theme.of(context)` / token classes.
- Reusable presentational widgets (`PriceText`, `SymbolLabel`, `StatusBanner`, `AppCard`) wrap the tokens so a redesign changes few files.
- Do **not** pre-create dozens of unused tokens. Add a token when a second usage appears.

**Strict separation to maintain:**

| Concern | Lives in |
| --- | --- |
| Business logic | `features/*/domain/` (e.g. `AlertEngine`) |
| State | `features/*/presentation/cubit/` |
| Data access | `features/*/data/`, `core/networking/`, `core/storage/` |
| UI structure | `features/*/presentation/pages|widgets/` |
| Design tokens | `core/theme/` |

Phase 14 must be able to touch only the last two rows.

---

## 15. Error handling

A **small** error model, not a framework:

```dart
sealed class AppException implements Exception { final String message; final Object? cause; }
class NetworkException      extends AppException {}
class DataFormatException   extends AppException {}
class StorageException      extends AppException {}
class ValidationException   extends AppException {}
```

Data sources throw these; repositories catch low-level exceptions (`HiveError`, `FormatException`, `SocketException`, `WebSocketChannelException`) and translate them. Cubits catch `AppException` and put a user-facing failure into state. Nothing above the repository layer catches raw platform exceptions.

| Failure | Behaviour |
| --- | --- |
| WebSocket cannot connect / drops | Status → `reconnecting`, banner shown, backoff retry, last known prices kept. Never a blocking error dialog. |
| Malformed WebSocket message | Logged, dropped, connection kept (Section 7.5). Not surfaced to the user. |
| Server error message | Status/banner shows a short reason; logged with full payload. |
| Missing/invalid quote fields | Quote dropped by the mapper; previous value for that symbol remains displayed. |
| `instruments.json` missing/invalid | `InstrumentsCubit` → failure state with message + Retry button. Nothing else can work, so this *is* blocking. |
| Empty instrument list | Distinct empty state ("No instruments available"), not an error, with Retry. No subscribe call is made. |
| Hive open/read failure | Logged; one automatic recovery attempt (delete + recreate box); app continues with an in-memory alert list and a non-blocking warning. |
| Hive write failure | Cubit keeps the in-memory change, emits a "could not save" failure; the user is told, the app does not crash. |
| Invalid alert configuration | Rejected in the form (validation messages); `AlertRepository.save` additionally asserts invariants and throws `ValidationException`. |
| Unexpected backend data shape | `UnknownEvent`, rate-limited log, no crash. |

Cross-cutting:

- **No empty `catch {}` blocks.** Every catch either translates, logs, or both. This is a review checklist item.
- One `ErrorLogger` entry point (`debugPrint`/`log` now, swappable for Crashlytics/Sentry later without touching call sites).
- `runZonedGuarded` + `FlutterError.onError` in `bootstrap.dart` route uncaught errors to the same logger.
- Logs never contain full credentials or tokens; payload logging is truncated.

---

## 16. Performance

Baseline decisions (structural, cheap, done from the start):

| Technique | Where |
| --- | --- |
| One WebSocket, N logical subscriptions | `MarketDataSocket` (Section 7) |
| `Map<String, Quote>` for latest quotes — O(1) update/lookup | `QuoteRepositoryImpl`, `QuotesState` (Section 8.1) |
| Coalescing ticks to ~10 Hz for the UI path only | `QuoteRepositoryImpl` (Section 11.1) |
| Immutable state + `Equatable` so equal states do not emit | All states |
| `BlocSelector` per row; list not rebuilt on ticks | `InstrumentListTile` |
| `ListView.builder` + `ValueKey(symbol)` + `const` leaf widgets | `InstrumentsPage` |
| No parsing/sorting/formatting inside `build()`; cached `NumberFormat` | `PriceFormatter` |
| Quote handling entirely outside widgets | Repository + Cubits |
| JSON decoding done once per frame in the socket handler, not per listener | `MarketDataSocket` |

Deliberately **not** done up front:

- No isolates. JSON frames here are tiny; `compute()` has per-call overhead that would likely make things *worse*. Revisit only if profiling shows main-thread jank attributable to decoding.
- No custom `RenderObject`s, no manual `RepaintBoundary` sprinkling, no `fast_immutable_collections`.

Phase 13 verifies with DevTools (timeline, rebuild counter, memory) under a synthetic high-rate feed (e.g. 200 symbols × 20 ticks/s via `FakeQuoteSocketDataSource`) and records findings in `NOTES.md`. Optimise only what the profile shows.

---

## 17. Application lifecycle

Handled with `AppLifecycleListener` (registered in `App`, delegating to `QuoteRepository`/`MarketDataSocket`):

| Event | Behaviour | Why |
| --- | --- | --- |
| **Launch** | `bootstrap()` opens Hive, builds dependencies, connects the socket, loads instruments, then `subscribeAll`. | First screen needs live prices immediately. |
| **`inactive` / `paused` (background)** | Keep the connection object alive; do not tear down eagerly. The OS will suspend timers/sockets on its own. | Short backgrounding (notification shade, app switcher) should not cost a reconnect. |
| **`resumed` (foreground)** | Call `ensureConnected()`: if the socket is not `connected`, reset the backoff counter and reconnect immediately, then resubscribe. Prices on screen are last-known until fresh ticks arrive. | The socket is usually dead after a long suspension, and iOS/Android do not always deliver a clean `onDone`. |
| **`detached` (termination)** | `dispose()`: cancel timers, cancel stream subscriptions, close the sink, close controllers, close Hive boxes. | No leaked sockets or pending timers. |

Deliberate scope limits, to avoid overengineering:

- No background execution, no attempt to receive quotes or evaluate alerts while suspended. Alerts are evaluated **only** while the app is running and receiving data (consistent with Section 9.7).
- No connectivity-plugin integration (`connectivity_plus`) in the first pass — the backoff loop already recovers. It is listed as an easy, isolated improvement: a connectivity signal would just call `reconnectNow()`.
- An optional refinement, left as a TODO: disconnect after a grace period (e.g. 2 min) in the background to save battery. The architecture supports it (one method call) but it is not implemented by default.

---

## 18. Configuration and secrets

- **No credentials, tokens or private URLs in source control.** Nothing is hardcoded.
- All environment values come from `--dart-define`, read in one place:

```dart
class AppConfig {
  static const wsUrl = String.fromEnvironment('WS_URL');            // empty => fake feed
  static const useFakeFeed = bool.fromEnvironment('USE_FAKE_FEED', defaultValue: false);
  static const instrumentsAsset = 'assets/instruments.json';
}
```

- `AppDependencies` selects `QuoteSocketDataSource` vs. `FakeQuoteSocketDataSource` from `AppConfig`, so swapping the endpoint or running fully offline is a launch-argument change — no code edits.
- If the protocol later requires auth, the token is passed as a `--dart-define` and injected into the handshake/first frame by `MarketDataSocket`; it is never logged and never written to Hive. (Whether auth is needed is an open question — Section 24.)
- A `--dart-define-from-file=env/dev.json` setup plus a committed `env/dev.example.json` is the documented convention; real env files are gitignored.
- README documents the exact run command, e.g. `flutter run --dart-define=WS_URL=wss://...`.

---

## 19. Testing strategy

Priority order: **domain logic > repositories/data > Cubits > widgets**. Tooling: `flutter_test`, `bloc_test`, `mocktail`, `fake_async`.

### 19.1 `AlertEngine` (highest priority — pure unit tests, no mocks)

| # | Test |
| --- | --- |
| 1 | Absolute upward: `prev 249 → cur 251`, target 250, above → **triggers** |
| 2 | Absolute upward, no crossing: `prev 251 → cur 252` → **no trigger** |
| 3 | Absolute downward: `prev 251 → cur 249`, target 250, below → **triggers** |
| 4 | Exact touch: `prev 249 → cur 250.00`, above (`>=`) → **triggers**; `prev 250 → cur 251` → **no trigger** (already at/above) |
| 5 | Bid-side alert reacts to bid changes and **ignores** ask-only changes |
| 6 | Ask-side alert reacts to ask changes and **ignores** bid-only changes |
| 7 | Percentage +5% on bid: reference 200 → target 210; `prev 209 → cur 211` triggers |
| 8 | Percentage −5% on bid: reference 200 → target 190; `prev 191 → cur 189` triggers |
| 9 | Percentage on **ask**: reference is the ask price, evaluation uses ask (regression guard against side mixing) |
| 10 | Reference/target computation is exact (`200 * 1.05 == 210`, no float artefacts) |
| 11 | Condition already satisfied at creation does **not** trigger (baseline rule — coordinator-level test) |
| 12 | Alert triggers only once: after `status == triggered` it is excluded from the active set |
| 13 | Multiple alerts on the same instrument all evaluated; several can fire on one tick |
| 14 | Quote for an unrelated symbol triggers nothing |
| 15 | Already-`triggered` alerts in the input list are skipped |

### 19.2 `AlertCoordinator`

- First quote for a symbol establishes a baseline and never triggers (cold start and post-restore cases).
- Second quote is evaluated against the first.
- A trigger results in exactly one `AlertsCubit` call and one persistence write.

### 19.3 WebSocket / `MarketDataSocket` (with `FakeTransport` + `fake_async`)

- `disconnected → connecting → connected` on a successful connect.
- `connected → reconnecting → connected` on a drop.
- Backoff delays follow 1/2/4/8/16/30/30 (jitter disabled via injected seeded `Random`).
- Attempt counter resets after a stable period.
- **Resubscription after reconnect**: subscribe A+B, drop, reconnect → asserts the resubscribe frame(s) contain exactly A and B.
- `subscribe` is idempotent; `unsubscribe` removes from the set and sends the frame.
- Quote parsing: valid frame → `QuoteEvent` with correct `Decimal` values.
- Malformed JSON → `UnknownEvent`, stream stays open, subsequent valid frames still delivered.
- Missing fields → dropped by the mapper, no exception escapes.
- `dispose()` closes the transport and emits no further events.

### 19.4 Cubits (`bloc_test`)

- `InstrumentsCubit`: loading → success; loading → failure; empty list; `subscribeAll` called with all symbols on success (and **not** called on failure/empty).
- `QuotesCubit`: emits on snapshot; emits on connection-status change; preserves the last known quote map while `reconnecting`; equal snapshots do not emit.
- `AlertsCubit`: create absolute; create percentage (reference/target correctness); reject percentage without a live price; delete; apply trigger (moves active → triggered, enqueues notification); `acknowledgeNotification` dequeues; persistence failure surfaces a failure without losing in-memory state.

### 19.5 Repository / Hive

Run against a temporary directory (`Hive.init(tempDir)`), no mocks:

- Save and load an active alert (round-trip through `AlertHiveModel`, including `Decimal` precision and `DateTime` UTC).
- Update to `triggered` persists status, `triggeredAt`, `triggeredPrice`.
- Delete removes the entry.
- `loadAll` correctly separates active vs. triggered.
- Data survives box close/reopen.
- Mapper round-trip is lossless (property-ish test over a few representative alerts).

### 19.6 Widget tests (selective — behaviour, not pixels)

- Quotes list renders rows with bid/ask from a seeded `QuotesCubit`, and updating one symbol's quote updates only that row's text.
- Connection banner appears in `reconnecting` and disappears in `connected`.
- Detail screen shows the current quote and navigates to the create-alert screen with the symbol pre-selected.
- Creating an alert from `CreateAlertPage` calls `AlertsCubit` with the expected arguments (form validation covered); percentage save is disabled when no live price exists.
- **Navigation shell**: all three tabs are reachable from the nav bar; the Quotes tab keeps its scroll position and any pushed details screen across a tab switch; `/alerts/create` covers the nav bar.
- **Tab separation**: an active alert appears only in the Alerts tab, and after triggering it appears only in the History tab.
- **Global notification**: triggering an alert while the History tab (or the create-alert screen) is active still shows the banner — this is the test that protects the architecture decision in Section 12.6.

Not tested: individual styling widgets, theme values, trivial getters.

### 19.7 Conventions

- `test/` mirrors `lib/`; fakes and fixtures live in `test/helpers/`.
- Domain tests import only `package:test` semantics (no `flutter_test` binding) to prove the domain is Flutter-free.
- No real network and no real timers in tests (`fake_async` everywhere backoff is involved).

---

## 20. Dependencies

Add with `flutter pub add` so versions resolve against the installed SDK (project targets Dart SDK `^3.9.2`). Versions below are indicative lower bounds, not pinned.

**Runtime**

| Package | Purpose |
| --- | --- |
| `flutter_bloc` | Cubits + widget integration |
| `equatable` | Value equality for states/entities |
| `web_socket_channel` | WebSocket transport |
| `decimal` | Exact decimal prices (Section 6.1) |
| `hive_ce`, `hive_ce_flutter` | Local persistence |
| `go_router` | Routing |
| `uuid` | Alert ids |
| `intl` | Price/time formatting |

**Dev**

| Package | Purpose |
| --- | --- |
| `flutter_test` | Test framework |
| `bloc_test` | Cubit testing |
| `mocktail` | Mocks without codegen |
| `fake_async` | Deterministic backoff/timer tests |
| `build_runner`, `hive_ce_generator` | Hive adapter generation |
| `flutter_lints` | Lints (already present; enable a few extra rules) |

**Deliberately excluded**

| Package | Why not |
| --- | --- |
| `get_it` / `injectable` | A composition root (`AppDependencies`) plus `MultiRepositoryProvider`/`MultiBlocProvider` is explicit, testable and dependency-free. A service locator would hide the dependency graph in a project this size. |
| `rxdart` | Only coalescing is needed; ~30 lines in `stream_x.dart` beats a large dependency and keeps stream semantics obvious. |
| `freezed` | `Equatable` + hand-written `copyWith` is enough for ~6 models and avoids a codegen step on every edit. (Reconsider if the model count grows.) |
| `dio` / `retrofit` | No REST calls in scope. |
| `connectivity_plus` | Backoff already recovers; see Section 17. |

`analysis_options.yaml`: keep `flutter_lints` and additionally enable `prefer_const_constructors`, `avoid_print`, `unawaited_futures`, `require_trailing_commas`.

---

## 21. Implementation phases

Each phase is independently reviewable and leaves the app in a runnable state. Do **not** implement them all at once.

---

### Phase 1 — Project bootstrap and dependencies

- **Goal:** dependency set installed, lints configured, placeholder demo code removed, app runs.
- **Files:** `pubspec.yaml`, `analysis_options.yaml`, `lib/main.dart`, `lib/bootstrap.dart`, `lib/app/app.dart`, `assets/instruments.json`, `.gitignore`, `README.md` (skeleton).
- **Tasks:**
  1. `flutter pub add` the runtime and dev packages from Section 20.
  2. Delete the counter demo from `main.dart`; `main()` → `bootstrap()` → `runApp`.
  3. Add `assets/instruments.json` (provided list) and register it under `flutter: assets:`.
  4. Add `runZonedGuarded` + `FlutterError.onError` wiring in `bootstrap.dart`.
  5. Enable extra lints.
- **Depends on:** nothing.
- **Result:** empty-but-clean app launches with a placeholder home screen; `flutter analyze` is clean.
- **Tests:** replace the generated `widget_test.dart` with a smoke test that the app builds.
- **Pitfalls:** forgetting the `assets:` entry (asset loads then fail only at runtime); leaving the generated test referencing the deleted counter.

---

### Phase 2 — Core architecture and design-system foundation

- **Goal:** the skeleton every later phase plugs into.
- **Files:** `core/theme/*`, `core/errors/*`, `core/config/app_config.dart`, `core/utils/decimal_x.dart`, `core/utils/stream_x.dart`, `app/app_dependencies.dart`, `app/router/*`.
- **Tasks:**
  1. `AppColors`, `AppTypography`, `AppTextStyles`, `AppSpacing`, `AppTheme` with minimal placeholder values + a `ThemeExtension` for price colours.
  2. `AppException` family + `ErrorLogger`.
  3. `AppConfig` with `dart-define` values.
  4. `decimal_x.dart`: `parseDecimal`, `percentOf`, rounding scale constant.
  5. `stream_x.dart`: `coalesce` helper (buffer + periodic flush), with tests.
  6. `AppDependencies` shell + `go_router` with `StatefulShellRoute.indexedStack`, `AppShell` (Scaffold + `NavigationBar`: Quotes / Alerts / History) and placeholder pages for all five screens (§12.0).
- **Depends on:** Phase 1.
- **Result:** themed app with a working bottom nav bar, all five routes reachable as placeholders, reusable primitives available.
- **Tests:** unit tests for `decimal_x` (rounding, percentage maths) and `coalesce` (uses `fake_async`); a widget test that each nav-bar tab shows its placeholder and that tab state is preserved across switches.
- **Pitfalls:** over-producing design tokens now; putting logic into theme files; a `coalesce` implementation that leaks its timer on cancel; forgetting `parentNavigatorKey` on `/alerts/create` (the nav bar would then stay visible over the form).

---

### Phase 3 — Instrument models and static instrument source

- **Goal:** the instrument list is loadable from the bundled asset.
- **Files:** `features/instruments/domain/entities/*`, `.../domain/repositories/instrument_repository.dart`, `.../data/dto/instrument_dto.dart`, `.../data/datasources/instrument_local_data_source.dart`, `.../data/repositories/instrument_repository_impl.dart`.
- **Tasks:**
  1. `Instrument` and `ContractType` (raw code preserved, `label` falling back to `Type <code>`).
  2. `InstrumentDto.fromJson` tolerant of unknown fields.
  3. Data source reading via `rootBundle.loadString`, decoding, mapping; throws `DataFormatException` on malformed JSON.
  4. Repository implementation; caches the parsed list in memory (it never changes).
- **Depends on:** Phase 2.
- **Result:** `instrumentRepository.getInstruments()` returns the full parsed list.
- **Tests:** parsing valid JSON; an unseen `contractType` code is preserved and labelled generically (not dropped, no throw); malformed JSON → `DataFormatException`; empty array → empty list (not an error).
- **Pitfalls:** inventing meanings for `contractType` codes; assuming a fixed field order; forgetting that `rootBundle` needs `TestWidgetsFlutterBinding` in tests.

---

### Phase 4 — WebSocket service and connection lifecycle

- **Goal:** one robust, app-wide socket with backoff and resubscription. **The most technically important phase.**
- **Files:** `core/networking/websocket/{websocket_transport, market_data_socket, connection_status, reconnect_policy, socket_event}.dart`.
- **Tasks:**
  1. `WebSocketTransport` interface + `WebSocketChannelTransport` + `FakeTransport` (in `test/helpers/`).
  2. `ConnectionStatus` enum + broadcast status stream + synchronous getter.
  3. `ReconnectPolicy` with injectable `Random` for deterministic tests.
  4. `MarketDataSocket`: `connect`, `close`, `dispose`, `subscribe(Iterable<String>)`, `unsubscribe`, `_subscribedSymbols`, `reconnectNow()`.
  5. Auto-reconnect on `onDone`/`onError`; replay all subscriptions after `connected`.
  6. Inbound handler: decode, classify into `QuoteEvent` / `ServerErrorEvent` / `UnknownEvent`, per-message `try/catch`.
  7. Buffer subscribe requests issued while not connected and flush them on connect.
- **Depends on:** Phase 2.
- **Result:** a socket service testable without a server, with observable state transitions.
- **Tests:** everything in Section 19.3.
- **Pitfalls:** multiple concurrent reconnect timers (guard with a single `Timer?` and an `_isDisposed` flag); resubscribing before the connection reports open; `addError` on a stream the UI listens to; a non-broadcast controller that only supports one listener; not cancelling the transport subscription before reconnecting (duplicate handlers are the classic bug here).
- **Note:** the exact frame formats are assumptions (Section 24) — isolate them in tiny `_buildSubscribeFrame` / `_parseMessage` functions so the real protocol is a one-function change.

---

### Phase 5 — Quote stream and quote state management

- **Goal:** quotes flow from the socket into presentation state, with last-known-value semantics.
- **Files:** `features/quotes/**`.
- **Tasks:**
  1. `Quote`, `QuoteSide`, `quote.priceFor(side)`.
  2. `QuoteMessageDto` + `QuoteMapper` (drops invalid payloads, returns `null`).
  3. `QuoteSocketDataSource` over `MarketDataSocket`; `FakeQuoteSocketDataSource` random-walk generator.
  4. `QuoteRepositoryImpl`: `Map<String, Quote>` cache, raw `Stream<Quote>`, coalesced `Stream<Map<String,Quote>>`, `Stream<ConnectionStatus>`, `subscribeAll/subscribe/unsubscribe/reconnectNow`.
  5. `QuotesCubit` + `QuotesState` (immutable map, status, `lastError`).
  6. Wire into `AppDependencies`; connect the socket during bootstrap.
- **Depends on:** Phase 4.
- **Result:** with the fake feed enabled, live quotes are observable in state (verifiable via a debug page or tests).
- **Tests:** mapper (valid/invalid); repository cache retains values across a disconnect; coalescing emits at most once per window and keeps the newest value per symbol; `QuotesCubit` emission behaviour.
- **Pitfalls:** clearing the cache on disconnect (breaks Section 8.3); emitting the same mutable map instance (equality checks then wrongly suppress emissions); coalescing the alert-facing raw stream by mistake.

---

### Phase 6 — Live quotes list (tab 0)

- **Goal:** the first tab shows live Bid/Ask for all instruments.
- **Files:** `features/instruments/presentation/**`, `app/router/app_router.dart`, `app/widgets/app_shell.dart`.
- **Tasks:**
  1. `InstrumentsCubit` + `InstrumentsState` (loading/success/failure/empty).
  2. On successful load, call `quoteRepository.subscribeAll(symbols)`.
  3. `InstrumentsPage` with `ListView.builder`, `ValueKey(symbol)`, loading/empty/error states.
  4. `InstrumentListTile` with `BlocSelector` on `state.quotes[symbol]`; `—` placeholder before the first quote.
  5. `ConnectionStatusBanner` with a "Retry now" action.
  6. `PriceText` + `PriceFormatter` with cached `NumberFormat`.
- **Depends on:** Phases 3 and 5.
- **Result:** a scrollable live list in the Quotes tab; only changed rows repaint.
- **Tests:** widget test that one symbol's update rebuilds only that row (assert via a rebuild counter); banner visibility per status; empty and failure states; scroll position survives a switch to Alerts and back.
- **Pitfalls:** `BlocBuilder` over the whole `QuotesState` in the page (rebuilds everything); subscribing before the instrument list is loaded; formatting inside `build`; calling `subscribeAll` on every rebuild instead of once.

---

### Phase 7 — Instrument details

- **Goal:** detail screen consuming existing app-level state.
- **Files:** `features/instruments/presentation/pages/instrument_details_page.dart`, route wiring.
- **Tasks:**
  1. Route `/quotes/:symbol` **inside branch 0**, symbol from path parameters.
  2. Read the instrument from `InstrumentsCubit`, the quote via `BlocSelector`.
  3. Show symbol, contract type, bid, ask, last-updated (`receivedAt`), status banner.
  4. Idempotent `subscribe(symbol)` call; **no** unsubscribe on dispose; **no** socket creation.
  5. "Create alert" entry point navigating to `/alerts/create?symbol=…` (the screen itself arrives in Phase 10).
- **Depends on:** Phase 6.
- **Result:** navigable detail view updating in real time, with the nav bar still visible.
- **Tests:** widget test rendering the quote; test asserting no new connection is created on navigation (e.g. `FakeTransport.connectCount == 1` after navigating); pushing details keeps the nav bar and stays in tab 0.
- **Pitfalls:** instantiating a screen-scoped quote source; unsubscribing on dispose and starving the list; crashing when the symbol is unknown (show a not-found state); declaring the route outside the branch, which would hide the nav bar and reset the tab stack.

---

### Phase 8 — Alert domain model and `AlertEngine`

- **Goal:** complete, fully tested alert business logic — with no UI and no persistence yet.
- **Files:** `features/alerts/domain/**`, `app/alert_coordinator.dart`.
- **Tasks:**
  1. Enums, `PriceAlert`, `AlertTrigger`.
  2. Factory helpers `PriceAlert.absolute(...)` and `PriceAlert.percentage(...)` that compute `targetPrice` from `referencePrice` and validate inputs.
  3. `AlertEngine.evaluate` — pure, stateless, side-aware, crossing-based.
  4. `AlertCoordinator`: subscribes to the **raw** quote stream, maintains `_previousQuotes`, applies the baseline rule, calls the engine, forwards triggers.
- **Depends on:** Phase 5 (for `Quote`).
- **Result:** alert logic proven by tests before any UI exists.
- **Tests:** the full matrix in Sections 19.1 and 19.2.
- **Pitfalls:** putting `_previousQuotes` inside the engine (kills statelessness/testability); comparing with `>`/`<` instead of `>=`/`<=` on the current side; using bid for reference and ask for evaluation; forgetting to filter by symbol; forgetting to exclude already-triggered alerts.

---

### Phase 9 — Hive persistence

- **Goal:** alerts and history survive restarts.
- **Files:** `core/storage/*`, `features/alerts/data/**`.
- **Tasks:**
  1. `HiveBoxes` constants (box names, typeIds, with the never-reuse comment).
  2. `AlertHiveModel` + generated adapter (`build_runner`).
  3. `AlertMapper` (`Decimal ↔ String`, enum ↔ explicit int codes, `DateTime ↔ epoch ms UTC`).
  4. `AlertLocalDataSource` (CRUD + `box.watch()` stream).
  5. `AlertRepositoryImpl` implementing the domain interface, translating `HiveError` → `StorageException`.
  6. Hive init + corruption recovery in `bootstrap.dart`; `runMigrations` placeholder with `schemaVersion = 1`.
- **Depends on:** Phase 8.
- **Result:** alerts persist across restarts; no Hive import exists outside `data/` and `core/storage/`.
- **Tests:** Section 19.5.
- **Pitfalls:** persisting prices as `double` (precision loss); storing `Enum.index` implicitly; local-time `DateTime`s; annotating the domain entity with Hive; forgetting adapter registration before `openBox`; leaving generated files out of version control decisions (commit them).

---

### Phase 10 — Alerts screens (tabs 1 & 2, create form) and global notification

- **Goal:** users create, view and delete alerts across three dedicated screens; triggered alerts are visible from anywhere.
- **Files:** `features/alerts/presentation/**`, `app/widgets/alert_notification_host.dart`, `app/widgets/app_shell.dart`, `app/router/app_router.dart`, `app/app.dart`.
- **Tasks:**
  1. `AlertsCubit` + `AlertsState` (active, triggered, `pendingNotifications`, failure) loading from the repository at startup.
  2. `AlertsPage` (tab 1) — active alerts, delete, tap-to-instrument, create action (§12.3).
  3. `AlertHistoryPage` (tab 2) — triggered alerts newest-first with trigger price and time, delete (§12.5).
  4. `CreateAlertPage` + `AlertForm` at `/alerts/create` on the root navigator, accepting an optional `symbol` query parameter; instrument picker when absent; live target-price preview; percentage disabled without a live price (§12.4).
  5. `AlertListTile` shared by both lists, rendering active vs. triggered variants.
  6. `AlertNotificationHost` in `MaterialApp.router`'s `builder`, driven by `pendingNotifications`, with `acknowledgeNotification`; tap navigates to the History tab.
  7. Connect `AlertCoordinator` triggers → `AlertsCubit.onAlertTriggered` → repository persist → notification enqueue.
- **Depends on:** Phases 7 and 9.
- **Result:** the full alert loop works end to end against the fake feed, across all three tabs.
- **Tests:** Section 19.4 (`AlertsCubit`) plus the navigation and cross-route notification widget tests from 19.6.
- **Pitfalls:** placing the listener inside a page (breaks the global requirement); showing a notification before persisting; re-showing the same notification after a rebuild (the queue must be acknowledged); a triggered alert still appearing in the active tab (both lists must derive from `status`, never from a local copy); pushing the create form inside a branch so the nav bar stays visible; losing the pre-selected symbol when arriving from details.

---

### Phase 11 — Error handling and reconnect edge cases

- **Goal:** the app behaves correctly under hostile conditions.
- **Files:** touches `core/networking/`, `features/quotes/data/`, `features/alerts/data/`, banner widgets.
- **Tasks:**
  1. Audit every `catch` for silent swallowing; route all through `ErrorLogger`.
  2. Verify malformed-message handling end to end with injected garbage frames.
  3. Hive failure paths (corrupt box, failed write) and their user-facing messages.
  4. Empty instrument list and asset-load failure states.
  5. Manual "Retry now" resets backoff; confirm no duplicate reconnect loops.
  6. `AppLifecycleListener` (Section 17) including `resumed → ensureConnected`.
- **Depends on:** Phase 10.
- **Result:** no crashes under connection loss, garbage data, or storage failure.
- **Tests:** garbage-frame integration test; repeated drop/reconnect cycles do not spawn duplicate listeners (assert listener/handler counts); storage-failure Cubit test.
- **Pitfalls:** a reconnect storm caused by overlapping timers; a resubscribe frame sent on a closing socket; error state that never clears after recovery.

---

### Phase 12 — Unit and widget tests

- **Goal:** the suite from Section 19 is complete and green (earlier phases add tests as they go; this phase closes gaps).
- **Files:** `test/**`.
- **Tasks:** fill remaining gaps, add `test/helpers/` builders (`buildQuote`, `buildAlert`), ensure no real timers or network, measure coverage.
- **Depends on:** Phase 11.
- **Result:** `flutter test` green; high coverage on `AlertEngine`, `MarketDataSocket`, repositories and Cubits. (Coverage is a signal, not a target — the alert and socket logic should be near-exhaustive; widget coverage stays selective.)
- **Pitfalls:** flaky tests from real `Future.delayed`; over-mocking so tests assert implementation rather than behaviour; widget tests that assert exact pixel/styling values that Phase 14 will change.

---

### Phase 13 — Performance review

- **Goal:** confirm the design holds under load; fix only what is measured.
- **Tasks:**
  1. Drive `FakeQuoteSocketDataSource` at a high rate (e.g. 200 symbols × 20 ticks/s).
  2. DevTools: timeline/frame chart, "track widget rebuilds", memory over ~5 minutes.
  3. Verify the list does not rebuild wholesale; only updated rows repaint.
  4. Tune the coalescing window if needed (100 ms is the starting point).
  5. Check for leaks: repeated navigation and repeated reconnects must not grow subscription counts.
  6. Record findings and numbers in `NOTES.md`.
- **Depends on:** Phase 12.
- **Result:** documented evidence that real-time updates are smooth; any optimisation justified by a measurement.
- **Pitfalls:** profiling in debug mode (always use `--profile`); optimising `Decimal` away without evidence; adding isolates reflexively.

---

### Phase 14 — Final UI / design-system pass (Figma)

- **Goal:** apply the real visual design by changing the design layer and reusable widgets only.
- **Files:** `core/theme/**`, presentational widgets; **no** changes to `domain/`, `data/`, or Cubit logic.
- **Tasks:** real colours/typography/spacing from Figma; restyle `PriceText`, tiles, banner, notification, sheet; add price-direction flash animation if the design calls for it; light/dark if required.
- **Depends on:** Phase 13 and the delivered design.
- **Result:** final look; the diff touches only theme and widget files — which is itself the proof that Section 14's separation worked.
- **Tests:** update only the widget tests that intentionally asserted placeholder text/structure.
- **Pitfalls:** sneaking business logic into styled widgets; hardcoding colours instead of extending tokens; animations that rebuild the whole list on every tick.

---

### Phase 15 — Final cleanup, README/NOTES and review

- **Goal:** a submission a reviewer can read in 10 minutes.
- **Files:** `README.md`, `NOTES.md`, whole-project cleanup.
- **Tasks:**
  1. `README.md`: how to run (including `--dart-define`), how to run tests, project structure overview, screenshots.
  2. `NOTES.md`: architecture summary, the decision log (Section 22), known limitations (Sections 9.7, 17, 24), what would come next with more time.
  3. `flutter analyze` clean; `dart format .`; remove dead code, TODOs and debug prints.
  4. Re-verify the checklist in Section 26.
- **Depends on:** Phase 14.
- **Result:** submission-ready repository.
- **Pitfalls:** leaving the fake feed enabled by default without documenting it; committing env files; a README that omits the required run arguments.

---

## 22. Decision log

| # | Decision | Why |
| --- | --- | --- |
| 1 | **Cubit instead of Bloc** | Interactions are direct method calls; no event sourcing, replay or transformation is needed. Cubits remove event-class boilerplate while keeping logic out of widgets. Where a Bloc's `EventTransformer` would help (throttling), the throttling belongs in the data layer anyway. |
| 2 | **One global WebSocket** | Connections are expensive and server-rate-limited; the list needs all symbols; alerts must keep evaluating across navigation. A screen-owned socket would reconnect on every navigation and stop alert evaluation when the screen is popped. |
| 3 | **Many logical subscriptions over one socket** | Matches how market-data protocols work. Subscriptions are protocol state (a `Set<String>` in the socket service), completely separate from Dart stream listeners. |
| 4 | **Subscribe to all instruments at startup** | The first screen displays live Bid/Ask for every instrument, so every symbol is needed immediately. One batched subscribe is cheaper than incremental viewport-based subscribing, and avoids flicker while scrolling. Viewport-based subscribing remains possible later because the detail screen already calls `subscribe` idempotently. |
| 5 | **Automatic reconnect with exponential backoff (1→2→4→8→16→30 s) + jitter** | Recovers without user action while protecting the server from retry storms. Jitter prevents synchronised client retries; the attempt counter resets after a stable period so a long session does not inherit a 30 s delay. |
| 6 | **Automatic resubscription after reconnect** | A new connection has no server-side subscription state. The socket owns `_subscribedSymbols` and replays it, so no other layer needs reconnect awareness. |
| 7 | **Keep last known prices during a disconnect** | Stale-but-labelled data is more useful than blank rows. The cache is never cleared; the connection status banner makes staleness explicit so nothing is presented as current when it is not. |
| 8 | **Never guess alert triggers during a disconnect** | The client has no knowledge of market movement while disconnected. Inventing triggers would produce false alerts; inventing "missed" evaluations would be unverifiable. Evaluation resumes on observed quotes only. Documented as a client-side limitation. |
| 9 | **Crossing-based triggering** | Users care about *events*, not about a condition that was already true when they set the alert. Comparing consecutive observed prices (`prev < target && cur >= target`) expresses that precisely. |
| 10 | **First observed quote establishes a baseline and never fires** | One rule that simultaneously prevents instant firing at creation time and prevents an alert storm on cold start. Simpler and more robust than special-case flags per alert. |
| 11 | **Reference price captured at creation for percentage alerts** | `+5%` is meaningless without an anchor. Capturing the reference at creation — from the *selected side* — makes the threshold deterministic, inspectable and testable, and it is precomputed into `targetPrice` so evaluation has a single code path. |
| 12 | **The selected side (Bid/Ask) is used for both reference and evaluation** | Mixing sides would silently shift the threshold by the spread. Enforced through a single `quote.priceFor(side)` helper. |
| 13 | **`Decimal` for prices** | Exact decimal arithmetic removes float artefacts in percentage maths and threshold comparisons, eliminates epsilon hacks, and makes tests deterministic. Fallback to scaled integers is documented if profiling ever demands it. |
| 14 | **Hive (`hive_ce`) for persistence** | Required by the brief; fast, no SQL, no schema migrations for a small key-value model. `hive_ce` is the maintained continuation of Hive 2. A separate `AlertHiveModel` keeps the domain entity free of storage concerns. |
| 15 | **One `alerts` box with a `status` field** | Makes `ACTIVE → TRIGGERED` a single atomic write instead of a cross-box move that can half-fail. The repository API still exposes active and triggered separately. |
| 16 | **Feature-oriented architecture with a separate `quotes` feature** | Groups code by what it does, not by technical layer. Splitting `quotes` out prevents the alerts feature from depending on instruments and isolates the high-frequency code path. |
| 17 | **`InstrumentsCubit` / `QuotesCubit` split** | Static list data and high-frequency quote data have different change rates. Combining them would rebuild the list structure on every tick. One reason to change per Cubit. |
| 18 | **Design-system layer prepared from day one** | The final Figma design arrives later. Tokens plus reusable presentational widgets confine the redesign (Phase 14) to the theme layer, with zero business-logic churn. |
| 19 | **Strict separation of socket / quote state / alert logic** | The socket knows about frames, the repository about caching, the engine about rules, the Cubits about presentation. Each is testable alone, and the alert logic runs with no Flutter dependency at all. |
| 20 | **Global alert layer above the Navigator** | Installing `AlertNotificationHost` in `MaterialApp.router`'s `builder` makes notifications independent of the active route, so no page needs alert awareness. |
| 21 | **Explicit composition root instead of a DI framework** | `AppDependencies` + Bloc providers keep the dependency graph visible in one readable file. A service locator would add indirection without benefit at this size. |
| 22 | **Coalesce quotes for the UI, raw stream for the engine** | Human perception needs ~10 Hz; crossing detection needs every tick. Two consumers, two guarantees, one source. |
| 23 | **Bottom navigation with three tabs (Quotes / Alerts / History)** | The three areas are peers the user switches between constantly, not a hierarchy. Active alerts and triggered history answer different questions ("what am I waiting for?" vs. "what happened?"), so they get separate tabs instead of two scrollable sections on one page. |
| 24 | **`StatefulShellRoute.indexedStack` for the tabs** | Each tab keeps its own navigator and state, so the quotes list keeps its scroll position and a pushed details screen survives tab switches. Achieving the same with a plain `BottomNavigationBar` would mean managing navigator keys by hand. |
| 25 | **Create alert as a full screen above the shell, not a bottom sheet** | It is a multi-field, validated form with an instrument picker — a committed task deserving full height, explicit Cancel/Save and no reachable nav bar to wander off into. Keeping the path `/alerts/create` preserves the hierarchy while `parentNavigatorKey` lifts it above the tabs. |

---

## 23. Trade-offs — what stays intentionally simple

| Kept simple | Rationale |
| --- | --- |
| No `UseCase`/`Interactor` class per repository method | Cubits calling repositories directly is readable; one-method wrapper classes would triple the file count with no behaviour change. |
| No DI framework (`get_it`, `injectable`) | An explicit composition root is clearer and testable. |
| No event bus / custom event-driven framework | Dart `Stream`s already are the event system. |
| No separate WebSocket per instrument | Explicitly wrong for this protocol shape; one connection with N subscriptions is the whole point. |
| No `rxdart` | One ~30-line coalescing helper covers the need. |
| No `freezed` codegen | `Equatable` + hand-written `copyWith` for ~6 models; avoids a codegen loop on every model edit. |
| No isolates / `compute` for JSON | Frames are small; the overhead would likely exceed the savings. Revisit only with profiler evidence. |
| No offline quote cache / historical storage | Not required; last-known in-memory values are enough, and persisting quotes would imply staleness semantics nobody asked for. |
| No server-side or push notifications | Out of scope; in-app global notification is what the task asks for. |
| No i18n / multi-language | Not requested. Strings are grouped so it could be added later. |
| No final visuals before the architecture works | Styling a moving target wastes effort; Phase 14 exists for this. |
| No per-symbol staleness heuristics | The protocol offers no per-symbol health signal; guessing would mislabel quiet instruments as broken. |
| No speculative features (watchlists, search, sorting, charts) | Not in the task. Easy to add on top of the existing structure. |

The line taken throughout: **invest in correctness and separation where the task is judged (real-time handling, alert semantics, testability), and keep everything else boring.**

---

## 24. Open questions and assumptions

Nothing below is invented as fact; each item is an assumption to confirm against the real mock/backend. Each is isolated in code so that confirming it changes one small function.

| # | Question | Working assumption | Where it is isolated |
| --- | --- | --- | --- |
| 1 | Exact inbound quote message format | `{"symbol": "...", "bid": ..., "ask": ..., "timestamp": ...}`, one quote per frame | `QuoteMessageDto.fromJson`, `MarketDataSocket._parseMessage` |
| 2 | Message type discriminator | A `type` field distinguishes quotes from other messages; if absent, presence of `bid`/`ask` is used | `MarketDataSocket._classify` |
| 3 | Subscription frame format | `{"type": "subscribe", "symbols": ["AAPL.US", ...]}`, batching supported | `_buildSubscribeFrame` |
| 4 | Whether batch subscribe is allowed | Assumed yes; fallback is one frame per symbol | same as above |
| 5 | Unsubscribe format | Mirror of subscribe | `_buildUnsubscribeFrame` |
| 6 | Whether the server sends timestamps | Assumed **optional** — `Quote.serverTimestamp` is nullable and `receivedAt` is always set locally | `Quote`, `QuoteMapper` |
| 7 | Snapshot vs. incremental updates | Assumed each message is a **full** bid/ask snapshot for one symbol. If incremental (only one side), the mapper must merge with the cached quote instead of replacing it | `QuoteMapper` + `QuoteRepositoryImpl._apply` — **TODO: confirm** |
| 8 | Whether an initial snapshot is sent on subscribe | Assumed yes-or-no tolerant: rows show `—` until the first tick | `InstrumentListTile` |
| 9 | Numeric types on the wire (string vs. number) | Parsing accepts both, via `Decimal.parse(value.toString())` | `decimal_x.dart` |
| 10 | How server errors are represented | Assumed a message with `type: "error"`; unknown shapes fall back to `UnknownEvent` | `MarketDataSocket._classify` |
| 11 | Whether authentication is required | Assumed **not** required for the mock. If needed: token via `--dart-define`, sent in the handshake or first frame, never logged | `AppConfig`, `MarketDataSocket.connect` |
| 12 | Heartbeat / ping-pong requirement | Assumed none. If the server expects pings, add a periodic ping and a pong timeout that forces a reconnect | `MarketDataSocket` — **TODO** |
| 13 | Instrument list source (asset vs. HTTP endpoint) | Assumed a bundled asset `assets/instruments.json`. If it is an HTTP endpoint, only `InstrumentLocalDataSource` is replaced; the repository interface is unchanged | `InstrumentLocalDataSource` |
| 14 | Meaning of `contractType` codes | Unknown. Raw int preserved; labels left empty until documented | `ContractType._labels` |
| 15 | Instrument count | Assumed hundreds, not tens of thousands. If far larger, add search/virtualised loading | Phase 13 |
| 16 | Decimal places / tick size per instrument | Not provided. Formatting uses a sensible default (e.g. 2–5 significant decimals derived from the incoming value) | `PriceFormatter` — **TODO** |
| 17 | Whether alerts should re-arm after triggering | Assumed **no** (`ACTIVE → TRIGGERED` is one-way), per the brief | `AlertsCubit` |
| 18 | Whether triggered history needs a size cap | Assumed no cap for the task; a trim-to-N policy is a one-line repository change | `AlertRepositoryImpl` |

Any item marked **TODO** must be resolved or explicitly noted in `NOTES.md` before submission.

---

## 25. Learning goal

Alongside the functional requirements, this project is used to deepen hands-on experience with **real-time data handling in Flutter** — specifically WebSocket lifecycle management, Dart `Stream` composition, subscription management across reconnects, propagating high-frequency state through Cubits without over-rebuilding the UI, and expressing alert evaluation as pure, testable domain logic.

The emphasis is on validating design choices in practice: measuring what a coalescing window actually saves, confirming that backoff and resubscription behave correctly under repeated failures, and verifying that crossing-based alert semantics hold under real tick sequences. The architecture and decisions in this document reflect deliberate engineering choices, and the implementation is the place to confirm them with measurements and tests.

---

## 26. Consistency checklist

Verify before considering the implementation complete. Each item maps to a decision above.

- [ ] **Exactly one** WebSocket connection exists in the app. `MarketDataSocket` is instantiated in exactly one place (`AppDependencies`), and a test asserts `FakeTransport.connectCount` stays at 1 across navigation. *(§3, §7, §22.2)*
- [ ] All instruments are subscribed after the instrument list loads, because the first screen shows live Bid/Ask for all of them. *(§12.1, §22.4)*
- [ ] No widget, page or screen-scoped Cubit constructs, opens, closes or reconnects a socket. `grep` for `WebSocketChannel` / `MarketDataSocket` outside `core/networking/` and `AppDependencies` returns nothing. *(§3, §12.2)*
- [ ] Reconnection restores **all** logical subscriptions, proven by a test. *(§7.2, §22.6)*
- [ ] The same quote source feeds both the UI (coalesced) and the `AlertEngine` (raw), from one socket. *(§4, §22.22)*
- [ ] `AlertEngine` imports no Flutter, no Hive, no socket package; it is stateless and has no `BuildContext`. *(§9.5)*
- [ ] Hive is touched only inside `features/alerts/data/` and `core/storage/`. No `package:hive` import exists in any Cubit or widget. *(§10.6)*
- [ ] Cubits hold presentation state only — no socket lifecycle, no direct persistence, no alert condition evaluation. *(§11)*
- [ ] Design tokens live in `core/theme/`; feature widgets contain no hardcoded colours or text styles. *(§14)*
- [ ] Phase 14 (Figma) can be completed by changing only `core/theme/` and presentational widgets — no `domain/`, `data/` or Cubit changes. *(§14, §21-14)*
- [ ] Last known prices remain visible while disconnected, with connection status clearly exposed and no per-instrument greying during a global outage. *(§8.3)*
- [ ] No alert triggering is inferred for the disconnected period; the limitation is documented in `NOTES.md`. *(§9.7)*
- [ ] Alerts fire on crossings only, never on a condition that was already true at creation, and never more than once. *(§9.1, §9.2, §9.6)*
- [ ] Percentage alerts use the selected side for both the reference price and all subsequent evaluation. *(§9.4, §22.12)*
- [ ] All five screens exist and are reachable: quotes list, instrument details, active alerts, create alert, alert history. *(§12.0)*
- [ ] The bottom nav bar has exactly three tabs (Quotes / Alerts / History), each preserving its own navigation stack and scroll position. *(§12.0, §13, §22.23)*
- [ ] Active alerts and triggered history are separate screens fed by separate fields of `AlertsState`; a triggered alert never shows up in the Alerts tab. *(§12.3, §12.5)*
- [ ] The create-alert screen covers the nav bar and works from both entry points (Alerts tab without a symbol, details screen with one pre-selected). *(§12.4)*
- [ ] The global alert notification appears above **both** navigators and is verified from a non-default tab by a widget test. *(§12.6)*
- [ ] No credentials or endpoints are hardcoded; configuration flows through `--dart-define`. *(§18)*
- [ ] No silently swallowed exceptions anywhere. *(§15)*
- [ ] `flutter analyze` is clean and `flutter test` is green. *(§21-15)*
