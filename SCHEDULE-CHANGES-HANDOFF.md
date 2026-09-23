# SCHEDULE CHANGES — IMPLEMENTATION HANDOFF

Continuation doc for the scheduling rework. Read in this order to resume:

1. `CLAUDE.md`
2. this file
3. `SCHEDULE-CHANGES-REPORT.md` (the analysis the rulings below override in places)
4. the current branch diff

Branch: `main` (working tree only — nothing committed yet for this work).

---

## 1. What was requested

The user's 2026-09-02 follow-up to `SCHEDULE-CHANGES-REPORT.md`. The report asked
ten questions (Q1–Q10); the user answered them as rulings and told me to use my
own judgement for the rest. The rulings:

- **Main flow:** Select Day → see shift **cards** (clean summaries, not control
  panels) → tap a card → a **shift-management surface** that exposes *everything*
  for that one shift: both existing assignment methods, quick-fill, the full
  attendee list, attendance management, check-in / check-out, edit shift, delete
  shift. Reuse the existing logic; do not reimplement it.
- **Member names:** readable rows with full names + status, not the 12px pills.
  On the card show the first few + "+N more"; the full list lives in the
  management surface.
- **Templates — CHANGED FROM THE REPORT.** The report's Q5/Q7 recommendation to
  delete `ShiftTemplate` is **rejected**. Keep templates. Redesign the
  repetition model so the user picks the *actual days* they want (not a weekly
  rule), works for a 10–15 day detachment, stays reusable/manageable, and
  materialises/updates shifts *without* a separate "Apply repeats" step.
  Constraints: no duplicate generated shifts; a shift with assigned members is
  never silently deleted by a template change; keep template↔shift links where
  useful; evolve the model, don't build a parallel one.
- **Navigation:** keep the tab buttons; **add** left/right swipe as a second way
  to move between detachment-detail tabs and workshop-detail tabs. Prefer a
  gesture + `context.go`, not `PageView`. Respect RTL.
- **Cleanup:** after the card→management flow works, pull the redundant inline
  actions off the cards; keep week navigation; re-evaluate "Copy last week" and
  the template controls; don't delete useful capability just to reduce buttons.
- **Workshops:** analysis-only (report §5 stands). Swipe nav for workshop tabs is
  in scope because it's navigation work; nothing else workshop is.
- **Discipline:** implement in parts, validate after each; update/extend tests;
  no unrelated refactors; run formatter/analyzer/tests; checkpoint + handoff at
  ~5% context left.

---

## 2. Design decisions (these must not be silently re-decided)

### D1 — `ShiftTemplate.weekday` → `ShiftTemplate.dates: List<DateTime>`

The template stops meaning "every Tuesday" and starts meaning **"this
centre / time / headcount, on these specific day-dates."** One field changes:
`int weekday` → `List<DateTime> dates` (day-only via `dateOnly`, sorted, deduped).
Everything else on the model stays (`id`, `detachmentId`, `centerName`,
`startMinutes`, `endMinutes`, `needed`, `active`, `period` getter).

Rationale: explicit dates is the smallest model that delivers "pick the actual
days you want" and is natural for a short detachment — the `dates` list simply
holds those 10–15 days. A hybrid (weekday + range) keeps two repetition
languages and a "which wins" question; rejected.

New getters: `firstDate`, `lastDate`, `dayCount`.

### D2 — The template owns its shifts; save/edit *reconciles*. No "Apply" button.

There is no bulk "apply the repeats to this week" anymore. Instead:

- **Create** with repeat days → the repo files a `ShiftTemplate` whose `dates`
  are `{anchorDate} ∪ pickedDates`, then materialises one `Shift` per date
  (each tagged `templateId`), skipping any date that already has a shift at the
  same start time (dedupe).
- **Edit** a shift that has a `templateId`, changing its repeat days →
  `updateRepeat(shiftId, dates)` reconciles the template's shift set:
  - date in `dates` with no shift for this template → create it;
  - shift of this template whose date is **not** in `dates` → delete it **only
    if it has no attendees**. If it has attendees it is kept and its date is
    forced back into `dates` (the model never diverges from reality);
  - shift whose date is still in `dates` → untouched (still individually
    managed — editing one occurrence does **not** edit the template; the
    existing `Shift.templateId` doc comment already states this rule).
- `updateRepeat` also writes the anchor shift's current centre/time/needed onto
  the template record, so **newly** materialised siblings match what the user is
  looking at. Existing siblings are frozen (not retro-edited). Documented
  trade-off: the template mirrors the last edit; past occurrences don't move.
- If repeat days collapse to just the anchor date, the template is deactivated
  (`active = false`); the anchor keeps its `templateId` for history.

`stopTemplate` keeps its current contract: deactivate, leave every shift it
already produced in place (a past week must keep reading the way it was worked).

### D3 — `Shift.templateId` stays (nullable, not deprecated)

It is a live link now: reconcile finds a template's shifts through it, the card
shows the repeat glyph from it, and edit-mode loads the template's date set
through it.

### D4 — Repeat-days picker range = rolling 21 days from the shift's date

`Detachment` has no start/end date, so there is no natural bound. The picker
shows a 21-day grid starting at the shift's own date; the anchor day is
pre-selected and locked. (If a bounded range is wanted later, add
`startsOn`/`endsOn` to `Detachment` — a separate model change, not done here.)

### D5 — Management surface = bottom sheet (`showAppSheet`), not a route

Consistent with every other action surface in the app (assign, attendance,
editor). A route costs a back-stack entry and buys nothing.

### D6 — Card attendee summary = 3 rows + "+N more"

Readable rows (avatar + full name + status chip), same shape as the Team tab's
`_MemberCard`. Cap at 3 on the card; the management sheet shows all. Running-now
cards keep the primary-colour border.

### D7 — Swipe direction = spatial, mirrored by `Directionality`

A horizontal fling switches to the tab **in the direction of the fling**:
leftward fling → the tab visually to the left, rightward → the tab visually to
the right. Because `AnimatedTabBar` lays tabs out with `start`-relative
positioning, "the tab to the left" is `index + 1` in RTL and `index - 1` in LTR.
Threshold: primary velocity magnitude > 240 px/s (a fling, not a slow drag);
the detector uses `HorizontalDragGestureRecognizer` behind `translucent` hit
testing so it never blocks vertical scrolls or the day-strip taps, and it yields
to any inner horizontal consumer. `context.go` to the adjacent tab route; the
existing `TabCrossFade` plays the visual. No `PageView`, no route restructuring.
`MediaQuery.disableAnimations` is irrelevant — the tab still switches, the fade
self-disables.

### D8 — Bulk actions row: 3 buttons → 2

`[ انسخ الأسبوع السابق ]  [ ☰ القوالب ]`. "طبّق الشفتات المتكررة" (Apply) is
removed — its job is now automatic (D2). "Copy last week" is kept (still the
fastest answer to "same as last few days") and stays in a compact managers-only
row rather than getting its own real estate. The templates list stays reachable
from the `☰` button because it is schedule-scoped, not shift-scoped.

### D9 — Strings

Old string keys are **kept** even when now unused (`repeatWeekly*`,
`applyTemplates*`) per the "don't delete" ruling. New keys added for the picker,
the management sheet, and the template date-span row.

---

## 3. Files changed

### Domain / data
- `lib/features/shift/domain/shift_models.dart`
  - `ShiftTemplate.weekday: int` → `dates: List<DateTime>` (normalised: day-only,
    sorted, deduped via `dateOnly`); constructor is no longer `const`. Added
    `dayCount`, `firstDate`, `lastDate`. `copyWith` takes `Iterable<DateTime>?
    dates`. `fromJson`/`toJson` use a `dates` array of ISO strings (was
    `weekday` int) — **JSON shape changed, see §7**.
  - `Shift.copyWith` gained an optional `String? templateId` (was hard-locked to
    `this.templateId`); used to stamp a template link onto an existing shift.
- `lib/features/shift/domain/shift_repository.dart`
  - `create(..., bool repeatWeekly)` → `create(..., List<DateTime> repeatOn)`.
  - **new** `Future<Result<ShiftTemplate>> updateRepeat(String shiftId,
    List<DateTime> dates)`.
  - **new** `Future<Result<List<Shift>>> shiftsForTemplate(String templateId)`.
  - **removed** `applyTemplates({detachmentId, weekStart})`.
  - `stopTemplate` doc reworded ("weekly" → "repeat"); behaviour unchanged.
- `lib/features/shift/data/mock_shift_repository.dart`
  - seed builds each template's `dates` from its weekday across the two seeded
    weeks (`[lastDay, thisDay]`).
  - `create`: `repeatDays = {anchor} ∪ repeatOn`; a template is filed only when
    `repeatDays.length > 1`; one shift materialised per date, `_exists`-deduped.
  - `updateRepeat`: reconcile (materialise missing / delete surplus-and-empty /
    fold staffed days back / mirror anchor spec onto template / deactivate when
    down to one day). `shiftsForTemplate` added.
  - `templates()` now sorts by `firstDate` then start time.
  - `copyWeek` no longer copies `templateId` onto the clone (an independent
    shift must not claim membership of a template whose date set omits it).
  - `applyTemplates` removed; `_dayOfWeek` kept (still used by the seed).
- `lib/features/shift/data/shift_providers.dart` — **new**
  `templateOccurrencesProvider` (family on templateId).

### Presentation
- `lib/features/shift/presentation/shift_edit_sheet.dart` — `_RepeatSwitch` (on/off)
  replaced by `_RepeatDays` + `_DayPill`: a 21-day rolling grid from the shift's
  date, shown in **both** new and edit mode. Anchor day and staffed days locked.
  `initState` async-loads the template's day set (`_loadRepeatDays`); Save is
  disabled while that load is in flight so a fast save cannot reconcile against
  just the anchor. `_save` rewritten: new → `create(repeatOn:)`; edit that
  touches repetition → `update()` then `updateRepeat()`.
- `lib/features/shift/presentation/shift_manage_sheet.dart` — **new**.
  `showShiftManageSheet(...)` + `_ManageBody` (watches `shiftByIdProvider` to
  stay live), `_ActionButton`, a local `_CoverageBar`, and the **public**
  `AttendeeRow` widget (avatar + full name + status chip) reused by the card.
- `lib/features/detachment/presentation/tabs/detachment_shifts_tab.dart`
  - `_ShiftCard` is now a `ConsumerWidget` (was `ConsumerStatefulWidget`): a
    tappable summary, no inline buttons; shows ≤3 `AttendeeRow`s then
    "+N آخرون"; whole card opens `showShiftManageSheet`.
  - deleted `_ShiftCardState`, `_AttendeeChip`, `_Icon`, and the card's
    `_quickFill` / `_edit` / `_confirmDelete` (all moved into the manage sheet).
  - `_BulkActions`: three buttons → two (`Copy last week`, `Templates`);
    `_applyTemplates` removed.
  - `_TemplateRow`: weekday line replaced by centre name + `_dateSpan(template)`
    ("٥ أيام · <first> – <last>").
  - class-level doc comment updated.
  - imports: `shift_assign_sheet.dart` and `team_models.dart` dropped;
    `shift_manage_sheet.dart` added.
- `lib/core/widgets/swipe_tabs.dart` — **new** `SwipeTabs` (fling → `onSwitch`).
- `lib/features/detachment/presentation/detachment_detail_shell.dart` — body
  wrapped in `SwipeTabs` (4 tabs).
- `lib/features/workshop/presentation/workshop_detail_shell.dart` — same (3 tabs).
- `lib/l10n/strings.dart` — added `repeatOnDays`, `repeatOnDaysHelp`, `daysUnit`,
  `manageShiftTitle`, `shiftMembersSection`, `moreMembers`, `templatesButton`,
  `templateDays`. Old keys (`repeatWeekly*`, `applyTemplates*`, `templatesTitle`,
  `templatesSub`, `templateStop*`) **kept** — some now only referenced by the
  templates sheet, `applyTemplates*` now unused but retained per ruling.

### Tests
- `test/features/shift/schedule_test.dart` — dropped the `applyTemplates` case;
  "a repeating shift files a template" rewritten around `repeatOn:` +
  `shiftsForTemplate`.
- `test/features/shift/shift_save_persistence_test.dart` —
  `_FailingCreateRepository.create` signature (`repeatWeekly` → `repeatOn`).
- `test/features/shift/template_repeat_test.dart` — **new**, 8 cases: materialise,
  single-day-no-template, dedupe, add/remove day, no-attendee delete guard,
  collapse-deactivates, unrepeated→repeat.
- `test/features/shift/shift_manage_sheet_test.dart` — **new**, 3 cases: full
  readable rows + all actions, capability gating, row → attendance sheet.
- `test/core/swipe_tabs_test.dart` — **new**, 5 cases: RTL fling both ways, LTR
  mirror, slow drag ignored, edge clamp, vertical scroll unaffected.

---

## 4. Status — ALL PARTS COMPLETE

- [x] Part A — model + repository
- [x] Part B — editor day picker
- [x] Part C — card summary + management sheet
- [x] Part D — bulk row + templates row cleanup
- [x] Part E — swipe nav (both shells)
- [x] Part F — strings
- [x] Part G — tests

`flutter analyze`: **clean** (whole project).
`flutter test`: **111 pass, 0 fail** (was 108 at start; +8 new − 5 removed/merged).
`dart format`: applied to all touched files.
`graphify update .`: ran.

## 5. Known issues / open points

- **`updateRepeat` mirrors the anchor's spec onto the template every time it
  runs**, including when the user only changed the day set. Existing sibling
  shifts are never retro-edited, so this only affects *future* materialised
  days. Intentional (decision D2) but worth knowing.
- The `_RepeatDays` grid is a flat 21-pill `Wrap` with no month affordance —
  fine for a 10–15 day detachment, would need grouping if the window grew.
- Templates sheet empty-state still uses `S.applyTemplatesEmpty` ("لا شفتات
  متكررة محفوظة بعد.") — reads fine, but the string name is now a misnomer.
- Workshop swipe nav is wired but there is no workshop-shell widget test (out of
  scope — workshops are analysis-only); `swipe_tabs_test.dart` covers the widget
  itself.
- No widget test drives the full `DetachmentShiftsTab` (needs capability-scope
  wiring); the card→sheet flow is covered at the sheet level instead.

## 6. If continuing / follow-ups

Nothing is required. Optional polish:
- Rename `S.applyTemplatesEmpty` usage or add a dedicated empty string.
- Consider a real-app run (`/run`) to eyeball the 21-pill grid and the swipe
  feel on device, and RTL of the manage sheet.
- If `Detachment` ever gains `startsOn`/`endsOn`, bound the `_RepeatDays` window
  to it instead of the rolling 21 days (decision D4).

## 7. Migration / data-model implications

- `ShiftTemplate` JSON changed: `"weekday": <int>` → `"dates": ["<iso>", ...]`.
  There is no persisted store in this frontend (mock repo seeds in memory), so
  no migration code is needed today. Any future real backend / cache
  deserialising old template JSON must map `weekday` → a `dates` list (e.g.
  project the weekday across the detachment's active range) before calling
  `ShiftTemplate.fromJson`, which now requires `dates`.
- `Shift` JSON is unchanged (`templateId` still optional).
- `ShiftRepository` is an abstract interface: any other implementer must add
  `updateRepeat` + `shiftsForTemplate`, change `create`'s last param, and drop
  `applyTemplates`. Only `MockShiftRepository` and the two test doubles exist.
