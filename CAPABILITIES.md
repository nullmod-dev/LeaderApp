# CAPABILITIES

Status: **ruled and implemented.** 2026-09-02. The stop point in §7 is lifted.
`lib/core/access/` exists and `UserRole` has been removed. One key added
2026-09-07 for internal announcements — see §10; the model is unchanged.

The fixed role-enum approach is cancelled. `UserRole { superAdmin, mainAdmin,
simpleAdmin, volunteer }` in `lib/features/auth/domain/auth_models.dart` was the
last surviving piece of it and is gone as of this ruling.

---

## 0. Rulings — 2026-09-02

Ahmed's instruction: *"read them again and read my answers in ur memory and
continue"* — i.e. rule the open items from the arguments already written and
from the decisions already on record, rather than asking a fifth time.

So every ruling below is **taken by delegation**, and each one names the evidence
it rests on. Anything that could not be settled from the record is listed in §8
as still open — it is not guessed.

| Sheet item | Ruling | Rests on |
|---|---|---|
| **A** — the six §4 changes in the report | **All six taken.** 32 keys → 29. | The report argues each one; none was contested. |
| **B/Q1** — multi-detachment scoping | **The representation carries a map, so several detachments are possible.** The UI to grant more than one is deferred. | Costs nothing now and forecloses nothing; collapses to one id later if ruled so. |
| **B/Q2** — workshops org- or detachment-level | **Org-level.** All seven `workshop.*` keys are global, not scoped. | Legacy has no detachment↔workshop relation; a workshop belongs to a **centre**. The legacy backend confirms the shape: `organizations` → `centers.organization_id` → operational rows. |
| **B/Q3** — does a scoped grant imply `detachment.view`? | **Yes.** Any scoped entry for a detachment implies the right to see it. | Report recommendation; removes a class of "granted but invisible" tickets. |
| **B/Q4** — union or override | **Union.** `canIn` is true if the key is global **or** in that detachment's set. | Report recommendation; revocation stays explicit and auditable. |
| **C** — Super Admin | **Option 3 — not a mobile role.** Three presets ship, not four. | Cross-organisation administration is vendor-run outside the app (a service-role provisioning endpoint behind a platform secret), and the in-org root admin is a *Main* Admin. The mobile app never renders a cross-org actor. |
| **D** — the preset table | **Approved with the three questioned cells resolved.** See §3. | Resolved by one stated principle rather than case by case. |
| **E** — the two blocking decisions | **Still open — see §8.** Neither blocks the access layer. | Decision #1 sets the *values* `member.role.assign` writes, not whether the key exists. Decision #8 governs whether `workshop.section.manage` survives. |

**Reversal cost.** Every ruling here is one line in
`lib/core/access/capability.dart` or `capability_presets.dart`. Nothing about
the check surface depends on which way any of them went.

---

## 1. The model

- A **capability** is a plain string key, e.g. `workshop.create`.
- The signed-in user's profile carries a **set of granted capability keys**. It
  is runtime data returned by the repository, not a compile-time enum.
- The UI asks `can('workshop.create')`. It **never** asks `role == 'admin'`.
- **Roles are presets**, i.e. named starting sets of keys used when a Main Admin
  creates an account. They are a convenience at grant time, never the check.
  After creation the Main Admin can add or remove individual keys, so a user's
  real capability set may not match any preset.
- An unknown key is **denied**, never granted. Adding a key server-side must
  never silently unlock a client that does not know it.

### Client-side checks are UX only

This is written into the code, not just this document — see the library comment
at the top of `lib/core/access/capability.dart`:

> Capability checks in this app hide, disable, and gate UI. They are a usability
> device — they stop a user being offered an action that would fail. They are
> **not** a security boundary. Anyone can modify a client. Real enforcement of
> every capability in this file is the backend developer's responsibility, on
> every request, server-side. `TODO(security)` markers in the capability code
> point back to this paragraph.

### A denied capability renders as absent or disabled — never as a dead control

Carried from the house rule the legacy app enforces: the UI must never present a
control that does nothing. A capability the session lacks renders its control
**absent or visibly disabled**, and a missing handler is passed down as `null` so
the widget renders read-only. Preferring a removed affordance over an inert one
is the rule; `CapabilityGate` implements both and defaults to removal.

### The single-resolver rule

Carried over from the legacy `session_access.dart`, which got this right: **one**
function resolves whether a capability is held, and both the route guard and the
in-screen controls call it. When the guard and the controls resolve access
separately they drift, and a user reaches a screen where every control is
disabled — or worse, a control works on a screen they should not have reached.

In this code that function is `Capabilities.canIn`. `can` delegates to it. The
route guard and `CapabilityGate` both call it and nothing else.

### Two-key routes

Also carried from legacy: a route may open on **either of two** capabilities
while each control inside is gated individually. The shift screens are the
example — they open for schedule management *or* attendance recording, and the
edit controls and the attendance toggles check different keys.
`Capabilities.canAnyIn` is the resolver for that case.

### Tenant lifecycle is an earlier access gate (Point 9)

For a real tenant account, lifecycle is evaluated before any product-module or
administrator authorization question. `suspended`, `deletion_pending`, and
`deleted` are full operational blocks for both Main Admin and Simple Admin.
Capabilities cannot bypass them, and lifecycle changes do not rewrite the
capability grant, feature configuration, or limit values. Super Admin remains
on the separate Platform surface and manages these records there.

The canonical enforcement order is:

1. authentication/session validity;
2. account lifecycle;
3. `SaasTenant` lifecycle;
4. correct role/surface;
5. tenant Feature Flag;
6. Capability;
7. relevant Plan Limit for creation/mutation.

Flutter centralizes the tenant lifecycle decision in the typed startup/router
classification. It is UX enforcement, not the security boundary: the backend
must re-evaluate the lifecycle on protected requests and session refresh.

### Feature availability is a separate tenant entitlement (Point 8)

A **Feature Flag** asks whether the whole `SaasTenant` has a product module. A
**capability** asks whether this administrator may use an available module or
perform an action in it. A **plan limit** asks how much of a resource the
tenant may create or consume. No one of these implies another.

Once an authenticated tenant route has passed account and tenant lifecycle and
the surface check, the decision order is feature availability, then the
existing capability guard, then any applicable plan/usage limit. Consequently:

- feature enabled + capability granted → access;
- feature enabled + capability denied → the existing capability-denied state;
- feature disabled, regardless of a grant → the distinct feature-disabled
  state, without revealing or deleting module data;
- unknown, missing or unsupported feature state → disabled (fail closed).

The pure feature decision is `TenantFeatureAccess.isAvailable`; capability
resolution remains `Capabilities.canIn` / `canAnywhere`. They are deliberately
not combined into a role, mega-permission object or plan entitlement. Client
checks are UX only: the backend must reject disabled-module operations with
`feature_disabled` and then separately enforce capabilities and limits.

---

## 2. Capability keys — 29, as ruled

`[SOURCED]` = named explicitly in the brief.
`[RULED]` = was an assumption; settled on 2026-09-02 per §0.

### Detachment — 4

| Key | Unlocks | Scope | Source |
|---|---|---|---|
| `detachment.view` | See a detachment and its tabs. The anchor of per-detachment scoping. | scoped | [RULED — keep] |
| `detachment.create` | Create a new detachment. | **global** | [RULED — keep; an org coordinator who opens teams is not an account administrator] |
| `detachment.edit` | Edit name, region, main centre, notes. | scoped | [SOURCED] |
| `detachment.archive` | Archive / restore a detachment. | scoped | [RULED — keep; highest-consequence detachment act, never delegated in legacy] |

### Members — 6

| Key | Unlocks | Scope | Source |
|---|---|---|---|
| `member.view` | Names, roles, who is on a shift. | scoped | [RULED — keep, split] |
| `member.contact.view` | Phone numbers and personal details. | scoped | [RULED — **new**; the split so a volunteer can see who is on their own shift without reading everyone's phone number] |
| `member.invite` | Add a person to a detachment. | scoped | [SOURCED] |
| `member.edit` | Edit a member's name, specialty, phone. | scoped | [SOURCED] |
| `member.deactivate` | Deactivate a member. Legacy never hard-deletes. | scoped | [RULED — keep; touches attendance history on every past shift] |
| `member.role.assign` | Change a member's role within the detachment. | scoped | [RULED — keep] |

### Shifts — 7

| Key | Unlocks | Scope | Source |
|---|---|---|---|
| `shift.manage` | Create a weekly shift template **and** edit its name, leader, times. | scoped | [RULED — **merged** from `shift.create` + `shift.edit`] |
| `shift.delete` | Delete a shift with its occurrences, attendance, and roster. | scoped | [RULED — keep separate; destructive, cascades] |
| `shift.assign` | Add/remove members on a shift's roster. | scoped | [SOURCED] |
| `shift.publish` | Make a draft week visible to volunteers. **Reserved — meaning still open.** | scoped | [SOURCED, meaning pending] |
| `shift.attendance.record` | Mark present/absent on a dated occurrence, inside the one-hour window. | scoped | [RULED — keep, split] |
| `shift.attendance.override` | Correct attendance **after** the one-hour lock. | scoped | [RULED — **new**; a supervisor act, and the one that wants an audit trail] |
| `shift.occurrence.manage` | Cancel a date, or add a date manually. | scoped | [RULED — keep; cancelling one Tuesday ≠ changing every Tuesday] |

> **Not a permission:** the weekday of a shift is immutable for everyone. That is
> a data rule carried from legacy. It must never become a key.

> **On `shift.publish`:** the legacy program has no draft/published concept — a
> shift exists and is immediately live. Whether publish is real depends on which
> scheduling interaction the Domain Note 5 redesign picks, and that redesign now
> carries a standing requirement to be *easier* to operate than legacy, which
> argues against an extra state. The key is reserved and granted, but nothing
> checks it yet. Decide it when scheduling is designed.

### Inventory — 2

| Key | Unlocks | Scope | Source |
|---|---|---|---|
| `inventory.adjust` | Record an inflow or outflow movement. The daily act. | scoped | [SOURCED] |
| `inventory.item.manage` | Add items and edit name, unit, minimum, expiry. The setup act. | scoped | [RULED — **merged** from `inventory.item.create` + `.edit`] |

> The boundary that matters here is the sourced one and it is a good one: a medic
> logging an outflow is a different job from deciding what the detachment stocks.

### Workshops — 7, all org-level per §0/Q2

| Key | Unlocks | Scope | Source |
|---|---|---|---|
| `workshop.create` | Create a workshop. | global | [SOURCED] |
| `workshop.edit` | Edit name, date, location, fee, capacity. | global | [SOURCED] |
| `workshop.archive` | Archive / restore a workshop. | global | [RULED — keep] |
| `workshop.people.manage` | Add, edit, remove participants and team members. | global | [RULED — keep as one key; legacy handles the register as one screen] |
| `workshop.attendance.record` | Toggle a person's attendance. No time-lock in legacy, so no override key. | global | [RULED — keep] |
| `workshop.payment.record` | Set paid / unpaid / unspecified. | global | [RULED — keep; money, and the one field with an audit consequence] |
| `workshop.section.manage` | Create, rename, delete sections and assign people. | global | [RULED — **conditional** on open decision #8; deleted with sections if they do not carry over] |

**Implementation status (2026-09-15).** Six of the seven are now exercised by
real controls: create, edit (name, date, location, capacity, **fee**,
**status**), archive/restore, people management (participants, guests and the
organising team, all resolved against the roster by member id), attendance
and payment. `workshop.section.manage` remains granted-by-preset and checked
by nothing, pending decision #8. Every workshop control is additionally
closed while the workshop is archived — a lifecycle rule, not a second key.

### Statistics — 1

| Key | Unlocks | Scope | Source |
|---|---|---|---|
| `stats.view` | Open the statistics tabs. Scoped, so seeing your own detachment's numbers is a different grant from seeing every detachment's. | scoped | [RULED — keep; statistics are performance data about named individuals] |

### Administration and organisation — 2

| Key | Unlocks | Scope | Source |
|---|---|---|---|
| `admin.manage` | View Simple Admins, issue/cancel their onboarding invitations, and update their allowed capabilities. It never creates a password or activates an account. | global | [SOURCED; Point 17 management side implemented] |
| `org.edit` | Edit organisation info (name, legal name, address, public email). | global | [RULED — keep; editing the org's public email is not the same job as creating admin accounts] |

> **Deliberately not a capability:** personal app settings — theme, motion level,
> notification preferences, profile, security/sessions. These affect only the
> signed-in user's own device or account, so gating them behind a grant would be
> wrong. The legacy `editSettings` permission conflated personal preferences with
> organisation settings; that is split here into "no capability needed" and
> `org.edit`.

#### Simple Admin management

`/more/simple-admins` and both child forms resolve authority only through the
global `admin.manage` key. A `main_admin` normally holds it through the full
tenant grant; an `admin` role does not acquire it by role, and can enter only
if the backend explicitly granted the key. The invitation selector offers
only existing operational keys from `simpleAdminAssignableKeys`; it excludes
`admin.manage`, `org.edit`, lifecycle/destructive authority and capabilities
for tenant modules that are unavailable. The repository and backend remain
authoritative.

Creating an invitation binds the verified tenant context, normalized invited
email, `AuthRole.admin` relationship and selected grant on the server side.
The Flutter command carries no tenant id, role or password. Cancellation keeps
the record/status, and retries are idempotent. Account activation remains the
Point 17 recipient journey.

**Point 18B:** the selector groups the same keys by module (team, shifts,
inventory, workshops, statistics/announcements) with localized labels and
never shows a raw key; it offers nothing new. A successful invitee setup
consumes the invitation atomically (`pending → accepted`) and creates exactly
one Simple Admin relationship carrying the invitation's backend-held grant —
the recipient selects no role or capability. The post-verification
Team/Demo decision carries no authority either: "تجربة ليدر" yields
`customer_demo` with `Capabilities.none` and no tenant.

### Dropped on 2026-09-02

`shift.view` · `inventory.view` · `workshop.view` — all three were granted to
every role in the old preset table, so they gated nothing and cost an admin
three clicks per account. **Visibility now follows membership:** if you are in a
detachment you see its schedule and its stock; if you are in the org you see the
workshop list. `detachment.view` survives because "which detachments can this
person see" is a real question and it anchors the scoping model.

> `inventory.view` was in the sourced set — it was named in the brief. It is
> dropped anyway on the argument above. Restoring it is one constant plus one
> preset row if you disagree.

**Total: 29 keys — 10 sourced, 19 ruled.** (Historical total for this
ruling; §10 later added `announcement.publish` — the catalogue is **30**.)

---

## 3. Presets — 3, as ruled

A preset is the starting grant set at account creation. It is not stored as the
user's identity and is not consulted at check time. Super Admin is not a mobile
preset (§0/C).

The sub-Admin column follows **one principle**, which is also how the three
questioned cells were resolved:

> **A sub-Admin does every operational act, and no lifecycle act, no money, and
> no administration.**

Lifecycle acts are the four that destroy or retire a record —
`detachment.archive`, `member.deactivate`, `shift.delete`, `workshop.archive` —
plus `detachment.edit`, which renames the team itself. Money is
`workshop.payment.record`. Administration is `admin.manage`, `org.edit`,
`detachment.create`. Retro-correcting attendance after the lock
(`shift.attendance.override`) is a supervisor act and sits with the lifecycle
group.

| Key | Main Admin | sub-Admin | Volunteer |
|---|:--:|:--:|:--:|
| `detachment.view` | Y | Y | Y |
| `detachment.create` | Y | – | – |
| `detachment.edit` | Y | – | – |
| `detachment.archive` | Y | – | – |
| `member.view` | Y | Y | **Y** |
| `member.contact.view` | Y | Y | – |
| `member.invite` | Y | Y | – |
| `member.edit` | Y | Y | – |
| `member.deactivate` | Y | – | – |
| `member.role.assign` | Y | Y | – |
| `shift.manage` | Y | Y | – |
| `shift.delete` | Y | – | – |
| `shift.assign` | Y | Y | – |
| `shift.publish` | Y | Y | – |
| `shift.attendance.record` | Y | Y | – |
| `shift.attendance.override` | Y | – | – |
| `shift.occurrence.manage` | Y | Y | – |
| `inventory.adjust` | Y | Y | – |
| `inventory.item.manage` | Y | Y | – |
| `workshop.create` | Y | Y | – |
| `workshop.edit` | Y | Y | – |
| `workshop.archive` | Y | – | – |
| `workshop.people.manage` | Y | Y | – |
| `workshop.attendance.record` | Y | Y | – |
| `workshop.payment.record` | Y | – | – |
| `workshop.section.manage` | Y | Y | – |
| `stats.view` | Y | Y | – |
| `admin.manage` | Y | – | – |
| `org.edit` | Y | – | – |

### The Customer Demo envelope — a fourth grant shape, 2026-09-15

The Customer Demo trial runs the tenant application from an isolated
in-memory workspace (`features/demo/`), and every control in this app asks
`canIn` rather than a role — so the demo identity carries a **demo-only
envelope**: `Cap.all` minus `admin.manage` and `org.edit`, held globally.

It is not a preset and it is not a grant:

- it is attached to the demo identity, which has **no `saasTenantId`**, and is
  never written to a tenant, a membership, an invitation or a Team Code;
- it never reaches a production repository — a demo session's reads and
  writes are served by `DemoWorkspace` and thrown away when the trial ends;
- the backend must refuse a demo session on every tenant endpoint whatever
  the envelope says, exactly as §1's contract requires of every check here;
- the two administration keys are excluded on purpose: a trial has no
  business demonstrating real administrators, invitations, the organisation
  record or the plan with a working button.

### The three questioned cells, resolved

1. **Volunteer now holds `member.view`.** The old table denied it, which meant a
   volunteer could not see who else was on their own shift — a real usability
   loss caused by the key doing two jobs. The split fixes it: volunteers see
   names and rosters, they do not see `member.contact.view`.
2. **sub-Admin keeps `member.role.assign` and still does not get
   `member.deactivate`.** This is not the inconsistency it looked like. Under
   the capability model, a member's *role* is a roster label (who leads this
   shift), not a grant of app capabilities — assigning it is operational.
   Deactivation retires a person's record and rewrites how their attendance
   history reads, which is a lifecycle act. Different axes, so the split holds.
3. **sub-Admin keeps `stats.view`.** A day-to-day operator running shifts needs
   attendance rates to do the job. The privacy concern is answered by *scope*,
   not by denial: `stats.view` is scoped, so a sub-Admin sees their own
   detachment's numbers and not the org's.

**Volunteer holds exactly two keys** — `detachment.view` and `member.view`.
That is not an oversight. Everything else a volunteer sees (the schedule, the
stock list, the workshop list) follows from membership now that the three view
keys are dropped.

---

## 4. Scoped capabilities — ruled and implemented

A sub-Admin can be scoped per detachment (may manage A but not B). The legacy
program already needed this: `session_access.dart` binds a temporary account to
exactly one record id and validates both the route subtree and each control
against it.

### The representation

Two grant sets, checked in one call:

- a **global set** — capabilities held everywhere in the org. Exactly ten keys
  are global: `detachment.create`, `admin.manage`, `org.edit`, and all seven
  `workshop.*`.
- a **scoped map** — detachment id → capability set, for the nineteen keys that
  live inside a detachment (`detachment.view/edit/archive`, `member.*`,
  `shift.*`, `inventory.*`, `stats.view`).

The check surface is two methods:

- `can(key)` — global capabilities only.
- `canIn(detachmentId, key)` — true if the key is in the global set **or** in
  that detachment's scoped set. **Union, per §0/Q4.**

Plus `canAnyIn(detachmentId, keys)` for the two-key routes.

**Q3 is implemented:** any scoped entry for a detachment implies
`detachment.view` for it. Granting someone `shift.manage` in Homs lets them see
Homs, without a second grant.

### Why this shape

1. **The check site never changes.** A screen inside a detachment always calls
   `canIn(detachmentId, ...)`, whether or not scoping is enabled for that user.
   Turning scoping on later does not touch a single screen.
2. **It matches how the data is already routed.** Every inventory and shift
   route already carries a detachment id (see `DETACHMENT-SCOPING.md`), so the
   scope argument is always in hand.
3. **Workshops are org-level** (§0/Q2), so no workshop screen carries a
   detachment id and `workshop.*` is checked with `can`.
4. **It degrades safely.** If the backend sends only a global set, `canIn`
   behaves exactly like `can`.
5. **Union, not override.** A Main Admin holds everything globally and should
   not need an entry per detachment. Revoking for one detachment means removing
   the global key and re-granting per detachment — explicit and auditable,
   rather than a silent negative override that is invisible in a grant screen.

---

## 5. Super Admin — was "not a mobile role"; superseded 2026-09-07 (Point 2)

### The 2026-09-02 ruling, kept for the record

In any preset table Super Admin and Main Admin hold identical keys. The real
difference is *scope* — a Main Admin administers one organisation, a Super Admin
sees all of them — and that is an axis the capability set does not carry.

**Ruled: option 3.** Super Admin is not a mobile role. Cross-organisation
administration is vendor-run outside the app entirely, and the in-organisation
root admin is a Main Admin, not a separate tier. The mobile app ships three
presets and never renders a cross-org actor. If a Super Admin surface is ever
needed it is the later web dashboard, which is why `lib/core/access/` is pure
Dart with no Flutter import — the dashboard can reuse it verbatim.

The two rejected alternatives, recorded so the decision is legible: (1) a
separate org-scope field on the profile, orthogonal to capabilities; (2)
dedicated `org.list` / `org.switch` keys. Both add an axis the mobile app has no
screen for.

### What changed

The product changed, not the reasoning. Leader is a SaaS platform with paying
`SaasTenant`s, and the Super Admin surface is being built **in this app**
(Points 4–13), not in a separate web dashboard. So the mobile app does now
render a cross-tenant actor.

**What the old ruling got right, and this does not undo:** the difference is
*scope*, and the capability set does not carry it. That is precisely why the
answer is `AuthUser.role` — a classification of the **product surface** — and
**not** new capability keys. Neither rejected alternative came back: there is
still no org-scope field on the grant, and there are still no `org.list` /
`org.switch` keys.

### The three account levels — aliases

The product's names, the wire values, and the capability shape each one starts
from. **These are aliases, not new keys.** Nothing in §2 was renamed and
nothing was added.

| Product name | `AuthUser.role` | `saasTenantId` | Grant it starts from |
| --- | --- | --- | --- |
| **Super Admin** | `super_admin` | **`null`** | none of these keys — see below |
| **Main Admin** | `main_admin` | required | the `mainAdmin` preset (§3) — every key in this file |
| **Simple Admin** | `admin` | required | the `subAdmin` preset (§3), the sub-Admin tier this file has always described |

"Simple Admin" is the product's name for what §3 calls the **sub-Admin**
preset. The preset keeps its code name (`CapabilityPreset.subAdmin`); the two
words mean the same tier.

A Main Admin and the Simple Admins under them share one `saasTenantId` — one
paying customer, several administrators. `API_CONTRACT.md` § AuthUser carries
the invariant and the refusal rule.

### Super Admin holds no capability in this file

All 30 keys here are **tenant-operational**: detachments, members, shifts,
inventory, workshops, announcements, one organisation's settings. None of them
describes platform authority, so a Super Admin holds `Capabilities.none` and
every check in this file denies it — correctly. Platform capabilities, if the
platform surface needs them, arrive with that surface and against its own
repositories; they are not these keys reused.

This is the rule the implementation is written to defend: **giving Super Admin
the tenant grant so it "has something to see" would assert the one thing the
product model denies** — that the platform owner is a very powerful team
admin. What keeps it out of the tenant application is the router, not an empty
grant alone.

### Role still does not authorize anything

Every access decision resolves through `Capabilities.canIn` — §1's
single-resolver rule, unchanged. `role` selects which application an account is
looking at; capabilities decide what may run inside it. `if (role == mainAdmin)
allowEverything` is exactly the mistake dropping `UserRole` removed on
2026-09-02, and it must not come back through this door.

---

## 5b. Surface vs. authorization — 2026-09-07 (Point 3)

Point 3 built the startup classifier that turns a session into a destination.
It is worth stating what that did **and did not** change here, because a
routing layer that reads a role is exactly where a role check tends to grow
into an authority check.

### The two-layer rule, restated

| Layer | Question | Decided by | Where |
| --- | --- | --- | --- |
| **Surface** | Which *application* is this account looking at? | `AuthRole` | `core/startup/startup_destination.dart` — once, at startup |
| **Authorization** | What may run inside it? | `Capabilities.canIn` | every route guard and every control, unchanged |

The classifier reads `role` in exactly one place — one `if` that sends
`super_admin` to the platform and everyone else to the tenant application —
and reads capabilities for exactly one question: `hasAny`, "does this session
hold anything at all". Neither opens a control. Every per-route guard in
`app_router.dart` still resolves through `requireCapability` /
`Capabilities.canAnywhere`, which still resolve through `canIn`.

### Empty capabilities ≠ suspended, revoked, or unfinished

An account holding nothing gets its own designed state
(`/access-not-assigned`, «لم يتم تعيين صلاحيات لهذا الحساب بعد») whose whole
message is *the account is valid and connected; nobody has assigned it
anything yet*. It is **not** an error screen and the client never upgrades it
into a lifecycle claim. A suspension, a revocation or an unfinished signup is
said by the server, in `SessionAccess` (`API_CONTRACT.md`), or it is not said.

### Route → role matrix, as of Point 3

Role opens the door; the capability column is what still decides once inside,
and it is unchanged by this point.

| Route | Required role | Required capability |
| --- | --- | --- |
| `/startup` | none — pre-session | none |
| `/login`, `/forgot`, `/otp`, `/new-password`, `/new-device` | none | none |
| `/mfa-setup`, `/mfa-challenge` | none (also open to a signed-in tenant account, from Security) | none |
| `/session-expired`, `/session-invalid` | none | none |
| `/upgrade-required` | none — outranks every role | none |
| `/platform`, `/platform/*` | **`super_admin` only** | none in `Cap` — platform authorization is not designed yet (§5) |
| `/access-not-assigned` | `main_admin` / `admin` | reached *because* none is held |
| `/account-suspended`, `/account-revoked` | any authenticated | none |
| `/tenant-suspended`, `/tenant-deletion-pending`, `/tenant-deleted` | `main_admin` / `admin` | none — lifecycle outranks Feature Flags and capabilities |
| `/account-setup` | any authenticated | none |
| `/demo`, `/demo-expired` | any authenticated demo session | none |
| `/home`, `/detachment*`, `/workshop*`, `/more*`, `/search`, `/needs-review`, `/notifications`, `/announcements*` | `main_admin` / `admin` | **unchanged** — each route's existing guard |
| `/dev/session-states` | `main_admin` / `admin`, **debug builds only** | none |

Point 8 adds this **separate feature overlay**; it does not replace the
capability column above:

| Tenant route family | Required tenant feature | Capability after the feature check |
| --- | --- | --- |
| `/detachment/:id/storage*` | `inventory` | existing inventory/detachment rules |
| `/detachment/:id/stats`, `/detachment/:id/report*` | `statistics_reports` | `stats.view` where already required |
| `/workshop*` | `workshops` | existing `workshop.*` rules |
| `/workshop/:id/stats` | `workshops` **and** `statistics_reports` | existing workshop/statistics rules |
| `/announcements*` | `announcements` | existing `announcement.publish` rules on publishing; reading remains detachment-scoped |

Global Search excludes a disabled module before constructing/loading its
repository. The Notifications Center excludes inventory- and
announcement-derived rows while those modules are disabled; local generic
sync/conflict history remains because it exposes no disabled-module record
payload. Core authentication, Home, detachment groups/detachments, teams,
shifts, profile/security/settings and sync infrastructure have no tenant
feature requirement.

Two rules make the table enforceable rather than descriptive:

1. **A tenant role reaching `/platform` is turned around, and a `super_admin`
   reaching any tenant route is turned around.** Deep links included; the
   tenant shell is never built for a platform account, so no tenant repository
   is read and then hidden.
2. **Every non-tenant location above is startup-only.** A session the
   classifier did not send there is bounced out, so a healthy account cannot
   sit on `/account-revoked` because a link said so.

### Route → role matrix, updated for Point 4

`/platform` stopped being one page and became a four-branch shell. The rule did
not change; its scope did — **the whole subtree** is `super_admin`-only, and
`StartupDestination.claims` is the single function both halves of the router
ask (may this session stay here / is this a location only the classifier hands
out), so the two readings cannot disagree about `/platform/tenants`.

| Route | Required role | Required capability |
| --- | --- | --- |
| `/platform` | **`super_admin` only** | none in `Cap` |
| `/platform/tenants` | **`super_admin` only** | none in `Cap` |
| `/platform/tenants/new`, `/platform/tenants/:tenantId` | **`super_admin` only** | none in `Cap` — added at Point 6, and the point of listing them is that the module brought no new authorization concept with it |
| `/platform/tenants/:tenantId/subscription`, `/platform/tenants/:tenantId/limits` | **`super_admin` only** | none in `Cap` — Point 7 commercial mutations remain role-gated in the frontend mock |
| `/platform/tenants/:tenantId/features` | **`super_admin` only** | none in `Cap` — Point 8 feature management remains a platform role gate; tenant users consume state but never toggle it |
| `/platform/operations` | **`super_admin` only** | none in `Cap` |
| `/platform/health`, `/platform/alerts` | **`super_admin` only** | none in `Cap` — Point 10 read-only Platform Health/Security are control-plane reads; server-side Platform authorization remains required |
| `/platform/audit` | **`super_admin` only** | none in `Cap` — Point 11 implements the read-only control-plane list/detail; the backend must independently authorize it |
| `/platform/access`, `/platform/access/request` | **`super_admin` only** (Point 12 complete) | none in `Cap` — Point 12A break-glass grant; Flutter routing is a UX guard and the backend authorizes every command/protected read |
| `/platform/tenants/:tenantId/main-admin` (+ `/replace`) — **POINT 14 COMPLETE** | **`super_admin` only** | none in `Cap` — Point 14 Main Admin account management; the backend authorizes every read and command |
| `/platform/more` | **`super_admin` only** | none in `Cap` |
| `/platform/more/profile`, `/security`, `/themes`, `/eye-protect`, `/about` | **`super_admin` only** | none — these are the *account's own* screens, and a person's own device preferences are never capability-gated (§2) |
| `/mfa-setup`, `/forgot`, `/otp`, `/new-password` | also open to a signed-in **platform** session | none |
| every tenant route | `main_admin` / `admin` | unchanged |

Two additions to the Point 3 rules, both narrow:

3. **A signed-in platform session may still open the four auth pages above.**
   The Security screen it shares offers MFA enrolment and a password reset, and
   a surface that showed both rows and bounced off both would be shipping two
   dead controls. `/login` is deliberately *not* in that set.
4. **Platform More is an allowlist, not the tenant hub with rows hidden.**
   Hiding rows would still build the screen, and the tenant Settings hub reads
   the sync outbox and the capability grant to compose its row summaries — so
   rendering it would initialise tenant machinery for the one session that must
   never touch any. The five rows the platform surface offers are Profile,
   Themes & Performance, Reading comfort, Security and About; the organisation
   record, the sync centre, tenant notification preferences, the tenant plan,
   detachment settings and tenant admin management are absent by construction.

### Super Admin holds no capability, and `Cap.all` is not a substitute

Restating §5 because Point 4 is where the shortcut would have been taken. The
platform shell renders four destinations, a settings hub and an account screen
and asks `Capabilities` **nothing**: there is no `CapabilityGate` on the
platform surface, no `requireCapability` on any `/platform` route, and the
account screen deliberately omits the access-level, scope and grant rows rather
than reporting them as empty — reporting them would describe the platform owner
as the narrowest administrator in the system.

Granting `Cap.all` to a `super_admin` would make every one of those rows read
"granted", make `AdminExperience` classify it as a full in-tenant admin, and
make the tenant route guards pass. It is refused, and
`test/features/platform/platform_routing_test.dart` holds the other direction
too: a `main_admin` carrying `Cap.all` still reaches no part of `/platform`.

### Platform authorization is still not designed

**Points 6–11 changed nothing here.** The subscriber, commercial, tenant
feature, lifecycle, Health/Security, and Audit modules add
platform reads and writes, and invent no capability key,
borrowed none of the tenant-operational thirty, and introduced no
`requireCapability` on any platform route. Role remains the whole gate: a
`super_admin` session reaches `/platform/tenants*`, every tenant role is turned
around, and `test/features/platform/saas_tenant_list_test.dart` holds the
harder direction — a `main_admin` carrying `Cap.all` still reaches none of the
subtree, including subscription, limits and feature management. Which platform operators may
perform each commercial mutation, as opposed to only read it, is still the
undesigned fine-grained platform-authorization question below.

Unchanged from §5, and restated because Point 3 made the platform surface a
real destination: all 30 keys in this file (29 at the time; §10 added the
30th) are tenant-operational. A
`super_admin` holds none of them, and none may be borrowed to give the platform
screen something to render. Platform capabilities arrive with the platform
resources they authorize.

Point 11's Platform Audit Log is therefore not tenant `Cap` authorization and
must never reuse a tenant capability. `super_admin` remains only the current
Flutter surface gate. The server must authenticate and authorize every Audit
read and must authoritatively append evidence for consequential platform
mutations; a client route check or locally built audit record is not an
authorization or integrity boundary. Fine-grained platform read scope remains
an explicit backend integration decision, not a capability
invented here.

### Break-glass is not capability authorization (Point 12A)

A break-glass grant (`features/platform/domain/platform_break_glass_models.dart`)
is a separate, session-bound, expiring authorization for **one** active tenant
with the closed scope `tenant_operational_read`. It is deliberately outside
this file's model:

- it grants, borrows, or emulates **no `Cap` key**, is never `Cap.all`, and is
  never a Main Admin or Simple Admin preset;
- the Super Admin's `AuthUser` keeps `role: super_admin`,
  `saasTenantId: null`, and `Capabilities.none` throughout
  (`platform_break_glass_session_test.dart` holds this);
- `Capabilities.canIn` is never consulted for it, and nothing in the tenant
  shell, `CapabilityGate`, or `AdminExperience` reads it;
- no scope permits a write; tenant Feature Flags still bound what may be read,
  and Plan Limits are never reached because nothing is created;
- it authorizes no Platform mutation (subscription, features, limits,
  lifecycle stay role-gated exactly as before).

For a grant-authorized request the server's precedence is session → account
lifecycle → `super_admin` surface → live grant bound to this session → target
match → target tenant `active` → scope (read) → Feature Flag. The grant scope
occupies the Capability step for that single actor; it is not a capability.
The full contract is in `API_CONTRACT.md` → "Break-glass emergency access —
Point 12 complete". Point 12 adds no tenant-data route: the management/request
UI never enters `MainShell`, never mutates `AuthUser`, and never initializes a
tenant-operational repository (`platform_break_glass_ux_test.dart` holds this
for `/platform/access` and `/platform/access/request`). The `PlatformShell`
strip reads only `breakGlassAccessProvider`; it is awareness, not a gate, and
no control anywhere is enabled by it except the strip's own "end" action.

### Platform Reports are Super Admin control-plane reads (Point 13 — COMPLETE)

`/platform/reports` (Point 13A foundation; the route and four screens Point
13B; visual/accessibility closure — including the ≥900 dp dense-row
alternative — Point 13C) belongs to the `super_admin` control plane and adds
**no capability key**:

- no tenant `Cap` key authorizes, filters or appears in a report; `Cap.all`
  confers nothing, and a `main_admin`/`admin` session is refused the whole
  `/platform` subtree exactly as before;
- no fine-grained report permission is invented. If one is ever needed it is
  backend policy under "Platform authorization is still not designed", not a
  key in this file;
- the Flutter route guard is UX only — the backend authorizes **every** report
  read (and any future export) independently;
- the feature-availability report counts the Feature Flag axis only; it is not
  a capability count, and the usage report counts the Plan Limit axis only.
  Feature Flag ≠ Capability ≠ Plan Limit remains the rule;
- a break-glass grant confers no report access, and no report reads or
  initializes a tenant-operational repository
  (`platform_reports_repository_test.dart` holds this with
  `TenantRepositoryWatch` and an import scan).

### Pricing is ungated; commercial configuration is Super Admin authority (Point 19 — ARCHITECTURE)

The commercial surface (`PRICING-PROMOTIONS-ARCHITECTURE.md`) splits across the
two axes this file keeps apart, and adds **no capability key** on either side.

**Viewing prices needs no capability at all.** `/more/pricing` is open to every
tenant session — `main_admin` and `admin` alike — *and to a Customer Demo
trial*, which is the one place in the product where a demo is deliberately
given a screen the organisation rows deny it. Gating the price list would hide
the product from the people being asked to buy it, and there is nothing on the
page to authorize: it has **no write path**. That is stronger than a guard —
the demo cannot create a `TenantSubscription`, a `SaasTenant` or any payment
state because no such call exists on the surface, and a test holds it with
`TenantRepositoryWatch`.

**Configuring prices, global offers and coupons is platform authority.**
`/platform/operations/commerce` follows the Customer Demo control-plane
pattern exactly (Point 12 / `DemoControlPlane`):

- no tenant `Cap` key authorizes, filters or appears in it; `Cap.all` confers
  nothing, and `main_admin` / `admin` / demo sessions are refused the whole
  `/platform` subtree as before. **Do not add a `Cap` for this**;
- authorization is the control plane's, not a widget's role check: every
  mutation demands a `CommerceActor`, built only from a `super_admin` session
  (`platformCommerceActorProvider`), and is otherwise refused with
  `not_authorized` — the same shape a backend will answer with;
- a break-glass grant confers no commercial authority, and the commerce surface
  reads and initializes no tenant-operational repository;
- the Flutter route guard is UX only. The backend authorizes every commercial
  read and write independently, and is the sole authority on final price,
  coupon validity and redemption (`BACKEND-HANDOFF.md` §18).

Plan Limit ≠ Feature Flag ≠ Capability ≠ **billing duration**. All four billing
durations grant identical capabilities; a duration buys time, never function.

### Main Admin account management is Super Admin control-plane authority (Point 14A)

Point 14 (`features/platform/domain/platform_main_admin_models.dart`,
`PlatformMainAdminRepository`) lets a `super_admin` read a tenant's Main Admin
seat and run five backend-authoritative commands (resend setup, suspend,
reactivate, replace, cancel replacement). It adds **no capability key**:

- the surface is `super_admin` only; no tenant `Cap` key — `admin.manage`
  included — authorizes, filters or appears in it, and `Cap.all` confers
  nothing. `main_admin`/`admin` sessions are refused the whole `/platform`
  subtree and the mock refuses their reads (`not_permitted`);
- **the Main Admin remains a tenant role.** Managing the seat never gives the
  Super Admin a `saasTenantId`, a capability, a Main Admin preset, a tenant
  session or impersonation; the signed-in `AuthUser` stays `super_admin`,
  `saasTenantId: null`, `Capabilities.none` (held by
  `platform_main_admin_controller_test.dart`);
- account state is **not** capability state: suspending the Main Admin does not
  edit its grant, and a replacement's new holder receives whatever grant the
  backend's Main Admin provisioning policy assigns — not something this client
  writes. Simple Admins and their capabilities are out of Point 14 entirely
  (`admin.manage` stays the tenant's own mechanism);
- the Flutter route/role gate is UX only — the backend authorizes every read
  and command independently. No fine-grained Platform permission key is
  invented; if one is needed it belongs to "Platform authorization is still
  not designed".
- Point 14C (closure) changed presentation only: the tenant's access state is
  labelled beside the team name, apart from the account status, and neither is
  a capability. No key, grant or role changed.

Full contract: `API_CONTRACT.md` → "Main Admin account management — Point 14A
foundation".

### Organization and Plan are tenant reads, not a new grant (Point 15)

`/more/organization` and `/more/plan` add **no capability key** and no role
branch. Both tenant roles (`main_admin`, `admin`) may open both; `super_admin`
is turned around by the surface redirect before either builds, and the read
itself returns `tenant_context_unavailable` for it.

- **Before Point 15** `/more/org` was guarded by `org.edit` because it showed
  organisation-wide *figures* (total detachments, total members). The new
  Organization screen shows none, so its route and hub row are ungated; the old
  path is a redirect. The rule "organisation-wide figures need `org.edit`" is
  kept — it moved into the read: Plan's usage counts are included only for a
  session holding `org.edit` (server-enforced; the mock is told). A session
  without it sees the plan, subscription, limit maxima and modules.
- **Four axes, never merged:** Feature Flag (does the organisation have the
  module — Point 8), capability (may this account act — this file), plan limit
  (how much — Point 7), subscription status (commercial — Point 7), and tenant
  lifecycle (access — Point 9). Plan shows the first, third and fourth; the
  modules list reads the same `currentTenantFeatureAccessProvider` navigation
  obeys, an enabled module still grants nothing, and the screen says in plain
  Arabic that a missing tool may be a permission rather than the plan.
- Nothing on either screen writes: no plan change, flag toggle, override,
  lifecycle command, Team Code action or Main Admin action exists on the
  tenant surface.

### The Simple Admin experience, audited (Point 16 — COMPLETE)

Point 16 audited the tenant application from a Simple Admin's side and changed
**no key, preset, role or check order**. The canonical order stays: session →
account lifecycle → tenant lifecycle → role/surface → Feature Flag →
capability → plan limit. Role picks the surface; every control below still
resolves through `Capabilities.canIn` (via `DetachmentAccess` inside a
detachment), so a Main Admin and a Simple Admin holding the same keys are shown
the same thing (`simple_admin_experience_test.dart` holds this parity).

**The Simple Admin mapping** — what a `role: admin` session sees and may do.
"Preset" is `CapabilityPreset.subAdmin`; any grant may differ key by key.

| Surface / action | Visible when | Mutation needs | Feature Flag | Plan Limit (server) | Preset holds? |
| --- | --- | --- | --- | --- | --- |
| Home, Detachments tab, More, Profile, Security, Sync, Needs Review, Notifications, Search | always (tenant surface) | — | — | — | — |
| A detachment and its **Shifts** tab | `detachment.view` there (any scoped key implies it) | — | — | — | yes |
| Detachment list card → lands on | **Team** with `member.view`, else **Shifts** (`detachmentTabFor`) | — | — | — | — |
| **Team** tab / member page | `member.view` (tab hidden and route refused without it) | add `member.invite`, edit `member.edit`, role `member.role.assign`, deactivate `member.deactivate` | — | members (on create) | view/invite/edit/role yes; deactivate **no** |
| Contact details | `member.contact.view` | — | — | — | yes |
| Shift sheet / schedule edits | schedule visible with `detachment.view` | `shift.manage` / `shift.assign` / `shift.attendance.record` / `shift.attendance.override` / `shift.delete` / `shift.occurrence.manage`, each alone | — | — | all but override and delete |
| **Storage** tab | `detachment.view` | movement `inventory.adjust`; item form `inventory.item.manage` | `inventory` | — | yes |
| **Stats** tab, report, preview | `stats.view` (tab hidden without it; a direct link shows a *permission* state). The report's roster/stock sections ride `stats.view` too — statistics are named-individual data by the §3 ruling | — | `statistics_reports` | — | yes (scoped) |
| Detachment edit form | `detachment.edit` **or** `detachment.archive` | details `detachment.edit`; status `detachment.archive` (archive-only sessions get read-only details and a status-only save); delete also rides `detachment.archive` (established, no dedicated key) | — | — | **no** |
| Detachment groups / create detachment | `detachment.create` (else redirected to `/detachment`) | `detachment.create`; group delete `admin.manage` (established, no dedicated key) | — | detachment groups, detachments | **no** |
| Workshops tab | any `workshop.*` key; the list itself needs none | create/edit/archive/people/attendance/payment/sections, each its own key | `workshops` (+ `statistics_reports` for workshop stats) | workshops | create/edit/people/attendance/sections |
| Announcements list / compose | `announcement.publish` **anywhere** | `announcement.publish` in every addressed detachment | `announcements` | — | **no** (withheld by every preset) |
| Reading announcements (Home card, detachment strip, Notifications) | `detachment.view` of an addressed detachment | — | `announcements` | — | — |
| Notification preferences | always; the stock / workshop switches only while their module is on | personal, no key | `inventory` / `workshops` per switch | — | — |
| Organization, Plan | always (both tenant roles) | none exists | — | usage figures need `org.edit` (in the read) | usage **no** |
| `/platform/**` | never | never | — | — | never |

**Refusals are three different sentences.** `not_permitted` (this account),
`feature_disabled` (the organisation lacks the module) and
`plan_limit_reached` (the organisation has no room) are separate
`ProblemCode`s with separate localized copy; the latter two never say
«صلاحية». Flutter performs **no** local plan-limit check — the server is the
authority (Point 7), and no create path in this build can yet receive the
typed rejection (see `DATA-NEEDS.md` §4).

Frontend gating is UX. Every action in the table is re-authorized by the
backend on every request, including a write replayed from the offline outbox
after a key was revoked.

---

### Onboarding never assigns authority (Point 17A, verified end-to-end in 17B, closed in 17C)

**Point 17B confirms this holds through the real screens, not only the
mock's interface shape.** `onboarding_full_session_bridge_test.dart` proves
the resulting `AuthUser.capabilities` matches the authorization's own grant
for a Main Admin seat, a Simple Admin invitation and a returning account —
never anything typed into the display-name field, which is the only free-text
input anywhere in the journey. The session bridge
(`MockAuthRepository.installOnboardedSession`) receives a fully-formed
`AuthUser`; it has no code path that reads a form value.

- **A pre-onboarding identity holds no capability.** A pending verification
  challenge is not a session at all; a restricted onboarding session has no
  `AuthUser`, so `capabilitiesProvider` is `Capabilities.none` and every
  guarded route and control is refused. The backend must answer every tenant
  operational, Platform, Sync, notification and search request made with an
  onboarding session with `onboarding_required`, whatever the client shows.
- **Role and capabilities are backend-assigned, never self-selected.** No
  sign-up, sign-in, Google, Team Code or setup request carries a role, a
  tenant id or a capability — the repository interface has no parameter for
  one. The role comes from the authorization record (the Point 14 Main Admin
  seat designation, or a Simple Admin invitation); the grant comes from that
  record's server-side preset/assignment and arrives with the **full**
  session, like every grant.
- **The Team Code authorizes nothing.** It names a tenant; eligibility is the
  backend authorization matched to the verified address. A valid code with no
  authorization is refused exactly like an unknown code.
- The capability catalogue, presets and the `stats.view` member-attendance
  policy are unchanged by Point 17A.

**Point 17C closure — re-checked, no catalogue change.**

- **A cancelled invitation grants nothing.** The grant a Simple Admin
  receives is the one on a *pending* invitation at setup time. 17C found and
  fixed a mock defect where an invitation cancelled after the in-process
  "server" had started could still auto-link and complete setup with its
  grant; it is now withdrawn on the shared server
  (`onboarding_repository_test.dart` "invitation cancelled after the server
  started never links", "cancelled mid-setup withdraws the link"). The backend
  must enforce the same: cancellation invalidates the authorization for link
  **and** for `complete`.
- **"Check for my invitation" carries no authority input.** The new
  `/link-team` action is a plain `GET /auth/onboarding`; the role and grant
  still come only from the matched invitation, and the answer never discloses
  another address's invitation.
- **Stored credentials carry no capability.** The secure-storage records hold
  opaque tokens and a display-only snapshot (no capability field); capabilities
  are re-read with the full session on every restore, never cached locally.
- **Google carries no capability.** The ID token is exchanged once; Flutter
  reads no claim, and a Google identity links through the same invitation /
  seat authorization as a password identity.

## 6. Where this lives in the code

Implemented as proposed. The split keeps the access rules free of mobile-only
dependencies, so the future web dashboard can import them unchanged.

- `lib/core/access/capability.dart` — the 30 key constants (§10), the global/scoped
  partition, and the `Capabilities` value type with `can` / `canIn` /
  `canAnyIn`. **Pure Dart, no Flutter import.**
- `lib/core/access/capability_presets.dart` — the three presets. **Pure Dart.**
- `lib/core/access/capability_guard.dart` — the Flutter/Riverpod layer:
  `capabilitiesProvider`, `adminViewProvider`, the `CapabilityGate` widget for
  hiding or disabling controls, and `requireCapability` for `go_router`
  redirects.
- `lib/core/access/admin_experience.dart` — the admin-experience resolver.
  **Pure Dart.** See §9.
- `lib/core/startup/startup_destination.dart` — the startup/surface classifier
  (Point 3). **Pure Dart**, and it consumes `Capabilities.hasAny` only. See
  §5b.

---

## 7. Stop point — lifted

The 2026-09-02 rulings in §0 clear this file. Admin screens are unblocked.

---

## 9. The admin experience — presentation, 2026-09-06

The product ships two administrator experiences. Neither is a role, and
neither is stored anywhere: both are **derived from the grant already issued**,
in one pure function, `AdminView.of` in `lib/core/access/admin_experience.dart`.

### The mapping, stated once

| Experience | Label | Holds |
|---|---|---|
| `AdminExperience.full` | «إدارة كاملة» | **any one** of `admin.manage`, `org.edit`, `detachment.create` |
| `AdminExperience.scoped` | «إدارة محددة» | anything less |

Those three keys are exactly the group §3 calls *Administration*, and they are
the three a sub-Admin preset is defined by not holding. Nothing else in the app
may invent a second definition of "main admin".

**This is not the account's role, and 2026-09-07 did not make it one.**
`AuthUser.role` (§5) names the *product surface* — platform, or one
`SaasTenant`. `AdminExperience` answers a different question one level down:
*inside the tenant application*, how broad is this session's UI. They are
independent — a `main_admin` whose keys were narrowed is still a Main Admin and
is honestly shown the scoped UI; an `admin` granted `org.edit` is still a
Simple Admin and is honestly shown the full one. A `super_admin` is not
classified here at all: it is not in the tenant application. The labels above
are presentation only: they name how broad the UI is, never what may run, and
never what the account *is*.

### What the classification is allowed to decide

Breadth, and nothing else:

- which bottom-nav destinations are offered (`MainShell`);
- whether the dashboard shows its organisation section and the two
  organisation-level shortcuts;
- whether the detachment-group/container hierarchy is where the second tab
  opens.

Every destination behind those still carries its own route guard, and every
control inside still resolves through `Capabilities.canIn`. Hiding a row is
decluttering; the guard is the gate. `test/core/access/admin_experience_test.dart`
holds the classification to "grants nothing, withholds nothing", and
`test/features/auth/admin_experience_routes_test.dart` walks the deep links.

### Scope

`AdminView.coversDetachment` is the one question a list filter asks, and
`detachmentListProvider` is the one place it is asked — the dashboard switcher,
the detachment group's detachments and the unscoped list all read through it. An
organisation-wide grant passes the list through untouched; a scoped grant sees
only the detachments named in it.

`AdminView.categoriesIn` / `searchableCategories` are the seam a
capability-aware Global Search will use: one question — *which data categories
may this admin search* — answered where every other scope question is.

---

## 10. `announcement.publish` — 2026-09-07

The internal announcement system (Point 14) needed an authority the 29 keys did
not express. Nothing existing covered it honestly:

- `admin.manage` administers *accounts*, not communication.
- `org.edit` edits the organisation *record*.
- `detachment.edit` edits the detachment *record*.

Overloading any of them would have meant "may edit the org" silently becoming
"may put a notice on five dashboards", which is the drift this whole model
exists to prevent. So **one** key was added — 29 → 30.

| Key | Scope | Covers |
|---|---|---|
| `announcement.publish` | **per detachment** | Publishing an announcement into that detachment, and withdrawing/managing one addressed to it. |

**Per-detachment, not global**, because an announcement is *addressed* to
detachments: the question the target picker asks is "may this session publish
**here**". A main admin holds it globally and may address every detachment they
can see; a scoped admin may address only the detachments their grant names.

**There is deliberately no `announcement.view`.** Reading a notice addressed to a
detachment follows from being able to see that detachment, which is exactly what
`detachment.view` says and what any scoped grant implies (§4/Q3). A second key
would gate nothing — the same reason `shift.view`, `inventory.view` and
`workshop.view` were dropped on 2026-09-02.

**Withheld by every preset.** `CapabilityPreset.mainAdmin` is `Cap.all` and so
holds it; `subAdmin` and `volunteer` list their keys explicitly, so a sub-Admin
gets it only when a main admin grants it deliberately. That is the ruling in
Point 14 §4 — a scoped admin publishes *only when granted* — implemented as
"fail closed", not as a special case.

**Closed by archiving.** It is in `historicallyClosedCapabilities`: publishing a
notice to a detachment that has finished running is an operational write with
nobody left to read it. Reading the announcements it already carries stays open,
like the rest of its history.

**The surfaces that span detachments.** `/announcements` and
`/announcements/new` are not inside one detachment, so their route guard asks
`Capabilities.canAnywhere` — held globally *or* in at least one detachment.
Asking the organisation-wide question (`canIn(null, ...)`) would have refused
precisely the scoped administrator the key was granted to. `canAnywhere`
delegates to `canIn`, so the single-resolver rule holds.

**Backend.** Frontend enforcement here is a UX gate like every other check in
this file. The server must verify the caller holds the key *in every detachment
an announcement addresses*, on create and on withdraw — see `API_CONTRACT.md`
§ Announcements.

---

## 8. Still open — not guessed

These could not be settled from the record and are **not** decided here.

1. **Decision #1 — member roles.** Legacy has seven (leader, organization,
   administrative, followUp, support, trainer, member); the new app invented
   four (`lead, medic, trainee, volunteer`). This sets the *values*
   `member.role.assign` writes. It does not block the key or the access layer.
2. **Decision #8 — do workshop sections carry over?** If not,
   `workshop.section.manage` is deleted — one constant and one preset row.
3. **Decision #2 — can one volunteer belong to several detachments?** Both
   codebases currently say scalar. The scoped map already allows several for an
   *admin*; the volunteer question is a domain-model question, not this one.
4. **`shift.publish`'s meaning** — reserved, granted, unchecked, pending the
   Domain Note 5 scheduling redesign.
5. **Does the legacy no-hard-delete rule for members carry over?** The new
   `TeamMember` has no deactivation concept yet, so `member.deactivate` has
   nothing to call.
6. **The grant UI for multi-detachment scoping.** The model allows it; no screen
   grants it. That is the admin dashboard's problem, now unblocked.
