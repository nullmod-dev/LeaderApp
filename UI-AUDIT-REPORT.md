# Leader UI Audit

**Date:** 2026-09-19 · **Branch:** `sync-conflict-and-pending-work` · **Scope:** audit only — no UI was modified.

> **Final status (2026-09-21).** The UI quality programme this document opened
> is **CLOSED**. Every finding below carries a disposition in place —
> **RESOLVED** with its phase, **INTENTIONALLY RETAINED**, **BACKEND/DATA
> DEPENDENCY** or **OPTIONAL FUTURE POLISH**. **No frontend P0 or P1 defect
> remains open.** The Phase 3C closure ledger is the summary; `HANDOFF.md`
> §"UI QUALITY PROGRAM — FINAL STATUS" is the programme-level record.

> **Status update — 2026-09-20.** Phase 1 (foundation) of the UI quality
> programme has landed. Findings it resolved are marked **✅ RESOLVED (Phase 1)**
> in place, with what was done; everything else is still open and is Phase 2
> (Super Admin) or Phase 3 (Main Admin) work. Nothing below was deleted — the
> audit stays readable as the document it was. See `HANDOFF.md` §"UI QUALITY
> PROGRAMME — PHASE 1".
>
> Phase 1 closed: **P1-1** (chevrons), **P1-3** (confirmation pattern),
> **P1-4** (filter control), **P1-5** (reading column), **P1-12** (internal
> identifiers), work item **0** (tenant render harness), the section-header
> and Arabic-plural P2s, and a **production DST bug in `copyWeek`** that the
> audit's test investigation surfaced. Phase 1 also found and fixed one defect
> the audit had not: the shifts day strip overflowed by 21 px at 320 dp/1.6×.
>
> **Status update — 2026-09-20 (Phase 2).** The Super Admin pass has landed.
> Findings it resolved are marked **✅ RESOLVED (Phase 2)** in place. Phase 2
> closed **P1-6** (Overview), **P1-7** (Commerce), **P1-8** (Tenant Detail),
> the Operations grouping, the Audit Log pass, the Security timestamps, the
> Demo session rows, the Tenant Features switch, the duplicate refresh
> affordances, the duplicated platform page titles, the four platform header
> treatments, the reports catalogue's re-implemented row, the overview's
> gigabyte division and the elevated FAB. **P1-11** (the ` · ` separator) is
> **partially resolved** — every Platform instance where it neighbours a
> figure is gone; the tenant surface is Phase 3. Phase 2 also found and fixed
> three defects the audit had not, **all three by reading its own renders**:
> `AppTypography` never defined `labelSmall`, so a `StatusChip` in a
> `ListTile.trailing` slot inherited a font with no Arabic-Indic digits and
> rendered a count as a placeholder box; `PlatformMeta`'s first separator
> design (a painted dot) was still a dot beside «٠» and became a vertical
> hairline; and a `NavigationRow` badge in the trailing slot squeezed the
> reports catalogue's titles into **broken words** at 320 dp / 1.6×, so the
> badge now moves under the subtitle past that text scale.

> **Status update — 2026-09-21 (Phase 3A).** The two high-risk tenant screens
> have landed. Phase 3A closed **P1-9** (Main Admin Home), **P1-10**
> (Statistics charts), and completed **P1-11** — the ` · ` separator — on the
> surfaces it touched, by promoting Phase 2's `PlatformMeta` hairline into
> `core/widgets/app_meta.dart` as `AppMeta`, and `PlatformTime` into
> `core/format/app_time.dart` as `AppTime`. It also established the tenant
> **measure policy** (four classes, written out in
> `core/widgets/reading_column.dart`) and applied it to Home and Statistics.
> The rest of Phase 3 — bottom-nav semantics, Shifts, Workshop register,
> Settings hub, Inventory, copy and terminology — is untouched and is the
> next pass.
>
> Phase 3A also found and fixed **three defects the audit had not**, all three
> by reading its own renders: `AnimatedTabBar` set a `TextStyle` with no
> family and `AnimatedDefaultTextStyle` *replaces* rather than merges, so
> every detachment and workshop tab label drew as **placeholder boxes**; the
> statistics glance tiles truncated «أدوية منخفضة» into «أدوية…» at 320 dp /
> 1.6×, losing the meaning while keeping the figure; and the Home shortcut
> grid broke the single Arabic word «الإحصائيات» across two lines at the same
> size. It also caught a data-truth defect the audit had not looked for: the
> week-coverage tile printed «١٠٠٪» for a week with **no shifts in it**,
> because `WeekSummary.coveragePercent` answers 100 when nothing is needed.

> **Status update — 2026-09-21 (Phase 3B).** The remaining lower-risk tenant
> pass is complete. It added bottom-nav semantics, finished Shifts and Workshop
> Register polish, labelled the audited icon actions, consolidated Settings,
> cleaned Pricing/Session Expired/theme terminology, split Inventory's empty
> states, injected `clockProvider` into Workshop statistics, adopted the Phase
> 3A formatters where safe, removed only verified-dead strings, and made
> `AnimatedTabBar` scroll conventional single-line labels at narrow widths.
> Organization and Plan were intentionally retained after their new renders
> showed no genuine defect. Home, Statistics, Platform, Login, Team roster,
> Detachment list, Sync Center and Needs Review were not redesigned.

### Phase 3B closure ledger

| Remaining Phase 3 finding | Final disposition |
| --- | --- |
| Tenant bottom-navigation labels and selection state | **✅ RESOLVED (Phase 3B)** — one Arabic semantics node per destination; routes/order/behaviour unchanged |
| Shifts metadata, time, accessibility and narrow large text | **✅ RESOLVED (Phase 3B)** — shared formatters plus large-text reflow; class-C schedule retained |
| Workshop Register search, scanning and two empty conditions | **✅ RESOLVED (Phase 3B)** — Team-roster pattern without a second person model |
| Permanently hidden Workshop offline banner | **✅ RESOLVED (Phase 3B)** — removed; no real offline state exists there |
| Five audited unlabeled icon actions | **✅ RESOLVED (Phase 3B)** — tooltips added and a source guard prevents recurrence |
| Settings headings, repeated sync label, two subscription concepts | **✅ RESOLVED (Phase 3B)** — fewer groups and one «الاشتراك والأسعار» door |
| Organization empty space / Plan responsive hierarchy | **INTENTIONALLY RETAINED** — Phase 1 measures render correctly at 320/390/600/900; no content invented |
| Duplicate Pricing message, percent and duration formatting | **✅ RESOLVED (Phase 3B)** — commercial values/domain IDs unchanged |
| Repeated Session Expired explanation / raw literal | **✅ RESOLVED (Phase 3B)** — one localized explanation; `S.signIn` unchanged |
| «الثيمات» terminology | **✅ RESOLVED (Phase 3B)** — user-facing copy now uses «السمات»; internals unchanged |
| Inventory no-results versus genuinely empty | **✅ RESOLVED (Phase 3B)** — distinct states on the existing filter architecture |
| Workshop wall-clock reads | **✅ RESOLVED (Phase 3B)** — `clockProvider` reaches stats/report generation; deterministic tests added |
| Ambiguous numeric metadata/time/percentage formatting | **✅ RESOLVED IN TOUCHED SCOPE** — `AppMeta`/`AppTime`/`AppNumber`; strong lists received formatting-only changes |
| Verified-unreferenced legacy strings | **✅ RESOLVED (Phase 3B)** — zero-reference candidates removed; live organization copy retained |
| Narrow/large-text `AnimatedTabBar` truncation | **✅ RESOLVED (Phase 3B)** — RTL horizontal strip keeps selection visible; tap/swipe semantics retained |
| Phase 3A Home/Statistics data gaps | **BACKEND/DATA DEPENDENCY** — unchanged and not masked; see the Phase 3A handoff |

Phase 3B added **61 inspected tenant renders** with the existing harness and
closed the only defect those renders found (Shifts compression at 320 dp /
1.6×). Its authoritative validation is 2442/2442 tests, clean analysis and
diff checks, and a verified debug APK; see `HANDOFF.md` for the exact gates.

> **Status update — 2026-09-21 (Phase 3C — closure).** The closure pass did
> not redesign anything. It re-read this document finding by finding, checked
> each one against the code and against fresh renders, and classified every
> remaining line. Four findings that Phase 3A had actually closed were still
> written here as open and are now marked in place; **P1-11 is complete**; and
> the review found **defects nobody had looked for**, every one of them by
> reading renders rather than source:
>
> 1. **The schedule's weekday row said nothing.** The day strip and the repeat
>    picker abbreviated a weekday as `AppDate.weekdayOf(d).substring(0, 2)`,
>    and every Arabic weekday begins «ال» — so all seven columns drew the same
>    two characters, at every width and every text size. They now draw the
>    conventional distinct initials `س ح ن ث ر خ ج`, each column is one
>    semantics node that says the whole day, and a source guard rejects the
>    next cut weekday name.
> 2. **The notification badge swallowed its own icon.** At 320 dp / 1.6× the
>    count grew to the width of the 24 dp bell and covered it. The count still
>    scales, now to a clamp, and the badge sits at the corner of the glyph
>    instead of on top of it.
> 3. **Two numeral systems on one screen, three times.** Platform Overview's
>    attention rows («2 تنبيه أمني»، «1 اشتراك») beside Arabic-Indic summary
>    rows; the trial-extension sheet's «إضافة 7 يومًا» directly above
>    «٢٥ أيلول ٢٠٢٦» — which was also the wrong plural for seven; and the
>    report range guard's «أطول فترة مسموحة 90 يوماً». The workshop capacity
>    failure printed a Latin count too.
> 4. **The tenant render harness never rendered dark.** It read
>    `AppThemeChoice.defaultMode`, which is Light for all six palettes since
>    the palette ruling, so the two shots named "dark" were light ones. Dark
>    is a parameter now, and Home in dark was reviewed on a real dark render.
>
> Everything else was verified and left alone. See `HANDOFF.md` §"UI QUALITY
> PROGRAMME — PHASE 3C".

### Phase 3C closure ledger

| Finding still open after Phase 3B | Final disposition |
| --- | --- |
| **P1-11** — ` · ` where a numeral can neighbour it | **✅ RESOLVED (Phase 3C)** — the last six joins are gone, including `AppDate.dayMonthTime`; prose separators remain by decision |
| `'٪'` literal in `detachment_stats_tab.dart` | **✅ RESOLVED (Phase 3A)** — the tab renders through `AppNumber.percent`; the audit line was stale |
| Home's filled alert button / two empty cards / ragged shortcuts / 16 px switcher | **✅ RESOLVED (Phase 3A)** — four P2/P3 lines Phase 3A closed and did not mark |
| Organization ~60 % empty at 390 dp | **INTENTIONALLY RETAINED** — the snapshot holds three facts; nothing was invented, and the measure renders correctly at four widths |
| Platform reports — "the four reports" light pass | **✅ REVIEWED (Phase 3C)** — separators are painted, the filter button is content-width, and the range guard now prints Arabic-Indic |
| Tenant Subscription / Limits — "leave alone" | **✅ REVIEWED (Phase 3C)** — one real defect found and fixed (the trial-extension figures); the rest is unchanged |
| Main Admin seat — follow the Tenant Detail pass | **INTENTIONALLY RETAINED** — its renders show the Phase 2 hierarchy already; no button stack survives |
| Notifications Center / Needs Review / Detachment list chevrons | **✅ RESOLVED (Phase 1)** — `ForwardChevron` everywhere, enforced by the design-system guard |
| Simple Admin management — shared confirmation | **✅ RESOLVED** — `showAppConfirmation` is what the page calls |
| Demo shell / trial banner — *not assessed* | **✅ REVIEWED (Phase 3C)** — one notice, 48 dp actions, and it stacks rather than squeezes past 16 sp |
| Login spells its own spacing and type | **INTENTIONALLY RETAINED** — tokenising Login's rhythm is a change to the one screen the audit calls the bar; out of scope for a closure pass |
| `Directionality` overrides that could be `Bidi.ltr` | **OPTIONAL FUTURE POLISH** — each wraps a single value and is correct; one was removed where it sat beside a defect being fixed |
| Wall-clock reads outside the injected clock (Needs Review, notifications, member status, shifts tab) | **OPTIONAL FUTURE POLISH** — presentation-only "how long ago" reads; none was flagged by the audit and none changes a stored value |
| The five Phase 3A Home/Statistics data gaps | **BACKEND/DATA DEPENDENCY** — re-verified in code, unchanged, and no UI claims the data exists |
| Workshop payment authority · real `.xlsx` export | **BACKEND/PRODUCT DEPENDENCY** — the register records payment locally and the export button says «Excel (CSV)», which is what it writes |

Phase 3C produced **256 renders** with the existing harnesses, inspected the
representative set by eye, and re-rendered the touched regions after each fix.
Its validation is **2451 / 2451** tests (2442 + 9 new), clean analysis and
diff checks, and a verified debug APK; see `HANDOFF.md` §"UI QUALITY
PROGRAMME — PHASE 3C" for the exact gates and the file list.

**Method.** Source inspection of every screen listed below, plus **202 real renders**
produced with the repository's own harnesses (`test/features/**/​*_render.dart`,
`--tags render --update-goldens`, `MTM_RENDER_DIR=…`). No screenshot infrastructure
was added. Renders covered 320 dp / 390 dp / 600 dp / 900 dp, 1.6× text, Light,
Dark, Eye Protection and four palettes. Claims in this document that say "visible
in the render" were read off a rendered PNG, not inferred from code.

**Coverage gap at the time of the audit.** Render harnesses exist for the Platform
surface, Break-glass, Audit, Main-Admin-seat, Organization/Plan, Simple Admin and
Onboarding. **There is no render harness for the tenant operational screens** —
Home, Detachments, Team, Shifts, Inventory, Statistics, Workshops, Notifications,
Sync. Those were audited from source plus the one Home render that the
Simple-Admin harness happens to produce. **Closed after the audit:** Phase 1
built `test/features/tenant/tenant_render.dart`; Phase 3B reused it for 61
passing, inspected renders across the touched tenant screens.

---

## Executive Summary

**Overall state: MINOR POLISH → NEEDS CLEANUP, not redesign.** Leader is a
well-built product with an unusually disciplined foundation — a six-palette token
system with contrast enforced by test, real loading / empty / offline / error /
permission states on nearly every surface, capability gating that never renders a
dead control, and code comments that argue for their own design decisions. Most
screens are *correct*. What they are not yet is *uniform*, and the gap between the
best screen and the median screen is what makes the product read as
work-in-progress rather than finished.

**Strongest areas**
- **Login** — the reference. One panel, one CTA, a deliberate spacing rhythm, a
  calm ground, and a sign-off. Nothing else in the app is composed this carefully.
- **The Platform primitives** — `PlatformPage`, `PlatformAppBar`,
  `showPlatformConfirmation*`. A 720 dp reading column, a single header shape, and
  a three-severity destructive-confirmation dialog that states what changes *and*
  what does not. This is genuinely good product design.
- **Team roster (Detachment → الفريق)** — search, a filter sheet, removable active
  filter chips, a roster header with count, and four genuinely distinct empty
  states. This is the best list in the app and should become the pattern.
- **Sync Center and Needs Review** — the two screens most at risk of leaking
  engineering vocabulary, and they do not. Plain Arabic, one obvious button.
- **Break-glass** — calm, restrained, correct.

**Weakest areas**
- **Platform Commerce** — the only screen that tells the operator it is not real
  («للتطوير فقط»), uses state adjectives as menu commands, and puts a status chip
  in the avatar slot.
- **Main Admin Home when the day is quiet** — the render shows two near-empty
  cards, one alert and four chips, then 55 % blank screen. It never answers
  "what needs my attention across the organisation".
- **Statistics** — two unlabelled 7-bar sparklines normalised to their own maximum.
  A coverage series of 40/42/41 % draws identically to 90/95/92 %.
- **SaaS Tenant Detail** — six full-width buttons, three of them filled primary;
  "suspend the team" carries the same weight as "open the subscription page".
- **Platform Audit Log** — four lines per row, no date grouping, two numeral
  systems in one row, machine timestamps ending in the token `UTC`.

**The three consistency problems that cost the most**
1. **Forward navigation chevrons point backwards in Arabic on 13 surfaces.**
   `Icons.chevron_left_rounded` declares `matchTextDirection: true`
   (`flutter/lib/src/material/icons.dart:5496`) and `Icon` mirrors it under RTL
   (`flutter/lib/src/widgets/icon.dart:334-342`), so a `chevron_left` drill-in
   arrow renders pointing **right** — "back" — in Arabic. The canonical
   `SettingsRow` gets this right with `chevron_right_rounded` and documents why.
   Both behaviours are visible side by side in the renders: Platform → Operations
   rows point left (correct), Platform → Overview attention rows point right.
2. **Two surfaces, two design languages.** The Super Admin surface has a reading
   column, a header primitive, a confirmation primitive and accessible
   navigation. The Main Admin surface has none of the four. The later-built
   platform code is the better-engineered half of the product, and the tenant
   half — the part customers actually live in — has not been brought up to it.
3. **One control, ten implementations.** "Filter this list by status" is solved
   nine different ways in private widgets plus five uses of Material's own chips,
   and the Super Admin's selected filter (tinted fill, brand-coloured label) looks
   nothing like the Main Admin's (solid brand fill, inverted label).

**Verdict: is it ready for a paying customer?** The Super Admin surface is, once
Commerce stops announcing that it is a test build. The Main Admin surface is
*functionally* ready and *visually* about one pass short — the individual screens
are fine, but the seams between them are visible, and Home does not yet look like
the front page of a product someone pays for.

---

## P0 Findings

**None.** Nothing audited is broken, unusable, or dangerously ambiguous enough to
qualify. No overflow was found at 320 dp / 1.6× on any rendered screen; every
destructive action is behind a confirmation; every error state exists. The most
severe findings are P1 and are about polish, consistency and hierarchy, not
failure. P0 is left empty deliberately rather than inflated.

---

## P1 Findings

### P1-1 · Forward chevrons point backwards in RTL on 13 surfaces
**✅ RESOLVED (Phase 1).** `core/widgets/forward_chevron.dart` now owns the
rule: `ForwardChevron` for disclosure, `DirectionalArrows.earlier`/`.later`
for a timeline. All 13 surfaces fixed, plus the swapped week arrows, plus
`NavigationRow` and `link_team_page` migrated so they are correct by
construction. `forward_chevron_test.dart` asserts what the glyph *physically
points at* in RTL and LTR and that it mirrors exactly once;
`design_system_guard_test.dart` fails the build if any other file names a
rounded chevron.

`Icons.chevron_left_rounded` is a mirroring glyph. Under `Directionality.rtl`
Flutter flips it, so it renders as `>` — pointing away from the direction the user
travels. Confirmed visually on Platform Overview and Platform Security renders.

Affected: `home_page.dart:504`, `platform_overview_page.dart:329`,
`platform_security_page.dart:336`, `platform_reports_catalogue_page.dart:91`,
`platform_activity_report_page.dart:342`, `global_search_page.dart:779`,
`needs_review_page.dart:253`, `notification_row.dart:165`,
`detachment_announcement_strip.dart:92`, `detachment_group_list_page.dart:248`,
`detachment_member_status_page.dart:399`, `detachment_stats_tab.dart:526`,
`sync_settings_section.dart:537`.

Correct today: `settings_widgets.dart:181` (with the explanation),
`link_team_page.dart:425`.

**Also:** `detachment_shifts_tab.dart:287-313` has the two week-navigation arrows
**swapped** — "previous week" draws `chevron_right` (renders left) and "next week"
draws `chevron_left` (renders right) — and the comment above it misstates how the
mirroring works.

**Action:** one shared `ForwardChevron` widget; delete the raw icon constants from
call sites. Effort: **small**.

### P1-2 · The tenant bottom navigation is invisible to a screen reader
**✅ RESOLVED (Phase 3B).** `_GlassTab` now exposes one button semantics node
with the Arabic destination label and `selected` state, while
`ExcludeSemantics` prevents the visible icon/active text from being announced a
second time. Destination order, branch order, routes, glass visuals and tap
behaviour are unchanged; focused RTL accessibility tests cover all destinations.

`core/widgets/glass_bottom_nav.dart` contains no `Semantics`, no `Tooltip` and no
`selected:` flag, and by design shows a text label only on the *active*
destination. Three of four primary destinations are therefore unlabelled icons
with no accessible name and no announced selection state — on the bar that is
present on every tenant screen.

The fix already exists in the repo: `platform_navigation.dart:173-181` wraps each
destination in `Semantics(selected:, label:, button:)` + `ExcludeSemantics`, and
its doc comment explicitly says it did not reuse `GlassBottomNav` because that bar
"hides every label but the selected".

**Action:** port the platform bar's semantics wrapper onto `_GlassTab`. Decide
separately whether inactive labels should be visible. Effort: **small**.

### P1-3 · The tenant side has no destructive-confirmation pattern
**✅ RESOLVED (Phase 1).** The platform dialog was lifted into
`core/widgets/confirmation_dialog.dart` as `showAppConfirmation` with
`ConfirmationSeverity`. `showPlatformConfirmation*` are thin wrappers over it
and keep their widget keys, so no platform call site or test changed. Adopted
on four representative tenant flows — delete member, delete stock item,
archive workshop (`warning`), cancel Simple Admin invitation (`destructive`).
The remaining tenant `AlertDialog`s are listed in the design-system guard's
allowlist with a reason each; most are not confirmations.

The platform side has three typed helpers (`showPlatformConfirmation`,
`…Spec`, `…FinalDeletionConfirmation`) with `normal / warning / destructive`
severity, a filled `c.crit` confirm button, a selectable identity line and an
explicit *what changes / what does not change* pair.

The tenant side hand-rolls `AlertDialog` in 13+ files. The pattern there is a
plain `TextButton` with a crit **foreground** for "حذف" sitting at equal visual
weight beside "إلغاء", with the record's identity concatenated into the body with
`'\n\n'`:

```dart
// detachment_member_edit_page.dart:234 and inventory_item_edit_page.dart:284
content: Text('${member.name}\n\n${S.deleteMemberBody}'),
…
TextButton(style: TextButton.styleFrom(foregroundColor: c.crit), child: Text(S.delete)),
```

So the Super Admin gets a rigorous safety ritual and the Main Admin — who deletes
members, deletes stock items, archives detachments and cancels invitations — gets
the weaker one.

**Action:** lift the platform dialog into `core/widgets/`, adopt it on the tenant
side. Effort: **medium**.

### P1-4 · Ten implementations of "filter this list"
**✅ RESOLVED (Phase 1).** `core/widgets/filter_chips.dart` —
`AppFilterChip` + `AppFilterBar`, category A only. Six implementations
retired, including both byte-identical `_Filter` copies and the platform's
opposite selected treatment, so the two surfaces now look like one product.
The bar wraps, so neither the platform tenants list nor the storage tab clips
a chip out of reach any more. The Team roster's multi-select sheet keeps
Material `FilterChip`s deliberately — see the Phase 1 handoff.

`_Filter` ×2, `_FilterChip` ×2, `_Chip` ×2, `_Chips`, `_Pill`, `_FilterGroup`,
`_FilterButtonRow`, plus five files using Material `ChoiceChip` / `FilterChip` /
`SegmentedButton`.

`detachment_list_page.dart:287` and `workshop_list_page.dart:175` are
**byte-identical copies** of the same class. `platform_tenants_page.dart:391`
renders the *same control* with an opposite selected treatment: the tenant pills
fill solid `c.primary` with `c.primaryInk` text; the platform chip fills
`c.primaryTint` with `c.primary` text and Material stadium metrics. A user moving
between the two surfaces sees two products.

They also disagree on overflow: tenant lists `Wrap` to a second row; the platform
list scrolls horizontally with a hard clip and no fade, so the sixth chip is
invisible with no affordance (visible in `light-tenants.png`).

**Action:** promote the Team tab's search-bar + filter-sheet + active-chips pattern
to `core/widgets/`, then retire the pill rows. Effort: **medium**.

### P1-5 · The tenant surface has no reading column
**✅ RESOLVED (Phase 1) for the flagged surfaces.**
`core/widgets/reading_column.dart` holds one four-stop measure scale (420 /
440 / 520 / 720); `kPlatformContentMaxWidth` is now an alias of the 720 stop
and `PlatformPage` uses the shared primitive. Applied to Settings, Themes,
Sync, Pricing, Organization and Plan — the last two through
`OrganizationPageWidth`, which caps below the 760 dp two-column breakpoint and
lifts above it, so the reflow those screens already had is preserved.
`11-plan-600-light.png` is now a centred 520 dp column. Home, Detachments,
Team, Shifts, Inventory, Statistics and Workshops are **still uncapped** and
belong to the Phase 3 screen pass.

`kPlatformContentMaxWidth = 720` caps every platform page. The tenant side has
**no equivalent** — the only `maxWidth:` constraints outside `/platform/` are
`glass_bottom_nav.dart:131` (380), `status_screen.dart:114` (520) and
`upgrade_required_page.dart:72` (420). Home, Detachments, Team, Shifts, Inventory,
Statistics, Workshops, Settings, Organization and Plan all stretch edge to edge.

Visible in `09-plan-600-light.png`: at 600 dp a usage row puts its label at the
far right and its figures at the far left with ~1 000 px of nothing between them.
It gets worse on a tablet or a landscape phone.

**Action:** a `TenantPage`/`ReadingColumn` wrapper mirroring `PlatformPage`.
Effort: **medium**.

### P1-6 · Platform Overview buries the thing it exists for
**✅ RESOLVED (Phase 2).** The hero block is gone: `PlatformSectionHeader`
was replaced across the whole surface by `PlatformPageIntro` — one lead
sentence, no tile, no heading that repeats the app bar. The page now opens on
a status strip (health chip, freshness, one refresh control) and the attention
list follows immediately; in `phase2-light-overview.png` «يحتاج إلى انتباه»
starts at about 17 % of the viewport instead of 36 %. The five equal tiles
became three weights: the two figures an operator can act on (tenants
requiring attention, running demos) lead and carry severity — `crit` when a
team is suspended or pending deletion, `warn` in a grace window, quiet when
zero — and the three that describe the size of the business are one card of
label↔value rows underneath. Every figure the page had is still there. The
duplicate refresh affordance went with it (P3): the app-bar icon is gone and
the control sits on the strip beside «آخر تحديث قبل ٦ د», keeping its widget
key and gaining a tooltip. `_UsageSection`'s `~/ 1 GiB` became
`tenantBytesLabel`, so «١٨ غ.ب من ١٠٠ غ.ب» replaces «٠ غ.ب من ٢٠ غ.ب» (P3).

*(original finding)* The page opens with a 52 dp tinted tile, the heading «منصة ليدر» and a lead
paragraph — ~270 px before any data, on top of an app bar that already says
«المنصة». In `light-overview.png` the attention list starts ~36 % down the
viewport; on a 390×844 phone the «يحتاج إلى انتباه» heading lands at the fold.

The five metric tiles are also visually equal and all render their number in
`c.primary`, including **«سماح أو إيقاف»** — a count of tenants in trouble, drawn
in the same brand green as «فرق SaaS».

**Action:** keep every figure. Drop the hero block to a single line, lift attention
above the fold, and give the two risk metrics a severity treatment. Effort:
**medium**.

### P1-7 · Platform Commerce does not read as a commercial control panel
**✅ RESOLVED (Phase 2).** The domain is untouched — $6 / $14 / $24 / $40,
full access on every duration, promotions on one and three months only, no
stacking, no redemption, no payment. What changed:

* **Verbs.** The popup menu reads «تعطيل» / «تفعيل» / «حذف العرض», not the
  state adjective. The adjective stays on the chip, where it belongs.
* **Chips trailing.** `StatusChip` left `ListTile.leading`; the row is now
  title (or coupon code) + state chip in a `Wrap`, a metadata line of the
  facts an operator compares offers by (duration, discount, final price,
  public/targeted, the account when targeted), and one labelled menu.
* **One create affordance per list**, as a `SectionHeader` action with a `+`
  glyph, instead of two competing full-width `FilledButton`s mid-scroll.
* **Real `unchanged` copy** — `S.platformCommerceUnchanged` says what does not
  change, rather than reusing the page's own description paragraph.
* **`destructive` on remove**, `warning` on disable, `normal` on enable, each
  with the record's identity on the dialog's identity line.
* **Base pricing as an admin view**: label↔value rows with the effective
  monthly price, not four marketing cards.
* **The editors** gained section headings, `kFormMaxWidth`, a live price
  preview, an availability switch whose title is no longer the same word as
  its subtitle, and one primary save beside a secondary «إلغاء».
* **The build note stays** at the foot, unchanged — the build does not take
  payment and the panel says so once, quietly.

*(original finding)*
- A `StatusKind.warn` chip «للتطوير فقط» sits directly under the header, and the
  Operations row that leads here says «إدارة محلية للاختبار فقط. لا تمثل دفعاً أو
  صلاحية تجارية في الإنتاج.» The screen announces it is not production.
- The popup menu uses the **state adjective as the command**:
  `offer.enabled ? S.platformCommerceDisabled : S.platformCommerceEnabled` — the
  menu item reads «معطّل» where it should read «تعطيل». The same constant is the
  chip label *and* the action label.
- `StatusChip` is passed to `ListTile.leading`, so the enabled/disabled word takes
  the avatar slot and the variable chip width leaves every title on a ragged edge.
  Everywhere else in the app a StatusChip is trailing or inline.
- Two full-width `FilledButton.icon` create actions mid-scroll — two competing
  primaries on one page, while `PlatformPage`'s single FAB slot goes unused.
- `showPlatformConfirmation(unchanged: S.platformCommerceLead)` fills the "what
  does not change" slot with the **page's own description paragraph**.
- Removing an offer or coupon is permanent but is confirmed with `warning: true`,
  not `destructive`.

**Action:** verbs for actions, chips to trailing, one create affordance, real
`unchanged` copy, `destructive` severity on remove, and a decision about the
dev-only banner. Effort: **medium**.

### P1-8 · SaaS Tenant Detail has no action hierarchy
**✅ RESOLVED (Phase 2).** Four of the six buttons were navigation and are now
`NavigationRow`s inside the card they belong to — Main Admin, subscription,
usage and limits, features. The only buttons left on the page are the two that
change state, and they are the lifecycle section's, which the audit calls
CLEAN and which was not otherwise touched: suspending a customer no longer
looks like opening a subscription page. The four muted footnotes moved *inside*
the cards they annotate. The identity card leads with the name, the lifecycle
chip and the subscription line, then the Team Code (copyable), then the tenant
id — labelled «المعرّف», kept because routing to a team by id is real Super
Admin work (§24) and never the hero identity.

*(original finding)* Six full-width buttons in one scroll (`tenant-detail.png`): «إيقاف وصول الفريق»
(filled), «بدء طلب الحذف» (outlined crit), «إدارة حساب المدير الرئيسي» (filled),
«إدارة الاشتراك والخطة» (filled), «الاستخدام والحدود» (outlined), «الميزات»
(outlined). Three filled primaries, and **suspending a customer** is styled
identically to **navigating to a subscription page**.

Each of the six cards also carries a muted explanatory paragraph *below* it —
four of them on one screen. The page is more prose than control.

**Action:** navigation becomes `NavigationRow`s; only state-changing operations
keep button treatment; footnotes collapse into the cards they annotate. Effort:
**medium**.

### P1-9 · Main Admin Home answers the wrong question
**✅ RESOLVED (Phase 3A).** Home's question is now stated and answered:
*what needs my attention today, in the detachment I am running.* The
hierarchy is **page context → attention → today → the standing facts →
shortcuts**, and each block is drawn only when it has something to say.

* **Attention leads**, above the day, and does not exist at all when nothing
  is raised. Its heading is «يحتاج قرارك» only when something genuinely asks
  for a decision, and «للعلم» when the only thing listed is the user's own
  queued work — a heading that claims a decision every time a device goes
  offline is how a screen teaches people to ignore it. Each row carries a
  **severity word** — عاجل / مهم / للعلم — because a tint and a glyph are not
  a carrier, and each row is a **navigation row with a chevron**, not a filled
  button. (The old row asked for `FilledButton.tonal`; Flutter paints that
  from the same `FilledButtonTheme`, so the "tonal" action on a warning row
  was brand green.)
* **The two near-identical empty cards are one card.** `TodayCard` carries the
  calm strip, what is running (or one sentence saying nothing is — and a
  *single* sentence, «لا شفتات اليوم، ولا شفت قادم مجدول», when the day is
  empty in both directions), and what is next as a compact row rather than a
  peer surface.
* **The quiet day is a designed state**: an `ok`-tinted strip inside the day's
  card saying what was checked, then the standing facts — roster, today's
  shift count, the store's verdict — on one `AppMeta` line. All three are
  read from state the dashboard already loaded; the store fact is withheld
  entirely from a session that may not read the store, rather than reported
  as «لا مخزن».
* **The organisation block is gone as a card** and is one fact on the page
  context — «من ٤ مفرزات» — beside a switcher that is now a real control with
  its own name, rather than a 16 px double chevron.
* **Two quick actions were removed**: «المفرزات» opened a bottom-navigation
  branch and «المؤسسة» a settings page two taps inside another one. Neither
  saved a step. The remaining four jump straight into this detachment's tabs
  (three taps saved) and sit in a `TileGrid` rather than a ragged `Wrap`.
* **Width**: class B of the measure policy — `kContentMaxWidth`. The 900 dp
  render no longer puts an alert's title at one edge of the window and its
  action at the other.

*What was **not** done, deliberately:* Home is still **one detachment at a
time** (`DETACHMENT-SCOPING.md` §4). A cross-detachment attention roll-up
needs an aggregate no repository can currently produce, and inventing one was
out of the question — it is recorded as a data gap in `HANDOFF.md` instead.

### P1-10 · Statistics charts cannot be read
**✅ RESOLVED (Phase 3A).** The scale is decided by the metric's **unit**, in
`core/chart/series_scale.dart`, and never by the data:

* a **percentage** is drawn against **0–100**, always. `series_scale_test.dart`
  holds the original complaint as an assertion: 40/42/41 % and 90/95/92 % must
  not draw alike, and neither peak may touch the ceiling;
* a **count** is drawn against **0 to the smallest of 1, 2 or 5 × 10ⁿ above
  the peak**, and that ceiling is printed («المقياس ٠–٥٠»), because a bar
  whose height is a fraction of an unstated maximum says nothing;
* **two units never share a scale**;
* a series with fewer than two readings, or one that is all zeros, is **not
  drawn** — it gets a sentence.

`SeriesCard` prints the period («٦ أيلول – ١٢ أيلول»), a **day number under
every bar** (which is the part that told a reader nothing, and in Arabic the
row runs right-to-left so guessing which end is today was a coin toss), the
**latest** reading as the headline figure rather than «الأعلى», the change
against the day before **in words**, and the high, average and scale on one
`AppMeta` line. The whole card carries one semantics sentence, so a reader who
gets no picture still gets the metric. The `'٪'` literals on this screen — and
the `Icons.percent_rounded` glyph above one of them, which is the **Latin** `%`
— now go through `AppNumber.percent`.

Also on this screen, beyond the finding: the four glance tiles reflow to two
columns rather than truncating their labels at 1.6×; the attendance totals are
label-over-value tiles rather than `·`-joined strings in a fixed 148 dp box;
every member row is an `AppMeta` line; the range and the week query read the
`clockProvider` rather than the wall clock; and the coverage tile reports
«—» for a week with no shifts instead of a perfect «١٠٠٪».

### P1-11 · The `·` separator is indistinguishable from the Arabic-Indic zero
**✅ RESOLVED (Phase 2 — Platform; Phase 3A — Home, Statistics and the shared
layer; Phase 3B — the touched tenant screens; Phase 3C — the last six
number-adjacent joins).**

*(Phase 3C)* The closure pass swept every remaining ` · ` in `lib/` and split
them in two: joins between words, which stay, and joins where a numeral sits
on either side, which do not. Six were left and all six are gone —
`AppDate.dayMonthTime` itself (read by Organization's «آخر قراءة», the SaaS
tenant detail, the lifecycle section, the feature-availability report,
break-glass copy and the attendance PDF), the Sync Center's last-success
stamp, Settings → Security's session row (which also stopped overriding
`Directionality` around its clock), the report preview's generated-at line,
the search result for a shift, and the conflict record's day line. The
remaining ` · ` in the app are prose — «الورشة · مركز حرستا», «التصفية ·
العنوان» — and they are deliberate.

*(Phase 2 / 3A)* Phase 3A promoted the hairline out of
`features/platform/` into `core/widgets/app_meta.dart` as `AppMeta` /
`AppMetaText`, and `PlatformTime` into `core/format/app_time.dart` as
`AppTime`; the platform names are now `typedef`s of the shared ones, and
`PlatformTime` keeps only the UTC pair, which is the part that is genuinely
about which clock a platform record is kept on. **Tenant code may never
import `features/platform/`, which is why promotion was the only move.**
`AppMetaText` gained the structured kinds — `.day .date .time .dayTime .count
.total .percent .code .money` — so no call site composes punctuation by hand,
and `Bidi.ltr` (`core/text/bidi.dart`) is the one isolation helper: **isolate
the value, never the row.** Adopted on the Home context line, the attention
rows, the next-shift row and the glance line, and on Statistics' member
totals, member records and series cards. **The remaining tenant screens are
still Phase 3B**, as is `AppDate.dayMonthTime`, which nothing in Home or
Statistics reads any more.

*(Phase 2 note)* The separator stopped
being a character: `PlatformMeta` draws a 1 dp vertical hairline whose height
follows the text scale, outside the text run, so it cannot be read as a
numeral, selected, copied or announced. The first attempt at this — a painted
dot — was rejected on its own render, because a dot beside «٠» is still two
dots. Adopted on the Overview's tenant and demo breakdowns, the audit rows,
the security and health snapshots and signals, the tenants list rows, the demo
session rows and policy provenance, the two report row lists, and the commerce
offer and coupon rows. Where the layout genuinely could not change — a plain
string handed to a label/value field — the mark became « — »: the audit detail
timestamp, the report freshness lines, the usage-limits override note, the
tenant-detail storage line. The **tenant surface is untouched and is Phase 3**,
as is `AppDate.dayMonthTime` itself, which both surfaces read by;
`PlatformTime.dayTime` is the platform-side replacement.

*(original finding)* The app joins facts with ` · ` in **115 places across 55 files**, and renders
numbers with `toArabicIndic`, where zero is `٠` (U+0660) — a raised dot.

In `audit-populated-390-dark-cyber.png` the actor line reads
«مدير منصة ليدر ٠ ١٠ أيلول ٢٠٢٦ ٠ ١١:٤٥»: the separators and the digits are the
same mark. The Platform Overview tenant-attention detail
(«١ سماح · ٠ موقوف · ٠ بانتظار الحذف») is worse — a run of five identical dots
where three are values and two are punctuation.

**Action:** for any `·`-joined string that can contain a number, use spacing, a
line break, or a distinguishable separator (« — » or a bullet with wider tracking).
Effort: **medium** (mechanical but broad).

### P1-12 · Internal identifiers are shown as product content
**✅ RESOLVED (Phase 1).** «فرق SaaS» → «الفرق المشتركة»; «الخادم هو جهة
التخويل والتدقيق» → «التخويل والتدقيق يتمّان في المنصة، لا في هذا التطبيق»;
«لقطة التطوير» → «آخر لقطة متاحة»; the tenant-facing slug is now
«الرقم المرجعي للدعم: HILAL» via `OrganizationCopy.supportReference` (the
underlying identifier is unchanged). The slug on **Platform Security is kept
deliberately and labelled** «المعرّف: …» — routing to a tenant by id is real
operational work. The Commerce dev-only chip moved from under the page title
to a note at the foot, with the truthful "no payment happens in this build"
text preserved.

- `09-organization-390-light.png` — a **tenant administrator** is shown
  «معرّف المؤسسة: `saas_hilal`» with a copy button. That is an internal slug.
- `point10-security-320-large-text.png` — the same slug under the affected team.
- `light-overview.png` — the metric label is «فرق SaaS».
- `01-management-none-390-light.png` — «الخادم هو جهة التخويل والتدقيق.» ("the
  server is the authorisation and audit authority") in a user-facing bullet.
- Platform Security copy refers to «لقطة التطوير» — the development snapshot.

**Action:** either a customer-facing account number or nothing; replace «SaaS» and
«الخادم» with product words. Effort: **small**.

---

## P2 Findings

- **Three section-header idioms.** **✅ RESOLVED (Phase 1)** — one `SectionHeader` with a `label`/`heading` style; `SectionLabel` delegates to it; the three identical private `_SectionTitle`s and `workshop_people`'s own are gone, and nine hand-spelled copies of the eyebrow style became `AppTypography.eyebrow`. Break-glass keeps its `titleSmall` sub-heading deliberately.
  *(original finding)* `core/widgets/section_header.dart:6`
  (`SectionHeader`) and `settings_widgets.dart:83` (`SectionLabel`) are
  typographically **identical** — `ink3 / 12 sp / w600 / 0.6 tracking` — differing
  only in padding and an optional trailing action. ~15 and ~40 uses respectively.
  On top of that, four private `_SectionTitle` / `_OverviewSectionTitle` classes
  (`platform_health_page.dart:375`, `platform_break_glass_page.dart:132`,
  `platform_security_page.dart:460`, `platform_overview_page.dart:778`) render a
  third idiom: `titleMedium` plus a primary-coloured icon. Plus
  `workshop_people.dart:574`. One heading, five spellings.
- **Four platform header treatments. ✅ RESOLVED (Phase 2)** — one
  `PlatformPageIntro` on all nine pages that carried `PlatformSectionHeader`,
  plus the tenants list. Break-glass keeps its own inline icon deliberately
  (CLEAN, §44). *(original finding)* Overview/Operations/Health use the tile +
  heading + lead; Break-glass uses an inline icon + lead with no heading; Tenants
  uses a bare subtitle paragraph; Commerce adds a chip under the header.
- **The page title is stated twice at the top of most platform screens.**
  **✅ RESOLVED (Phase 2) on the Super Admin surface** — the app bar states the
  page and the body never repeats it. Login is deliberately untouched (§45).
  *(original finding)* App bar
  «المنصة» then heading «منصة ليدر»; app bar «العمليات» then «عمليات المنصة»; app
  bar «أمن المنصة» then «أمن المنصة» verbatim. Login does it too («ليدر» wordmark
  then «مرحباً بك في ليدر»).
- **Platform Operations is a documentation index. ✅ RESOLVED (Phase 2)** —
  five groups (monitor / customers and trials / commercial / review and audit /
  sensitive authority), short purpose lines instead of each destination's own
  lead paragraph, live counts on the two rows that have synchronous local state
  (running trials, live promotions — each a numeral chip with a spoken plural
  label), and emergency access **last and alone** under a heading that says what
  opening it means, with a `crit` glyph, a chip while a grant is live and a
  one-sentence note. No route changed and no destination was invented; nothing
  network-shaped is read, so the index never spins before it can be navigated.
  *(original finding)* Seven identical
  `NavigationRow`s each carrying a two-line explanation, no counts, no state
  (except break-glass), no grouping. «الوصول الطارئ» — the most consequential
  capability on the surface — has exactly the weight of «تقارير المنصة».
- **Reports catalogue re-implements `NavigationRow`. ✅ RESOLVED (Phase 2)** —
  it is a `NavigationRow` now, with the report's data kind as the row's badge
  instead of a third line of small bold text. *(original finding)*
  `platform_reports_catalogue_page.dart:64-95` hand-builds a `ListTile` with the
  same padding and a two-line subtitle — and picks the wrong chevron in doing so.
- **Audit Log ergonomics. ✅ RESOLVED (Phase 2)** — grouped by local calendar
  day, newest first, with the two most recent days named («اليوم» / «أمس») rather
  than dated; the full date left the row and only the clock stayed; the row is
  three weights (what happened / who and to whom / category); the arrow became
  words, «الحقل: من X إلى Y», with each value LTR-isolated, and integer values
  render Arabic-Indic like every other figure in the product; the row gained a
  `ForwardChevron`; and «تصفية» is a content-width button — it was full-width
  because the theme's `Size.fromHeight(48)` is `Size(infinity, 48)`, the same
  bug the report filter button had. *(original finding)* No date grouping; actor and tenant repeat verbatim on
  every row; the before/after line mixes numeral systems («استثناء الحد: 10 ← 20»
  under an Arabic-Indic timestamp); a Latin-digit pair around a directional arrow
  inside an RTL paragraph is bidi-ambiguous about which value is old; rows have no
  drill-in affordance although they open a detail page; «تصفية» occupies a
  full-width outlined button for one word.
- **Machine timestamps on Platform Security. ✅ RESOLVED (Phase 2)** — now
  «٨ أيلول ٢٠٢٦ | ١٥:٠٤ بتوقيت UTC», on Health too. The instant is unchanged and
  still UTC, because two operators comparing an incident need the same number;
  what changed is the shape and that the timezone is named in Arabic. Each alert
  is one severity chip with the category and the time as plain metadata, rather
  than two differently-shaped chips stacked above the title. *(original finding)* «٢٠٢٦/٠٩/٠٨ · ١٥:٠٤ UTC» — an
  ISO-shaped date and the literal token `UTC` in an Arabic interface, while the
  rest of the product writes «٨ أيلول ٢٠٢٦».
- **Settings hub is mostly headings. ✅ RESOLVED (Phase 3B).** Related rows now
  live in fewer meaningful groups; the existing row primitives are unchanged.
  *(original finding)* Six `SectionLabel`s for nine rows; four
  sections contain exactly one row. «المزامنة» is used as the section heading
  *and* as the row title directly beneath it.
- **Subscription is in two places. ✅ RESOLVED (Phase 3B).** The one
  user-facing door is «الاشتراك والأسعار»; Plan remains reachable through the
  Organization flow, not as a duplicate Settings concept. *(original finding)*
  Section «الاشتراك» → row «الاشتراك والأسعار»
  (sub: «الخطط والأسعار وطرق الاشتراك»), while section «المؤسسة» → row «الخطة
  والاشتراك». Four appearances of the word, two destinations.
- **Pricing page states the same fact twice. ✅ RESOLVED (Phase 3B).** Full
  access is stated once; shared number formatting now owns percentages and
  Arabic-facing duration figures. *(original finding)* `S.pricingFullAccess` as a
  `StatusChip` in the intro and again as a `PricingNote` at the bottom.
- **Workshop register is thinner than the Team roster. ✅ RESOLVED (Phase 3B).**
  It now has search, compact rows, active removable filters, and separate true-
  empty/no-match states on the existing participant model. *(original finding)*
  No search at all, one
  empty state covering both "no participants" and "this filter matched nothing",
  and a third filter idiom (`_FilterChip`) inside a feature whose list page
  already uses a different one (`_Filter`).
- **Dead UI in the Workshop shell. ✅ RESOLVED (Phase 3B).** The permanently
  disabled placeholder was removed; there is no live offline state to wire on
  this shell. *(original finding)* `workshop_detail_shell.dart:96` renders
  `const OfflineBanner(visible: false, lastRefreshedAgoMinutes: 4)` — a
  permanently invisible banner with a placeholder number. It is also the **only**
  use of `OfflineBanner` in the app, so a shared primitive exists that nothing
  uses.
- **Demo session rows carry no status. ✅ RESOLVED (Phase 2)** — name and a
  `StatusChip` on the first line (which changes *word* under an hour, not only
  colour), one metadata line with the remaining time leading and emphasised, then
  the terminate action. `sessionStatus` is called. The list was already sorted by
  what expires soonest — `activeDemoSessionsProvider` does it and says why — so
  no sort was added. *(original finding)* `PlatformDemoCopy.sessionStatus` exists
  and is never called on the page; a row is five stacked lines (name, started,
  expires, remaining, terminate) with no chip, no sort and no filter.
- **Tenant Features screen separates control from label. ✅ RESOLVED (Phase 2)**
  — the switch sits on the title's line, and the consequence sentence appears
  only while the feature is *on*, i.e. only while the switch is about to turn it
  off. *(original finding)* Each row is title +
  chip, a description, a permanent amber consequence sentence, and *then* the
  switch on its own line at the opposite corner — a long diagonal between the
  toggle and the thing it toggles, four times (`features-eye-protection.png`).
- **The FAB is the only elevated surface. ✅ RESOLVED (Phase 2)** — the tenants
  FAB is flat now, like every other surface in the app. *(original finding)* The theme sets `elevation: 0` and a
  hairline border on every card; `FloatingActionButton.extended` on the Tenants
  list reintroduces Material elevation and a shadow.
- **Organization is ~60 % empty** at 390 dp — three facts and a support link.
  **INTENTIONALLY RETAINED (Phase 3B, re-verified Phase 3C)** — the screen
  shows everything the organisation snapshot holds, inside the Phase 1
  measure, at 320/390/600/900. Nothing was invented to fill it.
- **Home's alert action is a filled brand-green button** attached to a
  red-tinted warning row; it is the only filled button on the screen.
  **✅ RESOLVED (Phase 3A)** — an attention row with a severity word and a
  `ForwardChevron`; no filled button on the screen.
- **Home's two empty shift cards** say "nothing today" and "nothing next" in two
  separate cards. **✅ RESOLVED (Phase 3A)** — one day card that states the
  quiet day once.
- **Home's quick actions wrap ragged** — three tiles then one orphan, and they
  restate destinations already in the tab bar. **✅ RESOLVED (Phase 3A)** —
  «اختصارات المفرزة» is a `TileGrid` under its own heading, and the
  destinations it repeats are the ones a main admin actually re-enters.
- **Arabic plural error. ✅ RESOLVED (Phase 1)** — `tenantResultCount()` in `saas_tenant_copy.dart` handles «فريق واحد / فريقان / ٨ فرق / ١١ فريقا», the way `PlatformDemoCopy` already did for time. *(original finding)* `strings.dart:608` `platformTenantsResultCount = ' فريق'`
  renders «٨ فريق»; 3–10 requires the plural, «٨ فرق». The same product handles
  Arabic plurals meticulously in `PlatformDemoCopy._days/_hours/_minutes`.
- **Session Expired says it twice. ✅ RESOLVED (Phase 3B).** The surface shows
  one localized explanation and keeps `S.signIn = 'تسجيل الدخول'`. *(original
  finding)* `sessionExpiredSub` = «لأمانك، طُلب منك تسجيل
  الدخول مرة أخرى.» and the banner below it = «نحتاج التحقق من هويتك مرة أخرى قبل
  المتابعة.» — and that banner is a **raw Arabic literal** at
  `session_expired_page.dart:29`, not an `S` constant.
- **Two raw literals in shared code. ✅ RESOLVED (Phase 1 + Phase 3A).** `platform_confirmation_dialog.dart:42` (`dismissLabel = 'إلغاء'`) is `S.cancel`, as is the final-deletion step's. The `'٪'` literal in `detachment_stats_tab.dart` went with Phase 3A's one percentage path: the tab renders through `AppNumber.percent` and the sign lives once, as `S.percentSign`. *(Verified again in Phase 3C: no `'٪'` is appended at any call site in `lib/`.)*

---

## P3 Findings

- Five `IconButton`s carry no tooltip. **✅ RESOLVED (Phase 3B):** all audited
  actions now have tooltips, semantics where inference is insufficient, and
  unchanged touch targets/behaviour. `design_system_guard_test.dart` rejects a
  future unlabeled `IconButton`. *(original finding)* `workshop_list_page.dart:54` (create
  workshop, on a priority screen), `_auth_scaffold.dart:30` (back),
  `mfa_setup_page.dart:221`, `inventory_item_edit_page.dart:445`,
  `capability_guard.dart:145`. The other 33 in the app are labelled.
  **Phase 2 checked the Platform surface first (§42) and found none of the five
  there** — every `IconButton` under `features/platform/` already carries a
  tooltip. The one unlabelled platform control Phase 2 did find was the
  commerce row's `PopupMenuButton`, which now has one.
- Platform Overview and Platform Health each offer **two** refresh affordances —
  an app-bar icon and pull-to-refresh. **✅ RESOLVED (Phase 2)**, on Security
  too: one visible control, on the card that carries the reading it refreshes,
  keeping the widget key and gaining a tooltip. Pull-to-refresh is unchanged.
- `platform_overview_page.dart` `_UsageSection` divides bytes by 1 GiB with `~/`,
  so anything under a gigabyte reads «٠ غ.ب من ٢٠ غ.ب». **✅ RESOLVED (Phase 2)**
  — it calls the shared `tenantBytesLabel`, which falls back to megabytes.
- «الثيمات والأداء» is a transliteration. **✅ RESOLVED (Phase 3B):** all
  user-facing variants use «السمات»; internal filenames and concepts stay
  unchanged. *(original finding)* «السمات والأداء»
  is the Arabic word, and is what HANDOFF.md and CLAUDE.md still call the screen.
- `detachment_list_page.dart:287` and `workshop_list_page.dart:175` are literal duplicates — delete one. **✅ RESOLVED (Phase 1)**: both deleted, both now use `AppFilterChip`.
- `workshop_list_page.dart:_apply` reads `DateTime.now()` directly rather than
  `clockProvider`, unlike the rest of the time-dependent UI. **✅ RESOLVED
  (Phase 3B):** Workshop filtering, statistics and report generation receive
  the existing injected clock; deterministic tests pin the instant.
- The detachment switcher on Home is a 16 px unlabelled `⌃⌄` glyph — the smallest
  affordance on the screen for one of its more consequential actions.
  **✅ RESOLVED (Phase 3A)** — a bordered pill that says «تبديل», carries a
  button semantics node naming how many detachments it switches among, and is
  not drawn at all when there is only one.

---

## Super Admin

> **After Phase 2 (2026-09-20).** Every Super Admin row below except the three
> marked **do not touch** has been through the pass. Statuses in this table are
> the *original* audit verdicts; the per-finding ✅ marks above are the current
> state. What Phase 2 deliberately did **not** change on this surface: the
> tenant lifecycle suspend/delete flow, Break-glass, Platform More/Profile, and
> `BreakGlassCopy`'s own ` · ` joins (all CLEAN, §44).

| Screen | Status | Problems | Direction | Effort |
| --- | --- | --- | --- | --- |
| **Platform Overview** `/platform` | **NEEDS CLEANUP** · P1 | Hero block pushes attention to ~36 % down; five equal metric tiles with the risk count in brand green; backwards chevrons; duplicate refresh; `·`/`٠` collision in the tenant-attention detail; «فرق SaaS» | Keep every figure. One-line header, attention above the fold, severity on the two risk metrics, one refresh | Medium |
| **Platform Operations** | **NEEDS CLEANUP** · P2 | Seven identical prose rows, no state, no counts, no grouping; break-glass at the weight of reports; commerce row advertises "test only" | Group into *monitor / act / review*; put live state in the subtitles (open alerts, running demos, active break-glass) | Small |
| **Demo Management** `…/demo` | **MINOR POLISH** · P2 | Policy card, stepper and confirmations are good. Session rows have no status chip, no sort, no filter; `sessionStatus` unused; five lines per row | Add the chip, sort by remaining time, collapse the row to two lines | Small |
| **Commerce / Pricing / Offers / Coupons** | **NEEDS REDESIGN** · P1 | Dev-only chip; state adjectives used as menu commands; StatusChip in `leading`; two competing create buttons; page lead reused as dialog reassurance; remove confirmed as `warning` | Make it read as a commercial panel: verbs, trailing chips, one create affordance, `destructive` on remove, and a decision on the dev banner | Medium |
| **Platform Audit Log** | **NEEDS CLEANUP** · P2 | `·`/`٠` collision at its worst; no date grouping; actor+tenant repeat every row; mixed numerals; bidi-ambiguous before→after; no drill-in affordance | Group by day, drop the repeated actor into a compact meta line, isolate Latin/Arabic numeral runs, add the chevron | Medium |
| **Platform Health** | **MINOR POLISH** · P3 | Complete state coverage, clear signals. Private `_SectionTitle`; duplicate refresh | Adopt the shared header primitive | Small |
| **Platform Security** | **NEEDS CLEANUP** · P2 | Machine timestamps with `UTC`; raw `saas_hilal`; six stacked elements per alert; two differently-shaped chips stacked at 320 dp; backwards chevron on the one actionable row | Humanise the timestamp, drop the slug, make the two chips one line, one card shape | Small |
| **Platform Reports (catalogue)** | **MINOR POLISH** · P2 | Re-implements `NavigationRow` and gets the chevron wrong | Use `NavigationRow` | Small |
| **Platform Reports (the four reports)** | **MINOR POLISH** · P3 | Honour the 720 dp column, dense rows above 900 dp. Inspected via `platform_report_widgets.dart` only | Leave alone | — |
| **Tenants list** | **MINOR POLISH** · P2 | Filter row clips its sixth chip with no fade; rows have no drill-in affordance; «٨ فريق» plural; FAB is the only elevated surface; every row leads with `MTM-…` | Fade or wrap the filters, add the chevron, fix the plural | Small |
| **SaaS Tenant Detail** | **NEEDS REDESIGN** · P1 | Six full-width buttons (three filled); suspend at the weight of navigation; four muted footnote paragraphs | Navigation → rows; only state changes keep buttons; footnotes into their cards | Medium |
| **Tenant Features** | **NEEDS CLEANUP** · P2 | Switch on its own line, diagonally opposite its label; permanent amber consequence text on every row | Switch trailing the title; consequence text only when the switch is about to turn off | Small |
| **Tenant Subscription / Limits** | **MINOR POLISH** · P3 | Renders clean in all themes and at 320/900. Inherits the `·` issue | Leave alone | — |
| **Tenant Lifecycle (suspend / delete)** | **CLEAN** · — | Two-step deletion with a typed identity; the strongest destructive flow in the product | **Do not touch** | — |
| **Break-glass** | **CLEAN** · P3 | Calm and correct. Uses a fourth header variant; «الخادم» in a bullet | Header primitive, one word change | Small |
| **Main Admin seat** | **MINOR POLISH** · P3 | Inspected via render only; composed like Tenant Detail and inherits its button-stack weight | Follow the Tenant Detail pass | Small |
| **Platform More / Profile** | **CLEAN** · — | A five-row allowlist, correct | **Do not touch** | — |

---

## Main Admin

| Screen | Status | Problems | Direction | Effort |
| --- | --- | --- | --- | --- |
| **Home / Today** | ✅ DONE (Phase 3A) · P1 | *(was)* No organisation-wide answer; ~55 % empty on a quiet day; two near-identical empty cards; ragged quick-action wrap that duplicates the tab bar; filled green CTA on a warning row; 16 px switcher | Attention → today → facts → shortcuts; one day card; severity words; navigation rows; `kContentMaxWidth` | Large |
| **Detachment list** | **CLEAN** · P3 | Search, three filters, four distinct empty states, archive hint. Bespoke `_Filter`; no reading column | Swap in the shared filter control | Small |
| **Detachment detail shell** | **CLEAN** · — | Title + parent group, capability- and feature-filtered tabs, status strip, announcement strip | **Do not touch** | — |
| **Team roster** | **CLEAN** · — | The best list in the app: search, filter sheet, removable chips, roster header, four empty states | **Do not touch** — promote it instead | — |
| **Shifts / Scheduling** | **NEEDS CLEANUP** · P1 | Week-nav arrows swapped (P1-1) with a comment that misstates the mirroring; day strip and cards otherwise strong | Fix the arrows; re-inspect the day strip at 320 dp with a render harness | Small |
| **Inventory / Storage** | **MINOR POLISH** · P3 | Three purposeful filters, search, historical empty states, a shared 30-day horizon. Bespoke `_Chip`; no "filter matched nothing" state | Shared filter control; one more empty state | Small |
| **Statistics** | ✅ DONE (Phase 3A) · P1 | *(was)* Sparklines normalised to series max, no day labels, no axis, no fixed scale for percentages; `·` in every section title; `'٪'` literal | Unit-decided domains, day numbers, latest-first, change in words, one percentage path, text equivalent | Small |
| **Workshops list** | **MINOR POLISH** · P2 | Mirrors the detachment list well. Duplicate `_Filter` class; create button has no tooltip | Delete the duplicate, add the tooltip | Small |
| **Workshop detail shell** | **MINOR POLISH** · P2 | Archive banner and gating are good. Dead `OfflineBanner(visible: false, …4)`; archive confirmation is a bare `AlertDialog` | Delete the dead banner; adopt the shared confirmation | Small |
| **Workshop register (الأعضاء والضيوف)** | **NEEDS CLEANUP** · P2 | No search on a list that can hold dozens; one empty state for two conditions; a third filter idiom; two action buttons above the filters; `·` in the seats line | Adopt the Team roster pattern wholesale | Medium |
| **Workshop team / stats tabs** | *not assessed* | Read only at the structural level in this pass | Include in the workshop pass | — |
| **Notifications Center** | **MINOR POLISH** · P3 | Mark-all and clear-history actions, grouped by `SectionHeader`, two empty states. Backwards chevron in `notification_row.dart:165` | Chevron fix | Small |
| **Sync Center** | **CLEAN** · — | Five questions in the order they are asked, one button, one relabel for retry, no operation ids or revisions anywhere | **Do not touch** | — |
| **Needs Review / Conflict inbox** | **CLEAN** · P3 | Plain-language intro, honest non-interactive rows for conflicts without metadata, three states. Backwards chevron | Chevron fix | Small |
| **Organization** | **MINOR POLISH** · P1 (copy) | Raw `saas_hilal` shown to a customer; ~60 % empty at 390 dp | Replace the slug; either add content or make it a section of Plan | Small |
| **Plan / Subscription** | **MINOR POLISH** · P1 (responsive) | Good limit rows with deliberate bidi handling and in-words "at limit". Stretches badly at ≥600 dp | Reading column | Small |
| **Pricing** | **MINOR POLISH** · P2 | Clear plan cards and coupon section. States `pricingFullAccess` twice on one page | Remove one | Small |
| **Simple Admin management** | **MINOR POLISH** · P2 | Grouped, localized capability editing with no raw keys; cancel behind a confirmation; states in words. Bare `AlertDialog`s; permission list is long at 1.6× | Shared confirmation; consider grouping the capability list behind disclosure | Small |
| **Settings hub** | **MINOR POLISH** · P2 | Every row leads somewhere real and carries a live summary. Six headings for nine rows; «المزامنة» twice; subscription split across two sections | Merge single-row sections; one subscription destination | Small |
| **Themes & Appearance** | **MINOR POLISH** · P3 | Six palette cards with live previews, appearance, quality, frame rate, logo. Long scroll; «الثيمات» transliteration | Word change; consider collapsing performance behind a disclosure | Small |

---

## Shared / Auth

**Login — CLEAN. This is the bar.** One frosted panel, a capped 440 dp form, a
disabled-until-valid CTA, a divider, Google as a genuine peer, the sign-up row and
«صنع بفخر في العراق» pinned to the bottom of the viewport. Two notes: the brand
mark and the wordmark and the welcome line say «ليدر» twice in three lines; and
the screen spells its own spacing and type (`fontSize: 25`, `SizedBox(height: 13)`,
`letterSpacing: -0.4`) outside the token system, so its quality is **not
transferable** — nothing else can inherit it. If Login's rhythm is the target,
some of it needs to become tokens.

**Signup / OTP / Team-code / Demo choice — CLEAN.** The onboarding renders
(`03-signup-320-1.6x-long-email-short-password.png`,
`05-verify-wrong-code-320-1.6x.png`, `09-team-link-refused-320-1.6x.png`,
`22-choice-320-1.6x-dark-long-email.png`) hold up at 320 dp and 1.6× with long
emails and field errors. No overflow.

**Session Expired — MINOR POLISH.** Says the same thing twice, and the second
sentence is a raw literal (see P2).

**Signed-out Profile — CLEAN.** Correct `EmptyState` with a sign-in action.

**Update required — CLEAN.** Constrained to 420 dp, one action.

**Demo shell / trial banner — MINOR POLISH.** Not rendered in this pass; the
banner copy and the "end trial" relabelling in Settings are correct in source.

---

## Design-System Findings

| Concern | State |
| --- | --- |
| Colour | **Excellent.** One token set, `context.c`, six palettes, contrast enforced by `palette_contrast_test.dart`. No hard-coded colour found outside the entry surface (`EntryGlass`, formerly `LoginGlass`), which is deliberate and is now held to WCAG AA by `test/features/auth/entry_surface_test.dart`. |
| Radius / spacing | **Good.** `AppRadii` / `AppSpacing` used consistently — except Login, which spells its own. |
| Typography | **Good, and now enforced by habit.** `AppTypography` + `AppTypography.digits` for tabular figures. Two widgets had set a `TextStyle` with no family and fell off the app family — `labelSmall` (Phase 2) and `AnimatedTabBar` (Phase 3A, which drew every tab label as placeholder boxes). No widget sets a style that is not derived from a token. |
| Page shell | **Split, narrowing.** `PlatformPage` on one surface; the tenant side has `ReadingColumn` and the shared measure scale, applied to Settings/Themes/Sync/Pricing/Organization/Plan and, since Phase 3A, to Home and Statistics under a written four-class policy. The remaining operational screens (lists, Shifts) are Phase 3B. |
| Section headers | **One** — `core/widgets/section_header.dart`, with a `label` and a `heading` style. Break-glass keeps a `titleSmall` sub-heading deliberately. ✅ Phase 1 |
| Grouped card | **Good.** `SettingsSection` (38 uses) is the de-facto card, and it is a `Material` so ink lands correctly. |
| Navigation row | **Good but bypassed.** `NavigationRow` is correct; two screens re-implement it. |
| Status chip | **Good.** `StatusChip` + `StatusKind` used consistently — except Commerce, which puts it in `leading`. |
| Filters | **One** — `AppFilterChip` / `AppFilterBar`, for dataset filtering. Multi-select sheet chips, form values and status actions stay distinct on purpose. ✅ Phase 1 |
| Buttons | **Improving.** Tenant Detail and Commerce were fixed in Phase 2; Home's filled CTA on a warning row became a navigation row in Phase 3A. Note for every future screen: Flutter paints `FilledButton.tonal` from the same `FilledButtonTheme`, so a "tonal" button in this app is brand-filled. |
| Destructive actions | **One primitive, partially adopted.** `showAppConfirmation` in `core/`; the platform helpers wrap it, and four representative tenant flows use it. The rest of the tenant dialogs are listed in the design-system guard's allowlist. ✅ Phase 1 |
| Dialogs | One shared implementation; the platform helpers are thin wrappers over it. Nine tenant `AlertDialog`s remain and are enumerated — most are not confirmations. ✅ Phase 1 |
| Bottom sheets | **Good.** `showAppSheet` / `SheetScaffold` used consistently. |
| Empty / loading / error | **Excellent.** `EmptyState`, `ErrorStateView`, `SkeletonList`, `AsyncResultView` are used nearly everywhere, and the distinctions (offline-with-cache vs offline-empty, denied vs empty, archived vs empty) are real. |
| Offline | `OfflineBanner` was used **once, invisibly**; Phase 3B deleted that use, so the primitive now has **no call sites**. Offline is communicated by `StaleBadge` and per-screen states. **OPTIONAL FUTURE POLISH (Phase 3C):** adopt it where a real offline state exists, or delete it — a closure pass does not remove code nobody asked to remove. |
| Elevation | Flat + hairline everywhere, except the one FAB. |
| Icons | Consistent rounded set. Direction is now a primitive (`ForwardChevron`, `DirectionalArrows`) and guarded by test. ✅ Phase 1 |

---

## RTL / Responsive Findings

**RTL**
- P1-1, the chevrons — the single biggest RTL defect, on 13 surfaces.
- Swapped week-navigation arrows in the shifts tab.
- The `·` / `٠` collision (P1-11).
- Mixed numeral systems inside one row on the Audit Log — Arabic-Indic timestamp,
  Latin before/after values — and a Latin-digit pair around `←` inside an RTL
  paragraph, which is bidi-ambiguous without isolation.
- **Done well and worth preserving:** `_Figures` in `plan_page.dart:405-420`
  reasons explicitly about bidi ordering for «٢٣ / ٤٠»; `_CouponRow` and the
  base-price rows wrap Latin runs in `Directionality(ltr)`; `Login` forces the
  email field to LTR while keeping it start-aligned; `platform_confirmation_dialog`
  takes an `identityLtr` flag. The app's directional hygiene is good where someone
  thought about it — the failures are all places where nobody did.
- `EdgeInsetsDirectional` / `AlignmentDirectional` usage is broadly correct.

**Responsive** (from the renders)
- **320 dp + 1.6× text: no overflow found** on any rendered screen. Metric grids
  fall to one column, chips wrap, the demo duration stepper keeps its 48 dp
  targets. This is genuinely well handled.
- **600–900 dp: the tenant surface falls apart, the platform surface does not.**
  `09-plan-600-light.png` is the evidence. See P1-5.
- The platform tenants filter row clips its overflow with no affordance.
- Home's quick-action `Wrap` produces a ragged orphan row at 390 dp.

> **Re-verified in Phase 3C.** The chevrons, the week arrows, the numeral
> systems and the ` · ` collision are closed (P1-1, P1-11, the Audit Log pass).
> The 600–900 dp stretch is closed by the four-class measure policy, applied to
> Home and Statistics in Phase 3A and verified again here at 600 and 900. The
> tenants filter row wraps. Home's shortcuts are a `TileGrid` under a heading;
> a five-item grid still leaves one tile on the last row, which is arithmetic,
> not a defect. **New in this pass:** the schedule's weekday row drew «ال» in
> all seven columns (fixed), and the notification badge covered its own icon at
> 1.6× (fixed). No overflow was found at 320 dp / 1.6× on any render, and every
> render asserts `takeException() == null`, so the set is a real overflow gate
> rather than a gallery.

---

## Accessibility Findings

1. **Tenant bottom navigation: no semantics, no labels on 3 of 4 destinations**
   (P1-2). The highest-impact accessibility defect in the product.
2. **Five unlabelled `IconButton`s** (P3).
3. **Touch targets are good.** 48 dp minimums are explicit on the demo stepper,
   Login's text buttons, the demo terminate action and the platform confirmation
   buttons; `FilledButton`/`OutlinedButton` themes set `Size.fromHeight(48)`.
4. **State is communicated in words, not colour alone** — consistently and
   deliberately. Demo availability says on/off under the switch; plan limits say
   "at limit" in words; invitation status is a word; the demo remaining time
   changes *unit* («٤٥ دقيقة») rather than only colour when under an hour. This is
   a real strength.
5. **Contrast** is test-enforced across six palettes, both appearances and the
   eye-protect wash. The eye-protection render is legible.
6. **Text scaling** to 1.6× is handled without overflow, and several widgets
   (`PlatformSectionHeader`'s `Wrap`, the demo duration row, `_Meta`) carry
   comments explaining the large-text choice.
7. **Gaps:** the Platform Overview health card is one `InkWell` wrapping several
   rows that look individually tappable; Home's detachment switcher is a 16 px
   glyph; disabled states rely on Material's default opacity with no additional
   cue.

> **Re-verified in Phase 3C.** (1) and (2) are closed — the bottom navigation
> carries one Arabic semantics node per destination, and every audited
> `IconButton` has a tooltip with a guard that keeps it that way. (3)–(6) hold:
> touch targets, state-in-words, test-enforced contrast and 1.6× scaling were
> re-checked on fresh renders in Light, Dark, Eye Protection and two alternate
> palettes. Of (7), Home's switcher became a labelled pill in Phase 3A. **New
> in this pass:** a day cell announced «س ١٢» and its short-staffed dot was
> status in colour alone — the column is now one node that says «السبت ١٢
> أيلول، نقص في التغطية». Still open as **optional future polish**: the
> Overview health card's single `InkWell`, disabled-state cueing beyond
> opacity, the Team roster's `shrinkWrap` filter chip, and real-device
> screen-reader testing. **Source-level accessibility sweep: clean.**

---

## Copy / Terminology Findings

**Most important**
1. `saas_hilal` shown to a tenant administrator as «معرّف المؤسسة» (P1-12).
2. «فرق SaaS» as a dashboard metric label.
3. «الخادم هو جهة التخويل والتدقيق.» on the break-glass screen.
4. «للتطوير فقط» / «لا تمثل دفعاً أو صلاحية تجارية في الإنتاج» / «لقطة التطوير» —
   build-status language inside product surfaces.
5. Commerce menu items use the state adjective («معطّل») where the command
   («تعطيل») belongs.
6. `unchanged: S.platformCommerceLead` — the page description used as the
   confirmation dialog's reassurance.
7. «٨ فريق» — Arabic plural error on the tenants list.
8. Subscription vocabulary split across two Settings sections.
9. «المزامنة» as both a section heading and the row under it.
10. Session Expired says the same sentence twice, once as a raw literal.
11. «الثيمات» transliteration where «السمات» is the Arabic word.
12. `pricingFullAccess` printed twice on the pricing page.

**Done well:** `PlatformDemoCopy`'s Arabic plural handling; the Sync Center's
refusal to name an operation id, idempotency key or revision; `_ArchiveHint`;
`needs_review_page`'s intro; the distinction between «تجربة» (ending) and «تسجيل
خروج» (signing out) in Settings.

> **Re-verified in Phase 3C.** All twelve are closed across Phases 1–3B. Item 4
> is closed as *stated*, not erased: the Commerce foot-note still says no
> payment happens in this build, because that is true. **New in this pass:**
> four Arabic sentences printed a Latin figure — «2 تنبيه أمني»، «1 اشتراك في
> فترة السماح»، «إضافة 7 يومًا» (also the wrong plural) and «أطول فترة مسموحة
> 90 يوماً» — plus the workshop capacity failure. All now print Arabic-Indic.
> A version string stays Latin deliberately: it is a code, not a quantity
> (`AppMetaText.code`).

---

## Recommended Redesign Order

Ordered by impact per unit of work, and by dependency — the shared primitives come
first so the screen passes can consume them.

0. **Build a tenant render harness** mirroring `platform_render.dart`. Everything
   below is verified by eye or it is not verified. *(small)* —
   **✅ DONE (Phase 1):** `test/features/tenant/tenant_render.dart`, 51 renders
   over 15 screens at 390/320-1.6×/600/900, light, dark, eye-protect, two
   palettes, reduced motion and both tenant roles. It found a 21 px overflow in
   the shifts day strip on its first run.
1. **Fix the chevrons** — one `ForwardChevron`, 13 call sites, plus the swapped
   week arrows. Cheapest visible win in the product. *(small)*  — **✅ DONE (Phase 1)**
2. **Give the tenant bottom nav semantics** by porting the platform bar's wrapper.
   *(small)* — **✅ DONE (Phase 3B)**
3. **Lift `showPlatformConfirmation*` into `core/` and adopt it on the tenant
   side.** Safety and consistency in one move. *(medium)*  — **✅ DONE (Phase 1)**
4. **One filter control.** Promote the Team roster's search + sheet + active-chips
   pattern; retire the ten implementations. *(medium)*  — **✅ DONE (Phase 1)**
5. **One section header.** Collapse `SectionHeader`, `SectionLabel` and the four
   private `_SectionTitle`s into one primitive with an optional icon and action.
   *(small)*  — **✅ DONE (Phase 1)**
6. **`TenantPage` reading column** mirroring `PlatformPage`'s 720 dp cap. *(medium)*  — **✅ DONE (Phase 1) — as `ReadingColumn`; applied to the flagged screens, not yet to Home/Shifts/lists**
7. **Purge internal vocabulary** — `saas_hilal`, «SaaS», «الخادم», «لقطة التطوير»,
   the plural error, the duplicated strings. *(small)*  — **✅ DONE (Phase 1)**
8. **Commerce pass** — verbs, chip placement, one create affordance, `destructive`
   severity, and a decision on the dev-only banner. *(medium)*  — **✅ DONE (Phase 2)**
9. **Platform Overview pass** — compress the header, lift attention above the
   fold, severity on the risk metrics. *(medium)*  — **✅ DONE (Phase 2)**
10. **SaaS Tenant Detail pass** — navigation becomes rows, only operations keep
    buttons. *(medium)*  — **✅ DONE (Phase 2)**
11. **Statistics charts** — fixed scale, day labels, peak value. *(small)*  — **✅ DONE (Phase 3A)**
12. **The `·` separator** wherever it can neighbour a number. *(medium)*  — **✅ DONE in numeric/date/time contexts (Phase 2 + Phase 3A + Phase 3B); clear prose separators intentionally remain**
13. **Audit Log pass** — day grouping, compact meta line, numeral isolation.
    *(medium)*  — **✅ DONE (Phase 2)**
14. **Workshop register** — adopt the Team roster pattern. *(medium)* — **✅ DONE (Phase 3B)**
15. **Main Admin Home** — the big one. Decide its question first; it depends on
    1, 5 and 6 being done. *(large)*  — **✅ DONE (Phase 3A)**

16. **Apply `AppMeta` / `AppTime` / `AppNumber` and the measure policy to the
    remaining tenant screens** — Shifts, Workshops, Workshop register,
    Inventory, Team, Detachments, Notifications, Settings. The patterns exist
    and are documented; this is adoption, not design. *(medium)* — **✅ DONE
    where beneficial (Phase 3B); strong screens kept their structure**

---

## Screen Inventory

| Role | Screen | Status | Severity | Action |
| --- | --- | --- | --- | --- |
| Super Admin | Platform Overview | ✅ DONE (Phase 2) | P1 | Compress header, lift attention, severity on risk metrics |
| Super Admin | Platform Operations | ✅ DONE (Phase 2) | P2 | Group the seven rows, add live state |
| Super Admin | Demo Management | ✅ DONE (Phase 2) | P2 | Status chip, shorter rows (already sorted) |
| Super Admin | Commerce / Offers / Coupons | ✅ DONE (Phase 2) | P1 | Verbs, chip placement, one create, destructive severity |
| Super Admin | Platform Audit Log | ✅ DONE (Phase 2) | P2 | Day grouping, numeral isolation, chevron |
| Super Admin | Platform Health | ✅ DONE (Phase 2) | P3 | Shared header, one refresh |
| Super Admin | Platform Security | ✅ DONE (Phase 2) | P2 | Humanised timestamps, one chip line; the id stays, labelled (§24) |
| Super Admin | Reports catalogue | ✅ DONE (Phase 2) | P2 | Uses `NavigationRow` |
| Super Admin | The four reports | ✅ DONE (Phase 2 + 3C) | P3 | Painted separators, content-width filter button, Arabic-Indic range guard |
| Super Admin | Tenants list | ✅ DONE (Phase 2) | P2 | Chevron, meta line, flat FAB (filters and plural were Phase 1) |
| Super Admin | SaaS Tenant Detail | ✅ DONE (Phase 2) | P1 | Rows for navigation, buttons for operations |
| Super Admin | Tenant Features | ✅ DONE (Phase 2) | P2 | Switch on the title line, consequence only while enabled |
| Super Admin | Tenant Subscription / Limits | ✅ REVIEWED (Phase 3C) | P3 | Trial-extension figures are Arabic-Indic with the right plural; nothing else changed |
| Super Admin | Tenant Lifecycle | CLEAN | — | **Do not touch** |
| Super Admin | Break-glass | CLEAN | P3 | Header primitive, one word |
| Super Admin | Main Admin seat | ✅ INTENTIONALLY RETAINED (Phase 3C) | P3 | Renders already carry the Phase 2 hierarchy |
| Super Admin | Platform More / Profile | CLEAN | — | **Do not touch** |
| Main Admin | Home / Today | ✅ DONE (Phase 3A) | P1 | Attention → today → facts → shortcuts; one day card; the quiet day is designed |
| Main Admin | Detachment list | ✅ DONE (Phase 1) | P3 | `AppFilterChip`; chevron and measure verified in Phase 3C |
| Main Admin | Detachment detail shell | CLEAN | — | **Do not touch** |
| Main Admin | Team roster | CLEAN | — | **Do not touch** — promote it |
| Main Admin | Shifts / Scheduling | ✅ DONE (Phase 3B + 3C) | P1 | Shared metadata/time, labelled controls, 320 dp reflow; Phase 3C gave the day strip seven distinct initials and one semantics node per column |
| Main Admin | Inventory / Storage | ✅ DONE (Phase 3B) | P3 | Shared filter plus distinct empty/no-result states |
| Main Admin | Statistics | ✅ DONE (Phase 3A) | P1 | Unit-decided domains, day numbers, text equivalent, one percentage path |
| Main Admin | Workshops list | ✅ DONE (Phase 3B) | P2 | Shared filter and labelled create action |
| Main Admin | Workshop detail shell | ✅ DONE (Phase 3B) | P2 | Dead banner removed; shared confirmation retained |
| Main Admin | Workshop register | ✅ DONE (Phase 3B) | P2 | Search, compact rows, active chips and two empty states |
| Main Admin | Workshop team / stats tabs | ✅ REVIEWED (Phase 3B) | — | Shared formatting and injected clock; mathematics unchanged |
| Main Admin | Notifications Center | ✅ DONE (Phase 1 + 3C) | P3 | `ForwardChevron` only where a row opens something; bell badge no longer covers its icon |
| Main Admin | Sync Center | CLEAN | — | **Do not touch** |
| Main Admin | Needs Review / Conflict inbox | ✅ DONE (Phase 1 + 3C) | P3 | `ForwardChevron`; the conflict record's day line lost its dot |
| Main Admin | Organization | ✅ INTENTIONALLY RETAINED (Phase 3B) | P1 (copy) | Existing data and Phase 1 measure render cleanly; no invented content |
| Main Admin | Plan / Subscription | ✅ INTENTIONALLY RETAINED (Phase 3B) | P1 (responsive) | Existing responsive reading measure verified at four widths |
| Main Admin | Pricing | ✅ DONE (Phase 3B) | P2 | One full-access message; shared percent/duration formatting |
| Main Admin | Simple Admin management | ✅ DONE | P2 | `showAppConfirmation`; verified in Phase 3C |
| Main Admin | Settings hub | ✅ DONE (Phase 3B) | P2 | Fewer groups, no repeated sync heading, one subscription door |
| Main Admin | Themes & Appearance | ✅ DONE (Phase 3B) | P3 | User-facing «السمات»; six palettes and controls preserved |
| Shared | Login | CLEAN | — | **Do not touch** — tokenise its rhythm instead |
| Shared | Signup / OTP / Team code / Demo choice | CLEAN | — | **Do not touch** |
| Shared | Session Expired | ✅ DONE (Phase 3B) | P2 | One localized explanation; sign-in semantics unchanged |
| Shared | Signed-out Profile | CLEAN | — | **Do not touch** |
| Shared | Update required | CLEAN | — | **Do not touch** |
| Shared | Demo shell / trial banner | ✅ REVIEWED (Phase 3C) | — | One notice, 48 dp actions, stacks past 16 sp |
