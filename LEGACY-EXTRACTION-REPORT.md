# LEGACY-EXTRACTION-REPORT

Status: **analysis only — nothing has been ported.** No file was copied into this
repository. Awaiting approval before any porting begins.

Legacy source: `/home/ahmed/Documents/Python-Files/flutter/apps/medical_team`
(local path supplied by the owner; the GitHub URL in the brief was not used and
not contacted).

Scope read: `lib/features/workshops/**`, `lib/features/detachments/**`, and the
`lib/core/**` files those two features depend on. Backend, Supabase, sync,
export, centers, reports, and auth were read **only** where a workshop or
detachment file imports them.

---

## 0. Legacy source integrity

- Access was **read-only**: `ls`, `find`, `cat`, `sed -n`, `grep`, `wc`,
  `git status`, `git log`, `git remote`. No write, no checkout, no commit, no
  push, no branch, no stash.
- No clone was made. The local path was used directly, so nothing was written
  anywhere outside this repository.
- The legacy repo was **not** added as a remote of this project. This project
  still has no remote at all.
- **The legacy working tree was already dirty before this session.** At the time
  of reading, `git status --porcelain` reported **86 entries** (70 modified,
  1 deleted, 15 untracked) against HEAD `d8d5891`. Those changes are the
  owner's, pre-existing, and untouched. Baseline fingerprint recorded for
  comparison: `md5(git status --porcelain) = 0a698ec3293277a5b561f45e041a351a`.
- Confirmed: **the legacy source is unchanged by this session.**

---

## 1. Two corrections to the brief's premises

These change what the port actually is, so they are stated before the inventory.

### 1.1 The old program DOES have shift scheduling — and it is substantial

The brief states the old program had neither inventory nor shift scheduling.
Inventory is correct. Shift scheduling is not.

The legacy app contains a complete weekly-template + dated-occurrence scheduling
module, roughly 2,900 lines:

| File | Lines |
|---|---|
| `features/detachments/data/shift_schedule_providers.dart` | 368 |
| `features/detachments/data/daily_shift_providers.dart` | 431 |
| `features/detachments/data/attendance_lock.dart` | 150 |
| `features/detachments/presentation/shift_schedule_screen.dart` | 469 |
| `features/detachments/presentation/daily_shift_details_screen.dart` | 1033 |
| `features/detachments/presentation/widgets/create_shift_sheet.dart` | 431 |
| `features/detachments/presentation/widgets/shift_members_sheet.dart` | 234 |
| `features/detachments/presentation/widgets/shift_delete_dialog.dart` | 51 |
| `core/constants/shift_weekdays.dart` | 108 |

It carries real, decided business rules (recurrence, tombstones, the attendance
lock, roster-vs-attendance separation) that are documented in §4 below. **This is
proven logic and it should be extracted, not discarded**, even though the brief
calls for the scheduling *UI* to be redesigned. The redesign should sit on top of
these rules; the rules themselves are the expensive part and they already exist.

**Decision needed from you.** See open decision #7.

### 1.2 Inventory genuinely does not exist

Confirmed by content search across the whole legacy `lib/`: there is no
inventory, stock, warehouse, medicine, or supply module, and no such table in
`core/database/tables/`. Per-detachment inventory is a **new build with no
legacy source**. Nothing to extract.

What the legacy detachment module has *instead* — and which the new app's domain
does not model at all — is a **Patients** register
(`patients` table, `detachment_patients_*`, 1,341-line screen).

---

## 2. Inventory — WORKSHOPS (8,879 lines)

The brief says the old workshop implementation is good and should be ported
faithfully. Reading it, I agree: the logic is clean, the rules are explicit, and
the doc comments record the owner decisions behind them.

### 2.1 Data / logic layer

| File | Lines | What it does | Disposition | Reason |
|---|---|---|---|---|
| `data/workshop_list_providers.dart` | 319 | List item projection, date filter (all/today/upcoming/finished), 5 sort modes, 5 opt-in advanced filters, attendance %, unpaid count | **EXTRACT LOGIC ONLY** | `sortWorkshops`, `WorkshopAdvancedFilters.matches`, `statusFor`, `attendancePercent` are pure Dart and port verbatim. The Drift `customSelect` around them does not — it becomes a mock repository returning `Result<List<...>>`. |
| `data/workshop_form_providers.dart` | 120 | Create/update workshop; form projection | **EXTRACT LOGIC ONLY** | Field set and write semantics carry over; Drift companions do not. |
| `data/workshop_details_providers.dart` | 263 | Details + participants + team members; archive; attendance and payment mutations | **EXTRACT LOGIC ONLY** | Same. Note the archive-is-soft-and-reversible rule (§4.2). |
| `data/workshop_sections_providers.dart` | 236 | Sections CRUD; delete detaches people rather than deleting them; section member roll-up | **EXTRACT LOGIC ONLY** | The detach-on-delete rule is important and must survive; the SQL does not. |
| `data/workshop_participant_form_providers.dart` | 104 | Participant create/update/hard-delete | **EXTRACT LOGIC ONLY** | Hard-delete-vs-deactivate rationale carries over as a documented decision. |
| `data/workshop_team_member_form_providers.dart` | 106 | Team member create/update/hard-delete | **EXTRACT LOGIC ONLY** | Same. |
| `data/workshop_stats_providers.dart` | 467 | Stats aggregation (per group: total/present/paid/unpaid/unspecified) **plus** PDF and XLSX export builders | **SPLIT: EXTRACT LOGIC ONLY (stats) / DROP (export)** | The aggregation is the valuable half. The export half pulls `pdf`, `printing`, and an xlsx writer — three packages not on this project's allowlist, and export is not in any Batch 0 or near-term page. Re-propose export as its own feature later. |

### 2.2 Presentation layer

| File | Lines | What it does | Disposition | Reason |
|---|---|---|---|---|
| `presentation/workshops_list_screen.dart` | 634 | List, search, date-filter chips, options sheet entry | **PORT WITH CHANGES** | Flow and information architecture kept; theme, tokens, localization, five states, capability guards, Riverpod-over-mock all replaced. |
| `presentation/workshop_details_screen.dart` | 2378 | The core screen: header, archive action, two primary tabs (participants / team), 3 view modes (list / grid / compact), search, attendance switch, payment cycle button, filters by attendance + payment + section + role | **PORT WITH CHANGES** | Faithful port of behaviour. This file is far too large; splitting it into a shell + tab widgets is a *structural* change only and does not alter UX. |
| `presentation/workshop_form_screen.dart` | 707 | Create/edit: name, date, location, fee, capacity, active | **PORT WITH CHANGES** | Field-level behaviour preserved exactly. |
| `presentation/workshop_participant_form_screen.dart` | 669 | Participant add/edit incl. section, attendance, tri-state payment | **PORT WITH CHANGES** | Same. |
| `presentation/workshop_team_member_form_screen.dart` | 718 | Team member add/edit incl. role | **PORT WITH CHANGES** | Same. |
| `presentation/workshop_sections_screen.dart` | 764 | Sections list, create, rename, delete, member sheet | **PORT WITH CHANGES** | Same. |
| `presentation/workshop_stats_screen.dart` | 499 | Stats view + export buttons | **PORT WITH CHANGES** (minus export) | Export buttons dropped with the export layer. |
| `presentation/widgets/workshop_options_sheet.dart` | 220 | Sort dropdown + advanced-filter switches | **PORT WITH CHANGES** | Keep the "dropdown, not chips" decision recorded in the file. |
| `presentation/widgets/workshop_section_field.dart` | 79 | Shared section dropdown with an explicit "no section" null choice | **PORT WITH CHANGES** | Small, well-factored, and the null-is-a-real-state rule matters. |
| `presentation/widgets/delete_person_dialog.dart` | 42 | Destructive confirm naming the person | **PORT WITH CHANGES** | Becomes a core widget; reused by detachments. |
| `presentation/widgets/workshop_name_text.dart` | 34 | Name rendering helper | **PORT WITH CHANGES** | Trivial. |
| `presentation/widgets/workshop_export_buttons.dart` | 520 | PDF/XLSX share sheet | **DROP** | Export layer, out of scope, unapproved packages. |

---

## 3. Inventory — DETACHMENTS (10,774 lines)

Per the brief, detachments are **rebuild the UI, extract the rules**. Dispositions
below reflect that: nearly everything in `presentation/` is EXTRACT LOGIC ONLY,
not PORT.

### 3.1 Data / logic layer

| File | Lines | What it does | Disposition | Reason |
|---|---|---|---|---|
| `data/attendance_lock.dart` | 150 | The D-16 attendance time lock; permission-overrides-lock rule | **PORT AS-IS** (one of only two) | Pure Dart, zero Flutter/Drift imports, total parsing, already unit-testable. Only the Arabic-free API survives untouched; nothing to change but the file's home. |
| `data/shift_schedule_providers.dart` | 368 | Weekly shift templates, monthly occurrence auto-generation, date-range validation, cascade delete | **EXTRACT LOGIC ONLY** | Rules are gold (§4.3). Drift/uuid/sync wrappers are not. |
| `data/daily_shift_providers.dart` | 431 | Per-date occurrences, attendance seeding, cancel-as-tombstone, manual date add, roster diff | **EXTRACT LOGIC ONLY** | Same. |
| `data/detachment_list_providers.dart` | 137 | List + search + member/leader counts; create/update/archive | **EXTRACT LOGIC ONLY** | Same. |
| `data/detachment_details_providers.dart` | 193 | Details + member list with search across name/specialty/phone and role filter | **EXTRACT LOGIC ONLY** | The multi-field search and the leaders-sort-first rule carry over. |
| `data/detachment_member_details_providers.dart` | 106 | Member read/update/deactivate | **EXTRACT LOGIC ONLY** | Deactivate-not-delete rule carries over. |
| `data/detachment_stats_providers.dart` | 343 | Attendance donut, role distribution, per-member attended-days drill-down | **EXTRACT LOGIC ONLY** | Aggregation shapes are reusable; the new stats tab is a redesign. |
| `data/detachment_patients_providers.dart` | 205 | Patients register CRUD + search | **DEFER — DECISION NEEDED** | Not in the new domain model at all. See open decision #8. |
| `data/detachment_report_providers.dart` | 377 | PDF/XLSX attendance + patients report | **DROP** | Export layer, as above. |

### 3.2 Presentation layer

| File | Lines | What it does | Disposition | Reason |
|---|---|---|---|---|
| `presentation/detachments_list_screen.dart` | 459 | List, search, status chip, metrics | **EXTRACT LOGIC ONLY** | New design; a `DetachmentListPage` already exists in this project. |
| `presentation/detachment_details_screen.dart` | 871 | Header, summary grid, tab chips, member list, per-record capability lookup | **EXTRACT LOGIC ONLY** | The tab-shell idea survives; the tab *set* changes (Domain Note 3). |
| `presentation/detachment_member_details_screen.dart` | 816 | Member form, status pill, phone actions | **EXTRACT LOGIC ONLY** | New design. |
| `presentation/new_detachment_screen.dart` | 486 | Create detachment | **EXTRACT LOGIC ONLY** | Field set carries over. |
| `presentation/new_detachment_member_screen.dart` | 389 | Add member | **EXTRACT LOGIC ONLY** | Field set carries over. |
| `presentation/detachment_stats_screen.dart` | 1450 | Donut chart (custom painter), role distribution, role-member sheet with detailed/compact modes | **EXTRACT LOGIC ONLY** | The `_DonutPainter` is reusable as a core widget if you want it; flagged, not assumed. |
| `presentation/shift_schedule_screen.dart` | 469 | Weekday cards + shift cards | **EXTRACT LOGIC ONLY** | Explicitly to be redesigned. |
| `presentation/daily_shift_details_screen.dart` | 1033 | One weekday: shift details, occurrence date chips, per-date attendance list | **EXTRACT LOGIC ONLY** | Explicitly to be redesigned. |
| `presentation/widgets/create_shift_sheet.dart` | 431 | Create/edit shift; weekday locked in edit mode | **EXTRACT LOGIC ONLY** | The weekday-immutable rule must survive the redesign. |
| `presentation/widgets/shift_members_sheet.dart` | 234 | Roster checkbox diff | **EXTRACT LOGIC ONLY** | The diff semantics survive. |
| `presentation/widgets/shift_delete_dialog.dart` | 51 | Destructive confirm | **EXTRACT LOGIC ONLY** | Folds into the shared delete dialog. |
| `presentation/detachment_patients_screen.dart` | 1341 | Patients list/grid, search | **DEFER — DECISION NEEDED** | See open decision #8. |
| `presentation/widgets/detachment_export_sheet.dart` | 434 | Selective export | **DROP** | Export layer. |

### 3.3 Shared core files the two features depend on

| File | Disposition | Reason |
|---|---|---|
| `core/constants/shift_weekdays.dart` | **PORT AS-IS** (logic half) | `dateOnly`, `datesInMonthFor`, `latestDateOnOrBefore`, `dateTimeWeekday` are pure and correct. The Arabic month names and label formatters move into the localization file instead of staying inline. |
| `core/constants/app_roles.dart` | **PORT WITH CHANGES** | Enum *values* are useful; the inline Arabic `label` extensions violate the no-strings-outside-localization rule and must move to `S`. |
| `core/access/session_access.dart` | **EXTRACT LOGIC ONLY** | The single most useful access file: it already proves per-record scoped capability. See CAPABILITIES.md. |
| `core/access/app_permissions.dart` | **EXTRACT LOGIC ONLY** | Correct shape (grant set + `can()`), wrong granularity (5 coarse keys) and wrong anchor (`AdminRole` enum). |
| `core/access/temp_accounts.dart` | **EXTRACT LOGIC ONLY** | `TempPermission` is the closest thing legacy has to the runtime capability model you want. |
| `core/access/admin_role.dart` | **DROP** | Two-value role enum. Cancelled by the new permissions model. |
| `core/database/**`, `core/supabase/**`, `core/sync/**`, `core/export/**`, `core/config/**` | **DROP** | Drift, Supabase, sync outbox, PDF/XLSX. All backend or unapproved packages. Read only to recover the data model, which is captured in DATA-NEEDS.md. |

---

## 4. Business rules embedded in the legacy code, in plain language

These are the real deliverable of this report. Each is stated without reference
to SQL or storage.

### 4.1 Workshop rules

1. A workshop is a **single-day** event: one date, one location, one capacity,
   and **one unified registration fee for everybody**. There is deliberately no
   per-person amount. (Recorded as an owner decision dated 2026-07-09.)
2. A workshop holds two distinct kinds of people: **participants** (attendees)
   and **team members** (organisers, who additionally carry a role). They are
   separate lists with separate forms, but they are counted together for
   attendance percentage, "people" count, and unpaid count.
3. Payment is **tri-state**: paid / unpaid / unspecified. Unspecified means
   nobody has decided yet and is **never** counted as money owed. Only explicit
   `unpaid` contributes to the unpaid count.
4. Attendance is **binary**: present or absent. (The new app currently models
   four states — see §5.)
5. A workshop may have **sections**. Sections are optional; a person may belong
   to no section, and "no section" is a real, storable state, not a missing
   value.
6. **Deleting a section does not delete its people.** Participants and team
   members survive and simply lose the assignment.
7. Archiving a workshop is **soft and reversible**. Archived workshops stay
   visible in the list with a chip; they are hidden only if the admin opts into
   the "archived only" filter. Restoring happens through the form's status
   switch.
8. Removing a participant or a team member is a **permanent hard delete**, and
   the confirmation names the person. This differs from detachment members,
   which deactivate.
9. A workshop's list status is **derived from its date**, not stored: today /
   upcoming / finished, by calendar date comparison.
10. Cross-workshop safety: every person mutation is filtered by workshop id as
    well as row id, so an id from another workshop can never mutate across
    workshops.
11. Sorting offers five orders (newest, oldest, name A–Z, highest attendance,
    most people); every sort has a deterministic tie-breaker.
12. Advanced filters are **all off by default**, so the list behaves plainly
    until the admin opts in.

### 4.2 Detachment rules

1. A detachment has a name, a location, and an active flag. Archiving is soft
   (clears the active flag).
2. A detachment member has a name, a **specialty**, a **phone**, a role, and an
   active flag. Members are **deactivated, never deleted** — the opposite of
   workshop people.
3. Member search matches across **name, specialty, and phone** simultaneously,
   and can be combined with a role filter.
4. Members with the **leader** role sort to the top of the list, then by recency.
5. Counts shown on a detachment (members, leaders) count **active members only**.

### 4.3 Shift and attendance rules — the valuable part

1. A shift is a **weekly template**: it belongs to a detachment, falls on one
   weekday, has a name, a **shift leader** (who must be a member of that
   detachment), and **mandatory** start and end times in `HH:mm`.
2. The week starts on **Saturday**.
3. A shift may optionally carry an inclusive **start and end date**, making it a
   temporary schedule. Both bounds are set together or neither is — one alone is
   rejected, and an end before the start is rejected.
4. From the template the system **auto-generates dated occurrences** for the
   whole current calendar month, *including days already past*. Generation is
   idempotent and re-runs whenever a shift screen opens, so a shift that lives
   into a new month gets that month's dates automatically.
5. Cancelling a date is a **tombstone, not a deletion**. The occurrence row
   stays, flagged cancelled, so monthly auto-generation never resurrects a date
   the admin removed. Re-adding that date **restores the tombstone** rather than
   creating a duplicate.
6. A manually added date **must fall on the shift's weekday**, and must lie
   inside the shift's date range if it has one.
7. A shift's **weekday can never be edited**. The month's dated occurrences and
   their attendance history hang off it. To move a shift to another day you
   delete and recreate it. Name, leader, and times remain editable.
8. There are **two different member lists per shift**, and conflating them is the
   classic bug this design avoids:
   - the **roster** — who is assigned to this weekly shift in general;
   - the **per-date attendance** — who actually showed up on one specific date.
9. The first time a date is opened, attendance rows are **seeded from the roster
   as absent**. Nothing is ever auto-marked present; the admin flips each person
   who actually came.
10. **The attendance lock (D-16):** once a date's shift end time plus a **one
    hour** grace period has passed, that date's attendance becomes read-only.
11. A shift crossing midnight is handled: if the end time is not after the start
    time, the end is taken as the next day.
12. If the stored times cannot be parsed, the lock reports *not configured* and
    the date simply stays editable — it never throws. Reaching that state means
    the data is corrupt, not that the admin skipped a field.
13. **The edit permission overrides the lock** (owner decision, 2026-07-10). A
    session holding the record-attendance capability may always toggle
    attendance, even after auto-lock. Only a session *without* that capability is
    frozen. This produces exactly three interaction states: editable /
    locked-read-only / unpermitted-read-only.
14. Deleting a shift removes its occurrences, their attendance, and its roster,
    all in one transaction.

### 4.4 Access rules (superseded, but the shape is instructive)

1. Two logged-in admin kinds, Main and Local, plus **temporary accounts** bound
   to exactly one record.
2. A temporary account's entire route surface is **its own record's subtree**,
   filtered per granted capability. Everything else bounces back to that record.
3. Editing or archiving a record itself is **never** delegated to a temporary
   account — admin only.
4. Route access is resolved in **one function**, so the router guard and the
   in-screen controls can never disagree.
5. A route may open on **either of two** capabilities, with each control inside
   gated individually (this is how the shift screens work).

Rules 2–5 are directly reusable for the new capability model and are carried
into CAPABILITIES.md.

---

## 5. Status and enum values found in legacy — FOR YOUR CONFIRMATION

Per Domain Note 4 I am **not** adopting any of these. Listing them so you can
confirm, amend, or replace.

**Legacy detachment status:** there is no status enum. Only a boolean
active/inactive, surfaced as active vs archived.

**Legacy workshop status:** likewise no stored status enum. Only a boolean
active/inactive, **plus** a derived date bucket: today / upcoming / finished.

**Legacy member role** (7 values, Arabic labels live in
`core/constants/app_roles.dart`): leader, organization, administrative,
followUp, support, trainer, member.

**Legacy attendance status:** present, absent. Two values only.

**Legacy payment status:** paid, unpaid, and null meaning unspecified.

**Legacy weekday:** saturday … friday, Saturday-first.

**Values the NEW app already invented, which are NOT from legacy and need your
ruling:**

| Location | Value set | Note |
|---|---|---|
| `detachment_models.dart` | `DetachmentStatus { active, archived }` | Invented. Matches the legacy boolean in spirit. |
| `workshop_models.dart` | `WorkshopStatus { scheduled, ongoing, done }` | Invented. Legacy *derives* status from the date and never stores it. Conflicts with legacy rule 4.1.9. |
| `team_models.dart` | `AttendanceState { present, late, absent, notInvited }` | Invented. Legacy has two values. Four states change the attendance UI and every percentage calculation. |
| `team_models.dart` | `TeamRole { lead, medic, trainee, volunteer }` | Invented. Legacy has seven different roles. |
| `inventory_models.dart` | `StockLevel { ok, low, empty }` | New module, no legacy source. |

Screens depending on these are deferred per your instruction.

---

## 6. What does NOT carry over, and why

**Single-tenant / center assumptions.** Every legacy table carries a `centerId`,
and the whole access model splits "main" routes from "local" routes by center.
The new app has no center concept. Every `centerId` reference is dropped; where
legacy used it for scoping, the new app scopes by detachment.

**Old permission model.** `AdminRole` (2 values) and `AppPermission` (5 coarse
keys) are cancelled outright by your capability-key model. What survives is the
*shape*: a runtime grant set, a single `can()` entry point, one resolver
consulted by both the router and the controls, and per-record scoping.

**Old state management and storage.** Drift `customSelect` streams,
`AppDatabase`, `Value`/companions, the Supabase client, and the sync outbox
(`pendingSync` flags, deletion queue, `findEntityCenterId`) all go. The new app
uses Riverpod over repository interfaces returning `Result<T>` against mock
implementations. Note that `pendingSync` was **surfaced in the UI** as a filter
and a badge; that is an offline-sync affordance the new app will need to
re-decide (see DETACHMENT-SCOPING.md §6).

**Old theme.** Every legacy screen builds its own colours, spacing, cards, chips,
and state widgets inline, and repeats near-identical private widgets
(`_StateCard`, `_SearchField`, `_ViewModeSelector`, `_StatusChip`) across five or
six files. None of it carries over. The new app has `core/theme` and
`core/widgets` for exactly this.

**Inline Arabic strings.** Legacy hardcodes Arabic in widgets and in enum label
extensions. All of it must move into `lib/l10n/strings.dart`.

**Export layer.** PDF and XLSX generation requires packages not on the allowlist
and is not on any near-term page. Dropped, re-proposable later.

**Error handling.** Legacy throws `ArgumentError` and `StateError` from its write
functions for validation failures. The new app returns `Failure`. Every extracted
validation rule must be converted from a throw to a typed failure.

---

## 7. Detachments — what carries over vs. what is rebuilt

**Carried over (rules and data model):** everything in §4.2 and §4.3 — the
member model with specialty and phone, deactivate-not-delete, multi-field search,
leaders-first ordering, active-only counts, and the entire shift rule set
including the weekly-template/occurrence split, tombstones, roster-vs-attendance
separation, the one-hour attendance lock, and permission-overrides-lock.

**Rebuilt (all UI):** list, detail shell and its tab set, member detail, create
flows, stats, and both shift screens — to the new theme, with all five states,
localized, capability-guarded, and Riverpod-over-mock.

**Genuinely new, no legacy source:**
- **Per-detachment inventory** — items, stock levels, minimums, expiry,
  movements. Entirely new.
- **Per-detachment shift scheduling UI** — the rules exist, the interaction
  design does not and is to be redesigned per Domain Note 5.

**Reason for the split:** the legacy detachment *rules* were argued out with the
owner and carry dated decisions in their comments; that reasoning is expensive to
recreate and cheap to keep. The legacy detachment *screens* are 6,700 lines of
untokenised, unlocalised, single-tenant UI with no loading/empty/offline
discipline — cheaper to rebuild than to retrofit.

---

## 8. Honest note on the "PORT AS-IS" column

Only two files qualify: `attendance_lock.dart` and the pure-date half of
`shift_weekdays.dart`. Everything else in a 19,650-line legacy surface needs at
minimum a theme swap, localization, capability guards, five states, and a
Riverpod/mock rewrite — which is what your brief mandates for every ported file.

So for workshops, "port faithfully" in practice means: **the flows, screens,
field-level behaviour, and the twelve rules in §4.1 are preserved exactly; the
code is not.** I want that stated plainly rather than discovered mid-port.

---

## 9. Stop point

Nothing has been ported. Awaiting your approval, plus rulings on open decisions
#3, #4, #7, and #8.
