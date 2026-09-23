# Leader — Backend Handoff (Point 18 — final)

**Status:** **FINAL — Point 18 COMPLETE (18A consolidation + 18B
finalization), 2026-09-13.** Frontend Points 1–17 are complete and the
frontend/backend-handoff roadmap is closed. **No backend exists**; every
repository in `flutter_app` is a deterministic mock behind a seam. This file is
the backend developer's entry point. It **consolidates**. It does not
re-specify payloads: those stay in `API_CONTRACT.md`, which remains the wire
authority. Backend implementation is a separate, future project; nothing in
this package starts it.

## 0. How to use this file

| Document | Holds | Precedence |
| --- | --- | --- |
| **this file** | The consolidated model, rules, inventory, gaps and build order | Index and tie-breaker for *cross-cutting* rules (§3–§11) |
| `API_CONTRACT.md` | Every payload, endpoint, field and problem code | **Wire authority.** Where this file and it disagree on a field, it wins; report the disagreement |
| `FRONTEND-BACKEND-INTEGRATION.md` | Provisional seams: Forced Upgrade (§1), Problem Details (§2), local-first writes/idempotency (§3), conflicts (§4–§5, §7), attendance window (§6) | Authority for those seams until they graduate into `API_CONTRACT.md` |
| `CAPABILITIES.md` | The capability catalogue, presets, enforcement order | Authority for authorization semantics |
| `DATA-NEEDS.md` | What each screen reads, with no endpoints | Screen-side data requirements |
| `SCREEN-ROUTE-MATRIX.md` | Every route and the repository behind it | Route → seam mapping |
| `HANDOFF.md` | Why each decision was taken, per Point | Rationale and provenance only |

**Start at §19 — BACKEND IMPLEMENTATION READINESS.** It is the one-page index
of what is implementable now, what is waiting on external configuration, what
is an unresolved product or data decision, and what is frontend-only and must
never grow an endpoint. Everything else in this file is the detail behind it.

Conventions used below: **[AGREED]** = in `API_CONTRACT.md` as a settled `v1`
contract; **[FUTURE]** = fully specified future contract, no backend yet;
**[OPEN]** = the backend/product must decide (listed in §15.6);
**[CLAUDE-PROVISIONAL]** = decided by Claude under delegation, still subject to
Ahmed's confirmation.

### Stale contradictions corrected in Point 18A

Corrected at the source in the same change as this file:

1. `API_CONTRACT.md` listed **29** capability keys and omitted
   `announcement.publish`; the code and `CAPABILITIES.md` §10 have **30**.
   (Two present-tense "29" mentions in `CAPABILITIES.md` were fixed too.)
2. `API_CONTRACT.md` → SessionAccess named `POST /auth/login`; the endpoint is
   `POST /api/v1/auth/sign-in`.
3. `API_CONTRACT.md` → `AuthRepository.signIn` documented a pre-Point-17
   request/response (`emailOrUsername`, flat tokens + user) for the same path
   as the Point 17A outcome union. The 17A outcome shape is canonical; see §6.1.
4. `API_CONTRACT.md` → `POST /platform/tenants` errors said `fieldErrors`; the
   shared envelope key is `fields` (the client parses `fields`/`errors`, and
   would silently drop a wire `fieldErrors`).
5. `API_CONTRACT.md` → Team Code said a tenant-side read "is needed for
   self-service Simple Admin onboarding"; the 17B/17C invitation auto-link
   removed that need.
6. `DATA-NEEDS.md` §4 open item 3 (workshops org- vs detachment-level) was
   still open; `CAPABILITIES.md` §0 ruled it organisation-level.

Contradictions that were **policy**, not staleness, were left visible by 18A
and are resolved by 18B below.

### Point 18B — final decisions applied and contradictions removed

Owner-approved decisions (no longer open anywhere in this package):

1. **Customer Demo is self-service** from the verified-unlinked
   post-verification decision while the Platform has it globally enabled;
   Login has no direct Demo entry. Super Admin owns the
   global policy (enabled, duration, lifecycle), never per-user creation
   (§12). Corrected at source: the "Super-Admin-issued demo account" tier
   wording and "created and ended only by `super_admin`" in
   `API_CONTRACT.md`; the planned Platform demo row in `SCREEN-ROUTE-MATRIX.md`.
2. **Token refresh is mandatory:** `POST /api/v1/auth/refresh`, rotating,
   single-use, replay-detecting, online-only (§6.1, `API_CONTRACT.md` →
   "Token refresh — Point 18B").
3. **Login identity is email only.** The `/login` label now reads
   "البريد الإلكتروني" (code fixed); `DATA-NEEDS.md`'s "email or username"
   and the stale `SCREEN-ROUTE-MATRIX.md` Login row (`AuthRepository`,
   `POST /auth/login`) were corrected. Username login is future scope.
4. **A Simple Admin invitation is consumed atomically** by a successful setup
   (`pending → accepted`, never left pending, idempotent); the Flutter mock
   now models it (§13).
5. `main_admin_setup_completed` Audit is **required** (was provisional); the
   Simple Admin tenant-scoped audit events are named (§10).
6. `CAPABILITIES.md`'s historical "Total: 29 keys" is annotated with the later
   30th key.

---

## 1. Canonical backend domain model

Three boundaries, never conflated (`API_CONTRACT.md` → Terminology):

- **Control plane** — the Leader platform: subscribers, subscriptions, plans,
  features, lifecycle, Main Admin seats, audit, health, security, reports,
  break-glass. Actor: `super_admin`. Never queries tenant data through a tenant
  API.
- **Tenant plane** — one `SaasTenant`'s operational data. Actors: `main_admin`,
  `admin`. The tenant is **always derived from the verified token**, never sent.
- **Demo plane** — an isolated Customer Demo workspace. Actor: `customer_demo`.
  Not a tenant; never reads or writes tenant data.

| Entity | Plane | Owns / is | Key rules | Contract |
| --- | --- | --- | --- | --- |
| **Account** (`AuthUser` + `SessionAccess`) | identity | One administrator login. `id` is canonical and provider-independent; email is login identity, not the key | Role ↔ `saasTenantId` invariant; lifecycle `active/suspended/revoked/pending_setup`; login email immutable | Canonical payloads → AuthUser, SessionAccess |
| **Auth method** | identity | Password and/or Google subject on an account | Exactly two methods; never auto-merged | Sign-up and onboarding → Google |
| **Session** (full) | identity | Access + refresh token pair | Secure storage only; `sessionExpiresAt` optional | Authentication |
| **Onboarding session** (restricted) | identity | Scoped token for a verified-but-not-ready account | Only onboarding endpoints; everything else `onboarding_required` | Sign-up and onboarding → Three session tiers |
| **Verification challenge** | identity | Opaque `challengeId` for an email OTP | Enumeration-safe; server-masked email | Sign-up and onboarding → machine B |
| **SaasTenant** | control | The paying subscriber; billing, security, data-isolation boundary | Team Code unique + immutable; lifecycle version independent of subscription version | `SaasTenant` (Point 6) |
| **Tenant lifecycle** | control | `active/suspended/deletion_pending/deleted` | Sole legal transition table; deletion window from policy | Tenant operational lifecycle (Point 9) |
| **Tombstone** | control | Minimal record after final deletion | No Team Code, email, subscription, counts | Point 9 → Final destructive deletion |
| **Subscription / Plan / Limit override** | control | Commercial state `trial/active/grace/inactive`, plan, per-key overrides | `effective = override ?? plan default`; limits below usage allowed | Subscription, plans, usage and limits (Point 7) |
| **Tenant feature** | control | Per-tenant module flag, per-row version | Unknown/absent = disabled; disabling never deletes data | Tenant product features (Point 8) |
| **Main Admin seat** | control ↔ identity | Exactly one current Main Admin per non-deleted tenant; ≤ 1 pending replacement | No stand-alone revoke; atomic transfer on designate setup | Main Admin account management (Point 14A) |
| **Authorization** (seat designation / Simple Admin invitation) | identity ↔ tenant | Backend record binding (tenant, normalized address, role, grant, expiry) | Consumed on setup; withdrawn on cancel/replace/delete | Sign-up and onboarding → machine C/D |
| **Simple Admin account + invitation (management view)** | tenant | The issuer's view: accounts and invitations `pending/cancelled/accepted/expired` | Tenant + role derived server-side; grant from catalogue subset | Tenant-side Simple Admin management |
| **Capability grant** | tenant | `{global[], scoped{detachmentId: []}}` | 30 keys; unknown denied; arrives with the full session | Capabilities; `CAPABILITIES.md` |
| **Break-glass grant** | control | Session-bound, single-tenant, read-only, expiring | Never a role, a `Cap`, or a lifecycle bypass | Break-glass (Point 12) |
| **Platform Audit event** | control | Immutable actor-attributed evidence | Backend appends; sanitized before persistence | Platform Audit Log (Point 11) |
| **Security alert / Health signal** | control | Current awareness snapshots | Not audit; no raw telemetry | Point 10 |
| **Report projection** | control | Four closed, synchronous, read-only projections | Snapshot-bound cursors; no export | Platform Reports (Point 13) |
| **Organization snapshot** | tenant (read) | Tenant's own projection of `SaasTenant` + subscription | No Team Code; Main Admin display name only; usage behind `org.edit` | Organization & Plan (Point 15) |
| **DetachmentGroup → Detachment** | tenant | Operational grouping and field unit | `detachmentGroupId` is an ordinary field | Detachment groups; Detachments |
| **TeamMember** | tenant | Volunteer record — **never a login account** | Phone arrives server-masked | TeamMember |
| **Shift** (+ assignments, attendance, corrections) | tenant | Scheduled duty | Attendance edit window server-enforced; corrections append-only | Shifts; integration §6 |
| **InventoryItem / InventoryMovement** | tenant | Stock and its ledger | Movements append-only, **never versioned** | Inventory |
| **Workshop / WorkshopParticipant** | tenant | Organisation-level training | `workshop.*` keys are global | Workshops |
| **Announcement** | tenant | Internal admin notice addressed to detachments | Recipient fan-out is backend-owned [OPEN] | Announcements |
| **AppNotification / NotificationPrefs** | tenant (per account) | Feed and preferences | Read state per user | Notifications; Settings |
| **HomeSummary** | tenant (derived) | Dashboard aggregate | Server-derived | Home |
| **Customer Demo workspace** | demo | Constrained sample workspace | `saasTenantId: null`, `Capabilities.none` | §12 below |
| **PendingOperation** | client only | Local outbox record; its UUIDv7 is the wire `Idempotency-Key` | Server never stores it; it stores the key's result | integration §3 |

---

## 2. Canonical identifiers

All ids are **opaque strings** chosen by the backend. Prefixes seen in fixtures
(`u_`, `saas_`, `d_`, `sh_`, `bg_`, `audit_`, `az_`, `admin_inv_`) are
illustrative only; the client never parses an id.

| Identifier | Scope | Rule |
| --- | --- | --- |
| `accountId` / `AuthUser.id` | global | Canonical, stable across auth-method changes; a claimed Platform-provisioned account keeps its id |
| `tenantId` | global | **Reserved for `SaasTenant`.** Never sent by tenant sessions; derived from the token. Only `/platform/tenants/{tenantId}/*` names it. Appears client-side read-only as `AuthUser.saasTenantId` |
| `detachmentGroupId`, `detachmentId`, `memberId`, `shiftId`, `itemId`, `workshopId`, `participantId`, announcement `id` | per tenant | Ordinary domain ids; the client sends and routes on them |
| Team Code | per tenant | `MTM-XXXX-XXXX`, alphabet `23456789ABCDEFGHJKMNPQRSTVWXYZ`; unique on canonical (punctuation-stripped, upper-cased) form under concurrency; immutable; not a credential; retired code never reused without policy |
| `challengeId` | per verification | Opaque handle; the only thing the device keeps between OTP calls |
| Authorization id (onboarding) vs invitation id (management) | per tenant | The recipient client **never** receives either; the issuer sees only the management id |
| Break-glass grant `id` + `revision` | per session | `revision` is the command concurrency token |
| Audit event `id` | platform | Total order: `occurredAt` desc, then `id` desc |
| Report `snapshotId` / cursors | per read | Opaque; invalid/expired cursor is a typed failure |
| Operation id = `Idempotency-Key` (tenant writes) | per logical write | **UUIDv7** (RFC 9562), minted once per logical write |
| Command attempt keys (control plane) | per attempt | Per-family formats, e.g. `break-glass:activate:<uuidv7>`, `main-admin:<action>:<uuidv7>` |
| Concurrency tokens | per resource | See §7 — never compared numerically by the client |

Closed wire vocabularies the client already parses (unknown values fail closed
as described per resource):

- **Roles:** `super_admin`, `main_admin`, `admin`, `customer_demo`.
- **Capability keys (30):** global — `detachment.create`, `workshop.create`,
  `workshop.edit`, `workshop.archive`, `workshop.people.manage`,
  `workshop.attendance.record`, `workshop.payment.record`,
  `workshop.section.manage`, `admin.manage`, `org.edit`; scoped per detachment —
  `detachment.view`, `detachment.edit`, `detachment.archive`, `member.view`,
  `member.contact.view`, `member.invite`, `member.edit`, `member.deactivate`,
  `member.role.assign`, `shift.manage`, `shift.delete`, `shift.assign`,
  `shift.publish`, `shift.attendance.record`, `shift.attendance.override`,
  `shift.occurrence.manage`, `inventory.adjust`, `inventory.item.manage`,
  `stats.view`, `announcement.publish`.
- **Feature keys:** `inventory`, `statistics_reports`, `workshops`,
  `announcements`.
- **Plan ids:** `mtm_core`, `mtm_standard`, `mtm_advanced` (Basic / Standard /
  Advanced).
- **Limit / usage keys:** `detachment_groups`, `detachments`, `admins`,
  `members`, `workshops`, `storage_bytes`.

Wire conventions (`API_CONTRACT.md` → JSON conventions): `camelCase`
properties; RFC 3339 instants with offset (normalize to UTC); durations in
whole seconds; list responses are arrays in `v1` (the control-plane lists that
page use cursors, per resource); `204` for void; problem codes in `snake_case`.
All paths are relative to base **`/api/v1`**; the Platform sections write them
without the prefix (`/platform/...` means `/api/v1/platform/...`).

---

## 3. Roles and capability model

Authority: `CAPABILITIES.md`; wire: `API_CONTRACT.md` → Capabilities, AuthUser.

- **Role selects the surface; capabilities authorize actions.** No endpoint may
  be authorized by role alone. `super_admin` → Platform surface only;
  `main_admin`/`admin` → tenant surface; `customer_demo` → isolated `/demo`.
  The server enforces the surface boundary independently.
- **`role` ↔ `saasTenantId` invariant:** `super_admin` and `customer_demo`
  must be `null`; `main_admin` and `admin` must carry a real id. A violating
  payload is refused (never repaired) — do not emit one.
- **Capabilities:** 10 global + 20 detachment-scoped keys. `canIn` = global
  **or** in that detachment's set (union). Any scoped entry implies
  `detachment.view` for that detachment. Unknown keys are **denied**. Presets
  are grant-time conveniences, never the check.
- **Main Admin** holds the full catalogue by backend provisioning; the client
  writes no grant. **Simple Admin** receives the invitation's grant, which the
  issuer selects from an assignable subset (no authority/lifecycle/destructive
  keys, no keys for disabled modules) — the backend re-validates that subset.
- **`super_admin` holds no `Cap` key**, and `Cap.all` must never stand in for
  platform authority. Fine-grained platform permissions are **[OPEN]** (§15);
  until designed, the backend enforces an independently authorized platform
  session and action policy.
- **`customer_demo`** carries `Capabilities.none` and no tenant.
- **Break-glass** scope `tenant_operational_read` replaces the capability step
  for one actor and one tenant; it is not a `Cap` and never `Cap.all`.
- **Capability freshness:** the grant arrives with the session and is cached;
  revocation reaches the UI at the next session refresh. The server must
  enforce on every request, including replayed outbox writes (`DATA-NEEDS.md`
  §4 items 11–12).

## 4. Authorization order

**Tenant request** (`CAPABILITIES.md` §1; `API_CONTRACT.md` Point 9) — each
step is evaluated in order and none substitutes for another:

1. authentication / session validity (incl. `sessionExpiresAt`, revocation);
2. account lifecycle (`suspended`/`revoked`/`pending_setup` → refused);
3. `SaasTenant` lifecycle (`suspended`/`deletion_pending`/`deleted` → **FULL
   BLOCK**, no capability exception);
4. correct role / surface;
5. tenant Feature Flag → `feature_disabled`;
6. Capability (scoped to the target detachment where scoped) → `not_permitted`;
7. Plan Limit, only for operations that create/consume capacity →
   `plan_limit_reached`.

The three refusals of steps 5–7 are **distinct codes**; never answer a disabled
module or an exhausted limit with `not_permitted`, nor a missing capability
with either of them.

**Break-glass read** (Point 12): session → Super Admin account lifecycle →
`super_admin` surface → grant exists/bound/active/unexpired → target match →
target lifecycle `active` (per request) → scope is a read in
`tenant_operational_read` → target Feature Flags → (Plan Limits never reached).

**Platform request:** session → account lifecycle → `super_admin` surface →
platform action policy [OPEN] → the resource's own state machine and
concurrency token. A tenant's lifecycle never blocks Super Admin platform
access.

**Onboarding (restricted) session:** only `GET /auth/onboarding`, link,
complete setup, sign-out, and `POST /auth/refresh` with its own
onboarding-scope refresh token (which never yields a full session);
everything else answers `403 onboarding_required`.
`GET /auth/me` with an onboarding token → `onboarding_required`;
`GET /auth/onboarding` with a full token → `409 setup_already_completed`.

**MFA:** `SessionAccess.mfaRequired` outranks both product surfaces.
`426 upgrade_required` outranks everything.

---

## 5. State machines

### 5.1 Account (`SessionAccess.accountStatus`)

`pending_setup → active` (onboarding completion, backend-only) ·
`active ⇄ suspended` (Platform, for a Main Admin seat) · `→ revoked`
(terminal; e.g. replaced Main Admin). Suspend/replace/cancel **end every
session and refresh token immediately**; reactivate restores no session. The
backend never issues a full session to a `pending_setup` account.

### 5.2 Tenant lifecycle (Point 9 — the sole legal table)

`active →suspend→ suspended →reactivate→ active` ·
`active|suspended →begin deletion→ deletion_pending` (remembers previous) ·
`deletion_pending →cancel→ previous` (only while `now < scheduledFor`) ·
`deletion_pending →finalize→ deleted` (only when `now ≥ scheduledFor`) ·
`deleted` terminal. Anything else → `invalid_tenant_transition`. Deletion
window from policy (mock 30 days, **provisional**).

### 5.3 Subscription (Point 7)

`activate`: `trial|grace|inactive → active` · `trial/extend`: `trial → trial`
(later end) · `trial/end`: `trial → grace` (mock 14-day grace is
**provisional**, BACKEND-CRITICAL) · `grace`: `active → grace` · `plan`: any
state. **[OPEN]** how `grace` ends (to `inactive` or otherwise) is not
specified. Subscription state never changes lifecycle, and vice versa.

### 5.4 Onboarding (Point 17)

- **Machine A — entry:** sign-up (always a challenge), password sign-in,
  Google → one of `ready` / `verification_required` / `onboarding`.
- **Machine B — verification:** challenge → verified (ends every other open
  challenge of the account) | invalid (attempts) | expired (resend) | ended.
- **Machine C — link:** `unlinked → linked` (Team Code for a Main Admin seat;
  **automatic for a Simple Admin invitation**) · `linked → withdrawn`
  (cancel / replace / tenant deleted before setup) · `withdrawn → linked`
  (a new valid authorization).
- **Machine D — setup:** `required → completed` on `complete`: atomically
  re-checks authorization, expiry and tenant `active`; runs the Point 14 seat
  transition for a seat; assigns role + grant; consumes the authorization;
  revokes the onboarding token; issues the full session.
- Tiers: none (challenge only) → restricted onboarding session → full session.

### 5.5 Main Admin seat (Point 14)

Current account `pending_setup | active | suspended`, ≤ 1 pending replacement.
Replace is **immediate** when the current never activated, **pending**
otherwise (atomic transfer when the designate completes setup; former holder
`revoked`). Actions that open access need tenant `active`; reducing actions are
allowed on `active/suspended/deletion_pending`; `deleted` allows nothing.

### 5.6 Simple Admin invitation (final — Point 18B)

`pending → accepted` (invitee completes setup — **atomically consumed** in the
setup transaction; never left `pending`) · `pending → cancelled` (issuer;
final; withdraws any link) · `pending → expired` (time; duration is backend
policy, mock 7 days). `accepted`/`cancelled`/`expired` are terminal; only
`pending` can be consumed; an idempotent replay of the completion returns the
same success and never creates a second admin relationship.
Onboarding side (**Point 17C rule**): a `pending`, unexpired invitation whose
tenant is `active` auto-links the verified invited address **on every
authoritative read** (sign-in, verify, `GET /auth/onboarding`); cancellation
withdraws a not-yet-completed link and `complete` then answers
`setup_unavailable`.

### 5.7 Break-glass grant

`active → ended` (initiator / session ended / tenant unavailable / platform
revocation) · `active → expired` (server time). Terminal; renewal is a new
grant with a new reason.

### 5.8 Customer Demo (`SessionAccess.demoMode`)

`none | active | expired`. `expired` is blocking. Self-service start while
globally enabled; duration/availability/cleanup are Super-Admin-owned global
server policy (§12).

---

## 6. Endpoint / action inventory

Status: **A** = [AGREED] `v1`; **F** = [FUTURE] specified; **P** = provisional
seam in `FRONTEND-BACKEND-INTEGRATION.md`. "Key" = `Idempotency-Key` required.
"Token" = concurrency token. Flutter seam = the provider to override.

### 6.1 Identity, session, onboarding — `authRepositoryProvider`, `onboardingRepositoryProvider`

| Method + path | Purpose | Key | Status |
| --- | --- | --- | --- |
| `POST /auth/sign-in` | Password sign-in → **17A outcome union** (`{email, password}`) | — | F (supersedes the A shape; §0 item 3) |
| `POST /auth/sign-up` | Always `202` challenge; enumeration-safe | yes | F |
| `POST /auth/google` | `{idToken}` → outcome | yes | F |
| `POST /auth/verification/verify` · `/resend` | OTP | yes | F |
| `GET /auth/onboarding` | Restore/refresh snapshot; **re-resolves invitations** | — | F |
| `POST /auth/onboarding/link` | `{teamCode}` (seat path) | yes | F |
| `POST /auth/onboarding/complete` | `{displayName}` → `ready` | yes | F |
| `POST /auth/sign-out` | Ends full or onboarding session | — | A |
| `GET /auth/me` | `AuthUser` + `SessionAccess` | — | A (+ SessionAccess F) |
| `GET /auth/sessions` · `DELETE /auth/sessions/{id}` | Own sessions | — | A |
| `POST /auth/mfa/setup` · `/mfa/verify` · `/new-device/confirm` | MFA | — | A |
| `POST /auth/password-reset/request` · `/verify` · `/complete` | Reset (decoy for unknown address) | — | A |
| `POST /auth/customer-demo/start` | Self-service demo start (public, no bearer) → demo credential pair. **Resumes** the caller's active session instead of creating a second (§12.2) | — | F (final policy §12) |
| `GET /auth/customer-demo/session` | The **holder's own** demo session envelope — `expiresAt`, `status`, server `now`. What `DemoTrialBar` counts down and what retires the trial | — | F (§12.2) |
| `POST /auth/refresh` | `{refreshToken}` → rotated `{accessToken, refreshToken}`; single-use, replay revokes the family; failures one `401 authentication_expired` | — (token is the replay guard) | F (Point 18B) |

### 6.2 Control plane — `super_admin` only

| Method + path | Purpose | Key | Token | Status |
| --- | --- | --- | --- | --- |
| `GET /platform/overview` | Aggregate decision view | — | — | F |
| `GET /platform/health` · `/platform/security-alerts` | Snapshots | — | — | F |
| `GET /platform/audit` | Filtered, cursor-paged, read-only | — | — | F |
| `GET /platform/tenants` · `/{id}` · `/{id}/status-history` | Registry | — | — | F |
| `POST /platform/tenants` | Register (trial, `pending_setup` seat) | — | — | F |
| `POST /platform/tenants/{id}/lifecycle/suspend` · `reactivate` · `deletion/begin` · `deletion/cancel` · `deletion/finalize` | Lifecycle | yes | `expectedVersion` (lifecycle) | F |
| `GET /platform/tenants/{id}/subscription` · `/limits`; `GET /platform/plans` | Commercial reads | — | — | F |
| `POST …/subscription/activate` · `trial/extend` · `trial/end` · `grace` · `plan`; `PATCH …/limits/{limitKey}` | Commercial mutations | yes | `expectedVersion` (subscription) | F |
| `GET /platform/tenants/{id}/features`; `PATCH …/features/{featureKey}` | Entitlements | yes | per-row `expectedVersion` | F |
| `GET /platform/tenants/{id}/main-admin` | Seat | — | — | F |
| `POST …/main-admin/setup/resend` · `suspend` · `reactivate` · `replacements` · `replacements/{id}/cancel` | Seat commands | yes | `expectedRevision` | F |
| `GET /platform/break-glass/current`; `POST /platform/break-glass/grants` · `grants/{id}/end` | Emergency read access | yes | `expectedTenantVersion` / `expectedRevision` | F |
| `GET /platform/reports/subscriptions` · `usage-limits` · `feature-availability` · `platform-activity` | Closed report catalogue | — | snapshot cursor | F |
| `GET /platform/demo/policy`; `PATCH /platform/demo/policy` | Customer Demo global policy — enabled, default duration. No per-user demo creation | yes (change) | `revision` | F |
| `GET /platform/demo/sessions` | Demo session list for the operator | — | cursor | F |
| `POST /platform/demo/sessions/{id}/terminate`; `POST /platform/demo/sessions/terminate-all`; `POST /platform/demo/sessions/cleanup` | Terminate one, terminate every active, drop closed **operational** records — cleanup is never an Audit delete (§12.1) | yes | `revision` / — | F |

### 6.3 Tenant plane — tenant sessions only

| Family | Endpoints | Status |
| --- | --- | --- |
| Organization | `GET /tenant/organization` (Point 15; `super_admin`/demo → `403 tenant_context_unavailable`) | F |
| Simple Admin management | `GET /tenant/simple-admins`; `POST /tenant/simple-admin-invitations` (key); `POST …/{id}/cancel`; `PATCH /tenant/simple-admins/{id}/capabilities` — all `expectedRevision`, `admin.manage` | F |
| Detachment groups | `GET /detachment-groups[?query]`, `GET /{id}`, `POST`, `PUT /{id}`, `DELETE /{id}` | A |
| Detachments | `GET /detachments?detachmentGroupId&filter&query`, `GET /{id}`, `POST`, `PUT /{id}`, `GET /{id}/stats` | A |
| Members | `GET /detachments/{id}/members`, `PATCH /members/{id}/attendance`, `PATCH /members/{id}/role` | A |
| Shifts | `GET /detachments/{id}/shifts/today`, `GET /shifts/{id}`, `POST /shifts/{id}/assignments`, `PATCH /shifts/{id}/members/{memberId}/attendance`, `POST …/attendance-corrections` (append-only) | A (+ window/corrections P §6) |
| Inventory | `GET /detachments/{id}/inventory-items`, `GET /inventory-items/{id}`, `GET …/movements`, `POST …/movements` (append-only) | A |
| Workshops | `GET /workshops`, `GET /{id}`, `POST`, `PUT /{id}`, `GET /{id}/participants`, `PATCH /workshop-participants/{id}/attendance` | A |
| Home | `GET /home/summary?detachmentId` | A |
| Notifications | `GET /notifications?detachmentId`, `PUT /notifications/read` | A |
| Announcements | `GET /announcements`, `GET /{id}`, `POST`, `POST /{id}/withdraw` (`announcement.publish` per addressed detachment) | F |
| Settings | `GET/PUT /settings/notifications`, `GET/PUT /settings/motion-level`, `GET /settings/organization` (legacy `OrgInfo`, **no UI consumer**) | A |
| Sync | push (`Idempotency-Key` per operation) + pull (`GET /sync?cursor=…`) | P — §9 |
| Version gate | any request may answer `426 upgrade_required`; `X-Client-Version` header | P — integration §1 |

---

## 7. Idempotency and concurrency

**Idempotency** — universal rule wherever a key is required: same key + same
body → the original stored result, no new effect, no new Audit event; same key
+ different body → `idempotency_conflict`; retention window **[OPEN]**
(roadmap ~7 days). Keys are **per attempt** (never derived from resource state,
which would replay an old result).

| Family | Key required | Concurrency token → stale code |
| --- | --- | --- |
| Onboarding (sign-up, Google, verify, resend, link, complete) | yes | none; races answered by re-reading the snapshot |
| Tenant lifecycle | yes | `lifecycle.version` → `409 stale_tenant` |
| Subscription / limits | yes | `subscription.version` → `409 stale_subscription` |
| Tenant feature | yes (recommended by contract) | per-row `version` → `409 stale_feature_state` |
| Main Admin seat | yes | `revision` → `stale_main_admin` |
| Break-glass | yes | tenant lifecycle version → `stale_tenant`; grant `revision` → `stale_break_glass` |
| Simple Admin management | invite: yes | management `revision` → `stale_admin_management` |
| Tenant operational writes (via outbox) | yes — the operation's UUIDv7 | entity `version` (JSON integer, body field, starts at 1; client treats as opaque) → `409 stale_write` with `currentVersion` + `currentRecord` (same shape as the entity's `GET`) or reference-only fallback |
| Append-only writes (inventory movements, attendance corrections) | yes | **none** — structurally conflict-free |

Ordinary `v1` operational writes are **not** idempotent today; the outbox will
send the key once a real transport exists. **[OPEN]** for sync: the wire codes
for *same key still in progress* and *same key, different body*. Every other
family already uses `idempotency_conflict` for the latter; adopting it for sync
too is the consistent choice, but it must stay **distinct from `stale_write`**
(a protocol fault, not a version conflict) — backend to confirm.

---

## 8. RFC 9457 error taxonomy

Envelope today: `{ "error": { "code", "message", "fields"? } }`. Target: RFC
9457 `application/problem+json` with a `code` extension. The client already
parses `code` at the top level **or** `error.code`, and field errors from
`errors` **or** `fields` (`FRONTEND-BACKEND-INTEGRATION.md` §2).

**Rules:** the client branches on `code` only; `message`/`title`/`detail` are
diagnostics, never product copy and never a branch key; an unrecognized code
renders a generic localized fallback and is not assumed retryable; no
exception text, secret or stack trace in any body.

**Core (global) codes** — `ProblemCode` in `lib/core/problem/problem.dart`:
`not_found` 404 · `not_permitted` 403 · `conflict` 409 (business rule) ·
`authentication_expired` 401 · `feature_disabled` · `plan_limit_reached` ·
`upgrade_required` 426 · `stale_write` 409; plus the shared `validation` 422
(+`fields`) and `server` results. `network` and `offline` are client transport
outcomes, never sent. `rate_limited` 429 (+`Retry-After`) and
`idempotency_conflict` are used by several families but are feature-owned
today; promoting them to Core is the consistent choice once the backend
confirms them.

**Feature-owned codes** (full lists in each `API_CONTRACT.md` section):

| Family | Codes |
| --- | --- |
| Onboarding | `invalid_credentials`, `password_rejected`, `verification_code_invalid`, `verification_code_expired`, `verification_challenge_ended`, `verification_resend_throttled`, `google_assertion_rejected`, `auth_method_link_required`, `unsupported_auth_method`, `team_code_malformed`, `team_link_refused`, `invitation_expired`, `account_already_linked`, `tenant_unavailable`, `setup_unavailable`, `setup_already_completed`, `account_unavailable`, `onboarding_required`, `rate_limited`, `idempotency_conflict` |
| Tenant registry / lifecycle | `tenant_code_conflict`, `tenant_not_found`, `invalid_tenant_transition`, `invalid_lifecycle_reason`, `stale_tenant`, `deletion_window_expired`, `deletion_not_effective`, `tenant_already_deleted`, `idempotency_conflict` |
| Subscription / limits | `subscription_not_found`, `invalid_subscription_transition`, `invalid_trial_extension`, `plan_not_found`, `plan_unavailable`, `limit_invalid`, `stale_subscription` |
| Features | `feature_not_found`, `invalid_feature`, `stale_feature_state` |
| Main Admin seat | `tenant_not_eligible`, `invalid_main_admin_transition`, `invalid_main_admin_reason`, `invalid_main_admin_identity`, `main_admin_identity_unavailable`, `main_admin_replacement_already_pending`, `main_admin_setup_resend_throttled` (**provisional name**), `stale_main_admin`, `recent_authentication_required` |
| Break-glass | `tenant_not_eligible`, `invalid_break_glass_reason`, `invalid_break_glass_scope`, `break_glass_already_active`, `break_glass_not_found`, `break_glass_not_active`, `stale_break_glass`, `recent_authentication_required` |
| Reports | `report_cursor_expired` 409, `report_range_too_large` 422, `report_unavailable` |
| Tenant organization / Simple Admin | `tenant_context_unavailable` 403, `admin_invitation_exists`, `stale_admin_management` |
| Customer Demo | `demo_unavailable`, `rate_limited` |
| Token refresh | `authentication_expired` 401 for invalid/expired/revoked/replayed/account-blocked (one indistinguishable answer), `rate_limited` 429 |
| Attendance window | `attendance_window_expired` (**client constant; wire string [OPEN]**) |

**Enumeration policy** (onboarding): no code reveals whether an address exists
or which method it uses; one generic `team_link_refused` for every
unknown/unauthorized Team Code case. `recent_authentication_required` is
feature-owned today and may be promoted to Core if more privileged commands
adopt it. **[OPEN]** (integration §2): literal RFC 9457 members, field-error
key shape (flat vs nested), and a safe support reference id.

---

## 9. Sync / offline backend responsibilities

Client architecture (`FRONTEND-BACKEND-INTEGRATION.md` §3–§5, §7): one outbox
(`OutboxController`, `PendingOperation`, UUIDv7 identity), one engine
(`SyncCoordinator`) shared by Auto and Manual Sync, states
`pending/syncing/synced/failed/conflict`, a Needs Review inbox for conflicts.

The backend must:

1. enforce idempotency on `Idempotency-Key`; return success for a duplicate of
   a completed operation without re-applying it; distinguish *in progress*
   from failure;
2. answer version mismatches with `409 stale_write` + `currentVersion` +
   `currentRecord` (or reference-only fallback);
3. **re-authorize every replayed write** (lifecycle, feature, capability,
   limit) at replay time — a queued write carries no authority of its own;
4. specify which refusal codes are **terminal** for a queued operation (the
   client has no terminal "rejected" state yet — `DATA-NEEDS.md` §4 item 11);
5. provide the pull contract (`GET /sync?cursor=…`) and decide batch vs
   one-per-request push (integration §3 open item 5);
6. enforce the attendance edit window and stamp `correctedAt` with **server
   time**;
7. treat append-only resources as conflict-free (no `version`).

**Never in the outbox:** every control-plane command, every onboarding/auth
transition (including token refresh and Customer Demo start), break-glass,
Simple Admin management, report reads. They are online-only; offline returns
`offline` and nothing is queued.

**Notifications.** `GET /notifications?detachmentId` and `PUT
/notifications/read` (read state per account), `GET/PUT
/settings/notifications`; announcement delivery/fan-out and history ownership
are backend policy (§15.6); push is not designed (future scope).

**Offline truth:** an offline client may display cached data with its original
`generatedAt`/`readAt` and a stale label, but never manufactures authority
(e.g. a cached break-glass grant is unusable until re-read). On reconnect the
client revalidates the session (lifecycle, grant) before protected work; the
server rejects regardless.

---

## 10. Audit events

The backend alone appends; Flutter appends nothing and
`PlatformAuditRepository` is read-only. Server sanitizes before persistence;
changes are typed fields, never object snapshots; forbidden values become
`{"kind":"redacted"}`.

| Category | Actions (wire) | Target type |
| --- | --- | --- |
| `tenant_management` | `tenant_registered` | `tenant` |
| `subscription` | `subscription_activated`, `trial_extended`, `trial_ended`, `subscription_moved_to_grace`, `plan_changed` | `subscription`, `plan_assignment` |
| `entitlement` | `limit_override_changed`, `feature_flag_changed` | `tenant_limit`, `tenant_feature` |
| `lifecycle` | `tenant_suspended`, `tenant_reactivated`, `deletion_requested`, `deletion_cancelled`, `deletion_finalized` | `tenant_lifecycle` |
| `emergency_access` | `break_glass_activated`, `break_glass_ended`, `break_glass_expired` (system), `break_glass_revoked` | `break_glass_grant` |
| `account_management` | `main_admin_setup_resent`, `main_admin_suspended`, `main_admin_reactivated`, `main_admin_replacement_started`, `main_admin_replacement_cancelled`, `main_admin_replaced` (admin or `system`) | `main_admin_account` |

| `customer_demo` | `customer_demo_policy_changed`, `customer_demo_session_started`, `customer_demo_session_terminated` (all `platform_administrator`, except a session started by its own holder → `system`), `customer_demo_session_expired` (`system`) | `customer_demo_policy`, `customer_demo_session` |

Change fields: `lifecycle_status`, `subscription_status`, `plan_assignment`,
`feature_enabled`, `limit_override`, `account_status`, `login_identity`
(always redacted), `demo_availability` (boolean), `demo_default_duration`
(**integer minutes** — never a formatted duration, so two revisions can be
compared without parsing «يوم واحد» back into a number). Actor kinds
`platform_administrator | system`.

**Customer Demo Audit rules.** The events are backend-authored; the client
writes none. A demo event carries the `demoSessionId`, the `accountId`, the
policy `revision` and timestamps — **never** a session token, a credential, a
device identifier or anything from inside the demo workspace.
`customer_demo_session_expired` has a `system` actor because time ends a
trial and nobody does; it is still recorded, so "why did this user lose
access" stays answerable.

**Required, not yet a typed Flutter label (Point 18B):**
`main_admin_setup_completed` (`account_management`, target
`main_admin_account`, actor `system`, `account_status: pending_setup →
active`) parses today as the typed `unknown` action. Point 10 security actions
(alerts) are signals, not governance Audit.

**Tenant-scoped audit (Simple Admin, Point 18B):** `admin_invitation_created`,
`admin_invitation_cancelled`, `admin_invitation_accepted` (actor `system`,
inside the setup transaction), `admin_capabilities_changed`; category
`admin_management`; targets `simple_admin_invitation` /
`simple_admin_account`; typed changes `invitation_status`, `capability_grant`
(key lists), `login_identity` (always redacted). They live in a tenant-scoped
stream owned by the backend, **not** the Platform log; no Flutter read surface
exists (future scope). Registration, verification, login and Team Code failures are **security
events** (Point 10 alerts), not governance Audit. Tenant lifecycle
`status-history` is a separate compact chronology, not Audit. Every
grant-authorized read must be attributable to the grant id; per-read Audit
granularity is **[OPEN]**. Retention is backend policy **[OPEN]**; final tenant
deletion neither deletes minimized audit automatically nor authorizes
indefinite retention.

---

## 11. Privacy and redaction

**Never logged, audited, cached, persisted outside secure storage, or sent to
analytics/crash reports (Point 18B — final list):**

- passwords (the backend stores only a slow salted hash);
- email OTP / verification codes and reset OTPs;
- Team Code values in ordinary logs (only the Platform tenant record holds one);
- Google provider credentials — ID tokens and any provider token or client
  secret (the Web client **secret**, if one exists, is backend secret
  configuration, never in the app or a log);
- access, refresh and onboarding tokens, and the refresh-token family ids;
- MFA secrets / `otpauthUrl` / backup codes;
- password-reset tokens and secrets;
- challenge handles, authorization headers, cookies, session ids, request
  bodies.

Server-side obligations:

- **Masking at source:** member phones (`phoneMasked`) and session IPs arrive
  masked; contact detail is gated by `member.contact.view` — omit it
  server-side for a session without that key.
- **Minimal payloads:** onboarding snapshot carries no tenant id, Team Code,
  counts, Main Admin identity or capabilities; tenant organization read carries
  the Main Admin **display name only**, no Team Code/version/reason/history/
  billing, and `usage` only with `org.edit`; security alerts carry no raw
  telemetry; report rows follow each report's privacy class; break-glass grant
  carries no credential, contact or operational data.
- **Tombstones:** id, display-name snapshot, `deleted`, `deletedAt`, version,
  history reference — nothing else; restricted to the control plane.
- **Team Code:** hidden from every tenant session; never in an invitation/setup
  email (two-channel rule for the Main Admin seat).
- **Enumeration safety** for sign-up, sign-in and reset request (§8).
- **Client storage** (Point 17C): credentials only in platform secure storage
  (`flutter_secure_storage`), two versioned records; ordinary preferences hold
  non-sensitive settings only.
- **Platform Reports** expose aggregates and platform facts only — never a
  tenant's operational, member or medical data unless a future report is
  explicitly designed for it (none is).
- **Sensitive identifiers are minimized:** masked email in challenges, masked
  phones/IPs, no tenant id in onboarding snapshots, redacted `login_identity`
  in Audit, no email in Customer Demo payloads.
- **Legal:** Privacy Policy and Terms of Use are a pre-production
  product/legal requirement (§15.4). No compliance regime is claimed.

---

## 12. Customer Demo backend requirements

**Final policy (Point 18B; `API_CONTRACT.md` → "Customer Demo — final
policy").** Self-service, gated only by a Platform-wide switch. Super Admin
controls enabled/disabled, the configured duration and lifecycle/cleanup
policy — **not** per-user creation.

What the frontend ships: a post-verification "تجربة ليدر" option, gated by the
global `CustomerDemoPolicy` (`customerDemoPolicyProvider`), which is **derived
from `DemoPolicy`** and never authored separately; an isolated demo workspace
of **constant** sample data (2 detachments, 2 workshops); the in-app
`DemoTrialBar` and `/demo-expired`. Starting from the decision discards the
restricted onboarding session after the demo starts, so the demo never carries
the signup account.

**The default demo duration is 24 hours.** `DemoPolicy.defaultDemoDuration`
(`features/demo/domain/demo_policy.dart`) is the product constant; only a
Super Admin moves the policy away from it. The client never invents a window
for a session: it renders the `expiresAt` the control plane stamped.

**Super Admin management UI shipped** at `/platform/operations/demo`
(«إدارة الحسابات التجريبية»), inside the Operations area. It is the only Demo
policy surface in the product — no tenant-side control exists, and Main Admin
and Simple Admin have none. `features/demo/data/demo_control_plane.dart` is
the process-memory stand-in a production build replaces with the endpoints
below; `features/platform/data/platform_demo_providers.dart` holds the
authorization (a `DemoPolicyActor` exists only for a `super_admin` session,
and every mutation without one is refused `not_authorized`).

> ### ⚠ The shipped control plane is DEVELOPMENT / TEST ONLY
>
> `features/demo/data/demo_control_plane.dart` holds the policy and every
> session record **in process memory**. It is not persistence, and nothing in
> it may be read as a production guarantee:
>
> - a restart, a reinstall or a second device re-derives none of it, so an
>   operator's "terminate" that only happened there did not happen;
> - it is deliberately **not** written to `LocalStore` — persisting it would
>   let a reinstall undo a termination, and would put a list of other people's
>   sessions in one customer's device storage;
> - it authors **no Audit**, and can erase none.
>
> **The backend is the authority for every fact below.** The client's job is to
> render what the control plane returns and to fail closed when it cannot. The
> production adapter replaces `demoControlPlaneProvider`; the in-process
> implementation survives only as the deterministic fake the tests and the
> development build run against. The UI never changes: it already reads every
> answer as a `Result` and owns none of this state (`PlatformDemoActions` is
> the seam — no widget touches `DemoPolicy` directly).

**Server time is authoritative; the client clock is for display only.** The
window is stamped once by the backend at creation and the client never
recomputes it. Two invariants carry this, and both are covered by test:

- `sessionAccessProvider` may only **narrow** an active demo to expired. A
  `demoMode: expired` envelope from the backend is never talked back into
  `active` by any local state, and there is no path that widens the other way —
  so **no local clock or local state change can extend a trial**.
- `expiresAt` and `policyRevision` are stamped at creation and never rewritten
  client-side, so a later policy revision cannot move an expiry a user has
  already been shown.

A production build must therefore reject demo-authorized requests past
`expiresAt` **by server time**, regardless of what the device believes.

The backend must provide:

1. `POST /auth/customer-demo/start` — public, no body, **no bearer** →
   check the global enabled state → create an isolated ephemeral workspace and
   session → apply the configured expiry → return the credential pair; `GET
   /auth/me` reads `role: customer_demo`, `saasTenantId: null`,
   `Capabilities.none`, `demoMode: active`. Accepts no Team Code, tenant id,
   role or capability; creates no `SaasTenant`, Team Code, tenant membership,
   account link or production capability.
2. The global policy store and its Super Admin read/change actions, with Audit
   `customer_demo_policy_changed` (§6.2, §10). Shape:

   ```
   DemoPolicy  { enabled, defaultDurationMinutes, revision, updatedBy, updatedAt }
   DemoSession { demoSessionId, accountId, demoWorkspaceId,
                 startedAt, expiresAt, status, policyRevision,
                 displayName?, endedAt?, terminationReason? }
   ```

   `status` ∈ `active | expired | terminated` — three values, no more.
   **No token, credential, device identifier or workspace content may appear
   in a session record**; the operator's list shows a display identity and
   three timestamps.
2z. **`terminationReason` is metadata on `terminated`, not a fourth state.**
   ∈ `user_ended | super_admin_terminated | terminate_all`, and present only
   alongside `endedAt`. "The user ended it" and "an operator ended it" are the
   same fact about the session — it stopped before its window closed — and
   differ only in who asked; making that a status would force every reader that
   only cares whether the trial is over to handle one more case. **There is no
   `selfEnded` status**: a user pressing «إنهاء التجربة» produces
   `status: terminated` + `terminationReason: user_ended`. An expired session
   carries no reason at all — time is not an actor. A backend that cannot
   supply the field may omit it; an unreadable value is ignored rather than
   fatal, because the *status* is what authorizes anything.
2a. **Duration range.** The client imposes a **floor of one hour** and
   **no ceiling** — the stepper increases without bound. The backend must
   enforce a safe configured maximum and reject what it will not honour
   (`validation_failed` naming `defaultDurationMinutes`). Durations cross the
   wire as **integer minutes**, never a formatted string.
2b. **Changes are not retroactive.** A duration change applies to sessions
   created *after* it. Every existing session keeps the `expiresAt` it was
   stamped with, and records the `policyRevision` that authorized it — that
   field is what makes the non-retroactivity checkable. The client never
   recomputes an expiry from a later revision.
2c. **Disabling blocks creation only.** `enabled: false` must refuse new
   starts (`demo_unavailable`) and leave running sessions alone until their
   own `expiresAt`. Immediate eviction is a *separate*, explicitly chosen
   action (`terminate-all`), never a side effect of the switch.
3. Expiry through `demoMode: expired` (optionally `sessionExpiresAt`), then
   workspace termination per policy. Once `expiresAt` is reached the session
   is expired, subsequent demo-authorized requests are rejected, the client
   leaves the demo, and the workspace is discarded. **The real verified,
   unlinked identity is never deleted**: it may afterwards join with a Team
   Code or start another demo while the policy allows it.
3a. `GET /platform/demo/sessions` (Super Admin, cursor-paged, filterable by
   status) for the management list; `POST …/{id}/terminate` (one),
   `POST …/terminate-all` (every active session, answering how many),
   `POST …/cleanup` (see §12.1). A terminate on a session that is no longer
   active answers `demo_session_not_active`; an unknown id answers
   `demo_session_not_found`.
3b. **Start is atomic and resumes rather than duplicates.** See §12.2.
3c. **Ordering and identity in the operator's list.** Active sessions are
   returned **soonest `expiresAt` first** — the list is read to decide what to
   do about trials that are nearly over, so the most urgent row is first
   whatever order the records arrived in. The row is labelled by
   `displayName`, falling back to `accountId`; **`demoSessionId` is never the
   primary label** and is carried only for the terminate call and technical
   detail. `demoWorkspaceId` does not reach the screen at all.
4. A demo data source that is **not** a `SaasTenant`: tenant, lifecycle,
   subscription, feature and limit endpoints reject demo sessions; no writes to
   production data.
5. Enforcement that `demoMode ≠ none` ⇔ `role = customer_demo` (the client
   fails closed on mismatch).
6. `demo_started` / `demo_expired` Overview activity and the demo counts; with
   no demo kinds in the final policy, report every active demo as `simple`
   with `full: 0` until product defines kinds (**[CLAUDE-PROVISIONAL]**; the
   client requires `simple + full = active`).
7. `demo_unavailable` when switched off (the client shows its existing
   unavailable state and never falls back into a tenant); `rate_limited` for
   start abuse.

### 12.1 Cleanup is an operational action — it is **never** a history delete

Two different things are kept about a finished trial, and `POST
/platform/demo/sessions/cleanup` touches only the first:

| | What it is | What cleanup does |
| --- | --- | --- |
| **A. Operational record** | the `DemoSession` row an operator reads to decide what to do about running trials | **may be removed** once the trial has closed — it decides nothing, and a list that only grows stops being read |
| **B. Audit record** | `customer_demo_session_started` / `_terminated` / `_expired` / `customer_demo_policy_changed` (§6.2, §10), backend-authored and immutable | **must remain**, under the backend's retention rules. Cleanup has no reach into it. |

**A backend that implements cleanup as "erase all historical evidence" has
implemented a different operation than the one this button offers.** The worst
an over-eager cleanup may cost is an operator's convenience, never the
evidence that a trial existed. The client authors no Audit event and can erase
none.

Within the operational store the shipped behaviour is: **expired** rows are
dropped, **terminated** rows are retained — somebody decided those, and the
list is where that decision stays visible (with its `terminationReason`) until
retention removes it.

**Retention is deliberately undefined here.** How long a closed operational
record lives before the backend drops it on its own, and how long Audit is
held, are deployment and product/legal decisions this client cannot make.
Leave both **configurable and TBD**; do not adopt an invented retention period
on the strength of this document. (§15.4 — no compliance regime is claimed.)

### 12.2 Start atomicity, and duplicate Start Demo

**Atomic from the application's perspective.** `POST /auth/customer-demo/start`
either returns a usable demo envelope or changes nothing. In order:

1. verify the authenticated identity;
2. verify that identity is eligible for Customer Demo;
3. verify `DemoPolicy.enabled`;
4. resolve the authoritative duration from the policy in force **now**;
5. create the `DemoSession`;
6. stamp server-derived `startedAt` / `expiresAt` and the current
   `policyRevision`;
7. return the demo session envelope.

A partial start must leave **no** session record behind: a trial nobody was
ever in is not a trial that ended early, and must not appear on the operator's
list at all. The Flutter mock does exactly this —
`DemoControlPlane.discardFailedStart` removes the provisional record rather
than marking it `terminated`.

Never, on any step: a `SaasTenant`, a Team Code, a tenant membership, a
production capability grant, or any write to production data.

**Duplicate start → resume, one running trial per identity.** If the account
already holds a session that is active by **server** time, the start call
returns **that** session rather than creating a second one. A double tap, a
retry after a dropped response and a second device all converge on the same
`demoSessionId` and the same `expiresAt`. Duplicates would give one person two
windows to spend and would make the operator's list count people wrong, and no
product requirement asks for concurrent trials on one identity.

Two consequences the backend must match:

- **Resuming is not starting**, so it is checked *before* `enabled`, and
  succeeds while the offer is switched off. Disabling blocks new trials and
  leaves running ones alone (§12 item 2c); refusing to hand a running trial
  back to its own holder would be terminating it by another name. An identity
  with **no** running trial is still refused `demo_unavailable`.
- A resume is **not** a new `customer_demo_session_started` Audit event, and
  must not re-stamp `expiresAt`, `startedAt` or `policyRevision`.

Once the previous trial is over (expired or terminated), the same identity may
start a fresh one while the policy allows it — a new id, and a window stamped
from the policy in force then.

### 12.3 Audit events the backend must author

The client writes none of these; all are backend-authored (§10).

| Event | When | Actor |
| --- | --- | --- |
| `customer_demo_policy_changed` | `enabled` or `defaultDurationMinutes` changed | `platform_administrator` |
| `customer_demo_session_started` | a session is **created** (not on a resume) | `system` (the holder started it) |
| `customer_demo_session_terminated` | ended early, carrying `terminationReason` | `platform_administrator`, or `system` for `user_ended` |
| `customer_demo_session_expired` | `serverNow >= expiresAt` | `system` — time is not an actor |

**Terminate-all** follows the existing audit convention for bulk platform
operations: one operation event plus the affected per-session
`customer_demo_session_terminated` events (each `terminationReason:
terminate_all`). Pick whichever of those two shapes the deployed audit
conventions already use for bulk actions — do not invent a third.

**Never logged:** a token, a refresh token, a credential, a password, a device
fingerprint, or anything from inside the demo workspace. A demo event carries
the `demoSessionId`, the `accountId` and timestamps (§10).

### 12.4 Authorization — Super Admin only, enforced server-side

Platform Demo Management is `super_admin` only, and **the backend enforces
it**. The client's role presentation is a rendering decision and is never the
check: the page asks the control plane to act and is refused `not_authorized`
if the session cannot authorize it — the same shape a backend answers with,
and the same shape it would get if the route were reached another way.

- Main Admin and Simple Admin **cannot** read or change `DemoPolicy`. No
  tenant role may, by any path.
- A **Demo session's** authorization is never accepted as tenant
  authorization, and never as platform authorization. `demoMode ≠ none` ⇔
  `role = customer_demo` (item 5), and a demo session carries
  `saasTenantId: null` and `Capabilities.none`.
- Break-glass grants read-only *tenant* access and confers nothing here.

## 13. Simple Admin invitation / account backend requirements

1. **Issue** (`admin.manage`, tenant from token): `{invitedEmail,
   suggestedName, capabilityKeys, expectedRevision}` + `Idempotency-Key`;
   binds `role: admin`; validates keys against the catalogue, the actor's
   assignable subset, and enabled modules/plan; refuses a duplicate pending
   invitation or existing account (`admin_invitation_exists`). No password,
   role, tenant or activation input exists.
2. **Deliver** the invitation email (install / sign up / continue with Google
   using this address). **No Team Code** in it, and none is needed.
3. **Auto-link (Point 17B ruling, 17C closure):** on every authoritative read
   of a verified account — sign-in, verification, `GET /auth/onboarding` —
   link a `pending`, unexpired invitation for the normalized verified address
   whose tenant is `active`. The recipient goes straight to account setup; a
   valid invitation never produces a Team Code screen. An invitee who verified
   before the invitation existed links on the next read (the app's "check for
   my invitation" is exactly that read). "No invitation yet" must reveal
   nothing about other addresses.
4. **Complete setup — one atomic transaction (Point 18B, final):** validate the
   `pending` invitation → verify the same canonical identity (normalized
   verified address) → create/link the Simple Admin relationship → apply the
   invitation's backend-held grant (`role: admin`) → mark the invitation
   `accepted` → append `admin_invitation_accepted` → issue the full session.
   An idempotent replay returns the same success and never duplicates the
   relationship; a cancelled/expired/withdrawn invitation cannot be consumed.
   The Flutter mock now does exactly this (`SimpleAdminStore.acceptInvitation`
   inside `MockOnboardingRepository.completeSetup`), so the management list
   shows the new account and the invitation as `accepted`.
5. **Cancel** is final: withdraws a not-yet-completed link (`linkStatus:
   withdrawn`, `complete` → `setup_unavailable`); retains the management/audit
   record.
6. **Edit capabilities** of an existing Simple Admin (`expectedRevision`); the
   new grant takes effect on the account's next session read (§3 freshness).
7. **Who may do what:** a Main Admin, or any account holding `admin.manage`,
   may list Simple Admins, list pending invitations, create and cancel
   invitations and update an existing Simple Admin's allowed capabilities —
   from the assignable subset only (no `admin.manage`, `org.edit`, lifecycle,
   destructive or platform authority; no keys for disabled modules). No role
   escalation and no Main Admin seat transfer happen here. The recipient
   chooses nothing but a display name.
8. **Backend policy still to set while implementing:** invitation validity
   (mock 7 days), resend, whether tenant suspension/deletion invalidates
   pending invitations (§15.6).

## 14. Google and external configuration

Full list: `API_CONTRACT.md` → "Google external configuration (Point 17C)".
Summary — **nothing is committed and nothing may be fabricated**:

- `--dart-define=MTM_GOOGLE_SERVER_CLIENT_ID=<web client id>`; the backend
  verifies the ID token's signature, `iss`, `exp`, `email_verified` and `aud`
  against the same id. Missing → the Google button reports "unavailable".
- Android OAuth client for `com.leader.teams` (Leader rebrand; formerly
  `com.mtm.mtm`) with SHA-1/SHA-256 of every signing
  certificate (debug, production upload key, Play app-signing key if used).
- A production release keystore — `release` is still signed with the **debug**
  keys.
- Published OAuth consent screen. iOS/web not configured.
- **Backend Google verification/exchange:** verify the ID token's signature,
  `iss`, `aud` (= `MTM_GOOGLE_SERVER_CLIENT_ID`), `exp` and `email_verified`;
  map the subject per the identity rules; never log the token.
- **Secure storage / minSdk:** credentials live only in
  `flutter_secure_storage` (Android Keystore-backed), whose floor is API
  **23**. The app does not pin a value — `android/app/build.gradle.kts` uses
  `minSdk = flutter.minSdkVersion`, which on the toolchain in this repo
  resolves to **24**, comfortably above both that floor and the 23 that
  Credential Manager's Google ID flow needs. Nothing to change; read the
  effective number from the toolchain, not from this file. A record that
  cannot be read (for example after a device restore) is deleted and the
  device starts signed out — never repaired (the Point 17C corrupt-record
  rule).
- **Native chooser, cancellation, unavailability (entry pass, 2026-09-23).**
  Android uses the system Google account sheet (`signOut()` then
  `authenticate()`); the app never asks anyone to type a Google address, a
  dismissed sheet is silent and is **not** a failed authentication attempt,
  and every configuration fault collapses to one generic non-secret
  "unavailable" message. None of this changes the wire: `/auth/google` still
  receives `{idToken}` and still verifies it against the same Web client ID
  audience. Full statement in `API_CONTRACT.md` → "Google (machine A)".
- Other external dependencies the backend owns: transactional email (OTP,
  invitations, setup, "someone tried to sign up with your address"), minimum
  supported client version for the `426` gate, push (none designed).

---

## 15. Final gap classification (Point 18B)

Every remaining item is in exactly one class. Nothing decided in Point 18B is
left as "open".

### 15.1 NO LONGER OPEN — resolved in Point 18B

- Customer Demo provisioning → **self-service while globally enabled;** Super
  Admin owns the global policy only (§12).
- Token refresh → **`POST /api/v1/auth/refresh`**, rotating, single-use,
  replay-detecting, online-only (§6.1).
- Login identity → **email only;** username is future scope (`/login` label
  fixed).
- Simple Admin invitation consumption → **atomic `pending → accepted` in the
  setup transaction;** mock fixed (§5.6, §13).
- `main_admin_setup_completed` Audit → **required;** Simple Admin
  tenant-scoped audit events → **named** (§10).
- The post-verification Team/Demo decision → **built** (`/link-team`; no new
  endpoint).

### 15.2 REQUIRED BACKEND IMPLEMENTATION — mocked today, required before production

Everything in §6 marked F/P, and in particular:

1. Transport foundation: error envelope with `code`, `X-Client-Version` +
   `426`, `Idempotency-Key` storage, RFC 3339 UTC server time, the Audit
   append primitive and sanitizer.
2. Identity: accounts, sign-in outcome union, **refresh with rotation and
   family revocation**, `GET /auth/me` + `SessionAccess`, sign-out, sessions,
   MFA, enumeration-safe reset, transactional email (OTP, invitations, setup,
   "someone tried to sign up").
3. Onboarding: sign-up, verification challenge, Google ID-token verification
   and identity mapping, restricted session enforcement, Team Code link with
   one generic refusal and throttling, invitation auto-link on every read,
   atomic setup completion (seat transition / invitation consumption).
4. Control plane: tenant registry with concurrency-safe Team Code, lifecycle,
   subscriptions/plans/limits, features, Main Admin seat, Audit read, Overview,
   Health/Security, Reports, Break-glass (after its recent-auth mechanism and
   grant-scoped read surface are designed).
5. Tenant plane: the §4 enforcement chain as shared middleware; organization
   read; Simple Admin management with invitation lifecycle and tenant-scoped
   audit; operational resources with `version`/`stale_write`,
   `feature_disabled`, `plan_limit_reached`.
6. Sync: idempotent push, pull cursor, terminal refusal codes for queued
   writes.
7. Customer Demo: global policy store and change action, start endpoint,
   isolated ephemeral workspace, expiry/termination, Overview counts.
8. **Policy values the backend sets while implementing** (not frontend
   blockers; the client hard-codes none): see §15.6.

### 15.3 ENVIRONMENT / DEPLOYMENT CONFIGURATION

`MTM_GOOGLE_SERVER_CLIENT_ID` dart-define (legacy key name, kept); an Android
OAuth client for `com.leader.teams` (formerly `com.mtm.mtm`) with the SHA-1/SHA-256 of every signing certificate (debug,
upload, Play app-signing); a real release keystore (`release` still signs with
debug keys); a published OAuth consent screen; backend Google token
verification configured with the same client id; transactional email
provider; production HTTPS base URL; the minimum supported client version for
`426`; Android `minSdk 23` accepted as the device floor (§14). No value is in
the repository and none may be fabricated.

### 15.4 PRE-PRODUCTION PRODUCT / LEGAL REQUIREMENTS

Deliberately deferred until now and **not** invented here:

- **Terms of Service** — content and policy require a product/legal decision.
- **Privacy Policy** — content and policy require a product/legal decision,
  written against the real backend's data handling (what is collected,
  where, retention, processors, what deletion does — `DATA-NEEDS.md` §4
  item 10).
- **Consent and versioning** — if legally or product-required, acceptance
  (which version, when, by which account) must be captured and enforced
  **before public production onboarding** opens. No consent screen, field or
  endpoint exists today, and no text may be drafted by engineering alone.

### 15.5 FUTURE PRODUCT SCOPE — non-blocking, deliberately deferred

Username login; Apple/phone/magic-link/passkey sign-in; linking Google to an
existing password account from Security; verified-email change; multi-tenant
membership and tenant switching; push notifications; a Platform screen for the
Customer Demo policy and any demo kinds/tiers; a tenant-side audit viewer;
announcement read receipts; SQLCipher-backed outbox storage (after the sync
contract); a connectivity plugin for Auto Sync; step-up/recent-auth UI beyond
"sign in again"; the break-glass grant-scoped tenant-data viewer; report
export and historical snapshots; iOS/web Google configuration.

### 15.6 Still-open product/backend policy values (retained from 18A)

Genuinely undecided, none blocking the frontend; each is a value or rule the
backend/product sets during implementation.

#### Identity and onboarding (`HANDOFF.md` "POINT 17A" §Q)

OTP length/expiry/attempts; resend cooldown; password policy (client floor 8 is
a courtesy); lockout budgets; mandatory MFA for admins; lost-MFA / lost-email
recovery; Google auto-link on verified email; one account ↔ one tenant
forever; designating an unlinked existing account; reset completion marks
address verified and ends sessions; the exact auto-link trigger mechanics;
Team Code tenant-side read (now no flow needs it). **[CLAUDE-PROVISIONAL]:** no temporary password; restricted session
before readiness; no Google/password auto-merge; Simple Admin auto-link.

#### Control plane

Fine-grained platform permissions; recent-authentication mechanism and
freshness window (break-glass, Main Admin replace/reactivate, final deletion);
deletion window (mock 30 days); post-trial policy (mock 14-day grace) and how
`grace` ends; Main Admin invitation validity (mock 7 days), resend throttling,
revoke-vs-demote of a replaced holder, notification emails; break-glass
duration (mock 1 hour), write scopes, the grant-scoped read surface, Main Admin
notification, per-read audit granularity, who else may revoke; audit retention;
Team Code retired-code reuse; report projections' `admins` usage aggregate.
Point 12–15 rulings marked Claude-provisional in `HANDOFF.md` remain pending
Ahmed.

#### Tenant plane

Volunteer multi-detachment membership; detachment/workshop status value sets;
patient register scope; shift draft/published distinction; announcement
recipient fan-out, history ownership, read state; whether legal name/address/
public email join the organization read and whether `org.edit` edits them;
workshop statistics read key; attendance-window wire code; capability
freshness (grant revision/etag).

#### Transport

RFC 9457 literal members, field-error shape, support reference id; `426` body
(`minimumVersion`) and whether a dedicated version endpoint exists; what build
identity the server compares; `Idempotency-Key` as final header name and
retention; sync in-progress / invalid-reuse codes; sync batch vs single;
terminal refusal codes for queued writes.

---

## 16. Frontend mock-only pieces and genuine frontend gaps

**No HTTP layer exists in the app.** Each seam below is overridden by a real
implementation; the mock is then deleted or confined to tests.

| Seam (provider) | Mock today | Real implementation must |
| --- | --- | --- |
| `authRepositoryProvider` | `MockAuthRepository` (+ dev-only typed identities, `PersistentDemoSessionStore`; no Login picker) | call sign-in/me/sessions/MFA/reset; restore from `SecureAuthStateStore`'s full-session token; add **token refresh** |
| `onboardingRepositoryProvider` | `MockOnboardingRepository` over `MockOnboardingServer` (refused wholesale in release) | call §6.1; write challenge/restricted token via `authStateStoreProvider` |
| `googleIdentityGatewayProvider` | real `GoogleSdkIdentityGateway` (debug adds a mock chooser) | nothing — needs only §14 configuration |
| `simpleAdminRepositoryProvider` | `MockSimpleAdminRepository` over `SimpleAdminStore` | call §6.3 Simple Admin management |
| Platform repositories (tenants, subscription, features, lifecycle, main admin, audit, break-glass, reports, health/security, overview) | process-memory `PlatformTenantStore` and per-feature mocks | call §6.2 |
| Tenant operational repositories | in-memory mocks | call §6.3 with `version` tokens |
| `syncTransportProvider` / `outboxStoreProvider` | `OfflineSyncTransport` / `InMemoryOutboxStore` | real push/pull; SQLCipher-backed outbox |
| App version repository | `MockAppVersionRepository` (env-selected scenario) | send `X-Client-Version`; route `426` to `check()` |
| `customerDemoPolicyProvider` | `const CustomerDemoPolicy(available: true)` | read global policy |
| Notification/announcement history | client-local store | server-owned if product wants cross-device history |

**Frontend gaps found during consolidation** — status after Point 18B:

1. **Token refresh** — contract now specified (§6.1). Client wiring lands with
   the real HTTP `AuthRepository` (no HTTP layer exists to call it from).
2. ~~`/login` label "email or username"~~ — **fixed in 18B** ("البريد
   الإلكتروني").
3. ~~Mock never flips a Simple Admin invitation to `accepted`~~ — **fixed in
   18B** (`SimpleAdminStore.acceptInvitation` in the setup transaction).
4. No terminal "rejected" outbox state (§9 item 4).
5. No connectivity plugin; Auto Sync triggers on app start and resume only
   (`SyncScheduler.onAppStart`/`onAppResumed`), plus Manual Sync.
6. No step-up/recent-authentication UI beyond "sign in again".
7. No grant-scoped tenant-data viewer for break-glass.
8. Privacy Policy / Terms screens deliberately absent — a pre-production
   product/legal requirement (§15.4).
9. `SettingsRepository.orgInfo` (`GET /settings/organization`) has no UI
   consumer since Point 15; keep or retire with the backend.

---

## 17. Recommended backend implementation order

Each step unblocks the next; Audit append is built **with** each mutation, not
after.

1. **Transport foundation** — HTTPS, `/api/v1`, error envelope with `code`
   (RFC 9457-ready), `X-Client-Version` + `426`, `Idempotency-Key`
   middleware with stored results, server-time RFC 3339 UTC, the Audit append
   primitive and sanitizer.
2. **Identity and sessions** — accounts, `POST /auth/sign-in` (outcome
   shape), `POST /auth/refresh` (rotation + family revocation), `GET /auth/me`
   with `SessionAccess`,
   sign-out, sessions, MFA, enumeration-safe reset, transactional email.
3. **Control-plane core** — `SaasTenant` registry with concurrency-safe Team
   Code uniqueness; lifecycle state machine; **the §4 enforcement chain as
   shared middleware**, before any tenant data exists.
4. **Entitlements** — plans, subscription state machine, limit overrides,
   usage aggregates, tenant features.
5. **Main Admin seat + onboarding** — authorization records, sign-up,
   verification, Google verification, restricted session, Team Code link,
   atomic setup completion; resend/suspend/reactivate/replace.
   *Milestone: a registered tenant's Main Admin can sign in.*
6. **Tenant organization read and Simple Admin management** — with the
   auto-link-on-every-read rule, atomic invitation consumption and the
   tenant-scoped audit events.
7. **Tenant operational resources** — detachment groups, detachments,
   members, shifts (window + corrections), inventory (append-only), workshops,
   home, notifications, announcements, settings — each with `version` and
   `stale_write`, `feature_disabled`, `plan_limit_reached`.
8. **Sync** — idempotent push, pull cursor, terminal-refusal codes; then
   switch the client outbox to SQLCipher.
9. **Platform read side** — audit read, overview, health, security alerts,
   report projections.
10. **Break-glass** — after the recent-auth mechanism and the grant-scoped read
    surface are designed.
11. **Customer Demo** — global policy store, self-service start, isolated
    ephemeral workspace, expiry/termination (policy final, §12).
12. **Before release** — set the §15.6 policy values, complete §15.3
    configuration and release signing, and satisfy §15.4 (Terms, Privacy,
    consent/versioning) before public production onboarding.

---

## 18. Commerce — pricing, global offers, coupons (Point 19)

Added after the Point 18 package closed. The frontend architecture is
`PRICING-PROMOTIONS-ARCHITECTURE.md`; this section is only what the **backend**
owes it. The Flutter pricing and Platform management surfaces now exist against
an explicitly local, in-process **DEV / TEST ONLY** control plane. No backend
commercial authority, coupon redemption, payment gateway or production
subscription activation exists.

### 18.1 The product shape

One Leader product, one full-access plan, four billing durations. **All four
grant identical capabilities** — a duration buys time, never function. There is
no Basic/Pro/Premium split.

| Wire id | Months | Price | Minor units |
| --- | --- | --- | --- |
| `monthly` | 1 | $6 | `600` |
| `three_months` | 3 | $14 | `1400` |
| `six_months` | 6 | $24 | `2400` |
| `twelve_months` | 12 | $40 | `4000` |

Currency is `USD`, and the only currency.

### 18.2 Money on the wire

Integer **minor units** with an explicit currency, always:

```json
{ "amount": 600, "currency": "USD" }
```

Never a float, never a preformatted string, never a bare number whose unit must
be inferred. Percentage discounts round **half-up on the discount**, then
subtract: `discount = ((base * pct) + 50) / 100` (integer division). `1400` at
10% is `140` off, final `1260`. The client implements exactly this and the two
must agree to the cent.

### 18.3 Two distinct promotion mechanisms

- **Global offer** — Super Admin enables it; every eligible user sees it; no
  code is entered. At most **one live offer per billing option**.
- **Coupon** — code-based. Either public (anyone with the code) or **targeted to
  one account**. The durable targeting key is the **account id**; never an email
  and never a display name. An operator may *type* an email in the admin UI, but
  the **server** resolves it to an account id and stores the id.

Discounts are one of two kinds: a **percentage**, or a **fixed final price**
(«first month for $2» is a final price of `200`, never a subtraction).

**Current eligibility policy: `monthly` and `three_months` only.** `six_months`
and `twelve_months` take no discount. Model this as policy data, not as a
hard-coded branch.

### 18.4 No stacking — the authoritative rule

At most one promotion applies to an option. When a user has both a live global
offer and a valid coupon, apply **the one producing the lower final price**; on
an exact tie the global offer wins. Never compose the two. The response must say
**which** promotion was applied so the client can name it.

### 18.5 Validation is not redemption

`POST /pricing/coupons/validate` **must not consume, decrement, reserve or mark
anything**. It is a read. A user may validate the same coupon any number of
times.

Redemption happens **only** in `POST /billing/checkout`, **only after payment
succeeds**, in the same transaction that activates the subscription. A one-time
coupon burned by someone who never paid is the failure this rule prevents.

The client models **no usage counter at all** — `maxUses` / `usedCount` are
backend-owned and do not exist client-side, deliberately, so nothing can be
consumed by accident.

### 18.6 Validation rules the server owns

In this order: the code exists (after normalization) · enabled · not expired ·
assignment permits this account · the target duration is eligible · usage limits
not exhausted · the resulting price is **> 0 and < base**.

Code normalization is canonical and shared: trim, remove all internal
whitespace, uppercase, then require `^[A-Z0-9-]{3,24}$`. Store only the
normalized form, so lookup is equality. ASCII-only is deliberate — a coupon must
survive being read aloud and typed on an Arabic keyboard.

**Refusal codes** (`Problem.code`; the client branches on these, never on text):
`coupon_not_found`, `coupon_disabled`, `coupon_expired`, `coupon_not_assigned`,
`coupon_not_eligible`, `coupon_exhausted`, `coupon_invalid_price`.

The client collapses `not_found` / `not_assigned` / `disabled` / `expired` into
one user-facing message so the field cannot be used to enumerate valid codes;
the server should keep them distinct for audit.

### 18.7 Endpoints to reserve

```
GET    /pricing/catalog                 base prices; public to any session
GET    /pricing/offers/active           live global offers
POST   /pricing/coupons/validate        validate ONLY — MUST NOT consume

GET    /platform/commerce/offers        POST /platform/commerce/offers
PATCH  /platform/commerce/offers/{id}   DELETE /platform/commerce/offers/{id}
GET    /platform/commerce/coupons       POST /platform/commerce/coupons
PATCH  /platform/commerce/coupons/{id}  DELETE /platform/commerce/coupons/{id}

POST   /billing/checkout                the ONLY endpoint that redeems
```

`/platform/commerce/*` is **platform authority** (§3, §4), not a tenant
capability. Main Admin, Simple Admin and Demo sessions are refused.
`/pricing/*` reads need no capability — including from a Customer Demo session,
which may view pricing and validate coupons but must be refused every
commercial **write**.

### 18.8 Checkout, when payment exists

Client sends `{ billingOptionId, couponCode? }` and **nothing else**.

The server: loads the authoritative base price → resolves the live offer →
validates the coupon → applies the better of the two (§18.4) → computes the
final price → takes payment → **then** consumes the redemption and activates or
renews the subscription → **snapshots the price actually paid** on the
subscription record, so a later price or offer change never rewrites history.

**Never trust** the client's final price, savings, "coupon is valid" boolean,
eligibility view, or clock. Every figure the Flutter client renders is a preview
of the server's answer; if they disagree, the server is right.

### 18.9 Audit events to reserve

`commerce_offer_created` / `_updated` / `_enabled` / `_disabled` / `_removed`,
the `commerce_coupon_*` equivalents, and `commerce_coupon_redeemed` —
backend-authored, written at payment, **never** at validation.

Coupon codes are not secrets, but they are not logged casually either; an
internal coupon note is never returned to a non-platform caller.

### 18.10 Interim state

Until these endpoints exist, subscription is completed by **contacting Leader**
(Telegram, WhatsApp, email). The client says so plainly and offers no purchase
action. The client-side control plane is process memory, is never persisted, and
is not financial authority in any sense.

---

## 19. BACKEND IMPLEMENTATION READINESS

*Audited 2026-09-23, against the working tree at the entry-experience
checkpoint (Leader logo simplification, the new Login, EntryPulse, the
cold-launch intro, native Google sign-in). This section is the single index of
"can backend work start, and what is it still waiting on". It adds no new
contract; every row points at the section that owns the detail.*

**No backend stack is chosen here.** Language, framework, database, cache,
queue, cloud provider, hosting and CI remain undecided and are deliberately
not implied by anything in this package. The contract is expressed as HTTP
resources, state machines, error codes and invariants precisely so that
choice stays open.

### 19.1 Already contractually defined — implementable now

| Area | Owner section |
| --- | --- |
| Domain model, identifiers, tenancy boundary (`SaasTenant` → `DetachmentGroup` → `Detachment`) | §1, §2 |
| Roles (`super_admin`, `main_admin`, `admin`) and the capability model | §3, `CAPABILITIES.md` |
| Authorization order: session → account lifecycle → tenant lifecycle → role/surface → Feature Flag → Capability → Plan Limit | §4 |
| Sign-in outcomes, `GET /auth/me` / `SessionAccess`, sign-out, sessions, MFA, enumeration-safe reset | §6.1, `API_CONTRACT.md` |
| Rotating single-use refresh with family revocation — `POST /api/v1/auth/refresh` | §6.1, §15.1 |
| Google ID-token verification and backend-owned identity mapping | §14, `API_CONTRACT.md` → "Google (machine A)" |
| Sign-up / OTP challenge / restricted onboarding session / Team Code link / atomic setup completion | §5, §6.1 |
| Simple Admin invitation lifecycle — `pending` → `accepted` **atomically**, cancelled and expired can never be consumed, retry idempotent | §5, §13 |
| Customer Demo: isolated, **not** a `SaasTenant`, no Team Code, no production membership, no sync/outbox; `DemoPolicy` / `DemoSession`, enabled + default duration + revision, expiry and termination, server time authoritative, duplicate start resumes, cleanup preserves immutable audit | §12 |
| Optimistic concurrency (`version`, `stale_write`) and idempotency keys | §7, `FRONTEND-BACKEND-INTEGRATION.md` §5 |
| RFC 9457-ready error envelope; branch on `code`, never on text | §8 |
| Sync push/pull responsibilities | §9, `FRONTEND-BACKEND-INTEGRATION.md` §3 |
| Audit events and the redaction rules — admin/capability changes, Demo management, commerce later; **secrets and tokens never logged** | §10, §11, §18.9 |
| Platform report projections that structurally cannot expose tenant medical or operational data | §11, `mtm-platform-reports` scope |
| Workshops: nullable `memberId` participant identity, organisers outside participant capacity, organiser/participant exclusivity, duplicate and capacity rules, attendance, payment state, remove-participant ≠ delete `TeamMember`, archive/restore as lifecycle state, statistics | §6.3, `API_CONTRACT.md` → Workshops |
| Commerce shape: $6 / $14 / $24 / $40 (`600` / `1400` / `2400` / `4000` integer cents), all durations full access, `GlobalOffer` vs `Coupon`, percentage/fixed, uppercase normalization, **validation never redeems**, best final price wins, tie → Global Offer, Super Admin mutation authority, checkout the only redeeming endpoint | §18, `PRICING-PROMOTIONS-ARCHITECTURE.md` |

Build order: §17.

### 19.2 Requires external credentials or configuration — not code

Nothing in the repository can supply these, and none may be fabricated.

1. Google Cloud project with Google Identity / Credential Manager available.
2. **Android OAuth client for package `com.leader.teams`**, registered with the
   SHA-1 (and SHA-256 where asked) of **every** keystore that signs a build
   people sign in from — the debug keystore for development, the production
   upload key, and the Play App Signing key if used. A client registered for
   the old `com.mtm.mtm` package does not cover it.
3. **Web application OAuth client** in the same project. Its client ID is the
   app's `serverClientId` and the **audience** the backend verifies `aud`
   against. Supplied at build time as
   `--dart-define=MTM_GOOGLE_SERVER_CLIENT_ID=<web client id>` — **the env key
   keeps its historical `MTM_` name on purpose; it is a technical identifier,
   not branding, and renaming it breaks every existing build script.**
4. A production release keystore — `release` is still signed with debug keys.
5. Published OAuth consent screen. iOS and web are not configured and are not
   in scope.
6. Transactional email (OTP, invitations, setup, "someone tried to sign up
   with your address").
7. The minimum supported client version that drives the `426` gate.

Until 1–3 and 5 exist the Google button correctly reports *unavailable*; that
is configuration, not a defect, and not something `/auth/google` can fix.

### 19.3 Unresolved product decisions — backend must not invent an answer

1. Multi-detachment membership for one volunteer (`DATA-NEEDS.md` §4.1).
2. Detachment and workshop status value sets (§4.2).
3. Patient register in scope or not (§4.4).
4. Shift draft/published distinction and `shift.publish` (§4.5).
5. Announcement recipient fan-out and where announcement history lives
   (§4.7, §4.8); read state is deliberately absent (§4.9).
6. Whether workshop statistics need their own read capability (§4.14).
7. Terms of Use, Privacy Policy, consent and versioning — a pre-production
   product/legal requirement (§15.4); engineering drafts no legal text.
8. Break-glass grant-scoped tenant-data viewer, after the recent-auth
   mechanism is designed (§16.7, §17.10).
9. Whether `GET /settings/organization` is kept or retired (§16.9).
10. Whether workshop **payment** becomes an operational, money-moving feature.
    If it does, the backend owns the authoritative mutation — the frontend's
    current local payment display establishes no authority whatsoever.

### 19.4 Unresolved data requirements

The seven live frontend→backend data dependencies are enumerated once, in
`DATA-NEEDS.md` §16. They are **not** frontend defects and must not be closed
by making the UI claim data it does not have. Summary: cross-detachment Home
aggregation; explicit dates/ranges on `DetachmentStats` series; the unit and
meaning of historical stock series; the `attendanceSeries` product semantics;
historical roster-size trend; authoritative workshop payment mutation; real
`.xlsx` generation.

Also open: a terminal rejection state for replayed writes (§9 item 4,
`DATA-NEEDS.md` §4.11), plan-limit rejections on tenant creates (§4.13) and
capability freshness / grant revision (§4.12).

### 19.5 Explicitly frontend-only — no endpoint, no table, no contract

Do not add backend persistence for any of these unless the product changes.

- **Appearance**: palette (six), Light/Dark/System, **Eye Protection**. Device
  preference, durable local key `mtm.settings.theme`.
- **Performance / smoothness**: motion level (`mtm.settings.motion`) and frame
  rate (`mtm.settings.frame_rate`), plus reduced-motion behaviour derived from
  `MediaQuery.disableAnimations`. The historical
  `GET`/`PUT /settings/motion-level` contract is **superseded** — see
  `API_CONTRACT.md` and `FRONTEND-BACKEND-INTEGRATION.md` §8.
- **Brand and entry visuals**: the fixed Clean Layer launcher identity, the
  removed logo selector, the cold-launch intro and the EntryPulse ambience.
  These are rendering, not state. No API, no flag, no stored preference, and
  nothing about them belongs in an auth or settings response.
- Notification read state and cleared announcement history are client-local
  today; a server that owns one would own the other (§4.8) — a product
  decision, not a gap.

### 19.6 Standing truth about this repository

There is **no backend implementation and no HTTP layer here** — every seam is
a Riverpod provider over an in-memory or `LocalStore`-backed mock (§16). The
pricing and Platform commerce surfaces are explicitly DEV/TEST-ONLY process
memory with no financial authority (§18.10); the client offers no purchase
action and says so plainly. Nothing in this package should be read as a claim
that a server exists.
