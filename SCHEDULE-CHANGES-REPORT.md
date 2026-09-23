# SCHEDULE + WORKSHOPS — REPORT FOR YOUR RULING

Companion to your 6-part request of 2026-09-02 (shift cards, swipe nav, day-based
repetition, page cleanup, workshop analysis, token safety).

**Why this is a report and not a diff:** part 3 (repetition) changes the shape of
the schedule model — it retires `ShiftTemplate.weekday` and the whole weekly
"apply repeats" machinery. Your standing rule is that model-shaping changes get a
report first ([[report-before-implementing]]), and the scheduling screen is the
one place you have said a technically-correct build can still be the wrong answer
([[mtm-scheduling-must-be-easy]]). Parts 1, 2 and 4 also each remove or relocate
functionality, so they get argued here too. Part 5 is analysis-only by your
instruction and is finished below — §5.

Nothing in the app has been changed. I need your ruling on §6 before writing code.

---

## 0. What the schedule screen is today

`flutter_app/lib/features/detachment/presentation/tabs/detachment_shifts_tab.dart`
(1147 lines). One detachment's schedule, **a week at a time**:

- **Week header** — coverage / shift count / gaps, `‹ ›` chevrons to step weeks,
  a "this week" reset that only shows when you are off the current week.
- **Day strip** — 7 columns (Sat–Fri), each with a shift count and a warn/ok dot.
- **Bulk actions row** (managers only) — three buttons:
  `[ Copy last week ]  [ Apply the repeats ]  [ ☰ templates list ]`
- **Day header** — weekday · date, and an `+ Add shift` pill.
- **Shift cards** — one `_ShiftCard` per shift on the selected day. Each card
  today carries, inline: centre name, time range, a coverage bar + status chip,
  the attendees as a `Wrap` of tiny 12px `initials + name` pills, then a button
  row: `[ Assign volunteer ]  [ Quick fill ]*  [✎]  [🗑]` (`*` only when short).

Repetition today: `ShiftTemplate { detachmentId, centerName, weekday (1–7),
start, end, needed, active }`. Turning on "repeat every week" in the shift editor
files one template for that weekday; "Apply the repeats" materialises every
active template into the shown week; "Copy last week" clones the previous week's
shifts (without their people). Templates are listed and stopped in a sheet.

Detail-shell navigation: `DetachmentDetailShell` renders `AnimatedTabBar` +
`TabCrossFade(child)`. The 4 tabs (team / shifts / storage / stats) are
independent `GoRoute`s under a `ShellRoute`; the tab bar calls `context.go`.
There is **no `PageView` anywhere in the app** — swipe-between-pages would be a
new pattern.

---

## 1. Shift schedule cards + member-name display

**What you asked:** each shift a separate card; tapping a card opens its
shift-management interface; manage each shift individually; clearer member names.

**Reading of it:** the cards already exist and are already per-shift. What is new
is (a) the card stops being a control panel and becomes a *summary you tap*, and
(b) every management action for that one shift moves into a surface opened from
the card. This is also most of part 4 — the four inline buttons per card leave
the list.

### Assumptions

| # | Assumption | Recommendation |
|---|---|---|
| 1A | The "shift-management interface" is a **bottom sheet** (`showAppSheet`), like every other action surface in the app (assign, attendance, editor). Not a new full-screen route. | **Sheet.** A route buys nothing here and costs a back-stack entry. |
| 1B | The card shows: centre name, time range, coverage bar + status chip, and an attendee summary. **No buttons.** The whole card is the tap target → opens the sheet. | Yes. |
| 1C | The management sheet holds, each capability-gated exactly as now: *Assign volunteer*, *Quick fill* (when short), *Edit shift*, *Delete shift*, and the attendee list where tapping a name opens the existing attendance sheet. Nothing is lost — it is relocated. | Yes. |
| 1D | "Clearer member names" = replace the pill `Wrap` with a **vertical list of attendee rows** — initials avatar + full name + attendance status chip — the same row the Team and Workshop-members tabs already use. On the card, cap at 3 rows + "+N more" (opens the sheet); the sheet shows all. | Yes. The 12px pills are the least readable text on the screen and don't survive long Arabic names. |
| 1E | `running now` cards keep their primary-colour border. | Yes, unchanged. |

### What I need from you on part 1
- **Q1** — sheet, or full page? (I recommend sheet.)
- **Q2** — attendee rows on the card capped at 3 before "+N more", or show all?

---

## 2. Swipe navigation between pages

**What you asked:** keep the button (tab) navigation; add left/right swipe as a
second way to move between the related pages.

### Assumptions

| # | Assumption | Recommendation |
|---|---|---|
| 2A | "The related pages" = the **detachment detail tabs** (team ↔ shifts ↔ storage ↔ stats), and — for parity, since the shells are deliberately identical — the **workshop tabs** (team ↔ members ↔ stats). Not the week chevrons, not the bottom nav. | Confirm this scope. |
| 2B | Implementation = wrap the shell body in a horizontal-drag detector that, on a completed swipe past a distance+velocity threshold, calls `context.go` to the adjacent tab route. Reuses the router and the existing `TabCrossFade`. **No `PageView`, no route restructuring.** | Recommended. A real `PageView` fights `ShellRoute`, breaks per-tab deep links, and would force all tabs to build at once. |
| 2C | Direction follows reading order in RTL: swipe from the right edge leftwards → next tab (the tab visually to the left). Mirrors automatically with `Directionality`. | Yes. |
| 2D | The gesture yields to any inner horizontal consumer and never blocks vertical scroll. Today's tab bodies have no horizontal scrollers, so risk is low, but the threshold protects the day-strip taps. | Yes. |
| 2E | `MediaQuery.disableAnimations` — swipe still switches tabs; the cross-fade already self-disables. | Yes. |

### What I need from you on part 2
- **Q3** — is 2A the right set of "related pages" (detachment tabs + workshop tabs)?
- **Q4** — gesture-over-`context.go` (recommended) vs. converting the shells to `PageView`?

---

## 3. Day-based repetition  *(the model-shaping part)*

**What you asked:** repetition is currently week-based; make it day-based. A
detachment usually runs only 10–15 days, so let the user pick exactly which
individual days a shift repeats on, and add/remove any of those days.

### The core choice

| Option | Shape | Verdict |
|---|---|---|
| **3A — materialise on save, no template record** | The editor's repeat *switch* becomes a **day picker**. The user taps the specific days they want the shift on; on save the repository creates one independent `Shift` per chosen day (same centre / time / needed, no attendees). No `ShiftTemplate`, no "apply the repeats". Each shift is fully independent afterwards — which is exactly "manage each shift individually" from part 1. | **Recommended.** Matches a 10–15-day detachment: there is no "standing schedule" to keep as a rule, so keeping one is pure overhead. |
| 3B — keep a repeat record, change `weekday`→`List<DateTime>` | `ShiftTemplate` stays but stores explicit dates instead of a weekday; "apply" still exists. | Rejected. Keeps the machinery whose only justification (a schedule that outlives the week) does not apply here. |

### Sub-decisions under 3A

| # | Question | Recommendation |
|---|---|---|
| 3C | **What days does the picker offer?** `Detachment` has no start/end date, so there is no natural range. Default: a rolling window of the next **21 days** starting from the shift's own date, shown as a scrollable day grid; the chosen day is pre-selected and locked. | Rolling 21-day grid. (Alternative, if you want it bounded: add `startsOn` / `endsOn` to `Detachment` — a second, separate model change. Say the word and it gets its own section.) |
| 3D | **Fate of the weekly machinery.** 3A deletes: `ShiftTemplate` model, `shiftTemplatesProvider`, `templates()`, `stopTemplate()`, `applyTemplates()`, the `_RepeatSwitch`, `_TemplatesBody`, `_TemplateRow`, and the strings `repeatWeekly*`, `applyTemplates*`, `templates*`. | Delete them. They have no meaning without weekly repeats. |
| 3E | **`copyWeek` / "Copy last week".** Independent of templates — it just clones a week's shifts. Keep it? With the day picker at creation it is less needed, but it is cheap and still answers "same as the last few days". | Keep the capability; see part 4 for where the button goes. |
| 3F | **`Shift.templateId`.** Becomes always-null under 3A. Keep the nullable field for one release (avoids churning `fromJson` / `toJson` / seed data / tests) and drop it later, or remove now. | Keep nullable for now, marked deprecated. |
| 3G | **Editing repetition on an existing shift.** Show the same day picker in edit mode: ticking a new day creates that day's shift; unticking a day deletes that day's shift **only if it has no attendees**, otherwise it is kept and the picker shows it as locked with a note. | Yes — this is what "add/remove any desired repetition days" means after creation. |

### Blast radius (for your awareness, not your ruling)
- `test/features/shift/schedule_test.dart` — the `copyWeek` / `applyTemplates` /
  `repeatWeekly` cases change or are removed.
- `test/features/shift/shift_save_persistence_test.dart` — the fake repo's
  `repeatWeekly` parameter is replaced by `repeatOn: List<DateTime>`.
- `ShiftRepository.create` signature: `bool repeatWeekly` → `List<DateTime> repeatOn = const []`.

### What I need from you on part 3
- **Q5** — 3A (materialise, no templates) — yes?
- **Q6** — 3C — rolling 21-day picker, or do you want `Detachment` to gain a date range?
- **Q7** — 3D — delete the weekly-template code and strings outright?
- **Q8** — 3E — keep "Copy last week"?
- **Q9** — 3G — edit-mode picker with the "no-attendee" delete guard — yes?

---

## 4. Page cleanup

Candidates on the shifts tab and what I would do with each:

| Element | Action | Reason |
|---|---|---|
| Bulk row — **"Apply the repeats"** | **Remove** | Nothing to apply once repetition is day-based (part 3). |
| Bulk row — **templates list (`☰`)** button + its sheet | **Remove** | No templates. |
| Bulk row — **"Copy last week"** | **Keep, relocate** — fold into the day header as one secondary action next to `+ Add shift`, since the 3-button row is otherwise gone. Drop it instead if you want the row gone entirely (Q8). | Still useful, but does not deserve its own row. |
| `_ShiftCard` inline **Assign / Quick fill / ✎ / 🗑** | **Move** into the management sheet (part 1). | The card becomes a summary. |
| Week header **`‹ ›` chevrons** | **Keep** | Swipe covers tabs, not weeks; this is the only way to change week. |
| Week header **"this week"** reset | **Keep** | Only shows when off-week; one tap back. |

Net effect: the tab loses a 3-button row and 4 buttons per card; it gains one
day-picker (in the editor) and one management sheet. That is a strict reduction
in on-screen controls, which is the intent.

### What I need from you on part 4
- **Q10** — anything in the "Keep" rows you actually want removed?
- (Q8 from part 3 also lives here — the fate of "Copy last week".)

---

## 5. Workshops — analysis  *(done; no code, per your instruction)*

The workshop feature (`lib/features/workshop/…`) is today **read + record-attendance
only**. Every action that changes *who is involved* is missing. Concretely:

1. **No way to add a participant.** `WorkshopRepository` exposes `participants()`
   and `setParticipantAttendance()` — nothing else. The Members tab can filter
   (all / members / guests) and set attendance, but cannot register anyone.
   `Workshop.registered` and `Workshop.guests` are seed-only integers that
   nothing ever increments (`create` hard-codes them to 0). **This is the single
   biggest gap.**
2. **No remove / unregister participant.**
3. **Organising team is read-only.** `workshop_team_tab.dart` carries an explicit
   `ASSUMPTION: read-only` comment — no repo method touches `organizingTeam`. No
   add/remove organiser, no role edit, no attendance sheet for organisers, all of
   which the detachment Team tab has.
4. **No delete or archive workshop.** `create` + `update` only. The list page has
   no removal path.
5. **No status transition.** `WorkshopStatus { scheduled, ongoing, done }` is
   fixed at `scheduled` on creation and only changeable by shipping a whole
   `update(Workshop)`. No "start" / "mark done" action.
6. **No payment recording** — no model, field, or UI anywhere.
7. **No sections** — no model or UI.
8. **Capacity is never enforced** — `isFull` is computed and unused, because there
   is no registration flow to gate.
9. **Stats tab** works but rests on two unconfirmed assumptions (a late arrival is
   not counted present; the tab is not capability-gated).

**Dead capability keys** — defined in `capability.dart`, wired to nothing:
`workshop.people.manage`, `workshop.archive`, `workshop.payment.record`,
`workshop.section.manage`. The first would gate items 1–3 above; the others need
their features (or your ruling that they are not coming).

When you want this built, the minimum for day-to-day use is items **1, 2, 3, 5**
(add/remove participant, add/remove organiser, status transition). That is its
own report — it adds repository methods and touches `workshop.people.manage`.

---

## 6. YOUR DECISION SHEET

Answer inline; I implement 1 → 4 in order on your answers, then stop.

**Part 1 — shift cards**
- Q1: management surface — **sheet** / page?
- Q2: attendee rows on the card — **cap at 3 + "+N more"** / show all?

**Part 2 — swipe nav**
- Q3: "related pages" = **detachment tabs + workshop tabs** — correct?
- Q4: **gesture + `context.go`** / convert shells to `PageView`?

**Part 3 — day-based repetition**
- Q5: **Option 3A** (materialise on save, no template record) — yes?
- Q6: day picker = **rolling 21 days** / add a date range to `Detachment`?
- Q7: **delete** the weekly-template model, providers, sheet and strings — yes?
- Q8: **keep "Copy last week"** (relocated) / remove it?
- Q9: edit-mode day picker with **"only delete a day with no attendees"** guard — yes?

**Part 4 — cleanup**
- Q10: any "Keep" item you want removed after all?

**Part 6 — token safety**
- Acknowledged. The budget for this work is large; there is no risk on this
  report. Once implementation starts I will checkpoint after each numbered part
  and, if the budget nears ~5%, stop at the last completed part and write the
  remaining steps here.

---

## 7. Stop point

No code until Q1–Q10 are answered. Part 5 needs nothing from you — it is the
finished analysis. If you only want to rule on part 3 now and let 1/2/4 run on my
recommendations, say so and I will treat the "Recommendation" column as approved
for those.
