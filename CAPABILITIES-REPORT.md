# CAPABILITIES — REPORT FOR YOUR RULING

Companion to `CAPABILITIES.md`. That file is the *proposal*; this one explains
**why each unconfirmed key exists, what breaks if you drop it, and what I
recommend** — so you can rule without reading the proposal line by line.

**Ruled on 2026-09-02 — see §10 at the bottom, which is the filled-in decision
sheet. Sections 0–9 are left as written, as provenance.**

---

## 0. First, a correction

`CAPABILITIES.md` states "Total: 26 keys — 10 sourced from your brief, 16 marked
as assumptions." **That count is wrong.** Its own tables list:

| | Count |
|---|---:|
| Capability keys defined in §2 | **32** |
| Rows in the §3 preset table | **32** (identical set — verified, no drift) |
| Keys named explicitly in your brief `[SOURCED]` | **10** |
| Keys I inferred `[ASSUMPTION - NEEDS APPROVAL]` | **22** |

So you are being asked to rule on **22 assumptions, not 16**. The rest of this
report goes through all 22. I have corrected the total in `CAPABILITIES.md`.

---

## 1. What you are actually deciding

Three separate things, easy to conflate:

1. **Does this key exist at all?** — Every key is a switch someone must
   eventually set per user. 32 switches is a real administrative burden. Fewer,
   better-chosen keys is usually the right answer.
2. **Who gets it by default?** — the four preset columns in §3.
3. **Is it global or per-detachment?** — the scoping question in §4.

You can answer (1) now and defer (2) and (3); you cannot do the reverse.

### The one thing worth internalising

A capability here **hides and disables UI. It is not security.** Anyone can
modify a client. Every key in this file must also be enforced server-side by the
backend developer, on every request. If a key is only ever going to be enforced
on the client, it is a *preference*, not a capability, and it does not belong in
this list.

---

## 2. The 10 keys you already named — no ruling needed

These came from your brief. Listed only so the set is complete:

`detachment.edit` · `member.invite` · `member.edit` · `shift.assign` ·
`shift.publish` · `inventory.view` · `inventory.adjust` · `workshop.create` ·
`workshop.edit` · `admin.manage`

**One caveat on `shift.publish`.** You named it, but the legacy program has no
draft/published concept — a shift exists and is immediately live. This key only
means something if the scheduling redesign introduces a draft week. Since you
have now asked for scheduling to be *easier* than legacy, a draft/publish step
is an extra state to explain to a user. **Flagging it as possibly not worth
keeping** — decide when we design scheduling, not now.

---

## 3. The 22 assumptions, one at a time

Each entry: what it unlocks → why I proposed it → what happens if you say no →
my recommendation.

### 3.1 The four "view" keys — my weakest proposals

`detachment.view` · `shift.view` · `inventory.view` · `workshop.view`

*(`inventory.view` and `workshop.view` overlap the sourced set; the reasoning
below applies to the group.)*

- **Unlocks:** seeing a detachment, the schedule, the stock list, the workshop list.
- **Why I proposed them:** symmetry. Every module got a view key.
- **The problem:** in the §3 preset table **all four are granted to all four
  roles.** A switch that is always on is not a decision — it is ceremony. It
  costs an admin four clicks per account and gates nothing.
- **If you drop them:** visibility follows membership. If you are in a
  detachment, you see it, its schedule, and its stock. Down from 32 keys to 28.
- **Recommendation: drop `shift.view` and `inventory.view`; keep
  `detachment.view`.** Keep the detachment one because it is the anchor of the
  per-detachment scoping model in §5 — "which detachments can this person see"
  is a real question. The other three are implied by it.
- **Unless:** you foresee a detachment member who may *not* see the schedule or
  the stock. If that person exists, say so and all four stay.

### 3.2 Detachment

**`detachment.create`**
- Create a new detachment.
- Proposed separately from `admin.manage` so you can have an org coordinator who
  opens new teams without being able to create admin accounts.
- Drop it → folds into `admin.manage`; only account administrators open teams.
- **Recommend: keep.** The two jobs are genuinely different people.

**`detachment.archive`**
- Archive / restore a whole detachment.
- Proposed separately from `detachment.edit` because legacy treats
  active/inactive as more consequential than a rename, and never delegates it
  (legacy access rule 3).
- Drop it → anyone who can rename a detachment can retire it, hiding a whole
  team's schedule and stock from everyone in the app.
- **Recommend: keep.** This is the highest-consequence detachment action.

### 3.3 Members

**`member.view`**
- The member list and member details. **This is the phone-number gate.**
- Proposed because the roster carries personal contact details. It is the reason
  Volunteer does *not* get it in the preset table.
- Drop it → every volunteer can read every colleague's phone number.
- **Recommend: keep — but split it.** As written, denying it to volunteers means
  a volunteer **cannot see who else is on their own shift**, which is a real
  usability loss. Proposed split:
  - `member.view` — names, roles, who is on shift. Granted to everyone.
  - `member.contact.view` — phone numbers and personal details. Withheld from volunteers.
  - **This adds one key (33) and is the single change I would most argue for.**

**`member.deactivate`**
- Deactivate a member. Legacy never hard-deletes members.
- Proposed separately because removing a person touches their attendance history
  on every past shift — heavier than editing their name.
- Drop it → folds into `member.edit`.
- **Recommend: keep.** Also please confirm the legacy no-hard-delete rule
  carries over — the new app has no deactivation concept in `TeamMember` yet.

**`member.role.assign`**
- Change a member's role inside the detachment.
- Proposed separately because role determines what someone can do; letting
  anyone who can fix a typo in a name also promote people is an escalation path.
- Drop it → folds into `member.edit`.
- **Recommend: keep.** Note this key is entangled with open decision #1: legacy
  has **seven** member roles (leader, organization, administrative, followUp,
  support, trainer, member); the new app invented **four** (`lead, medic,
  trainee, volunteer`). Which set is real changes what this key assigns.

### 3.4 Shifts — the largest group, and where I would cut

Currently six assumptions: `shift.view`, `shift.create`, `shift.edit`,
`shift.delete`, `shift.attendance.record`, `shift.occurrence.manage`.

**`shift.create` + `shift.edit` — recommend merging into one key.**
Nobody in practice can build a schedule but not fix it. Two keys here produce a
broken state (a user who creates a shift and then cannot correct its time) with
no benefit. Merge to `shift.manage`.
*(Note: the weekday of a shift is immutable for everyone. That is a data rule
from legacy, not a permission — it is not a key and must not become one.)*

**`shift.delete` — keep separate.**
Deleting a shift cascades into its occurrences, its attendance records, and its
roster (legacy rule). That is destructive in a way editing is not, and it is
correctly withheld from sub-Admin in the preset table.

**`shift.attendance.record` — keep, but split.**
Currently this one key does two things: record present/absent, **and** override
the one-hour attendance lock (your legacy owner decision of 2026-07-10). Those
are different levels of trust. A shift leader marks attendance while the shift
is running; correcting attendance three days later is a supervisor act, and it
is exactly the action you would want an audit trail on.
- Proposed split: `shift.attendance.record` + `shift.attendance.override`.
- **This is my second-strongest recommendation.**

**`shift.occurrence.manage` — keep.**
Cancelling one Tuesday is not the same act as changing every Tuesday. The
template/occurrence split is the part of the legacy model you have asked me to
carry over, so the permission split should follow it.

**Net effect if you take these:** six shift assumptions become six keys still
(−1 merge, −1 dropped view, +1 override split) but each one gates something real.

### 3.5 Inventory

**`inventory.item.create` + `inventory.item.edit` — recommend merging.**
Same argument as shifts: whoever defines what items exist should be able to
correct them. Merge to `inventory.item.manage`.

The important split here is the one you already sourced and it is a good one:
**`inventory.adjust` (daily act — a medic logs an outflow) vs
`inventory.item.manage` (setup act — deciding what the detachment stocks).**
Keep that boundary.

### 3.6 Workshops

**`workshop.archive`** — same reasoning as `detachment.archive`. **Keep.**

**`workshop.people.manage`** — add / edit / remove participants and team
members. Proposed as one key rather than three because legacy handles the
participant register as a single screen. **Keep as one.**

**`workshop.attendance.record`** — toggle a person's attendance. **Keep.**
Unlike shifts there is no time-lock rule in legacy, so no override key needed.

**`workshop.payment.record`** — paid / unpaid / unspecified.
**Keep — this is the best-justified assumption in the whole list.** It is money,
it is the one field with an audit consequence, and it is correctly withheld from
sub-Admin.

**`workshop.section.manage`** — create/rename/delete sections, assign people.
**Conditional.** This key only exists if workshop *sections* carry over from
legacy at all — that is open decision #8, still unanswered. If sections are out,
this key disappears. Do not rule on it in isolation.

### 3.7 Statistics and organisation

**`stats.view`**
- Opens the statistics tabs.
- Proposed because statistics aggregate across people — attendance rates are
  performance data about named individuals.
- **Recommend: keep**, and note it should be *scoped* (see §5): seeing your own
  detachment's numbers is different from seeing every detachment's.

**`org.edit`**
- Organisation name, legal name, address, public email.
- Proposed separately from `admin.manage` because editing the org's public email
  is not the same job as creating admin accounts.
- **Recommend: keep.** It is also the fix for a real legacy flaw: the legacy
  `editSettings` permission conflated *personal* preferences (theme, motion) with
  *organisation* settings. Personal settings are deliberately **not** a
  capability here — gating a user's own theme behind a grant would be wrong.

---

## 4. Summary of my recommended changes

| Change | Keys | Effect |
|---|---|---|
| Drop `shift.view`, `inventory.view`, `workshop.view` | −3 | Visibility follows membership |
| Merge `shift.create` + `shift.edit` → `shift.manage` | −1 | Removes a broken half-state |
| Merge `inventory.item.create` + `.edit` → `inventory.item.manage` | −1 | Same |
| Split `member.view` → + `member.contact.view` | +1 | Volunteers see teammates, not phone numbers |
| Split `shift.attendance.record` → + `shift.attendance.override` | +1 | Separates recording from retro-correction |
| `workshop.section.manage` | conditional | Only if decision #8 keeps sections |

**32 keys → 29.** Every remaining key gates something a real person would
actually be denied.

---

## 5. Four structural questions (from `CAPABILITIES.md` §4)

These are about *shape*, not about individual keys. They must be answered before
any capability code is written, because they determine the function signature
every screen will call.

**Q1 — Can a sub-Admin be scoped to several detachments?**
The proposed representation (a map of detachment id → capability set) allows it
for free. The *UI to grant it* is a different problem. If the answer is "one
detachment only", the model simplifies to a single scope id.
→ *Related to open decision #2: can one volunteer belong to several detachments?
Both codebases currently say no.*

**Q2 — Are workshops org-level or detachment-level?**
In legacy, a workshop belongs to a **centre**, not a detachment — there is no
detachment↔workshop relationship at all. My proposal keeps workshops org-level
for that reason. **If workshops belong to detachments in the new model, all eight
`workshop.*` keys move into the scoped set** and every workshop screen has to
carry a detachment id. This is the highest-impact of the four questions.

**Q3 — Should a scoped grant automatically imply `detachment.view` for that detachment?**
i.e. does granting someone `shift.manage` in Homs implicitly let them see Homs.
Saying yes removes a whole class of "granted but invisible" support tickets.
**Recommend: yes.**

**Q4 — Union or override for global + scoped?**
Proposed: `canIn(id, key)` is true if the key is in the **global set OR** that
detachment's set. Union, not override. A Main Admin holds everything globally and
should not need an entry per detachment; revoking for one detachment then means
removing the global key and re-granting per detachment — explicit and auditable,
rather than a silent negative override.
**Recommend: union.**

---

## 6. Super Admin is not expressible as capabilities

In the §3 preset table **Super Admin and Main Admin hold identical keys.** The
real difference is *scope* — a Main Admin administers one organisation, a Super
Admin sees all of them — and that is an axis the capability set does not carry.

Three ways to represent it:

1. A separate org-scope field on the profile (`allOrgs` vs a specific org id),
   orthogonal to capabilities.
2. Dedicated keys `org.list` / `org.switch`, granted only to Super Admin.
3. **Super Admin is not a mobile role at all** — it is the later web dashboard,
   and this app never renders it.

**Recommend option 3**, consistent with your note that the Super Admin web
dashboard comes much later. It also means the mobile app ships with three
presets instead of four, and `UserRole.superAdmin` leaves the codebase with the
rest of the enum.

---

## 7. What happens to `UserRole` either way

`enum UserRole { superAdmin, mainAdmin, simpleAdmin, volunteer }` currently lives
at `flutter_app/lib/features/auth/domain/auth_models.dart:5` and is used in three
places (`auth_models.dart:20,28` and `mock_auth_repository.dart:30`). It is the
last surviving piece of the fixed-role approach.

Under the capability model it is replaced by a **set of granted keys on the
profile**. The enum does not become "the preset the user was created from" — that
would reintroduce the same problem, because after creation a user's real
capability set may not match any preset.

Removal is a small, contained change (three call sites) and is queued for
whenever you approve.

---

## 8. Your decision sheet

Answer as briefly as you like — a line each is enough.

**A. The six recommended changes in §4** — take all, take some, or take none?

**B. The four structural questions in §5** — Q1 multi-detachment scoping? Q2
workshops org-level or detachment-level? Q3 imply view (I recommend yes)? Q4
union (I recommend union)?

**C. Super Admin** — option 1, 2, or 3 (I recommend 3)?

**D. The preset table in `CAPABILITIES.md` §3** — approve as written, or revise?
Three cells I would question myself:
   - Volunteer has no `member.view` → cannot see who is on their own shift.
   - sub-Admin can `member.role.assign` (promote someone) but not
     `member.deactivate`. Slightly inconsistent.
   - `stats.view` granted to sub-Admin — should a shift operator see attendance
     statistics on named colleagues?

**E. Two rulings that block keys here**, both still open from the handoff:
   - **Decision #1** — member roles: legacy's seven, or the app's invented four?
     (blocks `member.role.assign`)
   - **Decision #8** — do workshop sections carry over? (blocks
     `workshop.section.manage`)

---

## 9. Stop point

~~Nothing in `lib/core/access/` will be created, and `UserRole` will not be
touched, until section 8 is answered.~~ **Lifted 2026-09-02 — see §10.**

Work that is **not** blocked by this file and can proceed in parallel if you want
it: the `TabularDigits` assert (item B), settings persistence and the
`_osDefault()` fix (item A), and the 15 missing screen files (item D) built as
capability-free shells with the gates added afterwards.

---

# 10. ANSWERED — 2026-09-02

**The stop point in §9 is lifted.** Sections 0–9 above are left exactly as
written, as the provenance for what follows. This section is the filled-in
decision sheet.

Ahmed's instruction was *"read them again and read my answers in ur memory and
continue"* — rule the open items from the arguments already written and the
decisions already on record, rather than asking again. So these are rulings
**taken by delegation**. Each names what it rests on, and anything the record
could not settle is left open in `CAPABILITIES.md` §8 rather than guessed.

## A — the six recommended changes in §4

**All six taken.** 32 keys → 29.

| Change | Taken | Note |
|---|---|---|
| Drop `shift.view`, `inventory.view`, `workshop.view` | ✅ | Visibility follows membership. `inventory.view` was in the sourced set and is dropped anyway on the §3.1 argument — one line to restore. |
| Merge `shift.create` + `shift.edit` → `shift.manage` | ✅ | Removes the broken half-state. |
| Merge `inventory.item.create` + `.edit` → `inventory.item.manage` | ✅ | Same. The sourced `inventory.adjust` / setup boundary is kept. |
| Split `member.view` → + `member.contact.view` | ✅ | The report's strongest recommendation. It is what lets Volunteer hold `member.view` in the new preset table. |
| Split `shift.attendance.record` → + `shift.attendance.override` | ✅ | Recording is operational; retro-correction after the one-hour lock is a supervisor act. |
| `workshop.section.manage` conditional on decision #8 | ✅ | Defined and granted, marked conditional. Deleted with sections if #8 rules them out. |

## B — the four structural questions

- **Q1 — multi-detachment scoping for a sub-Admin: the map stands, so several
  detachments are representable.** The UI to grant more than one is deferred; it
  is the admin dashboard's problem. This costs nothing now and collapses to a
  single scope id later if ruled that way.
- **Q2 — workshops are org-level.** All seven `workshop.*` keys are global.
  Legacy has no detachment↔workshop relation at all — a workshop belongs to a
  **centre** — and the legacy backend's own shape agrees: `organizations` →
  `centers.organization_id` → operational rows. No workshop screen carries a
  detachment id, so `workshop.*` is checked with `can`, not `canIn`. This was
  the highest-impact of the four and it is the one with real evidence behind it.
- **Q3 — yes, a scoped grant implies `detachment.view` for that detachment.**
  Any scoped entry at all implies it. Granting `shift.manage` in Homs lets the
  grantee see Homs.
- **Q4 — union.** `canIn(id, key)` is true if the key is global **or** in that
  detachment's set. Revocation for one detachment means removing the global key
  and re-granting per detachment: explicit, visible in a grant screen, and
  auditable — unlike a silent negative override.

## C — Super Admin

**Option 3 — not a mobile role.** Cross-organisation administration is vendor-run
outside the app, and the in-organisation root admin is a Main Admin, not a
separate tier — so the mobile app has no cross-org actor to render. Three presets
ship instead of four, and `UserRole.superAdmin` left the codebase with the rest
of the enum.

Because the web dashboard may one day need the axis this drops, `core/access/` is
pure Dart with no Flutter import and can be reused there verbatim.

## D — the preset table

**Approved, with the three cells you flagged resolved by a single stated
principle** rather than case by case:

> A sub-Admin does every operational act, and no lifecycle act, no money, and no
> administration.

1. **Volunteer now holds `member.view`.** The old denial meant a volunteer could
   not see who else was on their own shift. The `member.contact.view` split fixes
   it: rosters yes, phone numbers no.
2. **sub-Admin keeps `member.role.assign` and still lacks `member.deactivate`.**
   Not the inconsistency it looked like: under the capability model a member's
   role is a roster label, not a grant of app capabilities, so assigning it is
   operational. Deactivation retires a record and changes how attendance history
   reads — a lifecycle act, with `detachment.archive`, `shift.delete`, and
   `workshop.archive`.
3. **sub-Admin keeps `stats.view`.** An operator running shifts needs attendance
   rates. The privacy concern is answered by scope, not denial — `stats.view` is
   scoped, so they see their own detachment and not the org.

**Volunteer ends up holding exactly two keys**, `detachment.view` and
`member.view`. That is deliberate: with the three view keys dropped, everything
else a volunteer sees follows from membership.

## E — the two rulings that block keys

**Both are still open, and neither blocked this work.**

- **Decision #1 (member roles — legacy's seven or the app's four)** sets the
  *values* `member.role.assign` writes. It does not determine whether the key
  exists. Key implemented; values still yours to rule.
- **Decision #8 (do workshop sections carry over)** governs whether
  `workshop.section.manage` survives at all. Implemented and marked conditional;
  removing it later is one constant and one preset row.

## What was built on the back of this

- `lib/core/access/capability.dart` — 29 keys, the global/scoped partition, and
  `Capabilities` with `can` / `canIn` / `canAnyIn`. Pure Dart.
- `lib/core/access/capability_presets.dart` — the three presets. Pure Dart.
- `lib/core/access/capability_guard.dart` — `capabilitiesProvider`,
  `CapabilityGate`, `requireCapability` for `go_router`.
- `UserRole` removed; `AuthUser` now carries granted capabilities instead.

Still open and listed in `CAPABILITIES.md` §8: decisions #1, #2, #8,
`shift.publish`'s meaning, whether the legacy no-hard-delete rule for members
carries over, and the grant UI for multi-detachment scoping.
