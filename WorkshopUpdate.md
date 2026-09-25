# Workshop → «الأعضاء والزوار» rework: architecture report (hand-off to Codex)

## 1. What Ahmed asked for (as understood)

Every workshop owns its own people. Nobody is shared between workshops, and nobody is picked from the team roster. Inside a workshop, the members tab (today «الأعضاء والضيوف») has **two parts**.

### A. أعضاء الفريق (team members)

1. **«إضافة عضو»** opens a **full page**. Its fields, in this order:
   1. **Name**, typed in by hand.
   2. **Role**, a choice of exactly five:

      | Arabic | English |
      |---|---|
      | قائد | leader |
      | مدرب | trainer |
      | دعم | support |
      | إدارة | management |
      | عضو | member |

   3. **Paid?**, a yes/no switch, so it is visible who has not paid the workshop cost.
   4. Save.
2. After saving, the list shows the **name and the role**.
3. **Paid** is binary:
   - **green** means he paid (دافع);
   - **red** means he did not (غير دافع).
4. **Attendance.** The existing logic stays as it is, and is **not rewritten**. The person sheet shows two choices:
   - **«سجّل الدخول»**: he came and logged in;
   - **«لن يحضر»**: not coming.

### B. المتطوعون والزوار (volunteers & visitors)

- These are **not** team members.
- Adding one needs only **name + paid yes/no**.
- The row shows the name, the green/red payment chip and the attendance chip.

Everything else is unchanged:
- the organisers tab «الفريق وأدواره»;
- the roster;
- shifts;
- the `AttendanceState` enum and its repository methods.

## 2. What exists today (verified in code)

All paths below are under `flutter_app/lib/features/workshop/`.

### Model: `domain/workshop_models.dart:115-201`

`WorkshopParticipant` has these fields:
- `kind`: `ParticipantKind { member, guest }`
- `memberId?`: a roster link
- `attendance`: `AttendanceState`
- `paymentStatus?`: `PaymentStatus { paid, unpaid }`, where `null` means "غير محدد"

There is **no role** field.

### Members tab: `presentation/tabs/workshop_members_tab.dart`

- The filter enum `_ParticipantFilter { all, members, guests }` is at `:27`.
- **Add member** (`_addMembers`, `:255`) opens the **roster multi-picker** `pickWorkshopMembers`.
- **Add guest** (`_addGuest`, `:283`) opens a sheet with a name field only (`askWorkshopGuestName`, `widgets/workshop_people.dart:402`).
- **Tapping a row** opens `_personSheet` (`:294`), which shows `WorkshopPersonActions` (`widgets/workshop_people.dart:494`). That sheet offers:
  - four attendance choices;
  - three payment choices, including "غير محدد";
  - remove.
- The row itself is `_ParticipantCard` (`:357`), built on `WorkshopPersonRow` (`workshop_people.dart:322`).

### Repository

- The interface is `domain/workshop_repository.dart`.
- The mock is `data/mock_workshop_repository.dart`:
  - `addGuestParticipant` is at `:585`;
  - `_writable` / `_writablePart` guard not-found and archived workshops;
  - the error codes in use are `validation`, `duplicate`, `workshop_full`, `archived` and `not_found`.

### Stats: `domain/workshop_stats.dart`

- Payment is counted in three buckets: `paid` / `unpaid` / `unspecified`.
- Organisers always land in `unspecified`.
- `unspecified` is also read in:
  - `presentation/tabs/workshop_stats_tab.dart:198,332,432,471`;
  - `data/workshop_stats_report.dart:59,121`;
  - `test/features/workshop/workshop_stats_test.dart`.

### Routes

`core/router/app_router.dart:570-633`:
- `':id/edit'` is a root-navigator page that sits **before** the detail `ShellRoute`.
- The tabs are `:id/team`, `:id/members` and `:id/stats`.

### Form-page pattern to copy

`presentation/workshop_edit_page.dart`:
- `Scaffold` + `Form` + `ListView`;
- `_Labelled` labels (`:340`) and `_StatusPill` pill choices (`:296`);
- `_seed(w)` pre-fills from an `AsyncResultView`;
- `_saving` flag, then `result.when(...)`, a snackbar, and `context.pop()`.

### Legacy medical_team check

The legacy app did the same thing:
- the team member form had typed name + role + attendance + payment;
- participants had name + payment;
- the list showed name, then the role underneath, then the chips.

This confirms the reading in §1.

## 3. Architecture decisions (final — Codex implements these, does not re-decide)

| # | Decision |
|---|---|
| A1 | **Team members are typed by name.** The Members tab stops using the roster picker. `pickWorkshopMembers` and `addMemberParticipants` stay in the code, because the organisers tab and tests still use them. |
| A2 | **Two parts inside the existing `members` tab.** No new tab. At the top is a single-select pair of `AppFilterChip`s: «أعضاء الفريق (N)» and «المتطوعون والزوار (N)». They replace `_ParticipantFilter`. |
| A3 | **Organisers tab untouched.** This applies to `workshop_team_tab.dart`, the organiser flows, and the organisers' four attendance choices. |
| A4 | **New enum `WorkshopRole { leader, trainer, support, management, member }`**, separate from the roster `TeamRole`. It is stored on the wire by `.name`. |
| A5 | **`WorkshopParticipant.role` is `WorkshopRole?`**. It is non-null for `kind == member` and null for `kind == guest`. `ParticipantKind.guest` now **means** volunteer/visitor; the enum value is not renamed. |
| A6 | **Payment is binary in the whole workshop register UI and stats.** `PaymentStatus?` keeps its type for wire compatibility, but `null` is shown and counted as **unpaid (red)**. New records are always written explicitly as `paid` or `unpaid`. The "غير محدد" choice disappears from the participant sheet. |
| A7 | **Attendance logic unchanged.** The participant sheet offers only `checkedIn` «سجّل الدخول» and `absent` «لن يحضر». A new person starts at `notCheckedIn`, shown as a muted «لم يسجل الدخول» chip. Old `checkedOut` rows still render «سجّل الخروج». The global `S.absent` is **not** changed; add a new `S.workshopNotComing`. |
| A8 | **Capacity rule unchanged.** Everyone on the register still takes a seat, and the add page shows `workshop_full` when it happens. Changing this is a separate decision. |
| A9 | **Duplicates are refused within the same part:** the same normalised name (`memberNameKey`) twice among team members, or twice among visitors. The error code is `duplicate`. |
| A10 | **Free workshops** (`registrationFee == 0`) hide all payment UI: the switch, the chips and the unpaid filter. Records are saved as `unpaid`, but nothing displays it. |
| A11 | **Editing.** A team-member row's sheet gets «تعديل», which opens the same page pre-filled (name, role, paid). Visitors are not editable: remove and re-add, as today. |

## 4. Implementation spec, step by step

### Step 1: Model (`domain/workshop_models.dart`)

1. Add the enum:
   ```dart
   enum WorkshopRole { leader, trainer, support, management, member }
   ```
   Add a label extension in the same file or in `workshop_stats.dart`, next to `PaymentStatusLabel`:
   - leader → `S.workshopRoleLeader`
   - trainer → `S.workshopRoleTrainer`
   - support → `S.workshopRoleSupport`
   - management → `S.workshopRoleManagement`
   - member → `S.workshopRoleMember`
2. Add `final WorkshopRole? role;` to `WorkshopParticipant`, as an optional constructor parameter.
3. Add `bool get isPaid => paymentStatus == PaymentStatus.paid;`. The UI reads only this.
4. `copyWith` gains `String? name`, `String? initials` and `WorkshopRole? role`.
5. `fromJson` parses `role` by name:
   - an unknown or missing role on a `member` line becomes `WorkshopRole.member`;
   - a `guest` line is always `null`.
6. `toJson` adds `if (role != null) 'role': role!.name`.
7. Update the doc comments on `ParticipantKind` and `memberId`:
   - a member is now a typed name with a role;
   - `memberId` is kept only for old roster-linked records.

### Step 2: Repository

In `domain/workshop_repository.dart`, add or extend these methods and document each error code:

```dart
Future<Result<WorkshopParticipant>> addTeamMember(String workshopId,
    {required String name, required WorkshopRole role, required bool paid});
// errors: not_found, archived, validation (empty name), duplicate, workshop_full

Future<Result<WorkshopParticipant>> updateTeamMember(String participantId,
    {required String name, required WorkshopRole role, required bool paid});
// errors: not_found (also when the line is a guest), archived, validation, duplicate (excluding itself)

Future<Result<WorkshopParticipant>> addGuestParticipant(String workshopId, String name,
    {bool paid = false});   // extended, existing callers keep compiling
```

In `data/mock_workshop_repository.dart`, the new methods mirror `addGuestParticipant` (`:585`):
- start with `await _latency()`;
- guard with `_writable` / `_writablePart`;
- clean the name with `normalizeMemberName`;
- check duplicates with `memberNameKey`, **filtered by kind**;
- build initials with `TeamMember.initialsOf`;
- start at `attendance: AttendanceState.notCheckedIn`;
- set `paymentStatus: paid ? PaymentStatus.paid : PaymentStatus.unpaid`.

The Arabic failure messages follow the existing tone. Examples:
- 'اكتب اسم العضو.'
- 'يوجد عضو بهذا الاسم في الورشة.'

### Step 3: Strings (`lib/l10n/strings.dart`, next to the existing workshop keys ~`:1569-1632`)

**New keys:**

| Key | Value |
|---|---|
| `workshopTeamMembersPart` | 'أعضاء الفريق' |
| `workshopVisitorsPart` | 'المتطوعون والزوار' |
| `workshopMemberFormNew` | 'إضافة عضو للورشة' |
| `workshopMemberFormEdit` | 'تعديل العضو' |
| `workshopMemberName` | 'الاسم' |
| `workshopMemberNameHint` | 'الاسم الكامل' |
| `workshopMemberRole` | 'الدور' |
| `workshopRoleLeader` | 'قائد' |
| `workshopRoleTrainer` | 'مدرب' |
| `workshopRoleSupport` | 'دعم' |
| `workshopRoleManagement` | 'إدارة' |
| `workshopRoleMember` | 'عضو' |
| `workshopPaidSwitch` | 'دفع رسوم الورشة' |
| `workshopNotComing` | 'لن يحضر' |
| `workshopUnpaidCount` | 'لم يدفعوا' |
| `workshopEditMember` | 'تعديل' |
| `emptyWorkshopVisitors` | empty-state title for the visitors part |
| `emptyWorkshopVisitorsSub` | empty-state body for the visitors part |

**Changed values:**

| Key | From | To |
|---|---|---|
| `workshopMembers` | 'الأعضاء والضيوف' | 'الأعضاء والزوار' |
| `workshopAddGuest` | — | 'إضافة زائر أو متطوع' |
| `workshopGuestName` | — | 'الاسم' |
| `kindGuest` | — | 'زائر/متطوع' |
| `participantGuest` | — | 'زائر/متطوع' |
| `participantMember` | 'متطوع' | 'عضو فريق' (the old value now clashes) |
| `statsGroupParticipants` | 'طلاب/ضيوف' | 'الأعضاء والزوار' |

Never hard-code Arabic in widgets.

### Step 4: New page `presentation/workshop_member_form_page.dart`

Structure:
- `WorkshopMemberFormPage({required String workshopId, String? participantId})`, a `ConsumerStatefulWidget`.
- Copy the shape of `WorkshopEditPage`:
  - `Scaffold(backgroundColor: c.bg)` with an AppBar titled `workshopMemberFormNew` or `workshopMemberFormEdit`;
  - `Form` + `ListView(padding: AppSpacing.lg)`;
  - private copies of `_Labelled` and a `_RolePill` shaped like `_StatusPill`, at a minimum height of 48 for touch.

Fields:
1. **Name:** `TextFormField(autofocus: true)`. The validator uses `normalizeMemberName(v).isEmpty ? S.required : null`.
2. **Role:** a `Wrap` of 5 pills. The default is `WorkshopRole.member`. Each pill has `Semantics(button: true, selected: …)`.
3. **Paid:** a `SwitchListTile.adaptive` titled `S.workshopPaidSwitch`, with the fee as its subtitle via `formatWorkshopAmount`. It is shown only when the fee is above 0, which needs `workshopByIdProvider`. Default: off (red / unpaid).
4. **Save:** a `FilledButton(S.save)`, disabled while `_saving`, followed by `TextButton(S.cancel)`.

Edit mode:
- Read the line from `workshopParticipantsProvider(workshopId)`.
- Pre-fill it once (the `_seed` pattern) and handle loading, error, offline, and not-found or guest (the error state).
- Do **not** pass the participant through `extra`, because it does not survive a deep link or a restore.

Saving:
- Call `repo.addTeamMember` or `repo.updateTeamMember`.
- On success: `refreshWorkshop(ref, workshopId)`, a snackbar (`S.workshopAdded` or `S.savedOk`), then `context.pop()`.
- On failure: show the repository message in a snackbar, and stay on the page with the input kept.

Archived workshop: when `workshopModeProvider` is not `active`, the page shows `S.workshopArchivedBanner` and save is disabled.

### Step 5: Routes (`core/router/app_router.dart`, `_workshopBranch`)

Add two `GoRoute`s **next to `':id/edit'` and before the `ShellRoute`**:
- `':id/members/new'` → `WorkshopMemberFormPage(workshopId: id)`
- `':id/members/:pid/edit'` → `WorkshopMemberFormPage(workshopId: id, participantId: pid)`

Both use:
- `parentNavigatorKey: _rootKey`;
- `redirect: _needs(ref, const {Cap.workshopPeopleManage}, fallback: '/workshop')`;
- `_sharedAxisPage`.

Open them with `context.push(...)`, so that `pop` lands back on the tab.

### Step 6: Members tab (`tabs/workshop_members_tab.dart`)

1. **Replace `_ParticipantFilter`** with:
   - `enum _Part { team, visitors }`, default `team`;
   - `enum _PayFilter { all, paid, unpaid }`.
2. **Top of the tab:**
   - the existing `AppMeta` seat line;
   - an `AppFilterBar` with the two part chips, each showing its count through `AppNumber.count`.
3. **Add button per part** (behind `canManage`):
   - **Team part:** `FilledButton.icon(S.workshopAddMember)` → `context.push('/workshop/$id/members/new')`.
   - **Visitors part:** `FilledButton.icon(S.workshopAddGuest)` → `askWorkshopGuestDetails` (Step 7) → `repo.addGuestParticipant(id, name, paid: paid)`.
4. **Search** stays. **Payment filter chips** (all / دافع / غير دافع):
   - the unpaid chip label carries the count, «غير دافع (N)»;
   - hidden when the workshop is free.
5. **Empty states** exist per part. The no-results state clears both the search and the payment filter.
6. **`_ParticipantCard`**:
   - Team line context: role label (`participant.role.label`).
   - Visitor line context: `S.kindGuest`.
   - Plus a payment `StatusChip`: `StatusKind.ok` + `S.paymentPaid` when `isPaid`, otherwise `StatusKind.crit` + `S.paymentUnpaid`. It is hidden for free workshops.
   - Put the chip in the context line, as `Wrap(spacing: AppSpacing.sm, crossAxisAlignment: center, [role text, payment chip])`.
   - Keep the attendance chip as `trailing`, with `absent` → `S.workshopNotComing`.
   - Do **not** put two chips in `trailing`: it breaks at 320dp.
7. **`_personSheet`**:
   - Pass `attendanceChoices: WorkshopAttendanceChoices.register` (Step 7).
   - Pass `paymentChoices: binary`.
   - Add `onEdit` for `kind == member` && `canManage`: pop the sheet, then push the edit route.
8. Delete `_addMembers`. The roster-picker import and the `organizingTeam` exclusions go away **from this file only**.

### Step 7: Shared widgets (`widgets/workshop_people.dart`)

- **`WorkshopPersonActions`** gains parameters, so that **the organisers tab keeps today's behaviour by default**:
  - `List<(AttendanceState, String, IconData)> attendanceChoices`, defaulting to the current four-item list. Expose a public const for the register list: `checkedIn`/«سجّل الدخول», and `absent`/«لن يحضر».
  - `bool binaryPayment = false`. When true, only paid/unpaid are shown, and `null` counts as unpaid for the `selected` state.
  - `VoidCallback? onEdit`, plus `String? editLabel`. It renders an edit row above remove.
- **Guest sheet:** `askWorkshopGuestName` becomes `askWorkshopGuestDetails(context, {required bool showPaid})` and returns `({String name, bool paid})?`.
  - `_GuestNameForm` gains the same `SwitchListTile` used on the page.
  - Rename in place and update the only call site.

### Step 8: Stats (binary payment)

**`domain/workshop_stats.dart`:**
- `PaymentStatusLabel`: `null` → `S.paymentUnpaid`.
- `WorkshopGroupStats.of`: `unpaid` = everyone who is **not** `paid`.
- Keep the `unspecified` field, but it is always 0 for participants. **Organisers**: build `teamStats` with payment counts forced to 0, because organisers don't pay (e.g. `WorkshopGroupStats.of(list, countsPayment: false)`).
- `roleLabel`:
  - member lines → `p.role.label`;
  - guests → `S.participantGuest`.

**`tabs/workshop_stats_tab.dart`:**
- Remove the «غير محدد» parts (`:198`, `:432`, `:471`).
- Hide the payment line for the organisers group.
- `:332` becomes `stats.unpaidCount`.

**`data/workshop_stats_report.dart:59,121`:** drop the unspecified column.

### Step 9: Seeds

Add roles and explicit paid/unpaid to seeded **member** lines:
- `data/mock_workshop_repository.dart` (p1–p20);
- `features/demo/domain/demo_seed.dart` (`_participant` helper `:291-297`, lines dp1–dp7).

Use a spread of roles, including at least one قائد and one مدرب. Replace every seeded `null` payment with `unpaid`. Keep `w6` empty.

### Step 10: Docs

- **`API_CONTRACT.md` → Workshops** (`~:2618`):
  - `WorkshopParticipant.role` (the enum, present only for `kind: member`);
  - `kind: guest` = volunteer/visitor;
  - payment is binary for new records.
- **`BACKEND-HANDOFF.md` §6.3:** add `POST /workshops/{id}/team-members`, `PUT /workshop-participants/{id}` (name, role, paid), and `POST /workshops/{id}/guests` with `paid`.
- **`HANDOFF.md`:** add a new dated section for this rework.

## 5. The hard parts: read these before coding (Codex traps)

1. **Don't break the organisers tab.** `WorkshopPersonActions` is shared with `workshop_team_tab.dart:143-175`. Every new parameter must default to today's behaviour. Organisers keep four attendance choices and have no payment.
2. **Don't change the global `S.absent` or `AttendanceState`.** Shifts, the roster and detachments use both. «لن يحضر» is a workshop-only label, mapped at the call sites.
3. **Two meanings of `null` payment.** The wire and model keep `PaymentStatus?`, and old data and the API contract allow "absent".
   - Everywhere in the register UI and in stats, read `isPaid`, and treat `null` as unpaid.
   - Organisers are the exception: they are excluded from payment counts, not counted as unpaid. If they were counted, the "غير دافع" total would jump by the organiser count.
4. **Route order in go_router.** `':id/members/new'` must be registered at the `'/workshop'` level with `parentNavigatorKey: _rootKey`, **before** the `ShellRoute`, exactly like `':id/edit'`. If it is nested under the shell's `':id/members'` it would render inside the tab shell.
   - Also add a router test that `/workshop/w1/members/new` resolves to `WorkshopMemberFormPage`.
   - And that a session without `workshop.people.manage` is redirected.
5. **The edit page loads by id, not `extra`.** It must handle loading, error, offline, not-found, and "this id is a guest" as designed states. It must seed the form **once**; don't overwrite user typing on rebuild.
6. **The duplicate check on update must exclude the line itself**, and it compares by `memberNameKey`, which normalises Arabic. Renaming "أحمد" to "احمد" must not collide with itself.
7. **Backward-compatible JSON.** Old member records have no `role`, and may have `memberId` and a `null` payment.
   - `fromJson` must not throw: a member line defaults its role to `member`.
   - Add a round-trip test for both old and new shapes.
8. **A nested tappable inside the row.** If Codex makes the payment chip tappable for a quick toggle, it sits inside `PressScale` (`WorkshopPersonRow`). This is **out of scope**: payment is changed through the sheet. Keep the chip as display only.
9. **Layout at 320dp and 1.6× text, RTL.**
   - `WorkshopPersonRow` stacks the trailing chip under large text. The payment chip must live in the context line, inside a `Wrap`, so nothing overflows.
   - Role pills must wrap.
   - Use only `EdgeInsetsDirectional` / `AlignmentDirectional`.
10. **Existing tests will break by design and must be rewritten, not deleted.**
    - **`workshop_members_flow_test.dart`:**
      - "add member" (`:117`) and "picker exclusions" (`:131`) test the roster picker in the Members tab. Rewrite them to cover the new page flow.
      - Keep or move the picker-exclusion coverage to the organisers test (`:223`), since organisers still use the picker.
    - **`workshop_stats_test.dart:130-162,351,398-401`:** these assert `unspecified`. Update them to the binary rule, and add "organisers are not counted in payment".
    - **`workshop_people_test.dart`:** add group tests for `addTeamMember` / `updateTeamMember` / guest `paid`.
    - Also run `test/features/demo/demo_workspace_test.dart`, because the seed changes.
11. **Project rules (CLAUDE.md).**
    - Colours come only from `context.c`, via `StatusChip` kinds `ok` (green) and `crit` (red). No hex values, and no new packages.
    - Respect `disableAnimations`: only existing `Stagger` and `PressScale`.
    - Don't fix unrelated analyzer errors.
    - Three calendar-dependent suite failures are known and are not caused by this change.
12. **Capacity (A8).** Team members still take seats, so `addTeamMember` can return `workshop_full`. The page must show that message and keep the input.

## 6. Verification

- `cd flutter_app && flutter analyze`: no new issues in the touched files.
- `flutter test test/features/workshop/`, and add tests for:
  - **Model:** `WorkshopRole` JSON round-trip, and an old record without `role` defaulting to `member`.
  - **Repository:**
    - `addTeamMember` for validation, duplicate (per kind), `workshop_full`, archived, and paid/unpaid saved;
    - `updateTeamMember` for self-rename and for a guest id → not_found;
    - guest `paid`.
  - **Add page:**
    - empty name → required;
    - role defaults to عضو, and choosing مدرب saves مدرب;
    - the switch saves paid and unpaid;
    - the switch is hidden on a free workshop;
    - after save the list shows the name + «مدرب» + a green or red chip.
  - **Tab:**
    - the two parts separate members from visitors;
    - the unpaid filter and its count work;
    - the visitor add sheet saves name + paid.
  - **Sheet:**
    - a register person sees only «سجّل الدخول» / «لن يحضر» and paid/unpaid;
    - an organiser still sees four attendance choices.
  - **Layout:** 320dp × 1.6× text, RTL, no overflow on the page or the rows.
- `flutter test test/core/router/app_router_test.dart test/features/demo/`, then the full `flutter test`. Only the 3 known calendar tests may fail.
- **Manual (`flutter run`):**
  1. Workshop → الأعضاء والزوار → أعضاء الفريق → إضافة عضو.
  2. Enter a name, choose مدرب, turn paid on, and save. The row shows the name, «مدرب», a green دافع chip, and a muted «لم يسجل الدخول» chip.
  3. Tap the row → «سجّل الدخول». Then «لن يحضر».
  4. تعديل → change the role.
  5. المتطوعون والزوار → add a visitor with paid off. The row shows a red غير دافع chip.
  6. Check the stats tab totals.
- `graphify update .` after the code changes.
