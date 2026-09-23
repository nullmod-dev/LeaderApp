# MTM — Final Fixes Prompt

> Apply these three changes to the existing project. Do **not** build any of the remaining screens. Do not create stub files. Leave the missing files missing.

---

## 1. Typography — replace the current font setup

**Primary typeface: IBM Plex Sans Arabic.** Use it for the entire UI — Arabic and Latin both. It is a UI-first family, stays legible at 11–13px, and has no decorative or calligraphic character. Do not use Cairo, Amiri, Lateef, Aref Ruqaa, or any display/Kufi/Naskh calligraphic face.

**Remove JetBrains Mono entirely.** It contains no Arabic-Indic numeral glyphs (٠١٢٣٤٥٦٧٨٩). Any numeral rendered with it silently falls back to a different font, which breaks both the alignment and the visual consistency of every counter and statistic in the app.

For numerals, use IBM Plex Sans Arabic with tabular figures enabled so digits stay aligned in animated counters and lists:

```dart
const TextStyle(
  fontFamily: 'IBMPlexSansArabic',
  fontFeatures: [FontFeature.tabularFigures()],
)
```

**Bundle the font files as assets. Do not use the `google_fonts` package.** This app is offline-first: `google_fonts` fetches at runtime, so the first launch without a connection renders in the system fallback font and the entire design shifts. Download the static `.ttf` files, place them under `assets/fonts/`, and declare them in `pubspec.yaml`.

Ship these weights only: Regular (400), Medium (500), SemiBold (600). Do not ship Light, Thin, or Bold — the design uses 400 and 500 almost exclusively, and unused weights only inflate the bundle.

Define the type scale once in `app_typography.dart` and confirm no widget sets `fontFamily` inline.

**Verify:** every screen with numbers (attendance counters, statistics, OTP boxes, quantity fields) renders Arabic-Indic digits in the correct font with no fallback and no shifting during counter animation.

---

## 2. Motion level — make it a user setting

The current animation set stays as the full experience, but it must be switchable.

Add a setting under المزيد with two options:

- **حركة كاملة** — everything as currently built: shared-axis transitions, stagger, hero, animated counters, glass blur on the bottom navigation
- **حركة مخففة** — transitions become instant or a simple fade, stagger disabled, counters set their value directly, hero replaced by a plain push, and the glass bottom navigation renders as a solid semi-transparent surface with **no `BackdropFilter`**

Implementation requirements:

- One Riverpod provider, `motionLevelProvider`, persisted through `SettingsRepository`
- Every animation reads its duration from `motion_tokens.dart`, and those tokens return zero or reduced values when the level is مخففة — do not scatter `if` checks through widgets
- If the operating system reports reduced-motion (`MediaQuery.disableAnimations`), default to مخففة on first launch, but still let the user override it
- Wrap the bottom navigation in a `RepaintBoundary` in both modes
- The setting takes effect immediately, with no restart

The blur on the bottom navigation is the single heaviest effect in the app on low-end Android. This setting exists mainly so that it can be turned off.

---

## 3. MFA QR — mark the secret as server-owned

The TOTP secret must never be generated on the device. In the real system it is created by the server and delivered as an `otpauth://` URI.

In `mfa_setup_page.dart` and the auth repository:

- Move the secret and the full `otpauth://` URI into `AuthRepository` as returned data, not something the widget computes
- The mock implementation may return a fixed sample URI
- Mark the mock generation clearly:

```dart
// TODO(backend): secret and otpauth URI must come from the server.
// Never generate a TOTP secret on the client.
```

- Backup codes follow the same rule: returned by the repository, never generated on the device

---

## Scope

These three changes only. No new screens, no stubs, no refactors beyond what is described above. Report which files you touched.
