# Leader Mobile API Contract

Version: `v1`

Base path: `/api/v1`

This contract describes the API consumed by `flutter_app`. The field names,
enum values, and nesting below match the Dart `fromJson` / `toJson` methods.

Features built **frontend-first**, whose contract is not agreed yet, are not in
this file: they live in `FRONTEND-BACKEND-INTEGRATION.md` until their payload
and status codes are settled, and then move here.

## Transport and authentication

- Production traffic uses HTTPS.
- Request and response bodies use `application/json; charset=utf-8` unless the
  response is `204 No Content`.
- Authenticated requests send the access token in this exact form:

  ```http
  Authorization: Bearer <access-token>
  ```

- The sign-in response returns access and refresh tokens. Both are stored only
  in platform secure storage. They are never written to ordinary preferences.
- **Point 18B:** an expiring access token is renewed through
  `POST /api/v1/auth/refresh` (rotating, single-use refresh credential; see
  "Token refresh — Point 18B" under Authentication). Both tokens are opaque:
  the client never decodes either and never derives role, tenant, capability
  or expiry from them — authority is only what `GET /auth/me` returns.
- Password-reset endpoints use the reset token returned by the reset-request
  endpoint in the same bearer header.
- The TOTP secret and full `otpauthUrl` returned during MFA setup are displayed
  only for the active setup flow and are not persisted by the client.
- Member phone numbers and session IP addresses arrive already masked.

## Terminology — three concepts, three words

These are not synonyms and no field may carry two of them.

| Concept | What it is | Identifier |
| --- | --- | --- |
| **SaasTenant** | The paying team/customer. The subscription, billing, and data-isolation boundary. | `tenantId` |
| **DetachmentGroup** | A grouping of detachments — one branch, one operating area. Lives *inside* one SaasTenant. | `detachmentGroupId` |
| **Detachment** | The operational medical field unit. Lives inside one DetachmentGroup. | `detachmentId` |

`tenantId` is reserved for the SaasTenant boundary. Tenant-operational calls
never send it as trusted scope: the server derives it from the verified token
(`HANDOFF.md`). Cross-tenant `/platform/tenants/{tenantId}/*` operations are the
deliberate exception: only an independently authorized platform session may
name the subscriber it manages. `AuthUser.saasTenantId` returns the verified
association to a tenant account and is `null` for a Super Admin.

`detachmentGroupId` is an ordinary domain field on a detachment. The client
sends it, filters on it, and routes on it (`/detachment-groups/:groupId`).

The Flutter type behind `detachmentGroupId` was called `Tenant` until the
Point 1 terminology migration, and its routes were `/tenant/...`. Nothing on
the wire ever carried that spelling; the old routes survive in the client only
as redirects onto `/detachment-groups`.

## JSON conventions

- Property names use `camelCase`.
- Dates and timestamps are ISO 8601 strings, including an offset or `Z` when
  the value represents an instant.
- Durations use whole seconds. `HomeSummary.lockRemaining` is serialized as
  `lockRemainingSec`.
- Optional properties emitted conditionally by `toJson` are omitted when
  absent; they are not sent as empty strings.
- List responses are JSON arrays, not pagination envelopes in v1.
- A successful endpoint returning `void` responds with `204 No Content`.

## Errors

All non-success responses use:

```json
{
  "error": {
    "code": "validation",
    "message": "Human-readable message",
    "fields": {
      "capacity": "Field-specific message"
    }
  }
}
```

`fields` is optional. The client recognizes these codes:

- `not_found` — HTTP `404`
- `not_permitted` — HTTP `403`
- `conflict` — HTTP `409`
- `validation` — HTTP `422`
- `authentication_expired` — HTTP `401`
- `feature_disabled` — the tenant does not have the module (Point 8 →
  "Enforcement and retention"). Status is the backend's choice; the client
  branches on the code only.
- `plan_limit_reached` — a create/consuming mutation exceeds the effective
  plan limit (Point 7 → "Limit enforcement semantics"). Status is the
  backend's choice.

Point 16 clarification: the last two are organisation-wide refusals, not this
account's permission, and the client renders each with its own localized
sentence — never the `not_permitted` copy. A backend must therefore **not**
answer a disabled module or an exhausted limit with `not_permitted`, and must
not answer a missing capability with either of them.

### Frontend consumption (RFC 9457-ready)

The client models every error as a typed `Problem` (`lib/core/problem/`),
shaped so a future **RFC 9457 (`application/problem+json`)** response drops in
without touching screens or error architecture. Rules the backend contract must
respect:

- **The `code` is the only thing frontend flow branches on.** `error.message`
  / `detail` / `title` are diagnostics and last-resort fallback only, never
  product copy for a recognized code, and never a branch key.
- A **code this client version does not recognize** is safe: it renders a
  generic localized fallback ("تعذر إكمال العملية"), not `error.message`, and
  is not assumed retryable.
- The wire spelling above (`snake_case`) is what the client parses today; it is
  defined in one place (`ProblemCode.wire`) and can move to another convention
  cheaply.

Still open (see `FRONTEND-BACKEND-INTEGRATION.md` §2): whether the envelope
becomes literal RFC 9457 members (`type`/`title`/`status`/`detail`/`instance` +
`code` extension), the field-error key shape, and whether a safe support
reference id is provided.

`426 Upgrade Required` is not part of this contract yet. The client handles it
as a blocking application state and expects its body to use the shared Problem
Details contract with a `upgrade_required` code. See
`FRONTEND-BACKEND-INTEGRATION.md` §1 and §2.

`stale_write` (also `HTTP 409`, distinct from the `conflict` code above) is
likewise not part of this contract yet, but the client already recognises it:
`ProblemCode.staleWrite` — an **optimistic-concurrency** version mismatch on a
versioned write, never the same thing as the business-rule `conflict` code.
The full contract (the `version` token, what a `stale_write` body must carry,
and how a conflict is resolved) is decided in
`FRONTEND-BACKEND-INTEGRATION.md` §5.

Ordinary existing `v1` writes are **not idempotent**, and no `/sync` endpoint
exists yet. Point 7 subscription/limit commands and Point 9 tenant lifecycle
commands are deliberate exceptions: their own sections require an
`Idempotency-Key` because these consequential operations must be safe to retry.
That does not retrofit generic idempotency onto tenant-operational writes. The
client already has a local-first write foundation that mints one
UUIDv7 identity per logical write and will send it as `Idempotency-Key` on the
future write/sync transport; the backend contract for that (header name,
in-progress / invalid-reuse codes, retention) is open in
`FRONTEND-BACKEND-INTEGRATION.md` §3, and the related optimistic-concurrency
contract (record `version`, stale-write response contents, conflict
resolution/idempotency) is decided in `FRONTEND-BACKEND-INTEGRATION.md` §5.

## Canonical model payloads

### Capabilities

```json
{
  "global": [
    "workshop.create",
    "org.edit"
  ],
  "scoped": {
    "d_123": [
      "detachment.view",
      "member.view",
      "shift.assign"
    ]
  }
}
```

`global` and each value inside `scoped` are sets represented as arrays. Array
order is not significant. Unknown keys may be carried by the client but never
grant access in a client version that does not recognize them.

The 30 recognized capability keys are (`announcement.publish`, the 30th,
was added 2026-09-07 — `CAPABILITIES.md` §10; corrected here in Point 18A):

```text
Global
detachment.create
workshop.create
workshop.edit
workshop.archive
workshop.people.manage
workshop.attendance.record
workshop.payment.record
workshop.section.manage
admin.manage
org.edit

Scoped by detachment id
detachment.view
detachment.edit
detachment.archive
member.view
member.contact.view
member.invite
member.edit
member.deactivate
member.role.assign
shift.manage
shift.delete
shift.assign
shift.publish
shift.attendance.record
shift.attendance.override
shift.occurrence.manage
inventory.adjust
inventory.item.manage
stats.view
announcement.publish
```

### AuthUser

```json
{
  "id": "u_123",
  "name": "User Name",
  "email": "user@example.org",
  "role": "main_admin",
  "saasTenantId": "saas_123",
  "capabilities": {
    "global": ["workshop.create"],
    "scoped": {
      "d_123": ["detachment.view", "member.view"]
    }
  },
  "orgName": "Organization Name",
  "avatarInitials": "UN"
}
```

`avatarInitials` is optional. Every other property is required, `role` and
`saasTenantId` included — `saasTenantId` is **present and `null`** for a
platform account rather than omitted, because its null is a statement, not an
absence.

#### `role` — three administrator levels plus Customer Demo

| Wire value | Account level | What it administers |
| --- | --- | --- |
| `super_admin` | Super Admin | the Leader platform itself: subscribers, subscriptions, plans, platform health and platform audit |
| `main_admin` | Main Admin | one `SaasTenant` — one paying team, and everything operational inside it |
| `admin` | Simple Admin | part of one `SaasTenant`, narrowed by capability and by detachment |
| `customer_demo` | Customer Demo | an isolated constrained workspace; no `SaasTenant` and no tenant capabilities |

A Super Admin is **not** a high-capability administrator inside a team. It is
the control-plane account, and it is outside every `SaasTenant`.

Unknown values are refused, not defaulted: a client that cannot classify a
role must not be handed a product surface on a guess. Administrator roles and
the demo identity are distinct; a demo envelope paired with an administrator,
or `customer_demo` without a demo envelope, is invalid.

#### `saasTenantId` — the invariant

| `role` | `saasTenantId` |
| --- | --- |
| `super_admin` | **must be `null`** |
| `main_admin` | **must be a real id** |
| `admin` | **must be a real id** |
| `customer_demo` | **must be `null`** |

An account violating this is **invalid authentication data**. The client does
not repair it — it neither drops a stray id off a `super_admin` nor invents a
missing one for a tenant role, because it cannot know which half is wrong, and
either guess would produce a session silently scoped to the wrong customer.
The payload is refused and the app reads as signed out.

A Main Admin and every Simple Admin under them carry the **same**
`saasTenantId`: that is what makes them administrators of one customer rather
than two. The id is never inferred from `orgName`, which is a display string
two customers may share.

This is the one place `tenantId`'s value appears in a client-visible payload,
and it is read-only identity: the client still never *sends* it (see
**Terminology**) — the server derives the boundary from the verified token on
every request.

#### Role selects the surface; capabilities authorize the actions

The two answer different questions and neither substitutes for the other:

- **`role`** — *which application is this account looking at.* A capability
  set cannot express it: a Super Admin holding every tenant capability would
  still be the wrong product, and a Main Admin holding none would still be in
  the right one.
- **`capabilities`** — *what may run inside that surface.* Still the only
  thing any check consults (`CAPABILITIES.md` §1, the single-resolver rule).

No endpoint in this contract may be authorized by `role` alone, and no client
may open a control because of it. `role` is not a resurrection of the
`UserRole` enum dropped on 2026-09-02: that one named a rank inside one
organisation and was used as an authority check, which is exactly what
capabilities replaced.

#### Correction — an invalid payload is refused, not read as signed out

Point 3 sharpened what "refused" means on the client. It used to collapse into
"there is no session", which sent the person to the login form that would hand
back the same broken account. The payload is now its own outcome
(`AuthGate.invalid` → the invalid-session screen), and nothing downstream ever
sees the account: capability checks still resolve to none, and no surface
opens. **Nothing about the contract changed** — the server-side rule above is
unaltered, and a conforming server never emits such a payload.

### SessionAccess — the session envelope the startup decision reads

**STATUS: typed and consumed by the Flutter startup classifier; no live
endpoint returns it yet.** A backend that omits the object or any field still
gets the documented defaults, so partial rollout remains compatible.

Returned alongside `AuthUser` by the session endpoints (`POST /api/v1/auth/sign-in`
— spelled `POST /auth/login` here before Point 18A; there is no `/auth/login` —
and `GET /auth/me`) as a sibling object — **not** merged into `AuthUser`, because
these are lifecycle facts about the account and its customer that change
without the account changing.

```json
{
  "accountStatus": "active",
  "tenantStatus": "active",
  "demoMode": "none",
  "mfaRequired": false,
  "sessionExpiresAt": "2026-09-08T14:30:00Z"
}
```

Every property is **optional**, and every absent property means the normal
value. That is deliberate: partial implementation is the expected path.

| Property | Values | Meaning, and what the client does |
| --- | --- | --- |
| `accountStatus` | `active` \| `suspended` \| `revoked` \| `pending_setup` | The account's own lifecycle. `suspended` is reversible and blocks the app; `revoked` is terminal and is presented as terminal (never as a connection failure); `pending_setup` means identity verification and/or team-code linking has not been completed. |
| `tenantStatus` | `active` \| `suspended` \| `deletion_pending` \| `deleted` | The `SaasTenant`'s operational lifecycle — the customer, not the person. Every non-active value is a full tenant-shell block. `deletion_pending` has its own designed status destination. It is never inferred from subscription state. |
| `demoMode` | `none` \| `active` \| `expired` | Whether this session is a **customer demo**. A demo session carries `saasTenantId: null` and must never be served real tenant data. |
| `mfaRequired` | boolean | Authentication is incomplete until a second factor is presented. Outranks both product surfaces in the client's startup priority. |
| `sessionExpiresAt` | RFC 3339 timestamp with an explicit offset (`Z` or `±hh:mm`) | The server-issued absolute expiry instant. During session restoration the client converts both it and the injected local clock to UTC and treats `now >= sessionExpiresAt` as expired. It does not invent a lifetime or run a competing timer. A later `401 authentication_expired` remains authoritative during an open session. Absent/`null` preserves that existing 401-driven behaviour. A present malformed, non-string or offset-less value is refused as an unsupported access state. |

#### Absent vs. present-but-unknown — **revised 2026-09-08 (Point 4 preamble)**

The Point 3 text said *unknown values read as the normal value*. That was right
for one case and a **fail-open** for the other, and the client now tells them
apart. The table below is what a backend must assume.

| The server sends | The client concludes | Why |
| --- | --- | --- |
| the property **absent** (or `null`) | the documented normal value | Partial implementation is the expected path. A backend that ignores this whole section still produces today's behaviour. Unchanged. |
| a **value this build knows** | that value | Unchanged. |
| a **value or format this build does not know**, in any recognised gating property above | **refuse every product surface**, and show the account a screen saying this version cannot read its state | An installed build cannot safely reinterpret an unfamiliar lifecycle value, boolean, or expiry timestamp. |
| a **property name** this build does not know | ignore it | New metadata is additive and must not break a session. The line is drawn at a value inside a property the client already gates on. |

This is now the **same** direction as the `role` rule above rather than its
opposite: both refuse what they cannot classify. What is unchanged is that an
*absent* property is not "unknown" — it is the documented default, which is
why a partially-implemented envelope still works.

**What this asks of the backend, and it is one sentence.** A new **restrictive**
lifecycle state must be delivered as a new *value* of one of the lifecycle
properties above, never only as a new property. A build already in the field
reads the properties it knows; a new property it has never heard of is invisible
to it, so a restriction expressed that way would not be enforced by any
installed client at all. Expressed as a new value, every installed client fails
closed and the user is told to update.

Client detail, for reference: the refused value is preserved rather than
laundered — the client writes it back verbatim, never as the default it fell
back to — and the outcome is `StartupDestination.unsupportedAccessState` →
`/session-unsupported`, a designed screen whose only actions are sign-out and
support. See `features/auth/domain/session_access.dart` and
`test/features/auth/session_access_unknown_test.dart`.

#### What the client must never infer

None of the states above may be derived from anything else, and the client does
not. In particular:

- **An empty `capabilities` set is not a suspension, a revocation or an
  unfinished account.** It is an authorization outcome — nothing has been
  assigned to this account yet — and it gets its own screen that says exactly
  that (`/access-not-assigned`). Sending `accountStatus: "suspended"` is the
  only way to say "suspended".
- `orgName`, the email address and the shape of any id say nothing about
  lifecycle and are never read for it.

#### Error codes the startup decision needs

The startup decision can now reach `/session-expired` from either the valid
server-issued timestamp above while restoring a session, or the existing
`authentication_expired` (`401`) returned by a session read. They are not
competing expiry sources: both are server facts, and the 401 remains decisive
after startup. A `426` from the version gate continues to outrank everything
(see `FRONTEND-BACKEND-INTEGRATION.md` §1).

### The platform surface — Points 4–5

**STATUS: the client-side shell and typed Point 5 overview seam exist; the
endpoint below is a future backend contract and is still mocked.** Later Points
specify detailed management resources without changing this boundary.

#### Role selects the product surface; it never authorizes an action

Unchanged from `AuthUser.role` above, and now load-bearing for a whole route
subtree rather than one page:

| `role` | Surface the client opens | Route family |
| --- | --- | --- |
| `super_admin` | the SaaS control plane | `/platform` and everything under it |
| `main_admin`, `admin` | the tenant application | everything else |

The client enforces this in one place (`resolveStartup`) and refuses the other
surface at every location, deep links included. **The server must enforce the
same boundary independently** — the client's rule is a UX gate, as every access
decision in this app is.

#### Platform session requirements

Nothing new. A platform session is an ordinary session envelope whose
`AuthUser.role` is `super_admin` and whose `saasTenantId` is **null**; the
invariant is already stated under `AuthUser` and a payload violating it is
refused rather than repaired. `SessionAccess` applies to a platform session
exactly as to a tenant one: `accountStatus` and `mfaRequired` are meaningful,
`tenantStatus` is not (there is no customer), and `demoMode` must be `none` —
a demo session is never `super_admin`.

#### Platform repositories are a separate family, and must be

- **No tenant operational endpoint may be called by the platform surface.** Not
  detachments, detachment groups, members, shifts, attendance, inventory,
  workshops, announcements, the tenant organisation record, tenant notification
  preferences or the tenant sync outbox. The client holds this by construction
  and asserts it in the focused platform overview/shell tests; the
  server should treat a tenant-scoped call carrying a `super_admin` session as
  a bug on both sides.
- **Platform reads are cross-tenant by nature** (a list of subscribers, a
  platform health figure) and therefore cannot be scoped by `saasTenantId` the
  way every existing endpoint is. They need their own scoping rule, designed
  by the aggregate platform overview read and later management resources — not
  borrowed from a tenant id.
- **What the platform surface shares with the tenant one is the account, not
  the tenant.** `GET /auth/me`, `GET /auth/sessions`, `DELETE /auth/sessions/
  {id}`, MFA enrolment and the reset-by-email flow are the *account's own*
  endpoints and are called from both surfaces, unchanged.

#### `GET /platform/overview` — aggregate control-plane read (future)

One backend-friendly read supplies the decision-first overview. It is available
only to a valid `super_admin` platform session, is never scoped by
`saasTenantId`, and must never query through a tenant-operational client API.

```json
{
  "generatedAt": "2026-09-08T14:24:00Z",
  "tenants": {
    "total": 8,
    "activeSubscriptions": 4,
    "activeTrials": 2,
    "gracePeriod": 1,
    "suspended": 1,
    "deletionPending": 0
  },
  "demos": {
    "active": 4,
    "simple": 2,
    "full": 2,
    "expiringSoon": 2
  },
  "health": [
    {"id": "background_jobs", "label": "المهام الخلفية", "status": "degraded", "summary": "تأخير محدود في بعض المهام", "observedAt": "2026-09-08T14:23:00Z"}
  ],
  "attention": [
    {"id": "attention_grace", "severity": "warning", "category": "subscription", "title": "اشتراك واحد في فترة السماح", "description": "يحتاج إلى متابعة", "occurredAt": "2026-09-08T07:30:00Z", "target": "tenants"}
  ],
  "recentActivity": [
    {"id": "event_demo_started", "type": "demo_started", "title": "بدأت تجربة عميل جديدة", "description": "تجربة بسيطة", "occurredAt": "2026-09-08T13:52:00Z"}
  ],
  "usage": {"storageUsedBytes": 19327352832, "storageAllowanceBytes": 107374182400}
}
```

- `activeSubscriptions`, `activeTrials` and `gracePeriod` derive only from
  commercial subscription state. `suspended` and `deletionPending` derive only
  from tenant lifecycle and are orthogonal; neither is added to the commercial
  buckets as a sum invariant. Commercial buckets may total less than `total`
  when an inactive subscription exists. A pending deletion is surfaced as a
  typed Needs Attention item rather than a permanent headline KPI. Demo
  `simple + full` must equal `active`, and `expiringSoon <= active`.
  **Point 18B:** the final demo policy is self-service with no per-user kinds,
  so the `simple`/`full` split has no product meaning today; the client still
  requires both fields, and until product defines demo kinds the backend
  reports every active demo as `simple` with `full: 0`
  (**CLAUDE-PROVISIONAL**).
- `health[].status`: `healthy | degraded | unavailable | unknown`.
  `attention[].severity`: `info | warning | critical`. Categories currently
  accepted are `subscription`, `trial`, `demo`, `security`, `health`,
  `background_job`, and `tenant_lifecycle`.
- Activity types are summary events only: `tenant_created`,
  `subscription_changed`, `demo_started`, `demo_expired`, `security_alert`, or
  `platform_health_changed`. Return newest first; this is not the audit model.
- `target`, when present, is a typed existing section only: `tenants`,
  `operations`, `health`, or `security`. A `tenant_lifecycle` item may
  additionally carry `tenantId`
  and authoritative `scheduledFor`; the client uses those typed fields to open
  that tenant's detail and present stable day/date context. They are overview
  navigation/display hints, never an arbitrary route or permission grant.
- `usage` is optional and backend-neutral. Omit it when no truthful allowance
  exists; do not substitute database, host, RAM, or vendor metrics.
- `generatedAt` is required and is the sole freshness fact. The client refreshes
  explicitly/pull-to-refresh and does not claim that the response is live.
- Success may be minimal (zero summaries and empty lists). Distinguish it from
  network/offline failure. The mock demonstrates in-process cached data only;
  no durable platform cache exists yet. A real durable cache needs a separate
  security/storage decision because attention/activity may identify customers.
- Standard authenticated read errors apply. Return `403` outside a Super Admin
  session and a normal server/unavailable result when the aggregate cannot be
  produced; never leak an exception string into response copy.
- Starting a customer Demo must eventually emit a platform event/notification;
  Point 5 consumes a `demo_started` activity row only and does not define the
  notification system.

#### Platform Health and Security reads — Point 10 (future)

**STATUS: implemented in Flutter against typed deterministic mocks; backend
reads remain required. Both endpoints are read-only and available only to an
authorized `super_admin` platform session.** They are independent so a failed
security read does not erase usable health data, or vice versa.

##### `GET /platform/health`

```json
{
  "generatedAt": "2026-09-10T15:54:00Z",
  "isPartial": false,
  "signals": [
    {
      "id": "background_jobs",
      "label": "المهام الخلفية",
      "status": "degraded",
      "summary": "تأخير محدود في بعض المهام",
      "observedAt": "2026-09-10T15:52:00Z"
    }
  ]
}
```

- `status` is `healthy | degraded | unavailable | unknown`. An unsupported
  value is presented as `unknown`, never repaired to `healthy`.
- `generatedAt` and every `observedAt` are UTC timestamps. They describe a
  snapshot, not a live stream. The client performs an initial read plus
  explicit/pull refresh only.
- `isPartial=true` means the supplied signals remain usable but the backend
  could not supply the complete known catalogue. An empty `signals` list is
  unknown/unavailable data, not proof that everything is healthy.
- Overall status is derived on the client with conservative precedence:
  `unavailable`, then `degraded`, then `unknown`, then `healthy`; empty is
  `unknown`. Fetch failure/offline is not a platform-health status.
- The current catalogue contains only the three product-level signals already
  established by Point 5: `identity`, `background_jobs`, and `files`. Their
  labels/summaries remain safe product copy; no topology or raw telemetry is
  exposed.

##### `GET /platform/security-alerts`

```json
{
  "generatedAt": "2026-09-10T15:54:00Z",
  "alerts": [
    {
      "id": "security_tenant_sign_in",
      "severity": "critical",
      "category": "authentication",
      "title": "نشاط دخول يحتاج انتباها",
      "description": "توجد إشارة مصادقة عالية الأهمية مرتبطة بهذا الفريق.",
      "detectedAt": "2026-09-10T14:42:00Z",
      "affectedTenant": {
        "id": "saas_hilal",
        "displayName": "فريق الهلال الطبي",
        "isDeleted": false
      }
    }
  ]
}
```

- `severity` is `info | warning | critical`; unsupported values are preserved
  as the typed `unknown` presentation and must not be dropped or treated as
  informational. Point 10 currently justifies only `authentication`; an
  unsupported category becomes `unknown`.
- Alerts are current awareness records, not Point 11 audit events. The contract
  carries no actor, IP, request id, before/after evidence, immutable-retention
  claim, acknowledgement, assignment, resolution, or mutation endpoint.
- `affectedTenant` is optional. When present it is a platform-safe reference,
  not an operational tenant payload. The client validates it against Platform
  metadata before offering navigation and opens only
  `/platform/tenants/{tenantId}`. A deleted reference may contain only retained
  tombstone-safe id, display-name snapshot, `isDeleted=true`, and optional
  `deletedAt`; Team Code, admin email, subscription/features and operational
  records are forbidden.
- An empty list means only that the loaded snapshot has no current alerts; it
  is not proof that the platform is completely secure. Unknown alert states
  remain visible and do not collapse into the empty state.
- Pagination is not part of Point 10's implemented small snapshot contract.
  Add it only if real backend volume requires it.

For both reads, standard typed success/failure/offline behavior applies. A
usable cached snapshot may be returned with stale/offline metadata and its
original `generatedAt`; without cache the client shows no-data offline. No
durable cache or real-time guarantee exists. The server must independently
enforce Platform authorization and return safe errors without secrets, raw
exceptions, credentials, tokens, or operational medical data.

#### Platform Audit Log read — Point 11 (future backend)

**STATUS: the typed immutable Flutter domain, read-only repository boundary,
and deterministic mock are implemented, with the Point 11B list, filters,
pagination, and event detail on `/platform/audit`. The backend read below
does not exist yet.** Audit is
historical actor-attributed control-plane evidence. It is neither the current
Platform Security Alert snapshot nor a tenant's compact lifecycle history.

##### `GET /platform/audit`

```json
{
  "items": [
    {
      "id": "audit_20260910_001",
      "occurredAt": "2026-09-10T15:30:00Z",
      "actor": {
        "kind": "platform_administrator",
        "id": "u_demo_platform",
        "displayName": "مدير منصة ليدر"
      },
      "action": "feature_flag_changed",
      "category": "entitlement",
      "target": {
        "type": "tenant_feature",
        "id": "inventory",
        "displayName": "Inventory"
      },
      "tenant": {
        "id": "saas_hilal",
        "displayName": "فريق الهلال الطبي",
        "isDeleted": false
      },
      "changes": [
        {
          "field": "feature_enabled",
          "before": {"kind": "bool", "value": true},
          "after": {"kind": "bool", "value": false}
        }
      ]
    }
  ],
  "nextCursor": "opaque-server-cursor"
}
```

The canonical event contains only `id`, UTC `occurredAt`, typed `actor`, typed
`action` (whose category is deterministic), typed `target`, optional minimal
`tenant`, and a bounded list of typed safe `changes`. It has no severity,
incident status, acknowledgement, resolution, arbitrary metadata, request
body, route string, IP/device/geolocation, or invented correlation/request
identifier.

Actor kinds are `platform_administrator | system`. A platform-administrator
snapshot contains only stable account id and display name; it is deliberately
separate from the current `AuthUser` session and contains no email,
capabilities, credential, token, MFA, device, IP, or session data. A system
actor contains no service credential or infrastructure identity. Unsupported
actor kinds become the explicit typed `unknown` state.

The initial action catalogue is limited to mutations already implemented by
Points 6–9:

- tenant management: `tenant_registered`;
- subscription: `subscription_activated`, `trial_extended`, `trial_ended`,
  `subscription_moved_to_grace`, `plan_changed`;
- entitlement: `limit_override_changed`, `feature_flag_changed`;
- lifecycle: `tenant_suspended`, `tenant_reactivated`, `deletion_requested`,
  `deletion_cancelled`, `deletion_finalized`.

Category is derived from action as `tenant_management | subscription |
entitlement | lifecycle`; the client does not trust a contradictory category
as a second truth. Unsupported actions/categories remain visibly `unknown`
rather than becoming a neighbouring known action.

Target types are `tenant | subscription | plan_assignment | tenant_feature |
tenant_limit | tenant_lifecycle`. A target has only its typed resource class,
stable resource id, and optional safe display label. It is not a route and does
not itself grant navigation or authorization. Unsupported target types become
`unknown`.

`tenant` is optional and, when present, contains only tenant id, restricted
display-name snapshot, and `isDeleted`. A deleted tenant remains a minimal
tombstone reference; audit must not reconstruct the `SaasTenant`, restore or
retain its Team Code, or retain Main Admin email, subscription, feature,
limit, usage, or operational data for convenience. Tenant operational-data
deletion and minimized audit retention are separate policies.

Changes are not object snapshots. The only initial fields are
`lifecycle_status`, `subscription_status`, `plan_assignment`,
`feature_enabled`, and `limit_override`, with typed text/boolean/integer values
as appropriate; either side may be absent when there was no prior/next value.
An unsupported, forbidden, or malformed field/value is reduced to
`{"kind":"redacted"}` and never passed through as arbitrary metadata. The
client's safety policy does this defensively, but **the server must sanitize
before persistence**. Passwords, temporary passwords, OTPs, tokens, secrets,
authorization headers, cookies, credentials, session material, Team Codes,
medical operational records, and arbitrary request bodies are forbidden.

Query parameters are deliberately small:

| Parameter | Meaning |
| --- | --- |
| `from` | Inclusive UTC lower bound. |
| `before` | Exclusive UTC upper bound; when both bounds exist, `from < before`. |
| `actorKind`, `actorId` | Exact actor-kind/id filters. |
| `action`, `category` | Exact typed action or derived category. |
| `tenantId` | Exact optional tenant reference. |
| `targetType` | Exact typed resource class. |
| `search` | Normalized search over event id, actor display name, target id/display name, and tenant id/display name only. Never change bodies. |
| `cursor` | Opaque cursor returned by the previous page and echoed unread. |
| `limit` | Requested page size, 1–100; Flutter defaults to 50. |

Filtering precedes paging. Ordering is total and stable: `occurredAt`
descending, then event `id` descending. Responses contain `items` and optional
`nextCursor`; there is no count requirement. An invalid cursor is a typed
validation failure, not an instruction to restart silently. All timestamps
are RFC 3339 instants normalized to UTC.

The Flutter boundary is exactly
`PlatformAuditRepository.listAuditEvents(PlatformAuditQuery)`. It exposes no
append, edit, delete, mark-read, acknowledge, resolve, or history-rewrite
method. The authoritative backend alone appends audit evidence and must enforce
Platform authorization on the read and on the platform mutations that create
events; Flutter does not claim locally tamper-proof evidence. Opening Point 10
Health/Security pages creates no synthetic event.

Retention duration is not decided here and must not be hard-coded by Flutter.
It is a backend/platform policy that may be constrained by applicable policy
or law without this product claiming a particular compliance regime.
Finalizing tenant deletion does not automatically delete minimized audit
evidence, and it does not authorize indefinite retention either. The backend
must define retention/deletion behavior while preserving the minimization and
redaction rules above.

Point 11B integration clarifications (the Point 11A schema is unchanged):

- Calendar dates in the UI include the selected end day. Flutter converts
  local start-of-day to inclusive `from` and the start of the following local
  calendar day to exclusive `before`, then sends UTC instants. The server
  applies these exact instants; it must not truncate them back to UTC days.
- Search and every filter are repository queries, applied before pagination.
  Changing a query starts a fresh cursor sequence. A subsequent-page failure
  keeps existing rows, with an explicit retry. Invalid/expired cursors must
  return typed validation failure so the user can refresh the sequence.
- Display data must already be sanitized. Unsupported change text is displayed
  with a localized unknown-value label, never as a raw wire key or JSON.
- A tenant reference alone does not prove that a destination exists. Flutter
  offers a Platform tenant link only after checking current Platform metadata
  or the restricted Point 9 tombstone seam. The backend must support this
  authorized resolution without returning deleted operational/configuration
  data. Missing references remain historical display context without a link.
- Offline/stale pages retain original event timestamps and are explicitly
  labeled. This implementation has process-memory data only, with no durable
  Audit cache, real-time completeness, or polling guarantee.

#### Break-glass emergency access — Point 12 complete (future backend)

**STATUS: Point 12 frontend complete.** The typed Flutter domain
(`platform_break_glass_models.dart`), repository seam
(`PlatformBreakGlassRepository`), deterministic session-bound mock, providers,
and action controller remain the Point 12A authority. The Point 12B core adds the
Super-Admin-only `/platform/access` management page, separate request flow,
active-only Platform tenant picker, one activation/end confirmation,
persistent `PlatformShell` indicator, one-shot expiry handling,
recent-auth/sign-in-again UX, and the Audit catalogue. Point 12C completes the
localized, responsive and accessible presentation, reduced-motion strip
transition, and stable remaining-time context. There is still no backend or
grant-scoped tenant-data viewer; completion describes this read-only management
frontend only.

##### Definition

A break-glass **grant** is an exceptional, temporary, single-tenant, read-only
authorization that the backend attaches to **one authenticated Super Admin
session**, for a stated administrative reason, and ends automatically at a
server-set expiry. It exists for the rare case where a Super Admin must see one
subscriber's operational records to resolve an operational emergency that the
Platform control plane (identity, subscription, features, limits, lifecycle)
cannot resolve on its own.

It is **not**: a role; a tenant account; impersonation of the Main Admin or any
tenant user; a tenant `Cap` grant; a Platform permission; a way to change
Platform billing/subscription/features/limits/lifecycle; tenant switching; a
master password; a bypass of any tenant lifecycle block; or permanent access.
The signed-in `AuthUser` stays `super_admin` with `saasTenantId: null` and no
capabilities for the whole life of a grant. Normal Platform actions neither
need nor use a grant.

| Question | Settled answer |
| --- | --- |
| Who may initiate | Only an authenticated `super_admin` session. Tenant roles (`main_admin`, `admin`) never can. |
| What it grants | `tenant_operational_read` only: read-only access to the target tenant's operational records, still bounded by that tenant's Feature Flags. No writes, creates, deletes, exports-as-writes, account/credential actions, or Team Code. |
| Target | Exactly one existing `SaasTenant` in `active` lifecycle. Never a customer demo, a tombstone, or "all tenants". |
| Why a reason | The justification is the grant's accountability evidence; required, platform-only. |
| Duration | Server-set from platform policy; the client proposes none. Flutter's mock uses a **provisional 1 hour**. |
| Terminates on | initiator ends it; `expiresAt` reached; the bound session ends; target tenant leaves `active`; platform revocation. |
| After expiry | Terminal. No renewal or extension; renewed access is a new grant with a new reason and new audit evidence. |
| Platform state | One resource bound to the session; at most one possibly-live grant per session. |
| Audit | Backend appends Platform Audit evidence for activate/end/expire/revoke and attributes every grant-authorized request to the grant id. |
| Never bypasses | session validity, account lifecycle, Super Admin surface, tenant lifecycle, Feature Flags, Plan Limits, deletion/tombstone finality, Platform/tenant control-plane separation. |

##### Resource

```json
{
  "id": "bg_01J8...",
  "revision": 1,
  "tenant": { "tenantId": "saas_hilal", "displayName": "فرق الهلال الطبية" },
  "scopes": ["tenant_operational_read"],
  "reason": "تعذّر على قائد الفريق الوصول إلى سجلات المناوبات",
  "initiator": { "accountId": "u_demo_platform", "displayName": "مدير منصة ليدر" },
  "issuedAt": "2026-09-11T09:00:00Z",
  "expiresAt": "2026-09-11T10:00:00Z",
  "status": "active"
}
```

- `status`: `active | expired | ended`. `ended` additionally requires
  `endedAt` and `endReason`: `ended_by_initiator | session_ended |
  tenant_unavailable | revoked_by_platform`. `active`/`expired` carry neither.
- `revision` is the optimistic-concurrency token for grant commands; every
  state change (end, expiry, revocation) increments it.
- `issuedAt`/`expiresAt`/`endedAt` are RFC 3339 instants normalized to UTC;
  `expiresAt > issuedAt`. The server is authoritative; the client additionally
  treats an `active` grant at or after `expiresAt` as expired (fail closed).
- `tenant` is the minimum identity to target/display: id and display name.
- `initiator` is an id + display-name snapshot only.
- **Never returned or stored with a grant:** Team Code, Main Admin
  email/contact, subscription/plan/features/limits/usage, operational or
  medical records, credentials, passwords, OTPs, MFA material, tokens, session
  ids, cookies, IP/device/geolocation, or request bodies.

**Unknown values fail closed.** An unknown `status` is readable (so an
emergency state is never invisible) but never usable; an unknown scope confers
nothing (a grant with no recognised scope is unusable); an unknown `endReason`
reads as unknown. A malformed grant (missing id/tenant/initiator, bad
timestamps, `expiresAt ≤ issuedAt`, empty/over-length reason, `ended` without
end metadata) is an unreadable response, never a partially usable one.

##### Endpoints

| Method | Path | Body | Result |
| --- | --- | --- | --- |
| `GET` | `/platform/break-glass/current` | — | `{ "grant": <grant or null> }` for the calling session: the possibly-live grant, else the most recent terminal one, else `null`. |
| `POST` | `/platform/break-glass/grants` | `{ tenantId, expectedTenantVersion, scopes, reason }` + `Idempotency-Key` | the new `active` grant |
| `POST` | `/platform/break-glass/grants/{grantId}/end` | `{ expectedRevision }` + `Idempotency-Key` | the `ended` grant (`ended_by_initiator`) |

`expectedTenantVersion` is the tenant **lifecycle** version the operator
reviewed; a mismatch returns `stale_tenant`. `expectedRevision` mismatch
returns `stale_break_glass`. Idempotency follows the Point 9 pattern: same key
and same command replays the original result with no new effect or audit
event; the same key for a different command returns `idempotency_conflict`.
**Activation keys are per attempt**, never derived from tenant/version (a
derived key would replay an old ended grant); Flutter mints
`break-glass:activate:<uuidv7>` once per draft and reuses it only to retry
that unchanged draft. The end key is `break-glass:end:<grantId>:<revision>`.

Typed problems (RFC 9457 `code`): `tenant_not_found`, `tenant_not_eligible`
(suspended/deletion pending), `tenant_already_deleted`,
`invalid_break_glass_reason`, `invalid_break_glass_scope`,
`break_glass_already_active`, `break_glass_not_found`, `break_glass_not_active`
(already expired/ended), `stale_tenant`, `stale_break_glass`,
`idempotency_conflict`, `recent_authentication_required`, `not_permitted`,
plus the global `validation`/`server`/offline results. Messages are display
copy; clients branch only on `code`. `recent_authentication_required` is
feature-owned for now and may be promoted to a Core code if other privileged
Platform commands adopt it.

##### Server authority and access precedence

The backend must authorize every command **and every grant-authorized read**
independently of Flutter. For a request made under a grant, all of these must
hold, in order; none can be substituted by a later one:

1. authentication/session validity (grant is bound to this session);
2. account lifecycle of the Super Admin account;
3. surface: the actor is `super_admin`;
4. grant: exists, bound to this session, `active`, `now < expiresAt`;
5. target match: the requested tenant is the grant's tenant;
6. `SaasTenant` lifecycle of the target is `active` (re-evaluated per request);
7. scope: the operation is a read within `tenant_operational_read`;
8. the target tenant's Feature Flags (a disabled module stays unavailable);
9. Plan Limits — never reached, because no scope creates anything.

The grant's scope stands in for the tenant **Capability** step for this one
actor; it does not grant, borrow, or emulate any `Cap` key and must never be
implemented as `Cap.all` or a Main Admin preset. Feature Flags and Plan Limits
are commercial entitlements and are never bypassed or rewritten by a grant.
Break-glass does not authorize any Platform mutation.

**Tenant lifecycle.** Only `active` tenants are eligible. Suspension and
deletion pending are Point 9 FULL BLOCK and a grant is not a way around them
(`tenant_not_eligible`); a Super Admin who must intervene uses the Platform
lifecycle controls. Deleted tenants return `tenant_already_deleted`; a grant can
never recreate, restore, or read deleted operational data, and a tombstone is
never a target. When a target leaves `active` while a grant is live, the backend
must end it with `tenant_unavailable` and reject grant-authorized requests
immediately.

**Recent authentication.** Issuing a grant is a privileged action. The backend
must decide freshness from its own session/MFA evidence and return
`recent_authentication_required` when the evidence is too old. Flutter
validates nothing itself and has no step-up endpoint; until the backend
defines one, the only honest client path is to sign in again (which performs
the existing MFA challenge) and submit a new request. Whether Super Admin MFA
is mandatory is a backend account-policy decision.

**Session invalidation.** Sign-out, session expiry, session revocation, or
account lifecycle change ends the bound grant (`session_ended`). A grant is
never transferable to another session or device of the same account. On app
restart the client re-reads `GET /platform/break-glass/current`; nothing is
persisted on the device.

**Offline.** Activation and ending are online-only and never enter the tenant
operational outbox. An offline or stale read never manufactures usable
authority: the client may still *show* a cached possibly-live grant (so the
operator is not unaware of it) but treats it as unusable until a fresh
authoritative read confirms it. Server-side expiry proceeds regardless of
client connectivity.

**Expiry enforcement** is server-side on every request; the client-side check
is defensive only.

##### Audit and Security relationships

The backend appends Platform Audit evidence; Flutter never appends and
`PlatformAuditRepository` stays read-only. The Flutter Audit catalogue now
recognizes these backend-owned wire values:

- category `emergency_access`;
- actions `break_glass_activated`, `break_glass_ended` (initiator),
  `break_glass_expired` (system actor), `break_glass_revoked` (session end,
  tenant unavailable, or platform revocation);
- target type `break_glass_grant` with the grant id; `tenant` is the minimal
  tenant reference.

Unknown future values still parse as the existing typed `unknown` fail-safe.
The free-text reason stays on the grant resource and is not copied
into Audit `changes` (Audit has no free-text change field by design); its
retention follows the backend's audit-retention policy. Every request
authorized by a grant must be attributable to the grant id in backend security
evidence; whether individual reads also surface in Platform Audit, and at what
granularity, is an open backend/product decision.

A grant is **not** a Platform Security Alert and not a breach. It adds no
Security category and no Overview attention item; awareness is the Operations
module row and the persistent active-context indicator (Point 12).

##### Client behaviour (Point 12 — what the backend can rely on and must not)

- **Candidates.** The request picker pages the Platform tenant catalogue
  (`GET /platform/tenants`, `limit=100`, optional `search`) and keeps only
  `active` tenants; suspended, deletion-pending and deleted tenants are never
  offered. Immediately before submitting, the client re-reads the canonical
  lifecycle projection and aborts without sending if the tenant is no longer
  `active`. Both are UX only — the backend repeats eligibility authoritatively.
- **One confirmation per command.** Activation shows exactly one confirmation
  naming the team, the fixed read-only scope, the reason, that Feature Flags,
  Plan Limits and lifecycle stay enforced, and that the server sets the end
  time and records the action. Ending shows exactly one confirmation. No typed
  name, no client-proposed duration.
- **Attempt key.** Minted after the activation confirmation for a draft
  fingerprint (tenant id + lifecycle version + normalized reason); a retry of
  the unchanged draft reuses it, any change mints a new one.
- **Outcomes.** Success and `break_glass_already_active` return to the
  management page. `stale_tenant` refreshes the candidates and keeps the
  draft. Offline is refused locally and never queued; the draft is kept.
  `recent_authentication_required` explains that the app cannot prove
  freshness and offers sign-out (the draft is lost). Other codes show localized
  copy; nothing is replayed automatically.
- **Expiry.** No polling and no ticking countdown. The shell schedules one
  one-shot re-evaluation at `expiresAt − 10 min` (provisional near-expiry
  presentation) and one at `expiresAt`; at expiry the indicator is removed,
  `GET /platform/break-glass/current` is re-read, and one non-blocking message
  says access ended. The active card derives a stable human-readable remaining
  interval from the injected Clock; it does not add a timer or authority state.
- **Session.** A Super Admin sign-out confirmation states that it ends any
  emergency access bound to the session; the client drops the grant on any
  signed-in-account change. The backend's `session_ended` is still the
  authority.
- **Presentation.** The persistent strip uses `warn` / `warnTint`, has one
  short token-based size/fade transition, and becomes immediate when animations
  are disabled. Its live-region semantics announce a newly active or
  meaningfully changed emergency context, not rebuilds or timestamp refreshes.

##### Open backend/product policy (not decided by Point 12A)

- effective grant duration (mock: provisional 1 hour) and any per-tenant or
  per-operator limit;
- whether any write scope may ever exist (none does; it would be a new typed
  scope with its own enforcement);
- the concrete read surface an operator sees under `tenant_operational_read`
  and its endpoints — Point 12 does not build a tenant-data viewer;
- step-up/re-authentication mechanism and freshness window;
- whether and how the affected tenant's Main Admin is notified;
- per-read audit granularity and retention;
- whether platform authority other than the initiator may revoke, and who.

#### Platform Reports — Point 13A foundation (future backend)

**STATUS: POINT 13 COMPLETE.** Point 13A settled the architecture, the closed
catalogue, the typed Flutter domain (`platform_report_models.dart`,
`platform_report_datasets.dart`), the read-only
`PlatformReportsRepository` seam and a deterministic mock. Point 13B built the
route (`/platform/reports`, `/platform/reports/:reportType`), the catalogue
landing, the four report screens, filters, paging and every designed state
over that same mock. Point 13C closed the surface: the ≥900 dp dense-row/table
alternative for the three snapshot reports, a small keys×bands summary table
for usage limits, a two-column wide layout for Platform Activity's category
groups, the full theme/breakpoint/text-scale/accessibility/motion pass, and
the full test suite — **the wire contract below is unchanged throughout, and
none of the reads below exists on a backend.**

##### What a Platform Report is

A **Platform Report** is a structured, read-only, Super-Admin-only view over
one explicitly bounded **control-plane** dataset, answering one fixed
question. It is distinct from, and never merged with:

| System | Is | Reports' relationship |
| --- | --- | --- |
| Overview (`GET /platform/overview`) | current high-level awareness | reports do not repeat its KPI wall; the landing shows no metrics |
| Audit (`GET /platform/audit`) | immutable actor-attributed evidence | the activity report consumes a server-side **count projection** of Audit and links back to it; it never lists, copies, mutates or re-retains events |
| Security (`GET /platform/security-alerts`) | current security-awareness snapshot | not a report source; no alert history exists |
| Health (`GET /platform/health`) | current signal snapshot | not a report source; no signal history exists |
| Break-glass (`/platform/break-glass/*`) | a session-bound grant | not a report source; its four Audit actions are counted as governance events, never as incidents |

##### Closed catalogue

| `type` | Kind | Question | Sources | Rows | Privacy |
| --- | --- | --- | --- | --- | --- |
| `subscriptions` | `current_snapshot` | How is the current portfolio split by commercial status, plan and lifecycle, and what is due before a date? | subscription + tenant lifecycle | tenant rows, paged | `control_plane_tenant_rows` |
| `usage_limits` | `current_snapshot` | Which teams are at or over an effective plan limit, ranked by utilization? | usage aggregates + plan limits + lifecycle | tenant rows, paged | `control_plane_tenant_rows` |
| `feature_availability` | `current_snapshot` | How many teams have each optional module enabled? | Feature Flags + lifecycle | tenant rows, paged | `control_plane_tenant_rows` |
| `platform_activity` | `period_summary` | How many control-plane actions did Audit record in a range? | Audit (count projection) | none — counts only | `aggregate_only` |

Adding, removing or renaming a report is a contract change. An unrecognized
`type` parses as `unknown`, has no definition, and is never rendered. There is
no custom report builder, no arbitrary grouping, and no query language.

**Deliberately not reports:** revenue, MRR/ARR, invoices, payments, prices,
currency or customer lifetime value (Point 7 plans have limits and **no
prices**; "active subscription" is an administrative state, not a payment);
Health or Security history (none is stored — see backend requirements);
customer Demo accounts (no Demo resource exists yet); single-tenant reports
(a team's current state is `/platform/tenants/:tenantId`, its history is Audit
filtered by team); any tenant-operational data (members, shifts, attendance,
workshops' records, inventory rows, announcements, medical data).

##### Endpoints (synchronous projections; no report jobs)

```
GET /platform/reports/subscriptions
GET /platform/reports/usage-limits
GET /platform/reports/feature-availability
GET /platform/reports/platform-activity
```

All four are direct, synchronous reads of server-computed projections. The
datasets are bounded (tenant count; Audit counts), rows are paged, and no
export exists, so **no asynchronous job, job id, polling or download state is
specified**. If a future report or export cannot be answered within one
request, that report introduces a job contract of its own.

##### Common envelope

```json
{
  "type": "subscriptions",
  "generatedAt": "2026-09-11T09:00:00Z",
  "snapshotId": "opaque-snapshot-id",
  "summary": { },
  "rows": { "items": [ ], "nextCursor": "opaque-cursor-or-null" }
}
```

- `type` must equal the requested report; a mismatch makes the response
  unreadable.
- `generatedAt` — RFC 3339 **with an explicit offset** (UTC `Z` preferred).
  Snapshot reports state "as of `generatedAt`"; the client never re-labels it
  with the device clock. Offset-less timestamps are refused.
- `snapshotId` — opaque identity of the computed result. **Every cursor
  belongs to exactly one snapshot.** Pages 2…n of a snapshot report must be
  served from the same snapshot (same rows, same order, same summary); if the
  server can no longer serve it, return `409 report_cursor_expired` and the
  client reloads page one. The client never shows rows from two snapshots
  together.
- `summary` is computed over the **entire filtered set**, never over a page.

##### Shared query rules

- Typed, closed parameters only; unknown parameters are rejected with
  `validation`.
- `lifecycle` — comma list of `active`, `suspended`, `deletion_pending`;
  omitted = all three. `deleted` is **not** a reportable value.
- `planId=<id>` or `noPlan=true`; omitted = every plan.
- `cursor` — opaque; the client never builds or parses it. `limit` 1–100,
  default 50 (the Audit convention).
- Filters are applied before the summary and before paging.

##### `subscriptions`

Query: `status` (comma list of `trial`, `active`, `grace`, `inactive`),
`planId`/`noPlan`, `lifecycle`, `dueBefore` (instant; rows whose
`relevantDate < dueBefore`, overdue included, rows without a date never
match), `cursor`, `limit`.

```json
"summary": {
  "tenantCount": 8,
  "byStatus":    [{"key": "active", "count": 4}, {"key": "trial", "count": 2}, {"key": "grace", "count": 1}, {"key": "inactive", "count": 1}],
  "byLifecycle": [{"key": "active", "count": 7}, {"key": "suspended", "count": 1}, {"key": "deletion_pending", "count": 0}],
  "byPlan":      [{"plan": {"id": "mtm_standard", "name": "ليدر القياسية"}, "count": 3}, {"plan": null, "count": 1}]
},
"rows": {"items": [{
  "tenant": {"id": "saas_hilal", "displayName": "فرق الهلال الطبية"},
  "lifecycle": "active",
  "subscriptionStatus": "trial",
  "plan": null,
  "relevantDate": "2026-09-20T00:00:00Z"
}], "nextCursor": null}
```

- `relevantDate` is the server's own trial end / renewal / grace end. The
  client computes none; in particular the Point 7 **14-day grace is a
  provisional mock rule and must not become backend truth** through reports.
- Invariants: `byStatus`, `byLifecycle` and `byPlan` each sum to
  `tenantCount`. `byPlan` has one no-plan bucket at most (`plan: null`) and is
  ordered count desc, plan id asc, no-plan last.
- Row order: `relevantDate` ascending, no date last, then `tenant.id`
  ascending.
- Lifecycle and commercial status stay two axes (Point 7/9): a suspended
  tenant has its own commercial status.

##### `usage-limits`

Query: `limitKey` (one of `detachment_groups`, `detachments`, `admins`,
`members`, `workshops`, `storage_bytes` — ranks, does not filter), `band`
(comma list of `within_limit`, `at_limit`, `over_limit`, `no_limit`, matched
against `limitKey`'s band or the row's most severe band), `planId`/`noPlan`,
`lifecycle`, `cursor`, `limit`.

```json
"summary": {
  "tenantCount": 8,
  "byKey": [{"key": "members", "bands": [{"key": "within_limit", "count": 5}, {"key": "at_limit", "count": 0}, {"key": "over_limit", "count": 1}, {"key": "no_limit", "count": 2}]}]
},
"rows": {"items": [{
  "tenant": {"id": "saas_rukn", "displayName": "فريق الركن الطبي"},
  "lifecycle": "active",
  "plan": {"id": "mtm_core", "name": "ليدر الأساسية"},
  "cells": [{"key": "members", "usage": 118, "limit": 100, "overridden": true}]
}]}
```

- Metric definitions: `usage` is the backend's authoritative **platform
  aggregate** for that key (storage in bytes); `limit` is the **effective**
  limit `override ?? plan default`; `overridden` says which. No plan → every
  `limit` is `null` and the band is `no_limit`; a plan → every key has a
  limit. `limit: 0` is a real "no additional create" limit.
- Bands are factual: `over_limit` usage > limit, `at_limit` usage = limit,
  `within_limit` below. **No "near limit" threshold exists** — none is
  approved; the report ranks by utilization instead.
- Every row carries every known key; `byKey` covers every key and each sums
  to `tenantCount`. Keys the client does not know are ignored and flagged
  ("some limits not shown"), never re-labelled.
- Row order: band severity (over, at, within, none) desc, ratio
  `usage/limit` desc (a zero limit with usage is infinite), `tenant.id` asc.
- The server computes this from control-plane aggregates. It must **not** be
  computed by opening tenant operational datastores per request, and the
  client never does so.
- An over-limit row is not a deletion signal: nothing is deleted; creates are
  blocked (Point 7).

##### `feature-availability`

Query: `featureKey` (`inventory`, `statistics_reports`, `workshops`,
`announcements`), `state` (`enabled`/`disabled`, requires `featureKey`),
`lifecycle`, `cursor`, `limit`.

```json
"summary": {
  "tenantCount": 8,
  "byFeature": [{"key": "inventory", "states": [{"key": "enabled", "count": 7}, {"key": "disabled", "count": 1}]}]
},
"rows": {"items": [{
  "tenant": {"id": "saas_hilal", "displayName": "فرق الهلال الطبية"},
  "lifecycle": "active",
  "features": [{"key": "inventory", "state": "enabled"}]
}]}
```

- Reports the Feature Flag (module entitlement) only. It is **not** a
  Capability count, **not** a Plan Limit, and **not** module usage; the three
  axes stay separate (Point 8).
- A missing/unreadable state is reported as unsupported (its own bucket),
  never as disabled — while tenant access continues to treat it as disabled
  (fail-closed).
- Row order: tenant display name in a deterministic Arabic-aware collation,
  then `tenant.id` asc.

##### `platform-activity`

Query: `from` (inclusive instant), `before` (exclusive instant), optional
`category` (`tenant_management`, `subscription`, `entitlement`, `lifecycle`,
`emergency_access`). No cursor: the result is one bounded list of counts.

```json
{
  "type": "platform_activity",
  "generatedAt": "2026-09-11T09:00:00Z",
  "snapshotId": "opaque",
  "range": {"from": "2026-08-12T21:00:00Z", "before": "2026-09-11T21:00:00Z"},
  "evidenceAvailableFrom": null,
  "byAction": [{"key": "tenant_registered", "count": 1}, {"key": "break_glass_activated", "count": 0}]
}
```

- Counts events whose `occurredAt` satisfies `from <= t < before`, using the
  Point 11 action vocabulary; categories are derived client-side from actions.
  Actions the client does not know are counted as "other actions", never
  dropped or merged.
- `range` must echo the query exactly.
- `evidenceAvailableFrom` — set when Audit retention no longer covers the
  whole range; the client then says counts before that instant are
  **unavailable, not zero**.
- Payload is counts only: no actor, tenant, target, change body, reason,
  IP/device or request data. Every count links to `GET /platform/audit` with
  the same `from`/`before`/`action`, and the two must agree.
- No time buckets/series in Point 13: bucketing by calendar day needs an
  agreed IANA time-zone parameter the client cannot supply today. A trend is
  never synthesized from current state.

##### Date and time semantics (all reports)

- All instants are RFC 3339 with an explicit offset; the client normalizes to
  UTC.
- Ranges are half-open `[from, before)`. The client derives them from
  **device-local calendar days**: start of the first chosen local day, and
  start of the local day after the last chosen day — the Audit filter rule.
  The server never truncates timestamps into calendar days.
- Default range: last 30 local days including today. Maximum: 366 local days
  (the server bound is an instant span of 367 × 24 h, allowing for UTC-offset
  changes) → otherwise `422 report_range_too_large`. The bound exists because
  Audit retention is undecided and the aggregation must be bounded.
- Snapshot reports take no range; `dueBefore` is an instant.
- The mock and tests use the injected `Clock`; nothing uses `DateTime.now()`.

##### Deleted tenants

Snapshot reports contain **only** `active`, `suspended` and
`deletion_pending` tenants. A deleted tenant is never a row or bucket: its
tombstone has no subscription, plan, limits, usage or feature configuration,
and a report must not reconstruct them. A payload containing a `deleted`
row/bucket is refused whole. Deletions appear only as `deletion_finalized`
counts in `platform-activity`, with no name. Retired Team Codes and deleted
administrative identities never appear anywhere.

##### Data minimization (enforced by the client parser too)

Tenant rows carry `tenant.id` and `tenant.displayName` only, plus the report's
own typed fields. A report payload must never contain Team Codes, Main Admin
name/email/phone, credentials, temporary passwords, OTP/MFA material, tokens,
session ids, IP/device data, suspension/deletion reasons, member/volunteer
data, medical data, attendance, or tenant operational snapshots. The Flutter
parser refuses a row containing such a key rather than showing it; the
**server must not send it** in the first place.

##### Unknown and malformed values

- Unknown row status/lifecycle/feature-state → typed *unsupported*, labelled
  as such, counted in the breakdown's own `unsupported` bucket; never mapped to
  a known value.
- Unknown limit/feature keys → not rendered; the report is flagged.
- Missing required fields, negative counts, duplicate buckets, sums that do
  not match `tenantCount`, a range that does not echo the query, or
  offset-less timestamps → the whole response is unreadable (safe failure).

##### Authorization

Super Admin control plane only. The Flutter route guard is UX, not security:
the backend must authorize **every** report read independently, with the
Platform session policy used for other Platform reads. No tenant `Cap` key
applies or may be borrowed; `Cap.all` confers nothing. No fine-grained report
permission is introduced; if one is needed later it is backend policy
recorded under "Platform authorization". A break-glass grant confers no report
access. `403 not_permitted` is a typed state.

##### Errors

`validation` (bad parameter, malformed/foreign cursor), `not_permitted`,
`report_cursor_expired` (409 — reload page one), `report_range_too_large`
(422), `report_unavailable` (the backend does not serve this report), and
`server`. Offline is transport.

##### Offline and cache

Reports are online control-plane reads. The client may show a previously read
first page only as clearly **stale/offline**, with its original
`generatedAt`; it never claims freshness offline. No report read, page or
export is ever queued; paging is online-only. Nothing enters the tenant
operational outbox. No durable report cache exists (process memory only); a
durable cache would need its own policy for sign-out and tenant deletion.

##### Exports

**Point 13 approves no export (PDF, CSV or Excel).** There is no backend
export contract, a client-built file from a paged cross-tenant view would be
partial, and a file leaves the control plane. 13B adds **no** export
affordance. A future export must be backend-generated, authorized and
audited, stamped with report type, filters, range and `generatedAt`, subject
to the same minimization, never offered offline, and — if large — use an
explicit job contract.

##### Backend requirements recorded by Point 13A

- Four authorized report projections with the invariants above.
- A real `admins` usage aggregate (the Flutter mock uses the Point 7
  placeholder `1`).
- Snapshot-bound cursors or `report_cursor_expired`.
- An Audit count projection that agrees with `GET /platform/audit` and
  honours retention via `evidenceAvailableFrom`.
- **Historical storage, only if the product later wants trends:** periodic
  subscription/lifecycle/usage snapshots and Health/Security signal history do
  not exist; no trend report may exist until they do, and none may be derived
  from current state or from current tenants' `createdAt` (that would drop
  deleted tenants).
- Product decisions still open: a "near limit" threshold; time-series
  bucketing time zone; export formats; any fine-grained report permission;
  Audit retention duration.

#### Main Admin account management — Point 14A foundation (future backend)

**STATUS: POINT 14 COMPLETE (14A foundation + 14B core UX + 14C final
UX/visual validation).** Point 14A's typed domain
(`platform_main_admin_models.dart`), repository seam
(`PlatformMainAdminRepository`), deterministic mock, providers and action
controller remain authoritative and unchanged. Point 14B implements the
tenant-detail summary, `/platform/tenants/:tenantId/main-admin` management
page, `/replace` page, confirmations, safe outcomes and Audit catalogue over
that seam. Point 14C changed presentation only — no wire shape, command,
problem code, state or policy in this section moved. There is still no
backend. Rulings marked **PROVISIONAL** remain pending backend/product
authority (see "Point 14C closure" at the end of this section).

##### Definition

Point 14 is the Super Admin's view of, and a small set of
backend-authoritative controls over, the one account that holds a
`SaasTenant`'s **Main Admin seat**: see who holds it and in what state, re-send
an unfinished setup invitation, suspend and reactivate that account, and move
the seat to a different identity (replacement). Nothing more.

It is **not**: signup, onboarding, email-OTP, Google sign-in, Team Code
linking, first-login password change, returning-user flows or the account
setup screen (all **Point 17**, which owns how an invited identity completes
setup); Simple Admin or tenant-role management; the tenant-side Security
screen; a password, MFA or session console; impersonation; a way for the Super
Admin to become a Main Admin; or a tenant lifecycle control.

**Four independent dimensions.** `SaasTenant` lifecycle (Point 9), subscription
(Point 7), **Main Admin account state** (this section) and auth/session state
are separate. A tenant suspension is not an account suspension; account
suspension does not suspend the tenant (its Simple Admins keep working); a
completed replacement revokes an *account*, never the tenant; a session expiry
is not a revocation. Effective access for the Main Admin is the conjunction of
all four, evaluated in the existing order (session → account lifecycle →
tenant lifecycle → surface → Feature Flag → Capability → Plan Limit).

##### The seat invariant

- Every non-deleted `SaasTenant` has **exactly one current Main Admin
  account**, in `pending_setup`, `active` or `suspended` — never `revoked`,
  never absent. A tenant is never left without a Main Admin record, though it
  may temporarily have no *usable* one (never set up, or suspended).
- At most **one pending replacement** per tenant.
- Two usable Main Admins never coexist: authority moves only atomically, on the
  backend, when a designate completes setup. The designate has no tenant
  authority of any kind before that.
- There is **no stand-alone revoke** command — it would empty the seat. To
  remove a Main Admin, replace them; to contain one immediately, suspend.
- A deleted tenant has no seat; nothing may recreate a Main Admin linkage for a
  tombstone.

##### Resource — `GET /platform/tenants/{tenantId}/main-admin`

```json
{
  "tenant": {
    "tenantId": "saas_najd",
    "displayName": "فريق نجد للاستجابة",
    "lifecycleStatus": "active",
    "lifecycleVersion": 1
  },
  "revision": 2,
  "current": {
    "accountId": "ma_najd",
    "displayName": "بدر العنزي",
    "loginEmail": "badr@najd-response.sa",
    "status": "active",
    "createdAt": "2025-08-19T09:00:00Z",
    "activatedAt": "2025-08-20T09:00:00Z"
  },
  "replacement": {
    "id": "mar_najd_1",
    "status": "pending",
    "designate": {
      "accountId": "ma_najd_2",
      "displayName": "ريم القحطاني",
      "loginEmail": "reem@najd-response.sa",
      "setup": {
        "status": "outstanding",
        "lastSentAt": "2026-09-10T09:00:00Z",
        "expiresAt": "2026-09-17T09:00:00Z"
      }
    },
    "requestedAt": "2026-09-10T09:00:00Z",
    "reason": "طلبت الجهة تعيين مدير رئيسي جديد بعد انتقال المدير الحالي"
  },
  "readAt": "2026-09-11T09:00:00Z"
}
```

| Field | Rule |
| --- | --- |
| `current.status` | `pending_setup \| active \| suspended` (the session envelope's `accountStatus` values; the same account seen from the control plane). `revoked` is the state an **outgoing** account ends in and is invalid here. |
| `current.setup` | Required iff `pending_setup`: `{ status: outstanding \| expired, lastSentAt, expiresAt? }`. `expiresAt` absent = backend policy has no expiry. |
| `current.activatedAt` | Required iff `active`/`suspended`; absent for `pending_setup`. |
| `current.suspension` | Required iff `suspended`: `{ suspendedAt, reason }`. |
| `replacement` | Absent or `{ id, status: pending, designate, requestedAt, reason }`. The designate is always a new `pending_setup` account with a different login email and account id. |
| `revision` | Optimistic-concurrency token for the **whole seat** (current + replacement). Every change bumps it. |
| `tenant` | Minimal reference for the header and the lifecycle rule. |

**Unknown and malformed values.** An unknown `status` (account, setup or
replacement) is readable but makes the whole seat **read-only**: the client
shows "account state unavailable" and offers no action. A malformed seat —
`revoked` holder, `suspended` without `suspension`, `pending_setup` without
`setup`, designate equal to the holder, unknown tenant `lifecycleStatus`,
deleted tenant — is an unreadable response, never a partial one. The client
also treats an `outstanding` invitation at or after `expiresAt` as `expired`
(fails toward "offer a resend", never toward "grant").

**Privacy / minimal payload.** Never returned or accepted: passwords or hashes,
temporary or bootstrap credentials, OTPs, MFA secrets or enrolment material,
backup codes, reset or setup tokens/links, auth/refresh/session tokens, session
lists, device/IP/geolocation, Team Code, subscription/features/limits, or
operational data. Account ids are opaque. Emails are identity and are rendered
LTR-isolated. The reasons are Platform-only.

##### Commands

All commands: `POST`, JSON body with `expectedRevision`, `Idempotency-Key`
header, Super Admin session. Result: `{ snapshot, effect }` where `effect ∈
setup_resent | suspended | reactivated | replacement_started | replaced |
replacement_cancelled`.

| Command | Path | Body | Preconditions (seat) | Tenant lifecycle | Effect / sessions |
| --- | --- | --- | --- | --- | --- |
| Resend setup | `…/main-admin/setup/resend` | `{ expectedRevision, target: "current" \| "replacement" }` | target is a pending account (current `pending_setup`, or a pending replacement); outstanding **or** expired | `active` only | Previous invitation invalidated; new one issued; `lastSentAt`/`expiresAt` reset. No credential returned. |
| Suspend | `…/main-admin/suspend` | `{ expectedRevision, reason }` | current `active` | any non-deleted | `suspended`; backend **ends every session and refresh token** of the account; new sign-ins land on `/account-suspended`. |
| Reactivate | `…/main-admin/reactivate` | `{ expectedRevision }` | current `suspended` | `active` only | `active`; no session restored — the user signs in again. |
| Replace | `…/main-admin/replacements` | `{ expectedRevision, designate: { displayName, loginEmail }, reason }` | current holds the seat; no pending replacement | `active` only | see below |
| Cancel replacement | `…/main-admin/replacements/{id}/cancel` | `{ expectedRevision }` | that replacement is pending | any non-deleted | Designate's invitation invalidated, designate account discarded, any partial-setup sessions of it ended. Current unchanged. |

**Replace — two modes, decided by the backend from the current state.**

1. **Current is `pending_setup` (never activated) → immediate.** There is no
   authority to transfer. The current account's outstanding invitation is
   invalidated at once and its account revoked (any partial-setup sessions
   ended); the designate becomes the current `pending_setup` account with a
   fresh invitation. `effect: replaced`. This is how a wrong or obsolete
   registration address is fixed — never by editing the email.
2. **Current is `active` or `suspended` → pending.** A `replacement` is
   created and the designate invited; the current account keeps the seat (and,
   if active, keeps working). `effect: replacement_started`. When the designate
   completes Point 17 setup the backend **atomically**: makes the designate the
   `active` current account, revokes the former account's Main Admin
   authorization (`accountStatus: revoked` → `/account-revoked`), ends all its
   sessions, clears the replacement, bumps `revision`, updates the tenant's
   `mainAdmin` contact summary, and appends `main_admin_replaced`. Completion
   requires the tenant to be `active` and the invitation unexpired; it cannot
   complete while the tenant is suspended or deletion-pending (Point 17 setup
   is blocked by the tenant lifecycle, which the startup order already ranks
   above first-time setup).

Replacement of a suspended current is allowed (the realistic "outgoing admin
was contained first" case). Suspend of the current stays available while a
replacement is pending. The designate must differ from the current login and
must not already belong to any Leader account (`main_admin_identity_unavailable`
— the backend reveals nothing about which account or tenant). **PROVISIONAL —
BACKEND/PRODUCT DECISION REQUIRED:** that the outgoing account is revoked
rather than demoted (a demotion to Simple Admin would be tenant-role
administration, which the new Main Admin owns), and that an existing Leader
account may never be designated.

**Tenant lifecycle matrix.** Actions that can open, restore or extend a path
into tenant access (resend setup, reactivate, replace, resend replacement
setup) require `active`. Reducing actions (suspend, cancel replacement) are
allowed on `active`, `suspended` and `deletion_pending`. `deleted`: nothing,
not even a read (`tenant_already_deleted`). Reading is allowed on every
non-deleted tenant. Account reactivation therefore never bypasses a tenant
suspension; the operator reactivates the tenant first. Account actions never
change the tenant lifecycle, its version or history, the subscription,
features, limits, counts or Team Code; tenant lifecycle changes never change
account state.

**Concurrency and idempotency.** `expectedRevision` mismatch →
`stale_main_admin` with no write; the client reloads. The `Idempotency-Key`
is **per attempt** (`main-admin:<action>:<uuidv7>`): minted when the operator
confirms a draft, reused only to retry that unchanged draft, never replayed
automatically. Same key + same command → the original result
(`idempotentReplay`, no new effect, no new Audit event); same key + different
command → `idempotency_conflict`. A new key for an already-applied change is
refused by the state machine (`invalid_main_admin_transition` or
`stale_main_admin`). Concurrent cancel vs designate completion: the backend
serializes on the seat; the loser gets `stale_main_admin`.

**Typed problems** (RFC 9457 `code`): `tenant_not_found`,
`tenant_not_eligible`, `tenant_already_deleted`,
`invalid_main_admin_transition`, `invalid_main_admin_reason`,
`invalid_main_admin_identity`, `main_admin_identity_unavailable`,
`main_admin_replacement_already_pending`, `main_admin_setup_resend_throttled`
(**PROVISIONAL** name, if the backend rate-limits resends), `stale_main_admin`,
`idempotency_conflict`, `recent_authentication_required`, `not_permitted`,
plus the global `validation`/`server`/offline results. Clients branch on
`code` only.

**Reasons.** Required for suspend and replace; Point 9 convention (whitespace
normalized, non-empty, ≤ 280). Purpose: Platform accountability evidence for
an authority change, shown back to Super Admins on the seat. Never delivered to
the Main Admin or any tenant user, never placed in the session envelope, never
copied into Audit `changes`. Not collected for resend, reactivate or cancel
(no decision to justify beyond the Audit event itself).

##### Authentication, passwords, MFA, sessions

- **Recent authentication.** The backend decides freshness from its own
  session/MFA evidence and may answer any command with
  `recent_authentication_required`. **PROVISIONAL:** it should at least require
  it for replace (both modes) and reactivate. Flutter verifies nothing and has
  no step-up endpoint: the only client path is sign out, sign in again
  (existing MFA challenge), and re-submit — the draft is lost and the page
  says so. Same rule as Point 12.
- **Passwords.** The Platform never sees, sets, generates or resets a Main
  Admin password. The account owner already has the public reset-by-email flow
  (`/auth/password-reset/*`). A Platform-triggered reset email is **not** part
  of Point 14: it grants no capability the owner lacks and adds an unrequested
  credential email. Any future first-login bootstrap secret is created, shown
  once, expired and audited by the backend under Point 17 — never in Flutter.
- **Email identity.** A login email is immutable for its account; there is no
  edit command in any state. A different address is a different account,
  reached only by replacement (immediate when the holder never activated). A
  same-person verified email change is future account self-service, not a
  Platform action.
- **MFA.** No MFA status, secret, backup code, disable or reset is exposed or
  offered. Compromise recovery that needs an MFA or credential reset is a
  future backend-controlled recovery operation with its own audit and policy;
  containment today is suspend (+ replacement).
- **Sessions.** The Super Admin gets **no** session list and no per-session
  revoke for the Main Admin. Session consequences are server-enforced side
  effects of account commands (table above). The backend must reject every
  protected request of a suspended/revoked account immediately, not only at
  the next refresh.

##### Authorization and offline

- `super_admin` only. No tenant `Cap` is read, borrowed or granted; the
  Main Admin remains a tenant role and the Super Admin never becomes one. The
  backend authorizes every read and command independently of the Flutter role
  gate. No fine-grained Platform permission key exists or is invented here.
- **Online-only.** Every command is refused offline and never queued; nothing
  enters the tenant operational outbox. A stale or offline cached seat is shown
  read-only with no actions; no cache → offline empty state.

##### Audit (backend-appended; Flutter appends nothing)

New category **`account_management`**, target type **`main_admin_account`**
(target id = the affected account id; `tenant` = minimal tenant reference).
Actions:

| Action | Actor | Target | Safe `changes` |
| --- | --- | --- | --- |
| `main_admin_setup_resent` | platform administrator | the pending account (current or designate) | none |
| `main_admin_suspended` | platform administrator | current | `account_status`: `active → suspended` |
| `main_admin_reactivated` | platform administrator | current | `account_status`: `suspended → active` |
| `main_admin_replacement_started` | platform administrator | designate | none |
| `main_admin_replacement_cancelled` | platform administrator | designate | none |
| `main_admin_replaced` | platform administrator (immediate) or `system` (on designate setup completion) | the **new** holder; former account id referenced | `account_status` of the former: `→ revoked`; `login_identity`: **redacted** |

No email address, name, reason, invitation/reset token, credential or session
id appears in `changes`. Point 14B added these six actions, category
`account_management`, target `main_admin_account` and the
`account_status`/`login_identity` change fields to the Flutter Audit catalogue
(`login_identity` always renders redacted); any other value still parses as the
typed `unknown` fail-safe. Setup completion itself is Point 17 evidence and is
not defined here.

##### Backend requirements and open policy

Owed: the resource and five commands above with their invariants; atomic seat
transfer on designate setup completion; invitation issuance/expiry/delivery
and invalidation; immediate session/refresh-token termination for suspend,
replaced and cancelled accounts; the new holder's Main Admin capability grant
(the same backend provisioning policy as the initial Main Admin — the client
writes no grant); platform-wide login-email uniqueness;
recent-auth enforcement; Audit append. **PROVISIONAL — BACKEND/PRODUCT
DECISION REQUIRED:** invitation validity (mock 7 days) and whether invitations
expire at all; resend throttling; revoke-vs-demote of the outgoing holder;
whether an existing Leader account may be designated; recent-auth scope and
freshness window; whether the outgoing/incoming Main Admin is notified by
email; MFA/credential recovery operation; whether pending invitations are
invalidated automatically when a tenant is suspended or deletion begins
(Point 14 only guarantees they cannot complete).

##### Point 14C closure — presentation only

Point 14C (2026-09-12) changed no resource, command, field, problem code,
state, transition or policy above. It made two client-side presentation
guarantees the backend may rely on the client keeping: the page labels the
**tenant's access state** (`MainAdminTenantReference.lifecycleStatus`, shown as
a team-worded chip beside the team name) separately from the **account status**
(inside the seat card), and a stale/offline snapshot is presented read-only with
its `readAt` time and a read-only refresh — never a write, replay or queue. The
backend/product gaps listed above remain open and were not decided in Flutter.

#### `SaasTenant` — the subscriber resource (Point 6)

**STATUS: implemented in the client against typed repository seams. Reads,
registration, subscription/features, and Point 9 lifecycle commands are
process-memory mocks; their endpoint contracts are future backend work.**

A `SaasTenant` is **one paying Leader subscriber** — the subscription, billing,
security and data-isolation boundary, whose wire id is `tenantId`. It is not a
`DetachmentGroup` (a local grouping of detachments *inside* one subscriber) and
it is not a customer Demo account (which has no `saasTenantId` at all). Every
operation below is available only to a valid `super_admin` platform session, is
cross-tenant by nature, is never scoped by `saasTenantId`, and must never be
answered by querying a tenant-operational service through a client API.

##### The representation

```json
{
  "id": "saas_hilal",
  "displayName": "فرق الهلال الطبية",
  "teamCode": "MTM-4K7P-QX92",
  "lifecycle": {
    "status": "active",
    "version": 4
  },
  "createdAt": "2025-01-04T16:00:00Z",
  "updatedAt": "2025-01-04T16:00:00Z",
  "mainAdmin": {
    "name": "سلمى الحارثي",
    "email": "salma@hilal-medical.org",
    "provisioning": "pending_setup"
  },
  "subscription": {
    "status": "active",
    "planId": "mtm_standard",
    "version": 3,
    "trialEndsAt": null,
    "renewsAt": "2027-01-04T16:00:00Z",
    "graceEndsAt": null,
    "limitOverrides": {
      "detachments": 20
    }
  },
  "usage": {
    "storageUsedBytes": 7516192768,
    "storageAllowanceBytes": 21474836480,
    "lastActivityAt": "2026-09-08T14:00:00Z"
  },
  "counts": {
    "detachmentGroups": 6,
    "detachments": 23,
    "members": 418,
    "workshops": 37
  }
}
```

- **`lifecycle.status`** is the operational state
  `active | suspended | deletion_pending | deleted`. It is never inferred from
  commercial standing. `lifecycle.version` is the optimistic-concurrency token
  for lifecycle commands only; it is deliberately independent of
  `subscription.version` and every per-feature version. Unknown or internally
  inconsistent lifecycle payloads make the record unreadable (fail closed).
- **`subscription.status`** is the commercial state
  `trial | active | grace | inactive`. `inactive` is the explicit commercial
  state needed by a tenant whose access may separately be suspended; it is not
  a synonym for suspension. Unknown tenant or subscription values make the
  record unreadable rather than being repaired.
- **`teamCode`** — see below. Required, unique, and immutable once assigned.
- **`mainAdmin.provisioning`** is `pending_setup | active`, the same vocabulary
  as `AuthUser`'s `AccountStatus`. It says whether the initial Main Admin has
  completed first-time setup. **The object must never carry a password, a
  temporary password, an OTP, a token, or any other credential**, in this
  resource or in the create response — see "Initial Main Admin provisioning".
- **`subscription`** is now the Point 7 commercial snapshot. `planId` is absent
  for an explicitly unassigned trial; absence does not mean a missing record.
  `version` is the optimistic-concurrency token echoed by every mutation.
  `trialEndsAt`, `renewsAt` and `graceEndsAt` are present only when meaningful.
  `limitOverrides` contains only tenant-specific deviations from the selected
  plan defaults. It contains no feature flags and no payment-provider data.
- **`usage`** is backend-neutral: bytes and an activity instant. Never a
  database, host, vendor or RAM metric. `storageAllowanceBytes` is optional —
  omit it when no truthful allowance exists rather than inventing one. It is a
  *capacity* figure, not a plan limit.
- **`counts`** are **platform aggregates delivered with the record.** The
  control plane must be able to render a subscriber's size without ever calling
  a tenant-operational endpoint; a client that counted detachments by listing
  them would break the isolation rule above while looking harmless.
- All timestamps are RFC 3339 UTC.

##### Team Code semantics

- A short, human-transcribable identifier for one subscriber, canonical form
  `MTM-XXXX-XXXX`, where `X` is drawn from `23456789ABCDEFGHJKMNPQRSTVWXYZ` —
  digits and upper-case Latin minus the characters that are misread when a code
  is dictated or copied by hand (`I`, `O`, `L`, `U`, `0`, `1`).
- **Assigned by the platform.** The Super Admin sets it at creation. It is
  **immutable** afterwards in this Point, and the tenant application must offer
  no way to read-modify-write it — the server must reject a change originating
  from a `main_admin` or `admin` session regardless of what the client sends.
- **Unique across all subscribers, and the backend is the only authority on
  that.** Uniqueness must be enforced under concurrency (a unique index, not a
  read-then-write); the client's duplicate check is a courtesy that races and is
  documented as such. Compare on the canonical, punctuation-stripped,
  upper-cased form so `mtm 4k7p qx92` cannot slip past `MTM-4K7P-QX92`.
- **It is not a credential.** It identifies; it does not authenticate. The
  future verified first-time link requires email-ownership proof *and* the code,
  and the code alone must never grant access to anything. It is therefore
  displayed in plain sight on the Super Admin's tenant detail, and it is
  formatted to look like an order number rather than a password.
- Demo accounts have no Team Code.
- **Not readable from the tenant application (Point 15 decision).** No
  tenant-side read is authorized by any contract, so the Organization screen
  does not show it and the tenant organisation read never returns it. If the
  onboarding flow (Point 17) needs a Main Admin to share it with their
  admins, that is a new, explicitly authorized read — never an edit,
  regenerate, rotate or revoke.
- The real code is **generated server-side**. The client's generator is a
  deterministic seam used to offer a suggestion in the create form and to make
  tests exact; it makes no unpredictability or uniqueness claim.

##### `GET /platform/tenants` — list, search, filter, page

Query parameters, all optional:

| Parameter | Meaning |
| --- | --- |
| `search` | Free text matched against team name, Main Admin name, Main Admin email and Team Code. Matching must be accent/diacritic-insensitive for Arabic and fold alef/ya/waw/ta-marbuta variants and Arabic-Indic digits — the client normalizes the query the same way, and the two must agree. |
| `status` | List projection: `trial | active | grace | inactive | suspended | deletion_pending`. The first four derive from `subscription.status`; the blocking values derive only from `lifecycle.status` and take display precedence. Deleted tombstones are not normal `SaasTenant` list items. Absent means every active-resource status. |
| `cursor` | **Opaque.** Whatever the previous page returned as `nextCursor`, echoed back unread. |
| `limit` | Page size. |

```json
{
  "items": [ /* SaasTenant */ ],
  "total": 8,
  "nextCursor": "…"
}
```

- `total` is the number of records matching the **query**, before paging — the
  list screen shows a result count and a count of the current page would be a
  different and less useful number.
- `nextCursor` is absent or `null` on the last page. **It must be opaque**: the
  client neither constructs nor parses one, and must not be able to infer an
  offset, an id or a sort key from it. That is what keeps this contract free of
  a specific database — no Mongo `ObjectId`, no SQL `OFFSET`, no PostgreSQL
  keyset token leaks into the client.
- **Ordering is stable, total and server-defined**: newest-registered first,
  ties broken by id. Two identical requests must return the same rows in the
  same order, or paging silently duplicates and drops customers. Sorting is not
  a client parameter in this Point.
- The client currently reads the first page only and, when `nextCursor` is
  present, tells the operator the results were cut and to narrow the search. A
  "load more" affordance arrives with the Point that needs it.
- Filtering happens **before** paging.

##### `GET /platform/tenants/{tenantId}` — one subscriber

Returns the same representation. `404 not_found` when the id names none — the
client renders a distinct not-found state with no retry, because a retry on a
404 only produces the same 404.

##### `POST /platform/tenants` — register a subscriber

```json
{
  "displayName": "فريق الشمال الطبي",
  "mainAdminName": "أمل السبيعي",
  "mainAdminEmail": "amal@shamal.org",
  "teamCode": "MTM-7DQX-4NKR"
}
```

- Every field is required. The server trims and collapses whitespace,
  lower-cases the email and canonicalises the code before validating and
  storing — the client does the same, and both must reach the same string.
- **The created subscriber starts with `lifecycle.status=active`,
  `lifecycle.version=1`, and
  `subscription.status=trial`**, no assigned plan, and
  `mainAdmin.provisioning=pending_setup`. The client sends no status and no plan, and the server must
  not accept one on this endpoint: activating a subscription is a Point 7
  operation with its own authorization.
- Returns the created `SaasTenant`. **It must not return a password, a temporary
  password, an invitation token, or any other credential**, and the client is
  written so that it has nowhere to put one.
- Errors: `422 validation` with `fields` keyed by the request field names
  above (the shared error envelope's key; the client parses `fields`/`errors`,
  never a wire `fieldErrors` — corrected in Point 18A); `409 tenant_code_conflict` when the Team Code is taken.

##### `GET /platform/tenants/{tenantId}/status-history` — lifecycle history

```json
[
  {"id": "…", "type": "moved_to_grace", "occurredAt": "2026-09-05T16:00:00Z", "note": null}
]
```

- `type` is one of `tenant_created`, `trial_started`, `trial_ended`,
  `trial_extended`, `subscription_activated`, `moved_to_grace`,
  `plan_changed`, `limit_override_changed`, `tenant_suspended`,
  `tenant_reactivated`, `deletion_requested`, `deletion_cancelled`, or
  `tenant_deleted`. Newest first.
- **This is tenant/subscription lifecycle history, not the platform audit
  log.** It says what state moved and when. It carries no address, request id,
  or full before/after body; the immutable actor-attributed record is a separate
  Point 11 resource and must not be conflated with this one. `note`, when
  present, is short platform-only administrative text and must never contain a
  customer record or a credential.
- An unrecognised `type` makes the row unreadable rather than being mapped to a
  neighbouring event.

#### Tenant operational lifecycle (Point 9)

**STATUS: complete frontend-first through a dedicated
`TenantLifecycleRepository` over the same canonical `PlatformTenantStore` used
by Points 5–8, with the final Super Admin management, tenant blocking,
tombstone, and typed failure UX integrated. The endpoint family below is the
required backend contract; the Flutter mock performs no physical deletion and
no cryptographic operation.**

The lifecycle is independent of subscription status, tenant feature flags,
capabilities, and plan/limit values. A command may change only the lifecycle
object and the compact lifecycle-history projection. In particular, suspension,
reactivation, beginning deletion, and cancelling deletion must preserve the
subscription snapshot/version, plan, limit overrides, feature configuration,
Team Code, Main Admin association, usage, and tenant-owned data.

An active/suspended record may carry the following lifecycle shapes:

```json
{
  "lifecycle": {
    "status": "suspended",
    "version": 5,
    "suspension": {
      "suspendedAt": "2026-09-09T14:00:00Z",
      "reason": "مراجعة إدارية"
    }
  }
}
```

```json
{
  "lifecycle": {
    "status": "deletion_pending",
    "version": 6,
    "suspension": {
      "suspendedAt": "2026-09-09T14:00:00Z",
      "reason": "مراجعة إدارية"
    },
    "deletion": {
      "requestedAt": "2026-09-10T14:00:00Z",
      "scheduledFor": "2026-10-10T14:00:00Z",
      "previousStatus": "suspended",
      "reason": "طلب إغلاق موثّق"
    }
  }
}
```

`suspension.reason` and `deletion.reason` are required, whitespace-normalized,
platform-only administrative text of 1–280 characters. Tenant-facing status
copy remains generic. `suspension` is retained while a previously suspended
tenant is pending deletion so cancellation can restore the exact prior state.
`deletion.deletedAt` exists only in the final command response before the full
resource is removed. All timestamps are backend-issued RFC 3339 UTC instants.

##### The sole legal transition table

| Current | Command | Next | Rule |
| --- | --- | --- | --- |
| `active` | suspend | `suspended` | reason required |
| `suspended` | reactivate | `active` | subscription/features/limits unchanged |
| `active` | begin deletion | `deletion_pending` | remember `previousStatus=active`; reason required |
| `suspended` | begin deletion | `deletion_pending` | remember `previousStatus=suspended` and suspension metadata; reason required |
| `deletion_pending` | cancel deletion | recorded previous status | allowed only while `now < scheduledFor` |
| `deletion_pending` | finalize deletion | `deleted` | allowed only when `now >= scheduledFor`; backend destructive operation |
| `deleted` | any ordinary command | refused | terminal; no reactivation path |

Every unlisted transition returns `invalid_tenant_transition`; callers never
assign the enum directly. Cancellation restores the prior operational state,
not unconditionally `active`. `deletion_pending` is a grace/scheduling stage,
not physical deletion: all canonical data/config remains until finalization.

The Flutter mock uses a deterministic **provisional 30-day deletion window**.
That is not a product retention rule. The backend must obtain the duration from
platform policy/configuration and return the authoritative `scheduledFor`.
This is separate from, and does not alter, Point 7's separately provisional
14-day trial-to-grace mock behavior.

##### Commands, concurrency, and retry

All five endpoints require an independently authorized `super_admin` platform
session, server-side policy authorization, `expectedVersion`, and an
`Idempotency-Key` header. They are online-only: Flutter refuses offline writes,
does not enqueue them in the tenant operational outbox, and does not claim
success. The server compares `expectedVersion` atomically with the lifecycle
version and returns `409 stale_tenant` without mutation on mismatch.

- `POST /platform/tenants/{tenantId}/lifecycle/suspend`
  `{ "reason": "…", "expectedVersion": 4 }`
- `POST /platform/tenants/{tenantId}/lifecycle/reactivate`
  `{ "expectedVersion": 5 }`
- `POST /platform/tenants/{tenantId}/lifecycle/deletion/begin`
  `{ "reason": "…", "expectedVersion": 4 }`
- `POST /platform/tenants/{tenantId}/lifecycle/deletion/cancel`
  `{ "expectedVersion": 5 }`
- `POST /platform/tenants/{tenantId}/lifecycle/deletion/finalize`
  `{ "expectedVersion": 5 }`

The success body contains `tenantId`, `displayNameSnapshot`, the new
`lifecycle`, and `changed`. Replaying the same key with the same command returns
the original authoritative result safely (`changed=false` is acceptable);
reusing it for a different tenant/action/version/body returns
`409 idempotency_conflict`. Suspending twice or beginning deletion twice with a
new key is an invalid transition, not a second mutation or schedule.
Finalization retries must return the same terminal result/tombstone safely.

Typed failures are deliberately small:
`tenant_not_found`, `invalid_tenant_transition`, `invalid_lifecycle_reason`,
`stale_tenant`, `deletion_window_expired`, `deletion_not_effective`,
`tenant_already_deleted`, `idempotency_conflict`, and `not_permitted`, plus the
shared safe server failure. `offline` is a client transport outcome. Messages
are display copy, never control flow. Finalization should additionally enforce
the platform's privileged-action policy and may require recent backend MFA or
reauthentication; a client checkbox/typed phrase is accidental-action
protection, not authentication and not break-glass authority.

##### Access/session consequences and enforcement order

For a real tenant user, enforcement order is: authentication/session validity,
account lifecycle, `SaasTenant` lifecycle, correct role/surface, tenant Feature
Flag, Capability, then a relevant Plan Limit. `suspended`,
`deletion_pending`, and `deleted` are **FULL BLOCK** states for both Main Admin
and Simple Admin: the operational shell/repositories must not open, no deep link
may bypass the startup classifier, and no individual capability grants an
exception. If read/export-only access is desired later, it requires a distinct
restricted-access lifecycle mode and backend authorization design.

A lifecycle mutation does not revoke the person's identity or synthetically
expire an authentication session. The backend must nevertheless apply the new
tenant state on every subsequent protected request and session refresh, reject
mutations immediately, and invalidate/push/refresh session projections so an
open client leaves the operational shell. Super Admin platform access is not
blocked by the managed tenant's lifecycle. Customer Demo accounts are not
`SaasTenant`s and these endpoints must reject them.

An offline client cannot know about a remote suspension immediately. When
connectivity resumes it must revalidate lifecycle before protected work, while
the server already rejects the work. Suspension alone does not erase local
cache, but known suspension blocks the shell. Final deletion requires a future
cache/session/access-mapping invalidation or purge policy; Flutter must not
claim that it has erased server data or backups.

##### Final destructive deletion and tombstone

The final endpoint asks the backend to perform the destructive operation; the
mobile client never deletes storage directly, manages encryption keys, or
claims to crypto-shred. The backend must remove/invalidate tenant-owned
operational data and configuration according to policy, including detachments,
DetachmentGroups, shifts, member/team operational records, inventory,
workshops, reports/exports, announcements, feature configuration, plan/limit
overrides, tenant sessions/access mappings, Team Code mapping, object storage,
caches, and search indexes. It must separately define primary-data deletion,
export handling, backup retention, log/audit retention, legal holds, and
encryption-key destruction/cryptographic erasure where supported. Flutter stays
database- and implementation-neutral and must not promise instant physical
erasure from retained backups.

After success the normal `SaasTenant` resource no longer resolves as an active
resource. A backend may retain only this minimal control-plane tombstone:

```json
{
  "tenantId": "saas_hilal",
  "displayNameSnapshot": "فرق الهلال الطبية",
  "status": "deleted",
  "deletedAt": "2026-10-10T14:00:00Z",
  "lifecycleVersion": 6,
  "historyReference": "opaque-reference"
}
```

It contains no Team Code, Main Admin/email, subscription, plan/limits, feature
configuration, deletion reason, usage, counts, or operational record. The old
Team Code must stop resolving for onboarding and must not be immediately
reused; the backend owns an explicit long-term reuse policy. Account credentials
are not a field on this resource, but tenant access mappings and sessions cease
to grant operational access. The display-name snapshot can still identify a
customer, so tombstone access remains restricted to the control plane and its
approved retention purpose.

The client keeps `/platform/tenants/{tenantId}` as the smallest stable route
and renders either the full live resource or this dedicated tombstone shape;
it never coerces a tombstone into `SaasTenant`. A real backend must therefore
make the authorized tombstone available through a typed restricted read (or an
authoritative final-command result plus equivalent reload seam) when that route
is expected to survive refresh. Normal tenant list/search responses continue
to exclude tombstones.

Tenant lifecycle history adds `tenant_suspended`, `tenant_reactivated`,
`deletion_requested`, `deletion_cancelled`, and `tenant_deleted`; its short
reason note is platform administrative metadata. This chronology is not Point
11's immutable platform audit. The backend must later emit actor-attributed
platform audit/security events for these commands, and policy may retain that
minimal compliance evidence after tenant data deletion. Tenant data deletion
therefore does not necessarily mean platform audit deletion.

#### Subscription, plans, usage and limits (Point 7)

**STATUS: implemented frontend-first through `TenantSubscriptionRepository`
and the canonical process-memory tenant store. The endpoint family below is a
backend-neutral future contract. It marks no payment as collected and assumes
no billing provider.**

##### Representations

```json
{
  "subscription": {
    "status": "trial",
    "planId": null,
    "version": 4,
    "trialEndsAt": "2026-09-18T16:00:00Z",
    "renewsAt": null,
    "graceEndsAt": null,
    "limitOverrides": {"detachments": 18}
  },
  "currentPlan": null
}
```

`currentPlan: null` is valid only for the explicit no-plan assignment. The
client models this as `NoSaasPlan`, not as a failed plan lookup. If `planId` is
present but cannot be resolved, return `plan_not_found`; do not silently show a
no-plan state.

```json
{
  "id": "mtm_standard",
  "name": "ليدر القياسية",
  "description": "للفرق النشطة متعددة المفارز.",
  "recommended": true,
  "selectable": true,
  "defaultLimits": {
    "detachment_groups": 5,
    "detachments": 15,
    "admins": 8,
    "members": 300,
    "workshops": 40,
    "storage_bytes": 21474836480
  }
}
```

`PlanLimitKey` is the closed wire set `detachment_groups | detachments |
admins | members | workshops | storage_bytes`. Values are non-negative
integers; storage is always bytes. Point 7 deliberately has no unlimited
sentinel and no magic large number. A plan is a reusable definition; it is not
copied into each tenant record.

```json
{
  "tenantId": "saas_afiah",
  "plan": {"id": "mtm_standard", "defaultLimits": {}},
  "subscription": {"version": 7, "limitOverrides": {"detachments": 20}},
  "usage": {
    "detachment_groups": 4,
    "detachments": 15,
    "admins": 1,
    "members": 233,
    "workshops": 19,
    "storage_bytes": 4508876800
  }
}
```

The effective value is exactly `tenant override ?? plan default`, per key.
Deleting an override resets that key to the plan default. Usage is a
platform-supplied aggregate: the client must not query tenant-operational
repositories to count it.

##### Reads

- `GET /platform/tenants/{tenantId}/subscription` → subscription snapshot and
  resolved `currentPlan`; `404 not_found` for an unknown tenant.
- `GET /platform/plans` → the small ordered plan catalogue. Unselectable plans
  remain readable for an existing assignment but reject new selections.
- `GET /platform/tenants/{tenantId}/limits` → selected plan, subscription
  version, typed current usage, defaults, overrides and therefore all effective
  limits. A valid explicit no-plan subscription returns `409 plan_not_found`
  for this limits projection; it must not invent defaults.

##### Mutations

Every request includes `expectedVersion`, and every success returns the new
snapshot/version. A version mismatch returns `409 stale_subscription` without
changing state. Consequential requests also require an `Idempotency-Key`
header; replaying the same key and body returns the original result, while the
same key with a different body is a conflict.

- `POST /platform/tenants/{tenantId}/subscription/activate`
  `{ "planId": "mtm_standard", "expectedVersion": 4 }`. Legal from
  `trial | grace | inactive`; returns `invalid_subscription_transition` from
  `active`. This is an administrative state change only: it neither charges a
  payment method nor proves payment.
- `POST /platform/tenants/{tenantId}/subscription/trial/extend`
  `{ "newEndsAt": "2026-09-25T16:00:00Z", "expectedVersion": 4 }`. Legal
  only from `trial`. The UTC date must be later than both the current instant
  and current expiry; otherwise `invalid_trial_extension`.
- `POST /platform/tenants/{tenantId}/subscription/trial/end`
  `{ "expectedVersion": 4 }`. Legal only from `trial`. Point 7 defines the
  non-destructive result as `trial → grace` using the backend-owned grace
  duration. It does not suspend or delete the tenant.

  **BACKEND-CRITICAL — the current 14-day Flutter mock is provisional, not a
  product rule.** It was selected only to make the Point 7 frontend flow
  deterministic. A backend must not permanently hard-code fourteen days
  without explicit product-owner approval. Before this operation is finalized,
  product must choose the post-trial policy: a platform-configurable grace
  duration (preferred when it fits the subscription architecture), a direct
  transition to `inactive`, or another explicit platform-configured policy.
  The approved policy and its effective configuration must be returned by the
  authoritative subscription contract; the client must not infer it.
- `POST /platform/tenants/{tenantId}/subscription/grace`
  `{ "expectedVersion": 4 }`. Legal only from `active`; records a grace end
  timestamp and leaves the entire tenant `lifecycle` untouched.
- `POST /platform/tenants/{tenantId}/subscription/plan`
  `{ "planId": "mtm_advanced", "expectedVersion": 4 }`. Valid in any known
  commercial state. `plan_not_found` or `plan_unavailable` is returned before
  mutation. Existing tenant overrides remain explicit and are re-evaluated
  against the new defaults.
- `PATCH /platform/tenants/{tenantId}/limits/{limitKey}`
  `{ "overrideValue": 5, "expectedVersion": 4 }`. `overrideValue: null`
  removes the override and resets to the plan default. Negative/non-integer
  values return `limit_invalid`.

##### Limit enforcement semantics

The backend **may accept a limit below current usage**. Doing so never deletes,
hides or truncates existing data. It prevents future creates of that resource
type until usage becomes lower than the effective limit. The future
tenant-operational create endpoints are authoritative and must return the typed
`plan_limit_reached` result; Point 7 does not retrofit every tenant controller
with local enforcement. The platform response should return the current usage
again so the confirmation can be revalidated under concurrency.

Writes are online-only in this frontend. `offline` refuses the operation and
is never sent to the tenant operational outbox. Other typed errors used by this
family are `subscription_not_found`, `invalid_subscription_transition`,
`invalid_trial_extension`, `plan_not_found`, `plan_unavailable`,
`limit_invalid`, `stale_subscription`, `not_found`, `not_permitted`, `offline`
and `server`. Messages are not control flow. Platform authorization is still
the `super_admin` surface role gate in the frontend mock; no tenant capability
authorizes these calls.

#### Tenant product features (Point 8)

**STATUS: implemented frontend-first through a dedicated
`TenantFeatureRepository` over the same canonical `PlatformTenantStore` as the
Point 6/7 subscriber data. The endpoint pair below is the backend-neutral
future contract.** A feature answers only whether a `SaasTenant` has a product
module. It is not a user capability and it is not a plan limit.

##### Catalogue and representation

The closed feature-key catalogue understood by this client is:

```text
inventory
statistics_reports
workshops
announcements
```

```json
{
  "tenantId": "saas_hilal",
  "tenantName": "فرق الهلال الطبية",
  "features": [
    {
      "key": "inventory",
      "enabled": true,
      "version": 4,
      "updatedAt": "2026-09-09T15:20:00Z"
    }
  ]
}
```

- `tenantName` is the platform-safe display context used by the settings
  screen. It is not an authorization or lookup key.
- `key` is a canonical ASCII wire value, never an Arabic display label.
- `enabled` is a boolean. If a future backend sends an unsupported state such
  as `preview`, `read_only` or `retiring`, this client treats it as disabled.
- `version` is a positive, monotonically increasing optimistic-concurrency
  token **for that tenant-feature row**. `updatedAt` is an RFC 3339 instant.
- An unknown `key` is retained only as optional diagnostic input, is not
  rendered as a generic row, and grants no route, navigation item, search
  source or notification source. **Unknown feature = disabled.**
- A known key absent from the tenant response is also disabled. There is no
  implicit "the old app had it" compatibility default. Migration must create
  explicit rows for existing tenants.
- The current new-tenant mock creates all four explicit rows, enabling only
  `inventory` and `announcements`. This is an explicit product default for the
  frontend fixture, not inferred from a plan. A future product decision may
  change initial values, but the resulting tenant feature state remains an
  independent entitlement.

##### Reads and mutation

- `GET /platform/tenants/{tenantId}/features` returns the representation above.
  `404 tenant_not_found` means no subscriber; `feature_not_found` means the
  subscriber exists but no authoritative feature state can currently be read.
- `PATCH /platform/tenants/{tenantId}/features/{featureKey}` accepts:

  ```json
  {
    "enabled": false,
    "expectedVersion": 4
  }
  ```

  It returns the updated feature row. A version mismatch returns HTTP 409
  `stale_feature_state` and makes no change. An unknown path key returns
  `invalid_feature`; a known key with no authoritative row returns
  `feature_not_found`. `not_permitted`, `offline` and a small safe server
  failure complete the client taxonomy. Error messages are never control flow.

This platform mutation is online-only. It is never placed in the tenant
operational outbox and the Flutter client leaves the visible state unchanged
when persistence is refused. The controller prevents simultaneous duplicate
writes. The real transport should require `Idempotency-Key`: replay of the same
key and body returns the original result; reuse with a different body is a
conflict. Platform authorization is `super_admin`-only in the current client;
the server must independently authorize every read and mutation.

##### Enforcement and retention

**Disabling a feature removes access; it never deletes, truncates, archives or
resets the module's existing records or usage.** Re-enabling exposes the same
records again, subject to current capabilities. The mutation response does not
pretend to perform operational deletion and does not reset plan usage.

Flutter navigation hiding and route guards are UX/defense-in-depth only. The
backend must apply the same feature check before every disabled-module read,
write, export and search operation and return `feature_disabled`; a modified or
older client must not bypass it. After feature availability succeeds, the
backend must still check the administrator's capability. Plan limits remain a
third, independent check on quantities and mutations:

```text
authenticated tenant scope
  -> feature enabled
  -> user capability
  -> plan/usage limit where the operation creates or consumes capacity
```

Feature state is tenant-wide. Main Admin and Simple Admin accounts with the
same authenticated `saasTenantId` receive the same feature set; their different
experience comes from capabilities. Tenant sessions derive `tenantId` from the
verified token, never from organisation name, Team Code, email or selected
detachment. Customer Demo sessions have no real `saasTenantId`, never call this
resource and remain governed by a separate future Demo entitlement contract.

The mock updates live consumers through an in-process revision invalidation. A
real application must refresh this projection at session/config refresh, push
invalidation, or the next API load; Point 8 does not prescribe WebSockets.
Server-side enforcement is authoritative even while a client holds a cached
enabled state.

##### Initial Main Admin provisioning — what Point 6 deliberately does not do

The approved workflow is that the Super Admin registers the subscriber and
identifies its initial Main Admin, and the Main Admin then completes a verified
first-time setup: email-ownership proof by OTP, the Team Code, and a forced
password change on first sign-in. **Point 17A supersedes the last step:** the
invitee sets their own password at sign-up (or uses Google), so no temporary
password ever exists to be changed — see "Sign-up and onboarding — Point 17A
foundation".

**Point 6 models only the platform side of that: the Main Admin's identity and
the `pending_setup` state.** It does not generate, display, transmit or store a
temporary password, and the create response must not carry one. The reason is
not squeamishness: a password minted in the client is not a credential any
backend agreed to, and in the real flow the client never receives a stored
password at any point. Whatever mechanism eventually delivers the first
credential — an emailed one-time link, an OTP challenge, an out-of-band
handover — is owed by the authentication Point, and it inherits nothing here
that it has to undo.

**Still owed by the backend for this resource:** the invitation/first-setup
endpoint family (Point 14A now fixes its Platform side — setup state, resend,
replacement and seat transfer — in "Main Admin account management — Point 14A
foundation"; the invitee's own flow stays Point 17); the concurrency-safe uniqueness constraint on `teamCode`; the
rule that a tenant session can never write `teamCode`; and the authorization
model that decides which platform operator may call `POST /platform/tenants` at
all (see "Platform authorization" below — it is still undesigned, and Point 6
adds no capability key).

#### Platform route/resource families

Named so the implemented client seams and later planned modules stay distinct:

| Client route family | Resource family (planned) | Point |
| --- | --- | --- |
| `/platform` | platform overview aggregate (`GET /platform/overview`) | **implemented in the client at Point 5** |
| `/platform/tenants`, `/platform/tenants/:tenantId`, `/platform/tenants/new` | `SaasTenant` — list/search/filter, detail, create, status history | **implemented in the client at Point 6** (see above) |
| `/platform/tenants/:tenantId/subscription`, `/platform/tenants/:tenantId/limits` | subscription/trial/plan and plan-limit reads and mutations | **implemented in the client at Point 7** (see above) |
| `/platform/tenants/:tenantId/features` | tenant product-feature reads and one-feature mutations | **implemented in the client at Point 8** (see above) |
| `/platform/tenants/:tenantId` — tenant lifecycle actions | five versioned lifecycle commands | **implemented in the client at Point 9** (see above) |
| `/platform/audit` | immutable, actor-attributed Platform Audit Log read | **Point 11 implemented in Flutter; authorized backend read/append remains required** |
| `/platform/access` | break-glass grant read/activate/end (`/platform/break-glass/*`) | **Point 12 frontend complete; backend and grant-scoped tenant-data viewer still required** |
| `/platform/reports` | four synchronous report projections (`/platform/reports/*`) | **Point 13 COMPLETE in Flutter (13A domain/seam/mock, 13B core UX, 13C visual/accessibility closure); backend projections still required** |
| `/platform/tenants/:tenantId/main-admin` (+ `/replace`) | Main Admin seat read + five commands (`/platform/tenants/{tenantId}/main-admin/*`) | **Point 14 COMPLETE in Flutter (14A domain/seam/mock, 14B core UX, 14C visual/accessibility closure)**; backend remains future |
| `/platform/operations` and its modules | customer demo accounts, cross-tenant subscription operations, platform health, alerts, audit, break-glass access | 7–12 |
| `/platform/more/*` | none — the account endpoints above | — |

**Customer demo accounts are not `SaasTenant`s** and the platform contract must
not assume every managed account belongs to one. A customer demo has no
`saasTenantId` and lives in an isolated, ephemeral workspace. **Point 18B:**
it is started self-service from the verified-unlinked post-verification
decision while
the Platform's global demo policy is enabled; `super_admin` owns only that
policy (enabled, duration, cleanup), never per-user creation, and a
`main_admin` owns nothing about it. See "Customer Demo — final policy".

#### Platform authorization

Fine-grained platform permissions are still undesigned, deliberately. The 30
keys in `Cap` are all tenant-operational; `super_admin` holds none of them and
none may be borrowed. Every platform endpoint must still authenticate and
authorize the actor server-side. In particular, Point 9 lifecycle commands
must never rely on the Flutter route/role check, and final deletion may apply a
stronger recent-authentication/policy requirement.
`Cap.all` must **not** be granted to a platform account as a stand-in for
platform authority — it would assert that the platform owner is a very powerful
team admin, which is the one thing the product model denies. Platform
capabilities arrive with the platform resources they authorize.
Point 14 Main Admin account management is `super_admin`-only on the same
basis: no `Cap` authorizes it, the Main Admin remains a tenant role, and the
Super Admin never becomes one or acts as one.
A Point 12 break-glass grant is neither: it is a separate, session-bound,
expiring, read-only authorization for one tenant, enforced per request as
specified in "Break-glass emergency access — Point 12 complete" above, and it never
changes the account's role, `saasTenantId`, or capabilities.

#### Still owed by the backend, and named here so it is not forgotten

- **Platform authorization.** `super_admin` opens the platform surface and
  holds no key in `Cap`, all thirty of which are tenant-operational. Platform
  operations still need a fine-grained authorization design. Until one exists,
  the backend must at minimum enforce its independently authorized platform
  session and action policy; client role-gating is never sufficient.
- **A `SaasTenant` resource.** Specified at Point 6 above for list, detail,
  create and status history, with Point 7–9A mutation contracts above. The
  backend implementation, concurrency-safe `teamCode` uniqueness constraint,
  retired-code policy, and rule that a tenant session can never write
  `teamCode` are still owed.
- **First-time setup.** `pending_setup` names the state and Point 6 now *sets*
  it when a subscriber is registered; the flow that leaves it is specified by
  Point 17A in "Sign-up and onboarding — Point 17A foundation" (address proof →
  Team Code + authorization → setup; **no temporary password and no forced
  password change**). The client still collects, generates and stores no
  bootstrap credential.
- **Main Admin seat (Point 14A).** The seat resource, five commands, atomic
  transfer on designate setup completion, session termination, email
  uniqueness and Audit append — see "Main Admin account management — Point 14A
  foundation" above.
- **Platform Reports (Point 13A).** Four authorized synchronous report
  projections, snapshot-bound cursors, a real `admins` usage aggregate, and an
  Audit count projection honouring retention — see "Platform Reports — Point
  13A foundation" above. No export and no historical snapshots exist.
- **Customer Demo.** Policy and semantics are **final** (Point 18B — "Customer
  Demo — final policy"; `BACKEND-HANDOFF.md` §12). The Super Admin management
  screen has shipped; the client-side control plane behind it is **process
  memory, development/test only**, and is not persistence. The backend still
  owes every authoritative part: the global policy store and its endpoints, the
  start endpoint (atomic, resume-on-duplicate), the holder's session read,
  session list/terminate/terminate-all/cleanup, workspace isolation,
  server-authoritative expiry/termination, the four Audit events, and the
  Overview demo counts.

### MfaSetupData

```json
{
  "otpauthUrl": "otpauth://totp/Leader:user@example.org?secret=SERVER_ISSUED&issuer=Leader",
  "manualSecret": "SERVER_ISSUED",
  "backupCodes": ["CODE-ONE", "CODE-TWO"]
}
```

### Session

```json
{
  "id": "s_123",
  "device": "Device and client",
  "ipMasked": "192.0.xx.xx",
  "locationLabel": "City, Country",
  "startedAt": "2026-09-02T14:30:00Z",
  "current": true
}
```

### DetachmentGroup

```json
{
  "id": "g_123",
  "name": "Group name",
  "createdAt": "2024-03-12T00:00:00Z",
  "notes": "Optional internal notes",
  "status": "active",
  "detachmentCount": 3,
  "memberCount": 48,
  "coveragePercent": 82
}
```

`status` is one of `active`, `archived`. `notes` is optional.

The last three properties are **derived roll-ups over the detachments inside
the group**, not stored columns. `detachmentCount` is how many detachments name
this group and `memberCount` is the sum of their `memberCount` — both count
archived detachments, which still belong to the group. `coveragePercent` is the
rounded mean of `coveragePercent` over the **active** detachments only, and `0`
when there are none: averaging a dormant zero into a live number would read as
a failure. The server computes all three on read, so a card can never disagree
with the list behind it. A client that receives them absent reads each as `0`.

A `DetachmentGroup` is the **local grouping inside one SaasTenant** — one
branch, one operating area. It is not the SaasTenant and carries no
subscription, billing, or isolation meaning; see **Terminology**. The Flutter
type was called `Tenant` before the Point 1 rename, which is the collision that
rename removed.

### Detachment

```json
{
  "id": "d_123",
  "detachmentGroupId": "g_123",
  "name": "Detachment name",
  "region": "Region",
  "mainCenter": "Main center",
  "memberCount": 10,
  "weeklyShiftCount": 4,
  "coveragePercent": 90,
  "status": "active",
  "notes": "Optional internal notes"
}
```

`status` is one of `active`, `archived`. `notes` is optional.

`detachmentGroupId` names the `DetachmentGroup` this detachment belongs to —
the local grouping, not the SaasTenant (see **Terminology**). Every detachment
has exactly one; there is no unfiled detachment, because the group is what a
detachment is created inside.

### DetachmentStats

```json
{
  "attendanceSeries": [82, 85, 88, 86, 91, 90, 92],
  "coverageSeries": [90, 90, 95, 95, 100, 95, 100],
  "stockSeries": [3, 7, 5, 8, 4, 6, 5]
}
```

Each series contains the last seven days, oldest first.

### TeamMember

```json
{
  "id": "m_123",
  "name": "Member name",
  "initials": "MN",
  "role": "medic",
  "detachmentId": "d_123",
  "attendance": "present",
  "phoneMasked": "+963 9xx xxx 123"
}
```

`role` is one of `lead`, `medic`, `trainee`, `volunteer`. `attendance` is one
of `present`, `late`, `absent`, `notInvited`. `phoneMasked` is optional and,
when present, is already masked by the server.

### Shift

```json
{
  "id": "sh_123",
  "detachmentId": "d_123",
  "centerName": "Center name",
  "startHour": 8,
  "endHour": 14,
  "assigned": 2,
  "needed": 3,
  "hasCoverageGap": true,
  "attendees": [
    {
      "id": "m_123",
      "name": "Member name",
      "initials": "MN",
      "role": "medic",
      "detachmentId": "d_123",
      "attendance": "present",
      "phoneMasked": "+963 9xx xxx 123"
    }
  ],
  "corrections": [
    {
      "id": "corr_1",
      "memberId": "m_123",
      "before": { "status": "notCheckedIn" },
      "after": { "status": "checkedIn", "checkInAt": "2026-07-09T08:03:00.000" },
      "reason": "نسي المشرف تسجيل الدخول وقت الشفت",
      "author": { "id": "u_9", "displayName": "أحمد المشرف" },
      "correctedAt": "2026-07-12T10:00:00.000"
    }
  ]
}
```

Hours are whole local-clock hours in the range accepted by the backend.
`attendees` contains full `TeamMember` payloads. `corrections` is append-only
(oldest first), omitted or empty when the shift has never been corrected —
see `ShiftRepository.addAttendanceCorrection` and
`FRONTEND-BACKEND-INTEGRATION.md` §6. `author.id` is for internal
traceability only; the client never renders it, only `author.displayName`.

### InventoryItem

```json
{
  "id": "i_123",
  "detachmentId": "d_123",
  "name": "Item name",
  "unit": "box",
  "currentStock": 12,
  "minimum": 5,
  "expiresOn": "2027-03-15T00:00:00.000Z",
  "level": "ok"
}
```

`level` is one of `ok`, `low`, `empty`. `expiresOn` is optional.

### InventoryMovement

```json
{
  "id": "mv_123",
  "itemId": "i_123",
  "direction": "outflow",
  "quantity": 2,
  "reason": "Shift issue",
  "at": "2026-09-02T14:30:00Z"
}
```

`direction` is one of `inflow`, `outflow`.

### Workshop

```json
{
  "id": "w_123",
  "name": "Workshop name",
  "at": "2026-09-12T09:30:00Z",
  "location": "Training hall",
  "capacity": 20,
  "registered": 18,
  "guests": 3,
  "status": "scheduled",
  "registrationFee": 25000,
  "archived": false,
  "organizingTeam": [
    {
      "id": "m_123",
      "name": "Member name",
      "initials": "MN",
      "role": "lead",
      "detachmentId": "d_123",
      "attendance": "present"
    }
  ]
}
```

`status` is one of `scheduled`, `ongoing`, `done`. `organizingTeam` contains
full `TeamMember` payloads — roster members who run the workshop, whose
`attendance` belongs to *this* workshop rather than to their roster record.

`registered` and `guests` are **server-derived counts of the register**:
`registered` is every participant (members and guests), `guests` the guest
subset. The client never sends them and never keeps its own copy — the
workshop card, the capacity check and the statistics all read these.

`archived` (optional, default `false`) is the workshop's archive state.
An archived workshop stays readable and exportable; every mutation on it,
and on its register, must be refused with `archived`.

### WorkshopParticipant

```json
{
  "id": "p_123",
  "workshopId": "w_123",
  "name": "Participant name",
  "initials": "PN",
  "kind": "member",
  "memberId": "m_123",
  "attendance": "notInvited",
  "paymentStatus": "paid"
}
```

`kind` is one of `member`, `guest`. `attendance` uses the `TeamMember`
attendance values.

`memberId` is the roster member this line refers to. It is **required for
`kind: "member"`** and absent for a guest; `name` and `initials` are a display
snapshot taken when the person was registered, so a later rename or roster
deletion leaves the register readable. Clients may still receive an older
member line without `memberId`.

`paymentStatus` is `paid`, `unpaid`, or **absent** — and absent is a third
meaningful state, "not recorded yet". It must never be serialized as `unpaid`.

### HomeDecisionItem

```json
{
  "id": "decision_123",
  "kind": "unfilledShift",
  "title": "Decision title",
  "subtitle": "Decision details",
  "actionLabel": "Open"
}
```

`kind` is one of `unfilledShift`, `expiringStock`, `joinRequest`.

### HomeSummary

```json
{
  "detachmentName": "Detachment name",
  "centerName": "Center name",
  "activeShift": {
    "id": "sh_123",
    "detachmentId": "d_123",
    "centerName": "Center name",
    "startHour": 8,
    "endHour": 14,
    "assigned": 2,
    "needed": 3,
    "hasCoverageGap": true,
    "attendees": []
  },
  "lockRemainingSec": 1800,
  "attendancePresent": 2,
  "attendanceTotal": 3,
  "decisions": [
    {
      "id": "decision_123",
      "kind": "unfilledShift",
      "title": "Decision title",
      "subtitle": "Decision details",
      "actionLabel": "Open"
    }
  ],
  "workshopsThisWeek": 2,
  "attendanceRatePercent": 90,
  "stockLowCount": 3
}
```

`activeShift` and `lockRemainingSec` are optional.

### AppNotification

One row of the Notifications Center. `target` is a pointer, never a snapshot:
the client re-reads the record it names at the moment the user taps the row,
which is what makes a deleted shift a handled state rather than a crash.

```json
{
  "id": "shiftUnderstaffed:sh_412",
  "kind": "shiftUnderstaffed",
  "occurredAt": "2026-09-05T14:00:00+03:00",
  "count": 2,
  "recordLabel": "مركز الشعلان",
  "target": { "type": "shift", "detachmentId": "d_12", "shiftId": "sh_412" },
  "isRead": false
}
```

`kind` is one of `shiftUnderstaffed`, `shiftAttendanceMissing`,
`shiftStartingSoon`, `stockDepleted`, `stockLow`, `stockExpiring`. The two
remaining client-side kinds (`syncConflict`, `syncFailed`) are derived from
the local outbox and are **never** expected on this payload.

`target.type` is one of `shift`, `storage`, `review`, `sync`. An unrecognised
`type` is dropped by the client, and the row then renders as informational
rather than sending the user somewhere arbitrary. A row with no `target` at
all is valid and renders as informational — that is the shape a future
server-sent announcement takes.

**`id` must be stable for as long as the condition is.** Read state is keyed
by it, and the client rebuilds its own derived feed on every load; an id
regenerated per fetch would silently un-read every row the user had already
seen. `<kind>:<record id>` is what the client generates and what it expects
back.

`count` is the magnitude behind the row — volunteers still missing, attendance
still unrecorded, units left — and `0` when the kind has no count.
`recordLabel` is a real name from the record (a centre, a stock item), never
an id and never an internal tag.

### Announcement

An **internal operational notice** sent between administrators. Not advertising,
not a public announcement, and never delivered to volunteers — nobody but an
administrator signs into this app.

Not implemented by any backend yet. The client ships a repository seam and a
mock; this is the shape a real implementation is expected to serve.

```json
{
  "id": "a_9f21",
  "text": "تنبيه بخصوص شفت ٤:٠٠–١٠:٠٠ اليوم، يرجى الحضور قبل بداية الشفت بـ١٥ دقيقة.",
  "detachmentIds": ["d_12", "d_14"],
  "placements": ["notifications", "home", "detachment"],
  "publishedAt": "2026-09-07T10:00:00+03:00",
  "expiresAt": "2026-09-08T10:00:00+03:00",
  "status": "active",
  "authorName": "أحمد عبد الكريم"
}
```

`text` is **plain text**, trimmed, 5–500 characters. There is no rich text, no
formatting, no attachment and no image, and the client will not send one. An
announcement that concerns a shift says so in words — it carries no shift id,
no member id and no item id, deliberately.

`detachmentIds` is **never empty and never a wildcard**. There is no
"all detachments" value in the model; if that is ever a product requirement it
is a separate decision and a separate field. Order is the author's, duplicates
removed.

`placements` is a subset of `notifications`, `home`, `detachment`.
`notifications` is **always present** — it is the durable history surface — and
the client re-asserts it on parse, so a payload that omits it is corrected
rather than producing an announcement nobody can find later. An unrecognised
placement is dropped.

`status` is `active` or `withdrawn`. An unknown value reads as `active`.

`authorName` is a display name or absent. Never an id, never an email.

**Two lifetimes, and they are not the same thing.** `expiresAt` ends the
announcement's *active placements*. The Home placement additionally ends
**exactly one hour after `publishedAt`** — that rule is client-side and needs no
field. Neither ends the Notifications Center entry, which is history: it is
removed only when an administrator clears notification history.

### NotificationPrefs

```json
{
  "shiftReminders": true,
  "stockAlerts": true,
  "workshopUpdates": true,
  "joinRequests": false
}
```

### OrgInfo

```json
{
  "name": "Organization name",
  "legalName": "Legal organization name",
  "address": "Public address",
  "emailPublic": "contact@example.org",
  "detachmentCount": 5,
  "memberCount": 25
}
```

## Endpoints

The response type names below refer to the canonical JSON payloads above.

### Authentication

#### `AuthRepository.signIn`

`POST /api/v1/auth/sign-in` — public

Request:

```json
{
  "emailOrUsername": "user@example.org",
  "password": "user-supplied password"
}
```

Response `200`:

```json
{
  "accessToken": "opaque-access-token",
  "refreshToken": "opaque-refresh-token",
  "user": {
    "id": "u_123",
    "name": "User Name",
    "email": "user@example.org",
    "role": "main_admin",
    "saasTenantId": "saas_123",
    "capabilities": {
      "global": ["workshop.create"],
      "scoped": {
        "d_123": ["detachment.view", "member.view"]
      }
    },
    "orgName": "Organization Name",
    "avatarInitials": "UN"
  }
}
```

The `user` property is an exact `AuthUser` payload.

**Point 18A correction — one sign-in endpoint, the Point 17A shape wins.** This
section predates Point 17. The product login (`/login`) no longer calls
`AuthRepository.signIn`; it calls `OnboardingRepository.signInWithPassword`,
which uses the **same path** with request `{email, password}` and the 17A
**outcome** union (`ready` with tokens, then `GET /auth/me` ·
`verification_required` · `onboarding`) — see "Sign-up and onboarding".
`AuthRepository.signIn` with `emailOrUsername` and the flat token+user body
above survives only behind the debug-only developer persona section. The
backend implements the outcome shape. Login is by **email** only (the client
refuses a non-email locally). **Point 18B:** the `/login` field label now
reads "البريد الإلكتروني" (the "أو اسم المستخدم" leftover is gone). Login
identity is **email only**; username authentication is future scope and no
endpoint accepts a username. `emailOrUsername` above is the historical
developer-persona shape only.

#### `AuthRepository.beginMfaSetup`

`POST /api/v1/auth/mfa/setup` — access bearer required

Request: no body.

Response `200`: `MfaSetupData` JSON.

#### `AuthRepository.verifyMfa`

`POST /api/v1/auth/mfa/verify` — access bearer required

Request:

```json
{
  "code": "123456"
}
```

Response `204`: no body.

#### `AuthRepository.requestPasswordReset`

`POST /api/v1/auth/password-reset/request` — public

Request:

```json
{
  "email": "user@example.org"
}
```

Response `200`:

```json
{
  "resetToken": "opaque-reset-token"
}
```

The client keeps this token only for the active reset flow.

#### `AuthRepository.verifyResetOtp`

`POST /api/v1/auth/password-reset/verify` — reset bearer required

Request:

```json
{
  "email": "user@example.org",
  "code": "123456"
}
```

Response `204`: no body.

#### `AuthRepository.setNewPassword`

`POST /api/v1/auth/password-reset/complete` — reset bearer required

Request:

```json
{
  "password": "new user-supplied password"
}
```

Response `204`: no body. The reset token is invalid after success.

#### `AuthRepository.currentUser`

`GET /api/v1/auth/me` — access bearer required

Request: no body.

Response `200`: `AuthUser` JSON.

When no token exists, the client resolves the repository method to `null`
without making this request. An expired token returns
`authentication_expired`.

#### `AuthRepository.confirmNewDevice`

`POST /api/v1/auth/new-device/confirm` — access bearer required

Request:

```json
{
  "itsMe": true
}
```

Response `204`: no body.

#### `AuthRepository.signOut`

`POST /api/v1/auth/sign-out` — access bearer required

Request: no body.

Response `204`: no body. The submitted session token is revoked.

#### `AuthRepository.listSessions`

`GET /api/v1/auth/sessions` — access bearer required

Request: no body.

Response `200`: JSON array of `Session` objects.

#### `AuthRepository.revokeSession`

`DELETE /api/v1/auth/sessions/{sessionId}` — access bearer required

Request: no body.

Response `204`: no body. Revoking the current session returns `validation`.

#### Token refresh — Point 18B (future backend; final policy)

`POST /api/v1/auth/refresh` — public (the access token may already be
expired; no bearer is required)

Request:

```json
{
  "refreshToken": "opaque-refresh-token"
}
```

Response `200` — the rotated pair, in the same shape as the onboarding
`ready` outcome's credentials:

```json
{
  "accessToken": "opaque-access-token",
  "refreshToken": "opaque-refresh-token-rotated"
}
```

The authoritative session envelope stays `GET /api/v1/auth/me` (`AuthUser` +
`SessionAccess`); the client re-reads it after a refresh exactly as after
sign-in, and never infers anything from the tokens themselves.

Rules:

- **Online-only.** Never queued, never written to the outbox, never retried in
  the background by the sync engine. Offline or a transport failure keeps the
  stored pair and signs nobody out.
- **Rotation.** A successful refresh atomically issues a new refresh token and
  invalidates the presented one; each refresh token is single-use. The client
  replaces the stored record in secure storage in one write and single-flights
  refresh (one in flight per session).
- **Replay detection.** Presenting an already-rotated refresh token is treated
  as theft: the backend refuses it **and revokes the whole token family** (every
  descendant of that session). Whether a just-rotated token gets a very short
  lost-response grace is backend policy; without one, a lost response signs the
  device out — the safe failure.
- **Scope is preserved.** An onboarding-scope refresh token (the
  `onboardingRefreshToken` of a restricted session) yields another
  onboarding-scope pair and never a full session; a full-session token never
  downgrades. Customer Demo sessions refresh like any other until their
  workspace is terminated; a demo's end is expressed by `demoMode: expired`,
  not by a refresh refusal alone.
- **No `Idempotency-Key`.** The single-use refresh token is itself the replay
  guard.
- **Lifecycle is not decided here.** Suspending or revoking an account,
  replacing a Main Admin, sign-out, session revoke and password reset already
  end that account's refresh tokens (so they answer as revoked below). A
  tenant lifecycle block is **not** a refresh refusal: refresh returns
  credentials, the envelope carries `tenantStatus`, and every tenant endpoint
  refuses per the authorization order.
- **Never logged or audited:** the refresh token, the access token, or any
  derivative. Security telemetry records only that a family was revoked for
  replay (a Point 10 security signal, not governance Audit).

Errors (RFC 9457 envelope, branch on `code`):

| Case | Answer |
| --- | --- |
| unknown, malformed, expired | `401 authentication_expired` |
| revoked (sign-out, session revoke, reset, account suspended/revoked, Main Admin replaced) | `401 authentication_expired` |
| replayed (already rotated) | `401 authentication_expired` + the family is revoked |
| account blocked | `401 authentication_expired` — its refresh tokens were ended at the lifecycle change |
| tenant blocked (`suspended`/`deletion_pending`/`deleted`) | not a refusal — see above |
| throttled | `429 rate_limited` + `Retry-After` |
| client too old | `426 upgrade_required` (outranks everything) |

The first four are deliberately **one indistinguishable answer** (same body
and timing), so a token holder learns nothing about why a token failed. The
client handles a final `authentication_expired` from refresh exactly like a
`401` from `GET /auth/me`: it clears the stored credential and routes to
`/session-expired` — never to a local or developer identity.

**Client status:** no HTTP layer exists yet, so no Flutter code calls this
endpoint today; the real `AuthRepository` adds it when it replaces the mock
(`BACKEND-HANDOFF.md` §16).

### Sign-up and onboarding — Point 17A foundation, Point 17B integration, Point 17C closure (future backend)

Typed client: `features/auth/domain/onboarding_models.dart`,
`onboarding_repository.dart`; controller `features/auth/data/
onboarding_controller.dart`; deterministic mock `mock_onboarding_repository.dart`.
Values marked **PROVISIONAL** are the backend's to set; the client hard-codes
none of them.

#### Principles

- **Only administrators authenticate** (`super_admin`, `main_admin`, `admin`).
  Volunteer/member records are never login accounts.
- **Exactly two methods:** email + password, and Google. Apple, phone, magic
  link, passkeys, anonymous and other social providers are future scope.
- **Canonical account id.** Every account has a backend-issued opaque
  `accountId`, independent of email and of every method. Email is the login
  identity and contact address, never the database key. A Platform-provisioned
  Main Admin already has one (Point 14 `accountId`) and **claiming** it keeps it.
- **One account, at most one `SaasTenant`.** Multi-tenant membership and tenant
  switching are future scope; nothing in this contract models them.
- **No public tenant creation.** Sign-up never creates a `SaasTenant`, a plan, a
  role or a grant. A new identity stays unlinked until a Team Code matches an
  authorization or a Simple Admin invitation for its verified address
  auto-links it (Point 17B/17C); an unlinked identity may instead start the
  isolated Customer Demo, which links nothing (Point 18B).
- **Four separate facts, never one flag:** email verification, tenant link,
  account setup, account lifecycle (the existing `accountStatus`).
- **Online-only.** No trust transition is queued, retried in the background or
  written to the operational outbox.

#### Three session tiers

| Tier | Issued when | Token | May call | Must be refused |
| --- | --- | --- | --- | --- |
| **None** (verification pending) | sign-up; password sign-in to an unverified account; Google with `email_verified=false` | none — only an opaque `challengeId` | verify, resend | everything else |
| **Onboarding session** (restricted) | a verified account that is not yet ready (unlinked, withdrawn, linked with setup required, or suspended/revoked before ready) | access/refresh pair whose server-side scope is `onboarding` | `GET /auth/onboarding`, link, complete setup, sign-out, `POST /auth/refresh` (scope preserved — Point 18B) | every tenant operational, Platform, Sync, notification, search and full-session auth endpoint → `403 onboarding_required` |
| **Full session** | verified + linked + setup complete (or `super_admin`, or a self-service Customer Demo session — Point 18B) | the existing access/refresh pair | the existing API | — |

Both token kinds live **only in platform secure storage**, like today's pair.
**Point 17C (supersedes 17B's "no secure storage" gap):** `flutter_secure_storage
^10.3.3` is a dependency (Android minSdk raised to 23 for its Keystore-backed
AES-GCM), reached only through `core/storage/secure_store.dart`
(`SecureStore` / `PlatformSecureStore`) and
`features/auth/data/secure_auth_state_store.dart` (`SecureAuthStateStore`,
`authStateStoreProvider`). It holds exactly two versioned, mutually exclusive
records: `mtm.auth.onboarding.v1` (either the verification challenge, or the
restricted-session token plus a **display-only** cached snapshot) and
`mtm.auth.full_session.v1` (the opaque full-session token). A malformed or
unknown-version record is deleted and treated as signed out, never repaired.
Nothing else from this journey — password, OTP, Team Code, Google ID token,
reset/MFA secret — is ever written to either store, and `LocalStore`/
`SharedPreferences` never hold any auth credential. A real process kill and
relaunch therefore resumes: a pending verification is re-validated against the
server; a restricted session is re-read online (offline, the cached snapshot
routes read-only and `stale`); a full session is restored through
`AuthRepository.currentUser()`; a revoked/expired token closes the journey and
never falls back to a local or developer identity (`onboarding_process_
restore_test.dart`, `secure_auth_state_store_test.dart`).
The backend never issues a full session to a `pending_setup` account (the
classifier still routes such an envelope to `/account-setup` defensively).
`GET /auth/me` with an onboarding token answers `403 onboarding_required`;
`GET /auth/onboarding` with a full token answers `409 setup_already_completed`.

#### Endpoints (all `Idempotency-Key` on mutations; all `RFC 3339` UTC)

| Method | Path | Auth | Request | Success |
| --- | --- | --- | --- | --- |
| `signUpWithPassword` | `POST /api/v1/auth/sign-up` | public | `{email, password}` | `202` challenge |
| `signInWithPassword` | `POST /api/v1/auth/sign-in` (existing path) | public | `{email, password}` | outcome |
| `signInWithGoogle` | `POST /api/v1/auth/google` | public | `{idToken}` | outcome |
| `verifyEmail` | `POST /api/v1/auth/verification/verify` | public + challenge | `{challengeId, code}` | outcome |
| `resendVerification` | `POST /api/v1/auth/verification/resend` | public + challenge | `{challengeId}` | challenge |
| `restore`/`refresh` | `GET /api/v1/auth/onboarding` | onboarding bearer | — | snapshot |
| `linkTeam` | `POST /api/v1/auth/onboarding/link` | onboarding bearer | `{teamCode}` (canonical) | snapshot |
| `completeSetup` | `POST /api/v1/auth/onboarding/complete` | onboarding bearer | `{displayName}` | outcome |
| `abandon` | `POST /api/v1/auth/sign-out` (existing) | onboarding bearer | — | `204`; revokes the onboarding token |

**Challenge** — `{challengeId, maskedEmail, codeLength?, expiresAt?,
resendAvailableAt?, attemptsRemaining?}`. `maskedEmail` is masked by the server.

**Outcome** — exactly one of:
`{"outcome":"ready","accessToken","refreshToken"}` (full session; the client
then reads `GET /auth/me` as today) ·
`{"outcome":"verification_required","challenge":{…}}` ·
`{"outcome":"onboarding","onboardingToken","onboardingRefreshToken","snapshot":{…}}`.

**Snapshot** — `{accountId, email, methods[], accountStatus, linkStatus,
setupStatus, tenant?{displayName, role, tenantStatus}, displayNameSuggestion?,
authorizationExpiresAt?}`. `tenant` is present **exactly** when
`linkStatus = linked`. `role` is `main_admin | admin`, never `super_admin`.
Gating fields (`accountStatus`, `linkStatus`, `role`, `tenantStatus`,
`setupStatus`) follow the SessionAccess rule: absent → default, known → itself,
**unknown → the client fails closed** (`/session-unsupported`); a structural
contradiction (tenant without link, completed setup without link) is an invalid
payload (`/session-invalid`). Unknown `methods[]` values are metadata and
ignored. The snapshot never carries a tenant id, Team Code, count, Main Admin
identity, capability or operational record.

#### Email/password sign-up

1. Client trims/lowercases the address (the **same** normalization as the
   Platform's Main Admin address — the invitation match depends on it), checks
   shape and a courtesy password floor (**PROVISIONAL** 8), never trims the
   password. The backend re-normalizes authoritatively (no Gmail dot/plus
   folding unless it chooses to).
2. Backend answers `202` with a challenge **in every case**: new address → new
   account (unverified) + code mailed; address of a provisioned, unclaimed
   account → credential attached pending verification + code mailed; address of
   an unverified account → the unverified credential is **replaced** (it proved
   nothing) + code mailed; address of a verified account → a **decoy**
   challenge that can never verify, and the real owner receives a "someone tried
   to sign up with your address" email. Timing and throttling must not differ
   between these (**enumeration policy**).
3. `password_rejected` (optionally `fields.password` reasons) is the only
   sign-up refusal besides `validation` and `rate_limited`.
4. **No session is issued by sign-up.**

#### Email verification (machine B)

- Numeric code mailed to the address; `codeLength` **PROVISIONAL** (6).
  Expiry, attempt budget and resend cooldown are **PROVISIONAL — BACKEND
  DECISION REQUIRED** and reported through `expiresAt`, `attemptsRemaining`,
  `resendAvailableAt`; the client only displays them with its injected clock.
- Codes: `verification_code_invalid` (+`attemptsRemaining`),
  `verification_code_expired` (resend issues a new code on the same challenge),
  `verification_challenge_ended` (attempts exhausted, lifetime over, or unknown
  handle — start again), `verification_resend_throttled` (+`Retry-After`).
- Verifying the address anywhere ends every other open challenge for that
  account (another device then signs in and resumes at the next step).
- Changing the address during verification is **not** an in-place edit: the
  person abandons and signs up again; an invited address is fixed by its
  authorization. A verified-email change is future self-service.
- The challenge handle is the only thing kept between calls (secure storage),
  so a relaunch returns to the code screen without the network.
- **Email OTP is not MFA.** It proves ownership of an address once; MFA
  (existing `/auth/mfa/*`) is a second factor on a full session.

#### Google (machine A)

- Flutter obtains an ID token from the Google SDK and sends it once. **Point
  17C:** `google_sign_in ^7.2.0` through `GoogleSdkIdentityGateway`
  (`features/auth/data/google_identity_gateway.dart`): `initialize(serverClientId:)`
  then `authenticate()`, and only `authentication.idToken` is used. The token is
  never decoded, persisted or logged. SDK outcomes collapse to five client
  states — obtained, cancelled (silent), unavailable (missing/misconfigured
  provider, no picker UI, plugin missing), network, failed — and no provider
  code or message crosses the gateway. A failed `initialize` is not memoized
  (the next tap retries). A build without `MTM_GOOGLE_SERVER_CLIENT_ID` fails
  closed as *unavailable* before any SDK UI; see "Google external
  configuration" below. **The backend** verifies signature, issuer,
  audience and expiry and reads `email`/`email_verified`; Flutter reads no claim.
- **Native account chooser (entry pass, 2026-09-23) — no wire change.** On
  Android the gateway calls `signOut()` and then `authenticate()`, which issues
  a `GetSignInWithGoogleOption` credential request: the system "Sign in with
  Google" sheet, listing the device's own accounts, with no authorized-account
  filter and no auto-select. The `signOut()` clears **this app's** Google
  session only so a second tap can pick a different account; `disconnect()` is
  never called, no authorization grant is revoked, and a refused sign-out is
  swallowed rather than blocking sign-in. **The frontend no longer asks anyone
  to type a Google address** — there is no Google email field on `/login` or
  `/signup` in a release build. The backend sees exactly the same
  `POST /api/v1/auth/google` `{idToken}` either way; this is recorded so the
  backend does not build an email-entry path nobody calls.
- **Cancellation is not an authentication failure.** A dismissed sheet is
  silent: no request is sent, nothing is logged as a failed attempt, no
  rate-limit counter moves, and no error is shown. Only an *obtained* token
  ever reaches `/auth/google`, so the backend must not infer attempts from
  chooser activity — it cannot see it.
- **Unavailable is a distinct, non-secret state.** A missing/misconfigured
  `MTM_GOOGLE_SERVER_CLIENT_ID`, an unregistered package/SHA-1, a missing
  plugin or no picker UI all collapse to `OnboardingErrorKind.googleUnavailable`
  and one generic Arabic sentence ("Google sign-in is not available in this
  build"), never "try again" — trying again cannot work. No provider code,
  message, client id, token or fingerprint crosses the gateway or reaches a
  log, a screen or a crash report. The backend's own Google refusals
  (`google_assertion_rejected`, `unsupported_auth_method`) must hold the same
  line.
- **External OAuth configuration is deployment work, not backend code.** The
  console clients, fingerprints, consent screen and keystores below are *not*
  satisfied by implementing `/auth/google`; both are required before anyone can
  sign in with Google.
- `email_verified=true` → Leader verification is skipped; `false` → a challenge.
- Identity mapping is backend-owned: an account already holding the Google
  subject signs in; a **provisioned, unclaimed** account or an **unverified**
  password account for the same address is claimed by the verified Google
  identity (the unverified password is dropped); a **verified password
  account** for the same address is **never merged automatically** →
  `auth_method_link_required` (the person signs in with the password; linking
  Google from Security is future scope and requires recent authentication).
  Saying this specifically is safe: the requester has just proved ownership of
  the address. **PROVISIONAL:** whether the backend may auto-link on verified
  email after its own review.
- `google_assertion_rejected` for an unverifiable token; `unsupported_auth_method`
  if the backend has Google switched off.

#### Team Code link (machine C)

- The client sends the code once, in canonical `MTM-XXXX-XXXX` form
  (Arabic-Indic digits folded, prefix optional on input), and keeps it nowhere.
  A malformed code is refused locally (`team_code_malformed`) and spends no
  attempt. Format is public; it is not a security control.
- The backend resolves the code to a tenant and matches the **verified,
  normalized address** to an **authorization** in that tenant: the Point 14
  Main Admin seat designation (initial or replacement) or a Simple Admin
  invitation. **The Team Code alone never links and never grants a role.**
- Evaluation order and answers: throttled → `rate_limited`; account already
  linked → same tenant: idempotent success, other tenant:
  `account_already_linked` (the other tenant is never named, and the code is not
  evaluated); unknown code, retired/deleted tenant's code, disabled code **or**
  no authorization for this address → **one** `team_link_refused` (identical
  body and timing, so a guessed code is indistinguishable from a real code
  without an invitation); matched but expired authorization →
  `invitation_expired`; matched but tenant not `active` → `tenant_unavailable`.
  Only the invitee can ever receive the last two.
- Brute force: per-account and per-IP budgets with lockout (**PROVISIONAL**
  values), Security alert on sustained failure; never rely on code obscurity.
- A link reserves the authorization; it activates nothing. Before setup
  completes the backend may **withdraw** it (invitation cancelled, seat
  replaced — Point 14 immediate or cancelled replacement — or tenant deleted):
  the snapshot then reads `linkStatus: withdrawn`.
- **Team Code tenant-side read: unchanged — hidden.** Only the Super Admin
  sees it. **PROVISIONAL — PRODUCT/BACKEND DECISION REQUIRED:** whether the
  Main Admin seat holder may ever read it (never edit/rotate). Point 17A called
  that read necessary for self-service Simple Admin onboarding; the Point
  17B/17C invitation auto-link removed that need (a Simple Admin never types a
  Team Code — corrected in Point 18A), so no current flow requires it. The
  Main Admin receives it out of band from the Super Admin. The setup/invitation email must **not** contain the Team
  Code — the two-channel requirement is what makes a mis-addressed invitation
  harmless.
- **Point 17B ruling — a Simple Admin invitation never shows this screen.**
  A Simple Admin invitation already names both the tenant and the invited
  address, so **the backend links it the moment the address verifies** —
  no Team Code is ever exposed to that recipient. This refines Point 17A's
  "invitation + Team Code (option B)" note: Team Code stays the required,
  typed path for a Main Admin seat (initial or replacement), where the
  addressee otherwise has no way to name the tenant. `mock_onboarding_
  repository.dart`'s `_autoLinkInvitation` models the distinction: it links
  any unexpired, unwithdrawn, non-seat authorization for the verified email
  automatically, and leaves a seat authorization for the explicit `linkTeam`
  call. The backend's real trigger for the auto-link (verification event vs.
  a dedicated invitation-acceptance call) is otherwise unspecified here.
- **Point 17C — the auto-link runs on every authoritative read, and
  cancellation is final.** The backend resolves a valid (pending, unexpired,
  tenant `active`) Simple Admin invitation for the verified, normalized address
  on sign-in, verification, `GET /auth/onboarding` (restore/refresh) — not only
  at the moment of verification. An invitee who verified **before** the
  invitation existed, whose invitation was cancelled and reissued, or whose
  tenant was paused at verification time is therefore linked on the next read.
  `/link-team` offers that invitee a "check for my invitation" action (a plain
  `GET /auth/onboarding`), never a Team Code demand; "no invitation yet" is a
  neutral answer, not an error, and says nothing about whether any invitation
  exists for another address. A cancelled invitation never links; cancelling
  one that is linked but not yet set up turns the snapshot `withdrawn` and
  `complete` answers `setup_unavailable`.

#### Account setup and activation (machine D)

- Setup = confirm the display name (1–80, whitespace-collapsed, suggested from
  the authorization's name › Google profile name; not identity-critical, never
  authorization) and **accept the role** shown. No temporary password, no forced
  password change, no terms acceptance (Privacy/Terms deferred).
- On `complete` the backend atomically: re-checks the authorization, its
  expiry and the tenant (`active` only); for a Main Admin authorization runs the
  Point 14 transition — `pending_setup → active` for the initial seat, or the
  replacement transfer (designate becomes holder, former holder `revoked`, its
  sessions and refresh tokens ended, `main_admin_replaced` Audit with actor
  `system`); assigns the authorization's role and capability grant; marks the
  authorization consumed — for a Simple Admin invitation that **is** the
  management record's `pending → accepted` transition, in the same
  transaction (Point 18B); revokes the onboarding token; issues the full
  session (`outcome: ready`). Flutter never marks anything active.
- Refusals: `setup_unavailable` (not linked / authorization withdrawn or the
  seat transition refused), `invitation_expired`, `tenant_unavailable`,
  `account_unavailable` (suspended/revoked mid-journey), `validation`,
  `setup_already_completed` (this onboarding token was already exchanged —
  e.g. another device finished), `authentication_expired` (token gone).
- A replay of the same `Idempotency-Key` after success must return the same
  `ready` outcome even though the onboarding token was consumed by it.

#### Initial Main Admin and Simple Admin joining

- **Main Admin (Point 14):** the Super Admin registers the tenant and
  identifies the Main Admin address (seat `pending_setup`, account id assigned).
  The invitee receives a setup email (install, sign up or continue with Google
  using this address; get the Team Code from the platform contact), proves the
  address, links with the Team Code, completes setup → seat `active`.
- **Temporary passwords: not used.** The invitee sets their own password at
  sign-up (or uses Google). The older "forced password change on first sign-in"
  wording predates this and is superseded; no bootstrap secret exists anywhere.
- **Invitation tokens: not used by the recipient client.** An authorization is a backend
  record bound to (tenant, normalized address, role, grant, expiry). For a Main
  Admin seat, ownership of the address (OTP/Google) plus the Team Code is the
  proof; for a Simple Admin invitation, ownership of the invited address alone
  is (Point 17B/17C). No invite link or credential reaches the onboarding
  client. The issuer's management response
  has an opaque invitation record id only so it can display status or cancel.
- **Simple Admin:** invitation-bound, **no Team Code** (Point 17B ruling,
  17C closure — supersedes 17A's "invitation + Team Code (option B)"). An
  `admin.manage` holder inside the tenant creates the invitation with the
  initial grant; the invited address, once verified (password OTP or verified
  Google), is auto-linked and goes straight to `/account-setup`. An uninvited
  address holding a valid Team Code is still refused (`team_link_refused`). The
  issuer UI is `/more/simple-admins`; the recipient flow is built.
- **Super Admin** is provisioned platform-side, signs in, and receives a full
  session with `role: super_admin` — never an onboarding session, never a Team
  Code.
- **Customer Demo** starts self-service only from the Point 18B
  post-verification decision below — never directly from Login, from an admin
  credential or a developer persona, and never from a per-user Super Admin
  provisioning step. It receives a full isolated session with
  `role: customer_demo`, `saasTenantId: null`, no tenant grant and
  `demoMode: active|expired`. Sign-up never creates one; it never links a
  `SaasTenant`, sees a Team Code or reads/mutates production tenant data. See
  "Customer Demo — final policy (Point 18B)".

#### Post-verification decision — Team or Demo (Point 18B)

A **new, verified, unlinked** identity (`linkStatus: unlinked`, no valid
Simple Admin invitation for its address) sees one decision on `/link-team`
before any Team Code field:

- **الانضمام إلى فريق** — join an existing team with the Team Code it was
  given → the Team Code link above (`POST /auth/onboarding/link`).
- **تجربة ليدر** — explore Leader in an isolated, temporary demo workspace
  without joining a real team → `POST /auth/customer-demo/start`.

Rules the backend and client share:

- **Reached only after identity proof.** Email/password: sign-up → OTP →
  decision. Google: when the backend accepts the ID token with
  `email_verified=true` there is **no** Leader verification code — the `onboarding` outcome
  lands directly on the decision; only `email_verified=false` produces a
  challenge first.
- **An invitation outranks it.** Because a valid Simple Admin invitation
  auto-links on every authoritative read, such an invitee's snapshot is
  already `linked` and goes to `/account-setup`; it never sees the decision,
  a Team Code or a role/capability choice. "Check for my invitation" stays
  on the decision screen for an invitee who verified early.
- **A `withdrawn` account** already chose a team and opens on the Team Code
  form.
- **Choosing the demo links nothing.** The start call is sent **without** the
  onboarding bearer, so the backend cannot associate the demo with the
  account; after a successful start the client discards and signs out the
  restricted onboarding session (`POST /auth/sign-out`). No `SaasTenant`, Team
  Code, tenant membership, Simple Admin relationship or production capability
  is created or consumed; the verified account stays unlinked and returns to
  the same decision on its next sign-in. A refused or offline start leaves the
  onboarding session untouched.
- **Demo disabled** (`demo_unavailable`, or the global policy off): the demo
  option states that it is unavailable, in words, and cannot be started; the
  client never falls back into a tenant.
- No endpoint is added for the decision itself; it is client presentation of
  `linkStatus: unlinked`.

#### Tenant-side Simple Admin management

All calls require a full tenant session holding `admin.manage`. The server
derives `tenantId` from the bearer and always binds invitations to
`role: admin`; no request accepts tenant, role, password, activation state or
recipient-selected capabilities.

- `GET /api/v1/tenant/simple-admins` → `{ revision, accounts[], invitations[] }`.
  Accounts include opaque id, normalized email, display name, status,
  capability grant and revision. Invitations include opaque management id,
  normalized invited email, suggested name, status, selected grant,
  `createdAt`, nullable `expiresAt`.
- `POST /api/v1/tenant/simple-admin-invitations` with `Idempotency-Key` and
  `{ invitedEmail, suggestedName, capabilityKeys, expectedRevision }` → the
  pending invitation. Same key/body replays the same result; different body
  returns `idempotency_conflict`.
- `POST /api/v1/tenant/simple-admin-invitations/{id}/cancel` with
  `{ expectedRevision }` → cancelled status. Cancellation invalidates its
  Point 17 authorization but retains the management/audit record.
- `PATCH /api/v1/tenant/simple-admins/{id}/capabilities` with
  `{ capabilityKeys, expectedRevision }` → updated account.

Capability keys must already exist in the canonical catalogue, be assignable
by the actor, and be valid for enabled tenant modules/plan rules. The backend
rechecks all of this and never trusts the UI subset. Expected refusals:
`not_permitted`, `validation`, `admin_invitation_exists`, `not_found`,
`stale_admin_management`, `idempotency_conflict`, plus global transport/auth
codes. Invitation expiry duration and delivery remain backend policy.

**Invitation state machine (Point 18B — final).** The backend owns every
field of an invitation — `tenantId` (from the issuer's token), normalized
invited email, intended role (always `admin`), the selected capability grant,
lifecycle state, the management `revision`, `createdAt`/`expiresAt` and the
issue `Idempotency-Key` result. The recipient can choose none of them.

| From | Event | To |
| --- | --- | --- |
| — | issue (`admin.manage`, key) | `pending` |
| `pending` | invitee completes setup | `accepted` (consumed) |
| `pending` | issuer cancels | `cancelled` (final; withdrawn) |
| `pending` | `expiresAt` passes | `expired` |

`accepted`, `cancelled` and `expired` are terminal; only `pending` can be
consumed. **Consumption is atomic with setup** — one server transaction:
validate the pending invitation → verify it names the same canonical
identity (normalized verified address) → create/link the Simple Admin
relationship → apply the invitation's backend-held grant → mark the invitation
`accepted` → append the Audit event → issue the full session. After success
the invitation is never `pending` again. A replay of the same completion
(`Idempotency-Key`) returns the same `ready` outcome and **never** creates a
second admin relationship; a cancelled, expired or withdrawn invitation cannot
be consumed (`setup_unavailable` / `invitation_expired`). The Flutter mock
models exactly this (`SimpleAdminStore.acceptInvitation`, called inside
`MockOnboardingRepository.completeSetup`).

**Audit (tenant-scoped, backend-authored).** `admin_invitation_created`,
`admin_invitation_cancelled`, `admin_invitation_accepted` (actor `system`, in
the setup transaction) and `admin_capabilities_changed`; category
`admin_management`, targets `simple_admin_invitation` /
`simple_admin_account`, changes as typed fields (`invitation_status`,
`capability_grant` key lists, `login_identity` always redacted). They belong to
a tenant-scoped audit stream, not the Platform Audit Log; no Flutter read
surface exists for it yet.

#### Customer Demo — final policy (Point 18B)

Supersedes every earlier "created and ended only by a Super Admin" wording
(Points 4–6).

- **Self-service.** Anyone may start a demo from `/login` or from the
  post-verification decision — **only while the Platform has Customer Demo
  globally enabled.** No account, Team Code or per-user Super Admin step is
  involved.
- **Super Admin owns the global policy only:** enabled/disabled, the
  configured duration, and lifecycle/cleanup policy for demo workspaces. It
  does not create demo users one by one. The Platform screen **has shipped** at
  `/platform/operations/demo` («إدارة الحسابات التجريبية») and is the only
  Demo surface in the product; Main Admin and Simple Admin have none, and the
  backend enforces `super_admin` rather than trusting the client's role
  presentation.
- **Policy and session shapes** (`BACKEND-HANDOFF.md` §12):

  ```
  DemoPolicy  { enabled, defaultDurationMinutes, revision, updatedBy, updatedAt }
  DemoSession { demoSessionId, accountId, demoWorkspaceId,
                startedAt, expiresAt, status, policyRevision,
                displayName?, endedAt?, terminationReason? }
  ```

  `status` ∈ `active | expired | terminated`. **Default duration 24 hours,
  minimum 1 hour**, carried as integer minutes; the client sets no maximum and
  the backend rejects what it will not honour. `terminationReason` ∈
  `user_ended | super_admin_terminated | terminate_all` is metadata on
  `terminated`, **not a fourth status** — a user ending their own trial is
  `terminated` + `user_ended`.
- **Policy changes are not retroactive.** A duration change applies to sessions
  created after it; every existing session keeps the `expiresAt` it was stamped
  with and the `policyRevision` that authorized it. Disabling blocks new starts
  only and terminates nothing — mass eviction is the separate, explicitly
  chosen `terminate-all`.
- **Duplicate start resumes.** One running trial per identity: a start call
  from an account that already holds an active session returns *that* session,
  unchanged, and emits no second `customer_demo_session_started`. Resuming is
  checked before `enabled`, so it succeeds while the offer is off; an identity
  with no running trial is still refused `demo_unavailable`.
- **Cleanup is operational, never historical.** `POST
  /platform/demo/sessions/cleanup` drops closed *session rows* from the
  operator's list. Audit (`customer_demo_session_started` / `_terminated` /
  `_expired` / `customer_demo_policy_changed`) is immutable and retained under
  backend retention rules, which stay configurable and **TBD** rather than
  invented here.
- **Backend flow:** `POST /api/v1/auth/customer-demo/start` (public, no body,
  no bearer — never the onboarding token) → check the global enabled state →
  create an isolated, ephemeral demo workspace/session → apply the configured
  expiry → return the full-session credential pair (`{accessToken,
  refreshToken}`, as in the `ready` outcome); `GET /auth/me` then reads
  `role: customer_demo`, `saasTenantId: null`, `Capabilities.none`,
  `demoMode: active` (optionally `sessionExpiresAt`).
- **Never:** a `SaasTenant`, a Team Code, a tenant membership, a real
  production capability, or any read/write of operational tenant data. Tenant,
  lifecycle, subscription, feature and limit endpoints refuse demo sessions.
- **Expiry and termination** are backend-owned: `demoMode: expired` routes the
  client to `/demo-expired`; the workspace is then terminated per policy.
  The client invents no duration.
- **Server time is authoritative.** `expiresAt` is stamped once, by the
  backend, at creation. Once `serverNow >= expiresAt` the session is expired
  and demo-authorized requests are rejected **by server time**, whatever the
  device believes. The client's clock drives display only: an `expired`
  envelope is never talked back into `active` locally, and the client can only
  narrow an active demo to expired — so no local clock or state change can
  extend a trial. Leaving the demo discards the workspace; **the real verified,
  unlinked identity survives** and may afterwards enter a Team Code or start
  another demo while the policy allows it.
- **Refusals:** `demo_unavailable` when the policy is off (status is the
  backend's choice; the client shows its existing unavailable state and never
  falls back into a tenant); `rate_limited` (+`Retry-After`) for start abuse;
  `426` outranks both.
- **Events:** `demo_started` / `demo_expired` Overview activity (Point 5); and
  backend-authored Audit, which the client never writes —
  `customer_demo_policy_changed` (`platform_administrator`),
  `customer_demo_session_started` (`system`; not emitted on a resume),
  `customer_demo_session_terminated` (carrying `terminationReason`), and
  `customer_demo_session_expired` (`system` — time is not an actor). The client
  parses an unknown action as its typed `unknown` until the catalogue adds it.
  No token, credential, device fingerprint or workspace content is ever logged.

#### Returning users and startup

A returning finished account signs in straight to a full session — no OTP,
Team Code or setup. Any partial state resumes at its own step (see HANDOFF
"POINT 17A" §J for the full table and the classifier precedence).

#### Password reset (existing flow, Point 17 rules)

The existing `/auth/password-reset/request → verify → complete` flow is the
reset flow (screens `/forgot` → `/otp` → `/new-password`); no second family.
Point 17 adds: `request` answers identically for unknown addresses (decoy
`resetToken`). **PROVISIONAL:** a completed reset also marks the address
verified (the code proved ownership) and ends every session of the account; a
Google-only account receives a "you sign in with Google" email instead of a
code. The Platform never resets a password.
MFA recovery and lost-email recovery remain backend/product gaps; no bypass.

#### Idempotency and concurrency

`Idempotency-Key` on sign-up, Google, verify, resend, link and complete. Same
key + same body → the stored response; same key + different body →
`idempotency_conflict`. The client reuses a key only while retrying the same
inputs after a transport failure and single-flights each operation, so a
double tap or a network retry can never create a second account, challenge or
link. Races (verified/linked/finished elsewhere, suspension, tenant lifecycle,
Main Admin replacement) are answered by the authoritative snapshot, which the
client re-reads on `requiresRefresh` codes.

#### Error codes (feature-owned, `OnboardingProblemCode`)

`invalid_credentials`, `password_rejected`, `verification_code_invalid`,
`verification_code_expired`, `verification_challenge_ended`,
`verification_resend_throttled`, `google_assertion_rejected`,
`auth_method_link_required`, `unsupported_auth_method`, `team_code_malformed`,
`team_link_refused`, `invitation_expired`, `account_already_linked`,
`tenant_unavailable`, `setup_unavailable`, `setup_already_completed`,
`account_unavailable`, `onboarding_required`, `rate_limited`,
`idempotency_conflict`; plus the global `validation`, `authentication_expired`,
`network`, `server`. `429`s carry `Retry-After`. There is **no** "account
exists" code. The client maps codes to `OnboardingErrorKind` and never renders a
raw code or server message.

#### Account-enumeration policy

Unauthenticated probes learn nothing about whether an address exists or which
method it uses: sign-up always answers with a challenge; password sign-in
answers `invalid_credentials` for wrong password, unknown address and
Google-only account alike; reset request always succeeds. Specific answers are
given only after the requester has proved something: a correct password
(→ verification required), a verified Google identity
(→ `auth_method_link_required`), a verified address + matching Team Code
(→ `invitation_expired`, `tenant_unavailable`). Copy follows the same rule.

#### Privacy and Audit

Never logged, audited, cached, persisted outside secure storage or sent to
analytics/crash reports: passwords, OTP codes, Team Code values, reset tokens,
Google tokens, onboarding/refresh tokens, challenge handles, MFA secrets.
Payloads are minimal (the snapshot above). **Audit (backend-appended; Flutter
appends nothing):** `main_admin_setup_completed` (category
`account_management`, target `main_admin_account`, actor `system`, change
`account_status: pending_setup → active`) — **required (Point 18B)**; the
Flutter catalogue adds a typed label once the backend emits it (unknown
actions already parse as the typed `unknown`); `main_admin_replaced`
(existing) on designate completion. The Simple Admin events
(`admin_invitation_created` / `_cancelled` / `_accepted`,
`admin_capabilities_changed`) are tenant-scoped — see "Tenant-side Simple
Admin management" — not the Platform log. Registration, verification, login and
Team Code failures are security events (Point 10 alerts), not governance Audit.

#### Google external configuration (Point 17C — none committed, none fabricated)

The repository contains **no** Google client id, no `google-services.json`, no
iOS `GIDClientID`/URL scheme and no signing fingerprint. Every value below is
issued by the Leader Google Cloud project owner and supplied at build/console time:

1. **`MTM_GOOGLE_SERVER_CLIENT_ID`** — the OAuth 2.0 **Web application** client
   id of the Leader backend, passed as
   `--dart-define=MTM_GOOGLE_SERVER_CLIENT_ID=<id>.apps.googleusercontent.com`.
   It is the audience of the ID token; the backend must verify `aud` against the
   same value (plus signature, `iss`, `exp`, `email_verified`). Empty → the
   Google button reports "unavailable" and never opens the SDK.
2. **Android OAuth client** — an OAuth client of type **Android** in the same
   project for package `com.leader.teams` (`applicationId`/`namespace` in
   `android/app/build.gradle.kts`; was `com.mtm.mtm` before the Leader
   rebrand — a client registered for the old package does not cover it), with the **SHA-1** (and SHA-256 if
   requested) of every certificate that signs a distributed build: the debug
   keystore for development, the production upload key, and — if Google Play
   App Signing is used — the Play app-signing key. `google_sign_in` 7 uses
   Android Credential Manager; no `google-services.json` is required for
   sign-in alone.
3. **Release signing** — `build.gradle.kts` still signs `release` with the
   **debug** keys (Flutter template default). A production keystore and signing
   config are prerequisites for step 2's production fingerprint; until then a
   release APK can only work against a debug-SHA registration.
4. **OAuth consent screen** — app name, support email, authorized domains and
   the `openid email profile` scopes, published for the intended audience.
5. **iOS / web** — not configured and not a Point 17 target. iOS would need an
   iOS OAuth client, `GIDClientID` and the reversed-client-id URL scheme in
   `Info.plist`; web would need its own client id.

Development builds additionally keep the in-app chooser (`demoAccountsAllowed`
only) that drives the mock's `mock-google:<email>` convention; a release build
never contains that path.

### Detachment groups

The five calls behind `DetachmentGroupRepository`. Every one is scoped by the
caller's SaasTenant, which the server derives from the verified token — the
client never sends `tenantId` (see **Terminology**).

#### `DetachmentGroupRepository.list`

`GET /api/v1/detachment-groups?query={text}` — access bearer required

`query` is optional and matches the group name. Request: no body.

Response `200`: JSON array of `DetachmentGroup` objects, each carrying its
derived roll-ups.

#### `DetachmentGroupRepository.byId`

`GET /api/v1/detachment-groups/{groupId}` — access bearer required

Request: no body.

Response `200`: `DetachmentGroup` JSON. `404` → `not_found`.

#### `DetachmentGroupRepository.create`

`POST /api/v1/detachment-groups` — access bearer required, `detachment.create`

Request:

```json
{
  "name": "Group name",
  "notes": "Optional internal notes"
}
```

A name is the whole required form; `notes` is optional. Every other property on
`DetachmentGroup` is server-assigned (`id`, `createdAt`, `status`) or derived
(the three roll-ups, all `0` for a new and therefore empty group).

Response `201`: `DetachmentGroup` JSON. An empty name is `validation`; a name
already used by another group in the same SaasTenant is `conflict`.

#### `DetachmentGroupRepository.update`

`PUT /api/v1/detachment-groups/{groupId}` — access bearer required,
`detachment.edit`

Request: complete `DetachmentGroup` JSON. The body `id` must equal `{groupId}`.
The server ignores the three derived roll-ups on input and recomputes them.

Response `200`: updated `DetachmentGroup` JSON. Same two refusals as create —
`validation` for an empty name, `conflict` for a name held by another group.

#### `DetachmentGroupRepository.delete`

`DELETE /api/v1/detachment-groups/{groupId}` — access bearer required,
`detachment.archive`

Request: no body.

Response `204`: no body.

**Destructive and cascading.** Deleting a group deletes every detachment inside
it, because a detachment cannot exist unfiled — the client says so on the
confirmation and does not ask again at the repository. The client sends no
force flag; if the backend wants a two-step confirmation for a non-empty group
it must say so and this section will carry it.

### Detachments

#### `DetachmentRepository.list`

`GET /api/v1/detachments?detachmentGroupId={id}&filter={active|archived}&query={text}`
— access bearer required

All three query parameters are optional. `detachmentGroupId` narrows the list
to one group; omitting it lists every detachment the session may see, which is
what the unscoped list screen and the group roll-ups both want. Request: no
body.

Response `200`: JSON array of `Detachment` objects.

#### `DetachmentRepository.byId`

`GET /api/v1/detachments/{detachmentId}` — access bearer required

Request: no body.

Response `200`: `Detachment` JSON.

#### `DetachmentRepository.create`

`POST /api/v1/detachments` — access bearer required

Request:

```json
{
  "detachmentGroupId": "g_123",
  "name": "Detachment name",
  "region": "Region",
  "mainCenter": "Main center",
  "notes": "Optional internal notes"
}
```

`notes` is optional; `detachmentGroupId` is required — a detachment is always
created inside a group. Response `201`: `Detachment` JSON.

#### `DetachmentRepository.update`

`PUT /api/v1/detachments/{detachmentId}` — access bearer required

Request: complete `Detachment` JSON. The body `id` must equal
`{detachmentId}`.

Response `200`: updated `Detachment` JSON.

#### `DetachmentRepository.stats`

`GET /api/v1/detachments/{detachmentId}/stats` — access bearer required

Request: no body.

Response `200`: `DetachmentStats` JSON.

### Team members

#### `TeamRepository.listForDetachment`

`GET /api/v1/detachments/{detachmentId}/members` — access bearer required

Request: no body.

Response `200`: JSON array of `TeamMember` objects.

#### `TeamRepository.assignRole`

`PATCH /api/v1/members/{memberId}/role` — access bearer required

Request:

```json
{
  "role": "medic"
}
```

Response `200`: updated `TeamMember` JSON.

#### `TeamRepository.setAttendance`

`PATCH /api/v1/members/{memberId}/attendance` — access bearer required

Request:

```json
{
  "attendance": "present"
}
```

Response `200`: updated `TeamMember` JSON.

### Shifts

#### `ShiftRepository.listForDetachmentToday`

`GET /api/v1/detachments/{detachmentId}/shifts/today` — access bearer required

Request: no body.

Response `200`: JSON array of `Shift` objects.

#### `ShiftRepository.byId`

`GET /api/v1/shifts/{shiftId}` — access bearer required

Request: no body.

Response `200`: `Shift` JSON.

#### `ShiftRepository.assignVolunteer`

`POST /api/v1/shifts/{shiftId}/assignments` — access bearer required

Request:

```json
{
  "memberId": "m_123"
}
```

Response `200`: updated `Shift` JSON. A duplicate assignment returns
`conflict`; a member outside the shift detachment returns `validation`.

#### `ShiftRepository.markAttendance`

`PATCH /api/v1/shifts/{shiftId}/members/{memberId}/attendance` — access bearer
required

Request:

```json
{
  "attendance": "late"
}
```

Response `200`: updated `Shift` JSON.

**One-hour ordinary edit window.** This endpoint — and its check-in/check-out
equivalents — is only valid while the shift's real end time (see
`Shift.crossesMidnight` for how an overnight shift's end is computed) plus
one hour has not yet passed, evaluated against **server time**, not a client
timestamp. The frontend enforces the same window client-side
(`lib/features/shift/domain/attendance_policy.dart`, `AttendanceWindow`) —
this is a UX convenience only; the client check is not a security boundary
(`CAPABILITIES.md` §0) and the server must independently reject a late
attempt through this endpoint with `409 stale_write`-adjacent semantics —
concretely, a distinct wire code (the frontend mock uses
`attendance_window_expired`; the real wire code is a
`Backend contract decision required` — see §6 below). See
`FRONTEND-BACKEND-INTEGRATION.md` §6 for the full contract, including
`addAttendanceCorrection` below, which is the only endpoint that remains
valid after this window closes.

#### `ShiftRepository.addAttendanceCorrection`

`POST /api/v1/shifts/{shiftId}/members/{memberId}/attendance-corrections` —
access bearer required, and the bearer must hold
`shift.attendance.override` in the shift's detachment. Available
**indefinitely** — no time-window check applies to this endpoint.

Request:

```json
{
  "status": "checkedIn",
  "checkInAt": "2026-07-09T08:03:00.000",
  "checkOutAt": null,
  "reason": "نسي المشرف تسجيل الدخول وقت الشفت",
  "correctedAt": "2026-07-12T10:00:00.000"
}
```

`status` uses the same values as `TeamMember.attendance`
(`notCheckedIn`/`checkedIn`/`checkedOut`/`absent`). `reason` is required and
must be non-empty after the same normalization the frontend already applies
(trimmed, internal whitespace collapsed) — the server must reject a blank or
whitespace-only reason with `validation`, never accept it silently.
`correctedAt` is advisory (what the client's clock read); a real backend
should additionally stamp its own server-time value and treat that as
authoritative for the audit trail.

Response `200`: updated `Shift` JSON, with the new correction appended to a
`corrections` array (see `Shift` below) and the shift's live attendance
fields (`attendance`/`checkInAt`/`checkOutAt` on the affected member) updated
to the corrected values. **Append-only**: a correction is never returned by
any endpoint that edits or removes an earlier one — there is no
`PATCH`/`DELETE` on this resource, by design (`FRONTEND-BACKEND-INTEGRATION.md`
§6).

A checkout before its check-in returns `validation` with code
`checkout_before_checkin`, matching `markAttendance`'s own rule. A missing
shift or member returns `not_found`.

### Inventory

#### `InventoryRepository.listForDetachment`

`GET /api/v1/detachments/{detachmentId}/inventory-items` — access bearer
required

Request: no body.

Response `200`: JSON array of `InventoryItem` objects.

#### `InventoryRepository.byId`

`GET /api/v1/inventory-items/{itemId}` — access bearer required

Request: no body.

Response `200`: `InventoryItem` JSON.

#### `InventoryRepository.movementsForItem`

`GET /api/v1/inventory-items/{itemId}/movements` — access bearer required

Request: no body.

Response `200`: JSON array of `InventoryMovement` objects, newest first.

#### `InventoryRepository.addMovement`

`POST /api/v1/inventory-items/{itemId}/movements` — access bearer required

Request:

```json
{
  "itemId": "i_123",
  "direction": "outflow",
  "quantity": 2,
  "reason": "Shift issue"
}
```

The body `itemId` must equal `{itemId}`. Response `200`: the updated
`InventoryItem` JSON. Quantity must be greater than zero; an outflow cannot
exceed current stock. Rejected quantities return `validation`.

### Workshops

Workshop endpoints and capabilities are organization-level; no detachment id
is sent.

#### `WorkshopRepository.list`

`GET /api/v1/workshops` — access bearer required

Request: no body.

Response `200`: JSON array of `Workshop` objects sorted by `at` ascending.

#### `WorkshopRepository.byId`

`GET /api/v1/workshops/{workshopId}` — access bearer required

Request: no body.

Response `200`: `Workshop` JSON.

#### `WorkshopRepository.create`

`POST /api/v1/workshops` — access bearer required

Request:

```json
{
  "name": "Workshop name",
  "at": "2026-09-12T09:30:00Z",
  "location": "Training hall",
  "capacity": 20,
  "registrationFee": 25000
}
```

Response `201`: `Workshop` JSON. Capacity must be greater than zero;
`registrationFee` is optional, defaults to `0` (a free workshop) and may not
be negative.

#### `WorkshopRepository.update`

`PUT /api/v1/workshops/{workshopId}` — access bearer required

Request: complete `Workshop` JSON. The body `id` must equal `{workshopId}`.

**Editable fields only**: `name`, `at`, `location`, `capacity`, `status`,
`registrationFee`. The server owns `registered`, `guests`, `organizingTeam`
and `archived` and must ignore them on this request, so a stale form cannot
clobber a register or an organising team that changed meanwhile.

Response `200`: updated `Workshop` JSON.
Errors: `capacity_below_registered` when `capacity` is below the number of
people already registered; `archived` when the workshop is archived.

#### `WorkshopRepository.setArchived`

`PATCH /api/v1/workshops/{workshopId}/archive` — access bearer required,
`workshop.archive`

Request:

```json
{
  "archived": true
}
```

Response `200`: updated `Workshop` JSON.

#### `WorkshopRepository.participants`

`GET /api/v1/workshops/{workshopId}/participants` — access bearer required

Request: no body.

Response `200`: JSON array of `WorkshopParticipant` objects.

#### `WorkshopRepository.setParticipantAttendance`

`PATCH /api/v1/workshop-participants/{participantId}/attendance` — access
bearer required

Request:

```json
{
  "attendance": "present"
}
```

Response `200`: updated `WorkshopParticipant` JSON.
Errors: `archived`.

#### `WorkshopRepository.addMemberParticipants`

`POST /api/v1/workshops/{workshopId}/participants` — access bearer required,
`workshop.people.manage`

Request:

```json
{
  "memberIds": ["m_123", "m_456"]
}
```

Response `201`: JSON array of the created `WorkshopParticipant` objects.

**All or nothing.** The request is rejected whole, with nothing written, on:
`not_found` (a member id that is not on this tenant's roster),
`duplicate` (already on the register), `already_organizer` (on this
workshop's organising team), `workshop_full` (more people than free seats),
`archived`. Repeated ids in one request collapse to one registration.

#### `WorkshopRepository.addGuestParticipant`

`POST /api/v1/workshops/{workshopId}/guests` — access bearer required,
`workshop.people.manage`

Request:

```json
{
  "name": "Guest name"
}
```

Response `201`: `WorkshopParticipant` JSON with `kind: "guest"` and no
`memberId`. Errors: `validation` (empty name), `duplicate` (a guest of the
same normalized name is already registered), `workshop_full`, `archived`.

#### `WorkshopRepository.removeParticipant`

`DELETE /api/v1/workshop-participants/{participantId}` — access bearer
required, `workshop.people.manage`

Response `204`. **This removes one register line and nothing else** — the
`TeamMember` behind a member line must not be deactivated, deleted or
otherwise touched. Errors: `not_found`, `archived`.

#### `WorkshopRepository.setParticipantPayment`

`PATCH /api/v1/workshop-participants/{participantId}/payment` — access
bearer required, `workshop.payment.record`

Request:

```json
{
  "paymentStatus": "paid"
}
```

`paymentStatus` is `paid`, `unpaid`, or `null` to return the line to "not
recorded". Response `200`: updated `WorkshopParticipant` JSON.
Errors: `archived`.

#### `WorkshopRepository.addOrganizers`

`POST /api/v1/workshops/{workshopId}/organizers` — access bearer required,
`workshop.people.manage`

Request: `{"memberIds": ["m_123"]}`. Response `200`: updated `Workshop` JSON.

Same all-or-nothing rules as the register, with `already_participant` in
place of `already_organizer`, and **no seat limit** — organisers staff the
workshop, they do not occupy a seat at it. A newly added organiser's
`attendance` starts at `notCheckedIn` for this workshop.

#### `WorkshopRepository.removeOrganizer`

`DELETE /api/v1/workshops/{workshopId}/organizers/{memberId}` — access bearer
required, `workshop.people.manage`

Response `200`: updated `Workshop` JSON. The roster is untouched.
Errors: `not_found`, `archived`.

#### `WorkshopRepository.setOrganizerAttendance`

`PATCH /api/v1/workshops/{workshopId}/organizers/{memberId}/attendance` —
access bearer required, `workshop.attendance.record`

Request: `{"attendance": "present"}`. Response `200`: updated `Workshop`
JSON. Errors: `not_found`, `archived`.

### Home

#### `HomeRepository.summary`

`GET /api/v1/home/summary?detachmentId=<id>` — access bearer required

Request: no body. `detachmentId` is required — the Today dashboard renders one
detachment at a time (`DETACHMENT-SCOPING.md` §4), and the client picks which.

Response `200`: `HomeSummary` JSON — the day's operational snapshot for that
detachment, joined server-side so the dashboard costs one round trip rather
than three:

- `detachmentId`, `detachmentName`, `region`, `mainCenter`
- `shifts` — every shift dated yesterday, today, or tomorrow, each the same
  `Shift` shape the schedule endpoints return. Three days because "running
  now" and "next" are clock questions: a 20:00–02:00 shift dated yesterday is
  still running at 01:00, and after the last shift of today the next one is
  tomorrow's. The client resolves current/next from real timestamps.
- `rosterCount`
- `storageStatus` — one of `empty`, `healthy`, `expiring`, `low`, `depleted`
- `lowStockCount`, `expiringSoonCount`

Response `403` for a detachment the caller may not see, `404` for one that
does not exist — the client renders each as its own state rather than
silently swapping in another detachment.

The dashboard's remaining signals (queued writes, a failed sync run, a
conflict awaiting review) are **client-side** and are never expected on this
payload.

### Notifications

Not implemented by any backend yet. The client ships a repository seam and a
mock that **derives** this feed by joining the shift and inventory data it
already holds, so every row points at a record that really exists. These are
the shapes a real implementation is expected to serve.

#### `NotificationRepository.feed`

`GET /api/v1/notifications?detachmentId=<id>` — access bearer required

Request: no body. `detachmentId` is required, for the same reason
`home/summary` requires it: the centre renders one detachment at a time.

Response `200`: `{ "notifications": [ AppNotification, ... ] }` — every
condition the detachment's records currently raise, **already filtered to what
the caller may see**. The client filters again by capability as a UX gate, but
that is not the boundary: a notification the caller has no grant for must not
be in the payload at all.

Response `403` / `404` as for `home/summary`.

The client sorts and groups the rows itself, so no order is required.

#### Read state

`PUT /api/v1/notifications/read` — access bearer required

Request: `{ "ids": ["shiftUnderstaffed:sh_412", ...] }`. Idempotent: an id
already marked read is not an error.

Response `200`: `{ "readIds": [...] }` — the caller's complete read set, so
the client can reconcile rather than assume.

Read state is **per user**, and covers ids the server never issued: the
client's own `syncConflict` / `syncFailed` rows are stored in the same set.
An unrecognised id must therefore be stored, not rejected.

### Announcements

Not implemented by any backend yet, and no endpoint was invented in the client
to pretend otherwise. The app ships `AnnouncementRepository` and an in-memory
mock. These are the shapes a real implementation is expected to serve.

#### `AnnouncementRepository.list`

`GET /api/v1/announcements` — access bearer required

Request: no body. **No `detachmentId` parameter**, unlike `notifications`: an
announcement can address several detachments and the client renders it per
detachment from one list.

Response `200`: `{ "announcements": [ Announcement, ... ] }` — every
announcement the caller may see, **already narrowed server-side**. The client
narrows again by capability as a UX gate, but that is not the boundary.

#### `AnnouncementRepository.byId`

`GET /api/v1/announcements/{id}` — access bearer required

Response `200`: `Announcement` JSON. Response `404` when it no longer exists —
the client renders «لم يعد هذا العنصر متاحًا» and refreshes, rather than
dead-ending.

#### `AnnouncementRepository.publish`

`POST /api/v1/announcements` — access bearer required

Request: `text`, `detachmentIds`, `placements`, `publishedAt`, `expiresAt`.

Response `201`: the stored `Announcement`.

**The server must enforce, on this request:**

1. **Create authority per detachment.** The caller holds `announcement.publish`
   *in every detachment in `detachmentIds`*. A caller holding it in one and not
   another must be refused the whole request, not silently narrowed — the client
   revalidates its target list against the live grant immediately before
   sending, so a partial success would mean the author was told something
   untrue. `403` with `not_permitted`.
2. **A finite expiry.** `expiresAt` must be after `publishedAt`. There is no
   permanent announcement. `422` with `validation`.
3. **Text bounds.** Trimmed length 5–500. `422` with `validation`.
4. **At least one target.** `422` with `validation`.
5. **Idempotency.** The client's duplicate-submission guard is client-side and
   therefore not a guarantee; an `Idempotency-Key` on this request is the
   server's half of it.

#### `AnnouncementRepository.withdraw`

`POST /api/v1/announcements/{id}/withdraw` — access bearer required

Request: no body. Response `200`: the updated `Announcement` with
`status: "withdrawn"`.

**Withdraw, not delete.** Stopping an announcement must end its active
placements and leave the record — the Notifications Center entry is a record
that the notice was sent, and erasing it would rewrite what a detachment was
told. Idempotent: withdrawing an already-withdrawn announcement is `200`, not an
error.

#### Recipient targeting — owed to the backend

The client resolves **visibility**: an administrator sees an announcement when
their grants cover one of the detachments it addresses. It cannot resolve
**delivery**, because the app has no admin directory — there is no endpoint that
answers "which administrators have access to detachment X". Server-side fan-out
(and any future push) therefore has to be decided and enforced by the backend.
Until then the client makes no claim about who received a notice.

#### Announcement history in the Notifications Center

An announcement produces one `AppNotification` with `kind: "announcement"` and
`target: { "type": "announcement", "announcementId": "..." }`. The client
derives that row from the announcement itself, so a backend serving
`/api/v1/announcements` needs to do nothing extra on `/api/v1/notifications`.

Announcements carry **no read state** — no `isRead`, no receipts, no delivery
confirmation, and they are excluded from the unread badge. If read state for
announcements is ever wanted it is a new product decision, not a field to add
quietly.

Clearing announcement history is currently client-local (see
`notification_history_store.dart`). A backend that owns it would need a per-user
cleared set, in the same shape as `/api/v1/notifications/read`.

### Settings

#### `SettingsRepository.notificationPrefs`

`GET /api/v1/settings/notifications` — access bearer required

Request: no body.

Response `200`: `NotificationPrefs` JSON.

#### `SettingsRepository.updateNotificationPrefs`

`PUT /api/v1/settings/notifications` — access bearer required

Request and response `200`: complete `NotificationPrefs` JSON.

#### `SettingsRepository.orgInfo`

`GET /api/v1/settings/organization` — access bearer required

Request: no body.

Response `200`: `OrgInfo` JSON.

**No UI consumer since Point 15.** The pre-SaaS `/more/org` page that rendered
this (legal name, address, public email, detachment/member counts) was
replaced by the Point 15 Organization screen, which reads the canonical tenant
record below. `OrgInfo.name` disagreed with `SaasTenant.displayName`, and its
counts duplicated plan usage. The seam is kept; whether legal name, address
and public email become part of the tenant organisation read (and whether
`org.edit` ever edits them) is an open product/backend decision.

### Organization & Plan — Point 15 (tenant, read-only)

`OrganizationRepository.readCurrent()` → `OrganizationSnapshot`
(`features/organization/domain/`). One read serves both `/more/organization`
and `/more/plan`. It is the read-only tenant adapter Point 7 anticipated: a
projection of the canonical `SaasTenant` + `SaasSubscription`, **not** a second
record, and the seam has **no write**.

`GET /api/v1/tenant/organization` — access bearer required; `main_admin` or
`admin` only. **No tenant id in the request:** the backend derives the tenant
from the bearer, so a session can only ever read its own organisation.
`super_admin` and customer-demo sessions get
`403 tenant_context_unavailable` (the client also short-circuits both before
calling).

Response `200`:

```json
{
  "organization": {
    "tenantId": "saas_hilal",
    "displayName": "فرق الهلال الطبية",
    "lifecycleStatus": "active",
    "createdAt": "2025-01-08T09:00:00Z"
  },
  "mainAdmin": { "displayName": "سلمى الحارثي" },
  "subscription": {
    "status": "active",
    "planId": "mtm_advanced",
    "renewsAt": "2027-01-08T09:00:00Z"
  },
  "limits": {
    "usageIncluded": true,
    "items": [
      { "key": "detachments", "planDefault": 40, "effective": 40,
        "overridden": false, "usage": 23 }
    ]
  },
  "readAt": "2026-09-12T09:00:00Z"
}
```

- `lifecycleStatus` is `SaasTenantStatus`; `status` is `SubscriptionStatus`;
  `planId` is `null` for an explicit no-plan, otherwise one of `mtm_core` /
  `mtm_standard` / `mtm_advanced` (Basic / Standard / Advanced). `trialEndsAt`,
  `renewsAt`, `graceEndsAt` follow Point 7's `relevantDate` rule.
- `limits.items[].effective` is **computed by the backend** as
  `override ?? planDefault` — the Point 7 rule; the client never recomputes it.
  There is **no unlimited sentinel**. With no plan, `effective` is absent.
- `usage` is included only when the session holds `org.edit` (the key that
  already gates organisation-wide figures); otherwise `usageIncluded: false`
  and every `usage` is omitted. **The server enforces this**, not the client.
- `mainAdmin` carries the **display name only**. Never the login email,
  account state, setup/replacement detail, or suspension reason (Point 14
  keeps those Platform-only).
- **Never in this payload:** Team Code, version tokens, lifecycle reasons or
  deletion schedule, history, audit, break-glass, price, currency, billing.
- Feature availability is **not** duplicated here; the tenant reads it from
  the existing Point 8 entitlement (`TenantFeatureRepository` /
  `currentTenantFeatureAccessProvider`), the same answer navigation obeys.

Unknown values **fail safe** on the tenant side (unlike the Platform parsers,
which refuse): an unknown lifecycle, status or plan id renders as
"unknown/unsupported" — never active, never Basic; an unknown limit key is
counted and not rendered; a known key the server omits renders "unavailable",
never unlimited. `readAt` is required.

Offline/cache: read on open, on pull-to-refresh and on the explicit refresh of
a cached copy. No polling, no timers, no queue, no outbox. A cached copy is
shown with its `readAt` and a distinct offline vs. refresh-failed notice.
Errors: `tenant_context_unavailable`, otherwise the shared `ProblemCode`
pipeline (`server`, `not_found`, …).

#### `SettingsRepository.motionLevel` / `updateMotionLevel` — **DEVICE-LOCAL, no endpoint**

**Superseded (entry pass, 2026-09-23). Do not implement these two calls.**
Motion level is a per-device performance preference, not account state: it is
read and written through `SettingsRepository` against the durable `LocalStore`
key `mtm.settings.motion`, never over the wire. The historical contract below
is kept only so nobody re-derives it, and it is stale in two ways — the enum is
no longer two-valued, and the round trip never happens.

Current value set (`core/motion/motion_level.dart`):
`performance`, `low`, `balanced`, `high`, `maximum` — persisted by **name**,
never by index. `full` and `reduced` survive as source-compatibility aliases
for `high` and `performance` respectively; a stored `full`/`reduced` from an
older build still reads. Default is `balanced`, or `performance` when the OS
reports `MediaQuery.disableAnimations` and nothing is stored yet.

The same ruling covers appearance (`mtm.settings.theme` — palette, light/dark/
system, Eye Protection) and frame rate (`mtm.settings.frame_rate`). See
`FRONTEND-BACKEND-INTEGRATION.md` §8 for the full boundary and the reasoning.

<details><summary>Historical two-value contract — superseded, not to be built</summary>

`GET /api/v1/settings/motion-level`, `PUT /api/v1/settings/motion-level`,
access bearer required, body `{"motionLevel": "full" | "reduced" | null}`.

</details>