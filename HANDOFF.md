# Leader (formerly MTM) Front-Back — current handoff

## Current checkpoint — 2026-09-23

Leader / ليدر is a runnable, Arabic-first Flutter frontend under
`flutter_app/`. The Android application ID is `com.leader.teams`; documented
technical `MTM` identifiers remain for compatibility. The UI quality programme
is closed for its audited frontend scope. The later entry pass implemented the
Login and cold-launch Intro experience, fixed brand identity, and routed Google
sign-in through the native chooser on Android/iOS. Its detail and test coverage
are in **THE ENTRY EXPERIENCE** near the end of this file.

The latest committed frontend baseline before this repository handoff is
`d1e49ec` on the local `sync-conflict-and-pending-work` branch. That entry
checkpoint reported a full Flutter suite and clean analysis. For this handoff,
the current full suite passed **2505/2505** tests and `flutter analyze` found
no issues. One test date setup in `shift_save_persistence_test.dart` was
corrected to step across daylight saving by calendar day, matching the
existing production helper; no application behavior changed. Historical test
counts below belong to their dated checkpoints.

Backend contracts exist, but there is no real backend or HTTP transport in this
repository. Start implementation with `BACKEND-HANDOFF.md` §19, then the wire
authority in `API_CONTRACT.md`. Choose a backend stack explicitly. The seven
live backend/data dependencies are in `DATA-NEEDS.md` §16. Device-local
appearance and performance settings need no API. Production Google sign-in
needs the external Android OAuth client and signing fingerprints, a Web client
ID passed as `MTM_GOOGLE_SERVER_CLIENT_ID`, and backend verification of that
ID token audience; see **THE ENTRY EXPERIENCE** §I and
`BACKEND-HANDOFF.md` §19.2.

The detailed history below is retained for implementation rationale. Its
older branch, working-tree, and test-status lines describe those sessions,
not the current checkout.

Read in this order to resume:

1. `CLAUDE.md`
2. **`BACKEND-HANDOFF.md`** — the **final** backend handoff package (Point 18
   COMPLETE: domain model, identifiers, auth/refresh, onboarding, Team Code,
   invitations, Customer Demo, authorization order, state machines, endpoint
   inventory, idempotency, errors, audit, privacy, deployment, final gap
   classification, build order). Start here for anything backend-facing — and
   start *there* at **§19 BACKEND IMPLEMENTATION READINESS**, added in the
   2026-09-23 entry-checkpoint audit: what is implementable now, what waits on
   external Google/keystore/email configuration, which product and data
   decisions are still open, and what is frontend-only and must never grow an
   endpoint (appearance, Eye Protection, motion/frame rate, the intro, the
   pulse, the fixed mark). That audit also corrected the stale `minSdk` claim
   in §14, superseded the `settings/motion-level` endpoint pair in
   `API_CONTRACT.md`, recorded the native Google chooser as wire-neutral,
   enumerated the seven live data dependencies once in `DATA-NEEDS.md` §16,
   and added `FRONTEND-BACKEND-INTEGRATION.md` §8. No backend stack was
   chosen.
3. **this file** — start with **UI QUALITY PROGRAMME — FINAL STATUS**, then
   **PHASE 3C: CLOSURE VERIFICATION**, then **PHASE 3B: TENANT UI
   CLEANUP**, then **PHASE 3A: THE HIGH-RISK TENANT SCREENS**, then **UI
   QUALITY PROGRAMME — PHASE 2: SUPER ADMIN** (the Platform surface redesign),
   then **UI QUALITY PROGRAMME — PHASE 1:
   FOUNDATION** (the shared UI primitives every later screen pass builds on,
   plus the `copyWeek` DST fix), then **BRAND MARKS & THE GREEN/GLASS LOGIN
   (IMPLEMENTED)**, then **POINT 19 — PRICING, GLOBAL OFFERS & COUPONS
   (IMPLEMENTED)**, then **DEMO CONTROL PLANE, DEMO UI CLEANUP & ABOUT
   LEADER**, then **CUSTOMER DEMO — FULL ISOLATED APP TRIAL**,
   then **WORKSHOPS — FUNCTIONALLY COMPLETE FOR CURRENT FRONTEND SCOPE**, then **LEADER REBRAND — PHASE 2 COMPLETE**, then
   **LEADER REBRAND — PHASE 1 FOUNDATION COMPLETE** (product is now Leader /
   ليدر), then **POST-POINT-18
   AUTHENTICATION / SETTINGS CLEANUP**, then **POINT 18B — FINAL BACKEND HANDOFF PACKAGE,
   VALIDATION & PROJECT CLOSURE**, then **POINT 18A — FINAL BACKEND HANDOFF
   CONSOLIDATION**, then **POINT 17C — SIGNUP / ONBOARDING SECURITY,
   UX & FINAL CLOSURE** (Point 17 is COMPLETE), then **POINT 17B — SIGNUP /
   ONBOARDING CORE IMPLEMENTATION & INTEGRATION**, then **PERSONA / CUSTOMER DEMO + SIMPLE ADMIN
   MANAGEMENT + THEME RESTORATION**, then **POINT 17A — SIGNUP / ONBOARDING ARCHITECTURE
   & FOUNDATION**, then
   **POINT 16 — SIMPLE ADMIN EXPERIENCE AUDIT** (COMPLETE), then
   **POINT 15 — ORGANIZATION + PLAN SCREENS** (COMPLETE), then
   **POINT 14C — MAIN ADMIN ACCOUNT MANAGEMENT
   FINAL UX, VISUAL VALIDATION & CLOSURE** (Point 14 is COMPLETE), then **POINT 14B — MAIN ADMIN ACCOUNT MANAGEMENT CORE
   UX & INTEGRATION**, then **POINT 14A — MAIN ADMIN ACCOUNT MANAGEMENT
   ARCHITECTURE & FOUNDATION**, then
   **POINT 13C — PLATFORM REPORTS FINAL UX,
   VISUAL VALIDATION & CLOSURE** (Point 13 is COMPLETE), then **POINT 13B — PLATFORM
   REPORTS CORE UX & INTEGRATION**, then **POINT 13A — PLATFORM REPORTS
   ARCHITECTURE & FOUNDATION**, then **POINT 12C — BREAK-GLASS FINAL UX, VISUAL
   VALIDATION & CLOSURE**, then **POINT 12B — BREAK-GLASS CORE UX &
   INTEGRATION**, then **POINT 12A — BREAK-GLASS ARCHITECTURE &
   FOUNDATION**, then **POINT 11B — PLATFORM AUDIT LOG UX &
   INTEGRATION**, then **POINT 11A — PLATFORM AUDIT LOG
   FOUNDATION**, then **POINT 10 — PLATFORM HEALTH & SECURITY**, then
   **POINT 9B — TENANT LIFECYCLE UX & INTEGRATION**,
   then **POINT 9A — TENANT LIFECYCLE FOUNDATION**, then
   §ZZZZZZZZZZZZZZZZZZZ, then
   §ZZZZZZZZZZZZZZZZZ, §ZZZZZZZZZZZZZZZZ, §ZZZZZZZZZZZZZZZ, §ZZZZZZZZZZZZZZ, §ZZZZZZZZZZZZZ, §ZZZZZZZZZZZZ, §ZZZZZZZZZZZ, §ZZZZZZZZZZ,
   §ZZZZZZZZZ, §ZZZZZZZZ, §ZZZZZZZ, §ZZZZZZ, §ZZZZZ, §ZZZZ, §ZZZ, §ZZ, §Z, §A,
   then §0–§7 (all earlier, still accurate)
4. `UI-AUDIT-REPORT.md` — the UX audit the programme acted on. Every finding
   now carries a disposition in place (**RESOLVED** with its phase,
   **INTENTIONALLY RETAINED**, **BACKEND/DATA DEPENDENCY** or **OPTIONAL
   FUTURE POLISH**); the Phase 3C closure ledger near the top is the summary.
5. `SCREEN-ROUTE-MATRIX.md` — the canonical screen/route inventory. Update it in the same change that adds or moves a route.
6. `SCHEDULE-CHANGES-HANDOFF.md` (older handoff — still accurate for the
   template/manage-sheet architecture it introduced; §4 records where a later
   session changed its rulings)
7. the working-tree diff (`git status`, `git diff`)

Historical UI-quality checkpoint date: 2026-09-21. The current source state
is summarized above.

---

## UI QUALITY PROGRAM — FINAL STATUS

**The Leader frontend UI quality programme is CLOSED as of 2026-09-21.** No
frontend P0 or P1 defect remains open. What remains is named, classified and
honest: five data gaps a backend has to fill, two product/backend decisions on
Workshops, and a short list of optional polish nobody is blocked on.

| Phase | Scope | Outcome |
| --- | --- | --- |
| **Phase 1 — Foundation** | The shared UI layer every later pass builds on | `ForwardChevron` / `DirectionalArrows`, one `SectionHeader`, `AppFilterChip` / `AppFilterBar`, `showAppConfirmation`, `ReadingColumn` and the width scale, the internal-identifier copy pass, the tenant render harness — and the `copyWeek` DST bug the audit's test work surfaced |
| **Phase 2 — Super Admin** | The whole Platform surface | Overview, Operations, Commerce, SaaS Tenant Detail, Audit, Security, Tenants, Tenant Features, Demo, Health, Reports. Found three defects the audit had not, all by reading its own renders |
| **Phase 3A — High-risk Main Admin** | The two screens the audit rated worst | Home and Statistics rebuilt around the question each answers; `AppMeta` / `AppMetaText`, `AppTime`, `AppNumber` promoted into `core/`; the four-class tenant measure policy. Found three more render-only defects and one data-truth defect |
| **Phase 3B — Remaining tenant UI** | Adoption and copy, not design | Bottom-nav semantics, Shifts, Workshop Register, Settings consolidation, Pricing, Inventory states, Session Expired, «السمات», the injected workshop clock, dead-string removal, the scrolling `AnimatedTabBar` |
| **Phase 3C — Closure verification** | Verify, fix only real defects, classify, close | Every audit finding given a disposition; **P1-11 closed**; four previously unseen defects fixed (the weekday row that said «ال» seven times, the badge that covered its bell, four Latin-digit figures in Arabic sentences, and a render harness that never rendered dark) |

**What "closed" does not mean.** It does not mean the product is finished, and
it does not mean the remaining dependencies are small. It means no frontend
screen is known to be broken, inconsistent with the design system, unreadable
at 320 dp / 1.6×, wrong in RTL, or dishonest about data it does not have. The
next UI work should be driven by a product decision or by real users, not by
this audit.

**The open dependencies, unchanged and not reclassified downward**

1. A cross-detachment attention roll-up (organisation-level summary endpoint).
2. Dates on `DetachmentStats` — the three series are bare `List<int>`.
3. A stated unit on the stock series.
4. A product decision on showing `attendanceSeries` in the statistics tab.
5. Historical roster size, for any roster trend.
6. Workshop payment authority — the register records it; no backend settles it.
7. A real `.xlsx` writer, if «Excel (CSV)» is ever not enough.

---

## UI QUALITY PROGRAMME — PHASE 3C: CLOSURE VERIFICATION (COMPLETE, 2026-09-21)

Phase 3C is the closure pass. It did **not** redesign a screen. It re-read
`UI-AUDIT-REPORT.md` finding by finding, checked each against the code and
against fresh renders, fixed only what was genuinely broken, and classified
the rest. Home, Statistics, Platform, Login, Team roster, Detachment list,
Sync Center, Needs Review, Organization and Plan were not redesigned, and no
competing primitive was introduced.

Branch: `sync-conflict-and-pending-work`, working tree only — nothing
committed or pushed.

### What the pass found

The audit's own remaining lines were mostly already closed. The six items
below are what the phase actually changed, and every one of them was found by
**reading renders**, not source.

1. **The schedule's weekday row said nothing at any size.** Both the day strip
   (`detachment_shifts_tab.dart`) and the repeat picker
   (`repeat_days_picker.dart`) abbreviated a weekday as
   `AppDate.weekdayOf(d).substring(0, 2)` — and every Arabic weekday begins
   «ال», so all seven columns drew the same two characters. The row was
   decoration. `AppDate.weekdayInitial` now returns the conventional distinct
   calendar letters `ن ث ر خ ج س ح`; the strip draws them; a new guard in
   `design_system_guard_test.dart` rejects the next cut weekday name.
2. **Each day column now says its whole name.** A single letter and a number
   is the right visual density for seven columns and the wrong thing to hear,
   and the amber dot that marks a short-staffed day was status by colour
   alone. One `Semantics` node per column: «السبت ١٢ أيلول» plus
   «نقص في التغطية» when the day has a gap, `button: true`, `selected:`,
   descendants excluded so nothing is announced twice.
3. **The notification badge covered the bell.** At 320 dp / 1.6× the count
   grew to the width of the 24 dp icon. The badge subtree is now clamped
   (`MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3)`) — the count
   still scales, 10 sp to 13 — and sits at the corner of the glyph rather
   than on it. Every other string on that screen still scales in full.
4. **`AppDate.dayMonthTime` was the last helper printing ` · ` between two
   numerals**, and it is read by Organization's «آخر قراءة», the SaaS tenant
   detail, the lifecycle section, the feature-availability report,
   break-glass copy and the attendance PDF. It joins with a space now, like
   `AppTime.dayTime`. Five more number-adjacent joins went with it: the Sync
   Center's last-success stamp, Settings → Security's session row (which also
   stopped overriding `Directionality` around its clock), the report
   preview's generated-at line, the shift search result and the conflict
   record's day line. **P1-11 is closed.** The ` · ` that remain join words.
5. **Two numeral systems on one screen, four places.** Platform Overview's
   attention rows («2 تنبيه أمني»، «1 اشتراك في فترة السماح») sat beside
   Arabic-Indic summary rows; the trial-extension sheet offered
   «إضافة 7 يومًا» directly above «٢٥ أيلول ٢٠٢٦», with the wrong plural for
   seven; the activity report's range guard said «أطول فترة مسموحة 90 يوماً»;
   and the workshop capacity failure printed a Latin count. All four print
   Arabic-Indic now, and the trial options carry their own plural
   («٧ أيام» / «١٤ يوماً» / «٣٠ يوماً») the way the report ranges already did.
6. **The tenant render harness never rendered dark.** `shot()` read
   `AppThemeChoice.defaultMode`, which is `ThemeMode.light` for all six
   palettes since the palette ruling, so the two shots named "dark" were
   light. Appearance is a parameter now (`mode:`), and Home was reviewed on a
   real dark render.

### What was verified and deliberately left alone

* **The five Phase 3A data gaps are unchanged and were re-verified in code**:
  `HomeRepository.summary(detachmentId)` still answers for one detachment;
  `DetachmentStats` is still three bare `List<int>` with no dates;
  `stockSeries` still carries no unit; `attendanceSeries` is still read only
  by the PDF builder; and no repository carries a historical roster size. No
  screen claims any of it exists.
* **Workshop payment** is recorded through `setParticipantPayment` and shown
  as a register fact; nothing in the UI presents it as a settled transaction.
  **Export** is labelled «Excel (CSV)» — which is exactly what it writes.
* **Organization**, **Plan**, **Main Admin seat**, **Login**, **Signup/OTP**,
  **Session Expired**, **Demo trial bar** and the four platform reports were
  re-read and re-rendered with no genuine defect found.
* **Optional future polish, named rather than done**: the ~25 single-value
  `Directionality` overrides that could be `Bidi.ltr`; the presentation-only
  wall-clock reads in Needs Review, notifications, member status and the
  shifts tab; the Team roster's `shrinkWrap` filter chip; tokenising Login's
  hand-spelled rhythm; real-device screen-reader testing.

### Brand

`S.productNameAr` is «ليدر» and `S.productNameEn` is «Leader». There is
**one** mark — `06 · Clean Layer` — drawn by `core/brand/brand_mark.dart` from
the single path on `AppInfo.logoAsset`, and it is also the launcher icon. (It
was briefly three, selectable in Settings; see "THE ENTRY EXPERIENCE" below
for why that is gone.) The only `MTM` left in `lib/` outside comments is the
Team Code prefix and its hint mask — protocol identifiers `CLAUDE.md` keeps
deliberately. No visible branding leakage.

### Files changed

**Product**

* `core/format/app_date.dart` — `dayMonthTime` joins with a space;
  `weekdayInitial` / `weekdayInitialOf` added with the reasoning.
* `core/format/app_time.dart` — the doc paragraph that described the old
  behaviour.
* `core/widgets/app_meta.dart` — untouched; it was already the answer.
* `features/detachment/presentation/tabs/detachment_shifts_tab.dart` — the day
  strip's initial, and one semantics node per column.
* `features/shift/presentation/repeat_days_picker.dart` — the same initial.
* `features/shift/presentation/shift_conflict_adapter.dart` — `AppTime.weekdayDay`.
* `features/notification/presentation/widgets/notification_bell.dart` — clamped
  badge, corner offset, «، » instead of « · » in the spoken label.
* `features/settings/presentation/widgets/sync_settings_section.dart` — the
  last-success stamp.
* `features/settings/presentation/security_page.dart` — one `AppTime.dayTime`
  in place of three widgets and a `Directionality` override.
* `features/detachment/presentation/report_export_page.dart` — the
  generated-at line is an `AppMeta`.
* `features/search/data/search_entries.dart` — the shift subtitle.
* `features/platform/data/mock_platform_overview_repository.dart`,
  `features/platform/presentation/saas_tenant_subscription_page.dart`,
  `features/platform/presentation/platform_activity_report_page.dart`,
  `features/workshop/data/mock_workshop_repository.dart` — Arabic-Indic
  figures, and the trial-extension plural.

**Tests**

* `test/features/shift/day_strip_labels_test.dart` — **new**: the initials are
  distinct, the strip draws seven of them at 320 dp / 1.6×, and each column
  announces its whole day.
* `test/core/design_system_guard_test.dart` — **new rule**: no cut weekday name.
* `test/core/format/app_meta_time_test.dart` — `dayMonthTime` prints no dot and
  agrees with `AppTime.dayTime`.
* `test/features/notification/notification_bell_test.dart` — the badge scales,
  but not past the clamp and not past the icon.
* `test/features/platform/platform_tenant_consistency_test.dart` — the grace
  attention title is asserted in Arabic-Indic.
* `test/features/tenant/tenant_render.dart` — appearance is a parameter, so the
  dark shots are dark.

### Validation

* **Full suite: 2451 / 2451 green** (Phase 3B baseline 2442 + 9 new tests).
  One pre-existing assertion was updated rather than added:
  `platform_tenant_consistency_test.dart` asserted the attention title
  contained a Latin `2`.
* `flutter analyze` — no issues. `git diff --check` — clean.
* **Renders: 256 produced and the representative set inspected by eye**, with
  the existing harnesses only (`tenant_render.dart`, `onboarding_render.dart`,
  `platform_render.dart`, `platform_audit_render.dart`,
  `organization_plan_render.dart`). No screenshot tooling was added. The
  tenant set was re-rendered after each fix and the three changed regions were
  re-read at 320 dp / 1.6× and at 390 dp.
* `flutter build apk --debug` — built; `aapt dump badging` verified package
  `com.leader.teams` and label «ليدر».
* `graphify update .` — **14,364 nodes / 22,183 edges / 430 communities**
  (Phase 3B: 14,335 / 22,136 / 430).

---

## UI QUALITY PROGRAMME — PHASE 3B: TENANT UI CLEANUP (COMPLETE, 2026-09-21)

Phase 3B finished the lower-risk tenant adoption/copy pass on top of Phase
3A. It did **not** reopen Home, Statistics, Platform, Login, Team roster,
Detachment list, Sync Center or Needs Review, and it introduced no competing
metadata, time, percentage, width, filter or confirmation primitive.

Branch: `sync-conflict-and-pending-work`, working tree only — nothing
committed or pushed. The final full suite is **2442 / 2442 green** (Phase 3A
baseline 2432 + 10 tests), `flutter analyze` reports no issues,
`git diff --check` is clean, and `flutter build apk --debug` produced
`build/app/outputs/flutter-apk/app-debug.apk`. `aapt dump badging` verified
package `com.leader.teams` and application label «ليدر». Graphify was refreshed
after the final code and documentation changes.

### What closed

1. **Bottom navigation.** Every tenant destination now has one Arabic semantic
   label and explicit selected state; descendant icon/text semantics are
   excluded so nothing is announced twice. Routes, destination/branch order,
   glass styling and navigation behaviour are unchanged.
2. **Shifts.** Card facts use `AppMeta`, clocks/ranges use `AppTime`, and numeric
   coverage uses `AppNumber`. Navigation actions are labelled. The 320 dp / 1.6×
   render exposed compressed card metadata and clipped bulk-action labels;
   those reflow vertically at large text. The schedule remains an uncapped
   class-C surface, and the Phase 1 DST/arrows/day-strip fixes were not reopened.
3. **Workshop register.** Search and compact participant scanning now follow
   the Team roster's existing identity model. A workshop with no participants
   and a search/filter with no matches are separate states. Filters expose
   removable active chips only when active, participant facts use `AppMeta`,
   and the permanently disabled `OfflineBanner(visible: false, ...)` was
   deleted because no live offline state exists on that shell.
4. **Accessibility.** The remaining audited tenant/shared `IconButton`s have
   tooltips, with explicit semantics only where Flutter cannot derive the name.
   A source guard now rejects future unlabeled `IconButton` actions. Touch
   targets and actions are unchanged.
5. **Settings.** The small single-row sections were consolidated into meaningful
   groups; «المزامنة» no longer repeats as both heading and row; and the single
   user-facing subscription door is «الاشتراك والأسعار». Theme/palette, three
   logos, Eye Protection, performance controls and «صنع بفخر في العراق» are
   preserved. Plan remains reachable through Organization instead of a second
   conceptual subscription entry.
6. **Organization and Plan.** Their Phase 1 measures and existing responsive
   hierarchy rendered cleanly, so no speculative content or structural redesign
   was made. This is an intentional retain, not unfinished work.
7. **Pricing.** Each duration still grants full Leader access at exactly
   1/$6, 3/$14, 6/$24 and 12/$40. The duplicate full-access message is gone,
   percentages use `AppNumber.percent`, and Arabic-facing duration figures are
   Arabic-Indic. Domain IDs, coupons/offers and the contact action are unchanged.
8. **Small copy/state correctness.** Session Expired states its explanation once
   and uses `S.signIn` («تسجيل الدخول»); user-facing «الثيمات» became «السمات»;
   Inventory distinguishes genuine emptiness from zero search/filter matches;
   Workshop statistics/export generation takes the existing `clockProvider`
   time and has deterministic tests.
9. **Shared adoption.** `AppMeta`, `AppTime` and `AppNumber` replaced ambiguous
   numeric separators, bare local clocks and raw percentages in the touched
   Shifts, Inventory, Workshop, notification, member-status, report and pricing
   paths. Team and Detachments received safe formatting substitutions only; their
   strong structures were deliberately left alone.
10. **Dead strings.** Each candidate was searched before deletion. Removed only
    zero-reference legacy copy: `last7Days`, `dashboardQuickActions`,
    `dashboardAllClear`, `dashboardAssignedOf`, `dashboardOrgSection`, the three
    `dashboardActiveDetachments*` variants, `dashboardOpenDetachments`,
    `dashboardOrgAttention`, and the obsolete `sectionOrg`. Live organization
    copy such as `sectionOrgManagement` remains.
11. **Animated tabs.** The 3A ellipsis was not sufficient. The strip now gives
    labels their natural single-line width inside a horizontal RTL-aware scroll
    view, animates the same selected indicator, and scrolls the selected tab into
    view. Tap selection, page swipes, arena coordination and tab semantics remain
    on the existing controller path. Focused tests cover 320 dp, 1.6×, RTL,
    selected visibility, taps and swipes.

### Visual and automated verification

The existing `test/features/tenant/tenant_render.dart` harness produced and
passed **61 / 61** PNG renders; no screenshot infrastructure was added. The
review covered the touched Shifts, Workshop Register, Settings, Organization,
Plan, Pricing and Inventory surfaces at 320 dp / 1.6× and 390 dp, with meaningful
600/900 dp cases, plus Light, Dark, Eye Protection and alternate palettes. The
only new visual defect found was Shifts' large-text compression/clipping; it was
fixed and the exact 320 dp render was regenerated and re-read. Organization and
Plan were intentionally retained after their renders showed no genuine defect.

Focused gates included **170 / 170** navigation/shared/Shifts tests,
**394 / 394** Workshop/Settings/Organization/Pricing/Inventory/notifications/
auth/design-guard tests, **13 / 13** pricing appearance tests, and the 61 render
tests. These groups overlap by design; the authoritative aggregate is the one
full-suite run, **2442 / 2442**.

### Remaining classification

* **Backend/data dependency:** Phase 3A's five genuine Home/Statistics gaps are
  unchanged: cross-detachment attention, dated statistics samples, a stated
  stock-series unit, the attendance-series product decision, and historical
  roster size. Workshop payment remains read-only and real `.xlsx` export remains
  a delivery/dependency decision documented below; neither was Phase 3B scope.
* **Optional future polish:** real-device screen-reader and hardware-panel checks,
  and a real `.xlsx` workshop export if dependencies are approved.
* **Genuine unresolved defect:** none found in the Phase 3B scope.

---

## UI QUALITY PROGRAMME — PHASE 3A: THE HIGH-RISK TENANT SCREENS (COMPLETE, 2026-09-21)

Phase 3 of the programme that follows `UI-AUDIT-REPORT.md`, split: **3A** is
the part that needed product, information-architecture and data-visualisation
judgement — Main Admin Home, Statistics, the shared metadata/time layer they
both needed, and the responsive-width policy. **3B** is the lower-risk
adoption and copy pass, now complete in the section above.

Branch: `sync-conflict-and-pending-work`, working tree only — nothing
committed. Full suite **2432 / 2432 green** (baseline 2384 + 48 new),
`flutter analyze` clean, `git diff --check` clean, `flutter build apk --debug`
→ `com.leader.teams` / «ليدر».

### What Home is, and what it is not

Home answers **«ما الذي يحتاج انتباهي اليوم؟»** for **the detachment in
focus**. That is a decision, and it is the honest one: `HomeSummary` is
fetched for one detachment (`DETACHMENT-SCOPING.md` §4), and a
cross-detachment attention roll-up would need an aggregate no repository can
produce. Nothing was invented to fill the gap; it is written up under
"Genuine data gaps" below.

The hierarchy, each block drawn only when it has something to say:

1. **page context** — name, `AppMeta`(weekday+day │ region │ «من ٤ مفرزات»),
   and a switcher that is a real bordered control with its own word;
2. **attention** — heading «يحتاج قرارك» when something genuinely asks for a
   decision, «للعلم» when the only thing listed is the user's own queued
   work. Rows carry a **severity word** (عاجل / مهم / للعلم) and a
   `ForwardChevron`; they are navigation rows, never buttons;
3. **today** — one `TodayCard`: the calm strip when nothing is raised, what
   is running (or one sentence saying nothing is), and the next shift as a
   compact row;
4. **the standing facts** — roster, today's shift count, the store's verdict,
   on one `AppMeta` line;
5. **shortcuts** — the four that jump into this detachment's tabs, in a
   `TileGrid`.

Removed: `_OrganisationSummary` (its one fact moved onto the page context),
the «المفرزات» and «المؤسسة» quick actions (both re-opened permanent
navigation), the separate "all clear" card, and the second empty card.

### The three surfaces that were one absence

The audit's quiet-day render had «لا شيء يحتاج قرارك الآن» above «لا شفتات
اليوم في هذه المفرزة» above «لا شفت قادم مجدول». There is now one card: the
calm strip inside it, and — when the day is empty in both directions — one
sentence, `S.dashboardNoShiftsAtAll`. `dashboard_states_test.dart` asserts
that the other two strings are **absent** in that state.

### Statistics: the scale is decided by the unit

`core/chart/series_scale.dart` + `core/chart/series_card.dart`. Percentages
are always 0–100; counts get the smallest of 1/2/5 × 10ⁿ above the peak and
**print** it; two units never share a scale; a series with fewer than two
readings or all zeros is not drawn. Every card states the period, a day
number under every bar, the latest reading, the change in words, the high,
the average and the scale, and carries one semantics sentence.

Also fixed on that screen: the glance tiles reflow rather than truncate; the
attendance totals are label-over-value tiles; every `·`-joined member line is
an `AppMeta` line; the range and week query read `clockProvider`; and the
coverage tile prints «—» rather than «١٠٠٪» for a week with no shifts.

### The shared layer (promote, never duplicate)

| Moved from | To | Left behind |
| --- | --- | --- |
| `PlatformMeta` / `PlatformMetaText` | `core/widgets/app_meta.dart` → `AppMeta` / `AppMetaText` | `typedef`s |
| `PlatformTime.date/.time/.dayTime` | `core/format/app_time.dart` → `AppTime` | delegating statics |
| — | `core/format/app_number.dart` → `AppNumber.count/.percent/.ratio/.range` | — |
| — | `core/text/bidi.dart` → `Bidi.ltr` | — |
| — | `core/widgets/tile_grid.dart` → `TileGrid` | — |
| — | `core/chart/` → `SeriesPlot`, `SeriesCard` | — |

`PlatformTime` keeps `utcDate` / `utcTime` / `utcSpoken`: *which clock a
record is kept on* is a property of the record, and only the platform surface
has records kept on the other one. **No timezone semantics changed.** What was
UTC is still UTC; what was local is still local; `app_meta_time_test.dart`
asserts it.

**Direction:** `Bidi.ltr` isolates a value (`U+2066 … U+2069`). Never a
`Directionality` override, never a whole row, and a range is one isolate
around the pair — two isolates with a dash between them let the dash resolve
against the Arabic and swap which end it belongs to.

### The measure policy

Written out in `core/widgets/reading_column.dart`: **A** reading/form →
`kReadingMaxWidth` / `kFormMaxWidth`; **B** operational lists and landings →
`kContentMaxWidth`; **C** schedule and data-dense → uncapped, reflow; **D**
two columns only where two groups are genuinely consulted together. Home and
Statistics are class B. Home deliberately stays **one column at 900 dp**: its
sections are a reading order, and putting "today" beside "attention" would
undo the hierarchy. A grid inside a capped column picks its columns from its
own `LayoutBuilder` and the text scale, never from a window breakpoint.

### Three defects the renders found that the audit had not

1. **`AnimatedTabBar` drew every tab label as placeholder boxes.**
   `AnimatedDefaultTextStyle` *replaces* the inherited style rather than
   merging, and the style there had no `fontFamily`, so the detachment and
   workshop tab labels fell off `IBMPlexSansArabic`. Same defect class as the
   `labelSmall` one Phase 2 found. Now built from `AppTypography.chip`.
2. **The statistics glance tiles truncated their labels at 320 dp / 1.6×** —
   «أدوية…», «تغطي…». The figure survived and the meaning did not, which is
   the same defect as an unlabelled chart. They reflow to two columns now.
3. **A single Arabic word broke across two lines** in the Home shortcut grid:
   «الإحصائيا / ت». One-word labels use `FittedBox(scaleDown)` with
   `maxLines: 1`.

Plus one data-truth defect: the week-coverage tile printed «١٠٠٪» for a week
with **no shifts**, because `WeekSummary.coveragePercent` answers 100 when
nothing is needed. The domain was **not** changed (§33 — shift domain is off
limits); the tile reports «—» instead.

### Files

**New:** `core/text/bidi.dart`, `core/format/app_number.dart`,
`core/format/app_time.dart`, `core/widgets/app_meta.dart`,
`core/widgets/tile_grid.dart`, `core/chart/series_scale.dart`,
`core/chart/series_card.dart`, `test/core/format/app_meta_time_test.dart`,
`test/core/chart/series_scale_test.dart`,
`test/features/detachment/stats_presentation_test.dart`.

**Changed:** `core/widgets/reading_column.dart` (policy),
`core/widgets/animated_tab_bar.dart` (family + ellipsis),
`features/platform/presentation/widgets/platform_meta.dart` (now a wrapper),
`features/home/presentation/home_page.dart`,
`features/home/presentation/widgets/dashboard_cards.dart`,
`features/detachment/presentation/tabs/detachment_stats_tab.dart`,
`l10n/strings.dart`, `test/features/home/dashboard_states_test.dart`,
`test/features/tenant/tenant_render.dart` (taller stats shots, stats added to
the wide group).

### Genuine data gaps (Home / Statistics would use these; nothing was faked)

1. **A cross-detachment attention roll-up.** Home can only raise conditions
   for the detachment it fetched. A Main Admin running four detachments has
   no way to learn that a *different* one is short-staffed without switching
   to it. This needs either an organisation-level summary endpoint (counts of
   understaffed shifts / low stock / missing attendance per detachment) or a
   fan-out the client cannot currently afford.
2. **Dates on `DetachmentStats`.** The model is three bare `List<int>`
   documented as "last 7 days, oldest first". `SeriesCard` derives the day
   labels from the clock and that contract. A server that ever returns a
   different window, or a gap, would label the bars wrongly. The series should
   carry its own `from`/`to`, or one date per reading.
3. **A stated unit on the stock series.** «الاستهلاك اليومي» is documented as
   "consumed units per day" and is drawn as a unitless count. If items are
   ever counted in mixed units, the figure stops being addable.
4. **An attendance series on the statistics tab.** `DetachmentStats
   .attendanceSeries` exists, is seeded, and is rendered only by the PDF
   report builder. Showing it needs a product decision about whether it
   duplicates the attendance section below it — not more data.
5. **Historical roster size.** The glance line reports today's roster count;
   no repository carries what it was, so no trend is claimed.

### Phase 3B — original continuation list (completed above)

Everything below is adoption and copy, not design. The patterns exist and are
documented in `docs/FRONTEND-DESIGN-NOTES.md` §"The tenant surface".

1. **Tenant bottom-navigation semantics** — port the platform bar's wrapper
   (`core/widgets/glass_bottom_nav.dart`). Audit item 2.
2. **Shifts visual polish** — re-inspect the day strip; `AppMeta`/`AppTime`
   for the shift card meta lines; class C of the measure policy (the week
   grid stays uncapped).
3. **Workshop register** — adopt the Team roster pattern wholesale
   (`workshop_people.dart`); the `·` in the seats line becomes `AppMeta`.
4. **Tenant `IconButton` semantics** — tooltips/labels on bare icon actions.
5. **Settings hub** — merge single-row sections; one subscription door.
6. **Organization / Plan** — minor polish; both already have a measure.
7. **Pricing** — the duplicated `pricingFullAccess`; `'٪'` → `AppNumber
   .percent` in `pricing_copy.dart`.
8. **Session Expired** — de-duplicate the copy; move the literal into `S`.
9. **Themes terminology** — «الثيمات» → «السمات».
10. **Inventory** — a "filter matched nothing" state; the shared filter
    control.
11. **Workshop `clockProvider`** — `workshop_stats_tab.dart` and its
    providers still read the wall clock.
12. **Adopt `AppMeta` / `AppTime` / `AppNumber` and the measure policy** on
    Detachments, Team, Inventory, Workshops, Notifications. The remaining
    `'٪'` literals are in `detachment_list_page.dart`,
    `detachment_group_list_page.dart`, `detachment_member_status_page.dart`,
    `report_builder.dart`, `pricing_copy.dart` and
    `platform_commerce_page.dart`.
13. **Eight strings in `l10n/strings.dart` are now unreferenced** and were
    left in place deliberately, because removing product copy is not a
    layout pass: `last7Days`, `dashboardQuickActions`, `dashboardAllClear`,
    `dashboardOrgSection`, `dashboardActiveDetachmentsNone/One/Many`,
    `dashboardOpenDetachments`, `dashboardOrgAttention`,
    `dashboardAssignedOf`. Delete them once 3B confirms nothing wants them
    back.
14. **`AnimatedTabBar` still divides its width equally.** Once its labels
    stopped rendering as boxes it became visible that a long tab name
    ellipsises at 1.6× («الفريق وأدواره» → «الفريق أ…»). A strip that
    scrolls instead of dividing is the real answer and is a change to how
    the detachment and workshop shells *navigate*, which is why 3A stopped
    at the ellipsis.

---

## UI QUALITY PROGRAMME — PHASE 2: SUPER ADMIN (COMPLETE, 2026-09-20)

Phase 2 of the three-phase programme that follows `UI-AUDIT-REPORT.md`. The
**Super Admin / Platform surface only** — Main Admin is Phase 3 and was not
touched. Built entirely on the Phase 1 primitives; none of them was replaced
and no new framework was added.

Baseline was 2384 tests green; this work leaves **2384 / 2384 green**,
`flutter analyze` clean, `git diff --check` clean.

---

### A. What changed, screen by screen

#### Platform Overview `/platform` — P1-6

The page opened with a 52 dp tinted tile, «منصة ليدر» and a lead paragraph —
about 270 px of chrome above an app bar that had already said «المنصة», so on
a 390 × 844 phone «يحتاج إلى انتباه» landed at the fold. Now:

* a **status strip** first: the health chip, how old the reading is, and one
  refresh control. It also carries «لا شيء يحتاج إلى قرار» when the attention
  list is empty, so the negative answer is given without an empty card;
* the **attention list** immediately after it — about 17 % down instead of 36 %;
* **three weights of figure** instead of five identical tiles, every one of
  which used to draw its number in `c.primary` including the count of
  customers in trouble. The two an operator can act on lead (`_SignalTile`:
  tenants requiring attention, running demos) and carry severity derived from
  the *kind* of trouble — `crit` when a team is suspended or pending deletion,
  `warn` in a grace window, deliberately quiet at zero. The three that
  describe the size of the business are one `_ScaleCard` of label↔value rows.
  **Every figure the audit asked to keep is still on the page**;
* health, usage and recent activity unchanged below, still reflowing to two
  columns above 620 dp.

`_UsageSection` stopped dividing bytes by 1 GiB with `~/` (anything under a
gigabyte read «٠ غ.ب من ٢٠ غ.ب») and calls the shared `tenantBytesLabel`.

#### Platform Operations — P2

Seven identical rows, each repeating its destination's own lead paragraph,
became **five groups**: المراقبة / العملاء والتجارب / الجانب التجاري /
المراجعة والتدقيق / صلاحيات حسّاسة. Short purpose lines replaced the borrowed
paragraphs. The two rows with synchronous local state carry a count — running
trials, live promotions — as a numeral chip with a spoken plural label, because
a badge has to stay narrow in a navigation row at a 1.6 text scale and «١»
alone tells a screen reader nothing. Health and Security are network-shaped and
are **deliberately not read here**: a navigation index that spins before it can
be navigated is worse than one that describes itself.

**Emergency access is last and alone**, under a heading that says what opening
it means, with a `crit` glyph, a chip while a grant is live, and one sentence
underneath. Not a tinted card and not a banner — the danger zone at the bottom
of the page, which is hierarchy rather than decoration. **No route changed, no
destination was invented, and no authorization moved**: the screen behind that
row still refuses on its own.

#### Commerce / Offers / Coupons — P1-7

**The UI, not the domain.** $6 / $14 / $24 / $40, full access on every
duration, promotions on one and three months only, no stacking, no redemption,
no payment — all unchanged.

* the popup menu offers **verbs** («تعطيل» / «تفعيل» / «حذف العرض»); the state
  adjective stays on the chip, which is what it is;
* the `StatusChip` left `ListTile.leading`. A row is title (or coupon code,
  LTR-isolated) + state chip, then one metadata line of the facts an operator
  actually compares by — duration, discount, final price, public/targeted, and
  the account when targeted — then one labelled menu;
* **one create affordance per list**, a `SectionHeader` action with a `+`
  glyph, instead of two full-width `FilledButton`s competing mid-scroll;
* the confirmation's "what does not change" is real copy now, not the page's
  own description paragraph; **removal is `destructive`**, disabling is
  `warning`, enabling is `normal`, and each carries the record's identity;
* base pricing reads as an **admin view**: label↔value rows with the effective
  monthly price (shown only where it differs from the total), not four
  marketing cards;
* the two editors gained section headings, `kFormMaxWidth`, a **live price
  preview** computed with the domain's own `applyDiscount`, an availability
  switch whose title is no longer the same word as its subtitle, and one
  primary save beside a secondary «إلغاء»;
* **the build note stays** at the foot, unchanged. The build does not take
  payment and the panel says so once, quietly.

#### SaaS Tenant Detail — P1-8

Six full-width buttons, three of them filled, with "suspend this customer"
styled exactly like "open the subscription page". Four of the six were
navigation and are now `NavigationRow`s inside the card they belong to. **The
only buttons left on the page are the two that change state**, and they are
the lifecycle section's — which the audit calls CLEAN and which was not
otherwise touched.

The four muted footnotes moved *inside* the cards they annotate (`_Section`
became a `Material` with an optional note and optional full-bleed rows, so a
`ListTile` inside it paints its ink correctly). The identity card leads with
the name, the lifecycle chip and the subscription line, then the Team Code
(copyable, one copy button on the page), then the tenant id — **labelled
«المعرّف»**, kept because routing to a team by id is real Super Admin work
(§24), and never the hero identity.

#### Platform Audit Log — P2

Grouped by local calendar day, newest first, with the two most recent days
**named** («اليوم» / «أمس») rather than dated. The full date left the row and
only the clock stayed. Three weights per row: what happened / who and to whom /
category. The before→after line became words — «الحقل: من X إلى Y» — with each
value LTR-isolated, which removes the bidi ambiguity a Latin digit pair around
`←` inside an Arabic paragraph had about which value was old; integer values
now render Arabic-Indic like every other figure in the product. Rows gained a
`ForwardChevron`, because they have always opened a detail sheet.

«تصفية» is a content-width button now. It was full-width because the theme's
`minimumSize: Size.fromHeight(48)` is `Size(double.infinity, 48)` — the same
bug the reports filter button had, and both are fixed.

#### Platform Security and Platform Health — P2 / P3

«٢٠٢٦/٠٩/٠٨ · ١٥:٠٤ UTC» became «٨ أيلول ٢٠٢٦ | ١٥:٠٤ بتوقيت UTC».
**The instant is unchanged and still UTC** — two operators comparing an
incident need the same number — but it is written in the product's own date
shape with the timezone named in Arabic. Each alert is one severity chip with
the category and time as plain metadata, instead of two differently-shaped
chips stacked above the title; the affected tenant is a compact context strip
with its id still labelled. Both pages lost the duplicate refresh affordance:
the app-bar icon is gone and one control sits on the card that carries the
reading it refreshes, keeping its widget key and gaining a tooltip.

#### Tenants list, Demo Management, Reports — P2

* **Tenants**: rows gained a `ForwardChevron`, the subscription date and Team
  Code became one metadata line, and the FAB is flat like every other surface.
  The filters were already `AppFilterBar` from Phase 1 and were left alone.
* **Demo**: the session row is name + `StatusChip` (which changes *word* under
  an hour, not only colour) and one metadata line with the remaining time
  leading and emphasised — `PlatformDemoCopy.sessionStatus` existed and had
  never been called. The list was **already** sorted by what expires soonest,
  and `activeDemoSessionsProvider` says why, so no sort was added. Nothing
  about the policy, the confirmations or the two maintenance operations
  changed.
* **Reports**: the catalogue uses `NavigationRow` with the report's data kind
  as the row badge. The four report pages got a light pass only — the filter
  button width, an Arabic-Indic filter count, and the row facts moved onto
  `PlatformMeta`.
* **Tenant Features**: the switch moved onto the title's line, and the
  consequence sentence appears only while the feature is *on* — that is, only
  while the switch is about to turn it off.

---

### B. Two new platform primitives

#### `PlatformPageIntro` — `widgets/platform_page.dart`

Replaces `PlatformSectionHeader` on all nine pages that used it. One lead
sentence; no 52 dp tile, no heading that repeats the app bar. **The rule: the
app bar states the page, the body states what the page is for.**

#### `PlatformMeta` / `PlatformMetaText` / `PlatformTime` — `widgets/platform_meta.dart`

P1-11's answer on this surface. ` · ` and `٠` (U+0660) are the same mark to a
reader, and a control plane renders both constantly — «١ سماح · ٠ موقوف · ٠
بانتظار الحذف» is five identical dots of which three are values.

**The first design was a painted dot, and its own render rejected it**: a dot
beside «٠» is still two dots. The separator is now a **1 dp vertical hairline**
whose height follows the text scale, drawn outside the text run. It cannot be
read as a numeral, selected, copied into a ticket, or announced. It attaches to
the *following* item, so a wrapped line never starts with an orphan mark, and
each item is `Flexible` so a long fact wraps instead of overflowing the row it
is glued to.

`PlatformTime` is the surface's timestamp vocabulary: `date` / `time` /
`dayTime` for a local instant, `utcDate` / `utcTime` / `utcSpoken` for a
snapshot. `dayTime` exists because `AppDate.dayMonthTime` joins a date and a
clock with ` · ` and the clock very often begins with «٠»; the shared helper is
left alone because the tenant surface reads by it and that is Phase 3.

Where the layout genuinely could not change — a plain string handed to a
label/value field — the mark became « — », never a second kind of dot: the
audit detail timestamp, the report freshness lines, the usage-limits override
note, the tenant-detail storage line.

---

### C. Three defects Phase 2 found that the audit had not

1. **`AppTypography.build` never defined `labelSmall`.** Material's `ListTile`
   uses it for the `trailing` slot, so anything placed there inherited Roboto
   instead of the app family — and an Arabic-Indic digit rendered as a
   **placeholder box**. Caught on the Operations landing, where the
   running-trials count drew as tofu. `labelSmall` is defined now, and
   `StatusChip` paints `AppTypography.chip(c)` rather than inheriting whatever
   `DefaultTextStyle` it lands in. Both are `core/`, both affect the tenant
   surface too, and both are strictly fixes.
2. **`OutlinedButton.styleFrom(minimumSize: Size.fromHeight(48))` is
   `Size(double.infinity, 48)`.** That is why the audit log's one-word
   «تصفية» and the reports' filter button each occupied the full width of
   the page. Both now pass `Size(0, 48)`.
3. **A `NavigationRow` badge in the trailing slot takes width from the
   title.** At 320 dp and a 1.6 text scale the reports catalogue rendered
   «الاشتراكات» and «الاستخدام والحدود» broken across lines **mid-word** — no
   overflow exception, so only the render showed it. Past that scale the badge
   moves under the subtitle, where it has the whole row.

All three were found by looking at the pictures, which is the argument for
rendering at all: none of them threw, so no widget test could have caught
them.

---

### D. Small additions to shared widgets

* `NavigationRow` gained `iconColor` (for a destination that carries
  consequence) and `badge` (live state between the text and the chevron). The
  chevron is never replaced — the row still opens something.
* `SectionHeader` gained `actionIcon` and `actionKey`, so a create action can
  carry a `+` and a test can tap the button rather than the row.
* `StatusChip` and `AppTypography` — see C above.

Nothing else in `core/` changed.

---

### E. Rendering and inspection

`test/features/platform/platform_render.dart` gained a **`render Phase 2 Super
Admin screens`** group — same harness, same personas, no new framework.
39 shots: every redesigned screen at 390 dp, the two commerce editors (which
had **no** render coverage before this phase), light / eye-protect / an
alternate palette, 600 dp and 900 dp on the four screens that reflow, and a
**320 dp / 1.6× group over eleven screens** which is a real overflow gate
because `shot` asserts `takeException() == null`.

```
MTM_RENDER_DIR=/tmp/leader-phase2 flutter test \
  test/features/platform/platform_render.dart --tags render --update-goldens
```

The renders were read, not just produced. Five fixes came out of looking at
them: the tofu badge (C1), the reports catalogue's broken words (C3), the
painted-dot separator, a coupon's account line whose colon printed on the wrong
side of «الحساب» because the whole phrase had been isolated rather than just
the identifier, and the tenant identity dates, which wrapped mid-phrase at
320 dp / 1.6× as one metadata line and are two quiet lines instead.

---

### F. What Phase 2 deliberately did not touch

* **Main Admin.** Home, Detachments, Team, Shifts, Inventory, Statistics,
  Workshops, Notifications, Sync, tenant Settings — none of them. Phase 3.
* **Login, Signup, OTP, Team Code, the demo chooser, the user pricing page.**
* **The CLEAN platform screens** (§44): tenant lifecycle suspend/delete,
  Break-glass, Platform More/Profile. `BreakGlassCopy.operationSummary` still
  joins with ` · ` and `platform_more_page` still joins its appearance summary
  the same way; both are on CLEAN screens and neither puts the mark against a
  bare figure.
* **`AppDate.dayMonthTime`**, which both surfaces read by.
* **The five unlabelled `IconButton`s.** §42 asked for the Platform instances
  first — there are none; every `IconButton` under `features/platform/` was
  already labelled. The one unlabelled platform control found was the commerce
  row's `PopupMenuButton`, which now has a tooltip. All five audit entries are
  tenant-side and remain open.
* **Latin digits in `S.pricingThreeMonths`** («3 أشهر») and its siblings — that
  copy is shared with the customer-facing pricing page and is Phase 3.

---

### G. Phase 2 rulings that are Claude-provisional

Pending Ahmed; each is a small change if he disagrees.

1. **The separator is a vertical hairline**, not a character. A « — » was the
   alternative, and is what the four string-only cases use.
2. **UTC is named in Arabic** («بتوقيت UTC») rather than kept as the bare Latin
   token. The instant and its timezone are unchanged.
3. **The two most recent audit days are named** («اليوم» / «أمس») instead of
   dated.
4. **Emergency access is last** on the Operations landing rather than first.
   Danger zone at the bottom; the alternative reading is "most consequential
   first".
5. **The operations count badges are numerals** with a spoken plural label,
   rather than «١ جلسة نشطة» on the chip itself.
6. **The tenant id was added** to the tenant detail identity card, labelled.
   §22 lists "tenant identifier" as identity content and §24 says label it, but
   the page did not previously show it.
7. **The commerce section create actions are `SectionHeader` text buttons**
   rather than a single page-level FAB. `PlatformPage` has a FAB slot, but the
   page has two distinct create actions and a FAB may only be one.
8. **The base-price monthly equivalent is hidden on the one-month option**,
   where it would be the same figure twice.
9. **The feature consequence sentence shows only while the feature is enabled.**
10. **The overview's "nothing needs attention" answer lives on the status
    strip**, not as an empty attention card — §7B says the attention block is
    for when something *does* need attention.

---

### H. Ready for Phase 3 — the Main Admin findings still open

In the audit's own order of impact per unit of work:

1. **P1-2 — the tenant bottom navigation has no semantics.** Three of four
   destinations are unlabelled icons with no announced selection state, on the
   bar that is present on every tenant screen. The fix already exists in the
   repo: `platform_navigation.dart`'s `Semantics(selected:, label:, button:)`
   wrapper. *(small)*
2. **P1-10 — the statistics sparklines cannot be read.** Seven bars normalised
   to the series maximum, no day labels, no axis, no fixed scale, so 40/42/41 %
   draws identically to 90/95/92 %. Also the `'٪'` literal. *(small)*
3. **P1-1 leftovers — none.** Chevrons were closed in Phase 1.
4. **P1-11 on the tenant surface** — the ` · ` separator wherever it can
   neighbour a figure, including `AppDate.dayMonthTime` itself.
   `PlatformMeta` / `PlatformTime` are the pattern to promote. *(medium)*
5. **P1-9 — Main Admin Home answers the wrong question.** Decide what Home is
   (organisation-wide or this-detachment), then design the quiet day as a
   first-class state. Depends on 1, 5 and 6 of the audit's order, all done.
   *(large)*
6. **P1-5 leftovers — Home, Detachments, Team, Shifts, Inventory, Statistics
   and Workshops are still uncapped**; `ReadingColumn` exists and is applied
   elsewhere. *(medium)*
7. **The workshop register** — adopt the Team roster pattern (search, filter
   sheet, active chips, a "filter matched nothing" state). *(medium)*
8. **The five unlabelled `IconButton`s** — `workshop_list_page.dart:54`,
   `_auth_scaffold.dart:30`, `mfa_setup_page.dart:221`,
   `inventory_item_edit_page.dart:445`, `capability_guard.dart:145`. *(small)*
9. **Settings hub** — merge the single-row sections, one subscription
   destination, «المزامنة» not used as both heading and row. *(small)*
10. **Organization** (~60 % empty at 390 dp), **Pricing** (states
    `pricingFullAccess` twice), **Session Expired** (says it twice, second
    sentence a raw literal), **Themes** («الثيمات» → «السمات»), the dead
    `OfflineBanner(visible: false, …4)` in the workshop shell, and
    `workshop_list_page._apply` reading `DateTime.now()` instead of
    `clockProvider`. *(small, each)*

---

## UI QUALITY PROGRAMME — PHASE 1: FOUNDATION (COMPLETE, 2026-09-20)

Phase 1 of the three-phase programme that follows `UI-AUDIT-REPORT.md`.
**Foundation only** — one real bug, one navigation rule, four shared
primitives, a copy pass and a render harness. No screen was redesigned.
Phase 2 is the Super Admin pass; Phase 3 is the Main Admin pass.

Baseline was 2318 tests green; this work leaves **2384 / 2384 green**,
`flutter analyze` clean, `git diff --check` clean.

---

### A. The `copyWeek` DST bug (P0-class, confirmed in production code)

`MockShiftRepository.copyWeek` mapped each source shift onto
`to.add(Duration(days: s.date.difference(from).inDays))`. Both halves are
**absolute-time** arithmetic on values that are **calendar dates**:

* `difference(...).inDays` truncates, so in a source week containing a
  spring-forward day two different source days report the same offset and
  **collapse onto one target day** — one day of the week is silently lost.
  Reproduced: copying the week of 2025-03-09 under `TZ=America/New_York`
  produced six distinct dates from seven.
* `to.add(Duration(days: n))` into a target week containing a transition
  lands at **23:00 the previous day**. That value is no longer a normalized
  date, so `_exists` stops recognising it (copying twice duplicates the week)
  and every `s.date == day` read in the app — `listForWeek`, the day strip,
  the report builder — misses it.

**The rule, stated once:** `lib/core/time/calendar_day.dart`.

```dart
DateTime dateOnly(DateTime d);              // local midnight
DateTime addDays(DateTime d, int days);     // DateTime(y, m, d + n)
int calendarDaysBetween(DateTime a, DateTime b); // via UTC, exact
```

`shift_models.dart` re-exports all three, so the 28 files that already
imported `dateOnly` from the domain are unchanged. `copyWeek` now reads
`dayFor: (s) => addDays(to, calendarDaysBetween(from, s.date))`.

Local dates stay local — nothing was converted to UTC to dodge the problem,
because these are the dates people work shifts on.

**Every other date-valued `Duration(days:)` in the schedule was fixed with it**
(they are the same bug waiting for a different week): `startOfWeek`,
`_dayOfWeek`, `listForWeek`'s exclusive bound, `listForRange`'s bound,
`WeekQuery.shifted`, the repeat-days grid, the day strip and week arrows,
`copyDay`'s "previous day", the correction date-picker bounds, the report
builder's range start and day labels, the statistics and member-status range
starts, `AppDate.weekRange` and `AppDate.daysFromNow`.

**Deliberately not changed:** the two attendance-timestamp normalisations in
`mock_shift_repository.dart` (`normalized.add(const Duration(days: 1))` for an
overnight check-out). Those move an *instant*, not a date, and whether an
overnight shift's 02:00 check-out should keep its wall clock or its elapsed
hours across a DST change is a product question, not a mechanical one. Noted,
not guessed at.

**Coverage.** `test/core/time/calendar_day_test.dart` and
`test/features/shift/copy_week_dst_test.dart`. Both discover the host
timezone's real transitions (`test/core/time/dst_zones.dart` walks local
midnights and reads the UTC offset — no timezone package added) and skip the
DST groups in a zone that has none. Verified green under **EDT (host),
Europe/Berlin, America/New_York, Australia/Sydney, UTC and Asia/Baghdad**, and
verified **red** against the old formula.

---

### B. RTL forward navigation

`Icons.chevron_left_rounded` and `chevron_right_rounded` both declare
`matchTextDirection: true`, so Flutter mirrors them under RTL. Starting from
`chevron_left` therefore paints a **right**-pointing chevron in Arabic — the
glyph for *back* — on a row that opens a detail page.

**The rule:** `lib/core/widgets/forward_chevron.dart`.

* `ForwardChevron` — forward disclosure. Always `chevron_right_rounded`.
* `DirectionalArrows.earlier` / `.later` — a timeline, not a hierarchy.
* No `Transform.flip`, no `if (rtl)` at a call site, ever.

**15 surfaces fixed** — the 13 the audit listed, plus `NavigationRow` and
`link_team_page` migrated onto the primitive (they were already correct, and
are now correct *by construction*), plus the **swapped week arrows** in the
shifts tab, whose comment also misstated how the mirroring works.

Tests: `test/core/widgets/forward_chevron_test.dart` resolves the mirroring
and asserts what the glyph **physically points at** in each direction, and
that it mirrors exactly once (a double flip renders identically in both
directions, which is the failure mode a constant-equality test cannot see).
`design_system_guard_test.dart` fails the build if any file outside
`forward_chevron.dart` names a rounded chevron again.

---

### C. Shared UI foundation

#### One section header — `lib/core/widgets/section_header.dart`

Five spellings existed: `SectionHeader`, Settings' `SectionLabel` (identical
typography, different padding), three byte-identical private `_SectionTitle`s
on platform pages, and `workshop_people`'s own.

`SectionHeader(title:, icon:, action:, onAction:, style:)` with two styles —
`label` (the eyebrow) and `heading` (`titleMedium` + tinted icon). It is
announced as a heading, which only the two organisation screens used to be.
**No subtitle slot**: nothing has ever needed one, and an unused slot is one
the next screen fills wrongly.

`AppTypography.eyebrow` is now the token it paints (tracking aligned 0.7 →
0.6, which is what all ~55 call sites already wrote; the one previous caller
overrides letterSpacing and is unaffected). Nine more hand-spelled copies of
`ink3/12/w600/0.6` across eight files were replaced with the token — same
pixels, one definition.

`SectionLabel` is kept as a name (≈40 call sites, and it reads as the settings
idiom) but is now a one-line delegate.

*Intentionally retained:* `platform_break_glass_page._SectionTitle` — a
`titleSmall` sub-heading **inside** a card, a genuinely different level from a
page section heading. Migrating it would have changed 13 sp → 17 sp on a
screen the audit calls CLEAN.

#### One filter control — `lib/core/widgets/filter_chips.dart`

`AppFilterChip` + `AppFilterBar`. **Category A only** — filtering a dataset.
Explicitly not a form value, not a status action, not the Team roster's
multi-select sheet.

Six implementations retired: `detachment_list_page._Filter` and
`workshop_list_page._Filter` (byte-identical copies),
`detachment_storage_tab._Chip`, `workshop_members_tab._FilterChip`,
`global_search_page._Chip`, and `platform_tenants_page._FilterChip` (a
Material `ChoiceChip` with the **opposite** selected treatment — tinted fill
and brand label where the tenant side used a solid fill; that is P1-4's "two
surfaces, two products", now one).

The bar **wraps**. Two surfaces used to scroll horizontally with a hard clip:
the platform tenants list lost its sixth chip off the edge with no affordance,
and the storage tab clipped its third. Both now wrap; the storage tab keeps
its add-button-outside-the-bar layout, which was a deliberate choice.

*Intentionally retained:*
* `detachment_team_tab._FilterGroup` — Material `FilterChip` with a checkmark,
  multi-select, inside the filter sheet. Additive-and-several reads
  differently from exclusive-and-one, and the checkmark is what says so. The
  audit also names this screen the pattern to promote, not to change.
* `platform_report_widgets._FilterButtonRow` — a button that opens a sheet.
* `dashboard_cards._Pill` — a `StatusChip` alias, not a filter.
* `ChoiceChip` in `inventory_item_edit_page` and `announcement_compose_page` —
  form values.

`global_search_page._Chips` was renamed `_CategoryFilters` (it is the bar, not
a chip).

#### One confirmation — `lib/core/widgets/confirmation_dialog.dart`

`showAppConfirmation` is the platform's dialog, lifted into `core/`
unchanged: identity on its own selectable line, **what changes**, **what does
not**, optional **when**, and the severity on a *filled* button
(`normal` / `warning` / `destructive`) rather than a crit-coloured
`TextButton` sitting at equal weight beside «إلغاء».

`showPlatformConfirmation*` are now thin wrappers; `PlatformConfirmationSeverity`
is a `typedef` of `ConfirmationSeverity`, and a `keyPrefix` parameter keeps the
platform's `platform-confirmation-*` widget keys, so **no platform call site
and no platform test changed**. `showPlatformFinalDeletionConfirmation` stays
on the platform side — it is the tenant-deletion flow, not a primitive.

Adopted in four representative tenant destructive flows: **delete member**,
**delete stock item**, **archive workshop** (`warning`, because «استعادة
الورشة» undoes it), **cancel Simple Admin invitation** (`destructive`, LTR
identity, dismiss relabelled «تراجع» so two buttons do not both say «إلغاء»).
Nine more tenant `AlertDialog`s are listed in the guard's allowlist with why —
most are not confirmations at all.

#### One measure scale — `lib/core/widgets/reading_column.dart`

```dart
const kDialogMaxWidth  = 420; // a dialog body
const kFormMaxWidth    = 440; // a column of inputs  (was Login's own constant)
const kReadingMaxWidth = 520; // label↔value rows, facts, cards
const kContentMaxWidth = 720; // a working column    (was kPlatformContentMaxWidth)
```

`ReadingColumn` caps and centres, top-aligned. `kPlatformContentMaxWidth` is
now an alias and `PlatformPage` uses the primitive, so the two surfaces share
one number instead of agreeing by coincidence.

Applied to **Settings hub, Themes & Appearance, Sync, Pricing** (each a single
column of label↔value rows), and to **Organization** and **Plan** through a new
`OrganizationPageWidth`: the cap applies below `OrganizationColumns.breakpoint`
and **lifts above it**, so the 760 dp two-column reflow those two screens
already had is preserved. Verified in the renders: `11-plan-600-light.png` is
now a 520 dp centred column (the audit's «~1 000 px of nothing» is gone) and
`11-plan-900-light.png` still splits into two columns.

---

### D. Copy cleanup

| Was | Now |
| --- | --- |
| «فرق SaaS» (Overview metric) | «الفرق المشتركة» |
| «الخادم هو جهة التخويل والتدقيق.» | «التخويل والتدقيق يتمّان في المنصة، لا في هذا التطبيق.» |
| «…ضمن لقطة التطوير» ×2 (Security alerts) | «…في آخر لقطة متاحة» |
| «٨ فريق» | `tenantResultCount()` — «فريق واحد / فريقان / ٨ فرق / ١١ فريقا» |
| «معرّف المؤسسة: `saas_hilal`» (tenant admin) | «الرقم المرجعي للدعم: `HILAL`» |
| Commerce: `StatusKind.warn` chip «تطوير / اختبار فقط» under the page title | a `PlatformNoteCard` at the foot |
| Commerce lead: «إدارة محلية للاختبار فقط…» | «الأسعار والعروض والكوبونات التي يراها العملاء عند الاشتراك.» |

**Deliberately retained as operational metadata:** the tenant id on Platform
Security — but now **labelled** («المعرّف: saas_hilal») instead of a bare slug
floating under a team name. Routing to a tenant by id is real Super Admin
work; §25 says label it, not hide it.

**Truthfulness preserved on Commerce.** The build does not take payment, and
the new note says so («تُحفظ هذه الإعدادات محليا في هذا الجهاز، ولا يتم عبرها
أي دفع…»). What changed is its *hierarchy* — a warning chip directly under the
title made the whole commercial panel read as a test build.

`OrganizationCopy.supportReference()` strips a leading `saas_`, uppercases and
hyphenates. **The underlying identifier is untouched** — nothing in the
domain, the router or the wire sees this, and the distinctive part is
preserved verbatim so support can still find it. Copy copies what is shown.

---

### E. Tenant render harness — `test/features/tenant/tenant_render.dart`

The audit's work item 0. It reuses `platform_harness.dart` (same
`appRouterProvider` boot, same personas, same `settlePlatform`) and a new
shared `test/features/render_fonts.dart`; it adds no framework. PNGs go to
`MTM_RENDER_DIR` and the tests skip when it is unset, so nothing is committed.

```
MTM_RENDER_DIR=/tmp/leader-tenant flutter test \
  test/features/tenant/tenant_render.dart --tags render --update-goldens
```

**51 renders**: 15 screens (Home, Detachments, Team, Shifts, Storage,
Statistics, Workshops, Settings, Themes, Organization, Plan, Pricing,
Notifications, Needs Review, Sync) at 390 dp light **and** at 320 dp / 1.6×;
six of them at 600 and 900; dark, eye-protect, teal, copper + reduced motion;
and three as a Simple Admin. Every shot asserts `takeException() == null`, so
the 320/1.6× group is a real overflow gate, not just a picture.

**It earned its keep on the first run**: it found a previously unknown
overflow — the shifts day strip's fixed `SizedBox(height: 74)` clipped the
coverage dot and overflowed by 21 px at 320 dp / 1.6×. The height now follows
`MediaQuery.textScalerOf(context)`. That is a sizing fix, not a redesign; the
audit had flagged this exact strip for "re-inspect at 320 dp with a render
harness".

**Remaining render gaps:** the workshop detail tabs, the detachment/member/
inventory edit forms, the report composer and preview, and the conflict
resolution page. All are pushable into the same `shot()` when a phase needs
them.

---

### F. Design-system guard — `test/core/design_system_guard_test.dart`

Seven source-level rules, each naming the offender, the rule and its escape
hatch: no hand-picked directional chevron, no `Transform.flip`, no
re-spelled eyebrow style, no new private filter pill, no new bare
`AlertDialog` outside a shrinking allowlist, no invented content max-width,
and no absolute `Duration(days:)` on a date in the schedule. A widget test
cannot catch a *new* file doing the wrong thing; this can.

---

### G. What was NOT redesigned

Platform Overview, Platform Commerce, SaaS Tenant Detail, Main Admin Home,
Statistics and Shifts were **not** redesigned. Every change to them was a
compatibility change to adopt a shared primitive, a copy fix, or the day-strip
overflow.

Still open for Phase 2 / Phase 3, unchanged in `UI-AUDIT-REPORT.md`:
the `·` / `٠` collision (P1-11, 115 places), the tenant bottom nav's missing
semantics (P1-2), Platform Overview's hero block and equal metric tiles
(P1-6), Commerce's verbs/chip placement/create affordance (P1-7), Tenant
Detail's six full-width buttons (P1-8), Main Admin Home's question (P1-9), the
unreadable statistics sparklines (P1-10), the Audit Log pass, the Workshop
register, the machine timestamps with `UTC`, and the five unlabelled
`IconButton`s.

---

### H. Phase 1 rulings that are Claude-provisional

Pending Ahmed; each is a one-line change if he disagrees.

1. **The support reference format.** `saas_hilal` → `HILAL`. The audit said
   "a customer-facing account number or nothing"; this keeps the information
   and drops the internal shape without inventing an identifier. A real
   account number would be a backend decision.
2. **Commerce's build note wording and placement** — truthful and at the foot,
   rather than a chip under the title or removed entirely.
3. **`kReadingMaxWidth = 520`** as the tenant default. It is the value
   `status_screen.dart` already used; 560 or 480 are defensible.
4. **Archiving a workshop is `warning`, not `destructive`** — it is reversible.
5. **The multi-select Team filter sheet keeps Material `FilterChip`s** rather
   than being folded into `AppFilterChip`.
6. **Break-glass keeps its own `titleSmall` sub-heading** rather than adopting
   `SectionHeaderStyle.heading`.
7. **The Arabic plural forms** in `tenantResultCount` («لا فرق / فريق واحد /
   فريقان / ٨ فرق / ١١ فريقا»).
8. **`AppFilterBar` wraps everywhere**, including on the platform tenants list
   whose comment argued for horizontal scrolling at 320 dp. The audit's
   evidence (a chip clipped out of reach) outweighed it.

---

### I. Ready for Phase 2

The primitives the Super Admin redesign can now consume:

* `ForwardChevron` / `DirectionalArrows`
* `SectionHeader` (`label` / `heading`) + `AppTypography.eyebrow`
* `AppFilterChip` / `AppFilterBar`
* `showAppConfirmation` + `ConfirmationSeverity`
* `ReadingColumn` + the four-stop measure scale
* `addDays` / `calendarDaysBetween` / `dateOnly`
* `tenant_render.dart` and `render_fonts.dart`
* `design_system_guard_test.dart`, which makes the rules enforceable

---

## BRAND MARKS & THE GREEN/GLASS LOGIN (2026-09-19) — **PARTLY SUPERSEDED**

> Superseded by "THE ENTRY EXPERIENCE (IMPLEMENTED, 2026-09-22)" at the end of
> this file. Still true: the launcher icon and why it is fixed, the
> green/glass direction, the blur budget, the Google skin, the `S.loginTitle`
> / `S.loginSub` / `S.signIn` strings, and the `LoginField.keyFor` gotcha.
> **No longer true:** the three-mark catalogue, `BrandLogo`, `ThemeState.logo`,
> the `شعار ليدر` picker and its six strings, `login_glass.dart`/`LoginGlass`,
> and Login's mark-plus-wordmark header.

### What shipped

**Three Leader marks, one of them fixed to the launcher.** The approved
artwork from the brand sheet is now bundled and typed:

| `BrandLogo` | Concept | Asset | Label |
| --- | --- | --- | --- |
| `cleanLayer` | `06 · Clean Layer` (teal) | `assets/brand/leader_logo_clean_layer.png` | `الطبقة النظيفة` |
| `elegantCurve` | `14 · Elegant Curve` (gold) | `assets/brand/leader_logo_elegant_curve.png` | `المنحنى الأنيق` |
| `depth` | `07 · Depth` (blue) | `assets/brand/leader_logo_depth.png` | `العمق` |

`lib/core/brand/brand_logo.dart` is the only place an `assets/brand/…` path
is spelled. `cleanLayer` is the default, the fallback for anything
unreadable, and the artwork the Android launcher icon is generated from.

**The launcher icon is NOT a preference, and must not become one.**
`android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` is an adaptive
icon: `@color/ic_launcher_background` (`#FF081F26`, sampled from the mark's
own ground) under `@mipmap/ic_launcher_foreground` (the Clean Layer mark at
0.55 of the 108dp canvas, generated per density). Legacy `ic_launcher.png`
covers mdpi→xxxhdpi. The old stock Flutter mark is gone. Android can only
swap a launcher icon by toggling activity-aliases, which drops the user's
placed shortcut and widget — so this is fixed for everyone and only the
**in-app** mark follows the preference.

**The preference rides on `ThemeState`.** `ThemeState.logo` is persisted with
palette/mode/eye-protect under the existing `mtm.settings.theme` key, by
**name**, and `BrandLogo.fromName` falls back to Clean Layer for a missing,
legacy or corrupt value. It is there rather than in a store of its own
because the mark is needed on the first painted frame and `themePrefs()` is
already the one launch-path read without simulated latency. It is cosmetic:
it reaches no auth, role, capability, demo, tenant, plan or wire decision.
Picked in Settings → `الثيمات والأداء` → `شعار ليدر` (`BrandLogoCard`,
`brand-logo-<name>` keys), directly below the palette/comfort/appearance
block and above performance.

**Login is the green/glass design.** `login_glass.dart` holds the whole
palette — ground gradient, three ambient washes, accent, ink roles, glass
fill/border/sheen, field fill/border, hairline, shadows — as two token sets
(light + dark) converted once from the design's oklch values, with the
source value in the comment beside each. It is **scoped to Login**; no other
screen may read it and it is not an `AppColors` palette. Eye Protection runs
the same ground-only warm transform `AppColors.warmed()` uses (same target,
same strength), so ink, accent and danger keep their contrast.

The screen is: the selected mark at 72×68 with a coloured glow, `ليدر`,
`مرحباً بك في ليدر`, then **one** frosted panel (r30, `BackdropFilter`
capped at sigma 15, 1px border, 1px top sheen) holding the support line, the
two fields, forgot, `تسجيل الدخول`, `أو` and Google, with sign-up just
outside it and `صنع بفخر في العراق` (the shared `MadeInIraqFooter`) closing
the screen. Blur is budgeted off `MotionSpec.blurSigma`: at the lightest
quality there is no `BackdropFilter` at all and the panel fill steps up to
stay readable. Fields are flat translucency inside the panel — never a
second blur.

### What deliberately did NOT change

- **Auth.** Same `OnboardingController`, same password call, same Google
  gateway, same three outcomes. The only refusal Login makes on its own is an
  empty field (the CTA is disabled), which reaches no server.
- **Google.** `GoogleSignInButton` gained an optional `GoogleButtonSkin` —
  fill, border, ink, progress colour, and a white plate under the mark so the
  four brand colours stay saturated over glass. Presentation only; every
  other caller passes nothing and looks exactly as before.
- **Splash.** Still the neutral windowBackground. It never carried an MTM
  mark, so there was nothing to replace.
- `assets/brand/mtm_logo_full.png` stays bundled but is no longer drawn.
  `AppInfo.logoAsset` now points at the Clean Layer mark for the three
  surfaces that draw it without a `WidgetRef` (startup, forced upgrade,
  About), and `upgrade_required_page`'s `_trim` dropped 1.16 → 1.0 because
  the new artwork has no baked-in white margin to crop.

### Strings that moved

- `S.loginTitle`: `أهلاً بعودتك` → `مرحباً بك في $productNameAr`.
- `S.loginSub`: → `سجّل الدخول لإدارة فرقك وعملياتك`.
- `S.signIn`: `دخول` → aliased to `S.login` (`تسجيل الدخول`), so the button
  and the screen cannot drift. Also used by session-expired and the
  signed-out profile row, where the longer words read fine.
- New: `settingsBrandLogoSection`, `settingsBrandLogoSectionSub`,
  `settingsBrandLogoDefault`, `brandLogoCleanLayer`,
  `brandLogoElegantCurve`, `brandLogoDepth`.

### Tests

- `test/features/settings/brand_logo_test.dart` — three marks, distinct
  assets on disk, Clean Layer default and fallback, name-keyed persistence
  including a legacy and a corrupt value, the picker's three cards and their
  previews, selection + write-through, 320dp fit.
- `test/features/auth/login_screen_test.dart` — every required element and
  every forbidden one, the password toggle's semantics, the disabled CTA,
  the selected mark (all three, plus a live change), 320/360/390/430dp,
  1.6× text, an open keyboard, 48dp targets, and all four appearances.

### Gotcha for whoever is next

Login labels its fields **above** the input, not through
`InputDecoration.labelText`, so the label-based finder the `AuthScaffold`
screens use does not match here. Use `LoginField.keyFor(S.emailLabel)`. And
Login is a full-height screen: on the 800×600 default test surface the CTA is
below the fold, so `tester.ensureVisible` before tapping it.

---

## POINT 19 — PRICING, GLOBAL OFFERS & COUPONS (IMPLEMENTED, 2026-09-16)

The Flutter/local-development scope in `PRICING-PROMOTIONS-ARCHITECTURE.md`
§20 is implemented. There is one full-access Leader product and four billing
durations: `$6 / $14 / $24 / $40` (`600 / 1400 / 2400 / 4000` integer cents).
Every duration carries the same product access; duration never changes a
capability, module or permission.

### Domain and local control plane

- `features/pricing/` now owns `Money`, the billing catalog, sealed percentage
  and fixed-final-price discounts, global offers, public/targeted coupons,
  ordered coupon validation, `PriceQuote`, and promotion resolution.
- Percentage discounts use `((baseCents * percentage) + 50) ~/ 100`. Promotions
  can target only `monthly` and `three_months`.
- Global offers and coupons never stack. The best final price wins and the
  global offer wins an exact tie. Coupon validation only calculates a display
  result; it never redeems, consumes, activates or mutates a subscription.
- `pricingCatalogProvider` is the future backend seam. The current
  `CommerceControlPlane` is deterministic, in-process **DEV / TEST ONLY** state;
  every seeded offer and coupon starts disabled.

### Product surfaces

- `/more/pricing` is the one canonical «الاشتراك والأسعار» page for tenant and
  Customer Demo sessions. It shows the four quotes, optional applied promotion,
  coupon validation, centralized Telegram/WhatsApp/email contacts, and the
  contact-only CTA «للاشتراك تواصل معنا».
- The Demo trial bar carries one «أعجبتك ليدر؟ شاهد الخطط» conversion entry to
  that same page. Its stack rule was widened before adding the third control;
  the 320dp / 2.0× path remains reachable and overflow-free. Pricing exploration
  has no tenant, subscription, payment or redemption write path.
- `/platform/operations/commerce` and its offer/coupon create/edit children are
  implemented inside the existing Operations area. Base prices are read-only;
  Super Admin can locally create, edit, enable, disable and remove eligible
  offers and public/targeted coupons.
- Platform mutation authority comes only from `platformCommerceActorProvider`
  resolving an authenticated `super_admin`. Main Admin, Simple Admin and Demo
  cannot obtain an actor. Neither `capability.dart` nor `platform_area.dart` was
  changed.
- The temporary debug Super Admin login reuses the existing hidden
  `DevTestCredentials` mechanism. It is not rendered or logged and does not
  weaken the release authentication path.

### Commercial boundary

There is still **no payment gateway, transaction processing, production
subscription activation, coupon redemption or backend commercial authority**.
Production must later author the catalog, revalidate coupons and final prices,
redeem atomically at payment, and own the real subscription lifecycle.

---

## DEMO CONTROL PLANE, DEMO UI CLEANUP & ABOUT LEADER (2026-09-16)

Three things, in this order: the Super Admin now administers Customer Demo
policy; the Demo copy that no longer had a screen behind it is gone; and About
is named after the product and signed off «صنع بفخر في العراق».

**Full suite: 2207 passed** (baseline before this work: 2154). `flutter
analyze` clean, `git diff --check` clean, `flutter build apk --debug` succeeds
as `com.leader.teams` with the label `ليدر`.

### 1. The Demo control plane

**Default demo duration is 24 hours** — `DemoPolicy.defaultDemoDuration`, a
product constant, not a deployment seed.

New, in `features/demo/`:

- `domain/demo_policy.dart` — `DemoPolicy` (enabled, defaultDuration,
  revision, updatedBy, updatedAt), `DemoSession` (demoSessionId, accountId,
  demoWorkspaceId, startedAt, expiresAt, status, policyRevision, displayName?,
  endedAt?), `DemoSessionStatus { active, expired, terminated }`, and
  `DemoDurationPolicy` (the stepper's ladder).
- `data/demo_control_plane.dart` — one `Notifier` owning the policy and the
  session records, plus `activeDemoSessionIdProvider` and
  `demoSessionVerdictProvider`.

**Why one object and not two.** "May a trial start", "how long does it run" and
"which trials are running" are the same fact from three sides. Split across a
policy provider and a session registry, the login screen and the operator
could disagree about whether the offer exists.

**Why it imports no authentication.** The account id arrives as an argument and
every administrative mutation demands a `DemoPolicyActor` the caller had to be
authorized to build. `features/platform/data/platform_demo_providers.dart` is
where one is built, and only from a `super_admin` session — so the
authorization is the control plane's, not a role check on a widget. A mutation
without an actor is refused `not_authorized`, the same shape a backend sends.

**Settled semantics** (each has a test):

- **Disabling blocks creation only.** Running trials keep their windows.
  Immediate eviction is the separate «إنهاء جميع التجارب النشطة» action — never
  a side effect of the switch.
- **Duration changes are not retroactive.** A session is stamped once from the
  policy in force then, and records that `policyRevision`. 24h → 48h moves new
  sessions and nothing else.
- **Expiry is derived, never written.** `DemoSession.statusAt(now)` is what
  every reader asks; the stored `status` stays `active`. A terminated session
  stays terminated whatever the clock says.
- **Cleanup drops expired records and keeps terminated ones** — somebody
  decided those, and the list is where that decision stays visible.
- **The floor is one hour; there is no ceiling.** A ceiling is deployment
  policy the client cannot know, so the stepper is unbounded upward and the
  backend enforces the safe configured range (documented in
  `BACKEND-HANDOFF.md` §12.2a).

**How a trial actually ends.** `sessionAccessProvider` overlays
`demoSessionVerdictProvider` onto an *active* demo envelope. Termination or a
passed `expiresAt` turns the envelope to `DemoMode.expired`, the existing
startup classifier sends the user to `/demo-expired`, and the real unlinked
identity is untouched — it may then join with a Team Code or start another
trial while the policy allows. In production the backend is the authority and
says the same thing by refusing the request; this reproduces it without a
server.

### 2. `/platform/operations/demo` — «إدارة الحسابات التجريبية»

Inside the Operations area (`PlatformOperationsRoutes.demo`), pushed like
Health and Audit. Policy card (availability switch + hour/day stepper +
provenance), a three-number summary, the running trials soonest-to-expire
first with a terminate action each, then terminate-all and cleanup.

**No raw seconds and no session ids on screen.** The duration is spoken —
«يوم واحد», «٤٨ ساعة» — by `PlatformDemoCopy`, which carries the Arabic
singular/dual/few/many forms. A row names the person, never the
`demoSessionId` or `demoWorkspaceId`.

Audit: `customer_demo_policy_changed`, `customer_demo_session_started`,
`customer_demo_session_terminated`, `customer_demo_session_expired`, under a
new `customer_demo` category with `customer_demo_policy` /
`customer_demo_session` targets and the `demo_availability` /
`demo_default_duration` change fields. Backend-authored in production; the
client writes none.

### 3. Demo UI cleanup

Audited every Demo reference. The **user side was already right** — one entry
on the onboarding chooser, one `DemoTrialBar` above the shell, one exit — so
nothing there was removed. What went was copy with no screen behind it:
`customerDemoTitle`, `customerDemoWelcome`, `customerDemoIsolation`,
`customerDemoDataNotice`, `customerDemoSnapshot`, `customerDemoTodayShift`,
`customerDemoTeam`, `customerDemoInventory`, `customerDemoActionSub`,
`demoUnavailableHere`, `demoSignInFailed`, `demoActiveTitle`/`Body`/`Detail`
— the old holding screen's vocabulary.

`S.customerDemoAction` is **deliberately kept** and commented: it is the
expected-absent text of two guards proving Login offers no Demo action.
Deleting it would delete the assertion. `S.platformOpsDemo` was dead; it is
now the Operations row's label.

`demo_surface_cleanup_test.dart` is what stops a second Demo control growing
back: it asserts the trial indicator is present and singular, that Settings
offers no policy control, that the blocked destinations stay blocked and the
demonstrable modules stay open, and that a tenant administrator has no Demo
surface at all.

### 4. About Leader + the Iraq sign-off

- `S.aboutTitle` is now `'حول $productNameAr'` — «حول ليدر», built from the
  brand constant, never a literal (CLAUDE.md §Brand).
- `S.aboutDescription` is the product purpose: الفرق، المفارز، الورش، الأعضاء،
  الشفتات، المخزون والإحصائيات من مكان واحد.
- Two capability phrases added: «الورش والمشاركون» and «صلاحيات محدّدة حسب
  الدور». The second is the honest form of "security-oriented" — a design
  property the capability system really enforces, not an assurance about data
  this client could not back. No uptime, encryption or privacy claim was
  added, and no company or legal information was invented.
- `core/widgets/made_in_iraq.dart` — one widget, used by About and the
  Settings hub and nowhere else. Centred, `ink3`, small, not a row, not
  tappable, not pinned, text only (no flag). It follows light, dark and
  eye-protect because it asks the palette for one token.

**Known test-harness consequence:** About grew by two chips and the footer, so
the Telegram card starts below the fold on a test viewport. The three Telegram
tests in `about_page_test.dart` now `ensureVisible` before tapping. The
`made_in_iraq_test.dart` footer tests use `scrollUntilVisible` — a `ListView`
builds lazily, and "the footer does not exist until you scroll to it" is
itself the claim that it is not pinned.

### Still backend / external

Everything in `BACKEND-HANDOFF.md` §12 (the demo endpoints above), plus the
pre-existing gaps that session did not reopen. The control plane is process
memory by design: persisting it would let an operator's terminate be undone by
a reinstall, and would put other people's sessions in this device's storage.

---

## CUSTOMER DEMO — FULL ISOLATED APP TRIAL (2026-09-15)

The Customer Demo is no longer a summary page. It is the **real Leader tenant
application**, opened on the real screens, reading an isolated in-memory
workspace.

### What was actually wrong

The old `/demo` screen was a genuine limitation, not a login mistake: the
demo session classified to a destination whose location was `/demo`, so the
router held it on one page — a welcome line, three sample figures and an
exit. Nothing else was reachable, because nothing else was allowed to be.

### How it enters now

`StartupDestination.demoActive` now has **no location of its own**. Like
`tenantSurface`, the session goes wherever it asks, so after
`تجربة ليدر` the trial lands on `/home` inside `MainShell`. The old
`CustomerDemoPage` was deleted along with its `/demo` entry in
`startupStatusPages`; `/demo-expired` is unchanged. No intro screen replaced
it — the notice it used to carry now travels with the user (below).

### Isolation — `DemoWorkspace`

`features/demo/data/demo_workspace.dart` owns **one object holding a complete
set of in-memory repositories** seeded from `features/demo/domain/demo_seed.dart`:
team, detachments, detachment groups, shifts, inventory, workshops,
announcements, home and notifications.

Each repository provider asks `demoWorkspaceProvider` first and serves the
demo instance when there is one — one seam per provider, not an `if (demo)`
scattered through the screens. `isCustomerDemoSessionProvider` requires
**both halves** the startup classifier requires (`AuthRole.customerDemo` and
`DemoMode.active`), so a malformed session gets no workspace and no surface.
When the session stops being a demo the provider answers `null`, every
repository provider switches back, and the whole demo — seed and mutations
alike — is dropped. That is the reset.

### The dataset — the deliberate limit

**Exactly 2 detachments** (`d_demo_city`, `d_demo_field`) and **exactly 2
workshops** (`dw1` ahead and taking registrations, `dw2` finished with real
attendance and payment), one shared roster of **10 people**, 6 stock lines
(one low, one expiring), a small weekly schedule per detachment, and a
workshop register that points at roster members **by id**. Every demo id is
prefixed (`d_demo_`, `dm`, `dw`, `di`), so a demo record is recognisable on
sight and cannot be confused with a tenant fixture.

### What the trial may do

Everything operational: Home, Detachments (list, team, schedule, storage,
statistics), Workshops (including the whole new people flow — add and remove
participants, guests, organisers, attendance, payment), Team, Shifts,
Inventory, Statistics, Notifications, and the full Appearance surface (six
palettes, Light/Dark/System, Eye Protection, performance). Demo mutations
are ordinary product mutations against the demo repositories, and they are
discarded when the trial ends.

### What it may never do

- It is **not a tenant**: no `SaasTenant` is created, no `saasTenantId`, no
  membership, no Team Code issued or consumed, nothing persisted.
- **Capabilities**: a demo-only envelope (`features/demo/domain/demo_capabilities.dart`)
  carrying every operational key and **neither `admin.manage` nor
  `org.edit`** — so Simple Admin management, invitations, the organisation
  record and the plan are refused by the ordinary capability checks, not by a
  special case. It is attached to the demo identity, never written anywhere,
  and the backend must still refuse a demo session on every tenant endpoint.
- **Platform / Super Admin** is unreachable: `/platform` is startup-only and
  the demo role can never classify into it.
- **Blocked locations** are listed once, in the router
  (`_demoBlockedLocations`): `/more/security`, `/more/sessions`, `/more/sync`,
  `/more/organization`, `/more/plan`, `/more/simple-admins`, `/needs-review`.
  Deep links included; Settings hides exactly the same rows, so no row opens
  a page the router would bounce.
- **Sync**: demo writes never reach the outbox — the demo repositories are
  the whole world the session can reach — and the Sync screens are not
  offered at all rather than shown simulating.
- **Modules**: `TenantFeatureAccess.customerDemo` now answers from a fixed
  product set (`demoTenantFeatures`), never from a tenant's subscription.

### Saying so, and leaving

`DemoTrialBar` sits above every page of the shell: the notice that this is
sample data, and the exit beside it. Settings' sign-out becomes
`إنهاء التجربة`. Ending the trial confirms in the demo's own words, clears
the session through the ordinary sign-out, and returns to `/login` — the
verified unlinked identity that started it is untouched and may sign in again
and choose Team or Demo. Global demo availability (`CustomerDemoPolicy`) is
unchanged: with the demo disabled no session is created and the chooser says
so.

### Validation

- New: `test/features/demo/demo_workspace_test.dart` (10 — provider
  isolation, the 2+2 limit, the envelope, no tenant feature grant, mutation
  isolation, reset) and `demo_trial_flow_test.dart` (7 — shell entry, module
  tour, workshop people inside the demo, settings restrictions, exit,
  320dp/1.6x RTL, availability gate).
- `startup_routing_test` now proves the trial keeps its route across modules
  and is refused the platform and every blocked location.
- Two pre-existing 320 dp / 1.6x overflows on the detachment list (the filter
  row and the figures row) were fixed, because the demo is verified on those
  same screens.
- Three harnesses (`dashboard_states_test`, `notification_bell_test`,
  `notifications_center_page_test`) now declare `isCustomerDemoSessionProvider`
  as false: the repository providers consult the session, and those worlds
  have none.

### Remaining backend needs

Real demo start/expiry endpoints and the configured duration (unchanged from
Point 17). Nothing about the workspace above is backend work: it is a client
trial, and it must stay refused by production endpoints.

---

## WORKSHOPS — FUNCTIONALLY COMPLETE FOR CURRENT FRONTEND SCOPE (2026-09-15)

The Workshop module was audited end to end and the gaps that made it
unusable were closed. Workshops remain organisation-level
(`CAPABILITIES.md` §0, ruling B/Q2) and no new permission key was invented.

### Audit result

Working before this session: the list (search, upcoming/past), create and
edit (name, date, location, capacity), the detail shell with its three tabs,
per-participant attendance, the statistics tab and its exports, and the
`workshops` / `statistics_reports` feature gates.

Gaps found and closed:

- participants were **name-only**: a workshop pointed at people it could not
  identify;
- there was **no way to add or remove** a participant, an organiser or a
  guest — the empty states invited an action the screens did not offer;
- `registered` / `guests` were hand-seeded numbers that drifted from the
  register;
- `workshop.payment.record` and `workshop.archive` had **no implementation**
  at all;
- the edit form omitted the fee and the status, both of which the domain and
  `workshop.edit` already covered.

Out of scope and left alone: workshop **sections** (`workshop.section.manage`
stays conditional on open decision #8), any backend work, and an outbox for
workshops — there is none, and one was not invented.

### People

`WorkshopParticipant` now carries a nullable `memberId`. A member line is a
**reference** to a roster `TeamMember`; the name and monogram on it are a
display snapshot. No second person model was created. Guests keep
`memberId == null` — they are people from outside the team, which the domain
already modelled.

`WorkshopRepository` gained `addMemberParticipants`, `addGuestParticipant`,
`removeParticipant`, `setParticipantPayment`, `addOrganizers`,
`removeOrganizer`, `setOrganizerAttendance` and `setArchived`. Rules, all
enforced in the repository and surfaced by code:

- members are resolved through `TeamRepository`, so a person who is not on
  this workspace's roster cannot be put on a workshop (`not_found`);
- nobody is registered twice (`duplicate`), and nobody is both a participant
  and an organiser of the same workshop (`already_organizer` /
  `already_participant`), so the statistics count each person once;
- the register never exceeds the seats (`workshop_full`), and a multi-person
  add is all-or-nothing;
- **removal from a workshop never deletes the `TeamMember`** — proved by
  test;
- `registered` and `guests` are derived from the register on every read;
  `update` refuses a capacity below the people already registered
  (`capacity_below_registered`) and ignores the register, the organising team
  and the archive flag on the record handed to it, so a stale form cannot
  clobber them.

Claude-provisional rulings, pending Ahmed: the participant/organiser
exclusivity rule, the seat limit on registration, the capacity floor on edit,
and archive being a flag (`archived`) rather than a fourth `WorkshopStatus`.

### Screens

- **Members ("الأعضاء والضيوف")** — seat summary, `إضافة عضو` (roster picker,
  multi-select, search by name/section/detachment) and `إضافة ضيف` (name
  only), filters, and a per-person sheet holding attendance, payment and a
  confirmed removal that says the roster is untouched.
- **Team ("الفريق وأدواره")** — `إضافة منظِّم` from the same picker, plus a
  per-organiser sheet with attendance and removal. No payment: the team runs
  the workshop, it does not buy a seat at it.
- **Detail shell** — archive / restore action, and an archived banner. An
  archived workshop is readable and exportable and closed to every change,
  in the repository as well as the UI.
- **List** — an `الأرشيف` filter; archived workshops appear only there.
- **Edit** — fee and (on an existing workshop) status, both already in the
  domain. Status is set by hand because the record has a start time and no
  end.

The roster picker reads through `detachmentListProvider`, so it can only
offer people from active detachments the session may already see.

### Capabilities and feature flags

Unchanged keys, now actually used: `workshop.people.manage` (add/remove
participants, guests and organisers), `workshop.attendance.record`,
`workshop.payment.record`, `workshop.archive`, `workshop.create`,
`workshop.edit`. Every control is a capability check, never a role check, and
every one is additionally closed while the workshop is archived. With the
`workshops` feature off the routes still fail closed to `FeatureDisabledPage`.

### Offline

Workshop mutations are online commands: none is queued, none touches the sync
outbox, and a write that cannot land reports offline and changes nothing on
screen. That is tested.

### Validation

- `test/features/workshop/workshop_people_test.dart` (15) and
  `workshop_members_flow_test.dart` (10) are new; `workshop_stats_test.dart`
  still passes unchanged.
- Affected surface (workshop, team, detachment, search, tenant_feature,
  platform, router, access, home): **916 passed**.
- `flutter analyze`: no issues. `git diff --check`: clean.
- One pre-existing overflow inside the module was fixed while it was under
  work: the workshop card's figures row now wraps at 320 dp / 1.6x.

### Remaining backend needs

Endpoints for the register (`POST/DELETE participants`), guests, payment,
organising team and archive/restore, plus server-side enforcement of every
rule above. The client derives `registered` / `guests`; the server should be
the one that does so for real.

---

## LEADER REBRAND — PHASE 2 COMPLETE (2026-09-15)

The user-facing product migration is complete. The canonical names are
**Leader / ليدر**; the Android application id remains **`com.leader.teams`**.
The Arabic source literal in `S.productNameAr` is logically stored as `ليدر`
(Unicode code points `0644 064A 062F 0631`), not reversed to match terminal
BiDi display. `S.productNameEn` is `Leader`.

### User-facing result

- Migrated product-name copy across sign-up/onboarding and verification,
  Team/Demo choice, Customer Demo, dashboard/settings, About/Support,
  organization and plan surfaces, Admin/Platform screens, notifications,
  dialogs/errors, reports/exports, and the required-update screen. Login
  received no layout, behavior, route, animation, field, or button-design
  changes; its visible product name already comes from the canonical string.
- About renders the Arabic name in ambient RTL and confines LTR direction to
  the English `Leader` line. Customer Demo now reads `تجربة ليدر` while its
  isolated, ephemeral, no-tenant behavior is unchanged. Platform/Super Admin
  descriptions and display fixtures use Leader without changing roles,
  authorization, tenant lifecycle, Break-glass, routes, or reports.
- Visible plan names are `ليدر الأساسية` / `ليدر القياسية` /
  `ليدر المتقدمة`; persisted/API ids such as `mtm_core` remain unchanged.
  Product-branded demo names moved to Leader; technical fixture identities,
  selectors, Team Codes, and credentials did not move.
- Report filenames use `leader-report.pdf`. Android, iOS, and Linux visible
  app-name metadata reads `ليدر`. The iOS bundle identifier and Linux
  `APPLICATION_ID` remain unchanged pending separate signing/platform review:
  **IOS/LINUX TECHNICAL IDENTITY MIGRATION DEFERRED**.
- Logo, launcher/splash artwork, SVG/PNG assets, and icon geometry were not
  modified. The Login design was not modified.

### Compatibility and external ownership

The product brand is Leader / ليدر. Legacy technical identifiers containing
MTM/mtm are intentionally retained where changing them would break
compatibility or require a separate migration.

Remaining audit matches are classified as: Android/platform migration
history; Dart package/internal symbols; persistence/storage compatibility;
environment configuration; Team Code protocol; plan/API identifiers; backend
protocol; deterministic test fixtures; historical migration docs; and
unresolved external-domain placeholders. These are not accidental visible
branding.

The working support channels remain operational and their visible wording now
uses Leader. `https://mtm.app/download`, `*@mtm.app`, and example/fixture
`@mtm.org` addresses were not replaced with an invented domain:
**EXTERNAL BRAND DOMAIN MIGRATION REQUIRED** after the owner supplies the real
Leader domain. Google auth code and `MTM_GOOGLE_SERVER_CLIENT_ID` are unchanged;
deployment still requires an Android OAuth client for `com.leader.teams` with
the correct SHA-1/SHA-256 signing fingerprints. No backend implementation was
started.

### Validation

- Focused branding/identity/UI: 120 tests passed; directly affected screens:
  190 passed; onboarding render matrix: 24 passed (320/390dp, light/dark/eye
  protection, including 1.6x text); Platform appearance/theme coverage: 46
  passed. Representative renders were visually checked for joined Arabic RTL.
- Full Flutter suite: **2110 passed** in the required single run (Phase 1
  baseline 2108 plus two focused Phase 2 widget cases).
- `flutter analyze`: no issues. `git diff --check`: clean.
- `flutter build apk --debug`: passed. `aapt2 dump badging` reports package
  `com.leader.teams`, label `ليدر`, and launchable activity
  `com.leader.teams.MainActivity`; `com.mtm.mtm` is not the APK application
  identity. APK was not installed.
- The staged `git mv` of `MainActivity.kt` remains staged and was not reset or
  unstaged. The Phase 1 package/namespace decision was preserved.
- `graphify update .` was run once after the final code/docs changes.

---

## LEADER REBRAND — PHASE 1 FOUNDATION COMPLETE (2026-09-15)

The product is now **Leader / ليدر** (was MTM / Medical Teams Management).
Phase 1 moved the technical identity and set the compatibility rules; the
broad user-facing rename was completed in **Phase 2** above. Logo, launcher art, splash
and the Login design were **not** touched.

### Android identity

| | Old | New |
|---|---|---|
| `applicationId` | `com.mtm.mtm` | **`com.leader.teams`** |
| Gradle `namespace` | `com.mtm.mtm` | `com.leader.teams` |
| `MainActivity` | `kotlin/com/mtm/mtm/` | `kotlin/com/leader/teams/` (`package com.leader.teams`; moved with `git mv`, so the rename is **staged** in the index — nothing committed) |
| Installed label | `mtm` | `ليدر` (`AndroidManifest.xml` `android:label`) |
| Play listing (`UpdateChannel.androidStore[Native]`) | `?id=com.mtm.mtm` | `?id=com.leader.teams` |

Why `com.leader.teams`: contains `leader`, no `mtm`, not medical-specific
(teams is the product's unit of work — tenants, detachments, shifts), valid
Android id, and nothing in the repo ties the old id to anything that cannot
move (no Firebase / `google-services.json`, no deep links or custom schemes,
no custom `flutter_secure_storage` `AndroidOptions`). Manifest uses the
relative `.MainActivity`, so it resolves against the new namespace.

**Consequences (intentional):** Android treats Leader as a **different app**.
An installed MTM build cannot be updated in place; its local data (secure
auth session, onboarding record, theme, demo persona) is **not** inherited —
users sign in again. `adb install -r` over an MTM install no longer applies
(install fresh / uninstall `com.mtm.mtm`). No automatic data migration was
attempted. Release signing (still `signingConfigs.debug` in
`build.gradle.kts`) must be configured for the new identity.

### External follow-up (owner-supplied — nothing fabricated)

- Google Cloud: create an **Android OAuth client for `com.leader.teams`**
  with the SHA-1/SHA-256 of every signing cert (debug, upload, Play app
  signing). The `com.mtm.mtm` client does **not** cover the new package.
  The Web/server client id is unchanged in role.
- Play Console: a new listing for `com.leader.teams` (the forced-upgrade gate
  already points there).
- iOS bundle id (`ios/Runner.xcodeproj` → `com.mtm.mtm`) and Linux
  `APPLICATION_ID` (`linux/CMakeLists.txt`) are **unchanged** — iOS needs an
  Apple team/provisioning decision; no iOS listing exists yet.
- `UpdateChannel.webFallback` (`https://mtm.app/download`) and demo emails
  (`*@mtm.app`) are placeholders on a domain nobody has confirmed for Leader;
  replace when a real Leader domain exists.

### Intentionally preserved (do not rename)

- **Env keys:** `MTM_GOOGLE_SERVER_CLIENT_ID` (legacy technical name; no
  `LEADER_*` alias added — no technical benefit, and existing build scripts
  keep working), `MTM_VERSION_SCENARIO`, `MTM_RENDER_DIR` (test tool).
- **Persisted keys** (renaming loses user state): `mtm.auth.onboarding.v1`,
  `mtm.auth.full_session.v1` (secure storage), `mtm.settings.theme`,
  `mtm.dev.demo_persona`, `mtm.dev.demo_persona.seeded`. Policy: existing
  keys stay forever; a future key may use a `leader.` namespace only if it is
  brand-new (nothing to migrate) or ships with a read-old/write-new migration
  and a test.
- **Protocol identifiers:** Team Code prefix `MTM` (`kTeamCodePrefix`,
  `MTM-XXXX-XXXX` — a wire/user-entered format; changing it is a backend
  decision), plan ids `mtm_core` / `mtm_standard` / `mtm_advanced` /
  `mtm_enterprise_v2`, problem type URIs, endpoints, JSON keys, error codes,
  capability keys, roles, headers.
- **Internal:** Dart package name `mtm` (`package:mtm/...` imports), method
  channel `mtm/display` (Dart ↔ Kotlin pair), class/provider/route names,
  `mtm.iml` / `mtm_android.iml`.

### Canonical brand source

`lib/l10n/strings.dart`: `S.productNameAr = 'ليدر'`, `S.productNameEn =
'Leader'`; `S.appName`, `S.aboutAppName` → `productNameAr`,
`S.aboutAppFullName` → `productNameEn`. `MaterialApp.title` (Android recents
label) now reads `S.appName`. Upgrade-required lockup shows `productNameEn`
as the tracked wordmark and `productNameAr` beneath **untracked** —
letter-spacing breaks Arabic joining, so never apply the wordmark's
`letterSpacing` to the Arabic name.

### Validation

`flutter pub get` ✓ · `flutter analyze` — no issues · full `flutter test` —
2108 passed · new `test/core/app_identity_test.dart` (Gradle ids, Kotlin
package, store URLs, manifest label) · `git diff --check` clean ·
`flutter build apk --debug` ✓ · `aapt2 dump badging`: `package:
name='com.leader.teams'`, `application-label:'ليدر'`, launchable activity
`com.leader.teams.MainActivity`, zero `com.mtm.mtm` occurrences. Not
installed on a device.

### Phase 2 — historical checklist (completed above)

The checklist below is retained as migration history; Phase 2 completed it.

Replace visible `MTM` / `Medical Teams Management` brand text with
`S.productNameAr` / `S.productNameEn` (never new literals). Known sites:
- `lib/l10n/strings.dart`: `customerDemoAction`, `customerDemoTitle`, the
  customer-demo body, `platformBrand` (`منصة MTM`), platform overview/tenants
  copy, the Super Admin notice (~l.795), upgrade body (~l.1182 — also drops
  «نظام إدارة الفرق الطبية»), the about section comment. **Leave** the Team
  Code format strings (~l.762/784) — `MTM‑XXXX‑XXXX` is the protocol format.
- `lib/features/about/presentation/about_page.dart`: the brand block wraps
  names in LTR `Directionality` (comment says «MTM»); the Arabic name should
  not be forced LTR — revisit.
- `lib/features/about/domain/support_contacts.dart`: `supportEmailSubject`.
- Fixture/display names: `customer_demo.dart` (`زائر تجربة MTM`, `مساحة
  تجربة MTM`), `demo_personas.dart` (`مدير منصة MTM`, `منصة MTM`),
  `platform_audit_fixtures.dart`, `platform_subscription_fixtures.dart` +
  `platform_audit_copy.dart` plan **names** (`MTM أساسية`… — names only, keep
  the ids), `saas_tenant_features_page.dart`,
  `saas_tenant_subscription_page.dart`,
  `mock_platform_main_admin_repository.dart`, `mock_auth_repository.dart`
  (TOTP issuer label, device label).
- Docs: titles/prose in `README.md`, `CLAUDE.md`, `HANDOFF.md` header, etc.
  Historical sections may keep MTM.
- Then: `flutter analyze`, full `flutter test` (several tests read `S.*`),
  `flutter build apk --debug`, RTL visual check of About / Upgrade /
  Customer Demo / Platform overview at 320dp.

---

## POST-POINT-18 AUTHENTICATION / SETTINGS CLEANUP (2026-09-13)

Focused cleanup only; Points 17/18 were not reopened and no backend work was
started.

- Production Login now ends after the normal email/password surface, forgot
  password, the `أو` divider, the full-width Google action, and
  `ليس لديك حساب؟ إنشاء حساب`. The direct Customer Demo block, old join-request
  wording, MFA shortcut, Google hint, and all developer persona cards were
  removed. The identity label remains email-only.
- `GoogleGMark` now renders a small embedded local PNG of the recognizable
  four-colour Google G instead of the fragile overlapping-path painter. The
  Google SDK → `GoogleIdentityGateway` → `OnboardingController`/repository
  exchange is unchanged, including loading/disabled behavior and the
  backend-authoritative verified-email result.
- The existing post-verification rules remain authoritative: password signup
  → OTP → Team/Demo choice; Google with provider-verified email → Team/Demo
  choice without redundant OTP; a valid matching Simple Admin invitation
  auto-links and goes straight to `/account-setup`, bypassing Team Code and
  Demo selection. Customer Demo still starts only when globally available and
  remains isolated/ephemeral with no `SaasTenant`, grant, or tenant mutation.
- Developer identities remain debug-only infrastructure, but no picker is
  rendered. `DevTestCredentials` is the single deterministic local credential
  table for Super Admin, Main Admin, and Simple Admin; exact credentials typed
  into the normal Login fields authenticate through the development mocks.
  The compile-time/runtime gates refuse them outside development. Passwords
  are neither rendered nor logged and are not production provisioning data.
- Eye Protection remains independent persisted theme state and visual
  behavior, with one user-facing control inside Themes & Appearance. Duplicate
  tenant and Platform More rows and the standalone page were removed; legacy
  `/more/eye-protect` and `/platform/more/eye-protect` deep links redirect to
  their Themes screens. Palette, Light/Dark/System, motion, FPS, and performance
  behavior are unchanged. The shared Settings chevron was corrected for RTL.

Focused coverage now asserts the clean Login surface, rendered Google image,
Google handoff, responsive/keyboard states, onboarding choice/invitation/Demo
precedence, exact typed dev credentials and release refusal, the single Eye
Protection location, legacy redirects, and existing Main Admin management.

Final validation after the cleanup: the directly affected auth, startup,
router, settings/theme, platform-appearance, and admin-management set passed
644 tests; the complete Flutter suite passed once in three resource-safe
chunks (894 + 284 + 926 = 2,104 tests); the 24-case auth/onboarding render
harness passed, followed by a fresh-process first-frame Login render confirming
the Google G is immediately visible at 390dp. `flutter analyze` reported no
issues.

---

## POINT 18B — FINAL BACKEND HANDOFF PACKAGE, VALIDATION & PROJECT CLOSURE (2026-09-13)

One session, one agent, two phases: the approved final login/onboarding UX
adjustments (Phase 1, code), then the backend-handoff finalization and
roadmap closure (Phase 2, docs). Nothing was committed; no backend was
started.

### Phase 1 — final UX adjustments (code)

**Login / Google presentation** (`login_page.dart`,
`google_sign_in_button.dart`, `onboarding_ui.dart`). Below the email/password
form, an "أو" rule (`AuthMethodsDivider`) then a full-width, 52dp Google
surface: the standard multicolour Google "G" (`GoogleGMark`, painted from
Google's published 48×48 mark geometry — the repo ships no Google asset and no
SVG package, and a generic icon would misrepresent the provider) beside
"المتابعة باستخدام Google". The surface uses theme tokens (every palette,
light/dark/system, eye-protect); only the brand mark keeps Google's four fixed
colours — the one documented exception to token-only colour. Progress: while
the production SDK sheet is open, and while the page exchanges the assertion
(`loading`), the mark becomes a ring and the label "جارٍ المتابعة مع Google…";
a second tap starts nothing. (The debug chooser is modal, so it shows no ring
— a ring behind it would also never let `pumpAndSettle` settle.) The Google
auth architecture is unchanged: same gateway, same
`OnboardingController.signInWithGoogle`. At Point 18B, Customer Demo and
debug-only personas were still present below the form; the post-Point-18
cleanup above removed those entries without changing the Google flow.

**Email-only label.** `S.emailLabel` is now "البريد الإلكتروني". The constant
also labels the forgot-password and Simple Admin invite fields — both
email-only — so fixing the constant corrected all three; no username path
exists or was added.

**Team/Demo decision** (`link_team_page.dart`, `customer_demo_controller.dart`).
A state of `/link-team`, not a new route, so the startup classifier and its
precedence are untouched: an `unlinked` snapshot sees "كيف تريد المتابعة؟"
with two ≥72dp cards — **الانضمام إلى فريق** (→ the existing Team Code form,
with "العودة إلى الخيارات") and **تجربة MTM** (→ isolated Customer Demo). A
`withdrawn` snapshot opens on the form. The Point 17C "check for my
invitation" button is on both states. It is reached only after identity
proof: password sign-up → OTP → decision; a Google-verified address → decision
with no MTM code (the backend's `email_verified` verdict); an unverified Google
address still gets the code first. A valid Simple Admin invitation outranks it
structurally: the invitee arrives `linked` → `/account-setup` (no Team Code,
no demo choice, no role/capability choice).

**Demo from the decision.** `CustomerDemoController.start(leavingOnboarding:
true)` starts the existing isolated demo session, and only after it succeeds
calls `OnboardingController.abandon()` — the restricted session is discarded,
so the demo never carries the signup account and exiting the demo returns to
sign-in. Nothing is linked, no Team Code consumed, no tenant/Simple Admin
relationship or capability created; the account signs in again to the same
unlinked decision (tested). Demo disabled: the card says
"تجربة العملاء غير متاحة حاليًا." with an icon and cannot start; no fallback.

**Simple Admin management — verified, lightly polished.** Already complete
and correctly guarded (`admin.manage` on the Settings row and on all three
routes; catalogue excludes `admin.manage`, `org.edit`, lifecycle/destructive
keys; mock re-validates the subset; Feature Flags hide module keys). Polish
only: capabilities grouped under five localized module headings
(`SimpleAdminCapabilityGroup`), each account row states its grant count, the
edit page says "الصلاحيات الممنوحة" (it said "initial") and carries the
module-availability note. No second privilege system, no role escalation, no
seat transfer.

**Invitation consumption — real mock defect fixed.** Setup consumed the
onboarding authorization but the Simple Admin store's invitation stayed
`pending` and no account row appeared. Now `MockOnboardingRepository`
calls `authorizationConsumed` **inside** the idempotent setup transaction,
and `onboardingRepositoryProvider` wires it to
`SimpleAdminStore.acceptInvitation` (pending → accepted + one account keyed by
the canonical account id, carrying the invitation's grant; no-op if not
pending, so a replay never duplicates; cancelled/expired never accepted).

**One defect caught in render review:** the decision cards' chevron used
`chevron_left_rounded`, which Flutter mirrors to `>` in RTL (backward for an
Arabic reader); switched to `chevron_right_rounded` (mirrors to `<`). The
Settings `NavigationRow` uses the same `_left` glyph — not touched here
(outside scope), noted for a later look.

**Tests.** New `test/features/auth/onboarding_choice_test.dart` (11): email
label; Google surface full-width, ≥48dp, below the password form, Google mark;
login 320dp × 1.6× dark + eye protection; production gateway invoked once with
progress; password sign-up → OTP → decision; Team option → form → back;
Google-verified → decision without code; invitation (Google) bypasses the
decision; Demo starts isolated demo, links nothing, onboarding discarded;
Demo disabled enforced; decision 320dp × 1.6× long email. Also
`onboarding_full_session_bridge_test` (+1: atomic consumption, idempotent),
`simple_admin_repository_test` (+2: accept once / cancelled+expired never),
`simple_admin_management_page_test` (+2: Main Admin walkthrough — list,
grouped edit+save, cancel; capability editor 320dp × 1.6×).
`onboarding_screens_test` (2 cases) and the render harness (cases 08/09/11)
now pass through the decision; render cases 21–24 added (decision light,
320 × 1.6× dark long email, demo closed + eye protection, Google in
progress). All 24 render cases ran with no overflow (every shot is a fit
check); 01, 18 and 21–24 were inspected visually.

### Phase 2 — Point 18B backend handoff finalization (docs)

Final owner decisions applied everywhere and removed from "open":

- **Customer Demo:** self-service from the verified-unlinked decision while globally
  enabled; Super Admin owns enabled/duration/cleanup only; backend flow start
  → check enabled → isolated ephemeral workspace → expiry → session; no
  `SaasTenant`, Team Code or account link. Stale "Super-Admin-issued" /
  "created and ended only by `super_admin`" lines corrected; Overview
  `simple/full` split kept on the wire with a Claude-provisional interim rule
  (`simple = active`, `full = 0`).
- **Token refresh:** `POST /api/v1/auth/refresh` — `{refreshToken}` →
  rotated `{accessToken, refreshToken}`; online-only; single-use; replay
  revokes the family; scope preserved (onboarding stays onboarding);
  invalid/expired/revoked/replayed/account-blocked → one indistinguishable
  `401 authentication_expired` → `/session-expired`; tenant blocks are not a
  refresh refusal; no outbox; tokens opaque, never decoded.
- **Login identity:** email only; username future scope.
- **Simple Admin invitation:** backend owns tenantId, normalized email, role
  `admin`, grant, state, revision, timestamps, idempotency; states
  pending/accepted/cancelled/expired; atomic consumption transaction; replay
  safe.
- **Audit:** `main_admin_setup_completed` required; tenant-scoped
  `admin_invitation_created/_cancelled/_accepted`,
  `admin_capabilities_changed`; `customer_demo_policy_changed`.
- **Privacy:** final never-log list (passwords, OTPs, Team Codes in ordinary
  logs, Google provider credentials, access/refresh/onboarding tokens, MFA and
  reset secrets); Platform Reports never expose tenant operational/medical data.
- **Deployment:** Google client id, Android OAuth client + SHA-1/SHA-256,
  release keystore, consent screen, backend token verification, `minSdk 23`
  secure-storage floor.
- **Terms / Privacy:** a pre-production product/legal requirement (content,
  policy, consent/versioning before public production onboarding). No legal
  text written.

`BACKEND-HANDOFF.md` §15 is now the **final gap classification**: NO LONGER
OPEN · REQUIRED BACKEND IMPLEMENTATION · ENVIRONMENT / DEPLOYMENT ·
PRE-PRODUCTION PRODUCT / LEGAL · FUTURE PRODUCT SCOPE · still-open policy
values (retained from 18A, none frontend-blocking).

**Canonical-doc contradiction pass** (`API_CONTRACT.md`, `CAPABILITIES.md`,
`DATA-NEEDS.md`, `SCREEN-ROUTE-MATRIX.md`, `BACKEND-HANDOFF.md`, this file):
fixed the demo tier/provisioning lines, the "email or username" Login data row,
the stale Login route row (`AuthRepository` / `POST /auth/login`), the planned
"Simple/Full Demo" Platform row, the "first-time setup … not specified" row,
the historical "29 keys" total (annotated → 30), `BACKEND-HANDOFF.md`'s wrong
`DATA-NEEDS.md` "§3" item references (they are §4), and added refresh to the
onboarding-session allowlist. Error names checked consistent
(`idempotency_conflict`, `stale_*`, `recent_authentication_required`,
`plan_limit_reached`, `feature_disabled`, `demo_unavailable`,
`authentication_expired`; code and contract agree on the Simple Admin codes).
Theme and permission counts in the canonical docs were already correct (six
palettes; 30 keys).

### Validation

- Focused Phase 1 run: auth + startup + admin management + router suites,
  concurrency 3 — **522/522 passed** (before the added walkthrough/320dp
  tests, which then passed with their files).
- **Complete Flutter suite, once**, in three sequential chunks at
  concurrency 3 (core + about/admin/announcement/app_version/auth ·
  conflict/detachment/home/inventory/notification/organization ·
  platform/search/settings/shift/team/tenant_feature/workshop):
  **891 + 284 + 927 = 2,102 passed, 0 failed**, every chunk exit 0. (Run on a
  Sunday, so the Tuesday/Friday calendar-dependent archive test was not in
  its failing window.)
- `flutter analyze`: **No issues found.**
- `git diff --check`: clean; no trailing whitespace in the untracked
  `BACKEND-HANDOFF.md`, `SCREEN-ROUTE-MATRIX.md` or the new test file.
- `graphify update .` run once after the final code/docs.

**POINT 18B IS COMPLETE. POINT 18 — COMPLETE.** The frontend/backend-handoff
roadmap is closed. No backend implementation was started and no further
roadmap point was started.

---

## POINT 18A — FINAL BACKEND HANDOFF ARCHITECTURE & CONTRACT CONSOLIDATION (2026-09-13)

Documentation only — no code, no backend. Created the single canonical
**`BACKEND-HANDOFF.md`** (no equivalent existed: `FRONTEND-BACKEND-INTEGRATION.md`
is a per-feature seam list and `API_CONTRACT.md` the wire authority, which the
new file points into rather than duplicates). It consolidates the domain model,
identifiers, roles/capabilities, authorization order, state machines, endpoint
inventory, idempotency/concurrency, sync, RFC 9457 taxonomy, Audit, privacy,
Google configuration, Customer Demo and Simple Admin backend requirements,
mock-only seams, open policies and a recommended backend build order.

**Stale contradictions corrected at source** (listed in `BACKEND-HANDOFF.md`
§0): capability count 29 → 30 (+`announcement.publish`) in `API_CONTRACT.md`
and two present-tense `CAPABILITIES.md` lines; `POST /auth/login` →
`POST /api/v1/auth/sign-in`; the pre-17 `AuthRepository.signIn` shape marked
superseded by the 17A outcome union; `fieldErrors` → `fields` on
`POST /platform/tenants`; the Team Code read no longer "needed" for Simple
Admin onboarding; `DATA-NEEDS.md` workshop-scope item marked ruled.

**Found, recorded, not fixed (policy or code, out of 18A scope):** Customer
Demo is described both as Super-Admin-issued and as self-service from Login
(§15.1); no token-refresh endpoint exists anywhere; the `/login` field label
says "email or username" while login is email-only; the mock does not mark a
Simple Admin invitation `accepted` on setup completion.

**POINT 18A IS COMPLETE. POINT 18B WAS NOT STARTED.**

---

## POINT 17C — SIGNUP / ONBOARDING SECURITY, UX & FINAL CLOSURE (2026-09-13)

Closes Point 17. Two sessions did the work; this record covers both. Nothing
in 17A/17B's model was reopened except where noted.

### Done in the first 17C session (verified present in the tree)

- **Secure storage — closes 17B gap 2.** `flutter_secure_storage ^10.3.3`
  (Android `minSdk` raised to 23 in `android/app/build.gradle.kts`, with the
  reason inline). One seam, `core/storage/secure_store.dart`
  (`SecureStore`, `PlatformSecureStore`, `InMemorySecureStore` for tests),
  separate from `LocalStore`/`SharedPreferences`. `features/auth/data/
  secure_auth_state_store.dart` (`SecureAuthStateStore`,
  `authStateStoreProvider`) holds two versioned, mutually exclusive records:
  `mtm.auth.onboarding.v1` (challenge, or restricted token + display-only
  snapshot) and `mtm.auth.full_session.v1`. Corrupt/unknown-version records
  are deleted, never repaired; `toString` redacts. `MockOnboardingRepository`
  keeps its "server" in `MockOnboardingServer` (`mockOnboardingServerProvider`)
  so a rebuilt repository or a new container is the same backend;
  `MockAuthRepository.installOnboardedSession` now also writes the full-session
  token, and `currentUser()` restores from it (a revoked token → expired, never
  a developer persona). `test/flutter_test_config.dart` installs the
  secure-storage mock beside the preferences mock.
- **Google — closes 17B gap 1.** `google_sign_in ^7.2.0` through
  `GoogleSdkIdentityGateway` / `GoogleSdkIdentityTokenClient`
  (`google_identity_gateway.dart`); only `authentication.idToken` is used,
  never decoded/stored/logged; five client outcomes (obtained, cancelled,
  unavailable, network, failed), no provider code crosses the seam. Bug
  fixed: a failed SDK `initialize` was memoized, so Google stayed
  "unavailable" until a process restart — now retried on the next tap. A
  second server client id in one process fails closed. Tests use the real
  `google_sign_in` platform interface (`google_identity_gateway_test.dart`).
- **Secret-leak / security audit** of the journey — no unresolved gap.
  `secure_auth_state_store_test.dart` and
  `onboarding_process_restore_test.dart` ("ephemeral onboarding evidence never
  enters the secure vault") pin it.
- **Render harness** `test/features/auth/onboarding_render.dart` (tag
  `render`, skipped unless `MTM_RENDER_DIR` is set; PNGs stay outside the
  repo; no overflow is swallowed, so every shot is also a fit check). UI issues
  found in renders were fixed (auth scaffold, signup, verify, link, setup,
  login, forgot-password copy/layout).
- Auth/startup/router rerun 487/487; complete suite in three sequential
  resource-safe chunks, exit 0.

### Done in the closing 17C session

**Simple Admin invitation re-check — two real violations found and fixed.**

1. **A cancelled invitation still linked.** `onboardingRepositoryProvider`
   passes cancelled/expired Simple Admin invitation ids as
   `excludedAuthorizationIds`, but the constructor applied them only to the
   first fixture seed; once the shared `MockOnboardingServer` existed, a
   cancelled invitation stayed live on it — its invitee still auto-linked and
   could complete setup with the cancelled grant. Fix: the constructor now
   withdraws an excluded id the server still holds (skipping one the server
   already treats as expired, withdrawn or consumed), via the existing
   `withdrawAuthorization`, so an invitee mid-setup reads `withdrawn`.
2. **An invitee could end on a Team Code screen with no exit.** Auto-link ran
   only inside `_enter` (sign-in/verify). An invitee who verified before the
   invitation existed, whose invitation was cancelled and reissued, or whose
   tenant was paused at verification landed on `/link-team`, where the only
   action needs a Team Code they never receive; `refresh`/`restore` never
   re-resolved invitations. Fix (smallest, consistent with the 17B ruling
   "the backend links it the moment the address is proved"):
   `_autoLinkInvitation` now also runs in `refresh()` and in `restore()`'s
   restricted-session branch; `/link-team` gained a hint line and a secondary
   "التحقق من الدعوة" (check for my invitation) button that calls
   `OnboardingController.refresh()` and routes on a linked snapshot. "No
   invitation yet" shows as a neutral live-region note under that button —
   the first render showed it as a red error under the Team Code field, which
   read as "your code is wrong", so it was moved. New strings:
   `teamLinkInvitationHint`, `checkInvitationAction`, `noInvitationYet`.
   The Main Admin Team Code path is unchanged.

Files: `mock_onboarding_repository.dart`, `link_team_page.dart`,
`l10n/strings.dart`; tests `onboarding_repository_test.dart` (new group
"Point 17C — invitation-bound Simple Admin never needs a Team Code", 4 cases),
`onboarding_screens_test.dart` (+1 widget test), `onboarding_render.dart`
(+case 20).

**Render re-verification.** Re-ran only the affected cases — 01, 02, 03, 08,
09, 10, 12, 13, 17, 18, 19 and new 20 (login, signup, Google, Team Code,
invitation setup) — all fit at their sizes (320dp/1.6× included) and were
inspected. One cosmetic behaviour left as-is: a long address in the auth
subtitle wraps at its hyphen at 320dp/1.6× (pre-existing; the LTR isolate keeps
it legible).

**Checks.** 69 test files that reference the changed code or boot the app
router, concurrency 3: **948/948 passed**. `flutter analyze`: **no issues**.
`git diff --check`: clean (and no trailing whitespace in untracked files).
Full suite **not** rerun: every edit since the last full run is in onboarding
paths, plus new string constants, and all of their consumers are in the 948.
`graphify update .` run once after the code was final.

### Google external configuration (real requirements; nothing fabricated)

No client id, `google-services.json`, iOS `GIDClientID` or signing fingerprint
is in the repo. Needed from the MTM Google Cloud project owner:
`--dart-define=MTM_GOOGLE_SERVER_CLIENT_ID=<web client id>` (the backend
verifies `aud` against the same id); an **Android** OAuth client for
package `com.mtm.mtm` with the SHA-1/SHA-256 of every signing certificate
(debug, production upload key, Play app-signing key if used); a production
release keystore (`release` is still signed with the **debug** keys); a
published OAuth consent screen. iOS/web are not configured and not Point 17
targets. Full list: `API_CONTRACT.md` → "Google external configuration".

### Still open (backend/product, not Point 17 code)

17A "Q. Open decisions" that were never ruled stand: OTP/lockout budgets,
mandatory MFA, Team Code tenant-side read, one-account-one-tenant,
`main_admin_setup_completed` Audit action, the backend's exact auto-link
trigger. All auth/onboarding endpoints remain backend work.

**POINT 17 IS COMPLETE.**

---

## POINT 17B — SIGNUP / ONBOARDING CORE IMPLEMENTATION & INTEGRATION (2026-09-12)

Implements the production screens Point 17A designed and left as holding
pages, and wires the whole journey into startup, routing and the existing
full session. Point 17A's decisions stand except the one refinement this
session's brief explicitly authorized (§4.3, below) — nothing else was
reopened.

### Customer Demo / `AuthRole` — checked, found already correct

`AuthRole.customerDemo` **is** a canonical enum value (`customer_demo` on the
wire), alongside `super_admin`/`main_admin`/`admin`. Checked against the
brief's concern (a demo identity polluting production authorization) and
judged **not a defect**, for reasons already load-bearing in the code before
this session:

- `customerDemoUser.capabilities == Capabilities.none` and `saasTenantId ==
  null` — the role carries zero authority. `AuthRole`'s own doc comment states
  the invariant this depends on: "role selects the surface; capabilities
  authorize the actions" — exactly the same pattern `super_admin` uses (a role
  that picks a surface, never a grant).
- **A truly separate demo-session signal already exists and is
  cross-checked.** `SessionAccess.demo` (`DemoMode`) is independent state; the
  startup classifier (`resolveStartup`) fails closed to `/session-invalid` the
  moment `access.isDemo != (user.role == customerDemo)` — a demo envelope on
  an administrator, or a demo role without the envelope, can never reach a
  surface. This is the "separate demo session mode... independent of role"
  the brief asks for; it already shipped in the PERSONA/CUSTOMER DEMO session
  below.
- Removing `customerDemo` from `AuthRole` was evaluated and rejected as the
  fix: 17 files reference it (`profile_page.dart`, `login_page.dart`,
  `customer_demo_page.dart`, `tenant_feature_providers.dart`,
  `mock_auth_repository.dart`, six test files, …). Touching all of them to
  invent a parallel non-`AuthRole` identity type is a redesign of the demo
  feature, which §33/§39 of this session's brief forbid alongside
  "surgically correct... only if actually wrong."
- Existing coverage: `test/features/auth/auth_role_test.dart`
  ("`customer_demo` has no SaasTenant", `belongsToSaasTenant` false for it),
  `test/features/auth/customer_demo_test.dart` (capabilities/isolation),
  `core/startup/startup_destination.dart`'s demo/role cross-check tests in
  `onboarding_startup_test.dart` and `startup_classifier_test.dart`.

**No code changed for this item.** If Ahmed still wants `customerDemo` out of
the `AuthRole` enum on principle (a 4th value in an "Auth" enum, regardless of
grant), that is a real, larger redesign to schedule deliberately — not a
17B-scope fix.

### Login

Rewired onto `OnboardingController` (`signInWithPassword`/`signInWithGoogle`)
instead of the legacy `AuthRepository.signIn` path, which is now reached only
by the debug persona section (`DemoAccountsSection`, unchanged). No Team Code
field. "إن كنت أنشأت حسابك عبر Google..." hint shown unconditionally, per the
UX contract. `EntryNone.notice` (verification ended / session ended / setup
completed elsewhere) renders as one live-region info line above the form.
"طلب الانضمام" now navigates to `/signup` (`context.push`) instead of doing
nothing. The MFA-challenge test button and the customer-demo entry are
unchanged.

### Signup — `/signup` (new, public route)

Email + password only (`signup_page.dart`). Added to `_publicPages` in
`app_router.dart` beside `/login`, so it is reachable when signed out and
excluded from `_startupOnlyDestinations` (no classifier ever routes there —
it is a voluntary entry, not an outcome). Success always lands on
`/verify-email`, including for an already-registered address (the
enumeration-safe answer the repository already gives).

### Email verification — `/verify-email` (holding page retired)

`email_verification_page.dart`. One text field (`autofillHints:
oneTimeCode`, Arabic-Indic digits folded on submit via
`normalizeVerificationCode`), not six boxes — deliberately different from the
existing `/otp` reset-flow screen, which the brief's UX contract asked for and
which the reset flow does not touch. Resend cooldown counts down against the
injected `clockProvider`; attempts-remaining shown when the backend disclosed
it; "استخدام بريد آخر" calls `abandon()` then returns to `/signup`.

### Team Link — `/link-team` (holding page retired) — Team Code path only

`link_team_page.dart`. **A verified Simple Admin invitation never reaches
this screen** — see the ruling below. What does reach it: an unlinked or
withdrawn snapshot, chiefly the initial Main Admin seat and a replacement
designate, both of which type the Team Code they were given out of band.
Uppercased input, LTR-isolated inside the RTL layout, never persisted.

**Ruling applied (brief §4.3, refining Point 17A's "invitation + Team Code
(option B)"):** a Simple Admin invitation already names both the tenant and
the invited address, so exposing a Team Code to that recipient serves no
purpose — the backend links it the moment the address verifies.
`MockOnboardingRepository._autoLinkInvitation`, called from `_enter()` (the
one place a verified credential becomes a session-or-onboarding outcome),
auto-links any unexpired, unwithdrawn, non-seat (`mainAdminKind == null`)
authorization matching the verified email, and leaves a seat authorization
alone. This is additive and did not need to touch any of 17A's 41
`onboarding_repository_test.dart` cases — `linkTeam`'s existing idempotent
"already linked, same tenant → success" branch absorbs an account that
auto-linked before an explicit code was ever typed. One existing test's
premise did change: "sign-up → verify → link → setup / each trust transition
moves the state" used Noura (a Simple Admin invitee) to demonstrate the
Team-Code step; it now uses Huda (the Main Admin seat) for that, and a new
sibling test demonstrates Noura's no-Team-Code path.

### Account Setup — `/account-setup` (re-scoped from the 17A holding page)

`account_setup_page.dart`. Tenant name + role confirmation card (the "safe
organisation confirmation" the invitation path needs, since it never sees
`/link-team`), display name prefilled from `displayNameSuggestion` and
editable, "إكمال الإعداد" → `completeSetup`. Handles the documented
`setup: completed` race (another action finished the exchange first) with a
retry affordance that calls `refresh()` — unreachable through the current
mock (which converts that race straight to `EntryNone(notice:
setupCompletedElsewhere)`), kept for a real backend that might genuinely
produce it.

### The full-session bridge (the actual gap 17A left, §L of its own notes)

17A's mock could reach `EntryReady` but never installed a session
`AuthRepository.currentUser()` would answer with — `MockAuthRepository._me`
had no writer for it. Added:

- `MockAuthRepository.installOnboardedSession(AuthUser)` — sets `_me`/
  `_access`, the mock's side of "one secure token vault."
- `MockOnboardingRepository`'s new `OnboardingSessionIssued` callback
  (`sessionIssued`), invoked from a shared `_issueFullSession(_Account)`
  used by both `_enter()` (a returning, already-set-up account) and
  `completeSetup()` (first-time). Builds the `AuthUser` **only** from the
  account and its (consumed) authorization — id, name (display name or the
  authorization's suggested name), email, role, `saasTenantId`, capabilities,
  `orgName` — never from anything else in scope.
- `onboardingRepositoryProvider` wires `sessionIssued` to
  `authRepo.installOnboardedSession` when `authRepo is MockAuthRepository`.
  `OnboardingController._apply`'s existing `ref.invalidate
  (currentUserResultProvider)` on `EntryReady` then picks it up.
- Proven in `onboarding_full_session_bridge_test.dart`: a returning
  `readyEmail` sign-in, a Main Admin seat completion (`Cap.all`, `saas_nabd`),
  and a Simple Admin invitation completion (the invitation's exact capability
  set, explicitly checked against a capability the invitation does *not*
  grant) all produce the correct `currentUser()` — and the display name typed
  at setup never leaks into role or capabilities (there is no code path that
  could read it for that).

### Google

No `google_sign_in` dependency added (package approval + native OAuth
configuration this repository does not have — see "Remaining gaps" below).
`google_identity_gateway.dart` defines the seam
(`GoogleIdentityGateway`/`GoogleSignInAttempt` — obtained / cancelled /
unavailable) with `UnavailableGoogleIdentityGateway` as every build's
default: a clear, retryable failure, never a fabricated identity.
`google_sign_in_button.dart` additionally shows a development-only chooser
dialog (gated on `demoAccountsAllowed`, absent from a release build's call
graph) that drives `MockOnboardingRepository`'s existing `mock-google:<email>`
/ `mock-google-unverified:<email>` convention, so the verified, unverified and
`auth_method_link_required` paths are all exercised in
`google_sign_in_flow_test.dart`. Two bugs the test caught and this session
fixed: the chooser disposed its `TextEditingController` the instant
`showDialog` resolved (before the closing transition finished) — moved
ownership into a proper `StatefulWidget`; and `OnboardingExitRow` overflowed
at 320dp (`Row` → `Wrap`).

### Restore / startup integration

`OnboardingController.restore()` is now called from `main.dart`'s
`_MtmAppState.initState`, **deferred to a post-frame callback** — not called
synchronously, which was tried first and reliably corrupted the element tree
(`'_elements.contains(element)'`) under `admin_profile_test.dart` and others:
setting provider state synchronously during `initState` triggers
`startupDestinationProvider`'s dependents (the router's `refreshListenable`)
to re-run while Flutter is still mid-mount for the very first frame. A
post-frame callback still beats every classifier decision that matters:
`currentUser()`'s own restore carries real latency in every build (mocked or
real), so `AuthGate.restoring` already holds `/startup` for longer than
`restore()` needs.

### Simple Admin invitation integration

Already wired by 17A's own `onboardingRepositoryProvider` (it folds pending
`simpleAdminStoreProvider` invitations into `MockOnboardingRepository` as
additional authorizations) — 17B's job here was the auto-link ruling above
and the UI. No admin-management code changed.

### Main Admin activation

Unchanged from 17A: `completeSetup` runs the seat transition via the
`seatActivation` hook when wired to `MockPlatformMainAdminRepository`
(`onboarding_repository_test.dart` already proves the two agree); Flutter
never marks a seat active locally. `onboarding_screens_test.dart`'s Main Admin
flow additionally confirms the *UI* path reaches a real `/home` session with
`admin.manage` held.

### Routing security

No change to `core/startup/startup_destination.dart` or the router's redirect
— the existing `StartupDestination`/`_isStartupOnly`/`startupStatusPages`
machinery already refuses a direct/deep-linked visit to any onboarding-step
route the classifier did not send the session to; swapping the three holding
widgets for real ones changed nothing about that wall (re-verified: every
"router wall" case in `onboarding_startup_test.dart` still passes). `/signup`
is a voluntary public page like `/login`, not a classifier destination — a
signed-in session can still navigate to it (exactly as it already could to
`/login`), which is pre-existing behaviour this point did not touch.

### Secrets / offline / single-flight

Unchanged 17A guarantees, reused as-is: no password/OTP/Team Code/Google
token persisted; every trust transition is online-only (`Offline`, unchanged
state, nothing queued); the controller's single-flight + idempotency-key
reuse is the only mutation path every new screen calls through.

### Tests

New: `onboarding_full_session_bridge_test.dart` (3),
`onboarding_screens_test.dart` (8, incl. 320dp/1.6× fit),
`google_sign_in_flow_test.dart` (3). Updated:
`onboarding_controller_test.dart` (Main Admin test repointed to the
Team-Code path + a new Simple-Admin-no-Team-Code test),
`onboarding_startup_test.dart` (holding-page type reference →
`LinkTeamPage`), `status_screens_test.dart` (the three retired holding pages
dropped from the generic status-screen table and its now-obsolete
"setup screen offers no team-code field" assertion removed — the real screen
correctly has a display-name field).

Focused run (`test/features/auth/`, `test/core/startup/`, `test/core/router/`,
`test/features/admin_management/`, `test/features/settings/`,
`test/features/organization/`, `test/features/platform/`): **1261 passed**.
`flutter analyze`: **No issues found.**

### Remaining backend/dependency gaps (genuine, not deferred by choice)

1. **[Closed in 17C — see POINT 17C.]** **No `google_sign_in` package.** `UnavailableGoogleIdentityGateway` is
   honest about this; the dev chooser proves the rest of the flow. Needs
   package approval + Android `google-services.json` / iOS URL scheme / web
   client id.
2. **[Closed in 17C — see POINT 17C.]** **No `flutter_secure_storage` package.** The onboarding challenge handle
   and token are not persisted anywhere (never in `LocalStore`/
   `SharedPreferences` — 17A is explicit that must not happen). A real
   process kill/relaunch loses an in-progress verification or onboarding
   session in this build; `restore()` is wired correctly for the day a
   storage-backed repository exists.
3. Every item already listed under 17A's "Q. Open decisions" that this
   session did not rule on (OTP/lockout budgets, whether MFA enrolment is
   mandatory, Team Code tenant-side read, one-account-one-tenant forever,
   `main_admin_setup_completed` Audit action) stands unchanged.

**POINT 17 IS NOT YET COMPLETE.**

**NEXT: POINT 17C — SIGNUP / ONBOARDING SECURITY, UX & FINAL CLOSURE.**

**POINT 18 WAS NOT STARTED.**

---

## PERSONA / CUSTOMER DEMO + SIMPLE ADMIN MANAGEMENT + THEME RESTORATION (2026-09-12)

This implementation closes three gaps found during APK testing while preserving
Points 1–17A and the dirty working tree. Git history was used only as a
read-only theme reference; no reset, broad checkout/restore, stash, commit or
push was used.

### Persona and Customer Demo result

The three developer personas were already distinct; Simple Admin was not
actually sharing the Customer Demo identity. The product problem was that the
Customer Demo lifecycle seam existed (`DemoMode`) but had no reachable,
isolated login flow, which made the available `admin` demo look like the
customer demo.

| Entry | Identity | Tenant | Capabilities | Startup |
| --- | --- | --- | --- | --- |
| Super Admin Demo | `AuthRole.superAdmin` | none | platform role; no tenant grant | Platform shell only |
| Main Admin Demo | `AuthRole.mainAdmin` | canonical `saas_hilal` | `Cap.all` | tenant shell |
| Simple Admin Demo | `AuthRole.admin` | canonical `saas_hilal` | realistic limited preset | tenant shell |
| Customer Demo | `AuthRole.customerDemo` | none; never a `SaasTenant` | `Capabilities.none` | isolated `/demo` workspace |

Customer Demo now has a separate login action and controller, a global
availability policy independent of the debug persona gate, a matching
identity/session envelope, and a constrained read-only sample workspace. It
does not accept Team Code, read tenant repositories, mutate tenant data or
fall through to a tenant/Platform shell. The classifier fails closed when an
admin identity carries `DemoMode`, or a Customer Demo identity does not.

### Main Admin -> Simple Admin management

The tenant Organization area now exposes Simple Admin management only through
`admin.manage`. It lists current accounts and pending invitations, creates and
cancels invitations, and edits existing Simple Admin capabilities. Routes are
`/more/simple-admins`, `/more/simple-admins/invite` and
`/more/simple-admins/:accountId/capabilities`, all capability guarded.

The invitation command contains only normalized invited email, optional
display name, selected existing capability keys, revision and idempotency key.
Tenant and intended `AuthRole.admin` relationship are derived server-side from
the authenticated management session. There is no password, role picker,
tenant picker, automatic activation or recipient capability selection. The
mock invitation store feeds eligible pending invitations into the existing
Point 17A onboarding repository; cancelled/expired invitations cannot link.
Point 17B still owns identity proof, verification, Google, acceptance and
account setup.

The selector uses only the established capability catalogue and filters out
authority/lifecycle/destructive grants. It also removes capabilities whose
module is unavailable under the existing tenant feature rules. Repository and
route authorization remain authoritative; role `admin` alone grants nothing.

### Theme and appearance restoration

Historical reference: commit `d115d79` (`Add local-first sync, conflict
resolution, and full app feature set`). The versions inspected with
`git show` were:

- `flutter_app/lib/core/theme/theme_state.dart`
- `flutter_app/lib/core/theme/app_palette.dart`
- `flutter_app/lib/features/settings/presentation/themes_page.dart`
- `flutter_app/lib/features/settings/presentation/settings_page.dart`

That history confirms six palettes: Medical, Slate, Copper, Clay, Indigo and
Teal, each with Light/Dark/System appearance and independent Eye Protection.
Only those missing definitions were ported into the current consolidated
theme/performance architecture. `MotionLevel`, `MotionSpec`, performance
quality, frame-rate selection, reduced-motion behavior, semantic tokens and
RTL remain in place.

The canonical screen order is now palette catalogue -> Eye Protection ->
Light/Dark/System appearance -> performance quality -> frame rate -> current
motion/animation controls. Palette selection preserves appearance and Eye
Protection; appearance changes the running app immediately. The complete
state is persisted through the existing local settings store. Unknown/corrupt
legacy values fall back field-by-field and do not wipe unrelated settings.

### Validation

- Focused persona, Customer Demo, admin-management, theme, persistence,
  routing and responsive battery: 204 passed; supporting lifecycle and
  performance regression files: 32 + 4 passed.
- Full resource-safe suite (three sequential chunks, concurrency 3):
  834 + 376 + 835 = **2,045 passed**.
- `flutter analyze`: no issues.
- Debug APK built successfully at
  `flutter_app/build/app/outputs/flutter-apk/app-debug.apk`.
- Impeccable changed-UI detector: no findings.
- Widget coverage includes 320dp, 390dp and 320dp at 1.6x text scale; changed
  actions retain 48dp targets and Arabic RTL/LTR email islands.

### Remaining production dependencies

- Real Customer Demo start/expiry/data endpoints and configured duration are
  still backend work; this implementation deliberately does not invent a
  duration or represent the workspace as a tenant.
- Simple Admin list/invite/cancel/capability mutation endpoints, email
  delivery, audit events, concurrency enforcement and authoritative
  plan/feature validation remain backend work as recorded in `API_CONTRACT.md`
  and `DATA-NEEDS.md`.
- Point 17B remains responsible for the recipient-facing onboarding UI and
  production invitation acceptance.

## POINT 17A — SIGNUP / ONBOARDING ARCHITECTURE & FOUNDATION (2026-09-12)

**Point 17 is split:** 17A (this session) = architecture, state machines,
security boundaries, contracts, repository seam, mock, UX contract. 17B =
production screens + integration. 17C = visual/security/a11y polish and
full-suite closure. **No production onboarding UI was built.** Architecture
was delegated to Claude in implementation mode (same override of
`report-before-implementing` as Points 12A–14A); rulings marked
**Claude-provisional** await Ahmed.

### A. Definition

Point 17 owns the tenant-admin entry journey: email/password and Google
authentication, email verification, Team Code tenant linking, first-use
account setup (incl. the Point 14 Main Admin `pending_setup → active` seat
event), the returning-user path and post-auth startup routing. Only
administrators authenticate; members are never accounts. Sign-up never creates
a `SaasTenant`.

### B. Five machines, never one flag (`onboarding_models.dart`)

| | Question | Type |
| --- | --- | --- |
| A. Authentication | who is this? | `AuthMethod {password, google}`, `AuthEntryOutcome` (`EntryReady` / `EntryVerificationRequired` / `EntryContinueOnboarding`) |
| B. Verification | owns the address? | `VerificationChallenge` (opaque handle, server-masked email, codeLength, expiresAt, resendAvailableAt, attemptsRemaining) |
| C. Tenant link | which tenant? | `TenantLinkStatus {unlinked, linked, withdrawn}` + `LinkedTenant {displayName, role, status}` |
| D. Setup | first use done? | `AccountSetupStatus {required, completed}` |
| E. Startup | which surface now? | `AuthEntryState` (`EntryNone{notice}` / `EntryRestoring` / `EntryVerificationPending` / `EntryOnboarding{stale}` / `EntryInvalid`) → `StartupInputs.entry` |

Account lifecycle reuses the envelope's `AccountStatus` (no competing enum).
`OnboardingSnapshot` = the restricted session's authoritative read; gating
fields fail closed on unknown values (`unsupported` → `/session-unsupported`),
contradictions throw (`EntryInvalid` → `/session-invalid`).

### C. Identity, methods, sessions

- **Canonical `accountId`** (backend, provider-independent); email = login
  identity/contact; a provisioned Main Admin account is *claimed*, keeping its
  Point 14 id. One account ↔ at most one tenant (multi-tenant = future).
- **Exactly two methods**: email/password, Google.
- **Session tiers:** none (verification pending — only a challenge handle) →
  **restricted onboarding session** (verified, not ready; may only read its
  snapshot, link, complete setup, sign out; backend answers everything else
  `onboarding_required`) → **full session** (existing `AuthUser` +
  `SessionAccess`), issued only when verified + linked + setup complete. A
  pre-onboarding identity has no `AuthUser` ⇒ `Capabilities.none` everywhere.
- **Storage:** tokens and the challenge handle in platform secure storage only
  (17B wires a secure store — `flutter_secure_storage` needs package approval;
  none exists today, `LocalStore` is SharedPreferences and must not be used).
  Never persisted: password, OTP, Team Code, Google token, reset token.

### D. Email/password + verification

Sign-up collects email + password only; **always** answers with a challenge
(new, provisioned-unclaimed, unverified-replaced, or a decoy for a verified
address + owner notice) — no session. Password sign-in: wrong/unknown/
Google-only → one `invalid_credentials`; unverified → challenge; verified not
ready → onboarding session; ready → full session. Code numeric, length/expiry/
attempts/cooldown **PROVISIONAL — BACKEND DECISION REQUIRED** (server-reported,
clock-rendered). Wrong → attempts narrow; exhausted/unknown → challenge ended
(journey closes with `EntryNotice.verificationEnded`); expired → resend on the
same challenge; verified elsewhere → this challenge ends, sign-in resumes.
Changing the address = abandon + sign up again (no in-place edit). Restart
resumes `/verify-email` from the stored handle without network. **Email OTP ≠
MFA.**

### E. Google

Backend verifies the ID token and owns mapping. `email_verified` true skips
MTM OTP; false → challenge. Existing Google account → sign in; provisioned or
unverified-password account → claimed (unverified password dropped, id kept);
verified password account → `auth_method_link_required`, **no automatic
merge** (Claude-provisional). Linking a second method later = future Security
feature with recent auth.

### F. Team Code

Link credential only — not a session secret, API key, role, password or grant.
Input canonicalized (Arabic-Indic digits folded, prefix optional), malformed
refused locally, sent once, stored nowhere. Backend matches the **verified
address** to an **authorization** in the code's tenant; code alone never links.
One `team_link_refused` for unknown / retired / no-authorization (no oracle);
`invitation_expired` and `tenant_unavailable` only after a match;
`account_already_linked` checked before the code is evaluated; same-tenant
replay = success; per-account/IP throttle. **Visibility: unchanged — Super
Admin only (hidden tenant-side)**; Main Admin read is recommended for Simple
Admin self-service → PROVISIONAL — PRODUCT/BACKEND DECISION REQUIRED. The setup
email must not contain the code (two channels).

### G. Initial Main Admin, replacement, Simple Admin

- Main Admin: Super Admin provisions address (seat `pending_setup`) → invitee
  signs up/Google with that address → verifies → Team Code → setup (display
  name + accept role) → backend runs `MainAdminPolicy.completeSetup` (or
  `.completeReplacement`: designate active, former holder revoked, sessions
  ended, `main_admin_replaced` Audit) atomically and issues the full session.
  Link reserves; only setup activates. Flutter marks nothing active.
- **No temporary password, no forced password change, no client-visible
  invitation token** (Claude-provisional; supersedes the Point 6 wording).
- Immediate replacement / cancelled replacement / tenant deleted before setup →
  link `withdrawn`, setup `setup_unavailable`, code refused. Tenant suspended
  or deletion pending → `tenant_unavailable`, seat untouched.
- **Simple Admin = invitation + Team Code (option B)**, invitation issued in
  the tenant by an `admin.manage` holder (issuing endpoint/UI future scope).
  Team Code alone cannot join (option C rejected).
- Role and grant always from the authorization, never from client input; the
  repository interface has no role/tenant/capability parameter.

### H. Setup, display name, reset, MFA

Setup = display name (suggested: inviter's name › Google name; editable;
collapsed; 1–80; not identity/authorization) + role acceptance. No Terms/
Privacy (deferred). Password reset = the **existing** `/forgot` → `/otp` →
`/new-password` flow; enumeration-safe request; no new route family; no
Platform reset. MFA enters **after** onboarding, on the full session (existing
`mfaRequired` hook); whether enrolment is mandatory is PROVISIONAL.

### I. Offline, idempotency, races

All trust transitions online-only → `Offline`, state unchanged, outbox
untouched (tested). Controller single-flights each operation, reuses an
`Idempotency-Key` (UUIDv7 from `newOperationIdProvider`) only while retrying
identical inputs after a transport failure, drops it on a definitive answer.
Drift codes (`requiresRefresh`) re-read the snapshot; `authentication_expired`/
`onboarding_required` → `EntryNone(sessionEnded)`; `setup_already_completed` →
`EntryNone(setupCompletedElsewhere)`. Offline refresh keeps the last snapshot
marked `stale` (routes, read-only).

### J. Startup precedence (extends Point 3; `resolveStartup`)

1 forced upgrade · 2 restoring · 3 expired · 4 invalid · **5 no full session
(signed out, or unknown with no account) → pre-session journey**:
a. entry restoring → `/startup`; b. `EntryInvalid` → `/session-invalid`;
c. verification pending → `/verify-email`; d. onboarding snapshot →
unsupported → `/session-unsupported`; account revoked/suspended; not linked or
withdrawn → `/link-team`; linked tenant deleted / deletion pending / suspended;
setup required **or complete-awaiting-exchange** → `/account-setup`;
e. nothing → `/login` (or unresolved offline) · then the unchanged full-session
order: expiry, unsupported, MFA, account, tenant, `pending_setup`, demo, role →
surface, no-access, requested route.
Deviations from the brief's sketch, deliberate: tenant lifecycle **before**
setup (a blocked tenant never invites anyone to finish — Point 3 rule);
verification needs no rank vs account lifecycle because a challenge exists only
before any session. A full session always wins over a stale entry state;
Super Admin → Platform; demo → demo; a snapshot can never yield a product or
demo surface (exhaustively tested).

### K. Routes

`/signup` (planned, public, 17B) · `/verify-email`, `/link-team` (new
startup-only destinations, **holding pages** in 17A) · `/account-setup`
(existing, re-scoped) · reset stays `/forgot`/`/otp`/`/new-password`. See
`SCREEN-ROUTE-MATRIX.md` ("POINT 17A FOUNDATION").

### L. Code (all new unless noted)

- `features/auth/domain/onboarding_models.dart`, `onboarding_repository.dart`
  (`OnboardingRepository`, `OnboardingProblemCode`, `OnboardingFailure`
  carrying `retryAvailableAt`/`attemptsRemaining`, `OnboardingErrorKind`,
  `onboardingErrorKindOf`).
- `features/auth/data/mock_onboarding_repository.dart` (+`OnboardingFixtures`
  mirroring Point 6/14 tenants/codes/addresses; `MainAdminSeatActivation` hook;
  release-gated like `MockAuthRepository`), `onboarding_controller.dart`
  (`onboardingRepositoryProvider`, `onboardingControllerProvider`,
  `authEntryStateProvider`).
- Modified: `core/startup/startup_destination.dart` (+`emailVerification`,
  `teamLink`, `StartupInputs.entry`, `onboardingDestination`),
  `startup_providers.dart` (wires entry), `status_pages.dart` (+2 holding
  pages), `strings.dart` (holding copy; `/account-setup` copy made accurate),
  `sign_out_controller.dart` (an active journey is ended by the same sign-out),
  `core/text/search_key.dart` (+`foldDigitsToAscii`).
- **Repository split:** `AuthRepository` = full session (unchanged);
  `OnboardingRepository` = every pre-full-session transition. 17B moves the
  login form's sign-in onto `OnboardingController.signInWithPassword` (whose
  `EntryReady` is today's full session) and backs both with one secure token
  vault.
- 17A leaves the controller's state at `EntryNone` at startup; **17B wires
  `restore()` into startup** (state `EntryRestoring` until it lands).

### M. Mock scenarios (`OnboardingFixtures`, password `mtm-fixture-pass`, code `246810`)

`huda@nabd-team.org` initial Main Admin (`saas_nabd`, `MTM-5JQX-2TWD`) ·
`reem@najd-response.sa` replacement designate (`saas_najd`) ·
`noura@hilal-medical.org` Simple Admin invite (`saas_hilal`, `MTM-4K7P-QX92`) ·
`late@hilal-medical.org` expired invite · `majed@rukn-medical.org` invite to a
suspended tenant (`saas_rukn`) · `unverified@`, `unlinked@`, `setup.pending@`,
`ready@`, `google.only@`, `suspended@mtm.test` · Google `mock-google:<email>` /
`mock-google-unverified:<email>` · `MTM-2222-3333` resolves to nothing. Test
hooks: `setTenantStatus`, `deleteTenant`, `withdrawAuthorization`,
`setAccountStatus`, `verifyElsewhere`, `completeSetupElsewhere`. All
expiry/budget constants are mock-only.

### N. UX contract for 17B

All screens: Arabic-first RTL, `EdgeInsetsDirectional`, theme tokens only,
existing `_auth_scaffold`/`StatusScreen`/button primitives, no new package
except the approved Google SDK and secure storage; 320dp @ 1.6× and 390dp
fit with a single scroll column, primary action reachable above the keyboard
(`MediaQuery.viewInsets`), no horizontal scroll; labels (never placeholder-only)
and `Semantics` on every field; errors announced via `SemanticsService`/live
region; focus moves to the first invalid field; respects
`MediaQuery.disableAnimations`. Copy never shows a wire code or server message
(map `OnboardingErrorKind`). Offline = inline notice «يتطلب هذا الإجراء
اتصالاً بالإنترنت» + disabled primary action; nothing queued.

1. **LOGIN `/login`** — purpose: sign in. Inputs: email, password. Primary:
   «تسجيل الدخول» (`signInWithPassword`). Secondary: «المتابعة باستخدام Google»,
   «نسيت كلمة المرور» (`/forgot`), «إنشاء حساب» (`/signup`); debug persona
   section unchanged. No Team Code field. Success: classifier routes
   (`/verify-email`, `/link-team`, `/account-setup`, `/home`, `/platform`,
   `/demo`). Failure: one generic sentence for `invalidCredentials`, plus a
   static hint «إن كنت أنشأت حسابك عبر Google فاستخدم زر Google» shown always
   (never conditional); `rateLimited` with a countdown when `retryAvailableAt`.
   Shows `EntryNone.notice` as one info line. Loading: button spinner, fields
   read-only.
2. **SIGNUP `/signup`** — inputs: email, password (show/hide; advisory 8+
   hint, server reasons verbatim-mapped). Primary «إنشاء الحساب». Secondary:
   Google, «لديّ حساب». No tenant/plan/role/capability/Team Code field. Success
   → `/verify-email` **always** (never "already registered"). Failure:
   `passwordRejected`, `invalidInput`, `rateLimited`.
3. **EMAIL VERIFICATION `/verify-email`** — shows server `maskedEmail`;
   `codeLength` digit boxes (one semantic text field, `autofillHints:
   oneTimeCode`, accepts Arabic digits/paste). Primary «تأكيد». Secondary:
   «إعادة الإرسال» with cooldown from `resendAvailableAt` (clock-driven
   countdown), «استخدام بريد آخر» / sign-out (= `abandon` → `/signup`).
   Success: classifier routes on. Failures: invalid (attempts left shown when
   known), expired (offer resend), ended (journey closes → login notice),
   throttled (countdown). Offline: code kept in the field, not submitted.
4. **TEAM LINK `/link-team`** — explains why (a code from your platform
   contact or Main Admin + an invitation to this address); shows «مسجّل
   باسم <email>»; `withdrawn` shows «سُحبت الدعوة السابقة». Input: Team Code
   (monospace LTR island inside RTL, auto-grouped, uppercase). Primary «ربط».
   Secondary: sign-out, support. Success → `/account-setup` showing the
   tenant display name + role (the **only** tenant data before setup). Failures:
   malformed (inline, local), refused (one generic sentence: «تعذّر الربط بهذا
   الرمز. تأكد من الرمز ومن أنك تستخدم البريد الذي دُعيت به»), invitation
   expired («اطلب دعوة جديدة»), tenant unavailable, already linked, rate
   limited (countdown). Field cleared after success; never restored.
5. **ACCOUNT SETUP `/account-setup`** — shows tenant name + role card; input
   display name prefilled from `displayNameSuggestion`; primary «إكمال
   الإعداد» (`completeSetup`); secondary sign-out. If the snapshot is already
   complete: «جارٍ إنهاء الإعداد» + retry (the exchange). Success → full
   session → classifier. Failures: drift codes refresh and the classifier moves
   the screen; `invitationExpired`, `tenantUnavailable` explained; full-session
   `pending_setup` case keeps the holding copy.
6. **RETURNING USER** — finished accounts go straight to their surface; partial
   states resume at their step; a stored challenge resumes offline; an
   onboarding session offline shows its step read-only (`stale`).
7. **PASSWORD RESET** — existing screens; copy made enumeration-safe («إن كان
   البريد مسجّلاً فستصلك رسالة»).
8. **GOOGLE** — button on login and signup (Google brand rules), cancellation
   by the user is silent, `googleRetry` offers retry, `methodLinkRequired`
   «هذا البريد مسجّل بكلمة مرور. سجّل الدخول بكلمة المرور.»
9. **ERROR/RETRY** — `OnboardingErrorKind.retryable` decides whether «إعادة
   المحاولة» is offered; countdowns use `retryAvailableAt` + `clockProvider`.
10. **OFFLINE** — see header; no screen spins forever.

### O. Tests and checks (focused only; full suite is 17C)

- New: `test/features/auth/onboarding_models_test.dart` (20),
  `onboarding_repository_test.dart` (41, incl. Point 14 seat integration via
  `MockPlatformMainAdminRepository.simulate*` and fixture parity with
  `PlatformTenantStore`), `onboarding_controller_test.dart` (22),
  `test/core/startup/onboarding_startup_test.dart` (31: partial-state table,
  precedence, exhaustive "no product surface from a snapshot", full-session
  wins, Super Admin, demo, router walls with deep links, sign-out). Updated:
  `startup_classifier_test` (page ownership), `status_screens_test` (+2 pages).
- Affected auth/startup/router/settings-security/hub suites: **461 passed**
  (plus a mistyped nonexistent path in the command, not a test);
  `saas_tenant_repository_test` 40/40; final new+adjacent run **175/175**.
- `flutter analyze`: **No issues found.** `git diff --check`: clean.
  `dart format` on touched files.
- Bug caught during 17A: `whenComplete(() => map.remove(op))` returned the
  removed future and awaited itself — fixed with a block body and commented.

### P. Audit / privacy

Backend-appended only. PROVISIONAL `main_admin_setup_completed`
(`account_management`, `main_admin_account`, actor `system`) — not added to the
Flutter catalogue until confirmed; existing `main_admin_replaced` covers
designate completion. Simple Admin acceptance → future tenant audit. Login/OTP/
Team Code failures → security events. Never audited or logged: passwords, OTP,
Team Code, reset/Google/onboarding tokens, challenge handles, MFA secrets —
`toString`s redact the handle and Google token; failures never echo inputs.

### Q. Open decisions — PROVISIONAL — BACKEND/PRODUCT DECISION REQUIRED

1. Team Code tenant-side read (recommend: Main Admin seat holder, read-only).
2. Simple Admin invitation issuance (who, endpoint, UI) — model is fixed (B).
3. Temporary password: **none** (Claude-provisional; supersedes Point 6's
   "forced password change").
4. Google ↔ password linking: no auto-merge; explicit linking later.
5. OTP length/expiry/attempts; 6. resend cooldown; 7. password policy
   (client floor 8 is courtesy); 8. lockout budgets.
9. Session issuance: none before verification, restricted before readiness
   (Claude-provisional).
10. Whether MFA enrolment is mandatory for admins, and where it is enforced.
11. Recovery after lost MFA / lost email — no bypass defined.
12. Invitation expiry (Point 14 mock: 7 days) and whether suspension/deletion
    invalidates pending invitations automatically.
13. One account ↔ one tenant forever? (multi-tenant is future scope).
14. Refinement of Point 14 "designate must be a brand-new identity": allow an
    **unlinked** existing account (no authority anywhere) to be designated.
15. Reset completion marks the address verified and ends all sessions.
16. `main_admin_setup_completed` Audit action.

### R. Not done here (by design)

No final login/signup/OTP/Team Code/setup screens, no Google SDK, no secure
storage package, no startup hydration wiring, no Point 16 overflow/tab-font
fixes, no `stats.view` change, no Point 18.

**POINT 17 IS NOT YET COMPLETE.**

**NEXT: POINT 17B — SIGNUP / ONBOARDING CORE IMPLEMENTATION & INTEGRATION.**

**POINT 18 WAS NOT STARTED.**

---


## POINT 16 — SIMPLE ADMIN EXPERIENCE AUDIT (2026-09-12)

**POINT 16 — COMPLETE.** An audit of the tenant application from a
`role: admin` session's side, with narrow fixes. No key, preset, role, route
family, check order, package or visual system changed; no permission editor,
no Point 17 work.

### A. Scope and method

- Read the access core (`capability.dart`, `capability_guard.dart`,
  `admin_experience.dart`, `detachment_access.dart`), the router (every
  tenant route and its guard; go_router 14.8.1 runs every matched route's
  redirect, so `report/preview` inherits `report`'s guard), the startup
  classifier, `MainShell`, Home, the More hub, both detachment shells and
  every tab, member/inventory/detachment/workshop forms, announcements,
  Notifications (feed filter + destinations), Global Search (index + tap-time
  re-check), Needs Review / conflict resolution / sync classification,
  Profile/Security, Organization/Plan, the Problem layer.
- **Route inventory:** now a table in `SCREEN-ROUTE-MATRIX.md` §4.0 (Main Admin
  vs Simple Admin, Feature, Capability, refusal target). **Action mapping:**
  `CAPABILITIES.md` → "The Simple Admin experience, audited".
- **Role-vs-capability sweep:** every `AuthRole` read outside `features/
  platform` is surface selection (startup classifier, login redirect) or a
  label (profile, status pages, demo personas). No `role == mainAdmin`
  authorization and no `role == admin` denial exists; nothing corrected.
- **Five-fixture matrix** (real keys only): A minimal (`detachment.view`),
  B operations (roster + shifts), C inventory, D reports (`stats.view`),
  E broad (sub-Admin preset + `announcement.publish`), plus the shipped
  Simple Admin persona.

### B. Findings

**Critical — none.** No authorization bypass or unintended mutation path:
every mutation route is guarded; controls resolve through `canIn` /
`DetachmentAccess`; announcements re-validate at publish and withdraw; search
and notifications re-check at the tap; conflict "keep mine" enqueues a new
write the server re-authorizes.

**High — 2, fixed.**

1. **H1 — a granted detachment could not be opened from the Detachments tab.**
   Every card pushed `/detachment/:id/team`, whose route needs `member.view`;
   a Simple Admin without it (fixtures A, C, D) was bounced to Home, and the
   shell offered a Team tab that did the same. Fix: new pure
   `features/detachment/domain/detachment_tabs.dart`
   (`detachmentTabOffered`, `detachmentTabFor` — moved from Search, which
   re-exports it); the list lands on Team with `member.view`, else Shifts;
   the shell's tab bar drops Team without `member.view` and Stats without
   `stats.view`, **always keeping the tab being stood on** (a direct link or
   a mid-session narrowing never leaves the bar unselected).
2. **H2 — `detachment.archive` alone could rename a detachment.** The edit
   form enabled name/region/centre/notes for any session that could open it
   and saved them. Fix: fields follow `detachment.edit` (which
   `DetachmentAccess` already closes on a finished detachment); an
   archive-only session sees a quiet note («يمكنك تغيير حالة هذه المفرزة
   فقط…») and its save writes **status only**, from the repository's current
   record — so it also cannot overwrite a rename made elsewhere.

**Medium — 3, fixed.**

1. **M1 — Stats denial read as "no data yet".** Without `stats.view` the tab
   said «لا إحصائيات بعد… بعد أول أسبوع» — a permission told as emptiness.
   Now the tab is not offered (H1) and a direct link shows
   «إحصائيات هذه المفرزة غير متاحة لحسابك» + who can grant it.
2. **M2 — notification preferences for disabled modules.** The stock and
   workshop switches showed while `inventory` / `workshops` were off (dead
   controls). Now absent; the stored values are untouched.
3. **M3 — plan limit and feature refusals were unrecognised.** The contracted
   `plan_limit_reached` and `feature_disabled` fell back to the generic
   "unexpected" copy, indistinguishable from each other and from
   `not_permitted`. Added both to `ProblemCode` + `resolveProblem` (Core-owned
   global codes, per the error-architecture rule) with their own localized
   sentences; neither says «صلاحية»; not retryable. No local limit check was
   added — the server stays authoritative.

**Low — 1, fixed.** Search's stock result opens a modal sheet the router never
sees; the tap now re-asks the Inventory module as well as the grant.

**Recorded, not changed** (established or pre-existing, per CLAUDE.md):

- Detachment-group delete rides `admin.manage`, detachment delete rides
  `detachment.archive` — established; no dedicated keys exist.
- Home's organisation tile is still a full-experience breadth shortcut
  (`org.edit`); a Simple Admin reaches Organization/Plan from More.
- The report composer's roster/stock sections ride `stats.view` (§3 ruling:
  statistics are named-individual data).
- Workshop statistics carry no capability (see Backend gaps).
- **Pre-existing layout, found by the audit, not Point 16 changes:** at
  320dp × 1.6 the Shifts tab body overflows (`detachment_shifts_tab.dart`
  :399 column, :870/:991 rows) — identical for the Main Admin; with the
  flutter_test square-glyph font the detachment list's filter row (:118) and
  card count row (:410) and the workshop list row (:267) overflow at phone
  widths (the real-font renders of Home/More/forms did not).
- `AnimatedTabBar` sets its label style through `AnimatedDefaultTextStyle`
  with no `fontFamily`, which replaces the inherited IBM Plex style — tab
  labels fall back to the platform font (tofu in the render harness).

### C. Per-area results

Home: quick actions exactly the reachable set (A: shifts + storage; E: +
members, stats, announcements); no organisation section for a scoped grant;
alerts filtered by module and grant. Detachments: H1/H2. Shifts/Attendance:
every control on its own key via `DetachmentAccess`; sheets degrade to the
schedule tab without shift keys. Team: roster/member pages on `member.view`,
contact on `member.contact.view`, deactivate on `member.deactivate`.
Inventory: `adjust` vs `item.manage` independent; module-gated tab, form,
search, alerts and notifications. Statistics/Reports: M1; report and preview
on `stats.view`. Workshops: tab with any `workshop.*`, each action its own
key; list readable without one (ruled). Announcements: publish/compose on
`announcement.publish` anywhere, withheld by the preset; reading on
`detachment.view`. Notifications: kinds filtered by grant in the target's own
detachment, module-filtered, tap re-reads the record. Search: scope-first
index, module-filtered categories, tap-time grant (+ module, L1) re-check,
active detachments only. Archive/History: `historicallyClosedCapabilities`
closes every operational write; reading stays. Sync/Conflict: own writes
only; replay re-authorized server-side (gap below). Profile/Security:
personal, ungated; role label «مدير مساعد». Organization/Plan: Point 15
verified — both roles, Team Code absent, Main Admin email absent, usage
withheld without `org.edit`, `/more/org` redirects.

Lifecycle/session: suspended / deletion-pending / deleted and an expired
session each eject an open detachment screen; deep links, notification and
search destinations and Back all meet the same wall. A key revoked under an
open inventory form closes it and Back does not restore it. Super Admin
isolation: all 19 `/platform/**` paths (Main Admin management, reports,
break-glass, audit, health, features, subscription, limits) turn both the
persona and the broadest fixture around to `/home`. Main Admin parity: a
`main_admin` holding fixture B's keys gets B's tabs and routes exactly.

### D. Tests, renders, checks

- New `test/features/auth/simple_admin_experience_test.dart` — 38 tests
  (fixture route matrix A–E, H1/H2/M1/M2/M3 regressions, Feature Flags,
  lifecycle ×3, session expiry, back stack, notification/search pure checks,
  parity, role label, Organization/Plan, 320×1.6 and 390 layout of the
  changed surfaces). Walks outlast the page transition per hop (two
  `MainShell`s must never be mounted at once) and run at 800dp because the
  flutter_test font overflows pre-existing rows at phone widths.
- Render harness `test/features/auth/simple_admin_render.dart`
  (`@Tags(['render'])`, skipped without `MTM_RENDER_DIR`): 18 PNGs — Home 390
  Light / 320×1.6; More minimal / broad Dark Cyber; feature-disabled; stats
  permission 390 / 320×1.6; minimal tabs Dark Cyber; tenant suspended;
  Organization; Plan (maxima); inventory storage; reports composer;
  Organization offline Dark Cyber; status-only edit Eye Protection / 320×1.6;
  notification prefs Purple Arena; Home broad Dark Cyber reduced motion. All
  inspected; no layout exception in any.

      MTM_RENDER_DIR=/tmp/mtm-simple-admin flutter test \
        test/features/auth/simple_admin_render.dart --tags render --update-goldens

- RTL throughout; tokens only (no hex, `palette_contrast_test` unaffected);
  no motion added; the new notes/states use existing `EmptyState` /
  note patterns (text + icon, never colour-only); hidden tabs/rows are absent
  from semantics, not disabled.
- Focused: touched areas 235/235 (problem, admin routes, search, detachment,
  tenant feature, settings); Point 16 file 38/38; affected route/nav/feature/
  notification/organization/platform-routing suites 741/741.
- `flutter analyze`: **No issues found.** `git diff --check`: clean; new
  files checked for trailing whitespace; `dart format` changed only new lines.
- Full `flutter test`: **1886 passed, 0 failed** (1848 + 38). Two single-shot
  runs were killed by the host's low-memory guard (other applications held
  ~10 GB) before finishing — not test failures — so the same suite ran as
  three sequential `--concurrency=3` chunks covering every test directory:
  core + verify + about/announcement/app_version/auth 694, the twelve tenant
  feature folders 551, platform 641.
- `graphify update .`: 11,434 nodes / 17,584 edges / 335 communities.

### E. Backend gaps (genuine)

1. A terminal rejection for replayed writes: `not_permitted` /
   `feature_disabled` / `plan_limit_reached` on a queued operation is
   classified `failed` (retryable) today — `DATA-NEEDS.md` §4 item 11.
2. Grant freshness/revision for faster revocation — item 12.
3. Tenant create endpoints must return `plan_limit_reached`; the client now
   renders it — item 13; `API_CONTRACT.md` → Errors (Point 16 clarification:
   never answer a disabled module or an exhausted limit with `not_permitted`).
4. Whether workshop statistics need a read key — item 14 (product).
5. Capability management UI (grant/revoke per detachment) remains
   admin-dashboard / backend scope; not built.

**POINT 16 — COMPLETE.**

**NEXT: POINT 17 — SIGNUP / ONBOARDING.**

**POINT 17 WAS NOT STARTED.**

---

## POINT 15 — ORGANIZATION + PLAN SCREENS (2026-09-12)

**POINT 15 — COMPLETE.** Two read-only tenant screens, `/more/organization`
and `/more/plan`, composed from existing architecture: the canonical
`PlatformTenantStore` record (Points 6–9), Point 7's `SaasSubscription` /
`PlanLimitKey` / effective-limit rule, Point 8's runtime entitlement, and the
existing `/more` hub, theme tokens and settings widgets. No billing, no Platform
mutation, no new capability key, no new package.

### A. Attendance regression cleanup (before Point 15; not a numbered Point)

- **Repro:** `dashboard_states_test` at 320dp with a busy running shift (three-
  digit counts): RenderFlex overflow at `dashboard_cards.dart:628` —
  **64px at 1.6×**, 143px at 2.0×. The earlier cleanup fixed the header and
  `_ManagerLine` but not this row (it only fit with small counts).
- **Cause:** the `_AttendanceSummary` count row was
  `Row(label, Spacer, AnimatedCounter, "/ assigned")` — nothing flexible, in a
  254dp card body.
- **Fix:** a `Wrap(spaceBetween)` — label at the start, count at the end while
  both fit (identical at 1×); the count drops under the label when they do not,
  and "/ assigned" under the present figure only in the extreme. No font
  shrinking, no clipping, no `FittedBox`; RTL order and every figure kept.
- **Guard:** `dashboard_states_test.dart` → "attendance summary at narrow widths
  and large text" (320dp at 1.6× and 2.0×, asserts no exception and that the
  label, "/ ١٢٠" and the open-count pill are all present). `_pump` gained
  `width`/`textScale`. The summary carries `Key('dashboard-attendance-summary')`.

### B. Architecture (reused, one small seam added)

- `features/organization/` — `OrganizationRepository.readCurrent()` (no tenant
  id parameter: the backend derives it from the bearer; **no write method**) →
  `OrganizationSnapshot` {tenantId, displayName, lifecycle, createdAt,
  mainAdminName, subscription {status, plan, dates}, limits {usageIncluded,
  items, unsupportedCount}, readAt}. The Point 7-anticipated read-only tenant
  adapter.
- `MockOrganizationRepository` projects the **same** store record; effective
  limits come from `SaasSubscription.effectiveLimit` (the canonical
  `override ?? planDefault`), usage from `mockTenantPlanUsage` — extracted from
  `MockTenantSubscriptionRepository` so Platform and tenant share one
  derivation. Modes: loaded / stale / offline (last-read cache) / failure /
  unsupported.
- `organizationSnapshotProvider` (autoDispose) is the one read both screens
  render; Plan pushed over Organization reuses it. Demo and non-tenant sessions
  short-circuit to `tenant_context_unavailable`.
- Feature availability is **not** copied into the read: Plan reads
  `currentTenantFeatureAccessProvider`, the answer navigation already obeys.
- Tenant parsing **fails safe** (Platform parsers refuse): unknown lifecycle /
  status / plan → unsupported; unknown limit key → counted, not rendered;
  omitted known key → "unavailable". Never active, Basic, enabled or unlimited.

### C. Organization (`/more/organization`)

Identity-forward and calm: monogram (initial of the organisation's own name,
definite article skipped) + name as a heading; two independent chips — access
(lifecycle) and subscription (commercial); "بيانات المؤسسة": registered date,
Main Admin display name, organisation reference (tenant id, LTR island,
selectable, 48dp copy); a "الخطة" row → Plan; a note that the platform owns
this data, with "تواصل مع الدعم" → About. ≥760dp content: two columns. No
edit, rename, lifecycle, Team Code or seat action exists.

- **Team Code decision: NOT shown.** No contract authorizes a tenant-side read
  (`team_code.dart`: "nothing in the tenant feature tree imports this file";
  Points 12–13 exclude it from every payload). Recorded in `API_CONTRACT.md` →
  Team Code semantics. Point 17 may introduce an explicitly authorized read;
  never an edit/regenerate/rotate/revoke.
- **Main Admin context decision: display name only.** Login email, account
  state, setup/replacement detail and reasons stay Platform-only (Point 14). No
  resend/suspend/replace/session/MFA/password action.
- **Old page removed:** the pre-SaaS `OrgInfoPage` (`/more/org`, legal name,
  address, public email, counts from `SettingsRepository.orgInfo`) is gone;
  `/more/org` redirects to `/more/organization`. Its name disagreed with the
  canonical tenant name and its counts duplicated plan usage. The
  `SettingsRepository.orgInfo` seam is kept (no UI consumer) — open decision
  recorded in `API_CONTRACT.md`. Its five now-unused strings were removed.

### D. Plan (`/more/plan`)

Plan heading (Basic «الخطة الأساسية» / Standard «القياسية» / Advanced
«المتقدمة» / «لا توجد خطة معيّنة» / «خطة غير معروفة»), organisation name,
one-line plan purpose; subscription chip + its one relevant date (trial end /
"التجديد الإداري القادم" / grace end) + a neutral note for grace, inactive and
unknown. The grace note states no day count — the provisional 14-day mock rule
is never presented as contractual.

- **Limits:** one row per key: name, "usage / limit" (Arabic-Indic figures
  read right-to-left, usage first — same order as Home's attendance count), a
  6dp determinate track (no animation, excluded from semantics — the row
  announces "المفارز، الاستخدام ٢٣ من ٤٠، ضمن الحد"), "حسب الخطة" or
  "حد مخصّص لمؤسستك · حد الخطة N". At/over limit: warn icon + words ("بلغ
  الحد" / "تجاوز الحد") + a note (over: nothing deleted). No "near limit".
  No plan → a note, no rows, never "unlimited". Unsupported keys → a note.
- **Usage visibility:** organisation-wide usage needs `org.edit` — the rule
  that gated `/more/org` before — now enforced *in the read*. A session without
  it (the Simple Admin persona) sees maxima ("الحد الأقصى ٤٠") and a note.
- **Modules:** Inventory, Statistics/Reports, Workshops, Announcements, each
  with label, description and an enabled/disabled chip (icon + text). An
  unreadable entitlement is stated, not drawn as four disabled rows.
- **Explanation ("عن الإتاحة"):** the platform sets plan, limits and modules;
  a module being available does not grant the account permission; a missing
  tool may be a permission, not the plan. Plus support. No price, currency,
  upgrade, downgrade, cancel, renewal charge or payment anywhere.

### E. Routes, navigation, roles

- Routes in the tenant `/more` branch: `organization`, `plan`, `org` →
  redirect. Hub: the "المؤسسة" section now always shows «المؤسسة» and «الخطة
  والاشتراك» (no `org.edit` gate — `showsOrganisation` removed). Home's
  existing organisation tile now targets `/more/organization` directly.
- **Main Admin:** both screens, with usage. **Simple Admin:** both screens,
  usage withheld (from the grant, not a role check). **Super Admin:** turned
  around by the surface redirect from all three paths; the read itself returns
  `tenant_context_unavailable`; Platform More stays an allowlist without them.
- Tests changed on purpose (the gate moved, not weakened):
  `admin_experience_routes_test` (scoped admin now reaches Organization/Plan;
  mid-session narrowing now uses `/detachment/…/edit`), `settings_hub_test`
  (Plan row; taller surface), `platform_more_test`, route lists in
  `app_router_test`, `platform_routing_test`, `startup_routing_test`,
  `super_admin_routing_test`.

### F. Offline/stale, responsive, themes, accessibility

- Offline with cache: notice «لا يوجد اتصال…» + `readAt` + 48dp «تحديث» (a
  read, never a replay). Refresh failed: a different notice. Offline without
  cache: its own state with retry. Failure: problem pipeline + retry. No
  polling, timers, queue or outbox.
- 320/390/600/900dp and 320dp × 1.6 (both screens, including every limit over
  its maximum) lay out without exception; facts go side-by-side → stacked by
  text-scaled width; rows use `Wrap` so figures/chips take their own line.
- Dark Cyber, Purple Arena, Light, Eye Protection: tokens only, no hex added
  (`palette_contrast_test` unaffected). Reduced motion: nothing animates on
  either screen.
- Semantics: name and section titles are headers; the plan heading announces
  «الخطة الحالية: …»; chips are their own nodes announcing what they are the
  status *of* (a render-found bug: two chips merged into one announcement —
  fixed with `container: true`); limit and module rows carry one full
  announcement; the fact rows merge label+value but keep the copy button
  separately focusable; the freshness notice is a live region.

### G. Tests, renders, checks

- New: `organization_models_test.dart` (18), `organization_plan_screens_test.dart`
  (59). Attendance: 2 new cases in `dashboard_states_test.dart`.
- Render harness `test/features/organization/organization_plan_render.dart`
  (`@Tags(['render'])`, skipped without `MTM_RENDER_DIR`): 16 PNGs — org 390
  Light / 320×1.6 / 900 / offline-cached Dark Cyber / offline no-cache; plan
  Basic 390 Light, Standard+override 390 Dark Cyber, Advanced 390 Purple Arena,
  grace + at/over 320×1.6, 600, at/over 900, Eye Protection, stale,
  unsupported, Simple Admin, no-plan trial Dark Cyber + reduced motion.
  Inspected; fixed: a bidi-misleading LTR wrapper on the figures (removed —
  the RTL order was already the correct reading order), a date label wrapping
  at a third of the row (fact row now loose/loose), module chips not aligned
  at the row end (column stretch), and the chip semantics merge above.

      MTM_RENDER_DIR=/tmp/mtm-org-plan flutter test \
        test/features/organization/organization_plan_render.dart --tags render --update-goldens

- Focused: organization 77/77; Home + tenant-feature + settings + auth +
  router + startup + Point 7 subscription + Platform More/routing: 522 passed
  (the 523rd entry was a mistyped filename, not a test).
- `flutter analyze`: **No issues found.** `git diff --check`: clean (new files
  checked for trailing whitespace too). `dart format`: only new lines changed.
- Full `flutter test`: **1848 passed, 0 failed** (one run; was 1769 before — +79: 77 organization, 2 attendance).
- `graphify update .`: 11,347 nodes / 17,416 edges / 329 communities.

### H. Backend gaps (genuine, not billing)

1. `GET /api/v1/tenant/organization` (tenant from bearer), with
   **server-side** usage withholding for sessions without `org.edit`.
2. A real `admins` usage aggregate (the mock and Point 7 use a fixed 1).
3. Server-computed `effective` per key (`override ?? default`) and the
   `overridden` marker, so no client recomputes the rule.
4. Whether legal name / address / public email (pre-SaaS `OrgInfo`) join this
   read, and whether `org.edit` ever edits them — product decision.
5. Whether the Team Code becomes tenant-readable for onboarding (Point 17).
6. Cache/freshness: the backend should return `readAt`; the client shows it on
   a cached copy. Durable offline persistence of this read is not built (the
   mock caches for the app's lifetime).

Billing (checkout, invoices, payment method, upgrade/downgrade, renewal
charges, promo codes, currency) is future scope only and not specified.

**POINT 15 — COMPLETE.**

**NEXT: POINT 16 — SIMPLE ADMIN EXPERIENCE AUDIT.**

**POINT 16 WAS NOT STARTED.**

---

## POINT 14C — MAIN ADMIN ACCOUNT MANAGEMENT FINAL UX, VISUAL VALIDATION & CLOSURE (2026-09-12)

**POINT 14 — COMPLETE.** Presentation-only closure pass over 14B, following the
repo design sequence (`frontend-design` → `impeccable` polish → `emil-design-eng`).
**14A architecture preserved:** seat invariant, state machine, six-action
catalogue, lifecycle matrix, repository seam, typed problem codes, atomic
backend transfer, recent-auth semantics, online-only/no-outbox, audit/privacy
model — no domain, data, provider, controller or route file was touched.
**14B core preserved:** both routes, every state, all five commands,
confirm-once flow, stale/idempotency handling and the Audit catalogue behave as
before; every 14B test passes unmodified.

### A. What 14C changed (found by rendering, then fixed)

- **Account vs tenant state.** The management page now shows the team's
  access state as its own chip under the team name (`وصول الفريق نشط/موقوف`,
  `الفريق بانتظار الحذف`; neutral or warn, never red), apart from the account
  chip inside the seat card (`حساب نشط/موقوف`). Both are text-labelled; colour
  is never the only signal. The blocked-tenant notice now states that account
  actions do not change the tenant's state.
- **Holder vs designate.** The seat card title is `صاحب المقعد الحالي`; the
  designate block keeps `المرشح لاستلام المقعد` + "not yet a Main Admin". The
  designate's resend button reads `إعادة إرسال دعوة المرشح` (it used to share the
  holder's label), and its confirmation names the recipient email (LTR).
- **Less red.** Cancel replacement is a neutral outlined action — it leaves the
  holder untouched. Suspend is the only red action on the page.
- **Confirmations.** The shared `showPlatformConfirmationSpec` gained an
  additive `dismissLabel` (default unchanged for every other caller). All Main
  Admin dialogs dismiss with `تراجع`, so cancel-replacement no longer shows
  «إلغاء» next to «إلغاء الاستبدال». Resend names the recipient email;
  reactivate names the holder; suspend shows the holder name + LTR email
  before the reason. Still one confirmation per command and no typed name.
- **Reason fields.** Label shortened to `السبب الإداري` (the 1.6× floating label
  was truncating); the Platform-only purpose moved to the helper text;
  `helperMaxLines`/`errorMaxLines` stop helper/error truncation.
- **Replace page.** Current-holder context (name + LTR email) now precedes the
  mode note and fields. The email `TextField` is LTR through `textDirection`
  only — the Arabic label/helper/error stay RTL, fixing an error message whose
  full stop rendered on the wrong side. Server feedback is an icon notice.
- **Offline/stale cached seat.** "No actions for this state" was misleading;
  a read-only notice now says why (offline vs not refreshed), shows the
  snapshot's `readAt` and offers a 48dp `تحديث الحالة` read. No write, replay
  or queue copy.
- **Tenant-detail summary.** Labels now read `صاحب المقعد الحالي` /
  `بريد تسجيل الدخول`; they said "first admin", which is wrong after a
  replacement. No action in the summary other than navigation.
- **Semantics.** Section titles are headers; the account chip is announced as
  `حالة حساب المدير الرئيسي: …`; duplicated container labels (identity, designate
  block, actions) were removed so nothing is read twice; seat and action
  columns are separate groups, so reading order stays seat → actions at ≥900dp.
- **Copy.** Removed "Flutter" from the replace confirmation; gender-neutral
  wording in the replacement/suspend/reactivate lines; two grammar fixes; the
  unused `mainAdminReviewConsequences` string was removed. New strings are in
  `S`; the Point 14 presentation files have no hard-coded Arabic or rendered
  wire values (wire only appears inside widget `Key`s).

### B. Matrix results

- **Widths:** 320/390/600/900dp over active, pending setup, suspended account,
  pending replacement and suspended tenant — no overflow; ≥900dp keeps the
  seat/actions columns.
- **320dp × 1.6×:** every seat state, the replace form with errors and the
  suspend dialog with a reason — no overflow, every action reachable. Long
  emails wrap at the hyphen and stay LTR; the suspend dialog content scrolls.
- **Themes:** Dark Cyber, Purple Arena, Light and Eye Protection rendered and
  inspected; only semantic tokens are used and no hex value changed, so
  `palette_contrast_test.dart` still holds.
- **Reduced motion:** Point 14 adds no motion; the render with animations off
  shows the static confirmation. No bounce, pulse or new transition.
- **Touch targets:** all actions, the refresh read, the submit and the summary
  navigation are ≥48dp; dialog buttons use the theme's defaults.

### C. Render-output matrix

New opt-in harness `test/features/platform/platform_main_admin_render.dart`
(same pattern as the break-glass one; `@Tags(['render'])`, skipped without
`MTM_RENDER_DIR`, PNGs outside the repo). 16 PNGs were rendered into the session
scratchpad, inspected, fixed and re-rendered: tenant summary 390 Light; active
390 Light; pending setup 390 Dark Cyber; suspended 390 Dark Cyber; replacement
390 Purple Arena; replace with validation 390 Light; replacement 320 × 1.6;
account + tenant both suspended 600 Light; replacement 900 Light; pending setup
Eye Protection; offline cached; unsupported fail-closed; recent-auth; suspend
dialog 320 × 1.6; cancel dialog Purple Arena; reactivate dialog with reduced
motion. Run it with:

    MTM_RENDER_DIR=/tmp/mtm-main-admin flutter test \
      test/features/platform/platform_main_admin_render.dart --tags render --update-goldens

### D. Tests, analyzer, suite, diff, Graphify

- New `platform_main_admin_polish_test.dart` (35): account/tenant labels,
  announced account status, holder/designate labels, distinct dialog
  buttons, designate recipient, read-only offline notice, suspend dialog
  context, RTL email messages, the 4-width × 5-state matrix and 320 × 1.6.
- Focused 14A + 14B + 14C + affected tenant-detail/routing/Audit/appearance/
  lifecycle: **215/215 passed**. `saas_tenant_create_test.dart`: 15/15.
- `flutter analyze`: **No issues found.** `dart format`: clean.
- Full `flutter test`: first run found 2 failures. (1) A Point 14
  regression 14B never ran: `saas_tenant_create_test` still expected the Point 6
  provisioning label, but since 14B the summary shows the seat's account status.
  The expectation now asserts `S.mainAdminStatusPending` +
  `S.mainAdminSummaryPending`. (2) `tenant_feature_access_test.dart` → "remaining
  destinations stay stable at 320dp and 1.6 text": a RenderFlex overflow in the
  **tenant Home dashboard** (`features/home/presentation/widgets/dashboard_cards.dart`
  :138 active-shift header with `LockWindow`, :563 `_ManagerLine`). No Point 14
  file or anything 14C touched is involved, so it was **left unfixed** per the
  repo rule. Final rerun: **1768 passed, 1 failed** (that same Home test).
- **Regression cleanup (2026-09-12, after 14C — not a numbered Point):** the
  Home failure above was reproduced in isolation (width 320, textScale 1.6).
  Cause: two rigid rows in `CurrentShiftCard`. The `LockWindow` chip measured
  263dp against a 254dp header, leaving the `Expanded` title 0dp; the unflexed
  `مسؤول الشفت:` label plus icon took 255dp, leaving the manager name 0dp.
  Fix: the header's `LayoutBuilder` keeps the chip beside the title only when
  the header is ≥ 16 countdown ems wide (`textScaler.scale(15) * 16`), and
  otherwise stacks it under the time. `_ManagerLine` is a `Wrap`, so the name
  takes its own line. `LockWindow`'s caption column is a loose `Flexible`, so
  a bounded chip wraps its caption; unbounded placements keep their natural
  width. 1× layout at 400dp is unchanged. No test expectation changed. Home +
  shift + tenant-feature tests 152/152; `flutter analyze` clean; `git diff
  --check` clean; full `flutter test` **1769 passed, 0 failed**. Seen but
  left out of scope: at 2.0× text (beyond the 1.6× contract) the
  `_AttendanceSummary` count row still overflows.
- `git diff --check`: clean (the new untracked files were also checked for
  trailing whitespace). `graphify update .` (final, after docs): 11,080 nodes /
  16,987 edges / 344 communities.

### E. Files

Modified: `platform_main_admin_page.dart`, `platform_main_admin_replace_page.dart`,
`platform_main_admin_copy.dart`, `saas_tenant_detail_page.dart` (summary
labels), `widgets/platform_confirmation_dialog.dart` (additive `dismissLabel` +
dismiss key), `l10n/strings.dart`, `test/.../saas_tenant_create_test.dart`
(one stale expectation). Added: `test/.../platform_main_admin_polish_test.dart`,
`test/.../platform_main_admin_render.dart`. Docs: `API_CONTRACT.md`,
`CAPABILITIES.md`, `DATA-NEEDS.md`, `SCREEN-ROUTE-MATRIX.md`, this handoff.

### F. Regression check (reconfirmed)

Exactly one current seat; at most one pending replacement; no stand-alone
revoke; no email edit; no Platform password reset; no MFA/session controls;
no impersonation; no Simple Admin management; Point 17 untouched (no signup,
OTP, Google, Team Code, `/account-setup`); backend-owned atomic transfer;
online-only commands, no outbox; recent-auth still → sign-out dialog, no
step-up; tenant lifecycle restrictions intact; deleted tenant → tombstone, no
seat; Audit read-only; no secret fields; management/replace pages build no
tenant operational repository (asserted by every render).

### G. Backend/product gaps (unchanged, not decided in Flutter)

Invitation validity (mock 7 days) and whether invitations expire; resend
throttling; whether invitations are auto-cancelled on tenant suspension or
deletion; brand-new-identity-only replacement; the recent-auth command matrix
and freshness window; notification emails to the outgoing/incoming Main Admin;
compromised-account recovery; revoke-vs-delete of former holders beyond the
current provisional rule. The unrelated Home dashboard 320dp/1.6× overflow
in §D is fixed (see the regression-cleanup note there).

**POINT 14 — COMPLETE.**

**NEXT: POINT 15 — ORGANIZATION + PLAN SCREENS.**

**POINT 15 WAS NOT STARTED.**

---

## POINT 14B — MAIN ADMIN ACCOUNT MANAGEMENT CORE UX & INTEGRATION (2026-09-12)

**POINT 14B CORE UX IS IMPLEMENTED. POINT 14 IS NOT YET COMPLETE.** Point 14A
remains authoritative: its seat invariant, state machine, six-action domain
catalogue (five Super Admin operations), lifecycle matrix, repository seam,
typed problem codes, atomic backend transfer semantics and privacy boundary
were not redesigned or changed. This pass implements the frozen §J contract
over the existing mock/controller only. The backend is still future work.

### Routes and access boundary

- Canonical routes are `/platform/tenants/:tenantId/main-admin` and
  `/platform/tenants/:tenantId/main-admin/replace`, expressed only through
  `SaasTenantRoutes.mainAdmin` / `mainAdminReplace` and registered as tenant
  detail children inside the Platform Tenants branch.
- Both routes are `super_admin`-only through the existing whole-Platform
  startup/router boundary. `main_admin`, `admin`, and a tenant role carrying
  `Cap.all` are redirected before either page or its repository is built; no
  tenant shell flashes. No tenant `Cap` was introduced.
- A deleted tenant has no seat: a direct Main Admin route resolves back to the
  tenant-detail tombstone and renders no account identity or action.

### Tenant-detail summary and dedicated management page

- The existing tenant detail `_AdminSection` is now a concise Point 14
  summary: current name, LTR login email, account-status chip with icon/text,
  one state line for pending setup / active / suspended / pending replacement
  or unavailable, and one `إدارة حساب المدير الرئيسي` navigation action. It
  contains no security mutation. Pull-to-refresh also invalidates the seat
  read. It constructs no tenant operational repository.
- The dedicated management page leads with the team name and one seat card.
  The card shows only the 14A read model: current holder identity, immutable
  login email, explicit account status, invitation/activation/suspension
  timestamps and Platform-only administrative context. Revision is not shown.
- Pending setup shows last-sent time, expiry when present, and becomes expired
  exactly at `expiresAt`; expiry never revokes the seat. Active shows activation
  and only suspend/replace. Suspended says `حساب ... موقوف`, keeps tenant
  lifecycle separate, and offers reactivate/replace only when 14A policy does.
- A pending replacement presents the **current holder** first and a visually
  secondary **designate not yet authorized** block beneath it, including safe
  identity, request time, setup/expiry state, reason, and explicit copy that
  the current holder retains the seat until backend completion.
- Stale and offline-cached snapshots remain visible/read-only; offline without
  cache, failure, not permitted, missing tenant and unsupported enum values
  have distinct safe states. Unknown state offers no mutation. The page has a
  collapsed scope boundary explaining that password, MFA, session list and
  impersonation controls do not exist here.

### Commands, confirmations, and outcomes

- All mutations go through the existing Point 14A
  `MainAdminActionController`; widgets contain no repository mutation logic.
  Buttons reflect the controller's single-flight state and duplicate submit is
  blocked. Commands are online-only, never queued, and never retried or replayed
  automatically.
- Resend (current or designate) uses one confirmation, preserves the seat,
  states that the previous invitation stops working, and never creates or
  reveals a token.
- Suspend uses one combined confirmation with normalized required Platform-only
  reason, enforced 280-character maximum and inline empty validation. Copy
  states that backend ends all holder sessions and blocks login while Simple
  Admins and tenant lifecycle remain unchanged.
- Reactivate uses one confirmation, is shown only for a suspended account on an
  active tenant, and states that old sessions are not restored.
- Replace is a keyboard-safe full page with only new display name, new LTR login
  email and required Platform-only reason. Existing validation conventions are
  reused; the current login identity is refused. One confirmation shows the
  email LTR and changes copy by 14A mode: a never-activated holder is replaced
  immediately backend-side; active/suspended holders retain authority until
  designate setup completes and the backend atomically transfers the seat.
  Flutter performs no local role/seat assignment. An attempt key is minted on
  confirmation and reused only while the normalized draft is unchanged.
- Cancel replacement uses one confirmation, invalidates only the designate
  context backend-side, and explicitly preserves the current holder.
- Successful commands use action-specific feedback. `stale_main_admin` shows a
  localized persistent banner after controller refresh and is never replayed.
  `idempotency_conflict`, invalid transition, throttling, tenant unavailable,
  permission, offline and safe failure are localized without raw wire codes or
  exceptions. Replacement identity/reason refusals stay inline with the draft.
- `recent_authentication_required` follows Point 12: a dialog explains that the
  operator must sign out and sign in again and that an unsaved draft is lost;
  it offers the existing sign-out action and creates no step-up/MFA screen.

### Tenant lifecycle, sessions, Audit, and privacy

- Active tenants expose actions according to account state. Suspended and
  deletion-pending tenants expose reducing actions only (suspend and/or cancel
  where the seat permits) and show why resend/reactivate/replace are blocked.
  Deleted tenants expose no seat.
- There is no session-management UI. Copy only reports backend-owned effects:
  suspension ends the holder's sessions; completed replacement ends/revokes the
  outgoing holder; cancellation ends any designate setup context.
- Flutter Audit now recognizes category `account_management`, target
  `main_admin_account`, and exactly the approved actions
  `main_admin_setup_resent`, `main_admin_suspended`,
  `main_admin_reactivated`, `main_admin_replacement_started`,
  `main_admin_replacement_cancelled`, `main_admin_replaced`. Arabic catalogue
  labels flow through list/detail/filter presentation; the filter can select
  them without raw keys. `account_status` accepts typed status text;
  `login_identity` is always redacted. `PlatformAuditRepository` remains
  read-only and Flutter appends nothing.
- Production UI contains no setup token/link, password/hash, OTP, MFA secret,
  backup code, auth/session id or token, device/IP, Team Code, email edit,
  stand-alone revoke, impersonation, role switch or Simple Admin management.
- Point 17 was not entered: no signup, OTP, Google login, Team Code linking,
  first-login/returning-user onboarding, `/account-setup`, verification UX, or
  production `simulate*` hook was added.

### Responsive/accessibility baseline and files

- 320–390dp and 600dp use one stacked column with ≥48dp full-width actions;
  ≥900dp uses the existing Platform reading width with seat and action columns.
  Emails wrap and remain LTR inside Arabic RTL. Status uses icon + text, action
  and dialog reading/focus order follows the visual order, and success/error
  feedback is semantic. Point 14C still owns the final matrix and polish.
- Added:
  `lib/features/platform/presentation/platform_main_admin_copy.dart`,
  `platform_main_admin_page.dart`, `platform_main_admin_replace_page.dart`,
  `test/features/platform/platform_main_admin_ux_test.dart`.
- Modified: `lib/core/router/app_router.dart`,
  `lib/core/widgets/status_chip.dart`, `lib/l10n/strings.dart`,
  `lib/features/platform/domain/platform_audit_models.dart`,
  `lib/features/platform/presentation/platform_audit_copy.dart`,
  `saas_tenant_detail_page.dart`, `saas_tenant_routes.dart`,
  `widgets/platform_confirmation_dialog.dart`; affected routing,
  tenant-detail and Audit tests; `API_CONTRACT.md`, `CAPABILITIES.md`,
  `DATA-NEEDS.md`, `SCREEN-ROUTE-MATRIX.md`, this handoff.

### Verification and exact Point 14C scope

- Point 14A domain/repository/controller tests, Point 14B UX tests, and affected
  tenant-detail/routing/Audit tests passed: **182 passed, 10 declared skips**.
  `flutter analyze` reported **No issues found** and `git diff --check` passed.
  Graphify was refreshed after these checks. The full Flutter suite was
  deliberately not run.
- Point 14C must perform final visual/accessibility polish and render every
  state across Dark Cyber, Purple Arena, Light and Eye Protection; reduced
  motion; 320/390/600/900dp; 1.6× text; complete keyboard/focus/semantics and
  contrast review; any final screenshot comparison; then run the full Flutter
  suite once, analyzer, diff check, update docs and close Point 14. It must not
  redesign 14A or add Point 15/17/security-console scope.

POINT 14 IS NOT YET COMPLETE.

NEXT: POINT 14C — MAIN ADMIN ACCOUNT MANAGEMENT FINAL UX, VISUAL VALIDATION & CLOSURE.

POINT 15 WAS NOT STARTED.

---

## POINT 14A — MAIN ADMIN ACCOUNT MANAGEMENT ARCHITECTURE & FOUNDATION (2026-09-11)

**POINT 14A IS COMPLETE. POINT 14 IS NOT YET COMPLETE.** Architecture, security
boundaries, account lifecycle, typed domain, repository seam, deterministic
mock, providers, action controller, focused tests, backend contract and the
Point 14B UX contract. **No route, screen, dialog or tenant-detail change was
made.** One existing file was touched: `PlatformTenantStore` gained
`updateMainAdminContact` (contact summary only). Full wire contract:
`API_CONTRACT.md` → "Main Admin account management — Point 14A foundation".
Rulings marked **PROVISIONAL** are Claude's calls (the brief delegated the
architecture) and remain open to Ahmed / the backend.

### A. What Point 14 is

The Super Admin's view of, and five backend-authoritative commands over, the
one account holding a `SaasTenant`'s **Main Admin seat**: see who holds it and
in what state; re-send an unfinished setup invitation; suspend / reactivate
the holder; move the seat to another identity (replace); cancel a pending
replacement. Nothing else.

**Not Point 14:** signup, onboarding, email OTP, Google sign-in, Team Code
linking, first-login password change, returning-user flows, the
`/account-setup` screen, account creation by a Main Admin (**all Point 17**,
which owns *how* an invited identity completes setup — Point 14 only consumes
the "setup completed" fact as a backend event); Simple Admin / tenant-role /
capability management; the tenant-side Security screen; password, MFA or
session consoles; impersonation; tenant lifecycle.

**Four independent dimensions** (never collapsed): tenant lifecycle (Point 9),
subscription (Point 7), **Main Admin account state** (Point 14), auth/session
state. Tenant suspension ≠ account suspension (account suspension leaves
Simple Admins working); a completed replacement revokes an *account*, never
the tenant; session expiry ≠ revocation.

### B. Seat invariant

Every non-deleted tenant has **exactly one current Main Admin account**
(`pending_setup | active | suspended`, never `revoked`, never absent) and **at
most one pending replacement**. Authority moves only atomically on the backend
when a designate completes setup, so two usable Main Admins never coexist.
There is **no stand-alone revoke** (it would empty the seat); removal =
replace, containment = suspend. A deleted tenant has no seat and nothing
recreates one. The snapshot constructor refuses a `revoked` holder, a deleted
tenant, and a designate sharing the holder's login email or account id.

### C. Account / setup / replacement states

- `MainAdminAccountStatus { pending_setup, active, suspended, revoked, unknown }`
  — wire values = the session envelope's `AccountStatus`. Per-state metadata is
  enforced by constructor: `pending_setup` ⇒ `setup` only; `active` ⇒
  `activatedAt` only; `suspended` ⇒ `activatedAt` + `suspension{suspendedAt,
  reason}`.
- `MainAdminSetupStatus { outstanding, expired, unknown }` with `lastSentAt`,
  optional `expiresAt`; `effectiveStatusAt(now)` fails toward `expired` at
  exactly `expiresAt` (which only ever offers a resend). Mock validity
  **PROVISIONAL 7 days** (`kProvisionalMainAdminSetupValidity`).
- `MainAdminReplacement { id, status: pending|unknown, designate{accountId,
  displayName, loginEmail, setup}, requestedAt, reason }` — a typed object,
  never a nullable email on the account.
- Any unknown value ⇒ `hasUnsupportedState` ⇒ the seat is shown, **no action**
  is offered. Malformed ⇒ `FormatException` (unreadable, never partial).

```text
current:  pending_setup ──setup completed (Point 17 event)──▶ active
          active ──suspend──▶ suspended ──reactivate──▶ active
replace:  holder pending_setup ──replace──▶ designate is holder (pending_setup,
            fresh invitation); old account revoked               [immediate]
          holder active|suspended ──replace──▶ replacement pending
            ├─ designate completes setup (backend) ─▶ designate is holder
            │    (active); old account revoked, its sessions ended
            └─ cancel ─▶ no replacement; designate discarded
```

### D. Approved Super Admin actions

| Action | Seat precondition | Tenant | Reason | Confirmation (14B) | Sessions | Audit |
| --- | --- | --- | --- | --- | --- | --- |
| Resend setup (current) | holder `pending_setup` (outstanding or expired) | active | — | one light confirmation (old link stops working) | none | `main_admin_setup_resent` |
| Suspend | holder `active` | any non-deleted | required ≤280 | one confirmation with reason field | **all ended** | `main_admin_suspended` |
| Reactivate | holder `suspended` | active | — | one confirmation | none restored | `main_admin_reactivated` |
| Replace | holder holds seat, none pending | active | required ≤280 | full-page form + one confirmation (copy by mode) | immediate: old pending account's; pending: none until completion | `main_admin_replaced` (immediate) / `main_admin_replacement_started` |
| Resend setup (designate) | replacement pending | active | — | one light confirmation | none | `main_admin_setup_resent` |
| Cancel replacement | replacement pending | any non-deleted | — | one confirmation | designate's ended | `main_admin_replacement_cancelled` |

Backend-only event: designate setup completion → `main_admin_replaced`
(system actor), old holder revoked + sessions ended. **Rejected candidates:**
stand-alone revoke; Platform-triggered password-reset email (the owner already
has the public reset-by-email flow; a Platform trigger grants nothing the
owner lacks and adds an unrequested credential email); set/see password; MFA
view/disable/reset; session list or per-session revoke; email edit; "require
fresh setup" (covered by immediate replacement / resend). No typed-name
confirmation anywhere in Point 14 — nothing a Super Admin clicks is
irreversible (the one irreversible step, completion, is triggered by the
designate).

**Suspend vs revoke.** Suspend = temporary, reversible Platform block of the
holder; the account keeps the seat. Revoke = permanent withdrawal of an
account's Main Admin authorization; it happens **only** to an outgoing account
when a replacement takes the seat, and is never a command.

**Replacement — PROVISIONAL policy:** the outgoing account is revoked, not
demoted (a demotion is tenant-role administration, owned by the new Main
Admin); the designate must be a new identity (no existing MTM account —
`main_admin_identity_unavailable`, revealing nothing about where). A suspended
holder can be replaced; suspend stays available while a replacement is
pending. Completion requires an `active` tenant and an unexpired invitation.

### E. Email, password, MFA, recent auth

- **Email identity:** immutable per account; no edit command in any state. A
  different address = a different account, reached only by replacement
  (immediate when the holder never activated — this is how a typo at tenant
  registration is fixed without leaving a claimable invitation live).
- **Passwords:** Flutter never sees, sets, generates, stores or triggers a
  reset of a Main Admin password. Any future bootstrap secret is backend-
  created/shown-once/expired/audited under Point 17.
- **MFA:** nothing exposed or offered. MFA/credential recovery after
  compromise = future backend recovery operation (policy owed); containment
  today = suspend (+ replace).
- **Recent auth:** any command may return `recent_authentication_required`;
  Flutter decides no freshness. **PROVISIONAL:** backend should require it at
  least for replace and reactivate. Client path (same as Point 12): explain,
  offer sign out → sign in again (MFA challenge) → re-submit; the draft is lost
  and the page says so.

### F. Tenant lifecycle matrix

| Tenant | Read | Suspend | Cancel replacement | Resend (either) | Reactivate | Replace |
| --- | --- | --- | --- | --- | --- | --- |
| active | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| suspended | ✓ | ✓ | ✓ | ✗ `tenant_not_eligible` | ✗ | ✗ |
| deletion_pending | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ |
| deleted | ✗ `tenant_already_deleted` | ✗ | ✗ | ✗ | ✗ | ✗ |

Rule: anything that opens/restores/extends an access path
(`MainAdminAction.opensAccessPath`) needs `active`; reducing actions work on
any non-deleted tenant. Reactivation therefore never bypasses a tenant
suspension (reactivate the tenant first). Neither designate nor pending holder
can complete setup while the tenant is blocked. Account commands never touch
tenant lifecycle/version/history, subscription, features, limits, counts or
Team Code (tested by snapshot comparison); only the tenant's `mainAdmin`
contact summary follows the seat.

### G. Sessions, concurrency, offline, privacy

- **Sessions:** no direct session controls for the Super Admin. Server-enforced
  consequences only (`MainAdminMutationEffect.endsSessions`: suspended,
  replaced, replacementCancelled). The backend must reject protected requests
  of suspended/revoked accounts immediately. The client's existing
  `/account-suspended` and `/account-revoked` destinations already render the
  result for the affected person.
- **Concurrency:** `expectedRevision` per seat → `stale_main_admin`. Per-attempt
  `Idempotency-Key` `main-admin:<action>:<uuidv7>` (mint on confirm, reuse only
  for an unchanged draft; `core/sync/uuid_v7.dart`, as Point 12B does). Same
  key + same command → replay (`idempotentReplay`, no new effect); different
  command → `idempotency_conflict`. Nothing is replayed automatically.
- **Offline:** every command online-only, never queued, no outbox. Stale or
  offline-cached seat = read-only (no actions); no cache = offline empty.
- **Privacy:** read model is id, display name, login email, typed status,
  setup/suspension/replacement facts, timestamps, revision, minimal tenant ref.
  No password/hash/OTP/MFA/backup code/reset or setup token/auth or session
  token/session list/device/IP/Team Code — enforced by a field-name scan test.

### H. Audit catalogue additions (backend-appended; Flutter appends nothing)

Category `account_management`; target type `main_admin_account` (target id =
affected account); actions `main_admin_setup_resent`, `main_admin_suspended`,
`main_admin_reactivated`, `main_admin_replacement_started`,
`main_admin_replacement_cancelled`, `main_admin_replaced`. Safe changes only:
`account_status` (from/to) and `login_identity` (**redacted**). No email, name,
reason, token or session id in `changes`. **Not yet in the Flutter catalogue**
— they parse as `unknown` until 14B adds them.

### I. Repository architecture, providers, mock

- `domain/platform_main_admin_models.dart` — states, value objects, snapshot,
  `MainAdminAction` (closed, 6), `MainAdminReplacementMode`,
  `MainAdminMutationEffect`, pure `MainAdminPolicy` (tenant gate, check,
  available actions, all transitions incl. backend events),
  `MainAdminManagementPolicy` → `MainAdminManagementView`.
- `domain/platform_main_admin_repository.dart` — `MainAdminProblemCode`,
  sealed `MainAdminCommand` + five typed commands, `mainAdminIdempotencyKey`,
  `MainAdminMutationResult`, `PlatformMainAdminRepository` (`load`,
  `resendSetup`, `suspend`, `reactivate`, `replace`, `cancelReplacement`).
  Separate from `AuthRepository`, `SaasTenantRepository`,
  `TenantLifecycleRepository`, break-glass, Audit and every tenant
  operational repository (import-scan test).
- `data/platform_main_admin_fixtures.dart`, `data/mock_platform_main_admin_repository.dart`
  — reads the canonical `PlatformTenantStore` every call; seats derived from
  each tenant's own contact; `simulateSetupCompleted` /
  `simulateReplacementSetupCompleted` are **mock-only stand-ins for Point 17
  backend events** (not on the interface). Permission asked per call
  (`super_admin`).
- `data/platform_main_admin_providers.dart` — `mainAdminMockConfigProvider`,
  `platformMainAdminRepositoryProvider`, `mainAdminAccountProvider(tenantId)`
  (re-reads on `tenantLifecycleRevisionProvider`),
  `mainAdminManagementProvider(tenantId)`, `mainAdminActionControllerProvider`
  (single-flight; outcomes Succeeded / Offline / Stale / RecentAuthRequired /
  NotPermitted / TenantUnavailable(code) / Rejected(code, message) / Failed /
  Ignored; refreshes seat + tenant detail + tenant list after success).
- **Mock scenarios:** `saas_hilal` active (demo tenant); `saas_nabd` pending
  setup, invitation outstanding; `saas_najd` active + replacement pending
  (designate ريم القحطاني); `saas_sahel` suspended account; `saas_rukn`
  suspended tenant × active account; any newly registered tenant → pending
  setup. `MockMainAdminMode` loaded / stale / offline / failure / notPermitted
  / recentAuthRequired / unsupportedState. Clock-positioned only; no
  credential-shaped data.
- **Deliberately not done:** the demo Main Admin persona is **not** ejected by
  a Point 14 suspension in the dev mock (the persona is not the fixture
  account; linking them would invent an identity). 14B must not add that.

### J. UX CONTRACT FOR POINT 14B (frontend-design → impeccable → emil)

Mode: **Operate**, restrained, inside the existing Platform design language
(tokens, `PlatformPage`, `StatusChip`, `TechnicalText`, shared
`platform_confirmation_dialog.dart`). The page's job: *answer "who holds this
team's Main Admin seat, and can they get in?" and offer only the legal next
step.* The one signature element is the **seat card** — the holder, and in the
replacement state the incoming designate shown beneath it as a clearly
secondary "waiting to take over" row — so the handover is legible at a glance.
No other decoration. The skill interview step was substituted by the brief's
explicit instruction to decide and proceed.

1. **Entry.** Tenant detail keeps its `_AdminSection` as a *summary* (name,
   LTR email, account-status chip; a one-line note for pending setup /
   suspended / replacement pending) plus one button **«إدارة حساب المدير
   الرئيسي»** → `context.push(SaasTenantRoutes.mainAdmin(id))`. No action
   buttons on the tenant overview. Add `mainAdminSegment = 'main-admin'`,
   `mainAdmin(id)` and `mainAdminReplace(id)` (`…/main-admin/replace`) to
   `SaasTenantRoutes`; register both under the tenant detail route exactly like
   `subscription`.
2. **Page `/platform/tenants/:tenantId/main-admin`** (title «حساب المدير
   الرئيسي», subtitle = team name). Order: (a) stale/offline chip if
   applicable; (b) seat card — display name, `TechnicalText` email, status
   chip with icon **and** text (`StatusKind.ok` «نشط»; `StatusKind.warn` «بانتظار
   الإعداد»; `StatusKind.crit` «موقوف»; a pending replacement adds a
   `StatusKind.info` chip «استبدال قيد الانتظار»), then state facts: pending →
   «أُرسلت الدعوة <date>» + «تنتهي <date>» or «انتهت صلاحية الدعوة»; active →
   «فُعّل <date>»; suspended → «أُوقف <date>» + the reason under a label
   «السبب (للمنصة فقط)»; (c) replacement block when pending — designate name /
   LTR email / invitation status, requested date, reason, and the sentence
   «سيبقى <holder> المدير الرئيسي حتى يُكمل <designate> الإعداد»; (d) tenant
   note when `view.tenantBlocksAccessPaths` — «وصول الفريق <موقوف|بانتظار
   الحذف>؛ إعادة التفعيل والاستبدال وإعادة إرسال الدعوة غير متاحة حتى يعود
   الفريق نشطًا» (never silently hide); (e) actions, only those in
   `view.actions`, grouped: primary filled (resend setup / reactivate),
   secondary outlined (replace — label by mode: immediate «تغيير المدعو»,
   pending «استبدال المدير الرئيسي»), destructive outlined with icon + error
   text colour (suspend «إيقاف الحساب», cancel «إلغاء الاستبدال»); (f) a
   collapsed «ما لا تفعله هذه الصفحة» fact list: no passwords, no MFA, no
   session list, no signing in as the admin; password reset is done by the
   admin from the sign-in screen.
3. **Confirmations** (shared Platform dialog, one step each, no typed name):
   - resend: «سيتوقف رابط الدعوة السابق عن العمل.»
   - suspend: dialog/sheet with required reason (multiline, counter 280,
     inline error) — consequences: «ستنتهي جميع جلساته فورًا ولن يتمكن من
     الدخول حتى تعيد تفعيله. يبقى المديرون الآخرون والفريق يعملون.»
   - reactivate: «يمكنه تسجيل الدخول مجددًا؛ لا تُستعاد الجلسات السابقة.»
   - cancel: «ستتوقف دعوة <designate> ولن يتغيّر المدير الحالي.»
   - replace (after the form): immediate — «سيتوقف دعوة <old> فورًا ويصبح
     <new> المدعو الوحيد»; pending — «يبقى <holder> المدير الرئيسي حتى يكمل
     <new> الإعداد، ثم يُلغى حساب <holder> وتنتهي جلساته». The dialog shows
     the new email large and LTR with «تحقّق من البريد» — no re-entry field.
4. **Replace page `/…/main-admin/replace`** — full page, keyboard-safe:
   name, email (LTR input, `validateMainAdminName/Email`), reason (280
   counter), a mode sentence at the top from `view.replacementMode`, one submit
   → confirmation. Attempt key minted on confirm; reused only for an unchanged
   draft. On success pop back to the page.
5. **Outcomes.** Succeeded → SnackBar in the action's own verb («أُوقف
   الحساب», «أُعيد إرسال الدعوة», «بدأ الاستبدال», «تم تغيير المدعو», «أُلغي
   الاستبدال», «أُعيد تفعيل الحساب»). Stale → banner «تغيّرت حالة الحساب منذ
   فتحها — راجعها ثم أعد المحاولة» over the refreshed seat. TenantUnavailable
   → refreshed page with the tenant note (deleted → back to the tenant route,
   which shows the tombstone). Rejected: `invalid_main_admin_reason` inline on
   the reason field; `invalid_main_admin_identity` /
   `main_admin_identity_unavailable` inline on the email field (draft kept);
   `replacement_already_pending` → back to the page showing it; others →
   localized banner. RecentAuthRequired → dialog «يتطلب هذا الإجراء تسجيل
   دخول حديثًا» with «تسجيل الخروج» / «إلغاء», stating the draft is lost.
   NotPermitted / Failed → safe copy, no retry loop. Offline → «لا يمكن تنفيذ
   هذا الإجراء دون اتصال» and the draft is kept.
6. **States.** Loading skeleton (seat card + two action rows); confirmed;
   stale (read-only, refresh); offline cached (read-only, warn chip); offline
   no cache (`EmptyState` offline + retry); not permitted; failure
   (`ErrorStateView` + retry); tenant not found; tenant deleted (route back);
   unsupported («تعذّر عرض حالة الحساب في هذا الإصدار» — no actions, suggest
   updating). Branch on codes only, never message text.
7. **Responsive.** 320–390 dp: one column, actions full-width stacked, 48 dp
   minimum; the email wraps inside its LTR isolate, never ellipsized. 600 dp:
   same column, `PlatformPage` reading width. ≥900 dp: two columns — seat card
   + replacement on the start side, actions + tenant note + fact list on the
   end side. No tables; nothing depends on horizontal scrolling.
8. **Accessibility.** Status always text + icon (never colour alone);
   destructive actions carry icon + explicit verb; RTL reading/focus order =
   visual order (seat → replacement → actions); ≥48 dp targets; dialogs use
   the shared dialog semantics (title, scoped route, focus returns to the
   trigger); 1.6× text at 320 dp without overflow; emails and ids in LTR
   isolates (`TechnicalText`); reason/email errors announced as field errors;
   a one-shot live-region announcement on action success only.
9. **Motion.** None new. Seat-card state change may use the existing
   `AnimatedSwitcher`/motion tokens (≤200 ms fade), instant under
   `disableAnimations`. No stagger, no pulsing for suspended, no countdowns.
10. **Audit catalogue (14B):** add category `account_management`, target
    `main_admin_account`, the six actions and change fields `account_status` /
    `login_identity` (redacted) to `platform_audit_models.dart` +
    `platform_audit_copy.dart` with Arabic copy and filter options; the seat
    page may link to Audit filtered by that category.
11. Point 14C then renders every state in Dark Cyber, Purple Arena, Light,
    Eye Protection, reduced motion, 320/390/600/900 dp and runs the full suite.

### K. Files, verification

Added: `lib/features/platform/domain/platform_main_admin_models.dart`,
`lib/features/platform/domain/platform_main_admin_repository.dart`,
`lib/features/platform/data/platform_main_admin_fixtures.dart`,
`lib/features/platform/data/mock_platform_main_admin_repository.dart`,
`lib/features/platform/data/platform_main_admin_providers.dart`,
`test/features/platform/platform_main_admin_domain_test.dart`,
`test/features/platform/platform_main_admin_repository_test.dart`,
`test/features/platform/platform_main_admin_controller_test.dart`.
Modified: `lib/features/platform/data/platform_tenant_store.dart`
(`updateMainAdminContact`). Docs: `API_CONTRACT.md`, `CAPABILITIES.md`,
`DATA-NEEDS.md`, `SCREEN-ROUTE-MATRIX.md`, this handoff.

Focused Point 14A batch **58/58 passed**; store neighbours
(`platform_tenant_consistency`, `saas_tenant_repository`,
`tenant_lifecycle_repository`, `platform_break_glass_repository`) **69/69
passed**. `dart format`: 9 files clean. `flutter analyze`: **No issues
found.** `git diff --check`: clean (new untracked files also checked: no
trailing whitespace). `graphify update .`: succeeded (10,800 nodes, 16,513
edges, 341 communities). Full suite intentionally not run (Point 14C runs it
once).

### L. Backend gaps and PROVISIONAL policy (need backend/product authority)

Owed: the seat resource and five commands; atomic seat transfer; invitation
issuance/expiry/delivery/invalidation; immediate session + refresh-token
termination; the new holder's capability grant; platform-wide login-email
uniqueness; recent-auth enforcement; Audit append. **PROVISIONAL:** 7-day
invitation validity (and whether invitations expire); resend throttling
(`main_admin_setup_resend_throttled` name); revoke-not-demote; no existing
account as designate; recent-auth scope/freshness; email notification to
outgoing/incoming admins; MFA/credential recovery; auto-invalidating pending
invitations on tenant suspension/deletion (Point 14 only guarantees they
cannot complete).

### M. Exact Point 14B scope

Build §J 1–10 over this foundation without changing the state machine,
action catalogue, tenant matrix, repository/commands, problem codes, or
contract: the two routes + route constants, the tenant-detail summary button,
the seat page with every §J.6 state, the replace page, the confirmations, the
outcome handling, the Audit catalogue additions, and widget tests for each
state/action/outcome plus `TenantRepositoryWatch` isolation and RTL/320 dp.
No Point 17 flow, no password/MFA/session control, no Simple Admin
management.

**POINT 14 IS NOT YET COMPLETE.**

**NEXT: POINT 14B — MAIN ADMIN ACCOUNT MANAGEMENT CORE UX & INTEGRATION.**

**POINT 15 WAS NOT STARTED.**

---

## POINT 13C — PLATFORM REPORTS FINAL UX, VISUAL VALIDATION & CLOSURE (2026-09-11)

**POINT 13 — COMPLETE.** Closure pass over 13B: no architecture, catalogue,
domain, contract, date/pagination rule, export/chart decision or existing
test was reopened; 13A/13B were re-run unmodified before and after.

### A. What 13C actually added

- **≥900 dp dense-row alternative** for the three snapshot reports
  (subscriptions, usage & limits, feature availability), replacing the
  compact `ReportRowTile` stack with `ReportDenseTable` — a flex-columned
  table (`platform_report_widgets.dart`). §K.7's original wording ("its own
  horizontal scroll container") is refined here, not loosened: columns are
  proportioned to the reading column's own width so the table never depends
  on horizontal scrolling to be read or reached by keyboard. Each dense row
  keeps the exact same composed semantics label and the same `Key` the
  compact tile used (`subscription-row-<id>` etc.), so nothing about
  assistive technology or existing row-keyed tests changes at the 900 dp
  boundary — only density does. `PlatformReportScaffold.body` became
  `bodyBuilder: List<Widget> Function(bool wide)` so a report can build
  different content for the width class the scaffold already computes for
  its own filter-panel/sheet split — the only change to the shared 13B
  contract, and additive.
- **Usage & limits "small keys × bands" wide table** (§K.5): at ≥900 dp the
  six-key vertical stack of `ReportBreakdownSection`s is replaced by
  `_UsageKeyBandTable`, one row per limit key and one column per band, each
  cell still numeric-first with colour only supplementing it.
- **Platform Activity two-column wide layout**: `_CategoryGroupGrid` lays the
  five category groups two to a row at ≥900 dp via a width-aware `Wrap`,
  preserving every total, action count, the emergency-access governance
  note and the Audit drill-down untouched — never a fake event table.
- **`ChoicePill` overflow fix** (`settings_widgets.dart`, shared beyond
  Reports): its label `Text` is now wrapped in `Flexible` with `softWrap`.
  Testing the feature-availability filter panel at ≥900 dp for the first
  time (13B never exercised that specific combination) surfaced a real
  ~5px `RenderFlex` overflow — the longest feature-key label ("الإحصاءات
  والتقارير") didn't fit the 300 dp side panel's content width on one line.
  The pill now wraps to a second line under pressure instead of clipping;
  every existing short-label caller (theme pills elsewhere) is unaffected.
- **Column-header strings** added to `S`: `platformReportColumnTeam`,
  `platformReportColumnSubscriptionStatus`, `platformReportColumnPlan`,
  `platformReportColumnDate`, `platformReportColumnUsage`,
  `platformReportColumnBand`. Existing inline Arabic filter-form labels
  (`'حالة الاشتراك'`, `'الخطة'`, …) were left as-is — the same convention
  `platform_audit_filters.dart` already used before Point 13, so moving them
  into `S` now would be inconsistent scope creep, not a fix. Localization
  scan of the Point 13 presentation files found no raw wire value rendered
  as user-facing text anywhere.
- **Landing and report-page hierarchy** (§7/§8): reviewed against §K — no
  redundant repeated titles, no metrics on the landing, provenance line
  already reads correctly narrow and wide; no changes were needed.
- **Filter panel/sheet** (§12): reviewed at both host widths for all four
  reports; the only defect found was the `ChoicePill` overflow above, now
  fixed. Active-filter communication (badge + removable chips + "مسح الكل")
  was already in place from 13B and needed no change.

### B. RTL, themes, Eye Protection, large text, motion

- RTL: every screens-test render (dense tables included) runs inside the
  shared harness's `Directionality.rtl`; no test needed a directional fix.
- Themes/Eye Protection: `platform_appearance_test.dart`'s existing 900 dp ×
  every-theme walk covers the catalogue landing (unchanged in 13C); the new
  ≥900 dp dense-row/table code paths are covered directly by the new
  `platform_reports_screens_test.dart` group instead (themes are not
  re-iterated there — Point 13B's own appearance coverage already holds the
  palette/eye-protect contrast guarantee via `palette_contrast_test.dart`,
  which this work did not touch).
- 320 dp + 1.6× text: a new test group opens all four reports with real
  loaded rows at 320 dp / 1.6× scale and asserts a clean render (no
  `FlutterError.onError` override in the file — an overflow anywhere fails
  the test that produced it).
- Motion: nothing added. No stagger, count-up or filter animation exists in
  Point 13; reduced motion needed no dedicated Point 13 test because no
  Point 13 code depends on animation to be usable.

### C. Tests, analyzer, diff, Graphify

New in `platform_reports_screens_test.dart`: a `'≥900 dp dense rows'` group
(5 cases — subscriptions/usage/features switch to `ReportDenseTable` with no
`ReportRowTile` left, tap-to-tenant-detail still works, Platform Activity
lays out two columns, and a narrower width keeps the compact tiles) and a
`'320 dp at 1.6× text'` group (4 cases, one per report, real rows, no
overflow). `dart format`: clean on every changed/added file. `flutter
analyze`: **No issues found.** Focused Point 13A+13B+13C batch re-run:
104/104. Full `flutter test`: **1646/1646 passed**, run once. `git diff
--check`: clean. `graphify update .`: succeeded (10,503 nodes, 16,099 edges,
316 communities).

### D. Files changed

Modified: `platform_report_widgets.dart` (`ReportDenseTable`,
`ReportDenseTableRow`, `bodyBuilder`), `platform_subscriptions_report_page.dart`,
`platform_usage_limits_report_page.dart` (+ `_UsageKeyBandTable`),
`platform_feature_availability_report_page.dart`,
`platform_activity_report_page.dart` (+ `_CategoryGroupGrid`),
`settings_widgets.dart` (`ChoicePill` wrap fix), `strings.dart` (six column
headers), `platform_reports_screens_test.dart`. Docs: `API_CONTRACT.md`,
`CAPABILITIES.md`, `DATA-NEEDS.md`, `SCREEN-ROUTE-MATRIX.md`, this handoff.
No domain, repository, route or catalogue file touched.

### E. Backend/product gaps carried forward unchanged

Everything §J of Point 13A already owed remains owed: the four authorized
projections, snapshot-bound cursors, a real `admins` usage aggregate, an
Audit count projection honouring retention, and every "Claude-provisional"
open policy question (near-limit threshold, bucketing time zone, export
formats, fine-grained report permission, Audit retention, the 366-day max).
13C changed no product policy and added no new gap.

**POINT 13 — COMPLETE.**

**NEXT: POINT 14 — MAIN ADMIN ACCOUNT MANAGEMENT.**

**POINT 14 WAS NOT STARTED.**

---

## POINT 13B — PLATFORM REPORTS CORE UX & INTEGRATION (2026-09-11)

**POINT 13B IS COMPLETE. POINT 13 IS NOT YET COMPLETE.** Built the route, the
Operations row, the catalogue landing and the four report screens over the
Point 13A architecture exactly as §K specified it. **Point 13A's catalogue,
domain, contract, date/pagination rules and no-export/no-charts decision were
not touched** — every change below is additive UI/application code plus one
narrowly-scoped area-matching fix §K.1 itself called for.

### A. Point 13A architecture — preserved, not re-decided

Confirmed unchanged: the closed four-report catalogue (`PlatformReportType`),
the snapshot/period-summary split, the typed per-report queries, the
`PlatformReportRange` half-open UTC contract, the opaque cursor/snapshot
pagination rule, the privacy boundary (`isForbiddenReportField`), the
deleted-tenant exclusion, and "no export, no charts, no near-limit threshold".
13B ran the Point 13A focused suite (55/55) unmodified before and after — see
§I below.

### B. Routes and area matching

- `PlatformOperationsRoutes.reports = '/platform/reports'`,
  `.report(PlatformReportType type) = '/platform/reports/<wire>'`,
  `reportTypeParam = 'reportType'`; `reports` added to `.all`.
- Registered in `_platformOperationsRoutes` (`app_router.dart`) as a sibling
  `GoRoute` with a nested `:reportType` child, alongside Health/Security/
  Audit/Break-glass — a child route, not a tab, so filters differ per report
  and the back gesture returns to the catalogue.
- `PlatformArea.operations.siblingSegments` gained `kPlatformReportsSegment`
  (`'reports'`). `PlatformArea.contains` was made **prefix-aware for sibling
  segments** (it previously only matched a sibling's bare segment exactly,
  which is right for Health/Security/Audit — none has children — but wrong
  for Reports, which owns `:reportType`): a sibling segment now also claims
  `'$kPlatformRoot/$segment/…'`, exactly as the area's own `route` already
  did. Covered by a new `platform_routing_test.dart` case; `platform_area.dart`
  is the only domain file 13B touched.
- Unknown `:reportType` renders `PlatformReportPage`'s `_UnsupportedReportPage`
  in place — a designed state with a button back to the catalogue — never a
  redirect. Verified by a routing test that deep-links a bogus type and
  confirms no loop.

### C. Operations integration

`platform_operations_page.dart`: "تقارير المنصة" is now a real `NavigationRow`
pushing `PlatformOperationsRoutes.reports`, removed from
`PlatformNoteCard`'s planned list (the card is now empty and was removed
entirely — Point 14 was not given a placeholder in its place).
`platform_operations_test.dart` updated: the old "stays planned, not a dead
control" assertion is replaced with a real row-presence and navigation check.

### D. Reports landing

`PlatformReportsCataloguePage` (`platform_reports_catalogue_page.dart`): a
`PlatformSectionHeader`, then two `SectionLabel` groups — "الحالة الحالية"
(subscriptions, usage & limits, features) and "خلال فترة" (activity) — each a
`SettingsSection` of custom two-line rows (title, one-line question, and a
small text kind label "لقطة حالية"/"حسب الفترة"; `NavigationRow` itself has
only one subtitle line, so the row is a small dedicated widget rather than a
squeezed reuse). No numbers anywhere on the page.

### E. The four report screens

One file per report — `platform_subscriptions_report_page.dart`,
`platform_usage_limits_report_page.dart`,
`platform_feature_availability_report_page.dart`,
`platform_activity_report_page.dart` — each a `ConsumerStatefulWidget` built
on the shared `PlatformReportScaffold` (`widgets/platform_report_widgets.dart`).
`PlatformReportPage` (`platform_report_page.dart`) is the `:reportType`
dispatcher.

- **Subscriptions/Usage/Features** (paginated snapshot reports): breakdown
  sections per Point 13A's `summary`, a "الفرق (n)" row list, tenant rows
  pushing `/platform/tenants/:id`. Usage adds the "الكل + six keys"
  `limitKey` pill row, kept visually and behaviourally separate from the
  filter badge/chips (re-ranks, never narrows — matches
  `UsageLimitsReportQuery.isFiltered` excluding it). Features shows four
  wrapped per-module chips per row and gates the state filter behind a
  feature-key pick, matching the domain's own constraint.
- **Activity** (period summary, no rows/pagination — `paginatedRows: false`
  in the catalogue): category groups with per-action counts, an
  "إجراءات أخرى" unsupported-actions row, the emergency-access governance
  note, and a partial-coverage line when `evidenceAvailableFrom` is later
  than the query's `from` — worded as *unavailable*, never folded into `0`.

### F. Filters

Each report has its own typed filter form (`_SubscriptionFilterForm`,
`_UsageFilterForm`, `_FeatureFilterForm`, `_ActivityFilterForm`) — no
universal filter map. The same form widget is used two ways:
`showReportFilterSheet` (modal bottom sheet, local pending state, applies on
"تطبيق التصفية"/discards on dismiss, <900 dp) and
`PlatformReportScaffold.filterPanel` (the identical form, immediate
`onChange`, permanent start-side panel ≥900 dp). One form, two hosts, so the
two widths can never offer different controls. A filter change always builds
a brand-new typed query object, which is the family key the first-page
provider watches — so a query change is always a fresh page one.

### G. Date handling (Activity report)

`_ActivityFilterForm` reads "today" from `ref.read(clockProvider)()`, never
`DateTime.now()`. Presets (٧/٣٠/٩٠ days) and the custom `showDateRangePicker`
build a `PlatformReportRange.localDays(...)`; a custom selection over 366
days is rejected with a snackbar before it ever reaches the domain
constructor (which would otherwise throw). `lastDate` is pinned to the clock's
today; the exclusive-bound wording is never shown to the user (the provenance
line states "‹first› – ‹last› · حسب توقيت الجهاز").

### H. Rows controller and pagination

`PlatformReportRowsController<Q, Res, R>`
(`data/platform_report_rows_controller.dart`) is the one 13B rows/paging
application class, configured per report rather than duplicated four times.
It wraps Point 13A's pure `PlatformReportRowsState`:

- `syncFirstPage` folds in the page the report screen already has from its
  own `ref.watch` of the Point 13A family provider (page one is never
  re-fetched by this controller) — deliberately silent (no
  `notifyListeners()`) because the caller always reads it inside its own
  `build()`, in the same frame; a real async notify there would call
  `setState` mid-build.
- `loadMore` issues the repository call for the next opaque cursor directly
  (never through the family provider, per Point 13A §F), appends via
  `PlatformReportRowsState.appendPage`, and is guarded against a first page
  that lands mid-flight (`identical(state, current)`) so rows from two
  snapshots can never be shown together.
- Exercised in isolation by `platform_report_rows_controller_test.dart`
  (7 tests, no widgets, no mock repository): stable initial load, ordered
  append with de-dup, next-page failure keeps rows, cursor-expiry forces
  `mustReload`, offline next-page refuses without losing rows, and the
  stale-in-flight-page guard.

`ReportPagingFooter` renders the explicit "عرض المزيد" action with "shown /
total", never infinite scroll; offline disables it with a stated reason;
`mustReload` offers "إعادة التحميل" instead of a retry that would loop.

### I. States, freshness, offline

Every report screen switches on Point 13A's own `platformReportViewState` and
`platformReportFreshness` selectors — 13B added no parallel state machine.
Loading (skeleton), loaded, empty vs filtered-empty (distinct copy and
action), stale (banner + kept `generatedAt`), offline-cached (banner,
paging disabled), offline-no-data (distinct empty state, not "0"),
not-permitted, safe failure with retry, next-page failure (rows kept),
cursor-expired (forced reload), unsupported values/keys (explicit note, never
folded into a known bucket) all have dedicated `Key`s and were exercised in
`platform_reports_screens_test.dart` via `MockPlatformReportsMode` and
`auditRetention` overrides — the same mock knobs Point 13A built.

### J. Tenant navigation and Audit drill-down

Snapshot report rows push `SaasTenantRoutes.detail(tenantId)`. Activity
action rows with `count > 0` push `PlatformOperationsRoutes.audit` with
`report.auditQueryFor(action)` as `extra` — `PlatformActivityReportQuery`'s
own method, so the pushed `PlatformAuditQuery`'s `action`/`from`/`before`
are always exactly what produced the count; verified in
`platform_reports_screens_test.dart` by reading the pushed
`PlatformAuditPageWidget.initialQuery` back and comparing it to the report's
own range. (Pushed routes — Reports rows, the drill-down, and every existing
Operations sibling — leave `GoRouter.currentConfiguration.uri` at the branch
root, the same caveat `platform_routing_test.dart` already documents for
Health/Security/Audit; tests assert the pushed widget, not the URI.)

### K. Privacy and separation

No report screen imports a tenant-operational repository, a `Cap`, an export
package or a charting package. `platform_reports_screens_test.dart`'s
"separation" group re-runs `TenantRepositoryWatch` (the Point 4 instrument
that throws if a tenant repository is ever *built*) against all four report
detail routes, and asserts no download/share/pie/bar icon is offered anywhere
on a report page.

### L. Files changed

Added:
- `flutter_app/lib/features/platform/data/platform_report_rows_controller.dart`
- `flutter_app/lib/features/platform/presentation/platform_reports_copy.dart`
- `flutter_app/lib/features/platform/presentation/platform_reports_catalogue_page.dart`
- `flutter_app/lib/features/platform/presentation/platform_report_page.dart`
- `flutter_app/lib/features/platform/presentation/platform_subscriptions_report_page.dart`
- `flutter_app/lib/features/platform/presentation/platform_usage_limits_report_page.dart`
- `flutter_app/lib/features/platform/presentation/platform_feature_availability_report_page.dart`
- `flutter_app/lib/features/platform/presentation/platform_activity_report_page.dart`
- `flutter_app/lib/features/platform/presentation/widgets/platform_report_widgets.dart`
- `flutter_app/test/features/platform/platform_report_rows_controller_test.dart`
- `flutter_app/test/features/platform/platform_reports_screens_test.dart`

Modified: `platform_area.dart` (prefix-aware sibling matching + `reports`
segment), `platform_operations_routes.dart` (report routes), `app_router.dart`
(route registration), `platform_operations_page.dart` (real Reports row),
`strings.dart` (Point 13 Arabic copy block), `platform_operations_test.dart`,
`platform_routing_test.dart`. Docs: `API_CONTRACT.md`, `CAPABILITIES.md`,
`DATA-NEEDS.md`, `SCREEN-ROUTE-MATRIX.md` (status lines only — no Point 13A
architecture rewritten).

### M. Focused tests, analyzer, diff

Point 13A (55/55) + new Point 13B: rows controller (7), report screens (19),
routing additions (4 new cases inside `platform_routing_test.dart`),
operations (4, one new). Also ran unmodified: `platform_navigation_test.dart`
(4), `platform_appearance_test.dart` (35 — every theme/eye-protect/breakpoint
combination already iterates `PlatformOperationsRoutes.all`, which now
includes `reports`, so the wide 900 dp side-panel layout was exercised across
Dark Cyber, Purple Arena, Light and eye-protect without a dedicated 13C pass),
`platform_audit_list_test.dart` (12), `platform_audit_integration_test.dart`
(8). **All green.** `dart format` on every changed/added file: clean.
`flutter analyze` (whole project): **No issues found**. `git diff --check`:
clean; new files scanned for trailing whitespace manually (no tracked
baseline to diff against) — clean. Full `flutter test` intentionally **not**
run (13C).

### N. Exact Point 13C scope

Visual matrix (Dark Cyber, Purple Arena, Light, Eye Protection, reduced
motion) beyond the incidental appearance-test coverage above; dedicated
320/390/600/900 dp passes with real content density (not fixture-sized data);
1.6× text scale beyond the one narrow-width smoke case; detailed accessibility
review (reading order, semantics wording, touch targets under text scale);
final motion review; the ≥900 dp dense-table row variant §K.7 allows as an
alternative to the compact tile (13B ships the compact tile at every width —
functionally clean, not yet the denser table); the usage-report "small keys ×
bands table" ≥900 dp variant (13B renders the same per-key breakdown list at
every width); full `flutter test` suite; closure docs; marking Point 13
complete.

**POINT 13 IS NOT YET COMPLETE.**

**NEXT: POINT 13C — PLATFORM REPORTS FINAL UX, VISUAL VALIDATION & CLOSURE.**

**POINT 14 WAS NOT STARTED.**

---

## POINT 13A — PLATFORM REPORTS ARCHITECTURE & FOUNDATION (2026-09-11)

**POINT 13A IS COMPLETE. POINT 13 IS NOT YET COMPLETE.** Architecture, closed
catalogue, typed domain, repository seam, deterministic Clock-based mock,
first-page providers, pure selectors/paging state, focused tests, backend
contract and the 13B UX contract. **No route, screen, Operations-row change or
existing Dart file was modified.** Wire contract: `API_CONTRACT.md` →
"Platform Reports — Point 13A foundation (future backend)". The frontend-design
→ impeccable → emil-design-eng chain was applied to settle §K; Impeccable's
PRODUCT.md interview was not run (the brief was explicit and the incumbent
Flutter design system is the visual authority, as in Point 12A).

### A. Definition

A **Platform Report** is a structured, read-only, `super_admin`-only view over
one explicitly bounded **control-plane** dataset, answering one fixed
question. Two kinds, never mixed: **current snapshot** (computed from current
state at a server `generatedAt`; no history, never shown as a trend) and
**period summary** (counts of historical Audit events in `[from, before)`).

| System | Is | Reports |
| --- | --- | --- |
| Overview | current awareness (KPIs, attention) | not repeated; the Reports landing shows no metrics |
| Audit | immutable actor-attributed evidence | activity report reads a server **count projection** and links back; never lists, copies, mutates or re-retains events |
| Security / Health | current snapshots | **not report sources** — no history is stored |
| Break-glass | session-bound grant | not a source; its four Audit actions are counted as governance events, not incidents |

### B. Closed catalogue (`PlatformReportCatalogue`)

| Type (wire) | Kind | Sources | Metrics / dimensions | Filters | Rows | Order | Privacy |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `subscriptions` | snapshot | subscription + lifecycle | tenantCount; by subscription status (trial/active/grace/inactive + unsupported); by lifecycle (active/suspended/deletion_pending + unsupported); by plan (+ no-plan) | status set, plan (`planId`/`noPlan`), lifecycle set, `dueBefore` | tenant ref, lifecycle, status, plan ref, server `relevantDate` | relevantDate asc (none last), tenant id | tenant id + name |
| `usage_limits` | snapshot | usage aggregates + plan limits + lifecycle | per limit key: tenants per factual band `within/at/over/no_limit` | `limitKey` (ranks only), band set, plan, lifecycle | per key usage, effective limit (`override ?? default`), overridden | band severity desc, ratio desc, tenant id | tenant id + name |
| `feature_availability` | snapshot | Feature Flags + lifecycle | per module: enabled/disabled + unsupported | `featureKey` + `state`, lifecycle | four module states | display name (Arabic-aware collation), tenant id | tenant id + name |
| `platform_activity` | period summary | Audit count projection | counts per known Point 11 action; category totals derived; unsupported "other actions"; `evidenceAvailableFrom` | local date range, Audit category | none | — | aggregate only |

**Not reports:** revenue/MRR/ARR/invoices/payments/prices/currency/CLV (no
pricing exists; activation is not payment); Health/Security history; customer
Demos; single-tenant reports (current = tenant detail, history = Audit by
team); any tenant-operational data. No export, no charts beyond redundant
meters, no custom builder, no query language, no arbitrary maps.

### C. Data and privacy boundaries

- Rows carry only `tenant.id` + `tenant.displayName` plus the report's typed
  fields. The parser **refuses the whole payload** if a row or tenant ref
  carries Team Code, Main Admin/email/phone, reason, credential/OTP/token/
  session/cookie, IP/device, member/volunteer, medical or attendance keys
  (`isForbiddenReportField`, built on `PlatformAuditSafetyPolicy`). The model
  has no field for any of them (tested by source scan).
- Commercial: status and lifecycle stay separate axes; `relevantDate` is the
  server's; the Point 7 **14-day grace remains provisional** and reports never
  compute a date. Plans are `{id, name}` — no price.
- Usage: server platform aggregates only; never computed by opening tenant
  datastores. `admins` usage is the Point 7 mock placeholder `1` — backend gap.
  No "near limit" threshold exists (not approved); ranking by utilization
  replaces it.
- Feature Flags ≠ Capability ≠ Plan Limit: the features report counts the
  entitlement only; missing/unreadable state is *unsupported* in the report
  while tenant access still fails closed to disabled.
- Lifecycle: canonical Point 9 values; no suspension/deletion reasons; deleted
  handled below.

### D. Tenant / deleted-tenant rules

Snapshot reports contain only `active`, `suspended`, `deletion_pending`
(`kReportableLifecycleStatuses`). Lifecycle filters reject `deleted`
(`ArgumentError`); a `deleted` row or bucket in a payload makes it unreadable
(`FormatException`). Tombstones are never reconstructed; deletions appear only
as `deletion_finalized` counts. Retired Team Codes and deleted admin identities
never appear. No single-tenant report filter.

### E. Date rules

UTC instants with explicit offset (offset-less refused). Half-open
`PlatformReportRange [from, before)` built from **device-local calendar days**
(start of first day → start of the day after the last) — identical to Audit.
No truncation, no server re-bucketing. Default: last 30 local days incl.
today (`defaultAt(clock)`). Max 366 local days (instant span ≤ 367 × 24 h;
server `report_range_too_large`) — justified by undecided Audit retention and
bounded aggregation. `evidenceAvailableFrom` > `from` ⇒ partial coverage;
earlier counts are **unavailable, not zero**. No time buckets (no agreed
bucketing time zone). Mock/tests use injected `Clock` only.

### F. Filters, pagination, ordering

Per-report immutable queries with value equality (Riverpod family keys):
`SubscriptionReportQuery`, `UsageLimitsReportQuery`,
`FeatureAvailabilityReportQuery`, `PlatformActivityReportQuery`; closed enums
and typed sealed `PlatformReportPlanFilter`; deterministic
`toQueryParameters()`. `isFiltered` drives filtered-empty (range and
`limitKey` are not filters). Pages: opaque cursor, 1–100 (default 50),
`nextCursor`; **cursor bound to `snapshotId`** — pages 2…n come from the same
frozen snapshot or `report_cursor_expired`. `PlatformReportRowsState` (pure):
page one replaces; append in order with key de-dup; foreign snapshot,
repeated cursor, `validation` or `report_cursor_expired` → `mustReload`;
other page failures keep rows (`pageFailed`). Stable orders above; comparators
`compareSubscriptionRows`, `compareUsageRows` are in the domain.

### G. Repository, sync/async, cache, export, unknowns

- `PlatformReportsRepository`: `loadSubscriptions`, `loadUsageLimits`,
  `loadFeatureAvailability`, `loadPlatformActivity` → `Result<…>`. Separate
  from Audit/Security/Health/Break-glass/Overview/lifecycle/subscription/
  feature repositories and all tenant repositories (import scan). Composition
  happens server-side; the mock shares **data** (canonical
  `PlatformTenantStore`, `PlatformAuditFixtures`), not repositories.
- **Synchronous** projections (A). No job/queue/polling — bounded datasets,
  paged rows, no export.
- Offline/cache: online reads; a cached first page may show only as
  stale/offline with its original `generatedAt`; paging refused offline;
  nothing queued; process memory only.
- **Exports: none in Point 13.** 13B adds no export affordance. Future export
  = backend-generated, authorized, audited, stamped, minimized, never offline.
- Unknowns: `PlatformReportType.unknown` has no definition; unsupported
  row values are `PlatformReportValue.unsupported()` and counted in each
  `PlatformReportBreakdown.unsupported`; unknown limit/feature keys are dropped
  and flagged; invariant breaks (sums ≠ `tenantCount`, negatives, duplicates,
  range mismatch, wrong type) → unreadable.
- Authorization: `super_admin` UX gate only; server authorizes every read; no
  `Cap`, no fine-grained report permission, break-glass confers nothing.

### H. Files

Added (no existing Dart file changed):

- `flutter_app/lib/features/platform/domain/platform_report_models.dart`
- `flutter_app/lib/features/platform/domain/platform_report_datasets.dart`
- `flutter_app/lib/features/platform/domain/platform_reports_repository.dart`
- `flutter_app/lib/features/platform/data/mock_platform_reports_repository.dart`
- `flutter_app/lib/features/platform/data/platform_reports_providers.dart`
- `flutter_app/test/features/platform/platform_reports_domain_test.dart`
- `flutter_app/test/features/platform/platform_reports_repository_test.dart`

Docs (relevant sections only): `API_CONTRACT.md`, `CAPABILITIES.md`,
`DATA-NEEDS.md`, `SCREEN-ROUTE-MATRIX.md`, this handoff.

Mock: `MockPlatformReportsMode` loaded / empty / stale / offlineWithCache /
offlineWithoutCache / failure / notPermitted / nextPageFailure / cursorExpired
/ unsupportedValues, plus `auditRetention` for partial coverage;
`kMockReportCacheAge = 3h`; 8 retained snapshots.
Providers: `platformReportsMockConfigProvider`,
`platformReportsRepositoryProvider`, and first-page families
`subscriptionReportProvider`, `usageLimitsReportProvider`,
`featureAvailabilityReportProvider`, `platformActivityReportProvider`.
Selectors: `platformReportFreshness`, `platformReportViewState`.

### I. Tests and validation

Focused Point 13A batch: **55/55 passed** (domain 34, repository 21) —
catalogue closure, range boundaries/default/max, offsets, unsupported values,
breakdown invariants, query equality/validation, stable ordering, bands incl.
zero limit, deleted-tenant refusal, forbidden-field refusal, type/summary/range
invariants, freshness/view-state selectors, paging state; repository
loaded/empty/filtered-empty/stale/offline±cache/failure/not-permitted/
next-page failure/cursor expired/foreign & malformed cursor/unsupported
values, snapshot paging, Clock determinism, consistency with Point 5 counts,
Point 7 limits and Point 8 features, Audit drill-down counts equal
`MockPlatformAuditRepository` results, retention coverage, no store/Audit
mutation, `TenantRepositoryWatch` empty, import scan, no forbidden model field.
`dart format`: 7 new files clean. `flutter analyze`: **No issues found**.
`git diff --check`: clean (new untracked files also checked for trailing
whitespace). `graphify update .`: succeeded (10,184 nodes, 15,519 edges, 328 communities). Full suite
intentionally not run (Point 13C).

### J. Backend gaps and open product policy

Owed: the four authorized projections; snapshot-bound cursors; a real
`admins` usage aggregate; an Audit count projection that agrees with
`GET /platform/audit` and honours retention. Historical subscription/
lifecycle/usage snapshots and Health/Security history do not exist — **no
trend report until they do**, and none from current state or current
tenants' `createdAt`. Open (Claude-provisional where noted, pending Ahmed):
near-limit threshold (none; provisional: rank instead); bucketing time zone
for any future series; export formats (provisional: none); fine-grained
report permission (provisional: none); Audit retention; max range 366 days
(provisional).

### K. UX contract for Point 13B (frontend-design → impeccable → emil)

Operate mode, restrained, existing Platform vocabulary only (`PlatformPage`,
`PlatformSectionHeader`, `SectionLabel`, `SettingsSection`/`NavigationRow`,
status chips, `ChoicePill`, theme tokens via `context.c`, `AppSpacing`).
**Signature: the provenance line** — every report states, directly under its
title, what it is, as of when / for which range, from which source, and what
it excludes. No hero, no KPI wall, no decorative chart.

1. **Routing.** `PlatformOperationsRoutes.reports = '/platform/reports'`
   (catalogue) with child `:reportType` (wire values). Register in
   `_platformOperationsRoutes`; add `reports` to Operations
   `siblingSegments` **and** make sibling matching prefix-aware for
   `/platform/reports/<type>` (test deep links + area highlighting). Unknown
   `:reportType` renders a safe "تقرير غير مدعوم" state with a way back — no
   redirect loop. Operations row "تقارير المنصة" becomes a real
   `NavigationRow` (remove it from the planned note card). Child routes, not
   tabs: filters differ per report and back returns to the catalogue.
2. **Catalogue landing.** Two `SectionLabel` groups — "الحالة الحالية"
   (subscriptions, usage & limits, features) and "خلال فترة" (activity). One
   `NavigationRow` each: icon, title, one-line question, and a **text**
   data-kind label ("لقطة حالية" / "حسب الفترة"). No numbers on the landing.
3. **Report header.** Title in the app bar + refresh action (tooltip).
   Question line; provenance line — snapshot: "لقطة حالية · حتى <date> <time>";
   activity: "<first> – <last> · حسب توقيت الجهاز · المصدر: سجل تدقيق المنصة";
   snapshot scope line: "يشمل الفرق النشطة والمعلّقة وقيد الحذف، ولا يشمل
   الفرق المحذوفة". Freshness (stale / offline-cached) as text + icon in
   `warn` tokens, never colour alone. Times/ids LTR-isolated.
4. **Filters.** A "تصفية" button with an active-count badge, then removable
   active-filter chips and "مسح الكل". <900 dp: modal bottom sheet (Audit
   filter-sheet pattern), applies on "تطبيق", dismiss discards. ≥900 dp:
   start-side panel (~300 dp) beside the body, changes apply immediately.
   Any change → new first-page query. Activity: range button first, presets
   7 / 30 / 90 days, the platform date-range picker limited to 366 days and
   the injected clock's today; category filter. Usage: a `limitKey` pill row
   ("الكل" + six keys) that ranks, separate from filters.
5. **Summaries** — labelled breakdown lists, every known bucket shown (zero
   included), unsupported shown as "غير مدعوم في هذا الإصدار" when > 0:
   label · count · thin proportion meter (count/total, `ExcludeSemantics`,
   never the only carrier). Subscriptions: status, access state, plan
   (+ "بلا خطة"). Usage: per key "فوق الحد · عند الحد · ضمن الحد · بلا خطة"
   (compact: wrap per key; ≥900: small keys × bands table). Features: per
   module "مفعّلة n · معطّلة n". Activity: grouped by category with totals;
   each action row with count > 0 pushes `/platform/audit` with
   `report.auditQueryFor(action)` as `extra`; "إجراءات أخرى" row
   non-interactive; emergency-access group note "أحداث حوكمة مسجلة، وليست
   حوادث أمنية".
6. **Chart policy.** No charts in Point 13: no series (no history/bucketing
   contract), no pie/donut. The only graphic is the redundant proportion
   meter; `AnimatedCounter` must not be used for report numbers.
7. **Rows** (snapshot reports). Heading "الفرق (n)" with n = `tenantCount`.
   Compact: two-line tiles — name + non-active lifecycle chip; then
   report facts (subscriptions: status · plan/"بلا خطة" · "تنتهي التجربة /
   يتجدد / تنتهي المهلة <date>"; usage: "<usage> / <limit> <key> · <band>" +
   "مخصص" when overridden, for the selected key or the worst key; features:
   four wrapped "<module>: مفعّلة/معطّلة/غير معروفة" chips). ≥900 dp: dense
   table in its own horizontal scroll container, rows ≥ 48 dp. Tap pushes
   `/platform/tenants/:tenantId`. Paging: explicit "عرض المزيد" with "عُرض x من
   n", folded through `PlatformReportRowsState`; offline disables it with a
   reason; page failure inline + retry (rows stay); `mustReload` inline
   "تغيّرت بيانات التقرير" + "إعادة التحميل".
8. **States** (from `platformReportViewState` + freshness): skeleton (header +
   3 summary blocks + 4 rows); loaded; empty ("لا توجد فرق مسجلة" / "لم يُسجَّل
   نشاط في هذه الفترة" + widen-range action); filtered-empty + "مسح عوامل
   التصفية"; stale strip + retry; offline cached (load-more off); offline
   no-data + retry; not-permitted; safe failure + retry; unsupported-values
   notice; unsupported limit/feature keys notice; partial-coverage notice
   "السجل متاح منذ <date> فقط؛ الأعداد قبل ذلك غير متاحة". Refresh keeps
   content and shows a top linear progress indicator.
9. **Accessibility.** Reading order header → provenance → filters → summary
   → rows → paging; each bucket one semantics label ("تجربة: فريقان");
   status/band/state always text; ≥ 48 dp targets incl. chip delete; 1.6×
   text wraps (label above count at narrow widths, no fixed heights);
   keyboard-reachable sheet/panel controls in logical order; page-failure
   message `liveRegion`; RTL-first with directional APIs.
10. **Responsive.** 320–390 dp primary (stacked); 600 dp same single column
    with wider constrained reading width (rail shell); 900 dp side filter
    panel + tables. One widget tree with breakpoints, not two apps.
11. **Motion.** Nothing new: existing sheet/route transitions only, no
    stagger/count-up/meter animation; reduced motion = existing behaviour.

### L. Exact Point 13B scope

Route + Operations row + catalogue + four report pages per §K; a rows
controller per snapshot report using the repository cursor and
`PlatformReportRowsState` (revision-guarded like `PlatformAuditListController`);
filter sheet/panel; Arabic copy in `S`; all §K.8 states; navigation to tenant
detail and pre-filtered Audit; routing/isolation/state widget tests
(super-admin only, `TenantRepositoryWatch`, deep links, unknown type, paging,
offline paging refusal, drill-down query equality). Do **not** redesign the
catalogue, domain, contract, date/pagination rules or add export/charts.
13C: visual matrix (Dark Cyber, Purple Arena, Light, Eye Protection, reduced
motion; 320/390/600/900 dp; 1.6× text), accessibility verification, full
suite, closure docs.

**POINT 13 IS NOT YET COMPLETE.**

**NEXT: POINT 13B — PLATFORM REPORTS CORE UX & INTEGRATION.**

**POINT 14 WAS NOT STARTED.**

---

## POINT 12C — BREAK-GLASS FINAL UX, VISUAL VALIDATION & CLOSURE (2026-09-11)

Point 12A's architecture and security rules are preserved without change, and
Point 12B's routes, management/request flows, active-only picker,
confirmations, session/expiry handling, persistent awareness strip and Audit
catalogue remain the functional core. Point 12C adds presentation polish only:
the repeated body title is removed, production Arabic copy is centralized in
`S`, and the active state shows a stable Clock-derived remaining interval with
no countdown, polling or competing authority state.

The persistent `warn` / `warnTint` strip now enters and exits with a short
existing-token size/fade transition (no bounce or continuous motion) and is
immediate when animations are reduced/off. It exposes one live-region
announcement for a newly active or meaningfully changed emergency context,
not timestamp refreshes, while its open and end targets remain at least 48 dp.
State headings and labels communicate emergency, verified/unverified,
read-only scope, target, expiry, offline/stale and recent-auth states without
depending on icon or color. Technical ids stay LTR-isolated. Default RTL
reading/focus order remains visual and logical across management, request,
picker, reason, activation, confirmations, active controls, End Access, strip
and Audit link; no custom focus system was needed.

The final render harness produced and was visually inspected for 12 compact
cases: no-grant and request in Light; active plus strip in Dark Cyber;
near-expiry; stale/unverified; recent-auth-required; offline/no authority;
320 dp at 1.6× text; 600 dp Purple Arena; 900 dp Light; Eye Protection; and
Reduced Motion. Management, request and strip were also covered at 390 dp.
There were no overflows, clipping, inaccessible controls, unintended
horizontal scrolling, theme-token violations or motion-dependent content.

Validation: all directly changed Dart/test files formatted cleanly; Point 12
plus affected routing/Audit tests **137/137 passed**; visual render matrix
**12/12 passed** and actual PNGs were inspected; `flutter analyze` reported
**No issues found**; the full Flutter suite passed once, **1553/1553**;
`git diff --check` is clean; and the final Graphify update succeeded with
**9,873 nodes, 15,078 edges and 320 communities**.

Backend/product gaps remain intentionally unresolved: real duration and
limits; whether any write scope will ever exist; dedicated grant-scoped read
endpoints and the exact emergency tenant data allowed; recent-auth freshness
and step-up mechanism; Main Admin notification; Audit detail/retention policy;
and who besides the initiator may revoke. The frontend remains read-only
management only. Flutter is not the security boundary, appends no Audit,
creates no Security Alert, initializes no operational tenant repository, and
contains no emergency tenant-data viewer.

**POINT 12 — COMPLETE.**

**NEXT: POINT 13 — PLATFORM REPORTS.**

**POINT 13 WAS NOT STARTED.**

---

## POINT 12B — BREAK-GLASS CORE UX & INTEGRATION (latest session, 2026-09-11)

**POINT 12B IS COMPLETE. POINT 12 IS NOT YET COMPLETE.** Codex implemented the
bulk of 12B and stopped at the focused-test stage; Claude then reviewed the
tree, fixed the concrete defects listed in §J, added the missing guarantee
tests, and finished the docs. No full visual/theme/accessibility matrix and no
full suite were run — both belong to Point 12C.

### A. Point 12A architecture — preserved, not re-decided

Super Admin only; one `active` `SaasTenant`; closed read-only scope
`tenant_operational_read`; no impersonation, no `Cap` key, no `Cap.all`, no
write scope; suspended / deletion pending / deleted never bypassed; Feature
Flags and Plan Limits enforced; commands online-only and never queued; a
stale/offline grant is shown but never usable; the backend is the security
boundary; Flutter appends no Audit. `AuthUser` stays `super_admin`,
`saasTenantId: null`, `Capabilities.none`. The 12A domain, repository seam,
mock, `breakGlassCurrentProvider`, `breakGlassAccessProvider` and action
controller are unchanged in behaviour; 12B added only
`breakGlassEligibleTenantsProvider` to the providers file.

### B. Routes

| Route | Page | Where |
| --- | --- | --- |
| `/platform/access` | `PlatformBreakGlassPage` (management) | Operations branch, sibling of Health/Security/Audit (`PlatformOperationsRoutes.access`) |
| `/platform/access/request` | `PlatformBreakGlassRequestPage` | child of `/platform/access` (`PlatformOperationsRoutes.accessRequest`), so its stack always has management beneath it |

Both sit under the existing `super_admin`-only `/platform` subtree guard; a
tenant role is refused every location (`platform_routing_test`). No other
entry point.

### C. Operations integration

The Operations "الوصول الطارئ" row is real: it pushes `/platform/access` and
its subtitle is `BreakGlassCopy.operationSummary` — "لا يوجد وصول طارئ نشط" or
"<team> · ينتهي <local time>" plus "· غير مؤكد" when unverified. Reports stays
planned and non-interactive.

### D. Management and request flows

- **Management** — current state first. Inactive: state card, "طلب وصول طارئ",
  the five-line "حدود الوصول" fact list, and "عرض سجل التدقيق" (pushes Audit
  pre-filtered to `emergency_access`). No history list — Audit is the history.
  States: loading skeleton; none; usable (team, read-only scope chip, verified
  chip, issued, expiry, reason, near-expiry line, "إنهاء الوصول الطارئ");
  unverified (same facts, "غير مؤكد — غير قابل للاستخدام", no end action);
  expired; ended / revoked / tenant-unavailable by `endReason`, each with
  "طلب وصول طارئ" again; unsupported; stale-without-grant (cannot prove
  none → no request action); offline; not-permitted; failure + retry.
- **Request** — separate full page. Fixed scope text (not a control);
  "the server sets the end time" text; team search + dropdown of **active
  tenants only**; required reason (multiline, counter 280, whitespace
  normalized, inline required/too-long validation). Submit re-checks the
  canonical lifecycle projection and aborts without sending if the tenant left
  `active`.
- **Active-only selection** — `breakGlassEligibleTenantsProvider` pages the
  Platform `SaasTenantRepository` (never a tenant-operational repository) and
  filters through `BreakGlassPolicy.tenantEligibility`; the backend repeats it.

### E. Confirmation behaviour

- **Activation: exactly one** `showPlatformConfirmationSpec` (warning
  severity) naming the team, read-only scope, the reason, that Feature
  Flags / Plan Limits / lifecycle stay enforced, and that the server sets the
  end time and audits it. No typed-name step. The UUIDv7 attempt key is minted
  after confirmation per draft fingerprint (tenant id + version + reason) and
  reused only for a retry of the unchanged draft.
- **End: exactly one** confirmation ("إنهاء الوصول إلى <team>؟"), from the
  management page or the strip. Success is announced with a SnackBar.
- Outcomes: success / `break_glass_already_active` pop back to management
  (Operations back stack kept); stale refreshes candidates and keeps the
  draft; offline is refused and never queued; other codes show localized copy.

### F. Persistent `PlatformShell` strip

`PlatformBreakGlassStrip` sits above the branch body in both compact (bar) and
expanded (rail) layouts — in-layout, never an overlay, never in the tenant
shell. Shown whenever `isPossiblyLive`: warn icon + "الوصول الطارئ نشط · <team>",
state ("قراءة فقط — السجلات التشغيلية" / "ينتهي قريباً" / "غير مؤكد وغير قابل
للاستخدام") and LTR-isolated expiry time; tap-through to `/platform/access`;
"إنهاء الوصول" enabled only when usable. One Semantics container label. While
shown it owns the top system inset and `PlatformBreakGlassBodyInset` removes
it from the page below, so the page's app bar does not pad for the status bar
twice. It survives navigation across every Platform area (tested).

### G. End, expiry, session

- End removes the strip at once and the page shows the ended state.
- Expiry: the strip schedules one one-shot `Timer` at `expiresAt − 10 min`
  and one at `expiresAt` (no polling, no ticking). At expiry it invalidates
  `breakGlassAccessProvider`, re-reads current, removes the strip and shows one
  SnackBar "انتهى الوصول الطارئ إلى <team>." `effectiveStatusAt` fails closed at
  exactly `expiresAt`, so usable authority ends even before the re-read.
- Session: the repository provider rebuilds on any signed-in-account change;
  sign-out/sign-in never carries a grant (`platform_break_glass_session_test`).
  A Super Admin's sign-out confirmation adds "ينهي تسجيل الخروج أي وصول طارئ
  مرتبط بهذه الجلسة."

### H. Recent-auth and offline

- `recent_authentication_required` opens an explanation dialog ("لا يمكن
  للتطبيق إثبات حداثة المصادقة…") offering only close or sign-out. Flutter does
  not re-authenticate, verify freshness, or retry; the draft is lost.
- Offline: the management page shows a cached possibly-live grant as
  unverified and unusable; activation/end return `BreakGlassActionOffline`
  and nothing is queued.

### I. Audit catalogue integration

`platform_audit_models.dart` now recognizes `break_glass_activated`,
`break_glass_ended`, `break_glass_expired`, `break_glass_revoked` → category
`emergency_access`, and target type `break_glass_grant`. `AuditCopy` renders
them in Arabic ("تفعيل/إنهاء/انتهاء مدة/سحب الوصول الطارئ", "الوصول الطارئ",
"منحة الوصول الطارئ"); filter options derive from `.values`, so the category,
actions and target appear in the Audit filters. `/platform/audit` accepts a
`PlatformAuditQuery` as route `extra` for the pre-filtered link. Unknown values
still parse as the typed `unknown`. `PlatformAuditRepository` is still
read-only — no append exists.

**No emergency tenant-data viewer was built.** Nothing renders tenant
operational data under a grant.

### J. What Claude fixed on top of Codex

1. Strip drew under the status bar on a real phone (`SafeArea(top: false)`),
   and the page's app bar padded for the status bar again below it → strip
   now owns the inset and `PlatformBreakGlassBodyInset` removes it below.
2. Activation confirmation omitted the reason (12A §G.4) → the reason is now
   shown in the "what changes" line.
3. Successful activation used `context.go`, resetting the Operations back
   stack → pops back to management (falls back to `go` if nothing to pop).
4. A failed command showed "تعذّر تحميل الوصول الطارئ" (a load error) → uses
   the unused `breakGlassFailedAction` copy.
5. Ending was silent when done from the strip (12A §G.6 asks for an end
   announcement) → wires the unused `breakGlassEndedSnack`.
6. Typo in `breakGlassOfflineAction`: "قاة المزامنة" → "قائمة المزامنة".
7. `PlatformShell` doc comment still said "the shell reads no repository" →
   corrected to name the one Platform seam the strip reads.

### K. Files changed in Point 12B

Added: `presentation/platform_break_glass_page.dart`,
`presentation/platform_break_glass_request_page.dart`,
`presentation/platform_break_glass_actions.dart`,
`presentation/platform_break_glass_copy.dart`,
`presentation/widgets/platform_break_glass_strip.dart`,
`test/features/platform/platform_break_glass_ux_test.dart` (all under
`flutter_app/lib/features/platform/` or `flutter_app/`).

Modified: `core/router/app_router.dart` (two routes, audit `extra`),
`features/auth/presentation/sign_out_action.dart` (Super Admin warning),
`platform/data/platform_break_glass_providers.dart` (eligible-tenants
provider), `platform/domain/platform_audit_models.dart`,
`platform/presentation/platform_audit_copy.dart`,
`platform/presentation/platform_audit_page.dart` (initial query),
`platform/presentation/platform_operations_page.dart`,
`platform/presentation/platform_operations_routes.dart`,
`platform/presentation/platform_shell.dart`, `l10n/strings.dart`; tests
`platform_audit_domain_test.dart`, `platform_operations_test.dart`,
`platform_routing_test.dart`. Docs: `API_CONTRACT.md` (12A–12B section + new
"Client behaviour (Point 12B)"), `CAPABILITIES.md`, `DATA-NEEDS.md`,
`SCREEN-ROUTE-MATRIX.md`, this handoff.

### L. Verification

- `platform_break_glass_ux_test.dart`: 13 → **20** tests. Added: reason in
  the confirmation; back stack kept after activation; picker excludes
  suspended, deletion-pending and deleted tenants; management + request
  initialize no tenant repository; strip clears the status bar once; Super
  Admin sign-out warning; end announcement.
- Focused 12B batch (break-glass domain/repository/session/UX, Operations,
  routing, Audit domain/repository/integration/list/detail — 11 files):
  **125/125 passed** (was 120 before Claude's additions).
- Because `PlatformShell` changed, every `test/features/platform/` and
  `test/core/router/` test was also run: **427/427 passed**.
- `flutter analyze`: **No issues found.** `dart format`: changed files clean.
  `git diff --check`: clean (tracked and new files). `graphify update .`:
  9,804 nodes, 14,985 edges, 328 communities.
- The Operations routing assertion Codex changed (checks
  `PlatformBreakGlassPage` instead of the literal location) is correct:
  go_router reports the base location for imperatively pushed pages.

### M. Exact work left for Point 12C

1. Full visual pass of every management/request/strip state in Dark Cyber,
   Purple Arena, Light, Eye Protection, and reduced motion, at
   320 / 390 / 600 / 900 dp and 1.6× text (strip must wrap to two lines).
2. Strip enter/exit motion with existing primitives (≤200 ms size + fade,
   instant under `disableAnimations`) — today it appears/disappears instantly.
3. Accessibility: live-region announcement on strip appear / expire / end only
   (not per minute); focus order; ≥48 dp targets on the strip "إنهاء";
   screen-reader labels for state cards.
4. Relative remaining time next to the absolute expiry on the usable card
   (12A §G.3), without ticking.
5. `_BreakGlassHeading` repeats the app-bar title with unstyled `Text` —
   decide its typography or drop it.
6. Move the remaining inline Arabic literals in the break-glass pages, actions
   and sign-out warning into `S`.
7. Run the **full** Flutter suite, then close Point 12 with the unresolved
   policy list from 12A §I carried forward.

### N. Status

**POINT 12 IS NOT YET COMPLETE.**

**NEXT: POINT 12C — BREAK-GLASS FINAL UX, VISUAL VALIDATION & CLOSURE.**

**POINT 13 WAS NOT STARTED.**

---

## POINT 12A — BREAK-GLASS ARCHITECTURE & FOUNDATION (2026-09-11)

**POINT 12A IS COMPLETE. POINT 12 IS NOT YET COMPLETE.** Architecture, security
policy, typed domain, repository seam, session-bound mock, providers,
controller, focused tests and the backend contract. No route, screen, banner or
Operations-row change was made. The repository had no prior break-glass
semantics — only the planned Operations copy `الوصول الطارئ` and the planned
`/platform/access` route — so every rule below is derived from Points 3, 9, 10
and 11 and stated as the smallest safe model. Full wire contract:
`API_CONTRACT.md` → "Break-glass emergency access — Point 12A".

### A. What break-glass is in MTM

An exceptional, temporary, single-tenant, **read-only** authorization that the
backend attaches to **one authenticated Super Admin session**, for a required
platform-only reason, ending automatically at a server-set expiry.

| | Decision |
| --- | --- |
| Actor | `super_admin` session only; tenant roles never |
| Grants | closed scope catalogue with one value, `tenant_operational_read`: read the target tenant's operational records, bounded by its Feature Flags; `permitsWrites` is `false` for every scope |
| Target | one existing `SaasTenant` in `active` lifecycle (minimal `{tenantId, displayName}`); never a demo/tombstone/"all" |
| Reason | required; Point 9 convention reused (whitespace-normalized, non-empty, ≤280); platform-only, never tenant-facing, not copied into Audit changes |
| Duration | server-set; the client proposes none. Mock: **provisional** `kProvisionalBreakGlassGrantDuration = 1h` |
| Ends on | initiator end, `expiresAt`, bound session ending, target leaving `active`, platform revocation |
| After end/expiry | terminal; no renewal/extension; new access = new grant + new reason |
| Not | a role, tenant account, impersonation, `Cap` grant, `Cap.all`, Main Admin preset, Platform permission, tenant switching, or any Platform mutation |

`AuthUser` stays `super_admin`, `saasTenantId: null`, `Capabilities.none`
throughout — held by `platform_break_glass_session_test.dart`. The tenant
`MainShell`, `CapabilityGate` and `AdminExperience` never read a grant.

### B. State machine (`BreakGlassPolicy`, pure)

```text
(none) ──activate──▶ active ──end (initiator)──────────▶ ended[ended_by_initiator]
                       │   ──backend invalidation──────▶ ended[session_ended | tenant_unavailable | revoked_by_platform]
                       └── now ≥ expiresAt ────────────▶ expired
```

`BreakGlassGrantStatus { active, expired, ended, unknown }`; `ended` requires
`endedAt` + `endReason`. Every change bumps `revision`. `effectiveStatusAt(now)`
fails closed at exactly `expiresAt`. At most one possibly-live grant per
session (`break_glass_already_active`). Unknown status is readable but never
usable; unknown scopes are dropped (`hasUnsupportedScope`) and confer nothing;
malformed grants throw `FormatException` (unreadable, never partial).

### C. Precedence, lifecycle and entitlements

For a grant-authorized request: session → account lifecycle → `super_admin`
surface → live grant bound to this session → target match → target `active`
lifecycle → scope (read) → Feature Flag → (Plan Limit never reached). The grant
scope occupies the **Capability** step for this one actor; it is not a
capability. Nothing is substituted before it.

- Active tenant: eligible. Suspended / deletion pending: **denied**
  (`tenant_not_eligible`) — Point 9 FULL BLOCK is not bypassed; the Super Admin
  uses Platform lifecycle controls. Deleted: `tenant_already_deleted`; nothing
  recreated, tombstone untouched (tested). A target leaving `active` during a
  live grant ends it with `tenant_unavailable`; client access becomes
  `tenantUnavailable` immediately via `tenantLifecycleRevisionProvider`.
- Feature Flags: never bypassed. Plan Limits: never bypassed (read-only scope
  creates nothing). Subscription/features/limits/lifecycle/history unchanged by
  activate/end (tested by snapshot comparison).

### D. Session, recent auth, offline

- **Session-bound.** `platformBreakGlassRepositoryProvider` rebuilds on any
  signed-in-account change, so sign-out/sign-in never carries a grant. Nothing
  is persisted on device; restart re-reads `GET /platform/break-glass/current`.
- **Recent auth.** Typed `recent_authentication_required` →
  `BreakGlassActionRecentAuthRequired`. Flutter verifies nothing; with no
  step-up endpoint, the only honest 12B path is "sign in again" (existing MFA
  challenge), then a new request.
- **Offline.** Activate/end are online-only, never queued. An offline/stale
  read may *show* a possibly-live grant (`unverified`) but never makes it
  usable. Server expiry proceeds regardless.

### E. Repository, commands, providers

- `PlatformBreakGlassRepository`: `loadCurrent()`, `activate(ActivateBreakGlassCommand)`,
  `end(EndBreakGlassCommand)`. Separate from tenant operational repositories,
  lifecycle, Security, Audit and Auth (import-scan test).
- Activate: `tenantId`, `expectedTenantVersion` (lifecycle version reviewed),
  `scopes`, `reason`, **per-attempt** key `break-glass:activate:<uuidv7>`
  (a derived key would replay an ended grant). End: `grantId`,
  `expectedRevision`, key `break-glass:end:<id>:<revision>`. Same key + same
  command replays; different command → `idempotency_conflict`.
- Problem codes: `tenant_not_found`, `tenant_not_eligible`,
  `tenant_already_deleted`, `invalid_break_glass_reason`,
  `invalid_break_glass_scope`, `break_glass_already_active`,
  `break_glass_not_found`, `break_glass_not_active`, `stale_tenant`,
  `stale_break_glass`, `idempotency_conflict`,
  `recent_authentication_required`, `not_permitted`.
- Providers: `breakGlassMockConfigProvider` (mode/seed/latency),
  `breakGlassCurrentProvider`, `breakGlassAccessProvider`
  (`BreakGlassAccessDecision { state, grant, isPossiblyLive, isNearExpiry,
  permits(scope) }`), `breakGlassActionControllerProvider` (single-flight;
  outcomes Succeeded/Offline/Stale/RecentAuthRequired/NotPermitted/Invalid/
  Failed/Ignored; reloads current on state-changing problems). The access
  provider does not tick; consumers schedule one-shot re-evaluation.
- Mock: `BreakGlassFixtureScenario` none/active/nearExpiry/expired/ended/
  revoked/unsupported × `MockBreakGlassMode` loaded/stale/offline/failure/
  notPermitted/recentAuthRequired. Only injected `Clock`; reads the canonical
  `PlatformTenantStore`, never writes it.

### F. Audit and Security

Flutter appends nothing; `PlatformAuditRepository` unchanged and tested
untouched. Backend must append `break_glass_activated`, `break_glass_ended`,
`break_glass_expired`, `break_glass_revoked` under category `emergency_access`,
target type `break_glass_grant`, minimal tenant reference, and attribute every
grant-authorized request to the grant id. These values are **not yet** in the
Flutter Audit catalogue (they parse as the typed `unknown` fail-safe) — Point
12B adds them with copy/filters. A grant is not a Security Alert, adds no
Security category and no Overview attention item.

### G. UX contract for Point 12B (frontend-design → impeccable → emil chain)

Operate mode; restrained. Emergency state is carried by the existing `warn` /
`warnTint` tokens **plus** an icon and explicit text — never `crit` red, never
colour alone, no pulsing/flashing/countdown ticking, no full-screen takeover.

1. **Route** `/platform/access` inside the Operations branch
   (`PlatformArea.operations`, `platform_operations_routes.dart`), guarded by
   the existing `super_admin` subtree guard. The Operations "Break-glass" row
   becomes real and summarizes the state ("لا يوجد وصول طارئ نشط" / "نشط لـ
   <team> حتى <time>"). Request sub-route `/platform/access/request` (full
   page, keyboard-safe). No other entry point in Point 12.
2. **Management page hierarchy:** (a) current-state section first; (b) only in
   the inactive state, a compact "what this does / does not do" fact list
   (read-only, one team, ends automatically, recorded in Platform Audit, no
   changes to subscription/features/limits); (c) no history list — Audit is the
   history (link to Audit filtered by `emergency_access` once 12B adds it).
3. **States** from `BreakGlassAccessDecision`: none (primary action "طلب وصول
   طارئ"); usable (team, scope label "قراءة فقط — السجلات التشغيلية", issued,
   absolute local end time + relative remaining, reason, LTR grant id, action
   "إنهاء الوصول الطارئ" as a destructive secondary); near-expiry (text says it
   ends in under 10 min; no renew button); expired/ended/revoked (how and when
   it ended by `endReason`; "طلب وصول جديد"); unverified (cached, "تعذّر
   التأكيد — غير قابل للاستخدام حتى يتم التأكيد، وينتهي تلقائيًا في …");
   tenantUnavailable; unsupported (unknown state — treated as unavailable);
   loading skeleton; not-permitted; safe failure/retry.
4. **Request flow:** team picker (search; active tenants only), scope shown
   as fixed text (not a control), required reason (multiline, counter 280,
   inline validation), duration shown as "the platform sets the end time; you
   see it after activation". Then **exactly one** confirmation dialog naming
   team, read-only scope, reason, auto-end and audit recording, with
   "تفعيل الوصول الطارئ" / "إلغاء". No typed-name step (it is time-boxed and
   revocable, unlike final deletion). Mint the UUIDv7 attempt key on first
   submit of a draft; reuse it only for retrying that unchanged draft; a
   changed draft mints a new one. Outcomes: offline/failure keep the draft;
   stale refreshes the tenant; already-active routes back to the live grant;
   recent-auth explains and offers sign-in again (draft is lost — say so).
5. **End flow:** one confirmation ("إنهاء الوصول الطارئ إلى <team> الآن؟ ستحتاج
   طلبًا جديدًا بسبب جديد لاستعادته") → ended state; indicator disappears.
6. **Persistent active-context indicator** lives in `PlatformShell` (not in
   pages, not in the tenant shell), as an in-layout strip above the branch
   body in both compact (bottom bar) and expanded (rail) layouts, never an
   overlay. Shown whenever `isPossiblyLive`. Content: icon + "وصول طارئ نشط",
   team name, "ينتهي <local time>", an "إنهاء" action (≥48dp, opens the end
   confirmation), and tap-through to `/platform/access`. Unverified shows
   "غير مؤكد". Near-expiry changes text only. Wraps to two lines at 320dp /
   1.6× text; RTL-first with LTR-isolated times/ids. Semantics: one container
   label; live-region announcement only on appear/expire/end, not per minute.
   Enter/exit with the existing motion primitives (≤200ms size+fade), instant
   under `disableAnimations`.
7. **Expiry/exit:** one-shot `Timer` at the near-expiry threshold and at
   `expiresAt` that invalidates `breakGlassAccessProvider` (no polling); on
   expiry the indicator is removed and a non-blocking SnackBar says access to
   <team> ended. Sign-out confirmation mentions that it ends emergency access.
   Restart: no indicator until the backend read confirms (unverified offline).
8. **Audit catalogue:** add the four actions, `emergency_access` category and
   `break_glass_grant` target to `platform_audit_models.dart` with Arabic copy
   and filter options; tests updated accordingly.
9. Every state rendered in Dark Cyber, Purple Arena, Light, Eye Protection,
   reduced motion, 320/390/600/900 dp; then the full suite.

**Out of Point 12 entirely:** a tenant-data viewer under the grant (needs
product authority on content + backend grant-scoped read endpoints; when built
it lives under `/platform/access/…` in the Platform shell, reads through a
dedicated grant-scoped seam — never tenant operational repositories or the
tenant session — and renders only while `permits(tenantOperationalRead)`).

### H. Files and verification

Added:

- `flutter_app/lib/features/platform/domain/platform_break_glass_models.dart`
- `flutter_app/lib/features/platform/domain/platform_break_glass_repository.dart`
- `flutter_app/lib/features/platform/data/platform_break_glass_fixtures.dart`
- `flutter_app/lib/features/platform/data/mock_platform_break_glass_repository.dart`
- `flutter_app/lib/features/platform/data/platform_break_glass_providers.dart`
- `flutter_app/test/features/platform/platform_break_glass_domain_test.dart`
- `flutter_app/test/features/platform/platform_break_glass_repository_test.dart`
- `flutter_app/test/features/platform/platform_break_glass_session_test.dart`

Updated relevant sections only: `API_CONTRACT.md`, `CAPABILITIES.md`,
`DATA-NEEDS.md`, `SCREEN-ROUTE-MATRIX.md`, this handoff. No existing Dart file
was modified.

Focused Point 12A batch: **36/36 passed**. `flutter analyze`: **0 issues**.
`dart format`: 8 new files clean. `git diff --check`: clean. `graphify update
.`: succeeded (9,633 nodes, 14,668 edges, 326 communities). The full suite was
intentionally not run (no shared/core file changed); Point 12B runs it when
closing Point 12.

### I. Provisional and unresolved (need backend/product authority)

Provisional mock values: 1-hour duration; 10-minute near-expiry presentation
threshold. Unresolved: effective duration and limits; whether any write scope
may ever exist; the tenant-data read surface and its endpoints; the step-up
mechanism and freshness window; Main Admin notification of a grant; per-read
audit granularity and retention; who besides the initiator may revoke.

**POINT 12 IS NOT YET COMPLETE.**

**NEXT: POINT 12B — BREAK-GLASS UX & INTEGRATION.**

**POINT 13 WAS NOT STARTED.**

---

## POINT 11B — PLATFORM AUDIT LOG UX & INTEGRATION (2026-09-11)

**POINT 11 — COMPLETE.** Point 11A's canonical event, actor/action/category,
typed target/tenant/change, redaction, UTC ordering, opaque cursor, safe-search,
and read-only repository contracts remain unchanged. Point 11B added only the
production Platform UX and integration over that foundation. Point 12 was not
started.

### A. Route, Operations integration, and list UX

The canonical Super Admin route is `/platform/audit`, hosted inside the
Operations shell branch and classified by `PlatformArea.operations`. The
Operations landing now has three real rows: Health, Security, and Audit.
Break-glass and Reports remain plain planned copy with no dead controls. The
whole Platform subtree guard rejects Main Admin/Admin sessions before the Audit
repository can be read, and the route initializes no tenant-operational
repository.

The Arabic-first Audit list is a constrained, responsive, newest-first control
plane timeline. Each accessible row presents localized action, historical
actor, local device time, category, minimized team/tombstone context, and one
safe typed change summary when present. No raw enum/wire/JSON value is shown.
Unknown actor/action/resource/change values keep distinct professional
fail-safe labels.

### B. Search, filters, paging, and states

Search is a 300 ms debounced repository query over Point 11A's safe searchable
fields only; change bodies remain excluded. The progressive filter sheet
supports local inclusive start/end calendar dates converted to exact UTC
`from`/exclusive `before` instants, actor kind/id, action, category, team id,
and target type. Active filters are counted, clearing is explicit, and opening
or closing event detail does not reset query state.

Load-more uses only the opaque `nextCursor`. Query changes start page one;
successful pages append in repository order with event-id deduplication.
Already loaded rows remain visible during paging and page failure. A rejected
or repeated cursor stops the loop and offers a deliberate first-page refresh.

The page distinguishes initial skeleton, in-place refresh, paging, no Audit
records, no matching results, stale cache, offline cached/no-cache, safe
first-page failure, and safe next-page failure/retry. It does not claim fresh
or complete data while offline and has no outbox, polling, or real-time claim.

### C. Detail, navigation, privacy, and separation

An adaptive scrollable bottom sheet groups Event, Actor, Target/team, and typed
Changes. Administrator history displays only id/name; system and unknown remain
distinct. Technical ids are isolated LTR. Redacted values say only that the
value is restricted; malformed or arbitrary text never passes through.

Current-team navigation revalidates the live Platform store before opening the
real `/platform/tenants/:tenantId` route. Deleted references open only when the
restricted Point 9 tombstone seam actually exists; otherwise they remain
noninteractive minimized historical context. Audit never reconstructs deleted
tenant state or exposes Team Code, Main Admin email, subscription/features,
limits/usage, operational data, credentials, OTPs, tokens, session material,
or request bodies.

Audit remains read-only: no acknowledge, resolve, edit, delete, archive,
mark-read, append, or export surface/API was added. Point 10 Security Alerts
remain current awareness in their own model/repository/screen. `SaasTenantEvent`
lifecycle history remains compact tenant chronology and does not depend on
Audit. Neither system drives current tenant state.

### D. Responsive, themes, motion, accessibility, and verification

The shared Platform layout constrains the wide reading column and the Audit
rows/sheet wrap at 320 dp with 1.6 text scale. RTL is primary; technical ids
are LTR-isolated. The UI uses semantic theme tokens and was rendered in Dark
Cyber, Purple Arena, Light, and Eye Protection variants. Bottom-sheet motion
uses the existing motion system and becomes instant for reduced-motion users.
Rows expose semantic action/actor/resource context, change summaries announce
“from … to …”, controls use standard touch targets, and detail/filter surfaces
remain keyboard- and scroll-safe.

Compact visual verification generated ten `/tmp/mtm-audit-render` artifacts:
390 dp populated, active search/no-results, safe detail/change, deleted
tombstone, unknown/redacted, offline cached, stale, 320 dp at 1.6 text with
reduced motion, 600 dp Purple Arena, and 900 dp wide. Visual inspection found
no overflow or sensitive-value leak.

Focused Point 11 batch: **52/52 passed**. Compact render batch: **10/10
passed**. `flutter analyze`: **0 issues**. Full `flutter test`: **1488/1488
passed**. `git diff --check`: **clean**. `graphify update .`: **succeeded**
(9,410 nodes; aggregated 309-community view rebuilt). Graphify's optional label
refresh suggestion was informational; the established update workflow passed.

### E. Files and genuine backend work

Point 11 implementation files:

- `flutter_app/lib/features/platform/data/platform_audit_list_controller.dart`
- `flutter_app/lib/features/platform/presentation/platform_audit_copy.dart`
- `flutter_app/lib/features/platform/presentation/platform_audit_detail.dart`
- `flutter_app/lib/features/platform/presentation/platform_audit_filters.dart`
- `flutter_app/lib/features/platform/presentation/platform_audit_page.dart`
- `flutter_app/lib/features/platform/presentation/platform_operations_page.dart`
- `flutter_app/lib/features/platform/presentation/platform_operations_routes.dart`
- `flutter_app/lib/features/platform/domain/platform_area.dart`
- `flutter_app/lib/core/router/app_router.dart`
- `flutter_app/lib/l10n/strings.dart`
- `flutter_app/test/features/platform/platform_audit_list_test.dart`
- `flutter_app/test/features/platform/platform_audit_detail_test.dart`
- `flutter_app/test/features/platform/platform_audit_integration_test.dart`
- `flutter_app/test/features/platform/platform_audit_render.dart`
- `flutter_app/test/features/platform/platform_operations_test.dart`
- `API_CONTRACT.md`, `CAPABILITIES.md`, `DATA-NEEDS.md`,
  `SCREEN-ROUTE-MATRIX.md`, and `HANDOFF.md`

The remaining work is backend-only: implement independently authorized
`GET /platform/audit`; append sanitized evidence authoritatively from existing
Platform mutations; resolve current/tombstone links without returning deleted
operational/configuration data; define retention/deletion policy; and decide
whether a durable client cache or freshness mechanism is desired. Flutter has
only the deterministic process-memory mock and makes no tamper-proof,
real-time, indefinite-retention, or compliance claim.

**POINT 11 — COMPLETE.**

**NEXT: POINT 12 — BREAK-GLASS MANAGEMENT.**

**POINT 12 WAS NOT STARTED.**

---

## POINT 11A — PLATFORM AUDIT LOG FOUNDATION (2026-09-10)

**POINT 11A IS COMPLETE. POINT 11 IS NOT YET COMPLETE.** This session added
the canonical typed, immutable/read-only Platform Audit domain and backend
contract. It deliberately added no production Audit screen, route activation,
break-glass behavior, incident workflow, reporting/export, or audit mutation.

### A. Final event, actor, action, and target architecture

`PlatformAuditEvent` contains only a stable id, UTC `occurredAt`, typed actor,
typed action with a deterministic derived category, typed target, optional
minimal tenant reference, and an unmodifiable list of typed safe changes. It
has no severity/result, request/correlation reference, route, arbitrary
metadata, request body, or security-incident state.

Actors are `platform_administrator`, `system`, or fail-safe `unknown`. The
administrator is a historical snapshot containing only account id and display
name; it is not a live `AuthUser` and carries no email, capabilities, session,
device, IP, credential, OTP, or token. System/unknown actors carry no invented
service identity.

The initial action catalogue comes only from implemented Points 6–9:
`tenant_registered`; `subscription_activated`, `trial_extended`,
`trial_ended`, `subscription_moved_to_grace`, `plan_changed`;
`limit_override_changed`, `feature_flag_changed`; `tenant_suspended`,
`tenant_reactivated`, `deletion_requested`, `deletion_cancelled`, and
`deletion_finalized`. Categories are derived as tenant management,
subscription, entitlement, or lifecycle. Unknown future values stay typed
unknown and never masquerade as a known operation.

Targets are typed as tenant, subscription, plan assignment, tenant feature,
tenant limit, tenant lifecycle, or unknown. They carry only a stable id and
optional safe label, never a route or authorization decision. An unknown
resource discards its unclassified id/label at the parsing boundary.

### B. Tenant/tombstone, immutability, changes, and redaction

A tenant-linked event contains only tenant id, a restricted display-name
snapshot, and `isDeleted`. Deleted references remain minimal tombstones and
cannot reconstruct a `SaasTenant`; Team Code, Main Admin email, subscription,
features, limits, usage, and operational records are absent. Tenant deletion
and minimized Audit retention are separate policies, and Audit never drives or
restores current tenant state.

The Flutter boundary is append-free: `PlatformAuditRepository` exposes only
`listAuditEvents`. There is no edit/delete/mark-read/acknowledge/resolve or
history rewrite. The future backend is the authoritative append owner; Flutter
does not claim that local mock records are tamper-proof evidence.

Changes are a closed list of lifecycle status, subscription status, plan
assignment, feature-enabled, and limit-override fields with typed
text/boolean/integer values. They are not object snapshots. The central safety
policy rejects/redacts unknown or malformed pairings and forbidden names,
including passwords, temporary passwords, OTPs, tokens, secrets,
authorization/session material, credentials/cookies, and Team Codes. Direct
Dart construction and wire parsing use the same safe getters; redacted output
contains no value. The server must sanitize before persistence because the
client is not the primary security boundary. Arbitrary request bodies and
medical operational records are forbidden.

### C. Query, ordering, repository, and deterministic mock

`PlatformAuditQuery` supports only inclusive `from`, exclusive `before`, actor
kind/id, action, category, tenant id, target type, safe free text, opaque
cursor, and a 1–100 page limit (default 50). Search covers event id, actor
display name, target id/label, and tenant id/name only; it never searches
change bodies. `PlatformAuditPage` contains immutable items and optional
`nextCursor`, with no count requirement.

`MockPlatformAuditRepository` filters before paging and orders by
`occurredAt DESC, id DESC`. Its cursor is an opaque encoded sort-key anchor;
malformed or filtered-out anchors return typed validation failure rather than
silently restarting. Loaded, empty, stale, offline-with-cache,
offline-without-cache, and safe failure modes are available through dedicated
providers.

`PlatformAuditFixtures` calls injected `Clock` once and builds a small,
immutable representative history. It includes administrator and system actors,
tenant-linked plan/limit/feature/lifecycle events, a deleted minimal tombstone,
a redacted unknown future event, and equal timestamps for deterministic id
tie-break coverage. It imports no current tenant, lifecycle-history, or
Security Alert truth and cannot mutate any of them.

### D. Critical separations and backend authority

`PlatformSecurityAlert` remains current security-relevant awareness through
`PlatformSecurityRepository`; it is not historical actor-attributed Audit and
opening Health/Security creates no fake event. `SaasTenantEvent` status history
remains compact tenant/subscription state chronology with no actor and is not
merged with Audit. Audit is also not break-glass management; Point 12 remains
untouched.

The future `GET /platform/audit` contract requires independent server-side
Platform authorization, authoritative append semantics, server-side
pre-persistence sanitization, UTC timestamps, stable newest-first ordering,
opaque cursor pages, and the exact small filter/search surface above. No
database/SIEM/SOC design is claimed. Retention duration remains an undecided
backend/platform policy: final tenant deletion does not automatically erase
minimized Audit evidence and does not authorize indefinite retention.

### E. Files and verification

Added:

- `flutter_app/lib/features/platform/domain/platform_audit_models.dart`
- `flutter_app/lib/features/platform/domain/platform_audit_repository.dart`
- `flutter_app/lib/features/platform/data/platform_audit_fixtures.dart`
- `flutter_app/lib/features/platform/data/mock_platform_audit_repository.dart`
- `flutter_app/lib/features/platform/data/platform_audit_providers.dart`
- `flutter_app/test/features/platform/platform_audit_domain_test.dart`
- `flutter_app/test/features/platform/platform_audit_repository_test.dart`

Updated only the relevant contract/status sections in `API_CONTRACT.md`,
`CAPABILITIES.md`, `DATA-NEEDS.md`, `SCREEN-ROUTE-MATRIX.md`, and this handoff.
Focused Point 11A domain/repository batch: **25/25 passed**. Final root checks:
`flutter analyze` **0 issues**, `git diff --check` clean, and
`graphify update .` succeeded. The full Flutter suite was intentionally not
run; Point 11B must run it when closing Point 11.

Genuine remaining work: the backend endpoint/authorized read, authoritative
event append integration with existing platform mutations, production
retention policy, and Point 11B's route plus loading/empty/offline/error,
responsive Audit list/detail, filters/search, and navigation validation.

**POINT 11 IS NOT YET COMPLETE.**

**NEXT: POINT 11B — PLATFORM AUDIT LOG UX & INTEGRATION.**

**POINT 12 WAS NOT STARTED.**

## POINT 10 — PLATFORM HEALTH & SECURITY (latest session, 2026-09-10)

**POINT 10 — COMPLETE. POINT 11 WAS NOT STARTED.** The reserved Platform
Operations surface is now a real, read-only Super Admin health and security
experience. It stays backend-neutral, reuses Point 5's established product
signals, does not initialize tenant operational repositories, and adds no
audit, break-glass, report, incident-workflow, or infrastructure-monitoring
scope.

### A. Architecture and typed domains

Point 10 uses two deliberately independent repository boundaries:
`PlatformHealthRepository` and `PlatformSecurityRepository`. Health and
security have different loading/failure lifecycles, so either snapshot may
remain useful when the other read fails; no aggregate god repository or raw
map reaches presentation.

The health domain contains `PlatformHealthSnapshot`,
`PlatformHealthSignal`, and `PlatformHealthStatus` with the established
`healthy`, `degraded`, `unavailable`, and `unknown` states. A pure selector
derives overall health with conservative precedence: unavailable, degraded,
unknown, healthy; an empty catalogue is unknown rather than healthy.
Unsupported wire values fail closed to unknown.

The security domain contains `PlatformSecuritySnapshot`,
`PlatformSecurityAlert`, `PlatformSecurityTenantReference`, typed severity
(`info`, `warning`, `critical`, `unknown`), and typed category
(`authentication`, `unknown`). Its pure summary selector gives critical and
unknown conservative precedence, then warning, informational, and the honest
no-alert state. No actor, IP, request id, evidence payload, acknowledgement,
assignment, resolution, or mutation was added.

### B. Canonical deterministic data and Point 5 consistency

`PlatformOperationsFixtures` is the single deterministic `Clock`-based mock
truth for both Point 10 detail and Point 5 overview projection. Point 5 no
longer owns contradictory hard-coded health/security values: its overall
health derives from the same health signals, and its security attention count
and severity derive from the same alerts. Refresh/invalidation therefore
cannot produce two independent mock realities.

The health catalogue remains exactly the three Point 5 product-level signals:

- `identity` — login and sessions;
- `background_jobs` — background tasks;
- `files` — files and export.

No hosts, databases, queues, cloud regions, CPU/RAM, SLA, or other invented
topology was introduced. Security uses only the already justified
authentication category plus fail-safe unknown. Fixtures are neutral
development scenarios, not claims of real incidents.

Mock repository modes cover healthy, degraded, unavailable, unknown, partial,
stale, offline with cached data, offline without data, and safe failure for
Health; and no-alert, informational, warning, critical, mixed,
tenant-linked, platform-wide, unknown, stale, offline cached/no-cache, and
failure for Security. Every timestamp comes from injected `Clock`; Point 10
contains no `DateTime.now()`.

### C. Routes, Operations, and overview navigation

The existing route contract remains authoritative:

- `/platform/operations` — useful Operations landing;
- `/platform/health` — Platform Health;
- `/platform/alerts` — Platform Security.

Health and Security are the only real interactive module rows on the landing.
Audit, Break-glass, and Reports remain visibly planned and noninteractive, so
there are no dead cards. The existing four Platform root areas remain
Platform, Tenants, Operations, and More; no fifth destination was introduced.
The Operations branch recognizes both detail routes, including direct deep
links, and Point 5 health/security affordances now open their real targets.

All three routes remain inside the Platform shell and are guarded by the
existing `super_admin` surface boundary. `main_admin` and `admin` direct links
are rejected without a tenant-shell flash. No tenant `Cap` key was invented;
the future server must independently enforce Platform authorization.

### D. Health and Security experiences

The responsive Health page presents snapshot time/freshness, a restrained
overall state, compact signal cards with explicit textual status and observed
time, and attention detail only where meaningful. It distinguishes platform
degradation from read failure, partial data from no usable data, and an
unavailable signal from offline transport. Pull-to-refresh and an explicit
refresh action are provided; there is no polling, animation dependency, or
live/real-time claim.

The responsive Security page is read-only and presents a calm current-state
summary followed by alerts with textual severity, category, safe description,
detection time, and optional tenant context. An empty list says only that the
loaded snapshot has no current alerts; it never claims complete security.
Unknown severity/category remains visible and never collapses into no risk.

A tenant-linked alert becomes interactive only after its reference matches
the canonical Platform tenant store as a current tenant or retained tombstone.
Navigation uses only `/platform/tenants/:tenantId`; it never opens a tenant
operational shell. Missing/invalid references remain display-only. Tombstone
context is restricted to the Point 9 platform-safe id/display-name/deletion
metadata and never reconstructs Team Code, admin email, subscription,
features, or operational records.

### E. Freshness, offline, error, privacy, and accessibility

Freshness is derived from immutable snapshot timestamps and existing
repository metadata. Stale and cached/offline snapshots retain their original
generation time and are labeled honestly. Offline without a snapshot and
repository failure render separate safe no-data states; raw exceptions are
never shown. Partial Health remains usable. Snapshot-empty Health is unknown,
not healthy.

Health status and security severity use text and screen-reader semantics in
addition to semantic theme colors. Controls preserve touch targets, focus
order, wrapping, RTL order, and bidirectional handling for technical values.
The screens were exercised at 320dp with 1.6 text scale, 390dp, 600dp, and
900dp; Dark Cyber, Purple Arena, Light, Eye Protection, reduced motion, and
the lowest performance preset all render without overflow or color-only
meaning. Wide layouts constrain content instead of stretching mobile rows.

### F. Production files added or materially integrated

- domain/contracts: `platform_health_models.dart`,
  `platform_health_repository.dart`, `platform_security_models.dart`,
  `platform_security_repository.dart`, and the Point 5-compatible updates in
  `platform_overview_models.dart`;
- data/providers: `platform_operations_fixtures.dart`,
  `mock_platform_health_repository.dart`,
  `mock_platform_security_repository.dart`,
  `platform_operations_providers.dart`, plus the narrow overview
  repository/provider projection updates;
- presentation/routing: `platform_health_page.dart`,
  `platform_security_page.dart`, `platform_operations_routes.dart`,
  `platform_operations_page.dart`, `platform_overview_page.dart`,
  `platform_area.dart`, and `app_router.dart`;
- shared copy: `strings.dart`;
- project contracts: `API_CONTRACT.md`, `CAPABILITIES.md`, `DATA-NEEDS.md`,
  `SCREEN-ROUTE-MATRIX.md`, and this handoff.

### G. Verification and orchestration

Root performed Wave 0 context/architecture/ownership work, then used six fixed
roles across sequential waves because the environment allowed three worker
slots beside Root. Wave 1 was focused discovery; Wave 2 implemented disjoint
domain, Health, Security, route/Operations, mock/provider, and test ownership;
Wave 3 returned only narrow fixes to the original file owners. Shared strings,
documentation, integration review, and final validation remained Root-owned.
No file had concurrent writers.

Focused additions cover parsing/fail-closed behavior, pure selectors,
deterministic Clock data, repository modes, Point 5 consistency, every Health
and Security screen state, Operations navigation, role rejection, invalid
tenant references, responsive rendering, appearance variants, and tenant
repository isolation. Final evidence:

- focused Point 10 integration batch: **77/77 passed**;
- Agent 6 analyzer-correction batch: **21/21 passed**;
- complete Platform regression directory: **312/312 passed**;
- Point 10 visual render test: **1/1 passed**, producing and reviewing 21
  screenshots across required routes/states/sizes/themes/motion settings;
- `flutter analyze`: **0 issues**;
- full `flutter test`: **1,440/1,440 passed**;
- `dart format`: clean;
- `git diff --check`: clean;
- `graphify update .`: succeeded; the graph now reports 9,158 nodes, 13,916
  edges, and 299 communities, with `graphify-out` refreshed.

### H. Backend gaps and exact next point

The future backend still needs the two authorized reads documented in
`API_CONTRACT.md`: Platform Health snapshot and Platform Security alerts. It
must provide UTC snapshot timestamps, partial/freshness semantics, safe
forward-compatible unknown states, server-side Super Admin authorization, and
privacy-minimal tenant/tombstone references. The frontend currently has only
process-memory cache, no durable cache, pagination, polling/push stream, or
fine-grained Platform authorization. Those are requirements/decisions for a
real backend only when justified; alert mutations remain deliberately absent.

**Exact next product point: POINT 11 — PLATFORM AUDIT LOG. Do not begin it as
part of Point 10 maintenance.**

## POINT 9B — TENANT LIFECYCLE UX & INTEGRATION (latest session, 2026-09-10)

**POINT 9 — COMPLETE.** Point 9B completed the production-facing lifecycle
experience on `sync-conflict-and-pending-work` without changing Point 9A's
canonical enum, legal transitions, FULL BLOCK policy, exact cancellation
restore, dedicated repository boundary, optimistic version/idempotency model,
provisional 30-day mock schedule, minimal tombstone fields, Team Code retirement,
or backend-controlled deletion/crypto-shred contract.

### A. Final Super Admin lifecycle experience

`/platform/tenants/:tenantId` now has one responsive control-plane lifecycle
section that shows the localized state, relevant dates, stable deadline context,
and only actions legal at the injected `Clock` instant:

- active: suspend or begin deletion;
- suspended: suspension time/platform-only reason, full-block/data-preservation
  explanation, reactivate or begin deletion;
- deletion pending before `scheduledFor`: request/schedule, remaining whole-day
  context, exact previous state, platform-only reason, and cancel only;
- deletion pending at/after `scheduledFor`: deadline-reached context and final
  deletion only.

Normal Subscription, Usage & Limits, and Features links remain separate.
Lifecycle actions are visually isolated below the informational content, and
final deletion is not styled as an ordinary management link. No timer or
background polling was added.

Suspend and begin-deletion collect a required normalized platform-only reason
of at most 280 characters with inline validation and a character counter. The
reason draft survives an offline refusal. Reactivate and cancel confirmations
state that subscription, flags, capabilities, and limits remain unchanged;
cancel copy names the exact prior active/suspended state rather than promising
activation.

Final deletion retains the two-step safety flow. Step one names the tenant and
explains that Flutter sends a backend request rather than erasing storage or
backups. Step two is non-dismissible, requires an exact byte-for-byte tenant
name and the irreversible acknowledgement, allows paste, and cannot be
submitted by Enter without both conditions. No fake MFA or break-glass flow was
introduced.

### B. Tombstone, list, overview, history, and navigation

The existing detail route renders a dedicated `DeletedTenantTombstone` when
the live `SaasTenant` is gone. It shows only display-name snapshot, tenant ID,
and deletion time plus restricted-control-plane guidance. It never renders Team
Code, Main Admin/email, subscription, limits, features, usage/counts,
reason/schedule, or full history. Finalization remains on this usable tombstone
view; the normal list is invalidated and the deleted row disappears.

The normal tenant list presents lifecycle-precedence labels and explicitly
distinguishes commercial filters from tenant-access filters. Active, suspended,
and deletion-pending tenants are available; deleted is deliberately not a
normal filter or subscriber row. Existing search/filter state remains owned by
the list controller.

Platform Overview preserves the Point 9A aggregate decision: suspension stays
in the existing suspended count, while each pending deletion is a Needs
Attention item. The item names the tenant, shows its scheduled/remaining-time
context, and opens the concrete tenant detail. No lifecycle KPI or dashboard
final-delete shortcut was added. Lifecycle history rows retain localized event,
timestamp, and safe short platform note; they remain chronology, not Point 11
audit evidence.

### C. Tenant users, runtime routing, privacy, and failures

`/tenant-suspended`, `/tenant-deletion-pending`, and `/tenant-deleted` are final
FULL BLOCK status pages with clear Arabic copy, sign-out and support. They show
no tenant identity or administrative reason. Suspended copy does not claim
deletion; pending copy does not invent a schedule; deleted copy keeps tenant
relationship distinct from account identity/revocation.

Central startup/router precedence remains unchanged. Suspended, pending, and
deleted users never build the operational shell, and direct deep links are
redirected before protected content renders. Runtime lifecycle invalidation
ejects an open tenant module to the authoritative status page. Reactivation
returns predictably to `/home`; the blocked operational deep link is discarded
rather than replayed. Preserved Feature Flags, capabilities, and limits are
then reapplied normally.

All typed lifecycle problems have safe Arabic presentation. Stale, invalid
transition, expired cancellation window, too-early finalization, already
deleted, idempotency conflict, and not-permitted outcomes refresh the detail
when current state may have changed; no destructive operation is blindly
retried and no backend code/exception is shown. Offline writes are refused,
never queued, and keep local form input where useful.

### D. Responsive, theme, motion, accessibility, and visual inspection

The lifecycle section and dialogs use directional layout, wrapping facts,
stacked narrow actions, constrained wide content, scrollable/view-inset-safe
dialogs, explicit text labels, and semantic status/action names. Technical IDs
stay LTR. Warning states never rely on color alone; controls retain normal touch
targets and the exact-name field exposes a clear label and inline mismatch.

The render harness produced and was visually inspected for 23 Point 9B states:
active/suspended/pending-before/pending-after detail, suspend/reactivate/begin/
cancel confirmations, both final-delete steps, tombstone, stale/offline,
320dp at 1.6x text, 900dp, Dark Cyber, Purple Arena, Light, Eye Protection,
Reduced Motion, and all three tenant lifecycle status pages. The final render
run completed without interaction warnings or overflow. No looping/countdown
animation was added; reduced motion remains fully usable.

### E. Backend/cache boundary retained

The UI never claims instant physical deletion, backup erasure, or client
crypto-shred. Backend policy remains authoritative for schedule, authorization,
session/access unlinking, primary/object/search/cache deletion, backup/legal
retention, audit retention, and key destruction where supported. The contract
now clarifies that reloadable tombstone presentation needs a restricted typed
read seam while normal tenant list/search must exclude tombstones.

Suspension does not wipe local cache. An offline tenant client cannot observe a
remote state change until revalidation; the server must already reject protected
work. Receiving final deleted state still requires a future approved scoped
cache/session/access-map invalidation policy. No new global purge engine was
invented.

### F. Point 9B files and verification

Primary implementation files changed:

- `tenant_lifecycle_copy.dart`, `tenant_lifecycle_management_section.dart`,
  `tenant_lifecycle_confirmation.dart`, and
  `widgets/platform_confirmation_dialog.dart`;
- `saas_tenant_detail_page.dart`, `platform_tenants_page.dart`,
  `platform_overview_page.dart`, status pages/shared `StatusScreen`, and Arabic
  strings;
- overview models/mock projection, tenant/tombstone providers, and lifecycle
  controller invalidation;
- `API_CONTRACT.md`, `CAPABILITIES.md`, `DATA-NEEDS.md`,
  `SCREEN-ROUTE-MATRIX.md`, and this handoff.

Focused tests were added/extended in lifecycle management, tenant detail/list,
overview states/consistency, and tenant status screens. They cover legal action
visibility around the deadline, reason validation/privacy, exact-name plus
acknowledgement, typed failure copy, offline draft preservation, finalization
to a minimal tombstone, list/overview refresh, and narrow responsive layout.

Closing verification:

- final affected lifecycle/startup/platform/subscription/feature batch:
  **174/174 tests passed**;
- Point 9B visual render harness: **1/1 passed**, producing 23 inspected
  lifecycle captures;
- `dart format`: 24 directly affected Dart/test files checked;
- `flutter analyze`: **0 issues**;
- one final full `flutter test --reporter compact`: **1399/1399 passed**;
- Impeccable manual detector: no findings in the lifecycle section, detail,
  and status surfaces; the final dialog was also covered by tests and visual
  QA;
- `graphify update .`: refreshed `graphify-out` successfully (8875 nodes,
  13468 edges, 307 aggregated communities);
- `git diff --check`: clean after the final documentation refresh.

No separate current-branch status/handoff file exists, so none was invented.

### G. Exact next point

**POINT 10 — PLATFORM HEALTH & SECURITY.** Point 10 was not started in this
session. Customer Demo management, Platform Audit, break-glass, reports, and
all other later points remain untouched.

---

## POINT 9A — TENANT LIFECYCLE FOUNDATION (latest session, 2026-09-10)

This is the historical foundation record; Point 9B above now closes Point 9.
Point 9A was completed as an architecture/foundation phase on
`sync-conflict-and-pending-work`. It establishes the state machine, safe
commands, canonical store behavior, startup/session consequences, backend
deletion contract, and focused tests. It intentionally does **not** close Point
9: the final user-facing lifecycle experience and visual/regression closure are
Point 9B.

### A. Canonical states and the one legal transition policy

`SaasTenantStatus` now has exactly four operational states:
`active`, `suspended`, `deletion_pending`, and `deleted`. The duplicate auth
`TenantStatus` was removed; `SessionAccess` and the platform domain use the
same canonical type. Unknown wire values remain preserved as unsupported by
`SessionAccess` and fail closed; unknown/inconsistent lifecycle objects make a
`SaasTenant` unreadable.

`TenantLifecyclePolicy` is the sole pure transition engine. Repositories ask it
for a new immutable versioned lifecycle; callers never assign an enum directly.

| From | Operation | To / result |
| --- | --- | --- |
| active | suspend with reason | suspended |
| suspended | reactivate | active |
| active | begin deletion with reason | deletion pending, restore=active |
| suspended | begin deletion with reason | deletion pending, restore=suspended with the original suspension metadata |
| deletion pending | cancel before `scheduledFor` | exact recorded prior state |
| deletion pending | finalize at/after `scheduledFor` | deleted |
| deleted | any normal operation | rejected; terminal |

All unlisted transitions are refused. Cancelling at or after `scheduledFor`
returns `deletion_window_expired`; finalizing earlier returns
`deletion_not_effective`. Suspension and deletion initiation require normalized
non-empty platform-only reasons up to 280 characters. Tenant-facing status copy
does not reveal them.

### B. Access policy and separation from Points 7–8

Suspension is **FULL BLOCK**, not read/export-only. Both Main Admin and Simple
Admin are kept outside the operational shell; no user capability is a bypass.
Deletion pending is the same full block while Super Admin retains Platform
visibility/control. Deleted is terminal, has no ordinary reactivation, and
cannot resolve as a normal active tenant resource. If the product later wants
read/export-only access it must add a distinct restricted-access lifecycle mode
with matching backend enforcement instead of weakening `suspended`.

Lifecycle changes do not cancel or activate a subscription, clear Feature
Flags, rewrite capabilities, reset a plan/limit override, remove the Team Code,
delete the Main Admin, or convert a Demo. The canonical tests snapshot and
compare subscription, feature, plan/override/count/config data through
suspend/reactivate and deletion pending. Point 7's End Trial → 14-day Grace
mock remains a separate **provisional commercial behavior** and is unchanged.

The access order is now explicit:

1. authentication/session validity;
2. account lifecycle;
3. `SaasTenant` lifecycle;
4. correct role/surface;
5. tenant Feature Flag;
6. Capability;
7. applicable Plan Limit.

### C. Deletion pending and provisional schedule

Beginning deletion does not physically remove anything. The lifecycle records
backend-facing `requestedAt`, `scheduledFor`, `previousStatus`, and a
platform-only reason; existing suspension metadata is retained only when it is
needed for exact cancellation. The deterministic Flutter mock uses a
**provisional 30-day** window. This is not a product rule: the backend must read
platform policy/config and return the authoritative schedule.

Normal tenant work is blocked during the pending window. Cancellation is
allowed only before finalization becomes effective and restores exactly active
or suspended. Final deletion is a distinct backend-controlled operation, not a
side effect of beginning deletion.

### D. Repository/controller, concurrency, idempotency, and offline

A dedicated `TenantLifecycleRepository` owns the five consequential commands:
`suspend`, `reactivate`, `beginDeletion`, `cancelDeletion`, and
`finalizeDeletion`. This gives the future platform API a clear command boundary
without bloating Point 6 reads/registration or mixing Point 7 commercial
mutations. It does **not** introduce a second tenant truth:
`MockTenantLifecycleRepository` mutates the same `PlatformTenantStore` used by
overview, tenant management, subscriptions/limits, and Feature Flags.

Every typed command carries `tenantId`, lifecycle `expectedVersion`, and an
idempotency key; suspend/begin also carry the reason. A stale version returns
`stale_tenant` without overwrite. A same-key/same-command replay returns the
original result with no new history event; different reuse returns
`idempotency_conflict`. A new-key duplicate is rejected by the state machine.
The result returns the new lifecycle, whether it changed, and an optional final
tombstone.

The compact typed problem set is: tenant not found, invalid transition,
invalid reason, stale tenant, deletion window expired, deletion not effective,
already deleted, idempotency conflict, not permitted, plus safe server failure;
offline remains its own transport result. The controller blocks duplicate
submissions, maps those results, refreshes all affected Platform projections,
and increments one lifecycle revision only after success. Platform lifecycle
writes are online-only and never enter the tenant operational outbox.

### E. Startup, routing, and runtime sessions

The typed startup classifier adds `/tenant-deletion-pending` between terminal
deleted and suspended lifecycle handling. Tenant lifecycle is evaluated after
authentication/account security and before surface/features/capabilities. A
direct deep link cannot bypass it. Main and Simple Admin both resolve to the
corresponding blocking page; Super Admin remains on the Platform surface even
when managing a non-active tenant.

For the development mock only, `effectiveSessionAccessProvider` composes the
signed-in real tenant association with the canonical store. Lifecycle revision
invalidation ejects an already-open tenant shell on suspension or deletion
pending and observes later reactivation without restart; a finalized tombstone
resolves to deleted rather than silently becoming active/not-found. Production
auth/session state remains backend-authoritative. Suspension is not account
revocation and does not manufacture session expiry.

The backend must enforce a newly restrictive lifecycle on every subsequent
protected request/session refresh and reject mutations immediately. An offline
client cannot know about a remote change; it must revalidate when connectivity
returns. Known suspension blocks the shell but does not itself erase local
cache. Final-deleted state requires a future approved cache/session/access-map
invalidation or purge policy.

### F. Final deletion and tombstone decision

Mock finalization removes the normal active `SaasTenant` and its mock feature
configuration, retires its Team Code, preserves the terminal status for session
classification, and retains only a minimal control-plane tombstone:
`tenantId`, display-name snapshot, `deletedAt`, lifecycle revision, and an
opaque history reference. It retains no Team Code, Main Admin/email,
subscription, plan/limits, Feature Flags, reason/schedule, usage, counts, or
operational data. The old Team Code no longer links onboarding and remains
reserved; no reuse operation exists.

Flutter's final-delete action is only a request to an authorized backend. The
backend owns storage deletion, cache/search invalidation, exported files,
object storage, backup/legal-retention policy, session/access unlinking, and
encryption-key destruction/crypto-shred where its architecture supports it.
The client manages no keys and makes no instant-erasure claim. Final deletion
may require recent backend MFA/reauth and privileged policy checks; the
two-step typed-name/irreversible confirmation is accidental-action safety, not
authentication and not Point 12 break-glass.

Tenant data deletion is separate from platform audit retention. These lifecycle
events must later emit actor-attributed audit/security evidence, but Point 11
was not built. A minimal compliance/security event may remain after tenant data
deletion under backend policy.

### G. Platform projections, history, and minimum UI proof

The Platform Overview still has no lifecycle-statistics wall. Suspended remains
in its existing aggregate; deletion pending is included in the existing
attention detail and creates one typed Needs Attention item. Commercial counts
are independently recomputed and remain unchanged by lifecycle mutations.

Tenant list/detail can represent active, suspended, deletion pending, and the
typed deleted/tombstone state where applicable. Detail contains a minimal
Point-9A lifecycle management section with actual controller calls. The shared
confirmation architecture now has typed consequence metadata for all five
actions. Suspend/reactivate/begin/cancel state what changes and what remains;
final deletion requires a second non-dismissible step, exact tenant-name entry,
and an irreversible acknowledgement. This is intentionally functional rather
than Point-9B-polished.

Lifecycle history adds `tenant_suspended`, `tenant_reactivated`,
`deletion_requested`, `deletion_cancelled`, and `tenant_deleted`, with timestamp
and safe short reason where relevant. This is tenant state chronology, not the
future immutable Platform Audit Log.

### H. Files changed for Point 9A

- Canonical/access/startup: `core/access/saas_tenant_status.dart`,
  `core/startup/startup_destination.dart`, `core/startup/startup_providers.dart`,
  `features/auth/domain/session_access.dart`, status/dev-state pages and strings.
- Domain/repository/store: `tenant_lifecycle_models.dart`,
  `tenant_lifecycle_repository.dart`, `mock_tenant_lifecycle_repository.dart`,
  `tenant_lifecycle_providers.dart`, `platform_tenant_store.dart`, tenant
  models/repository/fixtures, and overview models/repository projection.
- Minimum UI: `tenant_lifecycle_confirmation.dart`,
  `tenant_lifecycle_management_section.dart`, the shared Platform confirmation
  dialog, tenant list/detail/status copy, and overview attention copy.
- Contracts: `API_CONTRACT.md`, `CAPABILITIES.md`, `DATA-NEEDS.md`,
  `SCREEN-ROUTE-MATRIX.md`, and this current branch handoff.

### I. Focused tests and verification

New focused suites are:

- `tenant_lifecycle_domain_test.dart` — exhaustive transition policy,
  cancellation restore, boundary times, metadata validation, JSON/fail-closed;
- `tenant_lifecycle_repository_test.dart` — all five commands, preservation,
  history, stale/idempotency/offline, pending retention, final tombstone/code;
- `tenant_lifecycle_controller_test.dart` — double submit and typed
  stale/offline handling/invalidation;
- `tenant_lifecycle_management_test.dart` — required reasons/consequences and
  two-step final confirmation;
- `tenant_lifecycle_runtime_test.dart` — Main/Simple full block, live ejection,
  deep-link refusal, reactivation, pending, and finalized deleted state.

Existing startup/session/status, tenant repository, overview consistency, and
platform tests were extended for deletion pending, fail-closed parsing, Super
Admin precedence, and lifecycle/commercial separation. The final affected
Platform + startup group passed **384/384 tests** after tombstone minimization;
the isolated final lifecycle subset contains **33/33 passing tests**.

Closing verification:

- `dart format` checked all 40 Point 9A-touched Dart/test files with no
  remaining formatting change;
- `flutter analyze` completed with **0 issues** after the final copy edit;
- the final full `flutter test --reporter compact` run passed
  **1392/1392 tests**;
- the final confirmation-copy test passed **2/2** after the full-suite snapshot;
- `graphify update .` refreshed the mandatory code graph after the last source
  change;
- `git diff --check` was clean.

### J. Historical Point 9A next step (now completed)

**POINT 9B — COMPLETE TENANT LIFECYCLE UX & INTEGRATION.** Finish production
presentation of the already-settled domain: responsive/RTL/theme/accessibility
polish, complete list/detail/tombstone/action states and navigation integration,
visual device inspection, remaining UX edge states, then final affected and
full-suite regression closure. Do not redesign the enum, transition table,
cancel semantics, repository boundary, concurrency/idempotency, or backend
deletion contract.

That was the Point 9A stop condition. Point 9B is now complete as recorded at
the top of this handoff; Point 10 remains not started.

---

## ZZZZZZZZZZZZZZZZZZZ. Latest session — 2026-09-09 (Point 8 — SaaS tenant feature flags)

Point 8 is complete frontend-first. The real Super Admin route is
`/platform/tenants/:tenantId/features`; tenant navigation, direct routes, Home,
Global Search and Notifications consume the same tenant-wide entitlement.
**Point 9 was not started.**

### A. Point 7 backend-critical note recorded first

The existing Point 7 Flutter mock still implements End Trial → Grace for 14
days, but that number is **provisional only**. `API_CONTRACT.md` and this handoff
now warn a backend developer not to hard-code it without explicit product-owner
approval. The final post-trial policy may be a configurable platform grace
duration (preferred if it fits the subscription design), direct transition to
inactive, or another explicit platform-configured policy. Point 8 changed none
of the Point 7 frontend behavior.

### B. Catalogue and boundaries

`TenantFeatureKey` is the sole closed wire catalogue:
`inventory`, `statistics_reports`, `workshops`, and `announcements`. Each typed
definition owns its Arabic label, description, disabling consequence,
confirmation policy and warning strength. These four are genuine
optional product modules with separable navigation/route families.

Authentication, Home/basic shell, DetachmentGroup/Detachment foundations,
teams, shifts, profile/security/settings, themes/Eye Protection, startup,
forced upgrade and sync infrastructure remain core and unflagged. No screen was
flagged merely to populate the catalogue.

Feature Flag, capability and plan limit remain three independent axes:

- feature: does this `SaasTenant` have the module?;
- capability: may this administrator use the available module/action?;
- limit: how much may the tenant create/use?

The route precedence after a valid tenant session is feature availability
before the existing capability guard, then any applicable usage limit. Thus a
disabled feature wins over a simultaneously missing capability and renders its
own copy; an enabled feature still grants no capability and no capacity.

### C. Typed feature state and fail-closed policy

`TenantFeatureState` carries a typed key, boolean state, per-row version and
`updatedAt`; `TenantFeatureSet` provides typed lookup and keeps unknown raw
keys only for diagnostics. Unknown wire key, missing known key and unsupported
non-boolean future state all resolve to **disabled**. Unknown rows are never
rendered or made into navigation. Backward compatibility is explicit in the
fixtures/store, never a hidden "old app enabled everything" UI fallback.

New tenants receive one explicit row for every known key. The current product
default enables Inventory and Announcements and disables Statistics/Reports
and Workshops. It is deliberately not plan-derived. The canonical eight
tenants contain all-enabled, Inventory-disabled, Workshops-disabled and
several-disabled scenarios; the developer Main/Simple personas both use the
canonical `saas_hilal` tenant with all features enabled.

### D. Repository and canonical store

`TenantFeatureRepository` is separate from `SaasTenantRepository` and
`TenantSubscriptionRepository`. It exposes `getFeatures` and one versioned
`setFeatureEnabled` command. `MockTenantFeatureRepository` reads and updates
the **same `PlatformTenantStore` record** used by Points 5–7, with typed
not-found/invalid/stale/offline/safe failures. Offline writes are refused and
never enter the tenant operational outbox. The controller owns the duplicate
mutation guard and refreshes the feature projection only after success.

Disabling changes only the entitlement row. No Inventory, Workshop,
Announcement, report, usage or other operational record is deleted or reset;
re-enabling reveals the same process-lifetime data subject to capability.

### E. Platform UI

Point 6 tenant detail now has one real «الميزات» action. The feature screen is
a compact Arabic RTL settings list, not a desktop matrix: tenant context,
feature/capability/limit explanation, explicit retention notice and one
accessible name/state/action row per catalogue item. Enable is a direct guarded
write. Consequential disables use the existing Platform confirmation sheet and
name the feature and tenant, navigation/access loss, retained data and restore
behavior.

Designed states cover loading, tenant not found, feature-state unavailable,
offline with honest cached read-only state, offline without state, safe
failure/retry, stale mutation refresh, invalid feature and safe mutation
failure. A switch is not optimistic and a failed write leaves state unchanged.

### F. Tenant consumption and runtime safety

`TenantFeatureAccess.isAvailable` is the one pure availability decision and
uses only the authenticated account's `saasTenantId`. Main and Simple Admin in
the same tenant therefore see identical features while existing capabilities
still make their actions differ. Customer Demo sessions are identified first,
have no real tenant id and never consume `TenantFeatureRepository`; platform
routes are unaffected.

`tenantFeaturesForLocation` is the central typed route-family mapping. Storage
requires Inventory; detachment stats/report/export require
Statistics/Reports; all Workshop routes require Workshops, with Workshop Stats
also requiring Statistics/Reports; Announcement routes require Announcements.
The router re-evaluates on a cheap feature revision, so disabling the currently
open module safely replaces it with `/feature-disabled` without restart. That
Arabic state says the module is unavailable to the team and data was not
deleted, and offers Home only. Re-enable makes the same deep link available
again subject to capability.

`MainShell`, detachment tabs and workshop stats destinations build their usable
destination lists before rendering. Remaining order/indexes stay valid; Home
omits disabled quick actions, announcement cards and inventory alerts.

### G. Search and notification policy

Global Search evaluates feature availability before constructing/loading the
Inventory repository. When Inventory is disabled its category and results do
not exist in the corpus. Workshops, Statistics and Announcements are not
current Global Search sources, so no speculative source was added.

Notifications use the same early-source rule: disabled Inventory contributes
no inventory repository/read/row, and disabled Announcements contribute no
announcement-derived row or destination. Generic local sync/conflict rows
remain because they are user-owned system state and expose no disabled-module
record payload. Notification data is excluded, never deleted.

### H. Backend handoff

`API_CONTRACT.md` defines the four wire keys, feature set/row fields, GET and
versioned PATCH, online/idempotency expectations, typed errors, unknown/missing
fail-closed behavior, explicit new-tenant initialization and data retention.
It prominently requires **server-side** `feature_disabled` enforcement before
the separate capability and plan-limit checks; Flutter hiding is UX only.

`CAPABILITIES.md` records the independent axes and precedence.
`DATA-NEEDS.md` records platform state/cache/write behavior and the affected
Home/Search/Notifications/routes. `SCREEN-ROUTE-MATRIX.md` marks the platform
screen implemented and carries a separate Required Feature overlay. No Point 9
lifecycle endpoint or behavior was added.

### I. Tests and verification

Focused tests cover catalogue uniqueness/parsing/fail-closed behavior, explicit
new-tenant defaults, varied canonical fixtures, repository read/enable/disable,
stale/offline/cached behavior, duplicate guard, all Platform screen states,
confirmation/retention copy, 320 dp × 1.6 text, route/nav runtime invalidation,
feature/capability precedence, shared-tenant Main/Simple behavior, Search and
Notification source exclusion, and data retention across disable/re-enable.

Verification completed with the following final gates:

- the focused Point 8/domain/repository/Platform/router/Search/Notifications
  gate passed **180/180 tests**;
- the two archive regressions affected by tenant identity passed **22/22**;
- the announcement provider and routed-surface regressions passed **28/28**
  after their isolated harnesses were given an explicit enabled entitlement;
- `flutter analyze` completed with **0 issues**;
- the final whole-project `flutter test --reporter compact` run passed
  **1353/1353 tests**;
- `dart format` checked the 42 Point 8-touched Dart files with no remaining
  changes;
- `git diff --check` was clean and `graphify update .` refreshed the mandatory
  project graph.

The tagged render harness produced **14 Point 8 PNGs** inside the larger
Platform render set. They cover all-enabled and partially-disabled tenants,
disable confirmation, cached-offline and failure states, 320 dp × 1.6 text,
900 dp, Dark Cyber, Purple Arena, Light, Eye Protection, reduced motion,
tenant navigation before/after disabling Workshops and the Feature Disabled
screen. Manual inspection found and fixed a real dynamic-bottom-navigation
overflow; the selected destination now uses bounded flex and an ellipsized
label. The final images had no clipping, overlap, bidi or theme defect.

### J. Next exact point

**POINT 9 — TENANT STATUS & DESTRUCTIVE ACTIONS.** It was not started.

---

## ZZZZZZZZZZZZZZZZZZ. Latest session — 2026-09-08 (Point 7 — subscriptions, trials, plans and limits)

Point 7 is complete frontend-first. The two canonical routes are real:
`/platform/tenants/:tenantId/subscription` and
`/platform/tenants/:tenantId/limits`. Point 6 detail links to both. **Point 8
was not started.**

### A. Point 6 audit and the required lifecycle correction

Point 6 had one `SaasTenantStatus { trial, active, grace, suspended }` field and
a `SaasTenantSubscription` containing only three dates. That representation
made commercial state and tenant access mutually exclusive, so an active
tenant could not be in grace and a suspended tenant had no independently
understandable subscription condition.

The smallest safe migration is now in place:

- `SaasTenantStatus { active, suspended }` is tenant access/lifecycle only;
- `SubscriptionStatus { trial, active, grace, inactive }` is commercial only;
- `SaasTenantListStatus` is an explicit Point 6 list projection. Trial,
  active, grace and inactive derive from subscription state; suspended derives
  only from tenant access and takes display precedence;
- `SaasTenant` now serializes `tenantStatus` and owns one enriched
  `SaasSubscription`. There is no second parallel subscription truth;
- Point 5 counts active/trial/grace from subscription state and suspended from
  tenant state. The first three need not plus suspended equal total because
  suspension is orthogonal. The canonical shipped snapshot remains
  `8 / 4 / 2 / 1 / 1` by giving the suspended fixture an explicit inactive
  commercial state.

Unknown wire values are still refused. `inactive` exists only because the
corrected Point 5 data needs a commercial condition for the suspended tenant;
it is not a synonym for suspension and exposes no Point 9 action.

### B. Commercial domain

`domain/saas_subscription_models.dart` defines:

- `SubscriptionStatus` and versioned `SaasSubscription`;
- explicit `NoSaasPlan` / `AssignedSaasPlan`, avoiding ambiguous null plan
  semantics;
- `SaasPlan` and `PlanLimits`;
- typed `PlanLimitKey`: detachment groups, detachments, admins, members,
  workshops and storage bytes — all real MTM concepts;
- `TenantPlanUsage`, `TenantSubscriptionDetails` and `TenantLimitsSnapshot`;
- typed versioned commands for activation, trial extension, plan change and
  limit override/reset.

No unlimited sentinel was introduced: none of the three current plans needs
it, and zero is a real "no additional create" limit rather than a magic value.
Storage is bytes in the domain and wire contract, formatted as MB/GB only at
presentation.

### C. Plans, defaults and overrides

`data/platform_subscription_fixtures.dart` contains exactly three professional
plans: MTM Basic/Core (`mtm_core`), Standard (`mtm_standard`, recommended) and
Advanced (`mtm_advanced`). There are no prices because Point 7 proves plan
selection, not a pricing/payment engine.

Limits use **plan defaults + sparse tenant overrides**. The pure rule is:
`effective = override ?? plan default`. Reset removes only that key's override.
Changing a plan retains explicit tenant overrides and re-evaluates them against
the new defaults; there is no duplicated plan definition on a tenant.

The eight existing canonical tenants now cover paid active, trial ending soon,
grace, suspended + inactive subscription, all three plans, explicit no-plan,
default-only, a tenant override, usage close to a limit, and usage above a
proposed lower limit. No second tenant dataset and no customer Demo record was
added.

### D. Repository and canonical store

Point 7 uses a dedicated `TenantSubscriptionRepository`, rather than turning
`SaasTenantRepository` into a control-plane god object. Identity/list/create
remain in the Point 6 seam; commercial reads and writes are:

- `getSubscription`, `listPlans`, `getLimits`;
- `activate`, `extendTrial`, `endTrial`, `moveToGrace`, `changePlan`;
- `updateLimitOverride` (null means reset to plan default).

This split is clearer for a future backend and lets Point 15 reuse the clean
models through a separate read-only tenant adapter without exposing Super Admin
mutations.

`MockTenantSubscriptionRepository` is injected with the **same
`PlatformTenantStore`** used by the Point 5 overview and Point 6 repository.
`PlatformTenantStore.updateSubscription` replaces the commercial snapshot on
the canonical tenant and adds a compact lifecycle event. Riverpod invalidates
subscription, limits, detail, history, every live list query and overview after
success. No event bus exists.

### E. Transitions and histories

Legal frontend mock transitions:

- `trial | grace | inactive → active`, with a selectable plan;
- `trial → trial` only for a future expiry later than its current expiry;
- End Trial: `trial → grace` for 14 deterministic mock days. It never suspends
  or deletes the tenant;
- `active → grace`, also without changing tenant access;
- plan change in a known commercial state;
- limit override set/reset when a plan exists.

**BACKEND-CRITICAL — provisional Point 7 rule.** The `14` days above is only
the current deterministic Flutter mock selected during frontend work. It is
not an approved product/business requirement, and the future backend developer
must not permanently hard-code it. Before backend finalization, confirm the
post-trial policy with the product owner: preferably a configurable platform
grace duration if that fits the subscription architecture, otherwise a direct
transition to `inactive` or another explicit platform-configured policy. Point
8 does not alter the existing Point 7 frontend behavior.

Every mutation checks `expectedVersion` against the fresh canonical record.
Mismatch returns `stale_subscription`; illegal state returns
`invalid_subscription_transition`. Histories add `trial_extended`,
`plan_changed` and `limit_override_changed` to the focused lifecycle vocabulary.
This is still not Point 11 audit and carries no actor/IP/full before-after body.

### F. Screens and confirmations

The Subscription screen shows tenant context, commercial status, current or
explicit no-plan assignment, relevant dates, state-specific context, only the
currently legal actions, a focused plan summary and navigation to limits.
Plan selection is a stacked mobile sheet comparing the relevant limits rather
than a desktop pricing table.

Consequential confirmations name the change, what remains unchanged and when
it applies: activation, end trial, grace and plan change. Activation copy says
it is an administrative platform state change and explicitly makes no payment
claim.

The Limits screen shows current usage / current effective limit for every key,
progress semantics safe for zero and over-limit values, plan-default/custom
indicators, edit and reset. At ≥600 dp cards use two columns; compact widths
stack. Technical quantities use an LTR island inside Arabic RTL.

If a proposed override is below current usage, the warning says existing data
remains and that future creates are blocked until usage falls below the limit.
It uses warning visuals, no delete icon and no destructive language. The mock
stores the lower value and changes no counts or records.

### G. Write safety and isolation

`SubscriptionActionController` owns a stateful duplicate-submit guard covering
all six mutation families. Repository version revalidation is the stale-state
guard. Offline platform writes return a typed refusal, preserve local
selection/form state and never touch the tenant operational outbox. Typed
outcomes cover success, validation/invalid transition, stale, offline, safe
failure and ignored duplicate.

The whole route subtree remains `super_admin` role-gated. No `Cap` key was
invented or borrowed, and platform fine-grained authorization remains deferred.
Main/Simple Admin routes are refused even with `Cap.all`. Point 7 reads only
platform aggregate usage and never initialises a detachment, team, shift,
inventory, workshop or other tenant-operational repository. Team Code,
provisioning and customer Demo behavior are unchanged.

### H. Backend handoff

`API_CONTRACT.md` now specifies the corrected tenant/subscription
representation, plans, typed limits/usage, effective override rule, all Point 7
reads/writes, legal transitions, typed errors, optimistic concurrency and
`Idempotency-Key` for consequential writes. It explicitly states that
activation is not payment, below-usage limits do not delete data, future tenant
create endpoints enforce limits, and tenant access is separate.

`CAPABILITIES.md`, `DATA-NEEDS.md` and `SCREEN-ROUTE-MATRIX.md` contain the two
routes, repository, states, refresh/offline/cache/sensitivity rules and the
deliberate Super Admin role-only authorization status. No Point 8/9 endpoints
were documented.

### I. Tests and verification

Added `saas_subscription_repository_test.dart` and
`saas_subscription_screens_test.dart`; updated the Point 5/6 consistency,
detail, routing and appearance regressions. Coverage includes parsing and
separation, effective/default/reset logic, zero/over-limit ratios, every legal
and illegal transition, deterministic Clock dates, stale/offline, duplicate
guard, canonical overview counts, valid action visibility, no-plan/failure
states, plan sheet, payment-honest confirmation, below-usage warning and
non-deletion, 320 dp × 1.6 text scale, reduced motion, every product theme and
the ≥600 dp shell.

The tagged render harness now writes **16 Point 7 PNGs** to a caller-selected
scratch directory, covering trial/active/grace, plan and trial sheets, the
below-usage confirmation, overrides/no-plan, offline/failure, 320 dp × 1.6,
900 dp, all themes, eye protection and reduced motion. Manual inspection found
and fixed one real issue: Material `AlertDialog` titles used an undefined
`headlineSmall` fallback and rendered Arabic as tofu in the test renderer;
`AppTypography` now defines that style on IBM Plex Sans Arabic. The final
render set had no clipping, overlap or bidi defect.

Verification: focused repository/screen tests passed; the complete platform
suite passed **208 tests**; `flutter analyze flutter_app` reported **0 issues**;
the final full `flutter test` run passed **1319 tests**; Dart formatting was
applied to the changed files; `graphify update .` refreshed the code graph; and
`git diff --check` was clean at handoff.

### J. Next exact point

**POINT 8 — FEATURE FLAGS.** It was not started: there is no flag model,
repository, route, control or contract in this change.

---

## ZZZZZZZZZZZZZZZZZ. Latest session — 2026-09-08 (Point 6 — SaaS Tenant / Subscriber management)

Point 6 is complete in the frontend. `/platform/tenants` is a real subscriber
list, `/platform/tenants/new` a real create flow, and
`/platform/tenants/:tenantId` a real detail screen. **Point 7 was not started.**

### A. What Point 4/5 left, and what changed

`/platform/tenants` was a reserved section landing: a header, a «قيد الإعداد»
badge and a `PlatformNoteCard` naming four future capabilities. No list, no
search, no create control — deliberately, so the route could stabilise before
the module arrived. Point 6 replaced that body. **The route, the destination,
the branch and the bottom-bar position are unchanged**, which was the whole
reason for shipping the landing early.

`PlatformArea.tenants.readiness` flipped `reserved → available`;
`platform_navigation_test` now asserts Operations is the one area still
reserved.

### B. Domain

`features/platform/domain/saas_tenant_models.dart` — `SaasTenant` (id,
displayName, teamCode, status, createdAt, updatedAt, `MainAdminContact`,
`SaasTenantSubscription`, `SaasTenantUsage`, `SaasTenantCounts`),
`SaasTenantEvent`, `SaasTenantQuery`, `SaasTenantPage`, `SaasTenantDraft`. All
immutable, all JSON round-trip, no `Map` reaches the UI.

Enums: `SaasTenantStatus { trial, active, grace, suspended }` — exactly the four
buckets Point 5 counts, and no more (`deletionPending` is Point 9);
`MainAdminProvisioning { pendingSetup, active }`; `SaasTenantEventType` (six
lifecycle events).

**Unknown wire values are refused, not repaired.** Unlike `teamRoleFromWire`,
which picks a conservative default, an unrecognised `status` makes the *record*
unreadable (`FormatException`). A wrong guess here is a verdict about a
customer: `active` grants standing a lapsed subscriber may not have,
`suspended` says a paying customer is cut off. `API_CONTRACT.md` records the
consequence — adding a status is a contract change.

`domain/team_code.dart`, `domain/saas_tenant_validation.dart` and
`domain/saas_tenant_repository.dart` hold the code rules, the field rules and
the seam. Two feature-owned problem codes only — `tenant_code_conflict` and
`invalid_tenant_code`; everything else reuses `core/problem`'s vocabulary.

### C. Repository

```dart
abstract class SaasTenantRepository {
  Future<Result<SaasTenantPage>> list(SaasTenantQuery query);
  Future<Result<SaasTenant>> byId(String tenantId);
  Future<Result<SaasTenant>> create(SaasTenantDraft draft);
  Future<Result<List<SaasTenantEvent>>> statusHistory(String tenantId);
}
```

Four operations, and deliberately no `suspend`, `activate`, `extendTrial`,
`setPlan`, `setLimits`, `delete` or `updateTeamCode` — a method declared before
its screen exists is a method something starts calling.

**Search and status filtering are repository parameters, not client-side
selectors.** A subscriber list is the one collection in this product with no
ceiling, so the read a backend will have to filter and page is written that way
now. The page response is `{items, total, nextCursor}` with an **opaque**
cursor: no Mongo id, no SQL offset, no database token, and the client neither
constructs nor parses one. `total` is the match count before paging.

### D. Canonical dataset — the Point 5 consistency fix

`data/platform_tenant_fixtures.dart` holds eight subscribers — 4 active, 2
trial, 1 grace, 1 suspended — positioned entirely from the injected `Clock`,
with varied creation dates, contacts, usage and organisation totals, and no
medical, patient or credential-shaped content.

Point 5's `MockPlatformOverviewRepository` stated `8 / 4 / 2 / 1 / 1` as four
literal integers. Those literals are gone. `data/platform_tenant_store.dart`
holds the records, both mocks are handed the **same** store by
`platformTenantStoreProvider`, and `tenantSummary()` counts them. So:

- the overview and the list cannot describe two different customer bases;
- registering a subscriber changes both, with no restart and **no event bus** —
  the create controller invalidates `saasTenantListProvider` and
  `platformOverviewProvider`, which is the app's existing mechanism;
- `platform_tenant_consistency_test.dart` pins both halves, including that the
  shipped numbers are still the ones Point 5 published.

The store is process memory and says so. Customer Demos are counted separately
by the overview and appear in no tenant record.

### E. Team Code

Canonical form `MTM-XXXX-XXXX` over `23456789ABCDEFGHJKMNPQRSTVWXYZ` — the
ambiguous characters (`I O L U 0 1`) are excluded because the code is
transcribed and dictated by humans. It is formatted to look like an order
number rather than a password, because it **is not a credential**: it
identifies, the future first-time link also requires email-ownership proof, and
a password-shaped string would teach an operator to refuse to read it aloud.

**Both §7 options, taken together and honestly.** The create form pre-fills a
deterministic suggestion (`teamCodeFromSeed`, a testable seam that claims no
entropy and no uniqueness) and lets the Super Admin accept it, regenerate, or
type their own. The typed value is normalized (`mtm 4k7p qx92` →
`MTM-4K7P-QX92`), format-validated, and checked for uniqueness **by the
repository**, which is the authority. It is immutable after creation and the
tenant application offers no edit. `API_CONTRACT.md` records that real
generation and concurrency-safe uniqueness are the backend's, and that a tenant
session must never be able to write the field.

### F. Initial Main Admin provisioning — no temporary password, and why

**Point 6 generates, displays, transmits and stores no credential of any kind.**
§36 permits a one-time temporary password under strict conditions; it was
refused because this client has no honest way to produce or deliver one. A
password minted in Dart is not a credential any backend agreed to, and in the
real flow — email-ownership OTP, Team Code, forced password change on first
sign-in — the client never receives a stored password at any point.

What is modelled instead is the **state**: the Main Admin exists, is identified
by name and email, and is `pending_setup`. The create screen says so on screen
rather than only in a comment, so the absence of a credential reads as a
decision and not as an unfinished form. Security correctness over visual
completeness; the later authentication Point inherits nothing it must undo.

### G. Screens

**List** — subtitle, search field (250 ms debounce; the query goes to the
repository), five status chips in a horizontal scroll, a match count with a
clear-filters button, three-line rows (name + status chip / Main Admin /
subscription date + Team Code), and one extended FAB. `PlatformPage` gained an
optional `floatingActionButton` slot for it. States: skeleton, populated,
platform-empty, no-results (distinct, with a way out), offline with the copy,
offline without, failure/retry. When a page is cut it says so in a sentence
rather than offering a "load more" that the mock could never exercise.

**Create** — four fields, per-field Arabic errors, a provisioning note, one
button. No plan, price, seat, limit, flag or initial-status control. Offline is
refused and **not queued** (there is no endpoint a queued write could reach).
The duplicate-submit guard is in the controller; the disabled button only shows
it.

**Detail (§20, option A)** — one scrolling page with real sections: identity +
Team Code (selectable, copyable) + dates, Main Admin, subscription, usage,
organisation counts, lifecycle history. **Not tabs**: two of the five tabs the
original plan sketched have nothing in them until Points 7–9, and a tab bar
whose second half opens empty rooms is worse than a page showing what exists.
A later Point can add a nested route under this location without moving
anything. Read-only throughout — the only control on the page is Copy, and
there is no disabled suspend/activate/delete standing in for a future one.

Organisation counts are **platform aggregates delivered with the record**, and
the card says so on screen.

### H. Shared changes

- `core/text/search_key.dart` — the roster's Arabic normalization moved down to
  `core/` the first time a second surface needed it; `memberSearchKey` is now a
  one-line delegate, so behaviour is unchanged and there is one rule, not two.
- `core/format/app_date.dart` — `dayMonthYear`, for records that can be years
  old.
- `PlatformPage.floatingActionButton`.

### I. Access and isolation

Unchanged surface gate: only a valid `super_admin` owns `/platform*`, and
`saas_tenant_list_test` walks a `main_admin` carrying `Cap.all` at all three new
locations and asserts `/home` and `MainShell` every time. `TenantRepositoryWatch`
proves no `DetachmentRepository`, `DetachmentGroupRepository`,
`TeamRepository`, `ShiftRepository`, `InventoryRepository`,
`WorkshopRepository`, `HomeRepository`, `AnnouncementRepository` or
`NotificationRepository` is constructed while the list, the create form or the
detail renders — including through a successful registration. No `Cap` key was
invented or borrowed.

### J. Documentation

- `API_CONTRACT.md` — a full `SaasTenant` section: the representation, status
  semantics and the refuse-don't-repair rule, Team Code semantics and the
  backend's uniqueness/immutability obligations, the four operations with
  pagination and ordering rules, typed errors, and an explicit statement that
  the create response must carry no credential.
- `DATA-NEEDS.md` — three new rows (list / create / detail) with fields,
  actions, refresh, offline, sensitivity and backend requirements.
- `SCREEN-ROUTE-MATRIX.md` — the three routes marked implemented with their
  repository, states and tests; the Points 7–9 mutation family left PLANNED.
- `CAPABILITIES.md` — the two new locations added to the route table, with a
  paragraph recording that Point 6 introduced no capability concept.

### K. Verification

- Focused: `flutter test test/features/platform/` — **173 passed**.
- Whole project: `flutter analyze` **clean (0 issues)**; one full
  `flutter test` run; `git diff --check` clean; `dart format` over every
  changed Dart file; `graphify update .`.
- Visual inspection through the tagged render harness, extended with fifteen
  Point 6 shots: list, search, no-results, empty, failure, offline, create,
  detail, pending-admin detail, Purple Arena, Light, Light + eye-protect,
  320 dp × 1.6, expanded 900 dp, reduced motion. Two real defects were found
  and fixed there: the organisation-counts card stayed one column on a 390 dp
  phone (the breakpoint measured the card, not the window, and was 40 dp too
  high), and the Latin `MTM-XXXX-XXXX` example inside Arabic help text was
  reordered and split across lines — it is now wrapped in an LTR isolate with
  non-breaking hyphens.

### L. Genuine remaining gaps

1. **No durable anything.** The store is process memory; a relaunch reseeds
   from the fixtures. Same limitation `MockSettingsRepository` has.
2. **Mock uniqueness is not a guarantee.** The client's duplicate-code check
   races by construction. The backend needs a unique index.
3. **Paging has no UI.** The contract carries a cursor and the screen reads the
   first page, telling the operator when results were cut. A "load more" arrives
   with the Point that needs it.
4. **Platform authorization is still undesigned.** Role is the only gate, for
   reads and for the one write alike.
5. **`context.push` inside a `StatefulShellRoute` branch** does not move
   `currentConfiguration.uri`; the branch's matched location stays the root.
   That is go_router's behaviour and the same as the existing `/platform/more/*`
   rows, so the tests assert on the rendered page. Worth knowing if a future
   deep-link feature needs the URL to reflect a pushed platform page.

### M. Next exact point

**POINT 7 — SUBSCRIPTIONS, TRIALS & PLAN LIMITS.** Nothing of it was begun: no
activate, no grace mutation, no trial extension or end, no plan model, no plan
editing, no limits, no feature flags, no suspension/reactivation, no deletion.
The `SaasTenant` model carries no plan or limit field for a screen to start
rendering early.

---

## ZZZZZZZZZZZZZZZZ. Earlier session — 2026-09-08 (two follow-ups + Point 5 — Super Admin Platform Overview)

Point 5 is complete in the frontend. `/platform` is now the first real SaaS
control-plane read and remains an overview only. **Point 6 was not started.**

### A. Follow-ups closed before Point 5

1. **Archive determinism.** `MockShiftRepository` now receives and uses the
   project `Clock` for seed-day selection and all remaining generated times;
   `shiftRepositoryProvider` passes `clockProvider`. The archive read-only test
   pins Saturday 2026-09-05, a seeded shift day. No archive or shift product
   behaviour changed.
2. **`SessionAccess.sessionExpiresAt`.** The existing expiry source remains the
   repository's `401 authentication_expired`. The optional server-issued RFC
   3339 timestamp is now parsed only with an explicit offset, normalized to
   UTC, and compared with the injected `Clock` during startup restoration.
   Equality is expired (`now >= expiry`). Absent/`null` keeps the 401-only
   behaviour; malformed, non-string, or offset-less present values fail closed
   through `/session-unsupported`. There is no invented session lifetime,
   timer, or competing expiry source.

### B. Point 5 domain and repository

`features/platform/domain/platform_overview_models.dart` defines one immutable
`PlatformOverviewSnapshot` with internally consistent tenant/subscription and
Simple/Full Demo summaries, typed health, attention, activity, optional
backend-neutral usage, and `generatedAt`. Enums cover the small Point 5 wire
vocabulary only: health (`healthy/degraded/unavailable/unknown`), attention
severity/category, activity type, overview destination, Demo type, and the four
subscription summary states.

`PlatformOverviewRepository.loadOverview()` is the only screen-facing read.
`platformOverviewProvider` consumes it; no collection of unrelated endpoint
providers was introduced. The future backend contract is one aggregate
`GET /platform/overview`.

The deterministic mock uses only injected `Clock` and provides:

- 8 SaaS tenants: 4 active subscriptions, 2 trials, 1 grace, 1 suspended;
- 4 active customer Demos: 2 Simple, 2 Full, with 2 expiring soon;
- healthy identity/files signals and one degraded background-jobs signal;
- three actionable items (security, grace subscription, degraded jobs);
- five newest-first summary events, including a new customer Demo;
- 18 GiB of a truthful mock 100 GiB storage allowance.

It contains no medical/tenant-operational records. Its cached-offline fixture
is explicitly process-memory mock semantics, not a durable cache claim.

### C. `/platform` information architecture and behaviour

The old signed-in landing note was replaced with a decision-first Arabic RTL
overview:

1. compact page context and truthful generated-at freshness;
2. conditional **Needs attention** group (omitted when empty);
3. five core metrics: SaaS tenants, active subscriptions, trials,
   grace/suspended, active customer Demos with Simple/Full/expiring detail;
4. coarse platform health signals;
5. concise storage usage when supplied;
6. five recent high-level events, newest first.

Only typed `PlatformOverviewTarget.tenants` and `.operations` can navigate, and
they map to the already registered `/platform/tenants` and
`/platform/operations` landings. Activity and unsupported future-detail facts
are non-interactive. No dead or future route was added.

The screen renders structured loading, loaded, truthful minimal, offline with
mock cached data, offline without cache, stale-success, and safe failure/retry
states. It supports pull-to-refresh and the header refresh action; there is no
aggressive polling and no “Live” claim.

At 320 dp × 1.6 text scale metrics become one column and rows wrap without
overflow. At expanded width the existing rail remains at the RTL start and the
720 dp content column reflows health/activity into two useful columns. Dark
Cyber, Purple Arena, Light, Eye Protection and reduced-motion/lowest-cost
render checks were inspected. That inspection also found and fixed a latent
`TabSwitchTransition` reduced-motion disposal bug by lazily creating its
animation controller only when animation is actually used.

### D. Access and isolation

The Point 4 surface gate is unchanged: only a valid `super_admin` session owns
`/platform*`; tenant roles are redirected to their own product surface.
`CAPABILITIES.md` required no edit because no route or authorization semantic
changed and no `Cap` key was invented.

The overview imports and consumes only `PlatformOverviewRepository`. Focused
tests prove that no `DetachmentRepository`, `DetachmentGroupRepository`,
`TeamRepository`, `ShiftRepository`, `InventoryRepository`, or
`WorkshopRepository` is constructed while it renders or navigates.

### E. Backend handoff

- `API_CONTRACT.md`: specifies the minimal future aggregate response, typed
  values, count invariants, freshness, errors, cache limits and the future
  `demo_started` platform-notification obligation; no Point 6 CRUD endpoint.
- `DATA-NEEDS.md`: records fields, refresh, process-memory mock cache, all UI
  states, sensitivity and the future aggregate requirement.
- `SCREEN-ROUTE-MATRIX.md`: marks `/platform` as a real overview and names its
  repository/states/tests.
- `CAPABILITIES.md`: intentionally unchanged.

### F. Focused verification and files

Focused tests: **146 passed** across archive determinism, session access,
startup classification, overview model/repository/states, platform isolation,
navigation, responsive layout, appearances and reduced motion. The tagged
render inspection also passed and produced only `/tmp` PNGs.

Files added for Point 5:

- `flutter_app/lib/features/platform/domain/platform_overview_models.dart`
- `flutter_app/lib/features/platform/domain/platform_overview_repository.dart`
- `flutter_app/lib/features/platform/data/mock_platform_overview_repository.dart`
- `flutter_app/lib/features/platform/data/platform_overview_providers.dart`
- `flutter_app/test/features/platform/platform_overview_repository_test.dart`
- `flutter_app/test/features/platform/platform_overview_states_test.dart`

Directly updated: the overview/page/shell widgets, platform render harness,
Arabic strings, startup classifier/provider and tests, `SessionAccess` and its
tests, shift mock/provider and archive test, transition primitive, plus the
three source-of-truth documents above and this handoff.

Whole-project gate after implementation: `flutter analyze` **clean (0
issues)**; the single full `flutter test --reporter compact` run **1194/1194
passed**; `git diff --check` clean. `dart format` was run over every directly
changed Dart file and mandatory `graphify update .` completed.

### G. Next exact point

**POINT 6 — SAAS TENANT / SUBSCRIBER MANAGEMENT.** *(Done — see
§ZZZZZZZZZZZZZZZZZ above.)* It may replace the existing Tenants section landing
with its list/search/create/detail work. None of that model, repository, UI,
route family or provisioning behaviour was begun here.

---

## ZZZZZZZZZZZZZZZ. Latest session — 2026-09-08 (Point 3 follow-ups + Point 4 — Super Admin platform shell)

`flutter analyze`: **clean (0 issues)** over `lib/` and `test/`.
`flutter test`: **1170 pass / 1 fail** (1171 total, 97 added this session —
1073 passed before it). The one failure is pre-existing and calendar-driven —
see §F, below. `dart format` run over
`lib/` and `test/`. `git diff --check`: clean. No new dependency.
**Point 5 was not started.**

---

### A. Point 3 follow-up — unknown `SessionAccess` lifecycle values

#### What it used to do

`AccountStatus.parse`, `TenantStatus.parse` and `DemoMode.parse` each looped
their known wire strings and **returned the normal value for anything else** —
and `null` (absent) took the same path. One rule for two different facts, and
the second half of it was a fail-open on a security gate:

- **absent** — the server has not implemented the field. Reading it as normal
  is correct, and `API_CONTRACT.md` promises exactly that.
- **present and unrecognised** — the server *is* asserting a lifecycle state,
  and an installed build has no way to know whether it is more permissive or
  more restrictive than the ones it knows. `accountStatus: "locked"` read as
  `active` hands a locked account the whole application; `demoMode:
  "read_only"` read as `none` hands a demo session the real product.

`mfaRequired` had a second, smaller problem: `j['mfaRequired'] as bool?` throws
on a non-boolean rather than failing closed.

#### The architecture chosen

**Type the distinction; fail closed only on the second case.**

- Each enum's `parse(String?)` became `tryParse(String)`, which answers `null`
  for a value it does not recognise. There is no defaulting left inside the
  enums at all.
- `SessionAccess.fromJson` is now the one place the three outcomes are decided:
  absent → the documented default; known → that value; anything else, including
  a value of the wrong JSON type → recorded in a new
  `Map<AccessLifecycleField, String> unsupported`, keyed by a typed field enum
  and holding the raw value as received.
- `SessionAccess.hasUnsupportedState` is what the classifier reads. A new
  `StartupDestination.unsupportedAccessState` → `/session-unsupported` →
  `AccessUnsupportedPage` (the existing `StatusScreen`, warning tone, sign-out
  + support).
- Priority: immediately **below** the authentication answers (expired, invalid,
  signed out) and **above** every authorization question including MFA. Lower
  would mean deciding a suspension or a surface out of an envelope already
  known to be unreadable; higher would tell someone whose session merely
  expired that their app is out of date. The forced-upgrade gate still outranks
  everything.
- `toJson` writes the **raw refused value back**, never the default it fell
  back to, so serialising a session cannot launder a state the client refused
  into one it accepts.

#### Why this is the best option

The three alternatives, and why each is worse:

1. **Keep unknown → normal.** Fail-open on four gating fields. Rejected.
2. **Refuse on any unknown *property name* too.** Makes the envelope
   unextendable: adding `lastPasswordChangeAt` would lock out every installed
   build. The line drawn instead — an unknown *value* in a property the client
   already gates on — is the smallest one that closes the hole.
3. **A sentinel enum value (`AccountStatus.unsupported`).** Would work, but it
   puts a non-wire value inside a wire enum, breaks round-tripping, and forces
   every `switch` in the app to handle a case that is never a real status. The
   map keeps the enums honest and puts the fact where it belongs — on the
   envelope, not on the status.

**Backend consequence, and it is the one thing the backend must take away:** a
new **restrictive** lifecycle state has to arrive as a new *value* of one of the
four existing properties, never only as a new property. An installed build
cannot see a property it has never heard of, so a restriction expressed that way
would be enforced by no client at all. Written into `API_CONTRACT.md`.

#### Tests proving it

`test/features/auth/session_access_unknown_test.dart` (27 cases) and a new
group in `test/core/startup/startup_routing_test.dart`:

- absent, explicitly `null`, and an unknown *property name* → normal, surface
  opens;
- every known value, normal and restrictive, still resolves where it did;
- one case per `AccessLifecycleField` — a test asserts the case map covers the
  whole enum, so a field added to the envelope fails here until someone decides
  whether an unknown value in it is a refusal;
- an unknown value in each field refuses **both** surfaces (`/home` and
  `/platform`), including through the router with deep links into the platform
  subtree;
- wrong JSON type → unsupported, not a crash;
- an unsupported state does not outrank an expiry or the upgrade gate;
- `toJson` round-trips the refused value; equality and hashing account for it.

Also inspectable by hand: the debug session-state inspector
(`/dev/session-states`) gained three rows — unknown account status, unknown
tenant status, unknown demo mode.

---

### B. Point 3 follow-up — `SCREEN-ROUTE-MATRIX.md`

Created, populated from `app_router.dart` rather than from memory. 71 rows in
five sections — Common/auth (11), startup and session states (11), Platform
(16, of which 6 are marked PLANNED), Tenant (32), plus a short list of gaps
found while compiling it. Columns as specified in the brief.

It is written to be **updated incrementally**: one row per route, no prose
duplicated from the other documents, and an explicit note that a Point which
adds a route adds a row in the same change.

Gaps the inventory surfaced (recorded, not fixed — each belongs to a later
Point): no platform repository exists at all; platform notifications have no
route and must not reuse the tenant Notifications Center; tenant notification
preferences are tenant-shaped so there is no platform equivalent to expose;
`/more/performance` is the one route with no screen of its own (a redirect);
first-time setup names a state but has no flow.

---

### C. Point 4 — the Super Admin platform shell

#### What `/platform` used to be

`PlatformHoldingPage` — one root route, no navigation, one action (sign out),
an account card, and two sentences saying the surface did not exist yet. It has
been **deleted**, and its route is now a shell.

#### The architecture

```
lib/features/platform/
  domain/platform_area.dart               pure Dart: the IA, routes, ordering, readiness
  presentation/platform_destinations.dart the icon/label registry
  presentation/platform_shell.dart        the adaptive shell
  presentation/platform_overview_page.dart
  presentation/platform_tenants_page.dart
  presentation/platform_operations_page.dart
  presentation/platform_more_page.dart
  presentation/widgets/platform_navigation.dart  bar + rail
  presentation/widgets/platform_page.dart        app bar, page, section header, note card
```

**Not `MainShell`, and not a clone of it.** `MainShell` chooses which branches
to *offer* from the capability grant, swipes between them, and floats the
tenant app's glass pill over the body. None of that transfers: the platform's
four areas are fixed, platform authorization is not the tenant capability model
at all, and swiping between control-plane areas is a gesture from the other
product. What **is** shared is the design system underneath — tokens, motion,
`StatusChip`, the settings row primitives — which is the sharing the brief asks
for and the sharing that costs nothing.

#### The information architecture, and the exposure decision

Four top-level areas: **المنصة** (`/platform`), **الفرق** (`/platform/tenants`),
**العمليات** (`/platform/operations`), **المزيد** (`/platform/more`).

«الفرق» rather than «العملاء»: MTM's own word for a paying customer is a team,
and «العملاء» would import a commercial word the product does not otherwise
speak. There is no collision with the tenant app's «الفريق» — a Super Admin
never sees the tenant application.

**All four are exposed now** (option A of the brief's §4), with the readiness
typed rather than commented: `PlatformAreaReadiness { available, reserved }`.
Overview and More are `available`; Tenants and Operations are `reserved` and
render a designed section state — an honest heading, a «قيد الإعداد» chip, one
sentence saying the module is not built in this build, and a plain
**non-interactive** list of what it will hold. No list, no search field, no
create button, no count.

Why exposed rather than added later:

- **Route stability.** Point 6 replaces one page body. Nothing moves, no
  destination appears under an operator who had already learned the layout, and
  there is no navigation reshuffle in the release that matters most.
- **The IA is the deliverable of this Point.** A shell whose shape only exists
  in a comment is not inspectable and not testable.
- **The cost is bounded and honest.** A reserved area is reachable, says
  truthfully what it will manage, and offers nothing that does nothing — which
  is the line §24/§25 draw, and `platform_more_test` holds it.

#### Compact and expanded navigation, and the breakpoint

One registry (`platformDestinations`), two controls, both reading it.

- **Compact (< 600 dp): `PlatformNavigationBar`**, docked in
  `Scaffold.bottomNavigationBar` — grounded, not floating, because a control
  plane's operator should never wonder what is underneath the bar. All four
  labels are visible at once, unlike the tenant pill which shows only the
  selected one: the platform's areas are unfamiliar nouns, not the four rooms
  someone works in daily.
- **Expanded (≥ 600 dp): `PlatformNavigationRail`**, 96 dp, first child of a
  `Row` so RTL puts it on the **right** with its hairline on the inner edge.
- **Neither is Material's `NavigationBar`/`NavigationRail`.** Those pin their
  own height and clip labels past roughly a 1.3 text scale, which §35 forbids
  solving with a smaller font. These are laid out from their content: a label
  that needs two lines gets a taller bar.
- **Breakpoint: 600 logical pixels of the shell's own available width**, read
  through `LayoutBuilder` — never a device check. The repository had no
  existing breakpoint to reuse (nothing in `core/` branched on width before
  this), so this is the app's first one and it is declared on
  `PlatformShell.expandedBreakpoint` for the next surface to reuse.
- Selection is carried three ways — outlined→filled glyph, tinted plate, label
  weight and ink — so it survives a monochrome rendering, and it is announced
  (`Semantics(button:, selected:, label:)` with the subtree excluded, the same
  treatment `ChoicePill` already uses).

#### Route tree and branch state

`StatefulShellRoute.indexedStack` with four branches and four dedicated
navigator keys, registered beside the tenant shell (the two never coexist).

```
/platform                      overview branch
/platform/tenants              tenants branch
/platform/operations           operations branch
/platform/more                 more branch
  /platform/more/profile
  /platform/more/security
  /platform/more/themes
  /platform/more/eye-protect
  /platform/more/about
```

Indexed branches, not a single navigator: the §13 scenario (Tenants → detail →
Operations → back to Tenants) needs per-branch stacks, and go_router's
`goBranch(initialLocation: branch == current)` gives "tap the current row to go
home, tap another to return where you left it" without a line of state
management. The nested More pages stay **inside** their branch, so the platform
navigation remains visible while the operator drills into their own settings —
the same rule the tenant `/more` sub-pages follow.

`PlatformArea.branchIndex` is the branch index, the bar's selected row and the
enum's declaration order, all one number.

#### Route security — the one substantive router change

`/platform` stopped being a location and became a **subtree**, so the router's
two questions had to learn that. Both now go through one function:

```dart
bool StartupDestination.claims(String here)   // own location, plus the subtree when ownsSubtree
```

`platformSurface` is the only destination with `ownsSubtree: true`. The redirect
asks `claims` to decide "may this session stay where it asked", and
`_isStartupOnly` asks the same function to decide "is this a location only the
classifier hands out" — so a guard written as `here == '/platform'` (which would
refuse `/platform/tenants` to the Super Admin *and* permit it to everyone else)
cannot be written twice and disagree with itself.

One narrow addition: a signed-in **platform** session may open `/mfa-setup`,
`/forgot`, `/otp`, `/new-password` — the auth errands its own shared Security
screen starts. `/login` is deliberately excluded. Without this the platform
surface would have shown two rows and bounced off both.

#### Platform app bar

One `PlatformAppBar`: the destination's short title in `titleMedium` (calmer
than the app-bar default, and the longest platform title then still fits beside
the action on a 320 dp phone at 1.6× without abbreviation), plus one action —
the account, going to `/platform/more/profile`. **No search field and no alerts
bell**: neither has a destination on this surface in this build, and a header
icon that opens nothing is exactly what §22 forbids. Both slots are one line of
code when a Point gives them somewhere to go.

#### Platform More — an allowlist

Five rows: **حسابي**, **الثيمات والأداء**, **حماية العين**, **الأمان**, **حول
التطبيق**, then sign-out, then one sentence saying what this screen is not.

Each was inspected before exposure. All five read only the session, the app's
own preferences, or a compile-time constant. **Explicitly excluded:** the
organisation record (`/more/org`), the sync centre and Needs Review (a tenant
outbox), tenant notification preferences (their four toggles are shifts, stock,
workshops and join requests), the tenant plan, detachment settings and tenant
admin management.

Rendering the tenant `SettingsPage` with rows hidden was rejected for a reason
beyond tidiness: that screen reads the sync outbox and the capability grant to
compose its row summaries, so it would initialise tenant machinery for the one
session that must never touch any.

#### Shared screens reused, and the two adaptations they needed

`ProfilePage`, `SecurityPage`, `ThemesAndPerformancePage`, `EyeProtectPage`,
`AboutPage` are registered at platform routes — the same widgets, not copies.
Two things had to change, and both are on the shared primitive rather than in a
fork:

1. **`ProfilePage.securityRoute`** (default `/more/security`). Its Security row
   used to push a tenant location the platform session is bounced off — a dead
   control. The platform route passes its own.
2. **`FloatingNavPadding` reads a shell-provided inset.** It hard-coded 96 dp
   for the tenant's floating pill; the platform bar is docked, so `Scaffold`
   already makes the room and the same 96 was a dead band at the bottom of
   every shared screen. The widget moved to
   `core/widgets/shell_insets.dart` with a `ShellBottomInset` lookup
   (default: the tenant's 96), and `main_shell.dart` **re-exports it**, so all
   twenty screens that import it from there are untouched.

#### Super Admin account presentation

`ProfilePage` in its platform form omits the organisation row (a `super_admin`
has no `saasTenantId` by invariant, and its `orgName` names the platform rather
than a customer) and the access-level, scope and two grant rows — all four are
readings of a *tenant* grant this account does not hold. Reporting them as
"not granted" would have described the platform owner as the narrowest
administrator in the system, which is the claim the product model denies. In
their place: the role row, read verbatim off `AuthUser.role`, and one sentence
saying platform authority is managed outside the tenant capability model. The
in-tenant `AdminExperience` chip is not shown for this account (it already was
not — Point 2 handled that; the test now pins it).

#### Data isolation

`PlatformShell` and every page under it import **no tenant repository**, so the
boundary holds by construction rather than by a hidden widget. It is also
asserted: `TenantRepositoryWatch` overrides the nine tenant repository
providers with recorders that throw on construction, and three tests walk the
whole platform surface — every destination, every page inside More, and a set
of refused tenant deep links — asserting nothing was built.

---

### D. Screens created, and what was looked at

**Created:** the platform shell, the compact bar, the expanded rail, the
platform app bar / page / section-header / note-card primitives, and four
destination pages (overview, tenants, operations, more), plus the
`/session-unsupported` state screen.

**Rendered and inspected** (real IBM Plex Sans Arabic, RTL, at 2× — see
`test/features/platform/platform_render.dart`, a tagged non-test that writes
PNGs to a scratch directory and is excluded from the ordinary run): every
destination in Dark Cyber; the account screen; Purple Arena; Light; Light with
Eye Protection; 320 dp at a 1.6 text scale; 900 dp with the rail.

**Two genuine visual defects were found this way and fixed:**

1. **The rail did not fill the shell's height.** `Row` centres its children by
   default, so a rail sized from four items floated as a short panel against
   the edge instead of reading as the side of the window. Fixed with
   `crossAxisAlignment: CrossAxisAlignment.stretch`.
2. **The account screen's value rows rendered in the platform font, not the
   app's.** `_InfoRow` set `DefaultTextStyle` with a bare `TextStyle`, which
   *replaces* the ambient style and therefore drops the theme's font family —
   so the email address and the account type were the only text on that screen
   not in IBM Plex. Changed to `DefaultTextStyle.merge`. Pre-existing, and it
   affects the tenant account screen equally.

**A third, in a shared primitive**, was surfaced by the new tests rather than by
eye: `SettingsSection` wrapped `ListTile`s in a decorated `Container`, so every
settings row's ink splash was painted behind the card's own background and
never seen — the "ListTile background color or ink splashes may be invisible"
complaint several router tests used to tolerate **by name**. It is now a
`Material` with the same shape, hairline and clipping, so a tap on a settings
row has visible feedback on both surfaces and the suppression is inert rather
than load-bearing.

---

### E. Tests added or updated

| File | What it holds |
| --- | --- |
| `test/features/platform/platform_harness.dart` | new — one way in, through the real router and classifier; `TenantRepositoryWatch` |
| `test/features/platform/platform_routing_test.dart` | new, 15 — the surface boundary over the whole subtree, deep links, branch state, back behaviour, no redirect loop, the domain/route agreement |
| `test/features/platform/platform_navigation_test.dart` | new, 19 — the registry is the one source; compact and expanded selection; the breakpoint from both sides; resize preserves the destination; announced selection; 320 dp × 1.6 on every destination; reduced motion |
| `test/features/platform/platform_more_test.dart` | new, 12 — no tenant repository is built anywhere on the surface; the More allowlist; every row opens what it names; the Super Admin account screen's truthfulness, and the tenant one's, unchanged |
| `test/features/platform/platform_appearance_test.dart` | new, 20 — all six appearances (3 themes × eye-protect) over all nine platform screens, at 390 dp, at 320 dp × 1.6, and at 900 dp, plus reduced motion. No `FlutterError` suppression anywhere in the file |
| `test/features/platform/platform_render.dart` | new, tagged `render` — the screenshot writer. Not part of the suite |
| `test/features/auth/session_access_unknown_test.dart` | new, 27 — the absent/known/unsupported table |
| `test/core/startup/startup_routing_test.dart` | +4 — the unsupported state at the router, for both surfaces |
| `test/core/startup/startup_classifier_test.dart` | updated — the new destination is in the "every status screen has a page" set |
| `test/features/auth/super_admin_routing_test.dart`, `test/features/auth/demo_login_test.dart` | updated — they named the deleted holding page; the expectations themselves survived unchanged |

---

### F. The one failing test — pre-existing, and not this work's

`test/features/detachment/archive_read_only_test.dart` →
«the schedule keeps every control it had» fails with *two* widgets matching
«أضف شفتا».

It is **calendar-driven and predates this session.** `MockShiftRepository`
seeds its plan relative to `DateTime.now()`, and `d_dam_central` is seeded for
Saturday, Sunday, Monday, Wednesday and Thursday only. Today (2026-09-08) is a
Tuesday, so the schedule opens on an empty day, the empty state renders **its**
«أضف شفتا» action beside the toolbar's, and `findsOneWidget` sees two. The test
passes on five weekdays and fails on Tuesday and Friday.

Nothing in this session touches the shift feature, the detachment feature or
that screen. It is left alone deliberately (`CLAUDE.md`: existing errors are
addressed when the work is requested, not because they are present). The fix,
when it is asked for, is either to pin a clock in the test or to scope the
finder to the toolbar.

---

### G. Documentation updated

- **`SCREEN-ROUTE-MATRIX.md`** — created (see §B).
- **`API_CONTRACT.md`** — the `SessionAccess` unknown-value contract rewritten
  as a four-row table (absent / known / unknown value / unknown property) with
  the one rule the backend must follow; and a new **platform surface** section:
  role selects the surface, platform session requirements, the "no tenant
  operational endpoint from the platform surface" boundary, cross-tenant
  scoping being an open design question, the planned route/resource families
  marked as planned, and platform authorization still undesigned.
- **`CAPABILITIES.md`** — the route→role matrix extended to the whole
  `/platform` subtree; the two new rules (signed-in platform sessions may
  finish an auth errand; Platform More is an allowlist, never the tenant hub
  with rows hidden); and a section on why `Cap.all` is not a substitute for
  platform authority.
- **`DATA-NEEDS.md`** — new §2.6 for the platform surface (ten rows: shell,
  overview, tenants, operations, More and the five account screens) with the
  data displayed, actions, refresh triggers, offline expectations, sensitive
  fields and the future backend data each will need; plus the new
  `/session-unsupported` row and an updated platform row in §2.1b.

---

### H. Genuinely remaining gaps

1. **No platform repository, and therefore no platform loading/offline/failure
   state.** Deliberate for this Point; Points 5–6 introduce the first ones.
2. **Platform authorization is undesigned.** The shell asks `Capabilities`
   nothing, which is correct today and cannot stay true once Operations has
   destructive actions.
3. **Platform notifications have no home.** The tenant Notifications Center is
   deliberately outside the platform shell; a platform inbox is a later Point.
4. **The development session-state inspector is tenant-reachable only.** A
   Super Admin cannot open `/dev/session-states` (it is a root route the
   platform surface is turned around at). The states it forces are surface-
   agnostic and inspectable from a tenant persona, so this was left alone
   rather than punching a hole in the boundary for a debug tool.
5. **`sessionExpiresAt`** is specified in the contract and still not parsed.
   Unchanged by this session; it is advisory and gates nothing.

---

### I. Exact next Point

**POINT 5 — SUPER ADMIN PLATFORM OVERVIEW.**

It replaces the body of `platform_overview_page.dart` and nothing else: the
route, the destination, the shell, the header and the navigation all stay where
they are. What it needs from the backend is the first platform read — the
resource family named but not specified in `API_CONTRACT.md` §"The platform
surface". It should also add the platform surface's first
loading/empty/offline/failure states, which do not exist today because there is
nothing to load.

---

## ZZZZZZZZZZZZZZ. Latest session — 2026-09-07 (Point 3 — startup, session restoration, role/surface routing)

`flutter analyze`: clean (0 issues). `flutter test`: **1074 pass / 0 fail**
(981 before, +93 new). `dart format` run over `lib/` and `test/`.
`git diff --check`: clean. One new dependency: `shared_preferences` — see
«Storage», below. **Point 4 was not started.**

### What startup used to do

`initialLocation: '/home'`, and a `redirect` that computed the answer inline:
the forced-upgrade gate, then a three-arm switch on `AuthGate`
(`signedOut` → `/login`, `expired` → `/session-expired`, `signedIn`/`unknown` →
nothing), then two lines about `super_admin`. The router held three
`ValueNotifier`s — the upgrade gate, the auth gate, the role — and merged them
into its `refreshListenable`.

Three consequences, all fixed here:

1. **The session read is async, so every cold start built the tenant
   dashboard** — app bar, bottom nav, repository reads — and only then
   redirected. A signed-out person saw a flash of an authenticated screen; a
   Super Admin saw a flash of the wrong product.
2. **`AuthGate.unknown` meant two different things** — "still reading" and
   "answered, and the answer was inconclusive" — which forced one behaviour on
   both.
3. **A refused account read as signed out**, so an `AuthUser` failing the
   role/`saasTenantId` invariant sent the person to a login form that would
   hand back the same broken payload.

### First: the Point 2 gap, closed

**The development persona now survives real process termination.**
`InMemoryDemoSessionStore` proved the seam but lost its record on a relaunch, so
a developer who signed in as the Simple Admin came back as the Main Admin, and
one who signed out came back signed in.

`PersistentDemoSessionStore` (`features/auth/data/`) writes the persona id —
**only the id**; the account and its grant are rebuilt from the fixture — to the
new durable store. Two keys, because one cannot distinguish "never-used device"
(seed the Main Admin, which is what every screen and fixture is written
against) from "signed out here" (stay signed out): `mtm.dev.demo_persona` holds
the selection, and a presence-only marker records that first-run seeding
happened. Sign-out **removes** the persona key and leaves the marker.

**Release safety, now three gates rather than two.** `demoAccountsAllowed`
(`const false` outside debug) and `MockAuthRepository`'s refusal were already
there. The new outermost one is the wiring: `demoSessionStoreProvider` hands a
release configuration `NoDemoSessionStore`, which reads and writes nothing — so
a record left on a device by a debug build is never *loaded*, not merely
ignored. It is not deleted either: refusing to honour a developer's record is
the requirement; erasing their device state from a production run is not.

### Storage — the one durable mechanism, and why a package was added

This repository had **no durable local storage at all**: `SettingsRepository`,
`AppVersionGateStore` and `DemoSessionStore` were in-memory mocks, and there was
no established persistence approach to reuse. Surviving a real process restart
is not achievable without one.

`core/storage/local_store.dart` is a three-operation `LocalStore` seam with a
`shared_preferences` implementation and an in-memory one. `shared_preferences`
is the official Flutter-team plugin, used through a single seam exactly as
`url_launcher` already is. The other two stores are written against the same
shape and can be moved onto it without a second storage architecture appearing.
`DATA-NEEDS.md` §3.3 still governs what may be written there — no token, no
secret, no grant, no personal record.

`test/flutter_test_config.dart` installs `shared_preferences`' own in-memory
store before each test, so the durable path is exercised for real rather than
falling into the "no platform" branch.

### The classifier

`core/startup/startup_destination.dart` — **one enum, one pure function, one
documented priority**. No `Ref`, no `BuildContext`, no provider read, no import
of a screen: the whole state table is callable from a plain unit test, which is
what the states no backend produces yet actually needed. The canonical route
string for each outcome lives on the enum, so the router and the classifier
cannot spell one differently.

`core/startup/startup_providers.dart` is the twelve lines that read the four
inputs. The router now holds **one** notifier — the decision — instead of three
ingredients, and its `redirect` computes nothing.

**Priority, in order.** 1 forced upgrade · 2 restoring · 3 expired ·
4 invalid · 5 signed out · 6 MFA required · 7 account revoked · 8 account
suspended · 9 tenant deleted · 10 tenant suspended · 11 first-time/unlinked ·
12 demo expired · 13 demo active · 14 role → surface · 15 tenant no-access ·
16 the requested route.

The one deviation from the brief's ordering is **forced upgrade before boot**,
and it is a deviation in name only: the existing `AppVersionController` blocks
only when it has *found* a reason, so a launch that has not answered yet is not
blocked and falls through to «restoring» exactly as if the step were second. A
build the backend refuses must not spend a restoration on a session it may not
use.

### `AuthGate` — two values split out

- `restoring` — the read is in flight. Holds the app on the loading surface.
- `unknown` — the read answered and the answer is not evidence (offline with
  nothing cached, a transport error). **Redirects nowhere**, unchanged from
  before, because parking an offline-first field app on a splash screen would
  be as broken as bouncing it to a login form. `capabilitiesProvider` is
  `Capabilities.none` throughout, so nothing gated is offered.
- `invalid` — an account payload that fails `isWellFormed`. Its own screen.

`AuthGate.isUnresolved` is what the capability route guards now ask, so both
waiting states keep deciding nothing.

### Where each account goes

| Account | Destination | Kept out of |
|---|---|---|
| `super_admin` | `/platform` | every tenant route, deep links included; the tenant shell is never built |
| `main_admin` | `/home`, then wherever it asks | `/platform`, every startup-only holding location |
| `admin` (Simple) | the same, with its existing capability guards unchanged | the same |
| tenant account holding nothing | `/access-not-assigned` | every operational route |
| customer demo (future) | `/demo` / `/demo-expired` | both real surfaces, always |

**Nothing routes by role except one `if`.** Capabilities still decide route
access, data scope and every action — `CAPABILITIES.md` §5b states the split and
carries the route→role matrix.

### `SessionAccess` — the provisional lifecycle seam

`features/auth/domain/session_access.dart`: `AccountStatus`
(active/suspended/revoked/pending_setup), `TenantStatus`
(active/suspended/deleted), `DemoMode` (none/active/expired) and `mfaRequired`.
No backend supplies any of it, so `sessionAccessProvider` answers
`SessionAccess.normal` for every real session; the types exist so the classifier
branches on them now and nothing has to be replaced when the fields arrive.
Unknown wire values read as the *normal* value — the opposite of `AuthRole`,
and deliberately so.

**Nothing is inferred.** An empty capability set is `tenantNoAccess` and never a
suspension; `orgName`, the email and id shapes say nothing.

### Screens

New, all on the root navigator so none builds the tenant shell:

- `StartupPage` `/startup` — the app's `initialLocation`. The mark, one line,
  a thin bar. No account, no organisation, no claim about the network (the
  restore is local). The bar is a static track when `MotionSpec.ambientLoops`
  is off, which covers both `MediaQuery.disableAnimations` and the lowest
  performance preset.
- `status_pages.dart` — nine screens over one `StatusScreen` component
  (`core/widgets/status_screen.dart`): session invalid, access not assigned,
  account suspended, account revoked, tenant suspended, tenant deleted, account
  setup, demo, demo expired. Scrolling body, stretched column of actions,
  directional insets throughout.
- `DevSessionStatesPage` `/dev/session-states` — **debug only**, reachable from
  one row on the Settings hub. Forces a `SessionAccess` and lets the *router*
  re-decide, so what is inspected is the routing as much as the layout.

Reused unchanged: `/login`, `/session-expired`, `/mfa-setup`,
`/mfa-challenge`, `/upgrade-required`, `/platform`.

What the status screens deliberately do **not** show: no email, no organisation
name, no capability, no tenant record. Only the account's display name and
account type, and only where that explains the screen — the refused-payload
screen shows not even that. Support is a dialog reading the same two constants
About uses, **not** a link to `/more/about`, because that route lives in the
tenant shell branch and opening it would build the bottom nav for exactly the
sessions that must not have one.

### MFA and forced update

Untouched and intact. `/mfa-setup` and `/forgot` are still reachable from
Security and Profile — a signed-in tenant session may open the public auth
pages, and the password-reset chain (`/forgot` → `/otp` → `/new-password`) still
completes while signed out. `SessionAccess.mfaRequired` is a typed hook that
outranks both surfaces; nothing sets it, and no MFA backend semantics were
invented. The forced-upgrade gate is unchanged and still outranks every role.

### Files

**New** — `core/storage/local_store.dart`; `core/startup/startup_destination.dart`,
`core/startup/startup_providers.dart`; `core/widgets/status_screen.dart`;
`features/auth/domain/session_access.dart`;
`features/auth/data/persistent_demo_session_store.dart`;
`features/auth/presentation/startup_page.dart`,
`features/auth/presentation/status_pages.dart`,
`features/auth/presentation/dev_session_states_page.dart`;
`test/flutter_test_config.dart`.

**Changed** — `core/router/app_router.dart` (the redirect rewrite, three
notifiers to one, the new routes), `features/auth/data/auth_providers.dart`
(the two new gate values, the durable store wiring, the access seam),
`features/auth/data/sign_out_controller.dart` (clears the forced session
state), `features/auth/data/persistent_demo_session_store.dart`,
`core/access/capability.dart` (`hasAny`), `core/access/capability_guard.dart`
(`isUnresolved`), `features/settings/presentation/settings_page.dart` (one
debug-only row), `l10n/strings.dart`, `pubspec.yaml`.

**Tests** — new: `core/startup/startup_classifier_test.dart` (32),
`core/startup/startup_routing_test.dart` (24),
`features/auth/demo_session_persistence_test.dart` (15),
`features/auth/status_screens_test.dart` (22). Updated:
`features/auth/super_admin_routing_test.dart` (invalid → `AuthGate.invalid`),
`features/auth/admin_experience_routes_test.dart` (an empty grant now lands on
its own screen), `features/search/search_navigation_test.dart` (the restricted
state needs a grant that is real but searches nothing),
`features/app_version/forced_upgrade_test.dart` (the boot transition finishes
before "nothing is animating" is asked),
`features/settings/settings_hub_test.dart` (scrolls to sign-out; the hub is one
section longer in a debug build).

### Known gaps

1. **No backend supplies any lifecycle state.** Every state screen below
   «no access assigned» is reachable only through the development inspector or
   a test override. That is honest, not incomplete — the fields are specified
   in `API_CONTRACT.md` § SessionAccess and nothing was faked.
2. **`/platform` is still a holding state.** Point 4 builds the shell.
3. **Tenant suspension blocks outright.** Point 9 owns the platform controls
   that set it and will decide what a suspended customer may still do; a
   read/export-only window is the likely refinement.
4. **First-time setup collects nothing.** No team-code field, no OTP — a field
   collecting a code nothing can redeem would be worse than no field.
5. **Customer demo has no workspace.** `/demo` is a holding surface; limits,
   timers, Try Demo and conversion are later points.
6. **No device run.** Every screen was verified by widget test at 320 dp,
   text scale 1.6, Arabic RTL, in all three themes plus eye-protect; none was
   looked at on hardware.
7. **`SCREEN-ROUTE-MATRIX.md` does not exist** in this repository. The
   route→role matrix was added to `CAPABILITIES.md` §5b and the per-screen data
   rows to `DATA-NEEDS.md` §2.1b instead.

### Exactly next

**Point 4 — the Super Admin platform mobile shell.** It builds the platform
overview, navigation and modules at `/platform` and deletes
`PlatformHoldingPage`. Nothing in Point 3 is a component of that shell.

---

## ZZZZZZZZZZZZZ. Latest session — 2026-09-07 (Point 2 — development demo accounts)

Authentication identity only. No platform surface, no `SaasTenant` model, no
subscriptions, no onboarding, no backend, no new packages. `flutter analyze`:
clean (0 issues). `flutter test`: **979 pass / 0 fail** (917 before, +62 new).
`dart format` run on the files this pass touched. `git diff --check`: clean.

### First: the two Point 1 documentation gaps, closed

- `DATA-NEEDS.md` §2.3 — the obsolete `/detachment/new` row is gone. The
  create route is `/detachment-groups/:groupId/detachment/new` (a detachment is
  always created inside a group), and three missing `DetachmentGroup` screen
  rows were added: the group list, the group form (with its cascading delete),
  and the detachments-inside-a-group screen. Heading renamed to
  «Detachment groups and detachments».
- `API_CONTRACT.md` — a `DetachmentGroup` **resource** section now exists: the
  canonical payload (including the three derived roll-ups and exactly how each
  is computed) and the five endpoints behind `DetachmentGroupRepository`, with
  their capability requirements, their `validation`/`conflict` refusals, and
  the cascade rule on delete. Written strictly from the existing Flutter
  domain and mock — nothing invented.

Documentation only. Point 1 implementation was not reopened.

### The product model this point encodes

Three account levels, and they are not three ranks of one admin:

| Level | `AuthUser.role` | `saasTenantId` | Administers |
|---|---|---|---|
| Super Admin | `super_admin` | **null** | the MTM platform — subscribers, plans, platform health |
| Main Admin | `main_admin` | required | one `SaasTenant` — one paying team |
| Simple Admin | `admin` | required | part of that **same** `SaasTenant` |

**Role selects the product surface; capabilities authorize the actions.**
Nothing branches on a role to grant anything — every check still resolves
through `Capabilities.canIn`. This is not the `UserRole` enum that was removed
on 2026-09-02: that one named a rank inside one organisation and *was* the
authority check.

### What `AuthUser` looked like before

`id`, `name`, `email`, `capabilities`, `orgName`, `avatarInitials`. No role, no
tenant. `MockAuthRepository` held one hard-coded account, booted signed in as
it, and `signIn` returned **that same full organisation-wide administrator for
any input** with a password of four characters or more. There was no
persistence of any kind on the auth seam and no build-mode convention anywhere
in the app beyond one `kDebugMode` in `async_result.dart`.

### What changed

**`AuthRole`** (`features/auth/domain/auth_models.dart`) — `superAdmin` /
`mainAdmin` / `admin` with explicit wire values `super_admin` / `main_admin` /
`admin`, `parse` that refuses an unknown value rather than defaulting, and
`belongsToSaasTenant`.

**`AuthUser.role` and `AuthUser.saasTenantId`** — both required (the tenant id
is required-but-nullable, so every call site states its intent). The invariant
is `isWellFormed`, and it is enforced in two places: `fromJson` throws on a
violation, and `auth_providers.dart`'s `_accepted` refuses such an account so
the app reads as **signed out**. Nothing repairs an invalid account — the
client cannot know whether the role or the id is the wrong half, and either
guess produces a session silently scoped to the wrong customer.

**Three personas** (`features/auth/data/demo_personas.dart`) — stable ids,
Arabic-facing identity, no randomness. Super Admin holds `Capabilities.none`
(all 30 keys are tenant-operational; none describes platform authority). Main
Admin is the account the mock always booted into, moved here unchanged. Simple
Admin is `CapabilityPreset.subAdmin` over `d_dam_central` + `d_homs`, sharing
the Main Admin's `saasTenantId`.

**Release safety, two gates.** `demoAccountsAllowed` (`core/env/build_mode.dart`)
is `const kDebugMode`, so in a release artefact every demo branch is dead code
the tree shaker removes — the selector is *absent*, not hidden, and there is no
hidden semantics node, no invisible tap target and no route or query parameter
that signs anyone in. `demoAccountsEnabledProvider` sits inside it and defaults
to it, so a test can exercise a release configuration under the debug VM.
Both are checked at every demo entry point.

**Persistence** — `DemoSessionStore` (one record, three operations, following
`AppVersionGateStore` rather than inventing a shape) stores **only the persona
id**; the account is rebuilt from it. `InMemoryDemoSessionStore` seeds with the
Main Admin persona, which is where the old hard-coded signed-in session moved
to — and that relocation is what makes sign-out survive a relaunch, because
sign-out clears the record.

**Mock login** — `signIn` resolves the address against the persona table and
returns *that* account, or refuses with `not_found`. The password rule is
unchanged. In a release configuration it authenticates nobody: there is no
production auth fallback that recognises a demo credential.

**Super Admin, temporarily** — `PlatformHoldingPage` at `/platform`: no
navigation, no repository, one action (the ordinary sign-out). The router
redirect gained one clause — a `super_admin` goes there and nowhere else, and
nobody else may reach it.

**Login page** — a successful sign-in now invalidates `currentUserResultProvider`.
Without it the session providers still answered from the pre-sign-in read, so
the account that just signed in was not the account the app ran as. That is
load-bearing for this point: it is what makes "sign in as the Simple Admin"
actually produce a Simple Admin session.

### AdminView / AdminExperience — clarified, not replaced

They were built before a real role existed and their doc comments asserted
«`AuthUser` carries no role», which is now false and was the source of the
semantic confusion. Both files (and `AdminAccountSummary`) now state the split:

- **`AuthRole`** — which product surface an account belongs to.
- **`AdminView` / `AdminExperience`** — *inside the tenant application*, how
  broad this session's UI is, derived from capability breadth.

Independent by construction: a `main_admin` whose keys were narrowed is still a
Main Admin and is honestly shown the scoped UI. A `super_admin` is not
classified there at all. **No behaviour changed** — no logic was rewritten, and
`AdminView.of` is byte-for-byte what it was.

### Profile

One new row, «نوع الحساب», read straight off `AuthUser.role`, above the
existing derived access-level and scope rows. The two are deliberately
separate so neither can lie. No redesign.

### Files

**New** — `core/env/build_mode.dart`; `features/auth/domain/demo_session_store.dart`;
`features/auth/data/demo_personas.dart`,
`features/auth/data/in_memory_demo_session_store.dart`,
`features/auth/data/demo_sign_in_controller.dart`;
`features/auth/presentation/demo_accounts_section.dart`,
`features/auth/presentation/platform_holding_page.dart`.

**Changed** — `features/auth/domain/auth_models.dart`,
`features/auth/domain/admin_account.dart`,
`features/auth/data/auth_providers.dart`,
`features/auth/data/mock_auth_repository.dart`,
`features/auth/presentation/login_page.dart`,
`core/access/admin_experience.dart` (comments only), `core/router/app_router.dart`,
`features/settings/presentation/profile_page.dart`, `l10n/strings.dart`.

**Tests** — new: `features/auth/auth_role_test.dart`,
`features/auth/demo_personas_test.dart`, `features/auth/demo_login_test.dart`,
`features/auth/super_admin_routing_test.dart`. Updated: 14 files carrying an
`AuthUser` fixture (the two new fields are required), plus
`core/access/capability_test.dart` (a test asserting the payload had no `role`
now asserts the role round-trips beside an independent grant) and
`features/auth/admin_profile_test.dart` (+2).

### Known gaps

1. ~~**Persistence is in-memory.**~~ **CLOSED by Point 3** (2026-09-07):
   `PersistentDemoSessionStore` writes the persona id through the durable
   `LocalStore`, so the selection survives real process termination.
2. **`/platform` is a holding state.** ~~Point 3 replaces the router clause~~ —
   it did; Point 4 builds the shell and deletes the page.
3. **No `SaasTenant` model.** A typed `saasTenantId` and one fixture id — Point
   6 owns the model.
4. **Platform capabilities do not exist.** Deliberate: nothing in `Cap`
   describes platform authority and inventing keys here would have been
   guessing. Points 4+ define them against real platform repositories.
5. **MFA is untouched.** The mock never required a challenge to reach a
   session, and personas inherit exactly that. No production MFA semantics
   were faked.

### Exactly next

**Point 3 — the complete role-based startup / router decision.** *(Done —
2026-09-07. It replaced the two-branch `super_admin` clause and the `role`
`ValueNotifier` with `startupDestinationProvider`, and kept `/platform` as the
platform entry point. See the Point 3 section at the top of this file.)*

---

## ZZZZZZZZZZZZ. Latest session — 2026-09-07 (Point 1 — Tenant → DetachmentGroup terminology migration)

Terminology only. No behaviour, no new screens, no new packages, no
architecture change. `flutter analyze`: clean (0 issues). `flutter test`:
**917 pass / 0 fail**. `dart format` run on the files this pass touched.
`git diff --check`: clean.

### Why

Three concepts were about to collide on one English word:

| Concept | What it is | Identifier |
| --- | --- | --- |
| **SaasTenant** | the paying team/customer; subscription, billing and data-isolation boundary | `tenantId` |
| **DetachmentGroup** | a grouping of detachments inside one SaasTenant | `detachmentGroupId` |
| **Detachment** | the operational medical field unit | `detachmentId` |

The frontend's local grouping concept had been called `Tenant` since the
container layer was built (§BATCH0-HANDOFF, Session 5). It is **not** a SaaS
tenant, and the platform layer that will need that word is not built yet — so
the local concept gave the word up rather than the boundary concept inheriting
an ambiguity.

### The audit that came first

The whole Flutter frontend was searched for `Tenant` / `tenant` / `tenantId`
before anything was edited, and every occurrence classified. The result was
unambiguous: **there was no SaaS-tenant code in the frontend at all.** Every
Dart occurrence — model, repository, providers, routes, l10n keys, mock
fixtures, tests, comments — was the local grouping. The only surviving
`tenant` prose is in `FRONTEND-BACKEND-INTEGRATION.md` and this file's
backend-security sections, where it has always meant the SaaS boundary, and in
`BATCH0-HANDOFF.md`'s dated session log, which records what the concept was
called on 2026-09-02.

### What was renamed

- **Types** — `Tenant` → `DetachmentGroup`, `TenantStatus` →
  `DetachmentGroupStatus`, `TenantRepository` → `DetachmentGroupRepository`,
  `MockTenantRepository` → `MockDetachmentGroupRepository`, `TenantListPage` /
  `TenantEditPage` → `DetachmentGroupListPage` / `DetachmentGroupEditPage`.
- **Field** — `Detachment.tenantId` → `Detachment.detachmentGroupId`, JSON key
  included. Also `DetachmentListQuery.tenantId`,
  `DetachmentRepository.list(tenantId:)`, `create(tenantId:)`, and
  `deleteAllInTenant` → `deleteAllInGroup`.
- **Report** — `ReportDocument.tenantName` → `detachmentGroupName` (CSV and
  plain-text output unchanged; only the Dart field is renamed).
- **Providers** — `tenantRepositoryProvider`, `tenantListProvider`,
  `tenantByIdProvider` → the `detachmentGroup*` equivalents.
- **Files** — `lib/features/tenant/` → `lib/features/detachment_group/`, every
  file inside renamed to match, and
  `test/features/detachment/tenant_flow_smoke_test.dart` →
  `detachment_group_flow_smoke_test.dart`. All moved with `git mv`.
- **l10n identifiers** — the whole `S.tenant*` block → `S.detachmentGroup*`.
  **The Arabic copy is byte-identical.** «الجهة» / «الجهات» was already the
  right product word for this concept and users see no change; the collision
  being removed was technical, not editorial.

### Routes

Canonical prefix is now `/detachment-groups`:

| Was | Is |
| --- | --- |
| `/tenant` | `/detachment-groups` |
| `/tenant/new` | `/detachment-groups/new` |
| `/tenant/:tid` | `/detachment-groups/:groupId` |
| `/tenant/:tid/edit` | `/detachment-groups/:groupId/edit` |
| `/tenant/:tid/detachment/new` | `/detachment-groups/:groupId/detachment/new` |

**The five old paths survive as redirect-only routes** (`app_router.dart`,
`_legacyDetachmentGroupPaths`). They are declared flat rather than nested,
because a parent `/tenant` redirect firing first would drop the id out of the
child paths; and they are a rewrite, not a bypass — the capability guard on
the canonical route runs afterwards and answers exactly the same, which
`admin_experience_routes_test.dart` asserts for a scoped admin.

**TEMPORARY.** Remove `_legacyDetachmentGroupPaths` and its route builder once
no build in the field still emits `/tenant` links. Nothing else in the app
references them.

### Deliberately *not* renamed

- **Mock fixture ids** (`t_damascus`, `t_central`, `t_coast`). Opaque
  identifiers, not terminology; renaming them would have churned every test
  fixture that names one for no gain, and they do not match a `tenant` grep.
- **`Detachment.fromJson` has no `tenantId` fallback.** It has zero call sites
  today — every mock builds `Detachment` in Dart and nothing writes detachment
  JSON to storage — so there is no persisted old key to be compatible with.
  Adding one would recreate the exact ambiguity this point removed: on a real
  wire, `tenantId` will mean `SaasTenant`, and a silent fallback would file the
  paying tenant's id into `detachmentGroupId`.
- **Capability keys.** There were none named `tenant.*`. The grouping screens
  gate on `detachment.create` / `admin.manage`, which are already correctly
  named and unchanged. Nothing in `CAPABILITIES.md`'s key table moved.

### Docs updated

`API_CONTRACT.md` (new **Terminology** section defining all three concepts;
`detachmentGroupId` added to the `Detachment` shape, the list query and the
create body), `CAPABILITIES.md`, `DATA-NEEDS.md`, this file.
`BATCH0-HANDOFF.md` keeps its dated prose and carries a rename banner.

### Open — both closed 2026-09-07 at the start of Point 2, see §ZZZZZZZZZZZZZ

- ~~`DATA-NEEDS.md` §2.3 still lists `/detachment/new`, a route the container
  layer removed on 2026-09-02, and has no screen rows for the group list and
  form.~~ **Closed.**
- ~~`API_CONTRACT.md` documents the `detachmentGroupId` **field** but still has
  no `DetachmentGroup` resource section.~~ **Closed.**

**Point 2 (Demo Accounts) was not started.** Nothing in this pass touches role
routing, Super Admin, subscriptions, onboarding or the backend.

---

## ZZZZZZZZZZZ. Latest session — 2026-09-05 (Point 4 — Notifications Center)

One area only. No redesign of the dashboard, Shifts, Inventory, Members,
Detachments or Settings; one new route, no new packages, no navigation
architecture change. `flutter analyze`: clean. `flutter test`: **536 pass / 0
fail** (486 before, +50 new). `dart format` run on the files this pass
touched. `git diff --check`: clean.

### What existed before this pass: nothing

The audit found **no notification domain, feed, model, repository, badge, or
screen** anywhere in the app. The one thing named "notifications" was
`/more/notifications` — `NotificationPrefs`, four push toggles, which is a
preference screen, not a feed. `API_CONTRACT.md` had no notifications
endpoint. Nothing in the app carried a notification icon, so there was no dead
badge to wire up either.

### What was built, and why it is not a fake backend

There is no notification table to read, so the centre **derives** its rows
from records that already exist, the way `MockHomeRepository` derives the
dashboard. `MockNotificationRepository` joins the shift and inventory
repositories; the client half is read straight off the outbox. Every row
therefore points at a real record with a real id, and disappears the moment
its condition is resolved. Nothing was seeded to fill the screen.

**Eight kinds, all backed by data the app can actually observe:** a shift
short of people, a finished shift with attendance unrecorded inside its
window, a shift starting within six hours, an item that ran out, an item under
its minimum, an item near expiry, a queued write that failed, a queued write
waiting on a conflict decision. One row per item, worst condition wins — the
same fold `storageStatusOf` uses.

**Three files carry the whole decision layer**, all pure Dart:
`notification_models.dart` (values, copy-free like `DashboardAlert`),
`notification_selectors.dart` (builders, capability filter, read-state stamp,
day grouping, destination mapping), and `notification_read_store.dart` (the
read-state seam, sitting beside `OutboxStore` and `ConflictReviewStore`
because read state covers rows from **both** halves of the feed).

### Three rulings worth keeping

1. **Ids are a function of the condition, not of the fetch.**
   `<kind>:<record id>`. The feed is rebuilt from scratch on every load, and
   read state is keyed by the id — a regenerated id would silently un-read
   every row the user had already seen. Tested.
2. **The fetch is split from the merge.** `notificationSourceProvider` asks
   the repository; `notificationFeedProvider` is a plain `Provider` that
   merges in the outbox, the read set and the session's grants. Written the
   other way round first, and every outbox change restarted a full round trip
   — which is also what broke eleven dashboard tests and two conflict tests
   with pending timers. The split is the fix and the right shape.
3. **Capability gates degrade the destination, they never fake one.** A
   volunteer is not told a shift is understaffed or that the store is low
   (`buildDashboardAlerts`' rule), but may know a shift starts soon — and
   tapping it opens the read-only schedule tab instead of a management sheet
   where every control would be disabled.

### Entry point and badge

One bell, in the dashboard's app bar, badged from
`unreadNotificationCountProvider` — which counts the very list the screen
renders, so the two cannot drift after a read, a mark-all, a refresh, or a
sync run. The dashboard's alert rows are unchanged: they still open the
surface that fixes each condition directly, which is a shorter path than
routing them through a list.

`/notifications` is a **root** route beside `/needs-review`, for the same
reason — a full surface opened deliberately, so it covers the bottom nav.

### One pre-existing test harness was touched

`dashboard_states_test.dart` now stubs `notificationSourceProvider` empty in
its `_pump`. The bell gave the dashboard a real new dependency; the assertions
are untouched. Nothing else in the preserved suites changed.

### Backend/domain gaps this pass could not close

- **No notification backend.** `API_CONTRACT.md` § Notifications now specifies
  `GET /api/v1/notifications` and `PUT /api/v1/notifications/read`; neither
  exists. Until they do, announcements, assignment/update/cancellation events,
  team messages and join requests **cannot** be shown — there is no record
  behind any of them, so none were invented.
- **Read state does not survive a relaunch.** `InMemoryNotificationReadStore`
  lives for the life of the object, exactly like the theme preference and the
  active-detachment choice. The seam is complete; there is still no durable
  local store in this build.
- **Read state is not queued to the outbox.** Deliberate: there is no
  transport, so `notification.read` operations would pile up forever and
  inflate the "بانتظار المزامنة" count on Settings and the dashboard. A real
  repository should enqueue them.
- **`NotificationPrefs` governs push, and there is no push.** No push package
  is in `pubspec.yaml`. The four toggles are not used to filter the in-app
  centre on purpose: switching off a *push* is not asking to be kept in the
  dark about a critical stock level when you open the app yourself.
- **No personal feed.** `AuthUser` still carries no link to a `TeamMember`
  (the same gap Point 2 recorded), so "your shift is starting" is really "a
  shift at your detachment is starting".

## ZZZZZZZZZZ. Earlier session — 2026-09-05 (Points 2 & 3 — Today dashboard finalized, Members module completed)

Two areas only. No redesign of Shifts, Inventory, Statistics, Detachments or
Settings; no new routes, no new packages, no navigation architecture change.
`flutter analyze`: clean. `flutter test`: **486 pass / 0 fail** (435 before,
+51 new). `dart format` run on the 17 files this pass touched.
`git diff --check`: clean.

### Point 2 — the Today dashboard was decorative; it is now operational

**What was wrong.** `MockHomeRepository` returned a hard-coded detachment
name, a hard-coded shift, and three invented "decisions" (including a join
request the app has no concept of). None of it carried an id, so every card
and every button on Home was a dead end, and the figures agreed with nothing
else in the app.

**What replaced it.** The `HomeRepository` seam is kept — a single-round-trip
summary is right for a mobile client — but it is now real:

- `HomeSummary` carries `detachmentId`, the detachment's identity, the shifts
  for **yesterday/today/tomorrow**, roster count, and the storage fold.
  Three days because "now" and "next" are clock questions: a 20:00–02:00
  shift dated yesterday is still running at 01:00.
- `MockHomeRepository` **composes** the detachment, shift, inventory and team
  repositories (the pattern `MockShiftRepository` already used for the
  roster), so a figure on the dashboard cannot disagree with the tab it links
  to. A section that fails degrades to "nothing known" instead of taking the
  screen down.
- `summary()` now takes a `detachmentId`. `API_CONTRACT.md` § Home updated.

**Which detachment.** `DETACHMENT-SCOPING.md` §4's proposal, implemented:
one at a time, deterministic seed (explicit choice if still valid → the only
one → first by name), a switcher rendered *only* when there is more than one.
Persistence across relaunch is still not possible (no durable local store —
the same gap the theme preference has), so the choice re-seeds deterministically
rather than being remembered wrongly.

**Decision layer, extracted and tested.** `shift/domain/shift_selectors.dart`
(current/next shift, attendance counts — shift-domain logic, so both the
dashboard and a member's page read the same answers) and
`home/domain/today_selectors.dart` (the alert rules). Two rules govern alerts:
nothing is raised without a record behind it, and nothing is raised at a user
whose grants cannot fix it (sync alerts excepted — those are their own writes).

**Screen.** Context header → current shift (manager, lock window, attendance
present/awaiting/absent/gap) → next shift → alerts → role-aware quick actions.
Every action opens an **existing** destination: the shift management sheet,
`/detachment/:id/{shifts,team,storage,stats}`, `/more/sync`, `/needs-review`.
The decorative stat cards (attendance rate, workshops this week) are gone —
that is Statistics' job, not Today's.

### Point 3 — Members completed in place, not rebuilt

The roster, the member form (add/edit/role/delete, each already gated) and the
member page already existed; nothing was duplicated. What was missing:

- **Search + filters** on the roster tab: a search field, a filter sheet
  offering only facets the data actually has (role, section), removable active
  filter chips, and a header that says how much of the roster is showing.
  Filtering is in memory (`team/domain/member_search.dart`) — a roster is tens
  of records, so a keystroke costs nothing and never touches the network.
- **Arabic search that works**: `memberSearchKey` folds أ/إ/آ→ا, ى→ي, ة→ه,
  strips harakat and tatweel, and maps Arabic-Indic digits, so "احمد" finds
  "أحمد" and "١٠٣" finds "103". `memberNameKey` (identity/duplicate detection)
  stays strict on purpose — folding there would merge two real people.
- **Member page**: identity card (detachment, section, number), a contact card
  gated on `Cap.memberContactView` (withheld and absent are different states,
  and it says which), and today's assignment — which opens the **existing**
  shift management sheet. Shifts remains the source of truth; Members is only
  a member-centric way in.

### Three real bugs the new tests caught

1. Two shifts short on the same day produced two alert rows keyed by kind
   alone — duplicate sibling keys, which is a hard crash. `d_dam_central` has
   exactly this shape today. Keys now carry the shift id.
2. The detachment picker's rows captured the page's context, so tapping one
   would have popped the dashboard instead of the sheet.
3. `SkeletonList` (a `ListView`) was used as a loading placeholder inside the
   member page's own `ListView` — unbounded height, i.e. a red screen while
   loading.

### Backend capability that blocked one thing

`AuthUser` carries no link to a `TeamMember`, so "my shift / my attendance"
for a plain volunteer is not resolvable on the client. The dashboard therefore
reports the **detachment's** day and gates management actions by capability,
rather than inventing a personal view. A `memberId` (or equivalent) on the
session profile is what would unlock it.

## ZZZZZZZZZ. Earlier session — 2026-09-05 (Settings IA Point 1 — hub + nested Themes/Performance/Sync screens)

**Point 1 of the Settings redesign only.** No backend, no `MTM-PRO` change,
no redesign of Profile/Security/Notifications/Org (Points 2–5 of that brief)
— their routes, contents, repositories, models, and workflows are untouched.
The working tree from every prior session was preserved; nothing reset,
reverted, or reformatted outside the files this pass touched.

`flutter analyze`: clean, whole project. `flutter test`: **435 pass / 0
fail** (roughly +17 new across the three new Settings test files, on top of
the pre-existing suite). `dart format` run only on the 12 files this pass
touched (3 needed reformatting: `settings_page.dart` and two of the new
test files). No `git diff --check` issues on the tracked files this pass
changed; the new/untracked files were checked by hand for trailing
whitespace instead, and are clean.

### The problem

`/more` mixed six theme controls, two performance controls, Manual Sync +
the conflict attention row, four account links, and sign-out on one long
page — the brief's "too many unrelated controls" complaint. The screen's
job was doing double duty as both a navigation index and a control panel.

### The information-architecture decision

`/more` becomes navigation-only: four grouped sections (Appearance & Device,
Data & Sync, Account, Organization) of `NavigationRow`s, each with an icon, a
label, and — for Themes/Performance/Sync only — a short live-state summary
(e.g. "طبّي · فاتح", "متوازنة · تلقائي", or the sync/needs-review line)
reusing strings the app already had. No control renders directly on the hub
any more; every one moved to its own nested screen, verbatim.

### Routes added (all children of the existing `/more` `GoRoute`, same
`_moreBranch`/`_sharedAxisPage` convention as every existing nested Settings
route — no new navigator, no new transition)

- `/more/themes` → `ThemesPage` — six-palette picker, Light/Dark/System,
  eye-protect.
- `/more/performance` → `PerformancePage` — the five-step motion/quality
  picker, the frame-rate picker.
- `/more/sync` → `SyncPage` — wraps the existing `SyncSettingsSection`
  widget unchanged (Manual Sync, pending count, the quiet Needs Review
  attention row).

### Controls moved / providers reused

Every control was **moved**, not reimplemented: same `themeStateProvider` /
`themeControllerProvider`, `motionLevelProvider`, `frameRateProvider` /
`displayCapabilitiesProvider`, `syncCoordinatorProvider` /
`pendingOperationsCountProvider` / `conflictOperationsCountProvider`, and the
same `SyncSettingsSection` widget (Task 4's conflict/Outbox wiring — Auto
Sync still cannot navigate, Manual Sync still never force-opens a conflict,
the attention row still opens `NeedsReviewPage.routePath` only on an
explicit tap). The five reusable pieces the old single-file page built
inline (`_SectionLabel`, `_SettingsSection`, `_NavigationRow`, `_PickerRow`,
`_ChoicePill`) were extracted, made public, and moved to
`features/settings/presentation/widgets/settings_widgets.dart` so the hub
and both new pickers screens share one implementation instead of three.
`_MotionPicker`/`_FrameRatePicker` moved with the rest of their screen into
`performance_page.dart` and stayed private — nothing else uses them.

### Provisional/mock behavior unchanged

Everything already documented as mock/provisional stays that way:
`MockSettingsRepository`'s simulated latency, the in-memory outbox, the
mock Profile/Security/Notifications/Org repositories. This pass added no
backend integration and claims none.

### Files changed

- New: `features/settings/presentation/{themes,performance,sync}_page.dart`,
  `features/settings/presentation/widgets/settings_widgets.dart`.
- Rewritten: `features/settings/presentation/settings_page.dart` (now hub
  only).
- Edited: `core/router/app_router.dart` (three routes added),
  `l10n/strings.dart` (one new string, `settingsPerformanceTitle` — Themes
  and Sync reuse existing `settingsAppearance`/`sectionSync` strings, same
  pattern the Organization section/row already used).
- Tests: `test/features/settings/{settings_hub,themes_page,performance_page}_test.dart`
  (new); `test/core/router/app_router_test.dart` (three new locations);
  `test/features/conflict/needs_review_page_test.dart` (its full-app boot
  now lands on `/more/sync`, where the attention row actually lives —
  same widget, same assertions, still proves Auto Sync never navigates and
  Manual Sync never force-opens a conflict).

### Docs corrected

`README.md` §5 and `DATA-NEEDS.md` §2.5 no longer say Settings is "NOT
built"/"stub" — both now describe the hub + nested screens as built (screen
exists; still mock-repository-backed, no backend integration claimed).
Nothing outside the Settings section of either file was touched.

---

## ZZZZZZZZ. Latest session — 2026-09-05 (Task 4 corrective pass — useLocal/useCurrent protocol, Shift snapshot path)

> **Addendum — same day, final narrow correction.** This session's own
> `applyShiftConflictCurrentVersion` deleted its captured `ShiftConflictSnapshot`
> the moment it applied it — before the outbox operation was actually
> retired, so a failed retirement afterwards would have left nothing to
> retry with. A follow-up pass fixed this: the applier now only applies and
> returns `true`/`false`; cleanup moved to a new sibling seam,
> `ConflictSnapshotCleaner`/`conflictSnapshotCleanersProvider`
> (`conflict_current_application.dart`), which `applyConflictResolution`
> invokes **last**, after the outbox step and the review-entry forget both
> succeed — in both `useLocal` and `useCurrent`, so both now remove the
> typed snapshot (this session's text below only ever describes `useCurrent`
> applying one; it never removed it either way). The same follow-up pass
> also closed two validation gaps this session left open:
> `OutboxController.supersedeConflict` now rejects an original operation
> that is not `SyncState.conflict` and a missing/empty `resolutionVersion`,
> both before any store write, and `applyConflictResolution` enforces the
> same two checks plus `decision.conflictId == operation.operationId` before
> resolving either intent. `reviewLater` is unaffected — it still calls
> nothing, so it still removes nothing. Touched only:
> `outbox_controller.dart`, `conflict_current_application.dart`,
> `conflict_outbox_resolver.dart`, `shift_conflict_review.dart`, and their
> three matching test files. `flutter analyze`: clean.
> `flutter test`: **416 pass / 1 fail** — the one failure is
> `test/features/conflict/needs_review_inbox_test.dart`'s `useLocal`
> decision test, which predates this correction and calls `useLocal` with no
> `currentVersion`; that file was outside this narrow pass's allowed-file
> list, so it was reported as a blocker rather than edited. See that pass's
> own completion report for the full detail.

**Corrective continuation of Task 4 only.** No other roadmap item started,
no backend, no `MTM-PRO` change. The working tree from every prior session
(§ZZZZZZZ and earlier) was preserved — nothing reset, reverted, deleted, or
reformatted outside the files this pass actually changed.

`flutter analyze`: clean, whole project. `flutter test`: **407 pass / 0
fail** (376 before this pass + 31 new — see "Tests added" below).
`dart format` run only on the 17 files this pass changed (8 needed
reformatting). No tracked file in the repo has a diff to run
`git diff --check` against — `core/sync`, `features/conflict`, and most of
`features/shift` are untracked working-tree state from earlier sessions (see
`git status`); every file this pass touched was checked by hand for trailing
whitespace and conflict markers instead, and is clean.

Full contract: `FRONTEND-BACKEND-INTEGRATION.md` §5 ("Resolution protocol and
idempotency", now implemented) and §7 (corrected — see its own "Corrective
pass" note and "What changed in the corrective pass" section).

### Root causes corrected

§ZZZZZZZ's own "Deliberate limits" section already named exactly what was
wrong, and this pass fixes each of them:

1. **`useLocal` called `OutboxController.requeueAfterConflict`** — reusing
   the original `operationId`/`idempotencyKey` for what §5.5 says must be a
   *new* logical write (its body carries a different `version`). Fixed: it
   now calls the new `OutboxController.supersedeConflict`.
2. **`useCurrent` dropped the pending operation without ever applying the
   chosen current record locally** — a user who chose "استخدام النسخة
   الحالية" would still see their own stale edit on screen, because nothing
   ever wrote the current/shared version back into local state. Fixed: a
   feature-owned `ConflictCurrentApplier` runs first; the operation is only
   retired if it reports success.
3. **The production Shift composer registry was empty and unregistered** —
   Task 4 tests injected a finished `ConflictReviewEntry` directly, so the
   claimed "representative typed path" was not actually reachable from a
   real (or even mocked-future) detection. Fixed: `ShiftConflictSnapshot(Store)`
   + `composeShiftConflictReview` + `applyShiftConflictCurrentVersion` are
   built and registered in `main.dart` via `shiftConflictReviewOverrides`.
4. **`NeedsReviewPage`'s retry only invalidated `conflictReviewProvider`** —
   `needsReviewItemsProvider` joins that *and* `outboxProvider`; an
   outbox-load failure had no working retry. Fixed: retry invalidates both.

### State/model decisions

- `PendingOperation` gains two optional fields —
  `resolvesOperationId: String?` and `currentVersion: String?` — both
  `null` for an ordinary operation, both absent from `toJson()` when unset,
  both read back as `null` from a record serialized before they existed
  (`PendingOperation.fromJson` never throws on a missing key). This is the
  "smallest typed extension" §5.5 asked for — sync metadata, not a payload
  field, same rule the rest of the class already follows.
- `OutboxController.supersedeConflict` is the new primitive.
  `requeueAfterConflict` **still exists** — it is the right tool for a
  same-body retry, which `useLocal` is not — but nothing in the
  conflict-resolution path calls it anymore; its doc comment now says so.
- `ConflictCurrentApplier` / `conflictCurrentAppliersProvider`
  (`features/conflict/data/conflict_current_application.dart`) is the new
  `useCurrent` seam, built to the exact same shape as the existing
  `ConflictReviewComposer` / `conflictReviewComposersProvider` (empty
  default registry, feature registers itself via a composition-root
  override) — no new architecture invented, the existing pattern reused.

### Shift snapshot path

- `ShiftConflictSnapshot` (an ordinary `Shift` + two opaque version
  strings) and `ShiftConflictSnapshotStore` live in `features/shift/domain/`;
  `InMemoryShiftConflictSnapshotStore` (object-lifetime only, same
  limitation as every other in-memory store in this app) lives in
  `features/shift/data/`. `core/sync` imports none of this.
- `composeShiftConflictReview` reads the *local* side from
  `shiftRepositoryProvider` (the user's edit is still sitting there — a
  failed push never touches local state) and the *current* side from the
  snapshot store, then reuses `presentShiftConflict` unchanged and wraps the
  result with the new `ConflictReviewEntry.fromPresentation`. With no
  captured snapshot it returns `null` — the conflict stays listed as
  "details unavailable," never fabricated.
- `applyShiftConflictCurrentVersion` applies the snapshot's `Shift` through
  the ordinary `ShiftRepository.update` — the same repository call every
  other shift edit already goes through — and clears its own snapshot entry
  once that succeeds.
- `shiftConflictReviewOverrides` installs both over the empty defaults;
  `main.dart` applies it alongside the existing `conflictReviewOverrides`.
  This is what makes "the registered production Shift adapter can consume a
  supplied mocked/future typed snapshot" checkable today, without a real
  transport: seed `shiftConflictSnapshotStoreProvider`, and the exact
  production functions produce a real entry / apply a real local write —
  see `test/features/shift/shift_conflict_review_test.dart`.

### Exact `useLocal` ordering (`OutboxController.supersedeConflict`)

1. If a replacement already exists for `originalOperationId` (found by
   `resolvesOperationId`), return it — minting nothing new. If the original
   is somehow still present too, retire it now (recovers a prior run that
   created the replacement but failed to retire the original).
2. Otherwise, the original must still be on file, or the call throws
   (`StateError`) rather than silently doing nothing.
3. Mint the replacement through the existing `PendingOperation.create` /
   `newOperationIdProvider` seam — new `operationId`, new `idempotencyKey`,
   `resolvesOperationId: originalOperationId`,
   `currentVersion: resolutionVersion`.
4. **Store the replacement** (`OutboxStore.upsert`) — if this throws, the
   original is untouched: still `conflict`, same identity, same metadata.
5. **Only then retire the original** (`OutboxStore.remove`) — if this
   throws, the replacement is already durable, so both operations are left
   on file; never neither.
6. The resolver (`conflict_outbox_resolver.dart`) forgets the stored
   `ConflictReviewEntry` only after `supersedeConflict` returns without
   throwing.

### Exact `useCurrent` ordering (`applyConflictResolution`)

1. Look up the still-conflicted `PendingOperation` by `localOperationId` —
   throws if it is gone (already resolved/synced elsewhere).
2. Look up `conflictCurrentAppliersProvider[operation.entityType]`. Missing
   entry ⇒ treated as `applied = false`.
3. Await the applier. It applies the typed current snapshot through the
   owning feature's own repository and returns whether that write actually
   succeeded — never throws by contract, but a thrown error is caught the
   same way a `false` is (both mean "do not resolve").
4. `applied == false` ⇒ throw. The operation, its `SyncState.conflict`, and
   its stored review entry are all untouched.
5. `applied == true` ⇒ `OutboxController.discardConflict` retires the
   operation, **then** the review entry is forgotten.

### Failure-preservation evidence

Both orderings above are proven with failure-injecting fakes, not just
happy-path assertions:

- `test/core/sync/outbox_supersede_conflict_test.dart` — a fake `OutboxStore`
  that fails `upsert`/`remove` on demand proves: the replacement is stored
  before the original is removed (call-order assertion); a failed `upsert`
  leaves the original's identity, state and metadata untouched; a failed
  `remove` leaves both operations on file; a second call after a completed
  resolution mints nothing new; a second call after a *failed* retirement
  completes the retirement without minting a second replacement.
- `test/features/conflict/conflict_outbox_resolver_test.dart` — fake
  `ConflictCurrentApplier`s (returns `false`, throws, or is simply absent
  from the map) each independently prove the operation and its review entry
  survive a failed/missing `useCurrent` application, and that a failed
  `useLocal` mint (a throwing `newOperationIdProvider`) leaves the original
  conflict and its entry exactly as they were.
- `test/features/shift/shift_conflict_review_test.dart` proves the same
  guarantees through the *real*, registered Shift composer/applier (not
  fakes): no captured snapshot ⇒ `null`/`false` rather than a fabricated
  entry or a fabricated local write; a repository-rejected snapshot
  (`needed: 0`) fails the apply without throwing.

### Files changed / added this pass

```
lib/core/sync/pending_operation.dart                          (resolvesOperationId, currentVersion)
lib/core/sync/outbox_controller.dart                          (supersedeConflict; requeueAfterConflict doc corrected)
lib/features/conflict/data/conflict_current_application.dart  (new — ConflictCurrentApplier seam)
lib/features/conflict/data/conflict_outbox_resolver.dart       (useLocal/useCurrent rewritten)
lib/features/conflict/domain/conflict_review_entry.dart        (ConflictReviewEntry.fromPresentation)
lib/features/conflict/presentation/needs_review_page.dart      (retry invalidates both sources)
lib/features/shift/domain/shift_conflict_snapshot.dart          (new — typed snapshot + store interface)
lib/features/shift/data/in_memory_shift_conflict_snapshot_store.dart  (new — MOCK)
lib/features/shift/data/shift_conflict_review.dart              (new — composer/applier + overrides)
lib/features/shift/data/shift_providers.dart                    (shiftConflictSnapshotStoreProvider)
lib/main.dart                                                    (installs shiftConflictReviewOverrides)

test/core/sync/pending_operation_test.dart                      (new field group)
test/core/sync/outbox_supersede_conflict_test.dart              (new — 11 tests)
test/features/conflict/conflict_outbox_resolver_test.dart       (rewritten — 7 tests)
test/features/conflict/needs_review_page_test.dart              (useLocal/useCurrent assertions updated; 2 retry tests added)
test/features/conflict/needs_review_inbox_test.dart             (useLocal/useCurrent assertions updated)
test/features/shift/shift_conflict_review_test.dart              (new — 8 tests, the real Shift adapter)
```

### Remaining provisional / blocked-on-backend work (unchanged in kind)

- Both new in-memory stores (`ShiftConflictSnapshotStore`,
  `ConflictReviewStore`) are object-lifetime only — not durable across an OS
  process restart. A concrete store writes the same JSON shapes to the
  encrypted DB alongside `pending_operations`.
- Nothing is recorded or applied in the shipped app yet, despite the
  registration being real: no real `SyncTransport` exists to ever write a
  captured snapshot into `ShiftConflictSnapshotStore`. This is unchanged
  from before this pass and is not a gap this pass could close — it depends
  on the backend `409 stale_write` body shape (`FRONTEND-BACKEND-
  INTEGRATION.md` §7's still-open `Backend contract decision required`).
- The resolution operation `supersedeConflict` mints is never actually
  pushed anywhere — no wire body, no `Idempotency-Key` header exists to
  carry `currentVersion` in yet. It waits in the outbox as an ordinary
  pending write, exactly like any other operation, until a real
  `SyncTransport` exists.
- The Settings `ListTile`-inside-`_SettingsSection` debug assertion
  (`needs_review_page_test.dart`'s suppression) was re-checked this pass:
  it comes from Flutter's own `ListTile._debugCheckBackgroundIsHidden`,
  which fires whenever a `ListTile` sits inside an ancestor with a
  background color — that is `_NavigationRow`'s `ListTile` inside
  `_SettingsSection`'s `Container`, both pre-existing widgets this pass did
  not touch. The new `_ConflictAttentionRow` uses `Material`+`InkWell`
  directly, not `ListTile`, so it cannot be and is not the source. The
  suppression was **not broadened** — same two matchers as before.

### Confirmation

No file outside the list above was modified. In particular
`lib/features/detachment/presentation/detachment_member_status_page.dart`,
`test/core/theme/palette_contrast_test.dart`, and every other untracked
file this session found already modified were left exactly as found.

### Task 5

Already complete (see §ZZZZZZ). Untouched by this session.

---

## ZZZZZZZ. Latest session — 2026-09-05 (Needs Review Inbox + Durable Conflict Review Foundation — Task 4)

**Task 4 only.** No other roadmap item started, no backend, no
`MTM-PRO` change. The pre-existing working tree was preserved — nothing
reset, reverted or deleted.

`flutter analyze`: clean, whole project. `flutter test`: **376 pass / 0
fail** (345 after Task 5 + 31 new: 21 in `needs_review_inbox_test.dart`, 10
in `needs_review_page_test.dart`; one location added to the existing
`app_router_test.dart` list). `dart format` applied. `git diff --check`
clean. `graphify update .` run.

Full contract: `FRONTEND-BACKEND-INTEGRATION.md` **§7** (new), plus the
now-closed follow-ons in §4 and the now-built half of §5.4.

### What this session builds

The user-facing review loop for conflicts that were already being
*classified* (Task 2) and *specified* (Task 3) but had nowhere to go:

1. Settings shows the quiet count — unchanged — and that row is now the way
   in;
2. `/needs-review` lists every conflicted operation;
3. tapping one opens the Task 1 differences-first screen, rebuilt from
   metadata stored at detection time;
4. `useLocal` / `useCurrent` / `reviewLater` apply through the existing
   `conflictDecisionHandlerProvider`;
5. `reviewLater` leaves the operation and its metadata exactly as they were,
   so the row is still on the list on the way back.

Auto Sync's contract is unchanged except for one added step — it now stores
safe review metadata after preserving the operation, and still never
navigates.

### Files added

```
lib/core/sync/conflict_review_recorder.dart                  (core hook, no-op default)
lib/features/conflict/domain/conflict_review_entry.dart      (durable safe metadata)
lib/features/conflict/domain/conflict_review_store.dart      (persistence seam)
lib/features/conflict/domain/needs_review_item.dart          (the joined row + record labels)
lib/features/conflict/data/in_memory_conflict_review_store.dart  (MOCK)
lib/features/conflict/data/conflict_review_controller.dart   (controller + needsReviewItemsProvider)
lib/features/conflict/data/conflict_review_recording.dart    (composer seam + app override)
lib/features/conflict/presentation/needs_review_page.dart    (the inbox)
test/features/conflict/needs_review_inbox_test.dart
test/features/conflict/needs_review_page_test.dart
```

### Files changed

- `lib/core/sync/sync_coordinator.dart` — calls the recorder after a
  conflict is durably classified; best-effort, cannot abort the run.
- `lib/features/conflict/domain/conflict_models.dart` — `ConflictValueDirection`
  gains an explicit `wire`/`fromWire` (the `SyncState` idiom);
  `ConflictFieldComparison` gains `toJson`/`fromJson` and value equality.
  Additive only — no behaviour change to the Task 1 screen.
- `lib/features/conflict/data/conflict_outbox_resolver.dart` — a resolved
  conflict now forgets its stored entry too; doc comments corrected, since
  this handler is no longer unwired.
- `lib/features/settings/presentation/widgets/sync_settings_section.dart` —
  the attention row is now a control that opens `/needs-review`, with one
  composed screen-reader announcement and the activation action on the same
  node.
- `lib/core/router/app_router.dart` — `/needs-review` as a root route,
  beside the conflict screen it opens.
- `lib/main.dart` — installs `conflictReviewOverrides` at the composition
  root.
- `lib/l10n/strings.dart` — the Needs Review vocabulary (Arabic).
- `test/core/router/app_router_test.dart` — `/needs-review` added to the
  reachable-locations list.

### Deliberate limits (read before "finishing" this)

> **Superseded — see §ZZZZZZZZ (the corrective pass on top of this
> session).** The first two bullets below described real gaps, not accepted
> limits: `useLocal` reusing the original identity contradicted §5.5, and
> the composer registry was not just empty by policy but was never actually
> registered anywhere, including in the shipped app. Both are fixed by the
> corrective pass. Left in place, unedited, as the historical record of what
> this session actually shipped.

- **The composer registry is empty, so the inbox is empty in production.**
  A composer needs the current record from a real `409`; inventing one to
  make the screen look populated would be fabricating a backend conflict.
  The seam is built, tested and documented — that is the deliverable.
- **`requeueAfterConflict` still reuses the original identity.** §5.5's
  create-then-retire protocol belongs with the work that adds a real
  `SyncTransport`; changing it now would be a wire-protocol change with no
  wire.
- **`InMemoryConflictReviewStore` is object-lifetime only**, like every
  other store in this app. A second container over the same instance models
  a relaunch and is tested; an OS process restart still loses it.

### Two notes on the working tree

- `dart format lib test` was run repo-wide and normalized three files this
  task did not otherwise touch:
  `lib/features/detachment/presentation/detachment_member_status_page.dart`
  and `test/core/theme/palette_contrast_test.dart` (both untracked
  work-in-progress) and `lib/core/theme/theme_controller.dart`. Whitespace
  only — `dart format` changes no semantics, and the suite and analyzer are
  green — but it is an unrelated diff, recorded here rather than left to be
  discovered.
- `needs_review_page_test.dart` renders Settings, which surfaces a
  **pre-existing** debug assertion (`ListTile` inside the decorated
  `_SettingsSection` — "background color or ink splashes may be invisible").
  It fires on `main` for every existing Settings row and was not introduced,
  or fixed, here; the test filters it narrowly, exactly as
  `detachment_group_flow_smoke_test.dart` already filters the known `GlassBottomNav`
  overflow.

### Task 5

Already complete (see §ZZZZZZ). Untouched by this session.

---

## ZZZZZZ. Latest session — 2026-09-04 (Attendance Edit Window + Append-Only Corrections — Task 5)

**Task 5 only**, implemented before Task 4 per explicit instruction. Task 4
(shift swap/cover requests) was **not started** — not read, not planned, not
touched.

`flutter analyze`: clean, whole project. `flutter test`: **345 pass / 0
fail** (full suite, up from 305 after Task 3 — 19 new in
`attendance_policy_test.dart`, 18 new in `attendance_correction_test.dart`, 3
new in `attendance_correction_sheet_test.dart`; every pre-existing shift/
capability/PDF/report test still passes unmodified in behaviour). `dart
format` applied to every touched file. `git diff --check` clean. `graphify
update .` run.

### What this session builds

A regular/sub-Admin (`Cap.shiftAttendanceRecord`) may record or edit a
shift's attendance for one hour after the shift ends. After that, ordinary
editing is read-only for that session. A Main Admin
(`Cap.shiftAttendanceOverride`) keeps working indefinitely, but only through
an **append-only correction** — the original attendance history is never
silently overwritten, every correction requires a reason, and the UI shows
who corrected what and why. Full contract:
`FRONTEND-BACKEND-INTEGRATION.md` §6.

### The one-hour boundary — decision and evidence

**Not a new decision.** Four independent, already-existing sources agree on
the exact same rule — shift end time (already correct for an overnight
shift, via `Shift.end`) plus exactly one hour:

1. `medical_team/lib/features/detachments/data/attendance_lock.dart`
   (`attendanceGracePeriod = Duration(hours: 1)`) — the legacy program's own
   executable rule, with its own boundary test suite this task's
   `attendance_policy_test.dart` mirrors (open at `end + 0:59:59`, closed at
   exactly `end + 1:00:00`, plus overnight and corrupt-data cases).
2. `LEGACY-EXTRACTION-REPORT.md` (D-16).
3. `CAPABILITIES.md` / `core/access/capability.dart` — `shift.attendance.record`
   already documented as "inside the one-hour window"; `shift.attendance.override`
   already documented as "after the one-hour lock" — both written before
   this session, for exactly this purpose.
4. `CAPABILITIES-REPORT.md` — cites "your legacy owner decision of
   2026-07-10" as the reason the two capabilities were split apart at all.

One deliberate, flagged divergence: MTM-PRO (a separate, unrelated project,
read-only reference) designed a *three*-layer scheme for its own unbuilt
backend (1h self-grace → 7-day gated window → permanent override). This
task's product-owner decisions specify only **two** layers, and are not open
for interpretation — the 7-day middle layer is intentionally **not** built
here. See `FRONTEND-BACKEND-INTEGRATION.md` §6 for the full citation trail.

Implemented as one pure function pair,
`lib/features/shift/domain/attendance_policy.dart`:
`AttendanceWindow.of(shift, now:)` (the boundary) and
`resolveAttendanceEditMode(window:, canRecord:, canOverride:)` (what the two
capabilities may do with it — `ordinary` / `correctionOnly` / `readOnly`).
No `DateTime.now()` inside either — `now` is always an argument, which is
what makes the whole boundary deterministically testable and cheap to change
later if the rule is ever revised.

### Capability behavior

Reused the existing `Cap.shiftAttendanceRecord`/`Cap.shiftAttendanceOverride`
keys and the existing presets — **no new capability, no `UserRole`, no
`role == mainAdmin` branch anywhere.** Both keys drive the ordinary path
while the window is open (a Main Admin uses the same controls a sub-Admin
does, not a separate admin path); only `shiftAttendanceOverride` continues
once the window closes, and then only through the correction method. Client
checks remain UX-only, exactly as this app's existing security contract
already states (`core/access/capability.dart`) — restated, not changed.

### Append-only model decision

New, minimal, owned entirely by the shift feature —
`lib/features/shift/domain/attendance_correction.dart`:
`AttendanceCorrection` (id, shiftId, memberId, before/after snapshots,
reason, author, correctedAt), `AttendanceSnapshot` (status +
checkIn/checkOut), `AttendanceCorrectionAuthor` (internal `id`, safe-for-UI
`displayName`), and `normalizeCorrectionReason` (trims, collapses
whitespace, rejects blank outright rather than accepting a placeholder).
`Shift` gained one field, `corrections: List<AttendanceCorrection>` (oldest
first) and a `correctionsFor(memberId)` helper — **not** on `TeamMember`,
because `TeamMember` already doubles as a workshop's organising-team
projection (`team_models.dart`'s own doc comment) and has no business
carrying shift audit data. The correction history is scoped to the
assignment (the shift), matching the existing precedent that attendance
state itself already lives there, not on the roster record.

### Files changed

New: `lib/features/shift/domain/attendance_policy.dart`,
`lib/features/shift/domain/attendance_correction.dart`,
`test/features/shift/attendance_policy_test.dart`,
`test/features/shift/attendance_correction_test.dart`,
`test/features/shift/attendance_correction_sheet_test.dart`.

Edited: `lib/features/shift/domain/shift_models.dart` (`Shift.corrections`),
`lib/features/shift/domain/shift_repository.dart`
(`addAttendanceCorrection` added to the interface),
`lib/features/shift/data/mock_shift_repository.dart` (window enforcement +
correction implementation + injectable `clock`),
`lib/features/shift/presentation/shift_assign_sheet.dart` (the attendance
sheet's three modes, correction form, and history section),
`lib/features/shift/presentation/shift_manage_sheet.dart` (threaded
`canOverride` so an override-only session can still open the sheet once the
window has closed), `lib/features/detachment/presentation/tabs/detachment_shifts_tab.dart`
(same threading, one layer up), `lib/l10n/strings.dart` (new Arabic strings),
`API_CONTRACT.md`, `FRONTEND-BACKEND-INTEGRATION.md` (new §6),
`DATA-NEEDS.md` (one glossary line).

Test-only, required by the new window enforcement (not a behaviour change):
`test/features/shift/schedule_test.dart` and
`test/features/shift/attendance_statistics_test.dart` now construct
`MockShiftRepository` with an injected clock frozen at the start of "this
week" — without it, a test picking an early-in-the-week seeded shift could
spuriously hit the new window check depending on what real day the suite
happens to run on. `test/features/shift/shift_manage_sheet_test.dart` gained
the same `canOverride` parameter its `showShiftManageSheet` call site now
requires, plus one latency-drain pump already used elsewhere in that file
(`member_assignment_sheet_test.dart`'s established pattern) for the test that
opens the attendance sheet.

### Repository behavior

`MockShiftRepository` gained an injectable `clock` (`DateTime Function()?`,
defaulting to `DateTime.now` — same pattern as `PendingOperation.create`/
`UuidV7`). The four ordinary mutation methods
(`recordCheckIn`/`recordCheckOut`/`markAbsent`/`resetAttendance`, and
`markAttendance` which dispatches to them) now share one choke point
(`_updateAttendance`) that checks `AttendanceWindow.of(shift, now: _clock())`
before doing anything else, returning `Failure(S.attendanceWindowExpired,
code: attendanceWindowExpiredCode)` — a typed, non-textual code, per the
task's requirement — without touching any state when denied.
`addAttendanceCorrection` is a new, separate method: validates the reason,
validates checkout-after-checkin (reusing the exact same overnight
normalization `recordCheckOut` already used, not a second copy of that
logic), appends one `AttendanceCorrection`, and only then updates the
member's effective attendance — both happen together, after every
validation has passed, so a failed call leaves both the effective state and
the correction history untouched (asserted directly in
`attendance_correction_test.dart`). It never checks the window itself,
matching "permit indefinite override only through the explicit override
method."

### UI behavior

`showAttendanceSheet`/`_AttendanceBody`
(`lib/features/shift/presentation/shift_assign_sheet.dart`) now renders one
of three modes:

- **`ordinary`** (window open): unchanged from before this task — the
  existing check-in/check-out pickers and status buttons — plus a
  `LockWindow` chip (`LockWindowState.open`, was already built and
  unwired anywhere except a static `home_page.dart` demo) showing the
  countdown.
- **`correctionOnly`** (window closed, override held): `LockWindow`
  (`sealed` — its pre-existing caption is literally "أضف تصحيحا") replaces
  the ordinary controls with a `إضافة تصحيح` action; the form reuses the
  same status buttons and date/time pickers as the ordinary path, plus a
  required reason field, and calls `addAttendanceCorrection`.
- **`readOnly`** (window closed, no override): `LockWindow` (`restricted` —
  "تعديل بصلاحية") plus `S.attendanceWindowClosedOrdinary` explaining why
  nothing here is editable. No dead controls, no hidden mutation path.

A compact `سجل التصحيحات` section (shown whenever a correction already
exists, or whenever the mode is not `ordinary`) lists every correction
newest-first: corrector name, timestamp, reason, and before/after attendance
— never the corrector's raw id.

### Local-first behavior

Not integrated with the outbox — a deliberate, documented deferral, not an
oversight. Grepping the whole `lib/features/` tree for `OutboxController`/
`PendingOperation.create` finds **zero** call sites anywhere in the app
today; no feature, shift attendance included, currently enqueues through it.
Per the task's own fallback instruction, the repository method
(`addAttendanceCorrection`) is already the clean seam a future outbox
integration would call — nothing about this session's UI or domain code
would need to change for that wiring to land later. Full reasoning:
`FRONTEND-BACKEND-INTEGRATION.md` §6.

### Privacy / security handling

`AttendanceCorrectionAuthor.id` is captured for internal traceability and
never rendered — only `.displayName` reaches a widget, asserted directly in
`attendance_correction_sheet_test.dart` (`findsNothing` for the raw id and
for the author's email). Client capability checks remain UX-only; the
backend must independently enforce both the capability and the time window
using server time — restated explicitly in `FRONTEND-BACKEND-INTEGRATION.md`
§6 because a correction/audit feature is exactly the surface where skipping
that would be a real gap, not a cosmetic one.

### What remains mock / provisional

Everything in this session is frontend/mock-only, per explicit scope. The
wire failure code for a denied ordinary edit
(`attendance_window_expired`) is the mock's own placeholder string, flagged
as `Backend contract decision required` in `FRONTEND-BACKEND-INTEGRATION.md`
§6 rather than assumed. The outbox/local-first integration is deferred, not
built (see above). No server enforces the window or the append-only rule —
both are honestly enforced by the mock for development/testing purposes
only, never a security boundary.

### Task 4

**Not started.** Not read, not planned. This session stops here per
instruction.

> Later correction (§ZZZZZZZ, 2026-09-05): "Task 4" as delivered is the
> **Needs Review inbox + durable conflict review foundation**, not the shift
> swap/cover requests this section guessed at from the roadmap ordering. The
> swap/cover work remains unstarted and unplanned.

**Task 3 only** (Optimistic Concurrency Backend Contract), resumed on top of
the Task 1 conflict screen and Task 2 outbox/conflict-state integration.
Primarily a documentation/contract task, as directed — no backend, no `/sync`,
no database, no resolution networking, no Needs-Review inbox were built.

`flutter analyze`: clean, whole project. `flutter test`: **305 pass / 0
fail** (301 from Task 2 + 4 new in `sync_conflict_classifier_test.dart`).
`dart format` applied to every touched file. `git diff --check` clean.

### Why this session, and what it actually resolves

Task 2 left four broad `Backend contract decision required` markers across
`FRONTEND-BACKEND-INTEGRATION.md` §3/§4 — no agreed `version` shape, no
agreed stale-write wire code, no agreed stale-write response contents, and no
agreed resolution/idempotency protocol for `useLocal`. Nothing about the
frontend's own behaviour was ever wrong; what was missing was a coherent,
evidenced answer a backend developer could implement against instead of
guessing. This session supplies that answer as a new
`FRONTEND-BACKEND-INTEGRATION.md §5 — Optimistic Concurrency & Stale-Write
Resolution Contract`, and updates `API_CONTRACT.md` / the older §3/§4 text so
nothing still calls a now-decided question "open."

### MTM-PRO evidence review

Read (read-only; nothing in MTM-PRO was modified) via a research pass over
`/home/ahmed/Documents/Python-Files/flutter/apps/MTM-PRO/mtm_app/`:
`CLAUDE.md`/`AGENTS.md` family, the `close-out/` decision-ledger documents,
`MTM-Unified-Roadmap.md`'s concurrency/idempotency/audit/tenant-isolation
sections, and the security skill set relevant to mobile/API security, secure
local storage, authorization, and idempotency (auth-assessment,
crypto-review, secure-storage-audit, privacy-audit, secure-mobile-dev-guide,
owasp-mobile-security-checker, mobile-threat-model, and related). Used
strictly as **evidence for how a comparable backend already reasoned about
the same problem**, never as an instruction to implement, never copied as
code, and never allowed to override an MTM-Front-Back ruling where the two
would conflict (none did). Concrete evidence points that shaped a decision
(see `FRONTEND-BACKEND-INTEGRATION.md` §5 for the full citations):

- A server-issued, DB-enforced `version bigint DEFAULT 1` counter — `xmin`
  explicitly rejected (lost on dump/restore, wraps around) — confirms §5.1's
  `version` token design.
- The equivalent concept `STALE_WRITE` (their casing) for exactly this
  condition — confirms §5.2's `stale_write` naming, translated into this
  project's existing lowercase `snake_case` `ProblemCode.wire` convention.
- A conflict response that inlines `serverState` alongside the code —
  confirms §5.3's "embed the current record by default" decision.
- Mandatory `Idempotency-Key`, a `same key/different hash → 422 key misuse`
  rule distinct from a version conflict, and a ~7-day retention window —
  confirms §5.5's "a resolution write needs a new key, not a resend under the
  old one" reasoning, and matches the retention figure this repo's own
  roadmap already carried.
- Tenant id read only from the verified JWT, never client-supplied context;
  an append-only, hash-chained audit log — confirms §5.7's authorization/audit
  requirements.
- A per-data-type conflict policy distinguishing status-field edits
  (version-checked), append-only ledger rows (structurally conflict-free),
  and shift double-booking (a DB exclusion constraint, unrelated to version)
  — confirms §5.1's inventory-movement exclusion and §5.9's shift-overlap
  scope boundary.

### The nine required decisions

All resolved except where explicitly and narrowly left open (see
`FRONTEND-BACKEND-INTEGRATION.md` §5 for full reasoning on every point below
— this is the short form):

1. **Concurrency token** — `version`: server-managed, wire JSON integer,
   frontend-opaque `String` (matches the existing `ConflictPresentation.
   baseVersion`/`currentVersion` type — no model change needed), starts at
   `1`, sent back as a body field (not a header), same mechanism for
   delete/archive. Append-only writes (`inventory.movement.add`) and
   server-computed fields are explicitly excluded — they cannot have a stale
   write by construction.
2. **Stable stale-write code** — `stale_write`, a new `ProblemCode` value,
   distinct from the pre-existing `conflict`. **Implemented**, not just
   documented — see "Code changes" below. The *in-progress* and
   *same-key-different-body* codes remain deliberately unresolved — see §5.2
   for why (they are a different failure shape and resolving them would need
   a `SyncState` surface change beyond this task's remit).
3. **Stale-write response contents** — a justified combination: always a
   `currentVersion`, `currentRecord` embedded by default using the entity's
   own ordinary read shape (reusing `presentShiftConflict`'s existing
   "two full typed records" design, no new diff-projection shape), reference
   -only fallback with an explicit note about the race that trades away.
4. **Conflict persistence boundary** — no new store: `conflictId :=
   operationId`, `PendingOperation` stays the durable record. One new,
   feature-owned, typed, encrypted "current-as-of-detection" snapshot is
   required (not implemented) so `reviewLater` works offline later; strict
   rules for what must never be persisted or displayed, and for removal
   timing (superseded on a newer `409`, deleted the moment the conflict
   resolves).
5. **Resolution protocol and idempotency** — `useLocal` becomes a **new**
   `PendingOperation` (new `operationId`/`idempotencyKey`, since its body
   genuinely differs) carrying a `resolvesOperationId` reference back to the
   original; create-then-retire ordering so a failed mint never loses the
   original conflicted operation. `useCurrent` sends nothing — there is
   nothing to submit. Today's `OutboxController.requeueAfterConflict` same
   -key reuse is documented as correct **only** because `OfflineSyncTransport`
   never actually sends anything — fixing it is explicit future work, not
   done here (`Explicitly forbidden` — no resolution networking).
6. **Meaning of the three intents** — restated precisely against §5's new
   ground truth; unchanged in substance from Task 1/2, no generic merge
   added.
7. **Authorization and privacy** — reauth is the ordinary token-expiry path,
   nothing special; tenant scope re-derived server-side at resolution time,
   never trusted from a cached snapshot; `ConflictUnavailablePage` is the
   correct fallback for access revoked since the conflict was created;
   auditability and safe-logging rules restated and tied to the new
   `resolvesOperationId` reference.
8. **Auto Sync / Manual Sync** — confirmed unchanged: already correctly
   implemented and proven by `auto_sync_no_navigation_test.dart`; nothing to
   redecide.
9. **Shift product context** — documented: shift conflicts are expected to be
   uncommon (one owner per shift) but the mechanism stays required for
   another device / Main Admin / stale offline copy / overlapping sessions;
   explicitly scoped away from `SHIFT_OVERLAP` (a different mechanism,
   MTM-PRO evidence: a DB exclusion constraint) and from inventory movements
   (structurally conflict-free).

### Code changes (small, aligning typed seams to decision #2)

- `lib/core/problem/problem.dart` — new `ProblemCode.staleWrite`
  (`'stale_write'`), documented against the pre-existing `conflict`.
- `lib/l10n/strings.dart` — `S.errStaleWriteTitle` / `S.errStaleWrite`
  (Arabic), styled like the existing `errConflict*` pair but distinct copy
  (points at reviewing differences, not "reload and retry").
- `lib/core/problem/problem_presentation.dart` — `resolveProblem()` gained
  `case ProblemCode.staleWrite:`, a required change once the enum grew (the
  switch is exhaustive) — generic modal fallback, `retryable: false` (unlike
  `conflict`'s `true`: resubmitting the same write against the same stale
  version is guaranteed, not just likely, to fail again).
- `lib/core/sync/sync_conflict_classifier.dart` — `defaultSyncConflictClassifier`
  now returns `ProblemCode.parse(problemCode) == ProblemCode.staleWrite`
  instead of always `false`. Compares through `ProblemCode.parse`, not a raw
  string, to keep one code vocabulary. Still inert in the shipped app: no
  real `SyncTransport` exists to ever produce this code.
- `lib/core/sync/sync_state.dart`, `outbox_controller.dart`,
  `sync_transport.dart` — doc-comment accuracy fixes only (they previously
  said "no production wire code classifies a push"; that is no longer true
  of the *code*, only of the *transport* — reworded precisely).
- `test/core/sync/sync_conflict_classifier_test.dart` — new, 4 focused tests:
  recognises `stale_write`; does not recognise `null`, the unrelated generic
  `conflict` code, or other/future/undecided codes.

No other production code changed. `ConflictPresentation`,
`ConflictResolutionDecision`, `OutboxController.requeueAfterConflict` /
`.discardConflict`, `presentShiftConflict`, and the conflict screen/route are
all **unchanged** — Task 3 documents what they will need once a transport
exists, but does not touch their behaviour, per the explicit "prefer no code
changes" / "do not implement resolution requests" instructions for this task.

### Verification

- `flutter analyze` — clean, whole project, before and after.
- `flutter test test/core/sync/ test/core/problem/ test/features/conflict/
  test/features/settings/manual_sync_settings_test.dart` — all pass,
  including every existing Task 2 conflict/outbox/idempotency test
  unmodified (the new classifier behaviour does not change any existing
  test's expected outcome: every existing test either overrides the
  classifier with its own private test code, or uses a code that is not
  `stale_write` and correctly stays `failed`).
- `flutter test` (full suite) — **305 passed, 0 failed**.
- `dart format` — applied to every touched `.dart` file.
- `git diff --check` — clean (see verification note at the end of this
  section for the exact command run).
- Manual cross-reference pass over `FRONTEND-BACKEND-INTEGRATION.md` §3/§4/§5,
  `API_CONTRACT.md`, and this entry: symbol names and file paths checked
  against the actual code, no remaining `Backend contract decision required`
  marker left pointing at something §5 actually decided.

### Documentation

- `FRONTEND-BACKEND-INTEGRATION.md` — new §5 (the bulk of this session's
  output); §3's "Conflict state model", the sync-result table, the "Mock /
  provisional" bullet, and its "Backend contract decision required" list all
  updated to point at §5 and to stop calling the stale-write code
  undecided; §4's "Frontend status", the `baseVersion`/`currentVersion`
  mock note, and its "Open decisions" list updated the same way; the index
  table gained a §5 row and corrected open-decision counts.
- `API_CONTRACT.md` — the "Errors" section gained a short `stale_write`
  paragraph (same treatment `upgrade_required` already gets: not part of the
  agreed `v1` contract yet, but the client already recognises it and the
  full contract lives in `FRONTEND-BACKEND-INTEGRATION.md`); the idempotency
  paragraph now also points at §5.
- This file — this section, plus the `§ZZZZZ` pointer at the top.

### Deferred / explicitly not built (unchanged from the task's own scope)

No backend API, no server-side optimistic concurrency, no database
constraint, no server `409` generation, no backend merge logic, no real
`/sync`, no cursors, no tombstones, no backend persistence, no server audit
infrastructure, no Needs-Review inbox, no generic merge engine, no resolution
networking. `OutboxController.requeueAfterConflict` was deliberately left
exactly as Task 2 wrote it — see §5.5's explanation of why that is correct
today and wrong the moment a real transport exists.

### Genuinely unresolved external facts

None required a business/legal/organizational answer this session could not
safely infer from repository evidence. The two items left open (the
*in-progress* and *same-key-different-body* wire codes, §5.2) are not
"unavailable facts" — they are a deliberate scope boundary: resolving them
would mean adding a third `SyncState` bucket for a client-protocol fault
distinct from both `failed` and `conflict`, which is a surface change beyond
"align a typed constant," and Task 3's required-decision list named only the
stale-write code. A future session should treat that as its own small,
explicit decision rather than something Task 3 silently expanded into.

---

## ZZZZ. Latest session — 2026-09-04 (Conflict/Outbox integration — Task 2)

**Task 2 only** (Outbox Conflict State + Sync Integration Seam), resumed on
top of the Task 1 conflict screen. Task 3 was **not** started (not asked for).

`flutter analyze`: clean, whole project. `flutter test`: **301 pass / 0
fail**, full suite (282 from Task 1 + 19 new/updated this session). `dart
format` applied to every touched file. `git diff --check` clean. Frontend
only — no backend, no real `/sync`, no server-side conflict generation.

### State-model decision

Added exactly **one** new `SyncState` value: `conflict`
(`lib/core/sync/sync_state.dart`). Rejected the alternatives the prompt
offered:

- **Adding both `conflict` and `needsReview` to the enum.** The roadmap's own
  original comment defined them as two different things — `conflict` is a
  *per-operation* stale-write verdict, `needsReview` was reserved for a
  *durable, cross-conflict inbox*. Task 2 does not build an inbox (explicitly
  out of scope), so a `needsReview` **state** would have no distinct meaning
  from `conflict` yet and would just be a second name for the same thing.
  `needsReview` survives instead as a `bool` convenience getter
  (`SyncState.needsReview` / `PendingOperation.needsReview`, `true` only for
  `conflict`) and as the aggregate `SyncRunOutcome.needsReview` — the run-level
  signal Settings/Manual Sync render — so the word is used precisely rather
  than doubled.
- **A separate "review disposition" structure.** Not needed: `reviewLater`
  from the Task 1 screen already has an exact meaning under this model — do
  nothing, the operation stays `conflict`. No extra field or type was
  required to represent that.

`SyncState` gained two predicates, both delegated onto `PendingOperation`:

- `isRetryable` — `true` for `pending`/`syncing`/`failed`, `false` for
  `conflict`. This is what `SyncCoordinator._run` now filters the queue on
  (previously `isUnsynced`), so a conflicted operation is never picked up by
  the ordinary retry loop.
- `needsReview` — `true` only for `conflict`.
- `isUnsynced` (existing) is unchanged in meaning (`!= synced`) and still
  includes `conflict` — it answers "still outstanding", not "should be
  retried".

### Classification seam (no wire code invented)

New file `lib/core/sync/sync_conflict_classifier.dart`: a
`SyncConflictClassifier = bool Function(String? problemCode)` seam
`SyncCoordinator` calls on every `Failure` before deciding `failed` vs
`conflict`. `defaultSyncConflictClassifier` — the one wired in the shipped
app — always returns `false`. `FRONTEND-BACKEND-INTEGRATION.md` §3 already
marked the *in-progress* / *invalid-reuse* wire codes as `Backend contract
decision required`; this session did not resolve that decision, so nothing
in the shipped app can transition an operation into `SyncState.conflict`
today. Tests override `syncConflictClassifierProvider` with a private test
code (`test_only_stale_write`) that will never collide with a real backend
value, and exercise the full transition honestly without asserting what the
real code will be.

### Preservation of operation / idempotency identity

`OutboxController.applyOutcome` already generically supported any non-synced
state, so classifying a `Failure` into `conflict` reuses that exact path —
same `operationId`, same `idempotencyKey`, no new record, no new store write
path. Verified directly: `conflict_outbox_test.dart` tests 1+2 assert the
stored `operationId`/`idempotencyKey`/`kind`/`entityId` are byte-identical
before and after the transition, and `conflict_outbox_resolver_test.dart`
asserts the same across a `useLocal` requeue.

### Auto Sync behaviour

Unchanged in shape, changed in effect: `SyncScheduler.request()` still only
calls `SyncCoordinator.syncNow(trigger: auto)` — it has no reference to
`GoRouter`, `context`, or any navigator, so it was structurally incapable of
navigating before this session and still is. What Task 2 adds is that a
`Failure` the classifier recognises now lands the operation in `conflict`
(a quiet state change) instead of endless `failed` retries, with **no**
route push, dialog, or navigation of any kind. New widget test
`test/core/sync/auto_sync_no_navigation_test.dart` proves this against a
real `GoRouter` instance: it seeds a conflict-classified failure, calls the
same `SyncScheduler.request()` `main.dart` calls on launch/resume, and
asserts the router is still on `/home` (not `/conflicts/...`) while
independently confirming the operation really did become `conflict` (so the
test is not vacuous).

### Manual Sync behaviour

`SyncCoordinator._run`'s per-op `failure` branch now asks the classifier
before deciding `failed` vs `conflict`; a classified conflict sets a new
`hitConflict` flag instead of `hitFailure`. `SyncRunOutcome` gained
`needsReview`, surfaced by `SyncSettingsSection._syncNow`'s existing outcome
switch as `S.syncNeedsReviewNote` ("توجد تغييرات تحتاج مراجعة قبل إكمال
المزامنة.") — distinct from the generic `S.syncFailedNote`, so a stale-write
conflict is never shown as a scary generic failure. Manual Sync still drains
the exact same `outboxProvider` through the exact same `SyncCoordinator` —
nothing new was introduced on that path.

### Settings changes

`SyncSettingsSection` (`lib/features/settings/presentation/widgets/`) gained:

- `conflictOperationsCountProvider` (new, `outbox_controller.dart`) watched
  alongside the existing `pendingOperationsCountProvider`. The latter now
  filters on `isRetryable` instead of `isUnsynced`, so a conflicted operation
  is no longer double-counted into "بانتظار المزامنة" — it has its own line.
- A quiet `_ConflictAttentionRow` (key `sync-conflict-attention`), shown only
  when the conflict count is `> 0`: "تغيير واحد يحتاج مراجعة" /
  "%d تغييرات تحتاج مراجعة" on a `c.warnTint` background — the same
  warning treatment Task 1's conflict screen uses for its intro icon.

**Deliberately not built:** a tap action on that row. Building a real
`ConflictPresentation` needs the feature's own typed local/current records
(exactly what `presentShiftConflict` does for a `Shift`) — a generic,
payload-free `PendingOperation` does not carry them, and there is no
Needs-Review inbox or live per-feature trigger to route a tap into yet.
Wiring a button to nothing honest would violate prompt §5/§9 ("do not
fabricate backend conflicts as production behaviour"). Settings otherwise
stays fully usable: the sync-now button and every navigation row keep
working while conflicts are outstanding (`manual_sync_settings_test.dart`,
"Settings stays usable while conflicts exist").

### Problem integration seam

Not touched beyond what `sync_conflict_classifier.dart` documents. §2's
`ProblemCode.conflict` (`'conflict'`, `HTTP 409`) is a **different** concept
— "someone else changed this record" for an ordinary request/response call —
from the sync-retry stale-write case this task's classifier is for (a
`409`/`422` on an *idempotent retry* whose exact wire code
`FRONTEND-BACKEND-INTEGRATION.md` §3 still marks undecided). The classifier
seam exists precisely so the two are never accidentally conflated by reusing
one wire string for both.

### Retry behaviour

`SyncCoordinator._run`'s `pending` list now filters on
`PendingOperation.isRetryable`, so a `conflict` operation is skipped by
every subsequent Auto or Manual run — proven by
`conflict_outbox_test.dart`'s "a conflicted operation is not retried
indefinitely" (three runs, transport pushed once). A generic (unclassified)
`Failure` is completely unaffected: same `failed` state, same retry-forever
behaviour as before Task 2 (test "generic temporary failures keep their
pre-Task-2 behaviour").

### Conflict resolution intent seam

New `lib/features/conflict/data/conflict_outbox_resolver.dart`:
`applyConflictResolution(ref, decision)` and the
`conflictDecisionHandlerProvider` it backs. Turns a Task 1
`ConflictResolutionDecision` into outbox calls only — no network, no claim of
server success:

- `useLocal` → `OutboxController.requeueAfterConflict` (conflict → pending,
  same identity, no push attempted here).
- `useCurrent` → `OutboxController.discardConflict` (removes the pending
  write; never contacts the transport).
- `reviewLater` → no call at all — leaving the operation alone **is** the
  preservation behaviour.

Not wired to a live call site: exactly as Task 1 left it, nothing in `lib/`
opens `ConflictResolutionPage` yet, so `conflictDecisionHandlerProvider` has
no real `onDecision` to be passed to today. It exists, is fully tested
(`conflict_outbox_resolver_test.dart`), and is ready for whatever future
conflict-detecting integration opens the route.

### Tests added/updated this session

- `test/core/sync/conflict_outbox_test.dart` (new, 10 tests) — prompt §10
  items 1, 2, 3, 6, 8, 9 plus the useLocal/useCurrent/reviewLater seam and
  the `needsReview` run outcome.
- `test/core/sync/auto_sync_no_navigation_test.dart` (new) — item 4.
- `test/features/conflict/conflict_outbox_resolver_test.dart` (new) — the
  decision → outbox bridge, all three intents.
- `test/features/settings/manual_sync_settings_test.dart` (+3 tests) — items
  6, 7, and the honest `needsReview` snackbar note.
- `test/core/sync/pending_operation_test.dart` — updated the Task-1-era
  "`'conflict'` is unknown" assertion, since it is now a real, recognised
  value (item 10); added `isRetryable`/`needsReview` coverage; `'needsReview'`
  remains the genuinely-unknown probe.
- Full existing suite (local-first sync, manual sync widget tests, Task 1
  conflict screen/router tests) re-run unmodified where not listed above —
  items 5, 11, 12 all pass with no changes needed.

### Deferred / mock work (unchanged or newly explicit)

- No production wire code classifies anything as a conflict — the shipped
  classifier always returns `false` (§3 "Backend contract decision required"
  still open).
- No Needs-Review inbox; no tap-to-review action in Settings (see "Settings
  changes" above).
- `useLocal`/`useCurrent` never talk to a server and never claim a server
  outcome — `useLocal` only re-queues for the *next* ordinary sync attempt;
  `useCurrent` only stops asking the server for that write.
- `ConflictResolutionDecision.currentVersion` is still carried by the Task 1
  model but nothing in this task's outbox seam reads or attaches it to a
  retried request — that is real transport work, out of scope here and
  dependent on the still-open `baseVersion`/`currentVersion` shape decision
  (§4 open decisions).
- No adapter beyond the existing `presentShiftConflict` was added or needed
  — Task 2 never builds a `ConflictPresentation`.

### Documentation

- `FRONTEND-BACKEND-INTEGRATION.md` — §3 updated (state model, classifier
  seam, retry-loop change, count providers, backend-decision note
  unchanged/still open) and §4 updated ("Frontend status", the outbox
  resolver as the new integration point, "Open decisions" #3/#4 narrowed to
  what is now actually true). Index table refreshed.
- This file — this section, plus the `§ZZZZ` pointer at the top.

---

## ZZZ. Latest session — 2026-09-04 (Conflict UX Task 1 — review, fixes, docs)

**Task 1 only** (Conflict UX Design + Frontend Screen Foundation), resumed
from a prior interrupted session whose documentation patch had not applied.
The implementation already existed in the working tree; this session
independently reviewed it against the original requirements, fixed what it
found, and wrote the missing documentation. **Task 2 was not started.**

`flutter analyze`: clean, whole project. `flutter test`: **282 pass / 0 fail**,
full suite (includes one new regression test added this session). `dart
format` applied to every Task 1 file (no changes needed — already formatted).
`git diff --check` clean. Frontend only.

### What existed already (verified correct, unchanged)

- `lib/features/shift/presentation/shift_conflict_adapter.dart`,
  `lib/core/router/app_router.dart`'s `/conflicts/:conflictId` route,
  `lib/l10n/strings.dart`'s conflict-resolution string block, and
  `test/core/router/app_router_test.dart`'s `/conflicts/c1` location. Reviewed
  line-by-line; no correctness, RTL, routing, or privacy defect found — left
  as-is.
- The differences-first design (Option B), the three typed intents
  (`useLocal`/`useCurrent`/`reviewLater`, deliberately no `merge`), the
  `PopScope`/`_allowPop`/deferred-pop fix for the "repeated reviewLater on a
  root route" bug, and the opaque-identity privacy model
  (`ConflictPresentation` never carries a raw backend field or JSON) — all
  verified against the code and the existing test suite (11 widget tests + 3
  router tests, all passing at session start).

### Fixes made this session

1. **Accessibility — double semantics announcement.** `_VersionLabel` and
   `_ConflictValue` in `conflict_resolution_page.dart` each wrapped their
   visible `Text` children in a `Semantics(container: true, label: …)` with no
   `ExcludeSemantics`. Every other composed-label widget in the app
   (`_ChoicePill` in `settings_page.dart`) wraps its child in `ExcludeSemantics`
   specifically so a screen reader announces the composed label once instead
   of the label followed by the same text again from the descendant nodes —
   this pair did not follow that pattern. Fixed by wrapping both in
   `ExcludeSemantics`, matching the established convention. New regression
   test: `version legend and value cells announce their composed label once`
   (asserts the composed label is reachable by `bySemanticsLabel` and the bare
   title/subtitle/value strings are not).
2. **Lint cleanup** (`flutter analyze` was not clean on these files before this
   session): `conflict_models.dart` — `assert(differences.length > 0)` →
   `assert(differences.isNotEmpty)` (`prefer_is_empty`).
   `conflict_resolution_page.dart` — hoisted `const` onto the `_VersionLabel`
   declarations and their enclosing `Column`/`Row` in `_VersionLegend`
   (`prefer_const_declarations` / `prefer_const_constructors`).

### Reviewed and found already correct (no change made)

- **State preservation on exit.** Confirmed every exit path (button tap,
  system back, AppBar back, failed callback) resolves through `onDecision`
  before the screen closes, or keeps the screen open on failure — unresolved
  local work is never silently discarded. See
  `FRONTEND-BACKEND-INTEGRATION.md` §4 "How unresolved conflicts are
  preserved" for the full trace.
- **Privacy.** No raw JSON, backend field name, or hidden identifier reaches
  the generic screen; `entityType`/`entityId`/`baseVersion`/`currentVersion`
  are carried but never rendered. Existing test already plants
  backend-looking strings in every non-display field and asserts none render.
- **Routing.** The route sits on the root navigator beside the forced-upgrade
  gate, inherits the router's one `redirect` with no special-casing, and
  falls back to `ConflictUnavailablePage` on a stale/missing `extra` rather
  than crashing or fabricating a conflict.
- **Scope discipline.** Confirmed by search: nothing anywhere in `lib/`
  outside the conflict feature and the router calls
  `presentShiftConflict`/`ConflictResolutionRouteArgs`/
  `ConflictResolutionPage.locationFor` — Auto Sync, Manual Sync, and every
  other feature are untouched, so "Auto Sync must never navigate here" holds
  by construction today. No outbox `conflict` state, Needs-Review inbox, or
  other-domain adapter was added, per the task's explicit exclusions.

### Documentation

- `FRONTEND-BACKEND-INTEGRATION.md` — new **§4 Conflict Resolution UX**
  (design options considered and rejected, product model, integration point,
  preservation guarantee, privacy/accessibility notes, mock/provisional
  pieces, open backend decisions). Index table updated.
- This file — this section, plus the `§ZZZ` pointer at the top.

### Deferred / not built (explicitly out of scope for Task 1)

Conflict *detection*, any outbox `conflict`/`needsReview` state, a
Needs-Review inbox, real sync, and adapters for domains other than shift. See
`FRONTEND-BACKEND-INTEGRATION.md` §4 "Removal / follow-on during integration"
and "Open decisions."

---

## ZZ. Latest session — 2026-09-04 (local-first write foundation + forced-upgrade cleanup)

Two tasks from one prompt, **both complete**. `flutter analyze` clean (whole
project); `flutter test` **270 pass / 0 fail** (was 242 at session start).
`dart format` applied to touched files; `git diff --check` clean. **Frontend
only — no backend code, no full sync engine.**

### ZZ.1 Local-first write / idempotency-ready sync foundation

- **Architecture chosen: C** — one shared lightweight local write-operation
  primitive in `lib/core/sync/`. Rejected A (network layer mints a key per
  request — there is no network layer, and a per-attempt key cannot survive a
  restart) and B (each feature owns write identity — fragments the one pending
  set Auto + Manual Sync must share, fights the "shared primitives are Core"
  grain). C matches the repo's own seam idiom (`abstract *Store` + in-memory
  mock + overridable `Provider`, exactly like `AppVersionGateStore`). No
  equivalent primitive existed (searched mutation/command/outbox/change-log/
  dirty-state/sync-metadata). Full rationale + integration points:
  `FRONTEND-BACKEND-INTEGRATION.md` §3 (new).
- **New — `lib/core/sync/`:**
  - `sync_state.dart` — `SyncState { pending, syncing, synced, failed }`.
    `conflict` / `needsReview` documented as deferred; `SyncState.fromWire`
    keeps an unknown state as `pending`, never "done".
  - `uuid_v7.dart` — RFC 9562 UUIDv7 (`Random.secure()`, `dart:math`, **no new
    dependency**; monotonic per-ms counter; injectable `Random`/clock for
    tests), `uuidV7()`, `isUuidV7()`.
  - `pending_operation.dart` — `PendingOperation`: `operationId` +
    `idempotencyKey` (one UUIDv7, minted once, never regenerated), `kind`
    (namespaced tag), opaque `entityType`/`entityId`, `createdAt`, `state`,
    attempt bookkeeping (`attemptCount`, `lastAttemptAt`, `lastProblemCode` —
    **wire code only**). **No payload field** — payloads stay with the
    feature's own storage / future SQLCipher tables.
  - `outbox_store.dart` — `OutboxStore` (seam) + `InMemoryOutboxStore` (mock,
    lifetime-of-object; real impl → SQLCipher `pending_operations`).
  - `outbox_controller.dart` — `OutboxController`/`outboxProvider`
    (`AsyncNotifier`, hydrates from the store), `enqueue(...)` is **the single
    identity-creation point**; `outboxStoreProvider`, `newOperationIdProvider`
    (test seam), `pendingOperationsCountProvider`.
  - `sync_transport.dart` — `SyncTransport` (seam; where a real impl attaches
    `Idempotency-Key`) + `OfflineSyncTransport` (every push → `Offline`, so no
    fabricated success is possible today).
  - `sync_coordinator.dart` — `SyncCoordinator`/`syncCoordinatorProvider`
    (`Notifier<SyncStatus>`), `syncNow({trigger})` is **the one engine both
    paths call**; re-entrancy guard (`_inFlight` future) so a flapping signal
    or a manual tap during an auto run cannot fan a write out twice; never
    creates a `PendingOperation`. `SyncTrigger { auto, manual }` — audit only,
    behaviour identical. `syncTransportProvider`.
  - `sync_scheduler.dart` — `SyncScheduler`/`syncSchedulerProvider`, the Auto
    Sync trigger seam. `main.dart` calls `onAppStart()` (post-first-frame) and
    `onAppResumed()` (on `AppLifecycleState.resumed`). No connectivity trigger
    (no connectivity plugin in deps — documented as the next hook).
- **Settings surface:** new `SyncSettingsSection`
  (`features/settings/presentation/widgets/sync_settings_section.dart`), placed
  in `settings_page.dart` under a new `S.sectionSync`. Shows plain-language
  state + pending count (`٣ تغييرات بانتظار المزامنة`) + last-sync line + a
  `مزامنة الآن` button. Button disabled while syncing; the rest of Settings
  navigation stays live. Honest feedback only — with the offline transport the
  snackbar says "لا يوجد اتصال…", never a fake "اكتملت المزامنة". No ids /
  keys / wire codes anywhere in the UI.
- **Representative integration:** `detachment_storage_tab.dart`
  `_ItemSheetBodyState._record()` — after the local `addMovement` succeeds it
  `enqueue`s a `PendingOperation` (`kind: 'inventory.movement.add'`,
  `entityType: 'inventory_item'`, `entityId`), `unawaited`-nudges
  `SyncScheduler.request()`, pops the sheet and shows `S.savedPendingSync`
  ("تم الحفظ · بانتظار المزامنة"). Nothing waits on a server. Every other
  write in the app is unchanged — the same one-line adoption is available to
  them.
- **Strings:** `strings.dart` new "Sync (local-first writes)" block.
- **7-day rule:** NOT implemented on the frontend. No timer. Recorded in
  `FRONTEND-BACKEND-INTEGRATION.md` §3 as backend-owned retention; the local
  outbox keeps an op until it is `synced`.
- **Security (scoped):** `PendingOperation` has no payload / header / token
  field; only a wire `code` is retained on failure, never server `detail`;
  no id / key is shown in the UI (test asserts a `Bearer …` / `SQLSTATE …`
  failure message never reaches the stored record).
- **Tests (+27):** `test/core/sync/{uuid_v7,pending_operation,local_first_sync}
  _test.dart`, `test/features/settings/manual_sync_settings_test.dart`,
  `test/features/inventory/local_first_movement_test.dart`. Cover: local write
  with no server, identity stable across auto+manual+restart retries, one
  engine / one queue, no duplication, offline ≠ data loss, unknown backend
  code passes through as code-only, re-entrancy = one run, RTL Settings,
  no-fake-success, sync button busy ≠ nav locked.

### ZZ.2 Forced Upgrade cleanup (did **not** redesign the feature)

- **Build/version identity.** The persisted gate was keyed on
  `AppInfo.version` (display SemVer `1.0.0` only). Added
  `AppInfo.buildIdentity = '1.0.0+1'` — the full `pubspec.yaml` `version:`
  string (`versionName+versionCode`) — and keyed
  `PersistedUpgradeGate.blockedVersion` on it
  (`AppVersionController._restorePersistedGate` / `_persistVerdict`). So a
  hotfix that keeps the SemVer but bumps the build number is a different
  binary and does not inherit the old build's `426`. `AppInfo.version`
  (SemVer) still drives the screen text and `X-Client-Version`. Both held to
  `pubspec.yaml` by the drift test. New test: "same version, different build
  number ⇒ not inherited".
- **Legacy `updateUrl`.** **Removed.** `AppVersionSupport.updateUrl` and
  `AppVersionState.updateUrl` deleted; `UpdateDestination.open()` /
  `resolvedDestination()` lost their `overrideUrl` param;
  `AppVersionController.openUpdateDestination()` passes nothing.
  Evidence for removing rather than keeping: the field sat on the
  *backend-response* model, implying the backend owns the update destination —
  which directly contradicts the already-resolved "destination is
  client-owned" decision, so every reference had to carry a "but not really"
  caveat. Its only justification was hypothetical edge cases (sideloaded
  enterprise build, moved listing) with no product driver — `com.mtm.mtm` is a
  fixed Play listing, there is no iOS target, no enterprise channel. And a
  wire-controlled launch target that `open()` would hand to a launcher is a
  redirect risk. `AppVersionSupport.fromJson` now simply ignores an incoming
  `updateUrl` (unknown-member-dropped, like `Problem.fromJson`), so a future
  server that sends one does not break the client. Test replaced: "an
  `updateUrl` on the wire is ignored — destination stays client-owned".
- Docs: `FRONTEND-BACKEND-INTEGRATION.md` §1 (Required-backend-data table +
  Open-decisions/Resolved rewritten — down to 2 open items), `API_CONTRACT.md`
  (idempotency note).

### ZZ.3 Unresolved — `Backend contract decision required`

`FRONTEND-BACKEND-INTEGRATION.md` §3: wire `code` strings for *in-progress* /
*invalid-reuse*; final `Idempotency-Key` header name; server retention window
+ whether the client is told a key expired; `/sync` upload single-vs-batch and
per-op result shape. §1: what identity the *server* compares (SemVer? +platform
+build? hash?) and whether `X-Client-Version` should carry more; `426` body
shape / `minimumVersion` placement; endpoint-vs-any-request for the check.

---

## Z. Latest session — 2026-09-04 (forced-upgrade finalization + Problem/error foundation)

Two requests, **both complete**. `flutter analyze` clean (whole project);
`flutter test` **242 pass / 0 fail** (was 198 at session start). `dart format`
applied to the touched files. Frontend only — **no backend code added**.

### Z.1 Forced Upgrade — finalization (feature was untracked/new, not redesigned)

- **Update action is no longer "copy a URL".** The update destination is
  **client-owned**: new `UpdateChannel`
  (`features/app_version/domain/update_channel.dart`) holds per-platform
  store/update links (`androidStore` real for `com.mtm.mtm`; `iosStore` empty —
  no iOS target; `webFallback` placeholder). `UpdateDestination.open()` no
  longer takes the backend URL — it resolves `UpdateChannel.forPlatform` and
  takes `AppVersionSupport.updateUrl` only as an *optional override*. The
  launcher-less dev build still copies to the clipboard (`UpdateLaunchOutcome`
  unchanged); production returns `opened`. Rationale: the destination is a fact
  about how the client shipped, identical for every user, needed with no
  network — so a `426` body never has to carry it, and a hostile `updateUrl`
  can't redirect off-store. Closes former open decision 2 in
  `FRONTEND-BACKEND-INTEGRATION.md` §1.
- **The gate now survives an offline restart.** New tiny seam
  `AppVersionGateStore` + `PersistedUpgradeGate`
  (`features/app_version/domain/app_version_gate_store.dart`), mock
  `MockAppVersionGateStore` in-memory (same limitation as
  `MockSettingsRepository`), `appVersionGateStoreProvider`.
  `AppVersionController.check()` now: (1) before the network call, when not
  already blocking, restores a persisted verdict **keyed to
  `AppInfo.version`** — a build previously told `426` re-enters the gate even
  with no network; (2) after a check that *reaches a verdict*, persists it
  (`supported` → clear). A stored verdict whose version string ≠ the running
  build is stale → ignored and cleared, so a fix shipped as a new version is
  not blocked by the old one. An unreadable store **fails open** (offline-first
  rule preserved). Deliberately NOT on `SettingsRepository` — that is
  user-chosen settings; a forced-upgrade verdict is a cached server answer.
  Real impl writes it to the same ordinary local-prefs bucket (`DATA-NEEDS.md`
  §3.3).
- Tests: `test/features/app_version/forced_upgrade_test.dart` — 15 original
  kept unchanged + 13 new (persisted-gate cases 1/2, verdict persist/clear,
  stale-version drop, failed-recheck-no-overwrite, relaunch-over-same-store,
  unreadable-store-fails-open; client-owned destination + override + platform +
  controller-with-no-backend-url).

### Z.2 RFC 9457-ready Problem / error UX foundation

- **Architecture: C — hybrid.** Evidence: `Result` / `AsyncResultView` /
  `ErrorStateView` are already shared Core primitives; `mock_shift_repository`
  already owns its own domain codes → its own `S.*` copy at its own call site;
  Forced Upgrade is already a Core-owned global blocking state; Riverpod has no
  global interceptor (errors travel per-provider as `Result`). A central
  resolver (A) would become the god object the feature folders avoid; a purely
  feature-owned model (B) would duplicate the shared widgets. Core owns the
  bounded set of app-wide conditions (a plain `switch`, not a registry);
  features own domain codes at their own `Result`/`Problem` sites and fall back
  safely for anything Core doesn't enumerate.
- **New:** `lib/core/problem/` — `problem.dart` (`Problem` RFC 9457-shaped +
  typed extensions `fieldErrors`/`reference`, no untyped map; `ProblemCode`
  enum with `wire` strings matching `API_CONTRACT.md`; `Problem.fromJson`
  parses RFC 9457 *and* tolerates the interim `{error:{…}}` envelope, drops
  unnamed members), `problem_presentation.dart` (`ProblemView`,
  `ProblemSurface` = field/inline/transient/modal/fullScreen, `resolveProblem`),
  `problem_result.dart` (`Result.problemOrNull` bridge — `Result` unchanged).
- **Representative integration:** `AsyncResultView` failure branch (~25
  screens) now renders MTM-owned localized copy for known codes, the generic
  fallback (`تعذر إكمال العملية`) for an unrecognised code, and **never** the
  raw wire `message`. Debug builds `debugPrint` an unhandled code + detail;
  release is silent. Feature mutation surfaces (form sheets, snackbars) are
  untouched — they adopt `problemOrNull` incrementally.
- **Not built** (foundation only, per prompt §15): session-terminated
  auto-routing, shift-overlap sheet, stale-write merge, cursor-expired,
  needs-review, FEFO UI, subscription suspension. `authentication_expired` is
  *classified* (full-screen, `S.sessionExpired*`) but nothing auto-navigates
  yet — extension point is `resolveProblem` + the existing `/session-expired`
  route.
- **Strings:** `strings.dart` new "Problem / error taxonomy" block.
- **Security (scoped to the error flow):** `Problem` has no field for headers /
  tokens / PII; `fromJson` reads only whitelisted keys and drops the rest;
  `detail`/`title`/`type`/`instance` are never shown for a known code (test:
  a fake `SQLSTATE … token=Bearer …` detail never reaches `ProblemView.message`
  for any code); unknown code → generic copy, not the server string; `reference`
  shown only on modal/full-screen, never on a field error.
- Tests: `test/core/problem/{problem_test,problem_presentation_test,async_result_problem_test}.dart`
  (31).
- Docs: `FRONTEND-BACKEND-INTEGRATION.md` §2 (new, full handoff),
  `API_CONTRACT.md` "Errors" (RFC 9457-ready note + open items).

### Z.3 Unresolved — `Backend contract decision required`

`FRONTEND-BACKEND-INTEGRATION.md` §1: `426` body shape / `minimumVersion`
placement; what answers the check (endpoint vs any-request); version-comparison
identity (semver vs +build). §2: whether the envelope becomes literal RFC 9457
members; field-error key shape; the safe support-reference field name.

---

## A. Latest session — 2026-09-03 (detachment status + more themes)

Two requests, **both complete**. Latest verification after the theme follow-up:
`flutter analyze lib test` clean; `flutter test` **183 pass / 0 fail**;
`git diff --check` clean.

### A.1 Detachment "status" + storage status, and a per-member status page

- **Status strip in the detachment detail shell** — new `_StatusStrip` in
  `features/detachment/presentation/detachment_detail_shell.dart`, shown under
  the app bar on all four tabs. Two `StatusChip`s:
  - lifecycle: نشطة / مؤرشفة (this is the "status" the legacy `medical_team`
    details header carried — brought across).
  - storage: a **derived worst-wins rollup** of the detachment's stock —
    `features/detachment/domain/storage_status.dart`, `StorageStatus`
    { empty, healthy, expiring, low, depleted } via `storageStatusOf(items)`.
    Precedence depleted > low > expiring > healthy. Not a stored field, no
    wire enum. Memory: `mtm-storage-status-rollup`.
- **Member status page** — new
  `features/detachment/presentation/detachment_member_status_page.dart`,
  route `/detachment/:id/member/:memberId/status`. Tapping a roster card in
  the Team tab now opens this (was: straight to the edit form); editing is an
  app-bar icon gated on `Cap.memberEdit`. Shows the member's current
  attendance state, week/month/quarter range chips, present/absent/completed/
  percent totals, and **one card per shift day** (weekday+date, center,
  status chip, `الدخول HH:MM · الخروج HH:MM` forced LTR, or "بلا تسجيل دخول").
  Data: existing `attendanceStatisticsProvider` filtered to one member — no
  new provider, numbers match the stats tab.
- `detachment_team_tab.dart` `_openMember` → `/status`.
- `strings.dart` — new keys: `detachmentStatusStrip`, `storageStatus*` (5),
  `memberStatusTitle`, `memberStatusCurrent`, `memberAttendanceLog(+Sub)`,
  `noAttendanceRecords(+Sub)`, `notCheckedInShort`.
- `test/core/router/app_router_test.dart` — added the `/status` location.

### A.2 More themes + eye-protect mode

- **Palettes: 3 → 6.** `PaletteId` is now
  `{ medical, slate, copper, clay, indigo, teal }` in
  `core/theme/app_palette.dart`, each with a full light + dark `AppColors`
  const. **`medical` is the new default** (clean clinical green on white) —
  `ThemeState.initial()` selects it in light mode. `indigo` (cool blue) and
  `teal` are the two new alternates; `slate`/`copper`/`clay` are unchanged.
  `AppColors.resolve` is exhaustive; no code uses `PaletteId.index`.
- **Eye-protect mode** — `AppColors.warmed()`: a warm, low-blue lerp toward
  amber applied to the **ground only**: backgrounds, surfaces, lines and
  status tints. Ink, primary and semantic foreground colours stay unchanged,
  preserving legibility and meaning. It is **orthogonal** to palette and to
  light/dark — `ThemeState.eyeProtect` (bool, default false),
  `ThemeController.setEyeProtect`; `main.dart` passes `theme.eyeProtect` into
  both `AppTheme.light` and `AppTheme.dark`.
- **Settings UI** (`features/settings/presentation/settings_page.dart`) —
  palette row loops over all 6 and each pill previews the palette's primary
  colour at the brightness currently on screen. The mode row exposes light,
  dark **and System** (`S.settingsModeSystem`). The new "حماية العين"
  `_PickerRow` has مفعّلة / متوقفة pills. `_ChoicePill` is a selectable
  button semantics node with its tap action registered, so TalkBack can
  announce and activate it.
- `strings.dart` — `settingsPaletteMedical` / `Indigo` / `Teal`,
  `settingsEyeProtect(+Sub)`, `settingsEyeProtectOn` / `Off`.
- `test/features/detachment/detachment_group_flow_smoke_test.dart` — the "every palette
  resolves" test now also loops `eyeProtect ∈ {false, true}`, so it covers
  all 6 palettes × 2 modes × 2 washes and exercises `warmed()`.
- **Theme settings seam** — `ThemeState` moved to
  `core/theme/theme_state.dart`; `ThemeController` is now an `AsyncNotifier`
  that hydrates from `SettingsRepository.themePrefs()` and writes the whole
  palette/mode/eye-protect value through `updateThemePrefs()`. Widgets read
  `themeStateProvider`, which supplies `ThemeState.initial()` while hydration
  is pending. The mock repository read is latency-free to avoid a manufactured
  launch-theme flash.
- **Theme tests** — `test/core/theme/palette_contrast_test.dart` covers all
  palettes in both brightnesses, plain and warmed; it checks contrast floors,
  visible blue removal and immutable foreground tokens.
  `test/core/theme/theme_persistence_test.dart` covers repository hydration,
  write-through, JSON fallback/value semantics and a fresh provider container
  sharing the same repository instance.

**Boundary / optional follow-up:** the current `MockSettingsRepository` keeps
theme preferences in memory. It proves and exercises the repository contract,
but it is not durable storage across an operating-system process restart. A
real repository must write `ThemeState.toJson()` to local storage or the
backend before claiming device-relaunch persistence. This was not required by
the original palette/eye-protect prompt. There is also no dedicated widget
test for the settings picker layout; the theme build path and state behavior
are covered by the smoke, contrast and controller tests.

---

## 0. Earlier-session status snapshot
_(The results below and §1–§7 record the earlier 2026-09-03 session. Use
the 183-test verification in §A for the current baseline.)_

| Check | Result |
|---|---|
| `flutter analyze` | **clean**, whole project |
| `flutter test` | **168 pass, 0 fail** (was 136 at the start of this session) |
| `dart format` | applied to `lib/` and `test/` |
| `graphify update .` | ran — 3405 nodes, 4845 edges |

Four requested work items, all complete. Nothing is half-written.

---

## 1. Swipe navigation reversed

**Rule now:** swipe **LEFT** → the tab physically on the **RIGHT**; swipe
**RIGHT** → the tab physically on the **LEFT**. The tabs behave like a
filmstrip in visual order, which is the pager contract.

For the RTL detachment row `الفريق | الشفتات | المخزن | الإحصائيات`
(indices 0–3, index growing leftward):

| From | Swipe left | Swipe right |
|---|---|---|
| الشفتات (1) | الفريق (0) | المخزن (2) |
| المخزن (2) | الشفتات (1) | الإحصائيات (3) |

- `lib/core/widgets/swipe_tabs.dart` — `adjacentTabIndex()` now steps by
  `rightStep = rtl ? -1 : 1` and a leftward swipe takes `+rightStep`.
  Thresholds, `HitTestBehavior.translucent`, the inner-consumer yield and the
  `enabled` flag are untouched. Still no `PageView`; still `context.go`.
- `lib/core/motion/transitions.dart` — `TabSwitchTransition._enterSign` flips
  with it: `destinationIsRight ? +1 : -1`. The body still travels **with the
  finger** (swipe left → body moves left, incoming enters from the right), so
  gesture and animation now agree instead of contradicting.
- Applies everywhere `SwipeTabs` is used: detachment shell, workshop shell,
  and the bottom-nav shell (`main_shell.dart`), which was already sharing the
  rule.

Tests: `test/core/swipe_tabs_test.dart` (10), `test/core/tab_switch_transition_test.dart` (5).

---

## 2. Settings → "السمات والأداء" (Themes & Performance)

Now the **first** section on the settings screen, above Account and
Organisation, ordered: **theme (palette, light/dark) → graphics/animation
quality → frame rate.** The old `sectionApp` grouping is gone from the screen;
its string constant is kept (project "don't delete" rule).

### 2a. Quality levels are now meaningfully different

`MotionSpec` gained three dials and converted one, so the five levels differ by
*kind* of work rather than only duration:

| dial | performance | low | balanced | high | maximum |
|---|---|---|---|---|---|
| `durationScale` | **0** | 0.60 | 0.85 | 1.0 | 1.0 |
| `intensity` | 0 | 0.50 | 0.80 | 1.0 | 1.15 |
| `blurSigma` | 0 | 0 | 10 | 18 | 24 |
| `ambientLoops` | ✗ | ✗ | ✓ | ✓ | ✓ |
| `staggerMaxItems` *(was `stagger` bool)* | 0 | 0 | 6 | 8 | 8 |
| `overshoot` | ✗ | ✗ | ✗ | ✓ | ✓ |
| `richShadows` | ✗ | ✗ | ✓ | ✓ | ✓ |
| `animatedValues` *(new)* | ✗ | ✗ | ✓ | ✓ | ✓ |
| `slideRoutes` *(new)* | ✗ | ✗ | ✓ | ✓ | ✓ |
| `crossFadeOutgoing` | ✗ | ✗ | ✗ | ✗ | ✓ |

- **`MotionSpec.performance` is now `MotionSpec.none`** — animations are off,
  not merely short, as the brief asked. `spec.isInstant` is true, so no
  controller/transform/opacity layer is built at all.
- `animatedValues` gates counter and progress-bar tweens via the new
  `effectiveValueDuration(context, d)` helper (`motion_tokens.dart`). Wired
  into `AnimatedCounter` and the three progress fills (home, detachment stats,
  shift coverage bar) and the new workshop donut.
- `slideRoutes` replaces the magic `spec.intensity >= 0.8` gate in
  `SharedAxisPageTransition`.
- `stagger` survives as a getter (`staggerMaxItems > 0`), so no call site
  changed; `Stagger` now reads the level's depth, capped by
  `MotionTokens.staggerMaxItems` (the sub-300ms budget).
- **OS accessibility still outranks everything** — `motionSpec()` returns
  `MotionSpec.none` on `MediaQuery.disableAnimations` regardless of level.
  Unchanged, and asserted in `mtm_verify_test.dart`.

### 2b. Frame rate — real display APIs, no fake throttling

New, self-contained: `lib/core/display/`.

- `frame_rate.dart` — `FrameRatePreference {auto, fps30, fps60, fps90, fps120}`,
  `DisplayCapabilities`, and three **pure** functions:
  `availableFrameRates()`, `resolveFrameRate()`, `isFrameRateExact()`.
- `display_refresh.dart` — `DisplayRefresh`, a `MethodChannel('mtm/display')`
  client with a per-process capability cache and a `PlatformDispatcher.displays`
  fallback for reading the active rate.
- `android/.../MainActivity.kt` — answers `capabilities` and `setFrameRate`
  using `Display.getSupportedModes()` and
  `WindowManager.LayoutParams.preferredDisplayModeId` / `preferredRefreshRate`
  (API 21/23 — compiles on any compileSdk the app uses).

Honesty rules, all enforced in code and tests:

- **Nothing drops or throttles frames.** The app asks the *display* for a mode;
  the compositor schedules as it always did.
- A rate is only offered when the panel has a display mode for it (or the
  platform accepts a frame-rate hint, which Android reports as `false` at this
  SDK floor). A 60 Hz phone is offered **Auto + 60**, not 90/120.
- A platform with no channel (desktop, web, tests) reports `canChoose == false`
  and gets **Auto only**, with an explanatory line instead of dead pills.
- When the nearest mode is not the exact request, the row says so
  (`S.settingsFrameRateNearest`) rather than implying the number was honoured.
- The row prints the display's current rate when known.

Persistence follows the existing pattern: `SettingsRepository.frameRate()` /
`updateFrameRate()`, `MockSettingsRepository` in-memory, `FrameRateController`
(`AsyncNotifier`) in `features/settings/data/frame_rate_provider.dart`. It is
`ref.watch`-ed in `main.dart` purely so its `build()` re-applies the stored
preference on launch (the platform forgets it between runs).

Tests: `test/core/frame_rate_test.dart` (14), incl. `MethodChannel` mocking and
the missing-plugin path.

---

## 3. Detachments → Shifts

### 3a. Copy previous **day** (was: previous week)

- `ShiftRepository.copyDay({detachmentId, fromDay, toDay})` — new.
  `copyWeek` is **kept** (still a valid repository capability, still tested);
  both now share `MockShiftRepository._cloneOnto`, so the dedupe rule
  (skip a day+time that already has a shift) and the "assignments do not
  travel" rule live in one place.
- UI: `_BulkActions` button → `S.copyPreviousDay`, copying
  `selectedDay - 1 day` onto the selected day. The previous day may sit in the
  previous week; the copy is date-based, so that works.
- `_BulkActions` no longer takes `weekStart` (nothing used it).

### 3b. Templates: custom date selection, kept and improved

Templates were **not** removed. The date-set model from the previous handoff
(D1/D2: `ShiftTemplate.dates: List<DateTime>`) stands. What is new:

- `ShiftRepository.updateTemplateDates(templateId, dates)` — edits a template's
  day set **directly**, without going through one of its shifts.
- `MockShiftRepository._reconcileTemplateShifts(...)` — extracted from
  `updateRepeat`, now shared by both paths. The three safety rules are stated
  once: materialise a missing day from the given spec (unless the day+time is
  already occupied — dedupe), delete a surplus day **only if its shift is
  empty**, and fold a staffed day back into the set rather than deleting it.
  Collapsing to ≤1 day deactivates the template and leaves its shifts alone.
- `lib/features/shift/presentation/repeat_days_picker.dart` — **new**. The
  21-day grid was extracted out of `shift_edit_sheet.dart` as the public
  `RepeatDaysPicker` (`firstDay`, `windowDays`, `selected`, `locked`, `title`,
  `help`), so the shift editor and the template editor drive the same widget.
- `lib/features/shift/presentation/template_edit_sheet.dart` — **new**.
  `showTemplateEditor(...)`; reached from the ✎ button on each row of the
  templates sheet. Window starts at `min(today, template.firstDate)` and runs
  at least 21 days (long enough for a 10–15 day detachment, and always long
  enough to show every day the template already occupies). Staffed days are
  locked in the grid with a snackbar explaining why.

### 3c. Weekly summary removed, day selector promoted

- `_WeekHeader` + `_Stat` + `_DayStrip` → one `_DaySelector`, now the **first**
  thing under the tab bar. It carries the week navigation (‹ / week range /
  ›, with the range doubling as a "jump to this week" tap target when off the
  current week) directly above the seven day chips.
- Gone: weekly coverage %, shift count, gap count. `WeekSummary` the *model*
  is untouched — the exported report still uses it.
- Each day chip keeps its own dot (green/amber) — that is what tells you which
  day to pick, and is not weekly-summary information.

### 3d. Shift cards simplified

- `_ShiftCard` no longer lists attendees. It shows centre + repeat glyph, the
  time range, the status chip (now / gap / covered), the coverage bar with
  assigned-of-needed, and **the shift manager's name** — or a warning line when
  no supervisor is assigned.
- New derived getter `Shift.manager` → the first attendee whose role is
  `TeamRole.shiftSupervisor`, else `null`.
- The whole card is still one tap target into `showShiftManageSheet`, which is
  **unchanged**: both assignment routes, quick-fill, the full attendee list,
  attendance, check-in/out, edit and delete all still live there.

Flow: **choose day → shift cards → open shift → full shift management.**

Tests: `test/features/shift/copy_day_and_template_dates_test.dart` (13).

---

## 4. Workshop → Statistics, copied from the `medical team` project

Source (read-only, **not modified**):
`/home/ahmed/Documents/Python-Files/flutter/apps/medical_team/lib/features/workshops/`
— `presentation/workshop_stats_screen.dart`,
`data/workshop_stats_providers.dart`,
`presentation/widgets/workshop_export_buttons.dart`.

The source's information architecture is preserved: **dashboard → detail →
file export**, two groups counted separately, a donut per group, a two-tile
financial summary, a copy-paid-names card, a one-tap full export and a
section-picking custom export. Everything underneath was rebuilt on MTM's
architecture.

### New files

| File | What |
|---|---|
| `features/workshop/domain/workshop_stats.dart` | `WorkshopStats`, `WorkshopGroupStats`, `WorkshopStatsPerson`, `WorkshopStatsGroup`, label extensions. `WorkshopStats.of(workshop, participants)` is the only calculation path. |
| `features/workshop/data/workshop_stats_providers.dart` | `workshopStatsProvider` — composes `workshopByIdProvider` + `workshopParticipantsProvider` into one `Result<WorkshopStats>`, preserving failure/offline honestly. |
| `features/workshop/data/workshop_stats_report.dart` | `WorkshopReportSection {summary, participants, team}` + `buildWorkshopStatsReport()` → a `ReportDocument`. `formatWorkshopAmount()`. |
| `features/workshop/presentation/widgets/workshop_stats_export.dart` | `WorkshopStatsExportCard`, `showWorkshopExportSheet`, `WorkshopCopyNamesCard`, `exportWorkshopReport`, `formatPaidNames`. |
| `features/workshop/presentation/tabs/workshop_stats_tab.dart` | Rewritten dashboard. |

### Adaptation decisions

- **Export reuses MTM's own report pipeline.** `buildWorkshopStatsReport`
  produces a `ReportDocument`, which `AttendancePdfBuilder` already renders as
  a paginated RTL PDF and `ReportDocument.toCsv()` already flattens for a
  spreadsheet. **No new packages were added.** The source used
  `archive` + `path_provider` + `share_plus` for a real `.xlsx`; MTM's
  documented delivery is `Printing.sharePdf` for PDF and CSV-to-clipboard for
  the spreadsheet (see `report_export_page.dart`), and this follows it exactly.
  *Consequence: the Excel option delivers CSV on the clipboard, not an .xlsx
  file. Swapping in a real file write is a delivery change, not a rebuild.*
- **`ReportDocument` gained one optional field**, `headerNote`, plus a
  `scopeLabel` getter. A workshop happens on a date, not across a window, so
  it must not print "last 7 days". Detachment reports are unaffected.
- **Two additive model fields** (the only data-model change):
  `Workshop.registrationFee` (default `0`) and
  `WorkshopParticipant.paymentStatus` (`PaymentStatus? {paid, unpaid}`,
  default `null` = not recorded). Both are read-only and seeded in
  `MockWorkshopRepository` — no payments-management UI was built, per the
  brief's exclusion. `w4` is seeded free so the "free workshop" path has data.
- **`null` payment is a real third state**, never folded into `unpaid`. The
  organising team carries no payment record (they run the workshop, they do
  not buy a seat), so they land in "غير محدد".
- **Attendance now counts `checkedOut` as present.** The old tile counted only
  `checkedIn`, which reported every *finished* workshop as 0 % attended. This
  supersedes the `// ASSUMPTION` comment that used to sit on that tab.
- Currency is `ل.س` (`S.currencyUnit`), not the source's `د.ع`.
- The source's app-bar "custom export" action became a button inside the
  export card, because the tab has no app bar of its own (the shell owns it).
- Section toggles use the same `PressScale` card style as the detachment
  report composer, not `CheckboxListTile` — the Material-ink assertion inside
  the sheet's `DecoratedBox` is a real failure mode, and the two export flows
  should not look like two different apps.

Tests: `test/features/workshop/workshop_stats_test.dart` (19), covering the
counts, the money, both export section paths, the CSV content, copy-names
formatting, and two widget tests of the rendered dashboard.

---

## 5. Files changed (this session only)

**Core**
- `core/widgets/swipe_tabs.dart` — reversed rule + docs
- `core/motion/transitions.dart` — `_enterSign` flip; `slideRoutes` gate
- `core/motion/motion_level.dart` — new dials, `performance = none`
- `core/motion/motion_tokens.dart` — `effectiveValueDuration()`
- `core/motion/animated_counter.dart`, `core/motion/stagger.dart`
- `core/display/frame_rate.dart`, `core/display/display_refresh.dart` — **new**
- `core/export/attendance_pdf.dart` — header reads `scopeLabel`

**Settings**
- `features/settings/presentation/settings_page.dart` — section reorder,
  `_FrameRatePicker`
- `features/settings/domain/settings_repository.dart`,
  `data/mock_settings_repository.dart`, `data/frame_rate_provider.dart` (new)
- `main.dart` — watches `frameRateProvider`

**Shifts / detachment**
- `features/shift/domain/shift_models.dart` — `Shift.manager`
- `features/shift/domain/shift_repository.dart` — `copyDay`, `updateTemplateDates`
- `features/shift/data/mock_shift_repository.dart` — `_reconcileTemplateShifts`,
  `_cloneOnto`, `copyDay`, `updateTemplateDates`
- `features/shift/presentation/repeat_days_picker.dart` — **new** (extracted)
- `features/shift/presentation/template_edit_sheet.dart` — **new**
- `features/shift/presentation/shift_edit_sheet.dart` — uses `RepeatDaysPicker`
- `features/detachment/presentation/tabs/detachment_shifts_tab.dart` —
  `_DaySelector`, copy-previous-day, template ✎, simplified card
- `features/detachment/domain/report_models.dart` — `headerNote`/`scopeLabel`

**Workshop** — see §4 table, plus `domain/workshop_models.dart` and
`data/mock_workshop_repository.dart`

**Platform** — `android/app/src/main/kotlin/com/mtm/mtm/MainActivity.kt`

**Strings** — `l10n/strings.dart`, ~70 new constants. Nothing deleted:
`copyLastWeek*`, `weekCoverage`, `weekShifts`, `weekGaps`, `settingsMotion*`,
`sectionApp`, `totalParticipants`, `presentCount`, `attendancePercent` are all
retained even where now unused, per the project rule.

**Tests** — new: `core/frame_rate_test.dart`,
`features/shift/copy_day_and_template_dates_test.dart`,
`features/workshop/workshop_stats_test.dart`. Updated:
`core/swipe_tabs_test.dart`, `core/tab_switch_transition_test.dart`,
`mtm_verify_test.dart`, `features/detachment/detachment_group_flow_smoke_test.dart`.

---

## 6. Known issues / open points

1. **Excel export is CSV-on-clipboard, not a `.xlsx` file.** Deliberate (§4).
   To make it a real file: add `archive` (already in the lock file as a
   transitive dep), `path_provider` and `share_plus`, port
   `medical_team/lib/core/export/xlsx_writer.dart`, and swap the `else` branch
   in `exportWorkshopReport`. Needs dependency approval per `CLAUDE.md`.
2. **Frame rate is Android-only in practice.** iOS/desktop/web report
   `canChoose == false` and get Auto only. iOS ProMotion would need
   `CADisableMinimumFrameDurationOnPhone` in `Info.plist` plus an engine-level
   hook that does not exist in Dart today.
3. **Frame-rate selection is untested on a real device.** The Kotlin compiles
   against API 21/23 APIs and the Dart side is unit-tested through a mocked
   channel, but nobody has watched a panel actually change mode. Worth a
   `/run` on hardware.
4. **Workshop payment data is read-only.** There is no UI or repository method
   to change `paymentStatus` — the brief excluded payments management. If that
   is wanted later, mirror `setParticipantAttendance`.
5. **`ReportDocument.range` is still required** and meaningless for a workshop
   report (it passes `ReportRange.week` and overrides the label via
   `headerNote`). Making it nullable is a small follow-up if it starts to grate.
6. **No widget test for the settings screen ordering** — the section order is
   asserted only by reading. The pieces underneath (`MotionSpec` ladder, frame
   rate resolution) are covered.
7. The `_RepeatDays` grid is still a flat `Wrap` of pills with no month
   affordance; fine at 21–25 days, would need grouping if the window grew.
8. `S.applyTemplatesEmpty` is still the templates-sheet empty state — reads
   fine, but the name is now a misnomer.

---

## 7. Exact next steps (nothing is required)

Optional, in the order I would take them:

1. `/run` the app and eyeball, on a device: the reversed swipe in RTL, the
   frame-rate picker against a real 120 Hz panel, the new shifts day selector,
   and the workshop statistics dashboard.
2. Decide on issue 1 (real `.xlsx`) — it is the one place the copied feature
   is deliberately thinner than its source.
3. If wanted, a widget test that asserts "السمات والأداء" renders above
   "الحساب" on the settings screen.


---

## THE ENTRY EXPERIENCE (IMPLEMENTED, 2026-09-22)

The app's front door: one fixed brand mark, a redesigned sign-in screen, a
cold-launch intro, and Google going through the platform's own account
chooser. Nothing outside `/startup`, `/login` and the brand plumbing was
touched.

### A. One mark. The selector is gone.

`BrandLogo` (three marks), `ThemeState.logo`, `ThemeController.setLogo`,
`BrandLogoCard` and the `شعار ليدر` section of `/more/themes` are **removed**,
along with `settingsBrandLogoSection`, `settingsBrandLogoSectionSub`,
`settingsBrandLogoDefault`, `brandLogoCleanLayer`, `brandLogoElegantCurve` and
`brandLogoDepth`. `assets/brand/leader_logo_elegant_curve.png` and
`leader_logo_depth.png` are deleted from the bundle.

The reasoning, which is also written into `core/brand/brand_mark.dart`: a
product's mark is the one thing that has to be the *same object* every time it
appears — on the home screen, at launch, on the forced-upgrade screen, in
About — and offering three of them made the product's own identity a setting.
The launcher icon could never follow the choice anyway (Android only swaps one
by toggling activity-aliases, which drops the user's placed shortcut), so the
selector guaranteed a mismatch between the icon someone tapped and the mark
they then saw.

* `AppInfo.logoAsset` is the **only** place `assets/brand/…` is spelled in
  `lib/`, and `test/features/settings/brand_mark_test.dart` fails if a second
  appears.
* `BrandMark` (`core/brand/brand_mark.dart`) is the widget that draws it, with
  an optional coloured bloom. Key: `BrandMark.widgetKey`. It carries no
  semantics — every screen that draws the mark also says the name.
* `ThemeState.fromJson` **reads and drops** a `logo` key written by the old
  build: a preference the app no longer offers must not cost the palette and
  appearance stored beside it. `toJson` no longer writes one.
* The launcher icon is unchanged and still fixed:
  `mipmap-anydpi-v26/ic_launcher.xml` over the per-density foregrounds.
* `assets/brand/mtm_logo_full.png` is still bundled and still drawn nowhere.
  It predates all of this and was left alone deliberately.

### B. `EntryGlass` — one surface for both entry screens

`login_glass.dart`/`LoginGlass` became
`features/auth/presentation/entry_glass.dart`/`EntryGlass`, because the launch
screen and the sign-in screen are now painted on the *same* ground. That is
what makes a cold launch read as the mark dissolving into a form rather than
as two screens with a cut between them — the route cross-fade changes the
content over a background that never moves.

New roles on top of the old set:

| Token | What it is for |
| --- | --- |
| `horizon` | The screen's light source: one wide soft glow seated off the top edge. Everything else is lit consistently with it. |
| `accentInk` | The accent **as text**. A filled button and a focus ring are UI components and clear 3:1 at `accent`; a 13.5 sp link is prose and has to clear 4.5:1 against the *ground*, which on the light surface `accent` does not. |
| `ctaDisabled` / `onCtaDisabled` | A real pair of colours for the primary action with nothing to submit. See "the disabled CTA" below. |
| `fieldFocusFill` | The focused well **brightens**; focus is carried by the surface as well as by the ring and the border. |
| `pulse` / `pulsePeak` | The ambient pulse's colour and its brightest alpha. |

**Two fixes that came out of measuring instead of looking.**

1. `EntryGlass.warmed()` now preserves each token's own alpha
   (`Color.lerp(...).withValues(alpha: c.a)`). `Color.lerp` interpolates alpha
   too and the warm target is opaque, so lerping an 8 %-alpha wash 40 % of the
   way there landed it at ~45 % — which does not warm the ambience, it turns
   it into a curtain. `AppColors.warmed` does not need this because every
   palette token is opaque; this surface has translucent ground tokens.
2. Contrast is now **enforced by test** for this surface as well:
   `test/features/auth/entry_surface_test.dart` holds every ink to WCAG AA
   against the surface it is actually drawn on, in light, dark and both
   eye-protect variants, and bounds what the pulse may do.

### C. Login: what changed and why

**The brand is said once.** The screen opened with the mark, then «ليدر»,
then «مرحباً بك في ليدر» — three statements of the same fact in the first
140 dp, before anything the person came to do. The mark block and the
standalone wordmark are gone; the heading carries the name, and a 44×3 accent
rule above it keeps the top from floating.

**Two zones, not one.** Who you are and what this is sit on the ground (the
heading and one supporting line). What you *do* sits on the glass (two fields,
forgot, the primary action, the rule, Google). The panel used to open with a
paragraph, which made the reader work out where the form started; now the
panel *is* the form. A notice carried over from a previous session
(«انتهت الجلسة» and friends) is a tinted live region at the top of the panel
rather than loose centred text.

**Colour.** The complaint was "muted, washed out", and it was mostly true of
the light ground: a near-white mint on which a white glass panel is almost
invisible. The light ground is deeper and genuinely tinted (`#E3F4F0` →
`#D1EAE5` → `#BBDADB`), its white light source is weaker (55 % → 35 %, because
white on a light ground bleaches rather than illuminates), and the light
accent moved from `#096865` — near-black at small sizes — to `#0B7F75`, which
is the brightest teal that still clears 4.5:1 with white on it. Dark gained
chroma in the ground and a brighter mint accent (`#5FDCBB`).

**The CTA is the one lit object.** Solid accent with its own accent-tinted
shadow under it, dropped while the button is disabled — an inert control that
still casts light is exactly the mixed signal a disabled state exists to
avoid.

**The disabled CTA is a real pair of colours.** The empty form is the first
thing everyone sees, so the disabled CTA is the most-viewed state on the
most-viewed screen, and diluting the accent with alpha produced precisely the
muddy slab the redesign was asked to fix. It is now an opaque, quiet chip
(`#9CC6C1` with `#0F3D39` ink in light; `#26544C` with `#9CC6BB` in dark) —
unmistakably not the accent, unmistakably still a button, and its label clears
4.5:1, which is more than the convention asks of a disabled control and the
right amount for one whose whole job is to say what is still missing.

**Focus moves three things**: the border takes the accent, a 4 dp ring
appears, and the well itself brightens. On a frosted panel a border change
alone is close to invisible.

### D. The ambient pulse

`EntryPulse` (in `entry_glass.dart`) is the screen's one piece of ongoing
motion: a breathing core of light plus two soft rings leaving it half a cycle
apart and fading as they widen, on a **5.2 s** cycle — slower than a resting
heart rate, because the screen should read as *awake*, not as *waiting*.

* It is a `CustomPainter` inside a `RepaintBoundary` inside an
  `IgnorePointer`, behind the form. It participates in no layout, moves no
  control, and allocates nothing per frame but three radial shaders. No
  `BackdropFilter`, no video, no package.
* Each ring is a radial gradient whose stops peak just inside its edge — a
  soft annulus with no rim anywhere, which a stroked circle cannot give.
* It answers to `MotionSpec.ambientLoops`, exactly where the skeleton shimmer
  and the lock-window halo stop, and that folds in
  `MediaQuery.disableAnimations`. With ambience off there is **no controller
  at all**: the painter draws one fixed mid-expansion frame, so the screen
  keeps its composition and loses only its movement.
* `_EntryPulseState` uses `TickerProviderStateMixin`, not the single-ticker
  one: the quality level is a live setting, so the widget can genuinely be
  asked to give its controller up and later create another.
* Light needs roughly twice dark's alpha for the same perceived lift, so the
  bound in the test is on the *result* — a wave at its brightest must stay
  under 2:1 against the ground it crosses, past which it stops reading as
  light and starts reading as an object with an edge.

### E. The intro, and `IntroGate`

`/startup` now renders `LeaderIntro` (`features/auth/presentation/
leader_intro.dart`). At full motion: the mark fades up and settles from 0.86
scale (0–520 ms), the pulse fades in behind it and runs, «ليدر» rises 10 dp
(560–900 ms), and the whole thing hands over at **1700 ms**.

**The hold lives in the routing decision, not in a widget's timer.** The
router leaves `/startup` the instant the classifier changes its mind, and on a
warm device that is frame two — so an intro that merely animated would be cut
off and the launch would flash. `core/startup/intro_gate.dart` adds
`IntroPhase` and `introGateProvider`, and `StartupInputs.introHolding` is a
new **priority 0** input to `resolveStartup`. It is first because it is not an
answer: it can only ever resolve to `restoring`, the surface a launch already
sits on, and every real outcome below it is merely *late* by the length of one
animation.

* **Cold launch only, by construction.** `main()` calls
  `IntroGate.armColdLaunch()` before `runApp`; `build()` consumes that arming
  the first time the provider is read and nothing can set it again. Signing
  out, tab changes, returning from the background and landing back on
  `/startup` therefore cannot replay it. There is no persisted "seen the
  intro" flag — process lifetime is exactly the right scope.
* **It is armed before `runApp`, deliberately.** Arming inside `initState`
  would write provider state while GoRouter's `refreshListenable` is still
  mounting — the reentrant rebuild-during-mount `main.dart` already documents
  avoiding.
* **It cannot stick.** Arming starts an `IntroGate.ceiling` (2600 ms) timer
  that finishes the gate whatever the screen does, so a disposed,
  never-mounted or crashed intro costs at most that long. `finish()` cancels
  the timer.
* **Slow boot is designed, not hidden.** If the classifier is still
  `restoring` when the sequence ends, the screen stays and — 600 ms later —
  fades in the same live-region «جارٍ فتح التطبيق» the old startup surface
  used. A quick launch never shows that line. No fake delay is ever
  introduced.
* **Reduced motion gets none of it**: `effectiveDuration` collapses the
  sequence to zero, the gate is released on the first post-frame callback, and
  the screen draws its finished composition.
* `LeaderIntro` releases the gate from a post-frame callback (or from the
  controller's status listener, which is outside the build phase) — writing
  provider state during a build is refused by Riverpod.

`StartupPage` is now three lines over `LeaderIntro`; the old mark + sentence +
`LinearProgressIndicator` are gone.

### F. Google: the platform's own account chooser

**What was wrong.** A debug build on a real phone put up
`_MockGoogleChooserDialog` — an in-app `AlertDialog` asking the user to *type*
a Google address. That is a development fixture for exercising the
repository's verified/unverified/method-link paths where no native chooser
exists, and it was gated only on `demoAccountsAllowed`, which is true in any
debug build including one installed on a device.

**What it is now.** `googleDevelopmentChooserProvider` (in
`google_identity_gateway.dart`) gates it on
`developmentGoogleChooserSupported(isWeb:, platform:)`, which is **false on
Android and iOS** and on web. On a phone the button always runs the SDK. The
two suites that drive a mock Google identity now override the provider to
`true` by name, which is honest about what they are exercising.

**The SDK path was already the native chooser** and is unchanged in shape:
`GoogleSignIn.instance.authenticate()` on Android issues a
`GetSignInWithGoogleOption` credential request — the system "Sign in with
Google" sheet listing the device's accounts, with no authorized-account filter
and no auto-select. What was added is `signOut()` immediately before it: the
plugin documents that a client should not call `authenticate` for a new
account until after a `signOut`, and someone pressing the Google button *on
purpose* is asking to choose, possibly a different account than last time. It
clears this app's own session only — not the device's Google accounts, not
Android's own sign-in, and not any authorization grant (`disconnect()` is
never called). A failed sign-out is swallowed; it must never be the reason a
sign-in cannot start.

**Unavailable now says something useful.** `OnboardingErrorKind
.googleUnavailable` + `S.onboardingGoogleUnavailable`
(«المتابعة عبر Google غير متاحة في هذا الإصدار…») replaced "try again" for
the configuration/no-UI case on both Login and Signup. "Try again" is the
wrong instruction when trying again cannot work.

**Everything after the identity is unchanged**: the same assertion goes to
`OnboardingController.signInWithGoogle`, invitation still outranks the
Team/Demo choice, tenant and demo isolation and the role gates are untouched.

**External configuration is still required** — see §H.

### G. Tests

* `test/features/settings/brand_mark_test.dart` — replaces
  `brand_logo_test.dart`. One mark, the retired assets gone, `assets/brand/`
  spelled exactly once in `lib/`, the launcher icon fixed and per-density, no
  picker and no artwork on `/more/themes`, no `logo` key persisted, and an old
  stored `logo` costing nothing else.
* `test/features/auth/entry_surface_test.dart` — the contrast floors above,
  the eye-protect asymmetry, the pulse's bounds, the painter at every phase
  including degenerate sizes, and that the controller exists only when
  ambience is allowed.
* `test/core/startup/intro_test.dart` — the gate's contract, a cold launch
  holding and then handing over, no other screen before it is over, the slow
  boot caption, no replay after sign-out, and the reduced-motion path.
* `test/features/auth/login_screen_test.dart` — rewritten for the new
  hierarchy: no mark, the product name exactly once, the heading above the
  panel, the pulse running/stopping by motion level and never taking a hit
  test, plus the existing fit and appearance matrices.
* `test/features/auth/google_identity_gateway_test.dart` — sign-out before
  authenticate and its order, a refused sign-out not blocking sign-in, no
  `disconnect`, no scope hint, and the development chooser refused on
  Android/iOS/web.

### H. Gotchas for whoever is next

1. **`pumpAndSettle` does not return on `/startup` or `/login`.** The ambient
   pulse is a looping controller, by design. `test/entry_settle.dart` holds
   the shared bounded pump (`settleEntry`) and explains why; six suites use
   it. Do **not** reach for it on a screen that has no entry surface in it —
   that would hide a genuine never-settling animation somewhere else.
2. **A render harness that only sets `MaterialApp.themeMode` renders light.**
   The entry surface resolves its own brightness and eye-protect from the
   *stored theme* (`themeStateProvider`). `onboarding_render.dart` had been
   labelling light shots "dark" for that reason; it now overrides
   `settingsRepositoryProvider` with a fixed `ThemeState`. This is the second
   time this exact defect has been found — see FRONTEND-DESIGN-NOTES, "A
   render harness that cannot render the mode is not covering it".
3. **The intro carries the Arabic wordmark**, so an assertion taken *during*
   the route transition off `/startup` sees «ليدر» twice. Pump past the
   transition (`forced_upgrade_test.dart` does).
4. Login still labels its fields **above** the input, so use
   `LoginField.keyFor(S.emailLabel)`, not a label finder.

### I. External configuration still required (nothing in the repo can supply it)

Google Sign-In will report *unavailable* until all of this exists. The code is
complete; these are console/keystore facts.

1. A Google Cloud project with the **Google Identity / Credential Manager**
   API available.
2. An **Android OAuth client** for package `com.leader.teams`, registered with
   the SHA-1 of every keystore that will sign a build people sign in from —
   the debug keystore (`~/.android/debug.keystore`, password `android`) for
   development, and the release/Play App Signing key for shipping. Without the
   matching SHA-1 the system sheet opens and then fails.
3. A **Web application OAuth client** in the same project. Its client ID is
   what the app passes as `serverClientId`; it is the audience of the ID token
   the backend will verify.
4. Build with that id:
   `flutter build apk --dart-define=MTM_GOOGLE_SERVER_CLIENT_ID=<web client id>`
   (or `--dart-define-from-file`). It is deliberately **not** committed.
5. The backend's `POST /auth/google` must accept that same web client ID as
   the token audience. See `BACKEND-HANDOFF.md`.
6. `minSdk` is 24 (Flutter's default for 3.44), comfortably above the 23 that
   Credential Manager's Google ID flow needs. Nothing to change.

### J. Not done, deliberately

* **The adaptive performance system** — explicitly out of scope; a later
  phase.
* **No physical device verification.** `adb devices -l` listed none while this
  was built, so the APK was verified by inspection (`com.leader.teams`,
  label «ليدر», `mipmap-anydpi-v26/ic_launcher.xml`, only the Clean Layer
  mark bundled) and not installed or launched. The intro, the pulse and the
  Google system sheet have not been watched on hardware.
* **`assets/brand/mtm_logo_full.png`** is still bundled and drawn nowhere. It
  is unrelated to the selector and removing it was not part of this work.

---

## WORKSHOP REGISTER — «الأعضاء والزوار» (IMPLEMENTED, 2026-09-24)

Implements `WorkshopUpdate.md` (decisions A1–A11) directly; no Codex hand-off.

### What changed for the user

* The workshop tab «الأعضاء والضيوف» is now **«الأعضاء والزوار»**, in two parts
  picked by chips at the top: **«أعضاء الفريق (N)»** and **«المتطوعون والزوار (N)»**.
* **«إضافة عضو»** opens a full page (`/workshop/:id/members/new`): typed
  name → role (قائد · مدرب · دعم · إدارة · عضو, default عضو) → «دفع رسوم الورشة»
  switch → حفظ. Nobody is picked from the roster any more.
* A team-member row shows name, role, a green «دافع» / red «غير دافع» chip, and
  the attendance chip. Row sheet: «سجّل الدخول» / «لن يحضر», paid / unpaid,
  **«تعديل»** (opens `/workshop/:id/members/:pid/edit`, loaded by id), remove.
* **Volunteers/visitors** are added from a sheet with name + paid switch; not
  editable (remove and re-add).
* Payment filter chips «الكل / دافع / غير دافع (N)» per part. A **free**
  workshop (fee 0) shows no payment UI at all.
* Statistics: payment is **binary**; «غير محدد» is gone from the dashboard,
  detail table and exports. Organisers are **excluded** from payment counts
  (their payment cells print «—»).

### Code

* `domain/workshop_models.dart` — `WorkshopRole` enum; `WorkshopParticipant.role`
  (member only), `isPaid`; `copyWith(name, initials, role)`; tolerant `fromJson`
  (old member line → `member`, guest → `null`).
* `domain/workshop_repository.dart` + mock — `addTeamMember`,
  `updateTeamMember`, `addGuestParticipant(…, paid)`. Duplicates by
  `memberNameKey` **within one part**; update excludes itself; guest id on
  update → `not_found`; team members still take seats (`workshop_full`).
* `presentation/workshop_member_form_page.dart` — new page (seeds once, handles
  loading/error/offline/not-found-or-guest, archived banner + disabled save,
  keeps input on failure).
* `core/router/app_router.dart` — the two routes as root-navigator siblings of
  `':id/edit'`, before the detail `ShellRoute`, behind `workshop.people.manage`.
* `presentation/tabs/workshop_members_tab.dart` — rebuilt around `_Part` /
  `_PayFilter`; roster picker no longer used here.
* `presentation/widgets/workshop_people.dart` — `WorkshopPersonActions` gains
  `attendanceChoices` (default = organisers' four), `binaryPayment`, `onEdit`;
  `WorkshopAttendanceChoices.register`; shared `WorkshopPaidSwitch`;
  `askWorkshopGuestName` → `askWorkshopGuestDetails`.
* `domain/workshop_stats.dart`, `data/workshop_stats_report.dart`,
  `tabs/workshop_stats_tab.dart` — binary payment, organisers excluded,
  `WorkshopRoleLabel`.
* Seeds (`mock_workshop_repository.dart`, `demo_seed.dart`) — roles on every
  member line, explicit paid/unpaid everywhere; `w6` still empty.
* Strings — new `workshop*` keys; `S.absent` untouched (`S.workshopNotComing`
  is workshop-only).

### Unchanged by design

Organisers tab «الفريق وأدواره» (roster picker, four attendance choices, no
payment), `AttendanceState`, the roster, shifts, `addMemberParticipants`
(kept for compatibility).

### Docs

`API_CONTRACT.md` → `WorkshopParticipant` + `addTeamMember` /
`updateTeamMember` / `addGuestParticipant(paid)`; `BACKEND-HANDOFF.md` §6.3
Workshops row.

## WORKSHOP REGISTER — team and volunteers on separate tabs (IMPLEMENTED, 2026-09-25)

Follow-up to the section above, at Ahmed's request. It supersedes that
section's "two parts" and "Unchanged by design: organisers tab" lines.

### What changed for the user

* **«الفريق وأدواره»** now holds the workshop's own **team members**. Its
  **«إضافة عضو»** opens the typed page (`/workshop/:id/members/new`: name →
  role → paid). The roster picker is **removed**, and so is «إضافة منظِّم».
* **«المتطوعون والزوار»** (the tab was «الأعضاء والزوار») holds only volunteers
  and visitors. Its **«إضافة متطوع»** (key `workshop-add-volunteer`) opens the
  same full page at `/workshop/:id/volunteers/new`, with name + paid and no
  role. The bottom sheet is gone.
* The part chips are gone, because each tab is now one part. Search, the
  «الكل / دافع / غير دافع (N)» filter, the row, and the «سجّل الدخول» / «لن يحضر»
  sheet are the same on both tabs.
* **Organisers already on a workshop** (roster-linked, `organizingTeam`) still
  show under the team members, below a «المنظِّمون» heading. They can be
  checked in or removed, but no new one can be added. The heading is hidden
  when there are none.

### Code

* `tabs/workshop_members_tab.dart`: `WorkshopRegisterView(kind, footer)` is
  the shared list. `WorkshopMembersTab` is its volunteer half.
* `tabs/workshop_team_tab.dart`: `WorkshopTeamTab` is the team-member half,
  with a `_Organisers` footer.
* `workshop_member_form_page.dart`: `volunteer: true` mode calls
  `addGuestParticipant(…, paid:)`.
* `app_router.dart`: the `':id/volunteers/new'` route, a root-navigator page
  behind `workshop.people.manage`.
* Removed: `pickWorkshopMembers`, `WorkshopMemberPicker`,
  `workshopCandidatesProvider`, `askWorkshopGuestDetails`, and the
  `workshopPick*`, `workshopAddOrganizer`, `workshopAddGuest` and
  `emptyWorkshopTeam*` strings. The repository's `addOrganizers` /
  `addMemberParticipants` stay, as API and backend contract.
* `test/core/widgets/animated_tab_bar_test.dart` now loads IBM Plex Sans
  Arabic. The default test font drew «المتطوعون والزوار» wider than 320dp;
  the real font draws it at 192dp at 1.6×.
