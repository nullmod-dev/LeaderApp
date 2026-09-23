# Frontend design notes

Adapted from MTM-PRO’s frontend-design guidance and Flutter translation rules.

## Visual direction

- Make deliberate choices that reflect the actual medical-team task and its Arabic-first audience. Avoid generic “AI dashboard” defaults.
- Typography carries much of the app’s personality. Preserve the supplied IBM Plex Sans Arabic fonts and established type scale unless a request explicitly changes the system.
- Use layout structure, labels, dividers, and grouping to communicate real information—not as empty decoration.
- Reuse the palette and tokens in `flutter_app/lib/core/theme/`; a one-off literal color, radius, font, or spacing value should be a deliberate design-system decision.

## Flutter translation

| Design guidance | Flutter implementation |
| --- | --- |
| Simple visual transition | `AnimatedContainer`, `AnimatedOpacity`, `AnimatedAlign`, `AnimatedSwitcher`, or `TweenAnimationBuilder` |
| Timed or coordinated transition | `AnimationController` with `AnimatedBuilder`, `FadeTransition`, `SlideTransition`, or `ScaleTransition` |
| Spring / physical response | `SpringDescription` and `SpringSimulation`; no additional animation package |
| Smooth performant movement | Prefer `Transform` and opacity; avoid animating layout properties every frame when possible |
| Reduced motion | Check `MediaQuery.disableAnimations` and `accessibleNavigation` |
| Shared route element | Use `Hero` and a deliberate route transition where appropriate |

## RTL and interaction

- Prefer `AlignmentDirectional` and `EdgeInsetsDirectional` over non-directional alternatives.
- Explicitly invert any horizontal `Offset` used by `SlideTransition` when direction requires it; Flutter does not do this automatically.
- Motion should explain hierarchy, confirmation, pending/offline work, conflict, or recovery. It should be interruptible and should not block a critical task.
- A professional operational app benefits from crisp, restrained motion. Do not add decorative animation merely to make a screen feel active.

## Shared UI primitives (Phase 1 of the UI quality programme, 2026-09-20)

Five decisions now live in one place each. Before writing a new screen, reach
for these; `test/core/design_system_guard_test.dart` fails the build when a
file re-implements one, and the failure message says what to use instead.

| Concern | Use | Never |
| --- | --- | --- |
| "This row opens something" | `ForwardChevron` (`core/widgets/forward_chevron.dart`) | `Icons.chevron_left/right_rounded` at a call site, `Transform.flip`, `if (rtl)` |
| Previous / next week, month, period | `DirectionalArrows.earlier` / `.later` | picking a chevron by hand |
| A heading above a group | `SectionHeader` — `label` (eyebrow) or `heading` (titleMedium + tinted icon) | a private `_SectionTitle`, a hand-spelled `ink3/12/w600/0.6` |
| Narrowing a list | `AppFilterChip` inside `AppFilterBar` | another private `_Filter` / `_Chip` / `_Pill` |
| A form value or a status action | `ChoiceChip`, a switch, a button | `AppFilterChip` — it is for datasets only |
| A consequential confirmation | `showAppConfirmation` + `ConfirmationSeverity` | a bare `AlertDialog` with a crit-coloured `TextButton` |
| How wide content runs | `ReadingColumn` + `kDialogMaxWidth` / `kFormMaxWidth` / `kReadingMaxWidth` / `kContentMaxWidth` | a new `maxWidth:` literal |
| Moving a **date** by days | `addDays` / `calendarDaysBetween` (`core/time/calendar_day.dart`) | `date.add(Duration(days: n))` — a calendar day is 23 or 25 hours across a DST change |

### The two mirroring facts worth memorising

1. `chevron_left_rounded` and `chevron_right_rounded` both set
   `matchTextDirection: true`. Flutter mirrors them under RTL, so
   **`chevron_right` is the forward glyph in Arabic** — it paints pointing
   left. Choosing `chevron_left` because "forward is left in Arabic" produces
   a back arrow. This is why the rule is a widget and not a convention.
2. A `matchTextDirection` icon must be mirrored **once**. A manual flip on top
   cancels it out and the icon renders identically in both directions — which
   looks correct in whichever direction you happened to check.

### Verifying by eye

`test/features/tenant/tenant_render.dart` and the platform/onboarding/
organisation harnesses render real screens through the real router. Nothing is
committed — set `MTM_RENDER_DIR` and pass `--tags render --update-goldens`.
Every shot asserts `takeException() == null`, so the 320 dp / 1.6× group is an
overflow gate as well as a picture.

## The Super Admin surface (Phase 2 of the UI quality programme, 2026-09-20)

Phase 2 redesigned the Platform screens on top of the Phase 1 primitives. Four
decisions came out of it that every future platform screen inherits.

| Concern | Use | Never |
| --- | --- | --- |
| What a platform page opens with | `PlatformPageIntro(lead:)` — one sentence, no tile, no repeated heading | a hero block that restates the app-bar title |
| Facts joined on one line | `PlatformMeta` + `PlatformMetaText` (`features/platform/presentation/widgets/platform_meta.dart`) | ` · ` in a string that can neighbour a number |
| A timestamp on a platform screen | `PlatformTime.date/time/dayTime` for a local instant, `PlatformTime.utcDate/utcTime` for a snapshot | `2026/09/08 15:04 UTC`, or `AppDate.dayMonthTime` where the clock can start with «٠» |
| Where a platform screen leads | `NavigationRow` (now with `iconColor` and `badge`) | a full-width `FilledButton` that opens a read-only page |

**The app bar states the page; the body never repeats it.** Every platform page
opened with a 52 dp tinted tile, its own heading and a lead paragraph — about
270 px before any data, on top of an app bar that had already named the screen.
`PlatformSectionHeader` is gone and `PlatformPageIntro` replaced it on all nine
pages that used it.

**The separator is a hairline, not a mark.** ` · ` and the Arabic-Indic zero
`٠` (U+0660) are the same glyph to a reader, and a control plane renders both
constantly. `PlatformMeta` draws a 1 dp vertical rule whose height follows the
text scale, outside the text run: it cannot be read as a numeral, cannot be
selected, and is never announced. It attaches to the *following* item so a
wrapped line never starts with an orphan separator. Where the layout genuinely
cannot change — a plain string handed to a label/value field — use « — », never
a second kind of dot.

**Buttons are for state changes; rows are for navigation.** On a screen that
both opens pages and suspends a customer, drawing both as full-width filled
buttons is the defect. Navigation is a `NavigationRow` inside the section's
card; only an operation that changes something keeps a button, and a
destructive one keeps the outlined-crit treatment under its own sub-heading.

**Hierarchy beats decoration for consequence.** The emergency-access row is the
last group on the Operations landing, alone, under a heading that says what
opening it means, with a `crit` glyph and a live chip — not a tinted card or a
warning banner.

### One more shared fix worth knowing

`AppTypography.build` never defined `labelSmall`, and Material's `ListTile`
uses it for the `trailing` slot — so anything placed there inherited Roboto
instead of the app family, and an Arabic-Indic digit rendered as a placeholder
box. `labelSmall` is defined now, and `StatusChip` paints
`AppTypography.chip(c)` rather than inheriting whatever `DefaultTextStyle` it
lands in.

## The tenant surface (Phase 3A of the UI quality programme, 2026-09-21)

Phase 3A took the two tenant screens that were making claims the data did not
support — Main Admin Home and Statistics — and, on the way, promoted the two
platform patterns they needed into `core/`. Six decisions came out of it.

| Concern | Use | Never |
| --- | --- | --- |
| Facts joined on one line | `AppMeta` + `AppMetaText` (`core/widgets/app_meta.dart`) | ` · ` in any string that can neighbour a number |
| A structured fact on that line | `AppMetaText.day/.date/.time/.dayTime/.count/.total/.percent/.code/.money` | composing `'$label · $value'` at the call site |
| A timestamp anywhere in the tenant app | `AppTime.day/.date/.weekdayDay/.time/.dayTime/.minuteRange/.clockRange` | `AppDate.dayMonthTime`, or a bare `AppDate.time` beside Arabic |
| A percentage, anywhere | `AppNumber.percent` | `'${toArabicIndic(n)}٪'`, and never `Icons.percent_rounded` (a Latin `%`) |
| A daily series | `SeriesCard` + `SeriesPlot` (`core/chart/`) | `value / max(series)` — see below |
| A row of comparable tiles | `TileGrid` | a `Wrap` of intrinsic-width tiles |

### `AppMeta` is the platform's separator, promoted

Phase 2 built the hairline for the Super Admin surface as `PlatformMeta`.
Nothing about a 1 dp rule between two facts is platform-specific, and the
tenant surface had the worse instances: Home's context line rendered
«السبت ٠ ١٢ أيلول ٠ اللاذقية» and a statistics member row rendered a run of
five identical dots of which three were values. The implementation now lives
in `core/widgets/app_meta.dart`; `PlatformMeta` and `PlatformMetaText` are
`typedef`s of it, and `PlatformTime` delegates its three local shapes to
`AppTime` and keeps only the UTC pair, which is the part that is genuinely
about *which clock a platform record is kept on*.

**The dependency runs one way.** A tenant screen may never import
`features/platform/`. That is why promotion — not a second copy, and not a
tenant import of the platform widget — was the only available move.

### Direction is isolated, never overridden

`Bidi.ltr` wraps a value in `U+2066 … U+2069`. A clock, a reference code, an
email, a money amount and a numeric range each keep their own order without
dragging the Arabic around them out of place. A `Directionality` override
would change a whole subtree, which is how a row of Arabic ends up
left-aligned because one id in it needed to read left-to-right. The rule is
**isolate the value, never the row**, and a range is one isolate around the
pair rather than one around each end — two isolates with a dash between them
let the dash resolve against the Arabic and swap which end it belongs to.

### A bar's height is a reading, not a ranking

`core/chart/series_scale.dart` decides a series' domain from its **unit**:

* a **percentage** is always drawn against **0–100**. Normalised to its own
  peak, a coverage series of ٤٠/٤٢/٤١٪ drew pixel-identically to ٩٠/٩٥/٩٢٪
  (UI audit P1-10);
* a **count** is drawn against **0 to the smallest of 1, 2 or 5 × 10ⁿ above
  the peak**, and that ceiling is printed, because a bar whose height is a
  fraction of an unstated maximum says nothing;
* **two units never share a scale.** Coverage and consumption are two cards
  with two stated domains. Making them look alike would be the same lie in
  the other direction;
* a series with fewer than two readings, or one that is all zeros, is **not
  drawn**. It gets a sentence.

The baseline is always zero, and the card says in words everything the
picture says: the period, a day number under every bar, the latest reading,
the high, the average, the scale, and the change against the day before. The
whole card carries one semantics sentence, so a reader who gets no picture
still gets the metric. Change is never an arrow or a colour, and the
magnitude of a percentage change is printed **bare** — a move from ٩٠٪ to
٩٢٪ is two points on a stated 0–100 scale, and «٢٪» is the shorter of the two
readings of that.

### How wide a tenant screen runs

The four-class policy is written out in `core/widgets/reading_column.dart`:
**A** reading/form surfaces take `kReadingMaxWidth`/`kFormMaxWidth`; **B**
operational lists and landings take `kContentMaxWidth`; **C** schedule and
data-dense views take the width they are given; **D** two columns only where
two groups are genuinely consulted together. Home and Statistics are class B
and were capped in this phase. A grid *inside* one of those columns picks its
column count from its own `LayoutBuilder` and the text scale — never from a
window breakpoint, because the grid sits inside a cap the window knows
nothing about.

### Two type defects the renders caught

`AnimatedDefaultTextStyle` **replaces** the inherited style rather than
merging with it, so the detachment and workshop tab bars — the one place in
the app that set a `TextStyle` with no family — dropped their labels off
`IBMPlexSansArabic` and drew every tab as a row of placeholder boxes. This is
the same defect Phase 2 found in `labelSmall`. Both are now built from an
`AppTypography` token, which is the rule: **no widget sets a text style that
is not derived from one.**

And a single Arabic word must never be broken across two lines. At 320 dp and
1.6× a shortcut tile wrapped «الإحصائيات» into «الإحصائيا / ت». A label that
is one word uses `FittedBox(fit: scaleDown)` with `maxLines: 1`, so the word
shrinks rather than breaking — and the floor is still the base size, because
the shrink only ever undoes part of the scale-up.

## Tenant finishing patterns (Phase 3B, 2026-09-21)

Phase 3B established three reusable finishing rules without adding a new
design-system primitive.

### Tabs keep their words; the strip moves

When a tab set cannot fit at 320 dp or 1.6× text, `AnimatedTabBar` gives each
label its natural **single-line** width and scrolls the strip horizontally. It
does not shrink text below the token, wrap a label, or distribute an impossible
width equally. Selection still flows through the existing controller, so the
indicator animation, tap navigation and `SwipeTabs` page/gesture coordination
remain one system. After any selection, the selected render box is revealed by
the strip's `ScrollController`; Flutter's directional scrolling supplies the RTL
behaviour. Each tab remains one labelled, selected/unselected semantics button.

Use this for navigation tabs only. An ordinary filter row still uses
`AppFilterBar` and wraps, because filters are a set of controls rather than a
single current location.

### Large text reflows operational controls

Class-C screens remain uncapped; accessibility is not a reason to turn a weekly
schedule into a narrow reading column. At narrow width with large text, reflow
the **contents** instead: stack competing action buttons, let identity/state
move onto separate lines, and preserve the normal compact row below the large-
text threshold. Do not solve clipping with tiny text or multi-line one-word
labels. The Shifts bulk actions and cards are the reference implementation.

### Empty and no-result are different states

An operational list owns at least two absences: the repository has no records,
or records exist but the current search/filter matches none. The first explains
how to begin and may carry the create action; the second names the active query
and offers clear/reset, never create. Workshop Register and Inventory now apply
this rule on the existing `AppFilterBar`/active-chip architecture.

## Closure notes (Phase 3C, 2026-09-21)

### An Arabic word is not abbreviated by cutting it

Every Arabic weekday begins «ال», so `weekdayOf(d).substring(0, 2)` is the
definite article and nothing else — the schedule's day strip and the repeat
picker drew the same two characters in all seven columns, at every width, for
as long as they existed. Where a column is too narrow for a word, use the
conventional calendar initial (`AppDate.weekdayInitial` → `ن ث ر خ ج س ح`),
never a prefix. The same rule holds for any Arabic noun with a fixed prefix: a
truncation that keeps only the article is not a short form. A source guard in
`design_system_guard_test.dart` rejects the next cut weekday name.

### A one-glyph label still has to say its whole name

Density is a visual decision; the accessible name is not. A control that shows
a letter and a number — a day cell, a compact chip — carries one `Semantics`
node with the full fact («السبت ١٢ أيلول»), its selected state, and any status
the layout communicates only in colour (the day strip's amber dot means «نقص في
التغطية», so the node says so). Exclude the descendants; two nodes for one
control is worse than one terse one.

### Text on top of an icon is the one place scaling is clamped

The app scales text everywhere — that is the accessibility contract. A count
badge drawn *over* a fixed-size glyph is the exception: at 1.6× the
notification badge grew to the width of the 24 dp bell and hid it. Clamp that
subtree (`MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3)`) and seat the
badge at the corner of the icon rather than inside it. Never clamp a line of
prose, a label, or anything the reader is meant to read rather than glance at.

### Figures in an Arabic sentence are Arabic-Indic, including in mock data

A raw `int` interpolated into an Arabic string prints Latin digits, and the
result is two numeral systems in one row — «2 تنبيه أمني» above «٢ فرق تحتاج
إلى متابعة». This applies to the mock repositories too: they are the only data
source this build has, so what they compose is what a reader sees. Use
`AppNumber`/`toArabicIndic`, and carry the plural with the figure when the
count is a fixed set («٧ أيام» / «١٤ يوماً» / «٣٠ يوماً»).

### A render harness that cannot render the mode is not covering it

`shot(...)` in `tenant_render.dart` read `AppThemeChoice.defaultMode`, which is
Light for all six palettes since appearance became its own axis — so the two
shots named "dark" were light ones, and a dark-mode regression could have sat
in a passing render set unseen. Appearance is an explicit parameter now. When a
harness names a condition, check that it actually produces it.

## The entry experience (2026-09-22)

`/startup` and `/login` are one surface with two states, and the rules they
established are reusable by any other screen the app decides to paint outside
`AppColors`.

| Concern | Use | Never |
| --- | --- | --- |
| The Leader mark, anywhere | `BrandMark` (`core/brand/brand_mark.dart`) | a second `assets/brand/…` path; `brand_mark_test.dart` fails on one |
| A colour on the entry screens | an `EntryGlass` token | a literal, and never an `AppColors` token — the palette is a *choice*, and this is the screen before there is a chooser |
| The accent as **text** | `EntryGlass.accentInk` | `accent` — a filled button clears 3:1, a 13.5 sp link has to clear 4.5:1 on the ground |
| A disabled primary action | a real pair of colours | the accent at an opacity |
| Holding a launch for an animation | an input to `resolveStartup` | a delay inside the screen |
| Settling a test tree with an entry screen in it | `settleEntry` (`test/entry_settle.dart`) | `pumpAndSettle` — it never returns |

### The brand is said once per screen

The mark, a wordmark and a welcome heading are three statements of the same
fact. Login used to carry all three above the fold, before anything the person
came to do. The launcher icon and the launch intro have already shown the
mark by the time the form exists, so the form's heading carries the name and
nothing else does. Where a heading would then float, a short accent rule is
enough — a mark is not the only way to put brand at the top of a screen.

### Warming a translucent token is not the same as warming an opaque one

`AppColors.warmed()` lerps toward an opaque warm target, which is correct for
a palette whose every token is opaque. A surface with translucent ground
tokens — ambient washes, a light source, a status wash — cannot use that
transform unchanged: `Color.lerp` interpolates alpha too, so an 8 %-alpha wash
lerped 40 % of the way to an opaque target lands at ~45 % and becomes a
curtain. Warm the hue, keep the alpha
(`Color.lerp(c, target, amount).withValues(alpha: c.a)`).

### Ambient motion is bounded by what it does, not by its alpha

The entry pulse needs roughly twice as much alpha on the light ground as on
the dark one to be equally perceptible, so a single opacity ceiling is the
wrong rule. The rule that holds in both is about the result: a wave at its
brightest frame must stay under 2:1 against the ground it crosses. Past that
it stops reading as light and starts reading as an object with an edge. The
same reframing applies to any glow, halo or shimmer added later.

Two mechanical requirements go with it. A looping ambience widget must use
`TickerProviderStateMixin`, not the single-ticker one, because the quality
level is a live setting and the widget can be asked to give its controller up
and later create another. And it must draw a **fixed frame** when
`MotionSpec.ambientLoops` is false rather than drawing nothing — the screen
should lose its movement, not its composition.

### A hold at launch belongs in the routing decision

The router leaves the launch surface the instant the startup classifier can
answer, which on a warm device is frame two. An intro that only animated would
be cut off and the launch would flash. `IntroGate` therefore feeds
`StartupInputs.introHolding`, which is priority 0 in `resolveStartup` — safe to
put first precisely because it is not an answer: it can only resolve to
`restoring`, the surface the launch already sits on, and it releases itself
after a ceiling whatever the screen does.

Two things follow. Arm it **before `runApp`**, so the first read of the
provider already reports the hold and no provider state is written during
mount. And never introduce a delay that is not covered by real work: if boot
finishes first the sequence simply ends, and if boot is still going the screen
says so in words after a delay a quick launch never reaches.
