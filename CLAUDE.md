# Leader Front-Back — Claude working guide

This repository contains the Flutter frontend for Leader / ليدر. Work within the existing application; do not replace it with a web, React, React Native, Swift, or new-package implementation.

## First reads for frontend and visual work

1. Read [frontend design steps](docs/FRONTEND-DESIGN-STEPS.md).
2. Read [frontend design notes](docs/FRONTEND-DESIGN-NOTES.md).
3. Inspect the affected feature, `flutter_app/lib/core/theme/`, `flutter_app/lib/core/motion/`, and `design_references/` before editing.
4. Use the appropriate skill in `.claude/skills/` before changing a screen, interaction, or animation.

## Project rules

- Preserve the current architecture, dependencies, files, and user changes unless the request explicitly asks to change them.
- Do not fix, suppress, reformat around, or remove existing errors merely because they are present. Address errors only when the user requests that work.
- Build UI with the existing Flutter theme, palette, typography, widgets, and motion primitives. Do not introduce a package for a visual or motion effect without explicit approval.
- The app is Arabic-first. Use `Directionality`, `AlignmentDirectional`, and `EdgeInsetsDirectional`; test every horizontal layout and transition in RTL.
- Treat loading, empty, offline, failure, conflict, authentication, and permission states as designed screens—not afterthoughts.
- Respect `MediaQuery.disableAnimations` and accessible navigation. Motion must clarify an interaction, never delay it.
- Keep changes small, focused, and consistent with the existing design language. Verify with the relevant Flutter checks when the requested work includes code changes.

## Brand

- The product is **Leader / ليدر** (formerly MTM). Read the name from `S.productNameAr` / `S.productNameEn` in `lib/l10n/strings.dart`; never add a brand literal. Android id is `com.leader.teams`.
- `MTM` stays only in protocol/compatibility identifiers — Dart package `mtm`, persisted `mtm.*` keys, `MTM_*` env keys, Team Code prefix, plan ids, the `mtm/display` channel. Do not rename those for branding. See HANDOFF.md "LEADER REBRAND — PHASE 1".

## Theme system

- All colour lives in `flutter_app/lib/core/theme/app_palette.dart` as `AppColors` token sets. Read tokens via `context.c` (e.g. `context.c.surface`); never hard-code a colour, radius, or spacing value.
- Six palettes: `PaletteId { medical, slate, copper, clay, indigo, teal }`. Each has a full light + dark `AppColors` const; `AppColors.resolve(id, brightness)` picks one.
- **The product offers all six palettes.** `core/theme/theme_choice.dart` maps `AppThemeChoice { medical, slate, copper, clay, indigo, teal }` one-to-one onto the palette engine. Appearance is a separate axis: every palette supports Light, Dark and System. The historical default is Medical + Light. The temporary `darkCyber` / `purpleArena` / `light` names remain source-compatibility aliases only.
- **Eye-protect mode** is orthogonal to the palette and to light/dark: `ThemeState.eyeProtect` (bool) makes `AppTheme.light/dark` run the resolved palette through `AppColors.warmed()`. That wash moves the **ground only** — bg, surfaces, hairlines, status tints — and never the ink, the primary or a semantic colour, because warming a foreground is what costs contrast where text is read. Do not model it as a palette.
- `ThemeState` lives in `core/theme/theme_state.dart` (its own file because `SettingsRepository` persists that shape). `ThemeController` is an `AsyncNotifier` that hydrates from `SettingsRepository.themePrefs()` and writes back on every change. **Read the theme with `themeStateProvider`**, which serves `ThemeState.initial()` until the stored value lands; only call `.notifier` to change it.
- The shipped `MockSettingsRepository` durably stores `ThemeState.toJson()` under `mtm.settings.theme` through the existing `LocalStore`. Unknown/corrupt values fall back safely without clearing unrelated preferences; names, never enum indices, are persisted.
- Settings has one canonical appearance screen, `/more/themes` (`ThemesAndPerformancePage`): six palette cards, the only user-facing Eye Protection control, Appearance (Light/Dark/System), performance quality, then frame rate. `/more/performance` and the legacy `/more/eye-protect` path redirect to it; the platform legacy path does the same. Eye Protection remains independent persisted state. `ThemeChoiceCard` previews the current appearance from resolved tokens, and `ChoicePill` owns its selected/button/tap semantics.
- **Contrast is enforced by test**, not by eye: `test/core/theme/palette_contrast_test.dart` holds every palette to floors derived from the original `slate`/`copper`/`clay` tokens, requires the later palettes (`medical`/`indigo`/`teal`) to clear WCAG AA on the filled-button label, and bounds what eye-protect may cost. Run it after touching any hex value.
- Adding a palette: add the enum value, a light + dark `AppColors` const, a `resolve` switch arm, and an `AppThemeChoice.ofPalette` arm. It only reaches users if a theme in `themeChoices` maps to it. `detachment_group_flow_smoke_test.dart` covers "every palette builds"; the contrast test covers "every palette is legible" — expect it to fail first and tune the hex until it passes.

## Available frontend/design skills

- `frontend-design` — intentional visual direction and design planning.
- `impeccable` — static UI craft and design-system quality.
- `emil-design-eng` — interaction and design-engineering principles.
- `animate`, `apple-design`, `animation-vocabulary`, `find-animation-opportunities`, `improve-animations`, `review-animations` — motion design, terminology, planning, and review.

The copied skills are guidance. Translate web-oriented examples into Flutter using the project’s current primitives; do not paste CSS, JSX, Framer Motion, or web-only code into this app.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
