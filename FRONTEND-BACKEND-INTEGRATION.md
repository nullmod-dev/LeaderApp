# FRONTEND-BACKEND-INTEGRATION

The integration contract for features that were **built frontend-first**: the
screen, the states and the seam exist in `flutter_app`, and the backend that
drives them does not exist yet.

One entry per feature. Each entry says what the frontend already does, what it
needs from the server, exactly where to plug the server in, what is currently
faked, and which parts of the contract are **not yet agreed**.

## How this relates to the other documents

| Document | Holds |
|---|---|
| `BACKEND-HANDOFF.md` | The Point 18A **consolidated** backend handoff — cross-cutting rules, inventory, open policies, build order. Start there. |
| `API_CONTRACT.md` | The **agreed** `v1` contract — endpoints, payloads, error codes. |
| `DATA-NEEDS.md` | What each screen needs, deliberately with no endpoints or status codes. |
| **this file** | The **provisional** seams: frontend built ahead of the backend, and the open decisions that blocks. |

A feature graduates out of this file: once its contract is agreed and
implemented, its payload and status codes move into `API_CONTRACT.md` and the
entry here is reduced to a one-line pointer.

Anything still undecided is marked **`Backend contract decision required`**.
Those are questions for the backend developer, not defaults to implement —
guessing one silently is what this file exists to prevent.

## Adding the next entry

Copy the section shape of §1: **Feature → Frontend status → Backend
responsibility → Expected request → Expected response → Frontend reaction →
Required data → Integration point → Mock status → Removal during integration →
Open decisions**. Use real paths and real symbol names, taken from the code
after it is written. Keep it to the contract; the reasoning belongs in
`HANDOFF.md`.

---

## Index

| § | Feature | Frontend status | Blocking open decisions |
|---|---|---|---|
| 1 | Forced Upgrade | Implemented | 2 |
| 2 | RFC 9457 Problem Details / error UX | Frontend foundation implemented | 4 |
| 3 | Local-first writes / idempotency-ready sync | Frontend foundation + conflict state model implemented | 4 (1 resolved by Task 3) |
| 4 | Conflict Resolution UX (stale-write differences screen) | Screen + outbox resolution seam implemented, opened by the Needs Review inbox (§7) | 0 (the last one closed by Task 4) |
| 5 | Optimistic Concurrency & Stale-Write Resolution Contract | **Contract decided (Task 3)**; §5.4's store + write-on-classify wiring built by Task 4 (§7); §5.5's `useLocal` new-operation protocol implemented by the Task 4 corrective pass (§7) | 2 (both explicitly scoped out — see §5) |
| 6 | Attendance Edit Window + Append-Only Corrections | Implemented (frontend/mock only) | 1 |
| 7 | Needs Review inbox + durable conflict review foundation | Implemented (frontend only; no conflict can occur until a real transport exists) — corrected and completed by the Task 4 corrective pass | 1 |
| 8 | Device-local settings + entry surface (**negative** contract: appearance, motion/frame rate, intro, EntryPulse, fixed mark) | Implemented, device-local only | 0 |

---

## §1 — Forced Upgrade

### Feature

The app refuses to run a build the backend no longer serves, and shows a
non-dismissible screen telling the user to update.

### Frontend status

**Implemented.** Screen, four states, routing block, mock trigger, a
client-owned update destination, an offline-persistent gate, and tests are all
in place. No networking was added — nothing in this app talks to a server yet.

### Future backend responsibility

Decide whether the client's installed build is still supported. The client
never compares version numbers: it reports the version it is running and obeys
the answer. Keeping the comparison on the server is what lets the floor move
without shipping an app update.

The backend does **not** own: where the app is installed from (client-owned,
see below), or remembering a past refusal (client-persisted, see below).

### Expected request information

The installed version travels in a header:

```http
X-Client-Version: 1.0.0
```

Declared as `AppInfo.clientVersionHeader` (`lib/core/app_info.dart`), value
`AppInfo.version`, which mirrors `version:` in `pubspec.yaml` and is held to it
by a test.

**Nothing sends this header yet** — there is no HTTP layer in the app. It is
declared so the future API client has one place to read it from.

### Expected backend response

When the installed build is below the minimum supported version:

```http
HTTP/1.1 426 Upgrade Required
```

### Frontend reaction

Enter the blocking Forced Upgrade state immediately: `AppVersionStatus.upgradeRequired`.
The router then sends **every** location to `/upgrade-required` until the gate
opens, so no deep link, tab, or `context.go` can reach application content.

**Two entry points, one state:**

1. **Startup check** — `AppVersionController.build()` fires `check()` once.
2. **A `426` on any ordinary authenticated request** — the transport layer
   calls `ref.read(appVersionProvider.notifier).check()`. There is no public
   "force the gate shut" setter; the gate closes only because a check found a
   reason to, so there is one path in.

Once a `426` (or a support check with `supported == false`) has been seen, the
verdict is **persisted against the installed build identity**
(`AppInfo.buildIdentity` = `major.minor.patch+build`; `AppVersionGateStore`).
A later relaunch — network or none — re-enters the gate before the check runs,
so an offline restart cannot walk past a refusal it already received. A verdict
whose stored build identity does not match the running build is treated as
stale, ignored, and cleared, so shipping a fix — as a new version *or* just a
new build number — is not blocked by the old one.

### Required backend data

| Data | Frontend field | Notes |
|---|---|---|
| Support verdict | `AppVersionSupport.supported` | The only structural field. `HTTP 426` alone is enough to set it `false`. |
| Minimum supported version | `AppVersionSupport.minimumVersion` | Optional. When absent the screen omits the row rather than inventing a number. Also persisted with the gate so the screen still shows the pair offline. |
| Update destination | — | **Wholly client-owned** (`UpdateChannel`). The backend does not send it. `AppVersionSupport.updateUrl` was **removed** (2026-09-04, this session): the field lived on the backend-response model and only muddied that decision, and a wire-controlled launch target is a redirect risk with no product driver behind it. `AppVersionSupport.fromJson` now silently drops an `updateUrl` (or any unknown member) if a `426` body carries one. |

Defined in `lib/features/app_version/domain/app_version_models.dart`. The JSON
names in `AppVersionSupport.fromJson` are the frontend's working assumption,
not an agreed shape.

### Frontend integration point

**The seam is one interface with one method:**

```dart
// lib/features/app_version/domain/app_version_repository.dart
abstract class AppVersionRepository {
  Future<Result<AppVersionSupport>> checkSupport();
}
```

Implement it against the real API and override one provider:

```dart
// lib/features/app_version/data/app_version_providers.dart
appVersionRepositoryProvider  // ← override with the network-backed repository
```

Map the response to the app's existing `Result` type:

| Server | Return |
|---|---|
| `426 Upgrade Required` | `Success(AppVersionSupport(supported: false, …))` |
| any success | `Success(AppVersionSupport(supported: true))` |
| no connectivity / timeout | `Offline()` |
| anything else | `Failure(message)` |

Everything above the seam is already written and must not need changing:

| Concern | Where |
|---|---|
| Gate state + transitions | `AppVersionController` / `appVersionProvider`, `lib/features/app_version/data/app_version_providers.dart` |
| The four states | `AppVersionStatus`, `lib/features/app_version/domain/app_version_models.dart` |
| Blocking predicate | `AppVersionState.blocksApp` — the single thing the router reads |
| Route block | `appRouterProvider` `redirect` + `refreshListenable`, `lib/core/router/app_router.dart` |
| Screen | `UpgradeRequiredPage`, `lib/features/app_version/presentation/upgrade_required_page.dart` |
| Persisted verdict | `AppVersionGateStore` + `PersistedUpgradeGate`, `lib/features/app_version/domain/app_version_gate_store.dart`; `appVersionGateStoreProvider` |
| Update destination | `UpdateChannel` (client-owned config) + `UpdateDestination`, `lib/features/app_version/domain/update_channel.dart`, `.../data/app_version_providers.dart` |
| Tests | `test/features/app_version/forced_upgrade_test.dart` |

**The fail-open rule, which the backend developer must not undo:** a check only
blocks the app if it *finds* a reason to. `Offline` and `Failure` at launch
leave the app running — Leader is offline-first and must open with no network —
*unless* a persisted verdict for this exact build says otherwise. Once the user
is already blocked, the same failures land on `AppVersionStatus.checkFailed` and
keep them there: "we could not ask" is never "you may pass." An unreadable
`AppVersionGateStore` also fails open.

### Mock status

| Faked today | Where |
|---|---|
| The whole endpoint | `MockAppVersionRepository`, `lib/features/app_version/data/mock_app_version_repository.dart` |
| `minimumVersion` = `1.4.0` | `MockAppVersionRepository.placeholderMinimumVersion` |
| Persisted verdict storage | `MockAppVersionGateStore` — in-memory for the lifetime of the object, exactly like `MockSettingsRepository`. Proves the seam and the offline-restart behaviour; **not** durable across an OS process restart. |
| Store / App Store links | `UpdateChannel.androidStore` is real (`applicationId com.leader.teams`; was `com.mtm.mtm` before the Leader rebrand). `UpdateChannel.iosStore` is empty (no iOS target) and `UpdateChannel.webFallback` is a placeholder landing page. |
| Opening the destination | `UpdateDestination.open()` copies the resolved link to the clipboard — the launcher-less development build. Production returns `UpdateLaunchOutcome.opened`. |

The mock answers `supported` by default, so a normal build behaves exactly as
it did before this feature existed. The other states are reached with a
build-time flag, never by anything a user can tap:

```sh
flutter run --dart-define=MTM_VERSION_SCENARIO=upgradeRequired   # the 426 case
flutter run --dart-define=MTM_VERSION_SCENARIO=unreachable       # Offline
flutter run --dart-define=MTM_VERSION_SCENARIO=failing           # Failure
```

### Removal during integration

1. Delete `MockAppVersionRepository` and `AppVersionScenario`, including the
   `MTM_VERSION_SCENARIO` dart-define.
2. Point `appVersionRepositoryProvider` at the real repository.
3. Point `appVersionGateStoreProvider` at a real store that writes
   `PersistedUpgradeGate.toJson()` to the same ordinary local-preferences
   bucket `SettingsRepository` uses (`DATA-NEEDS.md` §3.3 — non-sensitive UI
   state). One key, one JSON object.
4. Replace the body of `UpdateDestination.open()` with a real launch
   (`url_launcher`: try `UpdateChannel.androidStoreNative` then the `https`
   form on Android) and return `UpdateLaunchOutcome.opened`. Fill in
   `UpdateChannel.iosStore` / `webFallback` with real destinations. The button,
   its label and every state on the screen stay as they are.
5. Source `AppInfo.version` **and `AppInfo.buildIdentity`** from the build
   (`package_info_plus`: `version` and `"$version+$buildNumber"`) rather
   than the two constants — see the version-identity note under *Resolved
   since the first draft* below.

Nothing in `UpgradeRequiredPage` should change in any of these steps.

### Open decisions — `Backend contract decision required`

1. **Body of a `426`.** It will use the shared Problem Details contract — see
   §2. The machine-readable concept is `UPGRADE_REQUIRED`; the final wire
   spelling follows §2's decision (the client parses `upgrade_required` today,
   matching the existing `API_CONTRACT.md` casing). Is `minimumVersion`
   returned in that body (as an extension member), or not at all?
2. **What answers the check.** A dedicated support/version endpoint, or "any
   request may answer `426`", or both? This decides whether the app can detect
   an unsupported build before the user signs in. The client already supports
   both paths (`check()` is the single entry point).

**Resolved since the first draft:**

- *Who owns the update destination* — the client does (`UpdateChannel`). The
  API does not return a store URL, and `AppVersionSupport.updateUrl` has been
  removed entirely (see the Required-backend-data table above).
- *Frontend version identity for the persisted gate* — the client now keys
  `PersistedUpgradeGate.blockedVersion` on **`AppInfo.buildIdentity`**
  (`major.minor.patch+build`, the full `pubspec.yaml` `version:` string /
  Flutter's `versionName+versionCode`), not on the display SemVer. So a
  hotfix that keeps the SemVer but bumps the build number is a *different
  binary* and does not inherit the old build's `426`. `AppInfo.version`
  (SemVer only) is still what the screen shows and what
  `X-Client-Version` carries. **Still open — a backend decision:** what
  identity the *server* compares (SemVer? SemVer + platform + build? a
  build hash?), and whether `X-Client-Version` should also carry the
  platform / build number. The client sends `AppInfo.version` and never
  parses it; widening what it sends is a one-line change.

---

## §2 — RFC 9457 Problem Details / frontend error handling

### Feature

A frontend foundation that consumes a future standards-based **RFC 9457
(`application/problem+json`)** error contract: one typed `Problem` model, one
Core classifier for the app-wide conditions, a per-feature extension path for
domain conditions, Leader-owned localized copy for every known condition, and a
safe fallback for codes a shipped build has never heard of.

This entry is the **frontend contract**. It does not implement RFC 9457 server
behaviour, idempotency, concurrency, `/sync`, or revocation.

### Frontend status

**Foundation implemented.**

| Piece | Where |
|---|---|
| Problem model (RFC 9457-shaped, typed extensions) | `Problem`, `ProblemCode` — `lib/core/problem/problem.dart` |
| Parse boundary | `Problem.fromJson` — reads `type/title/status/detail/instance` + the `code` extension + `errors`/`fields`; also tolerates the interim `{error:{…}}` envelope. Unknown members are dropped, not stored. |
| `Result` → `Problem` bridge | `ResultProblem.problemOrNull` — `lib/core/problem/problem_result.dart` (no change to `Result`) |
| Presentation metadata | `ProblemView`, `ProblemSurface` (`field` / `inline` / `transient` / `modal` / `fullScreen`) — `lib/core/problem/problem_presentation.dart` |
| Core classifier (global codes + fallback) | `resolveProblem()` — same file. A bounded `switch`, not a registry. |
| Localized copy | `S.problemUnexpected*`, `S.errNotFound`, `S.errNotPermitted*`, `S.errConflict*`, `S.errValidation`, `S.errServer`, `S.errNetwork`, `S.problemReferenceLabel` — `lib/l10n/strings.dart` |
| Representative integration | `AsyncResultView` failure branch (~25 screens) now renders Leader copy for known codes, the generic fallback for unknown, and never the raw `message`. `lib/core/widgets/async_result.dart` |
| Tests | `test/core/problem/problem_test.dart`, `problem_presentation_test.dart`, `async_result_problem_test.dart` |

### Chosen architecture — **C, hybrid** (Core owns global; features own domain)

Evaluated A (one central resolver), B (fully feature-owned), C (hybrid).
Chosen **C**, because the repository already *is* hybrid and the other two
fight its grain:

- **Shared primitives are already Core.** `Result`, `AsyncResultView`,
  `ErrorStateView`, `EmptyState` are core widgets every feature reuses. A pure
  feature-owned model (B) would duplicate them.
- **Domain error copy is already feature-owned.** `mock_shift_repository`
  already maps its own `check_in_required` / `checkin_after_checkout` codes to
  its own `S.*` strings at its own call site. A central resolver (A) would have
  to absorb every present and future detachment / inventory / workshop /
  patient code — the god object the feature folders exist to avoid.
- **A global blocking state is already Core-owned.** Forced Upgrade (§1) is the
  template: a Core controller, one blocking predicate, one screen. `resolveProblem`
  follows it for `authentication_expired`, `not_permitted`, connectivity and
  `5xx`.
- **Riverpod has no global interceptor.** Errors travel per-provider as
  `Result`. A central resolver would need a new global seam that nothing else
  in the app has; a small pure function on the existing `Result`/`Problem`
  boundary does not.

Not a registry: the global set (upgrade, auth, permission, not-found,
connectivity, server, + `conflict`/`validation` generic defaults) does not grow
with the product, so a plain exhaustive `switch` is right-sized.

### Global vs feature ownership — where a future code is integrated

| A new backend code that is… | …is integrated in | Example |
|---|---|---|
| app-wide (any feature, any screen) | a `case` in `resolveProblem()` + an `S.*` string | session revoked, subscription suspended, account-wide access loss |
| domain-specific | the owning feature's `Result`/`Problem` call site — read `problem.code`, branch, show the feature's own `ProblemView` / sheet / field mapping | `SHIFT_OVERLAP`, `ATTENDANCE_LOCKED`, `EXPIRED_BATCH`, `QUARANTINE`, `FEFO_*`, workshop capacity |
| unknown to this build | nothing — `resolveProblem()` already returns `ProblemView.fallback` | any code shipped after this app version |

A feature code that Core does not enumerate simply resolves to the safe
fallback if it reaches Core — it never needs a Core change to be *safe*, only a
feature change to be *specific*.

### Expected future backend standard

**RFC 9457 Problem Details**, `Content-Type: application/problem+json`. Members
consumed: `type`, `title`, `status`, `detail`, `instance`, plus the extension
members below.

### Required machine-readable extension — `Backend contract decision required`

1. **The `code` member.** A stable machine-readable problem code is
   **required** — it is the only thing the frontend branches on (`§7.1`: never
   on `title`/`detail` text). The client parses it today as
   `code` at the top level *or* `error.code` in the interim envelope. Casing:
   the client currently matches the lowercase `snake_case` already in
   `API_CONTRACT.md` (`not_found`, `not_permitted`, `conflict`, `validation`,
   `authentication_expired`) and adds `upgrade_required`. **If the backend
   prefers `SCREAMING_SNAKE` or URI codes, update `ProblemCode.wire` in one
   place** — it is the single source.
2. **Field errors.** `errors` (or `fields`) as `{ "<field>": "<message>" }`.
   The client reads it into `Problem.fieldErrors`; the owning feature maps it
   to inputs. Confirm the key shape (flat path vs nested).
3. **Support reference.** An explicit, non-identifying id — `reference` /
   `traceId` / `requestId` — shown only on substantial (`modal` / `fullScreen`)
   unexpected-error surfaces, never on a field error. The client does **not**
   treat `instance` as this. No such id exists anywhere in the app today; the
   backend must provide one for it to be shown. Decide the field name.
4. **`minimumVersion` on a `426`** — see §1 open decision 1.

### Frontend rule

Product flow branches on `Problem.code` only. `title` / `detail` are carried
for diagnostics and a last-resort fallback and are **never** shown as product
copy for a known code. In debug builds an unhandled code is `debugPrint`-ed
with its raw code and detail; in release it is silent and the user sees the
generic fallback.

### Known-code behaviour

`resolveProblem()` → a `ProblemView` with an `S.*` title + message, a
`ProblemSurface`, a `retryable` flag (true only for connectivity / `5xx`), and
a `reference` (only when present *and* the surface is substantial). Feature
codes are handled the same way at the feature's own call site.

### Unknown-code behaviour

`ProblemView.fallback` — `S.problemUnexpectedTitle` / `S.problemUnexpectedBody`
("تعذر إكمال العملية" / "حدث خطأ غير متوقع. حاول مرة أخرى."), `retryable:
false` (§11 — an unknown error is not assumed retryable), no stack trace, no
JSON, no raw server text.

### Integration point

- **Parse:** `Problem.fromJson` — the transport/repository layer maps an RFC
  9457 body (or the interim envelope) to `Problem` here. This is the only place
  that touches error JSON.
- **Repository → Result:** repositories keep returning `Result`; a `Failure`'s
  `code` is the wire code and `message` is the (untrusted) server text.
  `ResultProblem.problemOrNull` converts at the presentation boundary.
- **Global codes:** add a `case` to `resolveProblem()` in
  `lib/core/problem/problem_presentation.dart`.
- **Feature codes:** the feature's own `result.when(failure: …)` /
  `problemOrNull` site.
- **Transport errors:** map no-connectivity to `Result.offline`
  (`ProblemCode.offline`), other transport failures and `5xx` to
  `Failure(code: 'network' | 'server')`.

### Mock / provisional state

- No networking anywhere — every repository is still a mock, so no real
  `Problem.fromJson` call happens yet. The parser is covered by unit tests
  against hand-written RFC 9457 and interim-envelope maps.
- Only `AsyncResultView` is wired to the pipeline. Feature mutation surfaces
  (form sheets, snackbars) still use their existing hand-written `S.*` copy and
  are **not** regressed; they adopt `problemOrNull` incrementally.
- `Problem.reference` is never populated (no backend id exists).
- `authentication_expired` is classified (full-screen, `S.sessionExpired*`) but
  nothing auto-routes to `/session-expired` yet — that interceptor is a
  separate task; the extension point is `resolveProblem` + the existing route.

### Backend developer notes

- Send `application/problem+json` with a stable `code`. Do not rely on the
  client reading `title` or `detail` for anything but diagnostics.
- Keep `detail` free of secrets, tokens, PII, stack traces, SQL and internal
  hostnames — the client treats it as untrusted and does not show it for known
  codes, but it may surface in a diagnostic log.
- If you introduce a new domain code, the client stays safe with no change
  (generic fallback). File it against the owning feature to get specific UX.
- Provide an explicit safe support-reference field if you want a reference
  shown on unexpected-error screens.

---

## §3 — Local-first writes / Idempotency-ready synchronization foundation

### Feature

The frontend foundation for Leader's offline-first write model: a valid write is
saved locally, the user keeps working, and the write is synchronized to the
server afterwards — automatically when possible, or from a **مزامنة الآن**
control in Settings. Every logical write carries one stable idempotency
identity that survives retries, app restarts and connectivity loss, so a
future backend can enforce exactly-once effects.

This entry is the **frontend contract**. It does **not** implement the `/sync`
queue, delta/cursor sync, tombstones, a durable Needs-Review inbox, real
conflict *detection* against a live record, or any server-side idempotency
enforcement — those are later tasks. Task 2 adds the local *state model* a
detected conflict would occupy and the local effect of resolving one (see
"Conflict state model" below) — it does not add detection itself.

### Frontend status

**Foundation implemented, conflict state model implemented (Task 2).** No
backend code. No networking (the transport seam exists and its only
implementation returns `Offline`). No full sync engine. No production wire
code classifies anything as a conflict yet — see "Conflict state model"
below.

| Piece | Where |
|---|---|
| Logical write operation (identity + metadata, **no payload**) | `PendingOperation` — `lib/core/sync/pending_operation.dart` |
| Sync lifecycle states | `SyncState { pending, syncing, synced, failed, conflict }` — `lib/core/sync/sync_state.dart` |
| Operation / idempotency id (UUIDv7, RFC 9562) | `UuidV7`, `uuidV7()`, `isUuidV7()` — `lib/core/sync/uuid_v7.dart` |
| Outbox persistence seam | `OutboxStore` (abstract) + `InMemoryOutboxStore` (mock) — `lib/core/sync/outbox_store.dart` |
| The one outbox, and the **single identity-creation point** | `OutboxController` / `outboxProvider` — `enqueue(...)` — `lib/core/sync/outbox_controller.dart`; `pendingOperationsCountProvider` (now `isRetryable`-only), `conflictOperationsCountProvider` |
| Conflict resolution's frontend-only effect on the outbox | `OutboxController.requeueAfterConflict` / `.discardConflict` — same file |
| Stale-write classification seam (no production code wired) | `SyncConflictClassifier`, `defaultSyncConflictClassifier`, `syncConflictClassifierProvider` — `lib/core/sync/sync_conflict_classifier.dart` |
| Network boundary (where `Idempotency-Key` is attached) | `SyncTransport` (abstract) + `OfflineSyncTransport` (honest no-op) — `lib/core/sync/sync_transport.dart` |
| The one engine both sync paths use | `SyncCoordinator` / `syncCoordinatorProvider` — `syncNow({trigger})`; `SyncTrigger { auto, manual }`; `SyncRunOutcome` (now includes `needsReview`) — `lib/core/sync/sync_coordinator.dart`; `syncTransportProvider` |
| Auto Sync trigger seam (lifecycle) | `SyncScheduler` / `syncSchedulerProvider` — `lib/core/sync/sync_scheduler.dart`; wired in `main.dart` on launch + `AppLifecycleState.resumed` |
| Manual Sync surface | `SyncSettingsSection` — `lib/features/settings/presentation/widgets/sync_settings_section.dart`; placed in `settings_page.dart` under `S.sectionSync` |
| Representative integration | `detachment_storage_tab.dart` `_ItemSheetBodyState._record()` — after a local `addMovement` success it calls `outboxProvider.notifier.enqueue(kind: 'inventory.movement.add', …)`, nudges `SyncScheduler.request()`, and lets the user go |
| Tests | `test/core/sync/{uuid_v7,pending_operation,local_first_sync,conflict_outbox,auto_sync_no_navigation}_test.dart`, `test/features/settings/manual_sync_settings_test.dart`, `test/features/inventory/local_first_movement_test.dart`, `test/features/conflict/conflict_outbox_resolver_test.dart` |

### Chosen architecture — **C: a shared lightweight local write-operation primitive**

Evaluated **A** (network-layer mints a key per request), **B** (each feature
owns its own write identity + lifecycle), **C** (one shared primitive).
Chosen **C**:

- **A is impossible and wrong here.** There is no network layer, and a key
  minted per HTTP attempt cannot represent "the same logical write across a
  restart" (roadmap §5).
- **B fragments the thing that must be single.** Auto Sync and Manual Sync
  must consume *one* pending set. Every feature re-implementing identity,
  attempt bookkeeping and persistence would guarantee drift and give the two
  sync paths nothing shared to drain. It also fights the repo's grain — `Result`,
  `Problem`, `AppVersionGateStore` are all shared Core primitives.
- **C fits the repo's own seam idiom** — an `abstract *Store` + an in-memory
  mock + an overridable `Provider`, exactly like `AppVersionGateStore` and
  `SettingsRepository`. No equivalent primitive existed (searched:
  mutation / command / outbox / change-log / dirty-state / sync-metadata —
  none). The `PendingOperation` record can gain fields and the store can move
  to SQLCipher **without replacement**, so the future `/sync` queue *extends*
  this rather than supersedes it.

### Product model (frontend rule)

**Save locally first → keep working → synchronize later.** A write does not
wait on the server. `enqueue` is called *after* the local write already
succeeded and is itself instant and local. Auto Sync is the primary path;
Manual Sync (**مزامنة الآن** in Settings) is the fallback. Both call
`SyncCoordinator.syncNow` over the same `outboxProvider`; neither creates a
`PendingOperation`.

### Logical operation identity

`PendingOperation.operationId` and `PendingOperation.idempotencyKey` are one
UUIDv7 value, minted once in `OutboxController.enqueue` and never regenerated.
`SyncCoordinator` reads it from the stored record on every attempt (this run,
a later auto run, after a restart), so a retry always replays the same
identity. It is dropped only when the operation reaches `SyncState.synced`,
or a human resolves it out of `SyncState.conflict` via `useCurrent`
(`OutboxController.discardConflict`) — see "Conflict state model" below.
`useLocal` (`requeueAfterConflict`) keeps the same record and identity too;
it only moves it back to `pending`.

### Conflict state model (Task 2)

Extends the state model above with exactly **one** new value —
`SyncState.conflict` — rather than the two (`conflict` **and**
`needsReview`) the original roadmap comment reserved. Reasoning and rejected
alternatives are in `HANDOFF.md` §ZZZZ "State-model decision"; the short
version: `needsReview` was reserved for a durable, cross-conflict inbox that
this task does not build, so adding it as a *second state* would have meant
two names for the same thing. It survives as a `bool` predicate instead
(`SyncState.needsReview` / `PendingOperation.needsReview`) and as
`SyncRunOutcome.needsReview`.

- **What moves an operation into `conflict`.** `SyncCoordinator._run` asks
  `syncConflictClassifierProvider` (`sync_conflict_classifier.dart`) to
  classify a `Failure`'s wire `code`. **Task 3 decided this code**: the
  shipped `defaultSyncConflictClassifier` now recognises exactly
  `ProblemCode.staleWrite` (`'stale_write'`, `HTTP 409`) — see §5 for the
  full contract. It is still inert in the shipped app for an unrelated
  reason: `OfflineSyncTransport` is the only `SyncTransport` and never
  returns anything but `Offline`, so no push can ever be classified either
  way until a real backend and transport exist. The wire codes for
  *in-progress* / *same-key-different-body* remain
  `Backend contract decision required` (below) — Task 3 deliberately did not
  resolve those; see §5's classifier subsection for why.
- **What changes for a `conflict` operation.** `PendingOperation.isRetryable`
  is `false`, so `SyncCoordinator._run`'s queue (now filtered on
  `isRetryable`, not `isUnsynced`) skips it — no more auto/manual pushes
  until a human acts. `pendingOperationsCountProvider` (also `isRetryable`
  now) stops counting it; `conflictOperationsCountProvider` (new) counts it
  instead, surfaced by `SyncSettingsSection`'s attention row.
- **How a human resolves it.** `lib/features/conflict/data/
  conflict_outbox_resolver.dart` maps a Task 1 `ConflictResolutionDecision`
  onto `OutboxController.requeueAfterConflict` (`useLocal` → back to
  `pending`, same identity, retried by the *next* ordinary run) or
  `.discardConflict` (`useCurrent` → removed, no server contact) or nothing
  at all (`reviewLater` → left exactly as-is). None of the three claims a
  server-side outcome — see §4 below for the full seam.

### Expected future request header

`Idempotency-Key: <PendingOperation.idempotencyKey>`, attached by the real
`SyncTransport` implementation. **Format: UUIDv7** (RFC 9562), generated
today by `lib/core/sync/uuid_v7.dart` with `dart:math` `Random.secure()` — no
new dependency. `X-Client-Version: <AppInfo.version>` travels alongside as
before.

### Future backend responsibilities

The backend must:

- enforce idempotency keyed on `Idempotency-Key`;
- recognise a duplicate retry of a completed operation and return success
  without re-applying the effect;
- distinguish "same key, still processing" from a hard failure;
- reject "same key, different body" as a protocol fault;
- retain idempotency results for the agreed window (roadmap: ~7 days —
  **backend-owned**, see *Retention* below);
- return **RFC 9457 Problem Details** for idempotency conflicts / in-progress
  cases (see §2).

### Future result behaviour — conceptual conditions the transport must map

| Condition | `SyncTransport.push` returns | Coordinator effect |
|---|---|---|
| Applied / accepted | `Success(null)` | operation → `synced`, removed from outbox |
| Duplicate of a completed operation | `Success(null)` | same as applied — the retry is a no-op server-side |
| Still processing the same key | `Failure(code: <in-progress code>)` | operation stays pending, retried later — **must not** surface as a scary generic error |
| Version mismatch (stale write) | `Failure(code: 'stale_write')` | routed to `SyncState.conflict` — `syncConflictClassifierProvider` recognises this code today (Task 3, see §5); only a real transport is missing |
| Same key, different body (invalid idempotency reuse) | `Failure(code: <invalid-reuse code>)` | **not** the same thing as a stale write — a protocol fault, not a version conflict (§5) — still `Backend contract decision required`, must **not** be classified into `SyncState.conflict` when it is agreed |
| No connectivity / timeout | `Offline()` | operation → `failed` (`lastProblemCode: 'offline'`), run stops, **not** data loss |
| `5xx` / transport error | `Failure(code: 'server' | 'network')` | operation → `failed`, retried later |

`Backend contract decision required` — the exact wire `code` strings for
*in-progress* and *same-key-different-body (invalid idempotency reuse)* are
**not** invented here; Task 3 resolved only the stale-write code (`§5`),
deliberately leaving these two open (see §5's classifier subsection for why).
When decided they become `ProblemCode` values (Core, §2) or feature-owned
codes; the coordinator already carries whatever `code` the transport hands
it, and `syncConflictClassifierProvider` must **not** be extended to treat
either of them as `stale_write`.

### Retention (7-day rule)

Treated as a **future backend contract** (idempotency-result retention,
~7 days). The frontend has **no** 7-day timer. The local outbox keeps an
operation until it is `synced`, or a human resolves it out of
`SyncState.conflict` (`useLocal`/`useCurrent`, see "Conflict state model"
above) — there is no time-based frontend expiry, and if one is ever needed it
must be decided from the outbox lifecycle, not copied from the server's
retention window.

### Frontend integration points (for the backend / networking work)

| Concern | Symbol / file |
|---|---|
| Local write identity is created | `OutboxController.enqueue` — `lib/core/sync/outbox_controller.dart` |
| Pending sync state lives | `OutboxStore` (`lib/core/sync/outbox_store.dart`); today `InMemoryOutboxStore`, override `outboxStoreProvider` with a SQLCipher-backed store |
| Auto Sync trigger connects | `SyncScheduler.request()` (`lib/core/sync/sync_scheduler.dart`), called from `main.dart`; add a connectivity-stream listener here when a connectivity plugin lands |
| Manual Sync trigger connects | `SyncSettingsSection._syncNow` → `syncCoordinatorProvider.notifier.syncNow(trigger: SyncTrigger.manual)` |
| Network transport receives the idempotency key | `SyncTransport.push(PendingOperation)` — implement it, attach `Idempotency-Key: operation.idempotencyKey`, override `syncTransportProvider` |
| The wire code → app effect mapping | `SyncCoordinator._run` `switch` on `Result` |
| The wire code → conflict classification | `syncConflictClassifierProvider` — override once the *invalid-reuse* code is agreed (`lib/core/sync/sync_conflict_classifier.dart`) |

### What is mocked / provisional

- `InMemoryOutboxStore` — holds operations for the lifetime of the object
  only (same limitation as `MockSettingsRepository` / `MockAppVersionGateStore`).
  A second `ProviderContainer` over the same instance models a relaunch and
  is used to test restart-persistence; it is **not** durable across an OS
  process restart. Real store → SQLCipher table `pending_operations`.
- `OfflineSyncTransport` — the only `SyncTransport` today; every push returns
  `Offline`. So in the shipped app, pending operations stay truthfully
  `pending` and Manual Sync reports "لا يوجد اتصال…", never a fabricated
  success.
- `SyncScheduler` — fires on launch and resume only. No connectivity trigger
  (no connectivity plugin in the dependency set).
- `SyncStatus.lastSyncedAt` — in memory only; a durable "last successful
  sync" belongs with the real outbox store.
- `AppInfo.buildIdentity` — a constant `'1.0.0+1'` held to `pubspec.yaml` by
  test; a real build sources it from `package_info_plus`.
- `defaultSyncConflictClassifier` (Task 2, wired to `stale_write` in Task 3) —
  recognises the agreed code, but no real transport exists to ever produce
  it, so `SyncState.conflict` is unreachable in the shipped app regardless.
  Tests override `syncConflictClassifierProvider` with a private test code to
  exercise the transition without depending on the production string. See
  "Conflict state model" above and §5.

### Deferred work (explicitly not in this task)

`GET /sync?cursor=…`, opaque cursors, `hasMore`, tombstones, full queue
upload, per-operation server results, a durable cross-conflict Needs-Review
inbox, a generic merge surface, `CURSOR_EXPIRED`, account-revocation sync
behaviour, and the `needsReview` `SyncState` value (the per-operation
`conflict` state is implemented — Task 2; a *durable, cross-conflict inbox*
state distinct from it is not — `SyncState.fromWire` already keeps an
unknown state as `pending` rather than treating it as done, so adding it
later is additive).

### `Backend contract decision required`

1. ~~Wire `code` for a stale-write conflict~~ — **decided, Task 3**:
   `stale_write` (`ProblemCode.staleWrite`). See §5.
2. Wire `code` strings for *in-progress* and *same-key-different-body
   (invalid idempotency reuse)* — **deliberately left open by Task 3**, not
   overlooked: these are idempotency-replay-timing conditions, not
   optimistic-concurrency conditions, and the code for
   *same-key-different-body* must **not** be folded into `stale_write` (§5
   explains why they are different failure shapes and why resolving them now
   risks a `SyncState` surface change beyond a small aligned constant).
3. Whether `Idempotency-Key` is the final header name (roadmap says yes).
4. The server-side idempotency retention window (roadmap: ~7 days) and whether
   the client is ever told a key has expired.
5. Whether `/sync` upload is one operation per request or a batch, and the
   per-operation result shape — this decides whether `SyncTransport.push`
   stays one-at-a-time or gains a batch method.

---

## §4 — Conflict Resolution UX (stale-write differences screen)

### Feature

A generic, privacy-safe screen and typed route seam for resolving one
stale-write conflict on a record the user edited locally: the app shows only
the fields that actually differ between the user's unsynced local edit and the
record's current shared state, and the user picks **استخدام تعديلي** (use
mine), **استخدام النسخة الحالية** (use current), or **مراجعة لاحقاً** (review
later).

This entry is the **frontend UX contract** for the resolution screen and its
outbox-resolution seam. It does not implement conflict *detection* against a
real record, a durable Needs-Review inbox, or any real sync — see §3 for the
local-first write foundation (including the `SyncState.conflict` state and
classifier seam, Task 2) this sits on top of.

### Frontend status

**Screen implemented (Task 1); frontend-only decision → outbox seam
implemented (Task 2); the backend contract this screen assumes is now
decided but not implemented (Task 3, §5); still not wired to any real
trigger.** Nothing in the app currently pushes this route — no repository
builds a `ConflictPresentation` from a real `SyncState.conflict` operation
yet, so there is nothing to open it with. This is the ready screen + typed
decision seam a future conflict-detecting integration opens and wires
together, now with a full write-up of what that integration must do (§5)
instead of a set of open questions.

| Piece | Where |
|---|---|
| Generic view model (no raw backend data) | `ConflictPresentation`, `ConflictFieldComparison`, `ConflictResolutionIntent`, `ConflictValueDirection` — `lib/features/conflict/domain/conflict_models.dart` |
| Typed decision emitted by the screen | `ConflictResolutionDecision`, `ConflictDecisionHandler` — same file |
| Route argument type | `ConflictResolutionRouteArgs` — same file |
| The screen | `ConflictResolutionPage` — `lib/features/conflict/presentation/conflict_resolution_page.dart` |
| Safe fallback (no data / stale deep link) | `ConflictUnavailablePage` — same file |
| The only feature adapter built so far | `presentShiftConflict()` — `lib/features/shift/presentation/shift_conflict_adapter.dart` |
| **Decision → outbox seam (Task 2)** | `applyConflictResolution`, `conflictDecisionHandlerProvider` — `lib/features/conflict/data/conflict_outbox_resolver.dart` |
| Route | `GoRoute(path: '/conflicts/:conflictId', …)` — `lib/core/router/app_router.dart` |
| Strings | "Conflict resolution" block, plus `S.syncReviewOne/Many`, `S.syncNeedsReviewNote` (Task 2) — `lib/l10n/strings.dart` |
| Tests | `test/features/conflict/{conflict_resolution_page,conflict_outbox_resolver}_test.dart`, `test/core/router/app_router_test.dart` |

### Chosen design — differences-first (Option B)

The screen shows only the fields that differ, each field paired local-vs-current,
rather than either alternative:

- **Rejected — full side-by-side of both complete records.** Duplicates two
  entire records the user must scan field-by-field to find what actually
  changed, and enlarges the surface where an unapproved or raw field could
  leak into a shared, generic screen.
- **Rejected — a generic automatic merge engine.** `ConflictResolutionIntent`
  deliberately has no `merge` value. Safe field-level merge semantics differ
  per domain (e.g. merging a shift's assigned members has no single safe
  default) — a shared merge engine would either be unsafe or would have to
  special-case every feature anyway, which defeats having a shared screen at
  all. A feature may add its own domain-owned merge flow later only once that
  domain can define what "merge" safely means for it.
- **Chosen — differences-first.** The generic screen never sees a full domain
  record, only feature-approved `ConflictFieldComparison` entries — already
  labeled and formatted by the owning feature's adapter. This directly
  satisfies "no raw JSON, no backend field name, no generic merge engine" and
  keeps the decision narrow: what changed, and which complete version should
  win.

### Product model

- **Local vs current framing:** "نسختك" (your version — the unsynced local
  edit) vs "النسخة الحالية" (the current version — the last one synced with
  the team). Consistent color/icon treatment distinguishes the two throughout.
- **Three typed intents only:** `useLocal`, `useCurrent`, `reviewLater`.
  `ConflictResolutionDecision.resolvesConflict` is `false` only for
  `reviewLater`.
- `baseVersion`/`currentVersion` are opaque `String?` concurrency tokens the
  frontend carries but never renders — a placeholder shape until the backend's
  token format is agreed (see open decisions). `ConflictResolutionDecision`
  carries `currentVersion` forward so a future keep-local retry targets the
  latest shared version rather than replaying the stale one.

### Frontend integration point

- **Push the route:** `context.push(ConflictResolutionPage.locationFor(conflictId), extra: ConflictResolutionRouteArgs(conflict: presentation, onDecision: handler))`.
  The route builder in `app_router.dart` only renders `ConflictResolutionPage`
  when `extra` is a `ConflictResolutionRouteArgs` **and** its
  `conflict.conflictId` matches the `:conflictId` path segment; otherwise it
  renders `ConflictUnavailablePage` — a cold deep link or a stale `extra`
  (e.g. browser-style forward/back reusing a previous navigation's `extra`)
  never fabricates or misattributes a conflict.
- **Build the view model:** each domain writes its own adapter, following
  `presentShiftConflict()` — read the two typed records, compare only the
  fields worth surfacing, and format+localize every value before it enters
  `ConflictFieldComparison`. No adapter exists yet for inventory, workshop, or
  member records; a feature adds one only when it actually needs this screen.
- **Handle the decision:** `onDecision` is awaited by the screen before it
  closes. `conflictDecisionHandlerProvider` (Task 2,
  `lib/features/conflict/data/conflict_outbox_resolver.dart`) is a
  ready-made, tested `ConflictDecisionHandler` a future caller can pass
  straight through: it applies `useLocal` (`OutboxController.
  requeueAfterConflict`, back to `pending`, same identity) and `useCurrent`
  (`.discardConflict`, removed) to the underlying `PendingOperation` (§3), and
  does nothing for `reviewLater` — which **is** how the operation stays
  `SyncState.conflict`, since there is still no durable Needs-Review store to
  persist that choice into (see open decisions). It never talks to a server
  and never claims one did. A thrown exception still propagates so the screen
  can show `S.conflictDecisionFailed` and keep the conflict open for a retry.
- **Root-navigator placement:** the route sits beside the forced-upgrade gate,
  before the bottom-nav `StatefulShellRoute`, so it covers the bottom nav like
  other substantial decision surfaces. It automatically inherits the router's
  one blocking `redirect` — while the forced-upgrade gate is closed, this
  route (like every other location) redirects to `/upgrade-required` with no
  special-casing needed.
- **Auto Sync must never open this route.** Still true after Task 2, and no
  longer only by absence: `SyncScheduler`/`SyncCoordinator` (§3) have no
  reference to `GoRouter`, `context`, or any navigator at all, so a classified
  conflict can only ever change local outbox state, never navigate —
  `test/core/sync/auto_sync_no_navigation_test.dart` proves this against a
  real `GoRouter` instance. Task 4's inbox keeps that intact: it is reachable
  only by a human tapping the Settings attention row, and the recorder Auto
  Sync calls on classification (§7) writes local metadata and returns — it
  has no `context`, no router and no UI of any kind.

### How unresolved conflicts are preserved

No conflict is silently discarded on exit:

- Tapping any of the three actions always calls `onDecision` and **awaits**
  it before the screen closes — navigation cannot outrun persistence.
- System back, the AppBar back icon, and an edge-swipe-to-dismiss gesture all
  funnel through one `PopScope`. Before a decision has been recorded, an
  attempted pop is intercepted and submits `reviewLater` first; only once that
  call resolves does the screen allow the real pop (`_allowPop`), and the pop
  itself is deferred to the next animation frame so it is not swallowed by the
  in-progress pop dispatch that triggered it. (This is the fix for the
  previously reported bug: a completed decision on a root route — no route
  below it to pop to — no longer re-triggers a duplicate `reviewLater`
  submission on a second back-press.)
- If `onDecision` throws, the screen stays open, shows
  `S.conflictDecisionFailed`, and the conflict is never marked resolved.
- `_saving` and `_allowPop` together also prevent a duplicate submission (for
  example a second back-press while the first `reviewLater` call is still in
  flight).

### Privacy / safety

The screen only ever receives what a feature adapter explicitly put in
`ConflictPresentation` — no raw JSON, backend field names, or hidden
identifiers are ever composited into displayed text. Covered by a dedicated
test (`opaque identities, versions, and backend details are not shown`) that
plants backend-looking strings (`Bearer …`, `SQLSTATE …`, a raw field name, a
JSON fragment) in every non-display field and asserts none of them render.

### Accessibility

Each version-legend and value cell composes one `Semantics` label (e.g. "نسختك،
تعديلاتك غير المزامنة") and wraps its visible `Text` children in
`ExcludeSemantics` — the same pattern already used by `_ChoicePill` in
`settings_page.dart` — so a screen reader announces the composed label once
instead of the label followed by the same title/value again as it descends
into the underlying text nodes. Covered by
`version legend and value cells announce their composed label once`.

### Mock / provisional pieces

- `SyncState.conflict`, the local decision → outbox seam (§3, Task 2) and
  the durable review store + inbox (§7, Task 4) **are** implemented. What
  remains missing is the one upstream step: nothing can *fill* a review entry
  for a real conflict, because no feature composer captures a `409` body's
  current record yet and no transport can return one. The inbox handles that
  honestly rather than papering over it — such a conflict is still listed,
  marked "details unavailable", and never opened with nothing to compare.
- `baseVersion`/`currentVersion` are typed as opaque `String?` today; §5
  decides the wire shape they wrap (a server-managed integer `version`,
  stringified at the parse boundary — no change needed to these fields).
  Task 2's outbox seam still does not read or attach either — a `useLocal`
  requeue is retried by the ordinary sync loop exactly as any other `pending`
  operation, with no version echoed. §5 documents why a real `useLocal` must
  **not** simply requeue the same operation once a transport exists (a new
  idempotency identity is required — see §5's resolution-protocol
  subsection) — `requeueAfterConflict`'s current behaviour is correct only
  because nothing is actually sent over the wire yet.
- `presentShiftConflict` is the only adapter. No other domain has one.
- `ConflictUnavailablePage` is the only "no data" state; no conflict is ever
  fabricated to demo the screen from a cold deep link.

### Removal / follow-on during integration

Nothing to *remove* — there is no mock to swap out, because nothing calls this
screen yet. The follow-on work is additive:

1. Add conflict *detection* to `SyncCoordinator`'s handling of a stale-write
   `Failure` — done in Task 2 via `syncConflictClassifierProvider` (§3), but
   with no production wire code wired to it yet.
2. ~~Build the piece that actually opens this route for a real conflict~~ —
   **done, Task 4 (§7)**: `NeedsReviewPage` pushes
   `ConflictResolutionPage.locationFor(conflictId)` with
   `onDecision: ref.read(conflictDecisionHandlerProvider)`, rebuilding the
   `ConflictPresentation` from the durable review entry stored at detection
   time. What is still missing is upstream of the route, not at it: a real
   transport that can return `stale_write`, and a feature composer that can
   build an entry from a real `409` body (§7, "What is still mock").
3. ~~Decide where an unresolved (`reviewLater`) conflict is surfaced beyond
   the quiet Settings count~~ — **done, Task 4 (§7)**: the count row in
   Settings is now the entry point to a full Needs Review list, derived from
   the same `conflictOperationsCountProvider` source so the two cannot
   disagree.
4. Add adapters for the other domains that can conflict, each following
   `presentShiftConflict`'s shape, only as each is actually needed.

### Open decisions — `Backend contract decision required`

Task 3 decided the contract this screen needs (§5). What is listed below is
what §5 explicitly could **not** decide from repository evidence alone — a
short, genuinely external list, not the four broad questions Task 1/2 left.

1. ~~How a stale-write response is detected; the shape of
   `baseVersion`/`currentVersion`; where a `reviewLater` choice is durably
   recorded; how `useLocal`/`useCurrent` gets applied server-side~~ — **all
   decided, §5**: the `stale_write` `409` embeds (or references) the current
   record and an opaque `currentVersion`; the token wraps a server integer
   `version` starting at `1`; the durable unit stays the existing
   `PendingOperation` plus a feature-owned "current-as-of-detection"
   snapshot (§5, "Conflict persistence boundary") — still no cross-conflict
   *list* UI, which stays explicitly out of scope, not undecided; `useLocal`
   resolves through a new logical operation referencing the original, never
   a same-key resend of a changed body (§5, "Resolution protocol").
2. ~~Whether a durable, cross-conflict Needs-Review *list* is ever built,
   and if so how a tap on `conflictOperationsCountProvider`'s count routes to
   a specific conflict~~ — **decided and built, Task 4 (§7)**: yes, as a root
   route `/needs-review` reached only from the Settings attention row, with
   the durable per-conflict metadata §5.4 specified. Nothing here is a
   backend decision; §7 lists the one item that still is.

---

## §5 — Optimistic Concurrency & Stale-Write Resolution Contract (Task 3)

### Feature

The backend contract §3 (local-first sync/idempotency) and §4 (conflict UX)
were both built against but never pinned down: what a "version" is, the exact
stale-write wire code, what a stale-write `409` must contain, what the client
durably keeps for a later review, and how resolving a conflict (`useLocal`)
becomes a safe, idempotent wire operation instead of an unsafe resend under
an already-used key.

**This section is a decision and documentation record, not new frontend
behaviour.** It resolves the open questions §3/§4 left, so a backend
developer can implement optimistic concurrency without guessing, and it
records exactly what changed in code to align with that (one `ProblemCode`
value, its generic presentation, and the classifier that now recognises it —
all already covered in §2/§3's own text). No `/sync` queue, no server, no
database constraint, no resolution networking, and no Needs-Review inbox was
built here — see "Explicitly out of scope" at the end of this section.

### Evidence this decision was built from

Two kinds of evidence, weighted differently:

- **This repository's own implemented decisions** (authoritative): the
  `Problem`/`ProblemCode` model (§2), the `PendingOperation` /
  `SyncState.conflict` / classifier seam (§3), the differences-first
  `ConflictPresentation` screen and its `presentShiftConflict` adapter (§4),
  and `API_CONTRACT.md`'s existing error envelope and tenant/auth
  conventions. Where a newer decision here narrows an older one, the newer
  one wins.
- **MTM-PRO** (`/home/ahmed/Documents/Python-Files/flutter/apps/MTM-PRO`,
  read-only reference, a *different, unrelated* project's security and
  architecture documentation for a similarly-shaped medical-teams backend):
  used only as evidence for how a comparable backend already resolved the
  same class of problem — never copied, never treated as this project's
  decision, and never allowed to override an MTM-Front-Back ruling. Cited
  below as "MTM-PRO evidence" wherever it shaped a choice. Nothing was
  changed in MTM-PRO and nothing from its backend implementation was ported
  here — this document restates the *concept* (e.g. "a server-issued
  version counter") in MTM-Front-Back's own already-established conventions
  (e.g. lowercase `snake_case` wire codes), not its code.

### 1. Concurrency token

**Decision: `version` — a server-managed, opaque-to-the-client token, wire
type JSON integer, frontend type `String`.**

- **Name and wire type.** Every mutable, synchronized entity's read/list
  response gains a sibling field `"version"` (a JSON integer) next to
  `"id"`. MTM-PRO evidence: every syncable table there carries
  `version bigint NOT NULL DEFAULT 1`, enforced by a database trigger, with
  `xmin` explicitly rejected as an alternative (lost on dump/restore, wraps
  around) and ordering defined as "the server-issued version counter, never
  device timestamp" — the same reasoning applies here: Leader field devices
  cannot be trusted to agree on wall-clock time, so the token must be a
  counter the backend alone advances.
- **Opaque from the frontend's perspective.** The client parses the integer
  into a `String` once, at the JSON boundary, and never re-parses,
  increments, or numerically compares it — it is a value the client is
  handed and echoes back verbatim. This matches the type already chosen for
  `ConflictPresentation.baseVersion`/`currentVersion` (`String?`,
  `lib/features/conflict/domain/conflict_models.dart`) — **no change needed
  to that model**; the wire integer is simply what those strings will
  actually hold once a real backend exists.
- **Where it appears in reads.** On every read (`GET`/list) of a mutable
  entity, sibling to `id`. Not implemented on any frontend domain model in
  this session — `Shift`, `TeamMember`, etc. gain a `version` field only when
  a real backend/read-response mapping is written for them; adding it now
  would touch every call site of a model this task does not own, for a field
  nothing yet reads.
- **How the frontend sends it back.** As a body field named `version`,
  sibling to the fields being changed, on the mutating request — not a
  header. Headers in this contract are reserved for transport-boundary
  concerns already spoken for (`Idempotency-Key`, `X-Client-Version`, §1/§3);
  `version` is a per-entity domain value the owning feature's repository call
  already assembles, so it belongs in the same JSON body that call already
  sends (`API_CONTRACT.md` "JSON conventions").
- **Creation.** A newly created record's response returns `version: 1` — a
  defined, documented starting value (matching MTM-PRO's `DEFAULT 1`), never
  `0` and never omitted.
- **After a mutation.** A successful mutation's own response returns the
  record's new `version` as an ordinary field of the updated resource. The
  client never computes the next value or assumes an increment amount — it
  always reads the fresh value back, exactly as it reads any other field the
  server just changed.
- **Deleted / archived entities.** A delete or archive request includes the
  `version` the client last read, so a concurrent edit-then-delete race is
  still caught as `stale_write` rather than silently deleting a version the
  client never saw. A soft-delete/archive response still returns the
  record's final `version` (useful for later audit/undo). A hard delete
  (`204 No Content`) needs no version in its response — nothing remains to
  conflict against, and a second delete attempt is answered by the existing
  `not_found` code, not `stale_write`.
- **What deliberately does NOT get a `version` (evidence-based scoping).**
  Purely append-only writes — the running example throughout §3,
  `inventory.movement.add` — create a new row per movement and never edit a
  shared counter, so they are structurally free of stale writes and must
  **not** carry a `version` field. MTM-PRO evidence names this exact
  distinction explicitly: status/attribute fields use last-write-wins with a
  version check, while append-only ledger rows (their inventory-movement
  equivalent) are described as conflict-free by construction — "the single
  most important design decision" for that data shape. The same reasoning
  applies to a server-computed/derived value the client never edits directly
  (e.g. a workshop's true capacity ceiling) — never versioned, because the
  client never held a version of it to begin with.
- **The backend remains the sole concurrency authority.** Nothing above
  prescribes a database engine, a locking strategy, or a schema — only the
  wire shape and the rule that the client treats the value as opaque.

### 2. Stable stale-write code

**Decision: `stale_write` — a new, distinct `ProblemCode` value. Already
implemented.**

- **What was added.** `ProblemCode.staleWrite` (`lib/core/problem/
  problem.dart`, wire `'stale_write'`), a generic `resolveProblem()` fallback
  for it (`lib/core/problem/problem_presentation.dart`, `S.errStaleWriteTitle`
  / `S.errStaleWrite`, `lib/l10n/strings.dart`), and
  `defaultSyncConflictClassifier` (`lib/core/sync/sync_conflict_classifier.
  dart`) now returns `true` exactly for this code —
  `ProblemCode.parse(problemCode) == ProblemCode.staleWrite`, never a raw
  string comparison, to stay in the one `ProblemCode` vocabulary rather than
  a second parallel one. Covered by `test/core/sync/
  sync_conflict_classifier_test.dart` (new) and the existing
  `problem_test.dart` / `problem_presentation_test.dart` parametrized loops
  (which already iterate `ProblemCode.values` and now include this one for
  free).
- **Relationship to `HTTP 409`.** `stale_write` is one of (at least) two
  distinct conditions this API returns as `409` — the pre-existing generic
  `conflict` (a synchronous business-rule condition, e.g.
  `ShiftRepository.assignVolunteer`'s "someone else changed this record") and
  the new `stale_write` (a versioned write's `version` no longer matches).
  **The status code alone never distinguishes them — only `code` does**, and
  the frontend already only branches on `code` (§2, §7.1).
- **Relationship to RFC 9457 / the interim envelope.** Carried as the `code`
  extension member exactly like every other `ProblemCode` — no new envelope
  shape, no second `code` vocabulary. `Problem.fromJson` needs no change:
  `ProblemCode.parse` already round-trips any string in the enum, `stale_write`
  included.
- **Relationship to the existing generic `conflict` classification.**
  Deliberately a different string precisely so the two are never conflated —
  `sync_conflict_classifier.dart`'s own doc comment already stated this rule
  before Task 3; Task 3 gives it a real code instead of leaving it as a
  naming convention with nothing to enforce it.
- **Relationship to the Task 2 sync conflict classifier.** This is the *one*
  code that flips a `PendingOperation` into `SyncState.conflict` — see §3's
  updated "Conflict state model". It does so today in a shipped build; it
  simply has nothing to receive it from until a real `SyncTransport` exists.
- **Frontend rule, unchanged and now proven.** Branch on `code` only. The
  generic `resolveProblem()` case for `staleWrite` sets `retryable: false`
  (unlike `conflict`'s `retryable: true`): resubmitting the exact same write
  against the same, now-stale `version` is *guaranteed* to fail the same way
  again, not merely likely to — offering a naive retry button would be
  actively misleading. A feature that can build a `ConflictPresentation`
  must read `problem.code == ProblemCode.staleWrite` at its own call site and
  open `ConflictResolutionPage` instead of ever reaching this generic
  fallback (exactly the existing pattern for `conflict`/`validation`, §2).
- **Naming evidence.** MTM-PRO's reference architecture uses the equivalent
  concept `STALE_WRITE` (its `SCREAMING_SNAKE` convention) for exactly this
  condition — cited as evidence that "stale write" is the right concept name
  and that a backend engineer already reasoned this exact problem
  independently the same way; translated here into this project's own
  already-established lowercase `snake_case` wire convention
  (`ProblemCode.wire`), not copied as code.
- **Deliberately NOT resolved by this decision.** The wire codes for
  *idempotency-key still in progress* (temporary — should map to
  `SyncState.failed`, never `conflict`) and *same-key-different-body /
  invalid idempotency reuse* (a **protocol fault** — the frontend sent a
  changed body under a key already committed to a different body, which
  should never happen if §5.5 below is followed — not a business-level
  version conflict). MTM-PRO evidence treats these as a genuinely different
  outcome from a stale write (a `409` retry-later vs. a `422` key-misuse,
  neither one routed through their `STALE_WRITE` path). Resolving them here
  would require deciding whether MTM-Front-Back's current two-state
  `failed`/`conflict` split needs a third bucket for "permanent client
  protocol fault, not a content conflict, not something a human resolves
  with `useLocal`/`useCurrent`" — a `SyncState` surface change, not a small
  aligned constant, and outside what Task 3 was asked to decide (its
  required decision list names only "the stale-write code"). Left open
  deliberately; **`syncConflictClassifierProvider` must never be extended to
  treat either of these as `stale_write`.**

### 3. Stale-write response contents

**Decision: a justified combination — always a version reference, embed the
current record by default, reference-only as the documented fallback.**

A `409` carrying `code: "stale_write"` MUST also carry, as Problem extension
members:

- `currentVersion` — the entity's authoritative `version` right now (§5.1's
  opaque string).
- `currentRecord` — **by default** — the current authoritative record, using
  the **exact same typed shape the entity's own ordinary read (`GET`)
  endpoint already returns**. Never a bespoke diff/projection shape, never a
  raw/generic map. This is what lets the frontend reuse the *same* `fromJson`
  and the *same* per-domain adapter it already needs for an ordinary read —
  `presentShiftConflict()` already assumes exactly this: two full typed
  `Shift` records to diff, not a pre-computed field list. MTM-PRO evidence:
  its batch-sync conflict result already returns `serverState` inline
  alongside `code: "STALE_WRITE"` for the same reason — handing back current
  state is how the client decides what to do next without a second
  round-trip.
- **Fallback — reference only.** When embedding is not appropriate (the
  payload would be disproportionately large, or the entity's ordinary read
  shape needs authorization context this failure-path response cannot safely
  evaluate), the `409` carries only `currentVersion` plus the entity
  reference the caller already has (`entityType` + `entityId` — already on
  `PendingOperation`, no new resource address needed). The owning feature's
  repository then performs one immediate authenticated follow-up `GET` of the
  canonical endpoint before building `ConflictPresentation` — exactly the
  path `presentShiftConflict`'s "two full typed records" design already
  tolerates.
- **Why not reference-only always (the race this avoids).** A follow-up `GET`
  re-checks authorization independently, which is good — but the record can
  move *again* between the `409` and the `GET`, so the user would end up
  comparing against a third state, not the one that actually caused the
  rejection. Embedding `currentRecord` directly in the `409` response
  captures the exact state that caused it, with no window for a second race.
  The reference-only fallback trades that guarantee away only where embedding
  itself is not appropriate — the two paths are not equivalent, and a future
  integration must not treat them as interchangeable.
- **No dedicated "conflict resource."** Declined. The entity's own existing
  id plus its own existing read endpoint is already a complete reference; a
  new `/conflicts/:id` *backend* resource would duplicate authorization logic
  the entity's endpoint already implements, for no benefit. (`/conflicts/
  :conflictId`, `app_router.dart`, is a **frontend** route only — see §5.4
  for what `conflictId` actually is.)
- **Data minimization / hidden fields.** `currentRecord` (or the follow-up
  `GET`) must use the exact same field allowlist the entity's ordinary read
  already uses — nothing internal, hidden, or newly exposed "because it's a
  conflict." MTM-PRO evidence: raw internal codes, table/column names and
  stack traces must never reach the client, and a server-computed field the
  client never edits (its capacity-ceiling example) stays server-side
  always, conflict response included.
- **Tenant authorization.** The embedded `currentRecord` (or the follow-up
  `GET`) must be authorized exactly as an ordinary read of that entity would
  be — re-derived from the caller's *current* session, never assumed from
  whatever tenant context the original (now-stale) write was made under. See
  §5.7.
- **Response size.** Bounded today by reusing an already-bounded ordinary
  read — this app's current domain models (`Shift`, `TeamMember`, …) carry no
  large or sensitive nested payloads. A future entity whose ordinary read is
  not small/safe enough to embed (a patient record, if that register ships —
  `DATA-NEEDS.md` open decision #4) must use the reference-only fallback for
  *that* entity — a per-domain choice made when that domain adds its own
  conflict adapter, not a blanket rule this document sets in advance.

### 4. Conflict persistence boundary

**Decision: no new store. The existing `PendingOperation` (`state:
conflict`) is the durable conflict record; `conflictId := operationId`; one
new, feature-owned, minimal snapshot is added for offline-later review.**

- **Identity.** `ConflictPresentation.conflictId` and `.localOperationId` are
  set to the **same value** — `PendingOperation.operationId` — for every
  conflict detected on the outbox/sync path. No second identity is minted.
  (The two fields stay distinct in the *type* only for flexibility a future
  non-outbox, live-edit conflict flow might need — the outbox path always
  sets them equal.) This directly answers "conflict identity" and "original
  operation identity" with one fact: they are the same fact, not two facts
  to keep in sync.
- **What is already durable, unchanged.** Entity type + id, and the
  operation's own identity/idempotency key — all already on `PendingOperation`
  (`lib/core/sync/pending_operation.dart`), already persisted by `OutboxStore`
  (§3), already covered by the encrypted-local-storage plan that record
  documents (SQLCipher table `pending_operations`). Nothing about this
  changes.
- **What is newly required (not implemented here): a current-as-of-detection
  snapshot.** `PendingOperation` is deliberately payload-free — the user's
  *local* edit already lives durably in the owning feature's own local write
  path (unchanged, out of scope here). What is missing is the *current*
  (server) side: for `reviewLater` to be reviewable **offline**, later, the
  `currentVersion` / `currentRecord` a `409` response carried at detection
  time (§5.3) must be captured then, because that is the only moment
  connectivity is guaranteed to exist. Requirements for this future piece:
  - **Typed, never raw.** The same per-entity typed model the feature
    already has (e.g. `Shift`), serialized via that model's own existing
    `toJson`/`fromJson` — never a generic JSON blob shared across features.
  - **Feature-owned, not a new generic field on `PendingOperation`.** Mirrors
    the existing payload-free rule: sync/outbox core stays generic, features
    own their own typed data, keyed by the `(entityType, entityId)` (or
    `operationId`) already on the operation.
  - **Encrypted at rest, no exception.** Lives in the same encrypted local
    store (SQLCipher) as the rest of local-first data — never plaintext
    preferences (`DATA-NEEDS.md` §3.3).
  - **Superseded, not accumulated.** A later sync attempt on the same
    operation that returns a newer `409` replaces the stored snapshot; the
    review screen must never show two stacked "current" states.
  - **One lifetime, tied to the operation's.** Deleted the moment the
    conflict is resolved (`useLocal` or `useCurrent`) or the operation is
    otherwise removed from the outbox — never lingers after
    `PendingOperation` itself is gone. `reviewLater` does not delete it —
    that is the entire point of `reviewLater`.
- **What must never be persisted.** Raw server error bodies, stack traces, or
  internal identifiers distinct from the entity's own public id; any other
  user's identity/session details beyond what the entity's ordinary read
  shape already includes (no new "who changed this" field invented for the
  conflict surface specifically).
- **What must never be displayed.** Anything not funneled through a feature's
  typed `ConflictFieldComparison` adapter — already enforced by the Task 1
  screen and its dedicated test (`opaque identities, versions, and backend
  details are not shown`, `conflict_resolution_page_test.dart`); unchanged.
- **Tenant/user scoping.** Implicit in the existing local-storage boundary:
  the outbox/local store is already scoped to the signed-in user's device
  session; `entityType`/`entityId` stay opaque locally, and access is
  re-validated server-side on every actual resolution attempt (§5.7) —
  no new cross-tenant surface is introduced by adding a snapshot next to data
  that is already scoped this way.
- **Removal.** As soon as `useLocal` or `useCurrent` resolves the
  `PendingOperation`, its snapshot is removed with it. If the device is
  wiped or the user signs out, the encrypted store — snapshot included — is
  wiped with it; there is no separate retention timer, matching the existing
  "no frontend 7-day timer" rule for idempotency retention (§3).
- **Explicitly not built here — since built by Task 4 (§7).** The store
  itself (`ConflictReviewStore`), the write-on-classify wiring
  (`ConflictReviewRecorder`) and the UI beyond the quiet Settings count
  (`NeedsReviewPage`) were correctly out of Task 3's scope and are now
  implemented, to these exact rules. What Task 4 could *not* build, because
  it depends on a real `409` body that no transport can produce, is the
  per-feature capture of the current record itself: the composer seam exists
  and is empty. See §7.

### 5. Resolution protocol and idempotency

**Decision: `useLocal` resolves as a new logical operation that references
the original; it never resends the original's idempotency key with a
changed body. `useCurrent` sends nothing.**

Both were documented-only when Task 3 wrote this decision. The Task 4
corrective pass implements the local half of both: `useLocal`'s new-operation
protocol (`OutboxController.supersedeConflict`, points 1–4 below) and
`useCurrent`'s "apply the current record locally before it counts as
abandoned" step this section's own text below already implies but the
original Task 4 pass never built. Neither sends anything over a wire — that
half stays exactly as undecided-in-code as before; see §7 for what changed
and where.

- **The tension, stated precisely.** `PendingOperation.idempotencyKey` is
  minted once and never regenerated for the *life of one logical write*
  (§3). A `useLocal` decision, by definition, wants to resubmit the user's
  edit — but against the *current* `version` (§5.1), not the stale
  `baseVersion` the original operation was minted against. That is a
  **different request body** (the `version` field differs). Resending a
  different body under an idempotency key already committed to the original
  body is exactly the "same key, different body" protocol fault §5.2
  deliberately left open as a *separate*, undesirable outcome — so naively
  requeuing the original operation and letting the ordinary retry loop
  resend it (today's `OutboxController.requeueAfterConflict` behaviour) would
  risk hitting that fault, or worse, looping (`stale_write` again →
  `useLocal` again → same fault again) once a real transport exists.
- **Decision: `useLocal` mints a new logical operation.** When the user picks
  **استخدام تعديلي**, a future integration must:
  1. Mint a **new** `PendingOperation` — new `operationId`, new
     `idempotencyKey` (via the existing, unchanged `enqueue`/`PendingOperation.
     create` path, §3) — because its body genuinely differs (it carries
     `version: <currentVersion>` from `ConflictResolutionDecision.
     currentVersion`, already threaded through the Task 1 model). This is a
     **new logical write, not a retry of the stale one** — stated explicitly
     so nothing downstream mistakes it for a replay.
  2. Set a reference field on the new operation back to the original —
     e.g. `resolvesOperationId: <original operationId>` — so a backend/audit
     log can stitch "this write resolves that conflict" together (§5.7). This
     is additive to `PendingOperation`, not implemented in this task.
  3. **Create-then-retire, never retire-then-create.** The new operation must
     be durably stored *before* the original conflicted operation is
     removed. If minting the new operation fails (e.g. a local-storage
     write error) before that happens, the original conflicted operation
     must still be exactly where it was — `SyncState.conflict`, unresolved,
     ready to be tried again. This is what "a failed resolution request
     cannot silently lose the original local work" means concretely: the
     local edit was already durable (payload-free rule, unchanged); this
     rule protects the *operation record*, not the edit itself.
  4. Only once the new operation is durably stored does the original get
     retired (removed from the outbox) — its identity is not deleted
     silently; it is superseded by an operation that explicitly names it.
- **Why this does not violate same-key/same-body rules.** There is no hazard
  to violate: the new operation's key was never used for any other body. It
  is exactly as new and exactly as single-use as any other `enqueue`d
  operation (§3's identity rule is completely unchanged — this is a new
  instance of that rule, not an exception to it).
- **Repeated resolution submissions stay idempotent.** The new operation's
  key is minted once, at the moment the decision is made, and reused for any
  of *its own* retries — ordinary `PendingOperation` idempotency applies to
  it unchanged. A human physically resubmitting the same decision twice (a
  double-tap) is a UI-level concern already closed by the Task 1 screen's
  `_saving`/`_allowPop` guard (§4, "How unresolved conflicts are preserved")
  — the wire layer does not need a second dedup mechanism for that case.
- **If the resolution write itself comes back stale again.** Expected and
  correct, not an edge case to special-case: a `reviewLater` conflict
  reviewed much later, or a slow resolution push, can race a third edit. The
  new operation's push then returns `stale_write` exactly like any other
  push, and is classified into `SyncState.conflict` exactly the same way —
  the user reviews again, with a freshly fetched/embedded current record.
  No special-casing is needed because the resolution operation is, by
  design, just an ordinary `PendingOperation` with an extra reference field.
- **`useCurrent` sends nothing, by design.** The user is explicitly choosing
  to abandon their local edit in favour of the shared state — there is
  nothing to submit. `OutboxController.discardConflict` (§3) already does
  exactly this: remove the operation, no transport contact, no claimed
  server outcome. "Durably applied" for `useCurrent` means only: the local
  discard is written to the encrypted outbox store before the operation is
  considered gone — already true (`_store.remove` is awaited before
  `_reload`).
- **Failure behaviour, restated as a rule.** A failed *local* step (steps 1–4
  above) must never leave the user with neither the original conflicted
  operation nor a working replacement — create-then-retire (above) is the
  whole of this rule. A failed *wire* push of the new operation is not
  data loss either way: it is an ordinary `PendingOperation` failure,
  `SyncState.failed`, retried by the ordinary loop like any other pending
  write (§3) — nothing about being a resolution operation changes that.
- **What is explicitly NOT changed by this decision.** Today's
  `OutboxController.requeueAfterConflict` keeps reusing the same
  `operationId`/`idempotencyKey` (§3, §4 already document this). That
  remains **correct today** only because `OfflineSyncTransport` never
  actually sends anything — there is no wire body to be "different" yet.
  It becomes the wrong implementation the moment a real `SyncTransport`
  exists, per the decision above; **fixing it is a concrete future frontend
  task, not done in Task 3** (`Explicitly forbidden` — "do not implement
  resolution requests").

### 6. Meaning of the three frontend intents

Restated precisely now that §5.5 exists (semantics themselves are unchanged
from Task 1/2 — this section removes any remaining ambiguity about *when* a
decision counts as applied):

- **`useLocal`** — "resubmit my edit against the record as it stands now."
  Never overwrites newer state without server validation: it is a brand-new
  versioned write (§5.5) that the server itself will reject as `stale_write`
  again if the record moved a fourth time — the frontend never assumes its
  own resubmission will succeed.
- **`useCurrent`** — "abandon my edit, keep the shared version." Abandons the
  local mutation only once the discard is durably applied locally (§5.5) —
  not merely tapped, not merely animated off-screen. No server contact,
  because there is nothing left to tell it.
- **`reviewLater`** — "decide nothing yet." Strictly local-only, leaves the
  conflict exactly as `SyncState.conflict`, unresolved, retained per §5.4's
  persistence rules until a later `useLocal`/`useCurrent`. Never expires on
  its own (§3's "no frontend 7-day timer" rule, restated for conflicts).
- **No generic merge, still.** `ConflictResolutionIntent` still has no
  `merge` value (§4's "Chosen design" is unchanged). A feature may add its
  own domain-owned merge flow only once that domain defines safe merge
  semantics for itself — nothing in §5 changes this or adds a shared merge
  engine.
- **Failure behaviour** is §5.5's create-then-retire rule: a failed
  resolution request cannot silently lose the original local work, in either
  direction (`useLocal` or `useCurrent`).

### 7. Authorization and privacy

Backend responsibilities (none implemented here; MTM-PRO evidence cited
where it directly shaped the requirement):

- **Reauthorization at resolution time.** A resolution write (§5.5) is an
  ordinary authenticated request — same bearer token flow as any other
  write, no special step. Because it is a genuinely new logical operation,
  ordinary token-expiry/refresh handling applies unchanged: if the access
  token expired while the conflict sat unresolved, the existing
  `authentication_expired` flow (§2) triggers before the resolution write is
  ever attempted. Nothing about conflict resolution bypasses re-auth.
- **Tenant/org isolation.** The resolution request must be authorized against
  the entity's **current** tenant/detachment scope, re-derived from the
  verified session at resolution time — **never** trusted from anything
  cached in the local conflict snapshot (§5.4). MTM-PRO evidence: tenant id
  is read only from the verified server-side JWT, never header/body/query;
  the same rule applies here to whatever tenant context a stale local
  snapshot implies. This defends specifically against a conflict cached
  while a record belonged to tenant A, resolved after the record's ownership
  changed.
- **Viewing both versions.** Permitted only if the user's **current**
  capabilities still grant read access to the entity — re-checked when the
  conflict is opened, not assumed from when it was created. If access was
  revoked in the meantime, the existing `ConflictUnavailablePage` (§4, "no
  data / stale deep link" fallback) is the correct surface — its purpose
  already covers "nothing safe to render here," so an access-revoked
  conflict is the same case, not a new one.
- **Auditability.** Backend-owned: record who resolved a conflict, which
  intent, old `version`, new `version`, and a timestamp. The client's only
  obligation is to make this reconstructable — the new operation's
  `resolvesOperationId` reference (§5.5) is exactly what lets a backend
  audit log stitch "this write resolves that conflict" together. MTM-PRO
  evidence: its audit trail is append-only and hash-chained specifically so
  an overwrite/accept-current decision cannot be quietly edited out after
  the fact — cited as the standard this kind of decision should be held to,
  not as something the frontend implements.
- **No disclosure of hidden/internal fields.** Unchanged from §5.3/§4: the
  generic screen only ever renders what a feature's typed adapter explicitly
  produced (`ConflictFieldComparison`) — already tested
  (`conflict_resolution_page_test.dart`, "opaque identities, versions, and
  backend details are not shown").
- **Sensitive/medical data on generic surfaces.** No patient-record adapter
  exists yet (`DATA-NEEDS.md` open decision #4 — the patient register is not
  in scope). If one is ever built, it must follow the exact same allowlist
  pattern as `presentShiftConflict` and must **never** diff or display a
  field that requires encryption at rest — MTM-PRO evidence marks its
  closest analogue (`patients.condition`) as always encrypted and never
  raw-comparable; a conflict adapter for such a field would need its own,
  explicit, feature-owned decision about whether/how to show that a field
  differs without showing its value — out of scope until that domain exists.
- **Safe diagnostic logging.** Unchanged rule (§2): never log tokens, raw
  request/response bodies, SQL errors, stack traces, or internal hostnames.
  `PendingOperation.lastProblemCode` already stores only the wire *code*,
  never `detail` — the same discipline extends to `stale_write` and to
  whatever logs a future resolution attempt, with no new exception carved
  out for this path.

### 8. Auto Sync and Manual Sync

**Confirmed, not changed — already implemented and tested (§3/§4).**

- Auto Sync: a classified conflict → persists `SyncState.conflict` → exposes
  the quiet Settings attention count → **never navigates** → the user keeps
  working uninterrupted → resolved later, by the user, on their own terms.
  Structurally guaranteed, not just conventionally true:
  `SyncScheduler`/`SyncCoordinator` hold no reference to `GoRouter`, `context`,
  or any navigator — proven against a real `GoRouter` instance by
  `test/core/sync/auto_sync_no_navigation_test.dart`.
- Manual Sync: may expose a count and a review action, but must **not**
  force-open every conflict — `SyncSettingsSection`'s `_ConflictAttentionRow`
  already shows only a count, deliberately with no tap action yet (§3,
  "Settings changes" — building a tap to nowhere honest was rejected there
  and remains rejected here).
- Both paths run the **same** `SyncCoordinator` over the **same**
  `outboxProvider` — unchanged, and nothing in §5 introduces a second engine
  or a second queue.

### 9. Shift product context

- Each shift normally has one responsible admin/owner, and Leader is not a
  real-time collaborative document editor — so a genuine two-writer race on
  the *same* shift field is expected to be **uncommon** in practice.
- Optimistic concurrency (this whole section) remains required regardless,
  for exactly the cases uncommon-but-real: the same admin signed in on a
  second device, a Main Admin correcting a shift a detachment lead already
  edited, an old offline copy resurfacing after days away from connectivity,
  or two sessions genuinely overlapping by chance. Rarity is not a reason to
  weaken the mechanism — it is the reason the mechanism can stay simple
  (§5.1's plain `version`, no CRDT, no field-level merge).
- **Scope boundary within "shift," evidenced by MTM-PRO.** This contract
  covers ordinary field edits — exactly `presentShiftConflict`'s existing
  diff set (manager, date, time, `needed`) — where two edits raced on the
  *same record*. It does **not** cover shift double-booking/overlap
  (`SHIFT_OVERLAP`), which MTM-PRO's evidence resolves through a completely
  different mechanism (a database exclusion constraint, surfaced as its own
  domain code) and which `FRONTEND-BACKEND-INTEGRATION.md` §2's table
  already lists as a separate, feature-owned code unrelated to `version`.
  The two must not be conflated: a shift can be `stale_write`-conflicted
  without being overlap-conflicted, and vice versa.
- **Inventory movements are out of scope by construction**, not by
  oversight — see §5.1's append-only exclusion.

### Frontend integration points (for whoever implements this next)

| Concern | Symbol / file | State after Task 3 |
|---|---|---|
| The agreed stale-write code | `ProblemCode.staleWrite` — `lib/core/problem/problem.dart` | Implemented |
| Generic (non-adapter) presentation | `resolveProblem()` case + `S.errStaleWriteTitle`/`S.errStaleWrite` — `problem_presentation.dart`, `strings.dart` | Implemented |
| Classifier | `defaultSyncConflictClassifier` — `lib/core/sync/sync_conflict_classifier.dart` | Implemented, inert without a real transport |
| `version` field on domain models | e.g. a future `Shift.version` | Not implemented — decided shape only (§5.1) |
| `409 stale_write` body shape (`currentVersion`/`currentRecord`) | future repository JSON mapping | Not implemented — decided shape only (§5.3) |
| Current-as-of-detection snapshot store | Shift: `ShiftConflictSnapshotStore`/`InMemoryShiftConflictSnapshotStore` — `lib/features/shift/domain/shift_conflict_snapshot.dart`, `lib/features/shift/data/in_memory_shift_conflict_snapshot_store.dart` | Requirements decided here (§5.4); representative in-memory implementation built by the Task 4 corrective pass — see §7. Still object-lifetime only, still empty in a shipped build (no real transport ever populates it) |
| Resolution operation (`resolvesOperationId`, new key) | `PendingOperation.resolvesOperationId`/`.currentVersion` + `OutboxController.supersedeConflict` — `lib/core/sync/pending_operation.dart`, `lib/core/sync/outbox_controller.dart` | **Implemented by the Task 4 corrective pass** (§7) — `useLocal` now mints the new operation this section decided, create-then-retire, instead of reusing the original identity. `OutboxController.requeueAfterConflict` still exists as a separate, narrower primitive (a same-body retry) but the conflict-resolution flow no longer calls it — see §7 |

### Explicitly out of scope (this section)

No backend API, no server-side optimistic concurrency, no database
constraint, no server `409` generation, no backend merge logic, no real
`/sync`, no cursors, no tombstones, no backend persistence, no server audit
infrastructure, no generic merge engine, no resolution networking. All of the
above are future implementation tasks this section gives enough contract to
start without guessing. The Needs Review inbox and the `useLocal`
new-operation wiring **were** out of scope for Task 3 specifically — both are
now built; see §7 for what changed and exactly how.

---

## §6 — Attendance Edit Window + Append-Only Corrections (Task 5)

### Feature

A regular/sub-Admin (`shift.attendance.record`) may record or edit a shift's
attendance for **one hour after the shift ends**. After that, ordinary
editing is read-only. A Main Admin (`shift.attendance.override`) may still
change attendance with no lifetime limit — but only by **appending an
immutable, reasoned correction**, never by silently overwriting the original
entry. Both capabilities use the exact same ordinary controls while the
window is open; there is no separate "admin edit" path during that hour.

### Evidence the one-hour boundary was built from

Not a new decision — carried verbatim from an already-decided, already-tested
rule, cited in full because a backend developer implementing the same check
server-side needs to reproduce the same boundary exactly:

- `medical_team/lib/features/detachments/data/attendance_lock.dart`
  (`attendanceGracePeriod = Duration(hours: 1)`, `resolveAttendanceLock`) —
  the executable legacy source of truth, with its own boundary test suite
  (`attendance_lock_test.dart`) pinning `open` at `shiftEnd + 0:59:59` and
  `locked` at exactly `shiftEnd + 1:00:00`, plus overnight-shift and
  corrupt-stored-time cases.
- `LEGACY-EXTRACTION-REPORT.md` (D-16): "once a date's shift end time plus a
  one hour grace period has passed, that date's attendance becomes
  read-only."
- `CAPABILITIES.md` and `core/access/capability.dart`: `shift.attendance.record`
  is scoped to "inside the one-hour window"; `shift.attendance.override` is
  scoped to "after the one-hour lock" — both already written before this
  task, reaffirming the same boundary.
- `CAPABILITIES-REPORT.md`: cites "your legacy owner decision of 2026-07-10"
  as the reason the two capabilities were split apart at all.

**One deliberate divergence, flagged rather than silently applied:**
MTM-PRO (`/home/ahmed/Documents/Python-Files/flutter/apps/MTM-PRO`,
read-only reference, a different project) designed its own three-layer
scheme for its own unbuilt backend — 1-hour self-grace, then a *second*,
longer (7-day) `recordAttendance`-gated window, then permanent
override-only correction. This task's product-owner decisions (given
directly, not open for interpretation) specify only **two** layers: the
one-hour ordinary window, then permanent override authority. The middle
7-day layer is **not** implemented here — it would contradict an explicit
instruction. If a backend developer has separately inherited MTM-PRO's
three-layer design, that is a conflict to resolve with the product owner,
not something this frontend silently reconciled one way or the other.

### Frontend status

Implemented against the mock. `lib/features/shift/domain/attendance_policy.dart`
holds the pure policy (`AttendanceWindow`, `AttendanceEditMode`,
`resolveAttendanceEditMode`) — no `DateTime.now()` inside it; every boundary
takes `now` as an argument, so it is exercised deterministically in
`test/features/shift/attendance_policy_test.dart` without depending on the
wall clock. `lib/features/shift/domain/attendance_correction.dart` holds the
append-only model (`AttendanceCorrection`, `AttendanceSnapshot`,
`AttendanceCorrectionAuthor`, `normalizeCorrectionReason`).
`MockShiftRepository` enforces the window on the four ordinary mutation
methods and implements the indefinite `addAttendanceCorrection` method
(`lib/features/shift/data/mock_shift_repository.dart`). The attendance sheet
(`showAttendanceSheet`/`_AttendanceBody`,
`lib/features/shift/presentation/shift_assign_sheet.dart`) renders one of
three modes and the correction form + history section.

### Backend responsibility

- **Enforce the window server-side, using server time.** The frontend's
  `AttendanceWindow` check is a UX convenience exactly like every other
  capability check in this app (`CAPABILITIES.md` §0,
  `core/access/capability.dart`'s security contract) — it is **not** a
  security boundary. A modified client can call the ordinary
  check-in/check-out/absent/reset endpoints after the window has closed;
  only a server-side check using its own clock, not a client-supplied
  timestamp, actually prevents that.
- **Enforce `shift.attendance.override` on the correction endpoint.** The
  mock does not check capabilities at all (no repository method in this
  codebase receives a capability today — see `core/access/capability_guard.dart`'s
  own TODO); the real backend must reject a correction from a bearer that
  does not hold `shift.attendance.override` in the shift's detachment.
- **Never allow a correction to mutate or delete an earlier one.** There is
  intentionally no `PATCH`/`DELETE` on the corrections resource in
  `API_CONTRACT.md` §"ShiftRepository.addAttendanceCorrection" — only
  `POST`, which always appends.
- **Reject a blank reason, never silently accept a placeholder.** Matches
  `normalizeCorrectionReason`'s own contract: trim, collapse internal
  whitespace, and if the result is empty, fail `validation` — the client
  already refuses to call the endpoint with a blank reason, but the backend
  must not trust that.
- **Stamp its own `correctedAt`** (server time) rather than trusting the
  client-supplied value for the authoritative audit record, per the same
  "server time, not device time" reasoning §5.1 already established for
  `version`.

### Expected request / response

See `API_CONTRACT.md` — `ShiftRepository.markAttendance` (now documents the
window) and the new `ShiftRepository.addAttendanceCorrection`, plus the
`Shift.corrections` field added to the `Shift` JSON shape.

### Frontend reaction

- **Ordinary path, window open** (`AttendanceEditMode.ordinary`): identical
  behaviour to before this task — `recordCheckIn`/`recordCheckOut`/
  `markAbsent`/`resetAttendance`, all through the existing controls. A
  denied attempt (window closed between render and tap — a narrow race) shows
  the mock's `attendance_window_expired` failure message inline, through the
  same generic `Failure` handling every other repository error already uses;
  no special-casing was needed.
- **Correction-only** (`AttendanceEditMode.correctionOnly`, window closed +
  override held): the ordinary controls are replaced by "إضافة تصحيح". The
  form collects a target status, optional corrected check-in/check-out, and
  a required reason; saving calls `addAttendanceCorrection` and, on success,
  updates the sheet's local view of the shift from the response directly
  (see "Mock status" below for why this is a local-state update, not a
  provider watch).
- **Read-only** (`AttendanceEditMode.readOnly`, window closed, no override):
  the current attendance is shown with `S.attendanceWindowClosedOrdinary`
  ("the ordinary edit window has closed...") and no mutation control at all.
- **Correction history**: always shown once `mode != ordinary`, or whenever
  at least one correction already exists (so a Main Admin editing during the
  still-open window can still see prior corrections). Each entry shows the
  corrector's display name (never `AttendanceCorrectionAuthor.id`), the
  timestamp, the reason, and the before/after attendance — newest first.

### Required data

`Shift.corrections: List<AttendanceCorrection>` (oldest-first in the model;
the UI reverses it for display). `AttendanceCorrection`: `id`, `shiftId`,
`memberId`, `before`/`after` (`AttendanceSnapshot` — `status`, `checkInAt`,
`checkOutAt`), `reason`, `author` (`AttendanceCorrectionAuthor` — `id`,
`displayName`), `correctedAt`. All typed and JSON round-trippable
(`fromJson`/`toJson` on every model) — no `Map<String, dynamic>` reaches the
UI.

### Integration point

`ShiftRepository.addAttendanceCorrection` (abstract method,
`lib/features/shift/domain/shift_repository.dart`) is the seam: a real
implementation replaces `MockShiftRepository`'s in-memory append with a
network call to `POST .../attendance-corrections` and returns the server's
updated `Shift` (with its server-computed `corrections` and effective
attendance) the same way every other repository method already does through
`Result<Shift>`. The window check inside `MockShiftRepository._updateAttendance`
is mock-only scaffolding — a real repository's ordinary methods should let
the server's `409`/`403` (whatever wire shape is agreed — see "Open
decisions" below) flow through as an ordinary `Failure`, the same as any
other rejected write.

### Mock status

- `MockShiftRepository` gained an injectable `clock` constructor parameter
  (`DateTime Function()?`, defaulting to `DateTime.now`) — the same pattern
  already used by `PendingOperation.create` and `UuidV7` — so the window
  check is deterministic in tests without scattering `DateTime.now()` calls.
  Production wiring (`shiftRepositoryProvider`) passes nothing and gets the
  real clock.
- The correction endpoint never checks the window itself (only reason
  validation, shift/member existence, and the checkout-before-checkin rule)
  — matching "permit indefinite override only through the explicit override
  method."
- The attendance sheet does **not** watch a Riverpod provider for its
  "live" correction history — it takes the `Shift` the caller already
  passed it (freshly re-read by the parent manage sheet each time it opens)
  and, after a successful correction, updates its own local copy from that
  call's own `Success` result. This was a deliberate simplification after
  discovering that watching `shiftByIdProvider` from inside the sheet
  introduces an async fetch (the mock's own artificial latency) with no
  benefit the local update does not already provide, and that latency is
  exactly the kind of thing a widget test can leave pending if it never
  explicitly settles it.

### Local-first / offline behaviour

**Deferred, not integrated with the outbox** — a deliberate, evidenced
choice, not an oversight. `core/sync/pending_operation.dart`'s own docstring
names `shift.attendance.mark` as an illustrative `kind` string, but grepping
`lib/features/` for `OutboxController`/`PendingOperation.create` turns up
**zero** call sites anywhere in the app today — no feature, shift attendance
included, currently enqueues a mutation into the outbox; every repository
write (ordinary or correction) goes straight through
`ShiftRepository`/`Result`, exactly as it already did before this task. Per
this task's own fallback instruction ("if extending the outbox would require
a partial payload architecture or destabilize the sync foundation, keep a
clean repository seam and document the deferred integration instead"): the
repository method (`addAttendanceCorrection`) is already the clean seam a
future outbox integration would call before or instead of the direct
network write — no client code outside `MockShiftRepository` needs to change
for that to happen. Local save still happens first from the user's
perspective (the mock's write is synchronous-to-the-UI, matching "local
save first → user continues → synchronization later"); what is missing is
only the *durable-across-restart, retried-on-reconnect* half the outbox
would add, same as every other shift mutation today.

### Privacy / security handling

- `AttendanceCorrectionAuthor.id` is captured (for internal traceability —
  matches `AuthUser.id`) but **never rendered**; only `.displayName` reaches
  any widget. Verified in `test/features/shift/attendance_correction_sheet_test.dart`
  (`find.textContaining(_authorId)` asserts `findsNothing`, alongside a
  distinct-from-name email that also must not leak).
- Client capability checks (`Cap.shiftAttendanceRecord`/`Override`) are UX
  gates only, per this app's existing, already-documented security contract
  (`core/access/capability.dart`'s header comment) — restated above under
  "Backend responsibility" because a correction/audit feature is exactly the
  kind of surface where skipping server-side enforcement would be a real
  security gap, not just a cosmetic one.
- No new local-storage exposure: corrections live inside the same `Shift`
  object every other attendance field already lives in, which is already
  covered by `DATA-NEEDS.md` §3.3 (no attendance data is currently in the
  "must never reach local storage" category — it is operational data, not a
  credential).

### `Backend contract decision required`

1. **The wire failure code for a denied ordinary edit after the window has
   closed.** The frontend mock uses a local string constant
   (`attendanceWindowExpiredCode = 'attendance_window_expired'`,
   `lib/features/shift/domain/attendance_policy.dart`) following this
   codebase's existing lightweight `Failure(message, code: '...')`
   convention (`mock_shift_repository.dart` already uses `not_found`,
   `conflict`, `validation`, etc. the same way) — no feature in this app has
   adopted the newer `ProblemCode` enum yet (§2), so this was not forced
   into that model either. A backend developer should either confirm this
   exact wire string, or supply the real one and this file's constant (and
   the one call site of it) update to match — no other frontend code depends
   on its exact spelling, only on it being distinct from every other shift
   failure code.

### Explicitly out of scope (this section)

No backend API, no database constraint enforcing the window or the
append-only rule server-side, no server-side audit persistence, no real
`/sync` integration for attendance corrections (see "Local-first / offline
behaviour" above), no Needs-Review inbox, no change to Task 4 (shift
swap/cover requests — not started).

---

## §7 — Needs Review Inbox + Durable Conflict Review Foundation (Task 4)

### Feature

The user-facing review loop for conflicts that are already classified. A
field worker can now: see that changes need review, **explicitly** open a
Needs Review list, pick a conflict, inspect the §4 differences-first screen,
choose `useLocal` / `useCurrent` / `reviewLater`, and come back without
losing unresolved work.

Frontend only. No backend, no `/sync`, no transport, no merge engine, and —
importantly — **no fabricated conflict**. Nothing in the shipped app can
produce a `stale_write`, so the inbox is empty in production by construction,
not by a flag.

**Corrective pass (2026-09-05).** The original Task 4 session left three
things short of what §5 and this section's own prompt required — a
`useLocal` that requeued the original operation under its unchanged identity
(contradicting §5.5), a `useCurrent` that dropped the pending write without
ever applying the chosen current record to local state, and an empty,
unregistered Shift composer that made the "representative typed path" claim
untrue. This section now describes the corrected, current behaviour; see
"What changed in the corrective pass" below for exactly what moved and why.

### The background contract this completes

Auto Sync's behaviour on a conflict is unchanged in every respect that
matters, with one step added in the middle:

```text
detect conflict
→ preserve operation        (SyncState.conflict, same operationId/idempotencyKey)
→ store safe review metadata   ← added by Task 4
→ update quiet attention count (conflictOperationsCountProvider)
→ do not navigate
→ user continues field work
```

`SyncCoordinator` calls `conflictReviewRecorderProvider` immediately after
the operation is durably `conflict`. That hook is **best-effort by design**:
the conflict is already preserved and already counted before it runs, so a
recorder that returns nothing, or throws, cannot abort the sync run, cannot
change the outcome, and cannot lose the user's work — it only costs the
inbox its detail rows. Tested in
`test/features/conflict/needs_review_inbox_test.dart`.

### What was built

| Piece | File | Role |
|---|---|---|
| `ConflictReviewEntry` | `features/conflict/domain/conflict_review_entry.dart` | The durable, safe review metadata for one conflict; JSON round-trip; rebuilds the §4 `ConflictPresentation` |
| `ConflictReviewStore` | `features/conflict/domain/conflict_review_store.dart` | The persistence seam (encrypted DB in a shipping build) |
| `InMemoryConflictReviewStore` | `features/conflict/data/in_memory_conflict_review_store.dart` | MOCK — object-lifetime only, same limitation as `InMemoryOutboxStore` |
| `ConflictReviewController` | `features/conflict/data/conflict_review_controller.dart` | `AsyncNotifier` over the store; `record` / `forget` |
| `needsReviewItemsProvider` | same file | The outbox × store join the inbox renders |
| `ConflictReviewRecorder` | `core/sync/conflict_review_recorder.dart` | The core hook, defaulting to a no-op so `core/sync` never imports a feature |
| `ConflictReviewComposer` | `features/conflict/data/conflict_review_recording.dart` | The per-feature seam that builds an entry at detection time — default registry **empty**; the real Shift entry is installed at the composition root (see below) |
| `NeedsReviewPage` | `features/conflict/presentation/needs_review_page.dart` | The list, at root route `/needs-review`; retry reloads both `outboxProvider` and `conflictReviewProvider` (corrective pass — either one can be the source that failed) |
| `OutboxController.supersedeConflict` | `core/sync/outbox_controller.dart` | **Corrective pass.** §5.5's `useLocal` protocol: mints a new `PendingOperation` (new `operationId`/`idempotencyKey`, `resolvesOperationId` pointing at the original, `currentVersion` carrying the concurrency token forward) and stores it before retiring the original — never the reverse. Idempotent against repeated submission |
| `PendingOperation.resolvesOperationId` / `.currentVersion` | `core/sync/pending_operation.dart` | **Corrective pass.** The minimal typed extension §5.5 asked for. Both optional, both absent from JSON when unset, so an operation serialized before this pair existed still decodes safely |
| `ConflictCurrentApplier` / `conflictCurrentAppliersProvider` | `features/conflict/data/conflict_current_application.dart` | **Corrective pass.** The feature-owned `useCurrent` seam: applies the typed current snapshot to the owning feature's local repository, returning whether it actually succeeded. Same empty-default-registry pattern as `ConflictReviewComposer`. Deliberately does not also remove the snapshot — see `ConflictSnapshotCleaner` |
| `ConflictSnapshotCleaner` / `conflictSnapshotCleanersProvider` | `features/conflict/data/conflict_current_application.dart` | **Final narrow correction.** Removes a feature-owned snapshot only after the outbox resolution that consumed it (`useLocal` or `useCurrent`) has already succeeded — a separate, later step from applying it, so a failed outbox retirement never destroys the snapshot a retry would need |
| `ShiftConflictSnapshot` / `ShiftConflictSnapshotStore` / `InMemoryShiftConflictSnapshotStore` | `features/shift/domain/shift_conflict_snapshot.dart`, `features/shift/data/in_memory_shift_conflict_snapshot_store.dart` | **Corrective pass.** The Shift-owned, typed current-as-of-detection snapshot §5.4 specified — an ordinary `Shift`, keyed by `conflictId`; in-memory, object-lifetime only |
| `composeShiftConflictReview` / `applyShiftConflictCurrentVersion` / `clearShiftConflictSnapshot` / `shiftConflictReviewOverrides` | `features/shift/data/shift_conflict_review.dart` | **Corrective pass, cleaner added by the final narrow correction.** The representative Shift composer/applier/cleaner, reusing `presentShiftConflict`; installed over the empty defaults by `main.dart` alongside `conflictReviewOverrides` |

### Decisions worth recording

- **The outbox stays the single source of truth for *what* needs review.**
  The inbox is derived from `SyncState.conflict` operations and only *joined*
  with stored metadata, never driven by it. Two consequences are load-bearing:
  the list length always equals `conflictOperationsCountProvider` (so the
  Settings count and the list behind it cannot drift), and a stored entry
  whose operation is gone is simply never joined, so a resolved conflict can
  never reappear even if its entry outlived it.
- **A conflict with no metadata is listed, not hidden.** The user's work
  really is waiting, so hiding the row would be the dishonest option. The row
  says the details are not available on this device, states plainly that the
  change is not lost, and is deliberately **not** tappable: offering
  "استخدام تعديلي" / "استخدام النسخة الحالية" with nothing to compare would
  be asking for an uninformed, irreversible choice.
- **No raw tag ever reaches the screen.** `PendingOperation.kind` /
  `entityType` are frontend-owned grouping metadata, not product copy.
  `needsReviewRecordLabel` maps them to Arabic, with a safe generic answer
  for anything unmapped, so a future feature's operations degrade to
  "تغيير غير مزامن" rather than leaking their tag. A dedicated test asserts
  no operation id, idempotency key or wire tag is rendered.
- **Entry lifetime is the operation's lifetime** (§5.4). `useLocal` and
  `useCurrent` forget the entry after the outbox change lands; `reviewLater`
  forgets nothing, which is exactly why the row is still there on the way
  back out.
- **Composition-root wiring, not a core→feature import.** `core/sync` ships
  the no-op recorder; `main.dart` installs the real one via
  `conflictReviewOverrides`, and — since the corrective pass — the real
  Shift composer/applier via `shiftConflictReviewOverrides`. Core sync still
  knows nothing about any feature, and `features/conflict` still knows
  nothing about Shift.

### What changed in the corrective pass

- **`useLocal` mints a new operation; it no longer requeues the original.**
  `conflict_outbox_resolver.dart`'s `applyConflictResolution` now calls
  `OutboxController.supersedeConflict`, not `requeueAfterConflict`. Ordering
  is create-then-retire: the replacement is durably stored first; only once
  that succeeds is the original removed; only once *that* succeeds is the
  stored `ConflictReviewEntry` forgotten. A failure at any step leaves the
  original conflict — identity, state, and review metadata — exactly where
  it was; a failure retiring the original after the replacement is already
  stored leaves both operations on file, never neither. Repeated submission
  (a resumed app, a retried decision) is idempotent: a second call finds the
  existing replacement by `resolvesOperationId` and mints nothing new.
  `OutboxController.requeueAfterConflict` still exists — it is the correct
  primitive for a same-body retry, which `useLocal` is not — but nothing in
  the conflict-resolution path calls it anymore.
- **`useCurrent` applies the current record locally before it retires
  anything.** §5.5's own text already implied this ("durably applied…the
  local discard is written…before the operation is considered gone") but the
  original Task 4 pass only ever removed the pending operation — the user's
  local repository still showed their stale edit even after choosing to
  abandon it. `applyConflictResolution` now looks up the owning feature's
  registered `ConflictCurrentApplier`, awaits it, and only proceeds to
  `OutboxController.discardConflict` (then forgets the review entry) if it
  returned `true`. A missing applier, a missing snapshot, or a failed
  repository write all resolve to the same `false` → the decision throws,
  the operation and its metadata are untouched, and
  `ConflictResolutionPage`'s existing failure handling (§4) keeps the screen
  open with `S.conflictDecisionFailed` — nothing new needed there.
- **The Shift composer and applier are registered in the shipped app**, not
  merely defined. `main.dart` applies `shiftConflictReviewOverrides` next to
  `conflictReviewOverrides`, so `conflictReviewComposersProvider['shift']`
  and `conflictCurrentAppliersProvider['shift']` are real, working functions
  in production — they simply have nothing to do yet, because
  `ShiftConflictSnapshotStore` starts empty and no real transport ever
  writes to it (see below). This is what makes "the registered production
  Shift adapter can consume a supplied mocked/future typed snapshot" true
  today, provable without a real backend: seed the snapshot store, and the
  composer/applier work exactly as they will once a transport does the
  seeding.
- **One source of truth, restated for the new pieces.** Neither
  `ShiftConflictSnapshotStore` nor `conflictCurrentAppliersProvider` is a
  second "needs review" queue. Both are only ever consulted for an
  `operationId` the outbox still lists as `SyncState.conflict`. **Corrected
  by the final narrow correction below:** a resolved conflict's snapshot is
  no longer merely left inert — it is actively removed once resolution
  succeeds, through `ConflictSnapshotCleaner`.

### Final narrow correction (2026-09-05) — snapshot cleanup ordering and validation

Two ordering bugs and two missing validations survived the corrective pass
above; this is the fix, described completely rather than duplicated in
"What changed" above:

- **The applier applies; it does not clean up.**
  `applyShiftConflictCurrentVersion` used to delete its own
  `ShiftConflictSnapshot` the moment `ShiftRepository.update` succeeded —
  before `applyConflictResolution` had actually retired the outbox
  operation. If that retirement then failed, the snapshot needed to retry
  was already gone. It now only reads and applies, returning `true`/`false`;
  it never touches the snapshot store.
- **Cleanup is a new, separate seam, run only after outbox resolution
  succeeds.** `ConflictCurrentApplier`'s sibling
  `ConflictSnapshotCleaner`/`conflictSnapshotCleanersProvider`
  (`features/conflict/data/conflict_current_application.dart`) is the same
  empty-by-default, per-`entityType`, composition-root-registered seam as
  the composer/applier. `applyConflictResolution` invokes the registered
  cleaner **last**, in both branches: after `supersedeConflict` succeeds and
  the review entry is forgotten (`useLocal`), and after `discardConflict`
  succeeds and the review entry is forgotten (`useCurrent`). Shift registers
  `clearShiftConflictSnapshot` for both, so both intents now remove the
  typed snapshot — not `useCurrent` alone. `reviewLater` still calls
  nothing, so it still removes nothing — operation, review entry, and
  snapshot all untouched.
- **`useLocal` requires a non-empty `currentVersion`.**
  `applyConflictResolution` rejects a decision whose `currentVersion` is
  `null` or empty before calling `supersedeConflict` at all — a `useLocal`
  with no concurrency version to carry forward is a caller bug, not
  something to send as a blank value. `OutboxController.supersedeConflict`
  independently enforces the same rule, so it stays safe even called
  directly.
- **A non-conflicted operation cannot be superseded.**
  `OutboxController.supersedeConflict` now rejects an `originalOperationId`
  that resolves to an operation which exists but is not `SyncState.conflict`
  (`pending`/`syncing`/`failed`/`synced`) — before any store write.
  `applyConflictResolution` independently checks the same thing for both
  `useLocal` and `useCurrent`, plus that `decision.conflictId` actually names
  the operation it loaded, so a mismatched id cannot silently act on the
  wrong operation. The repeated-submission recovery branch inside
  `supersedeConflict` was tightened to match: it only retires a
  still-present original when that original is still `SyncState.conflict`.

### What is still mock / provisional

- `InMemoryConflictReviewStore` and `InMemoryShiftConflictSnapshotStore` —
  both object-lifetime only. A second `ProviderContainer` over the *same*
  instance models a relaunch (tested); neither is durable across an OS
  process restart. A concrete store writes `ConflictReviewEntry.toJson()` /
  the snapshot's `Shift.toJson()` plus its version strings to the encrypted
  DB alongside `pending_operations`.
- The *default* `conflictReviewComposersProvider` / `conflictCurrentAppliersProvider`
  are still **empty** — that default is what a test gets without opting into
  the Shift overrides, and it is what keeps `features/conflict` itself
  feature-agnostic. The shipped app is not empty: `main.dart` overrides both
  with the Shift entry (see above).
- Nothing is ever actually recorded or applied in the shipped app today,
  despite the registration being real: a composer/applier needs a captured
  current record from a real `409` body (§5.4), and no real `SyncTransport`
  exists to ever write one into `ShiftConflictSnapshotStore`. Fabricating one
  to make the inbox look populated would be inventing a backend conflict —
  still explicitly refused, same as before the corrective pass.

### `Backend contract decision required`

1. **What a `stale_write` `409` body must contain for a composer to build an
   entry from it.** §5.3 already decided the response embeds (or references)
   the current record and an opaque `currentVersion`; what is still open is
   the per-entity read shape a composer parses — i.e. whether the `409`
   returns the same representation the entity's ordinary `GET` returns
   (which is what would let a feature reuse its existing typed
   `fromJson` unchanged, as §5.4 requires) or a conflict-specific subset. No
   frontend code depends on the answer yet; the composer registry is the one
   place it lands.

### Explicitly out of scope (this section)

No backend, no `/sync` queue, no real `SyncTransport`, no durable device
storage, no fabricated conflicts to demo the inbox, no generic merge engine,
and no navigation from the automatic sync path. The Task 4 corrective pass
**does** add the representative per-domain (Shift) composer/applier and
**does** implement §5.5's `useLocal` resolution protocol in code — both were
out of scope for the original Task 4 session but are explicitly in scope for
the corrective pass; see "What changed in the corrective pass" above.

---

## §8 — Device-local settings and the entry surface (no backend boundary)

### Feature

Appearance (six palettes, Light/Dark/System, Eye Protection), performance
(motion level, frame rate) and the entry visuals (the fixed Clean Layer
launcher identity, the cold-launch intro, the EntryPulse ambience on `/startup`
and `/login`).

This section exists to record a **negative** contract: none of it crosses the
frontend/backend boundary. It is written down because the absence of an
endpoint is otherwise indistinguishable from an endpoint nobody got around to,
and because `API_CONTRACT.md` did carry a stale `settings/motion-level` pair
that a backend developer would reasonably have implemented.

### The ruling

**Device preference, not account state. No endpoint, no table, no sync, no
outbox, no capability, no audit event.**

| Preference | Durable local key | Values |
| --- | --- | --- |
| Appearance | `mtm.settings.theme` | `ThemeState.toJson()` — `palette` (`medical`, `slate`, `copper`, `clay`, `indigo`, `teal`), `mode` (light/dark/system), `eyeProtect` (bool) |
| Motion level | `mtm.settings.motion` | `performance`, `low`, `balanced`, `high`, `maximum` |
| Frame rate | `mtm.settings.frame_rate` | `auto`, `fps30`, `fps60`, `fps90`, `fps120` |

All three are persisted by **name**, never by enum index, through the existing
`LocalStore` behind `SettingsRepository`. Unknown or corrupt values fall back
safely without clearing unrelated preferences. Defaults: Medical + Light,
Eye Protection off, `balanced` motion (or `performance` when the OS reports
`MediaQuery.disableAnimations` and nothing is stored), `auto` frame rate.

`GET`/`PUT /api/v1/settings/motion-level` is **superseded** and must not be
built; `API_CONTRACT.md` keeps the historical shape only so it is not
re-derived.

### Why device-local is the right boundary

The same person's phone and tablet are different screens in different light. A
server-owned appearance would push a choice made for one onto the other, and a
server-owned performance level would push a choice made for a fast device onto
a slow one — which is exactly backwards, since the setting exists to match the
hardware it runs on. Neither is shared, neither is auditable, neither is worth
a round trip on a screen that must paint before the session is even resolved.

That last point is now load-bearing: `loadDeviceSettings`
(`features/settings/data/device_settings_bootstrap.dart`) reads all three
together in `main()` **before `runApp`**, so the intro and Login paint in the
chosen appearance and performance rather than flashing a default and
correcting. A network-owned preference could not be honoured there at all —
there is no session yet, and at a cold launch there may be no network.

### The entry surface carries no state

The intro, the pulse, the fixed mark and the removed logo selector are
**rendering**. There is no API for them, no feature flag, no server-controlled
timing, no "has seen intro" field and no stored artwork choice. A `logo` key
written by the brief window when the mark was selectable is read as nothing
and costs nothing else. Do not let visual-only state into an auth, session or
settings payload.

### Backend responsibility

None. If the product later decides these should follow the account, that is a
new decision with its own section — not a gap to close quietly.

### Explicitly out of scope (this section)

Notification preferences (`GET`/`PUT /api/v1/settings/notifications`) and
organization settings are genuine server state and are unaffected. The
adaptive performance system is a later phase and does not exist.
