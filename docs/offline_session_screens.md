# Offline session — screen briefs

Design briefs for the states of the offline-session workflow (the seven-day
offline copy of a signed-in account). Ready to hand to Stitch or Codex.
Briefs only: implementation follows the project rules in `CLAUDE.md` and
`docs/FRONTEND-DESIGN-STEPS.md`.

## Shared rules (every brief)

- Colour only from `context.c` tokens. All six palettes, Light and Dark, and
  Eye Protection must work; no hard-coded colour, radius or spacing.
- Arabic first: `Directionality`, `AlignmentDirectional`,
  `EdgeInsetsDirectional`. Check every row in RTL.
- Status states build on `StatusScreen` (`core/widgets/status_screen.dart`)
  and its `StatusTone`.
- Motion uses `MotionTokens` through `effectiveDuration`, so
  `MediaQuery.disableAnimations` is honoured. Animation stays inside the one
  screen; nothing global changes.
- Copy strings live in `lib/l10n/strings.dart`, in logical order.

## State table

| # | State | Status after D2 | Where |
|---|---|---|---|
| 1 | Restoring at launch | partial — no slow-network line | `/startup` (`StartupPage`) |
| 2 | Offline indicator | missing — `OfflineBanner` unused | tenant + platform shells |
| 3 | Offline sign-in expired | **built in D2** | `/offline-session-expired` (`OfflineSessionExpiredPage`) |
| 4 | Launch error, no copy (network vs 5xx) | missing — lands on an empty `/home` | new status destination |
| 5 | Action blocked offline | partial — per-screen snackbars | shared helper + call sites |
| 6 | Fingerprint lock offline | done — the expired state disarms it (D2) | `AppLockGate` |
| 7 | Back online | missing — needs a behaviour change | out of scope (separate approval) |
| 8 | Sign-out confirmation | partial — never mentions the offline copy | `confirmAndSignOut` dialog |
| 9 | Settings: offline days left | missing | `/more/security` |

## 1. Restoring at launch

- **Purpose:** the cold launch waits for `GET /auth/me`; on a slow network
  the worst case is about 40 s (two 20 s requests). Say why it is waiting.
- **Copy:** after 3 s a line fades in under the mark:
  «الاتصال بطيء… سنفتح آخر نسخة محفوظة إن لم يصل الخادم».
- **States:** spinner only (0–3 s) → spinner + line.
- **RTL:** the line is start-aligned under the mark, max two lines.
- **Motion:** the line fades and rises 4 dp over `MotionTokens` short; with
  animations disabled it simply appears.

## 2. Offline indicator

- **Purpose:** the app is running on the stored copy; make that visible.
- **Copy:** the existing `OfflineBanner` under the app bar:
  «بدون اتصال — تعمل على آخر نسخة محفوظة». In the last 48 hours add
  «ينتهي الدخول دون اتصال خلال {n} ساعة».
- **States:** hidden (online) / shown / shown with countdown.
- **RTL:** icon at the start, text after it.
- **Motion:** `AnimatedSize` open/close only; no slide across the screen.

## 3. Offline sign-in expired — BUILT (D2)

- **Purpose:** offline, and the copy is past seven days. The session may
  still be valid, so ask for a connection, not a new sign-in. Tokens are kept.
- **Copy:** title «انتهت صلاحية الدخول دون اتصال»; body
  «مرّت ٧ أيام على تسجيل دخولك. اتصل بالإنترنت ثم أعد المحاولة.»
- **Actions:** «إعادة المحاولة» (primary, filled) and «تسجيل الخروج» (the
  ordinary sign-out with its confirmation).
- **States:** idle; retrying (spinner inside the button); still offline (an
  inline line «ما زلت دون اتصال. تحقّق من الشبكة ثم أعد المحاولة.»); back
  online (the router leaves on its own — into the app, or to
  `/session-expired` if the server ended the session).
- **Also mid-session:** the session re-reads itself when the seven days end.

## 4. Launch error, no copy

- **Purpose:** at launch there is no usable copy and the read failed. Tell a
  network problem from a server problem instead of an empty home.
- **Copy:**
  - Network: «لا يوجد اتصال بالإنترنت» / «تحقّق من الشبكة ثم أعد المحاولة».
  - 5xx: «الخادم لا يستجيب الآن» / «المشكلة ليست في هاتفك. أعد المحاولة بعد قليل».
- **Actions:** one «إعادة المحاولة»; sign-out as the secondary action.
- **States:** network / server / retrying. The icon differs per case
  (`wifi_off` vs `cloud_off`).
- **Lock:** the screen disarms the app lock (no session to protect yet).

## 5. Action blocked offline

- **Purpose:** one sentence for every action that needs the server.
- **Copy:** one shared snackbar: «يحتاج هذا الإجراء إلى اتصال بالإنترنت».
  It replaces the bare «بدون اتصال» at each call site.
- **Rule:** no retry queue for security actions (password, MFA, sessions).

## 6. Fingerprint lock offline

- Behaviour unchanged: cold launch locks, ≥5 minutes in the background
  relocks. The expired state and the launch-error screen disarm it.
- Lockout copy unchanged.

## 7. Back online (out of scope here)

- Silent re-check on resume and every 60 s while offline; same account =
  only the banner collapses; revoked = `/session-expired`.
- Needs a behaviour change (and possibly a connectivity plugin): separate
  approval.

## 8. Sign-out confirmation

- **Copy (added to the existing dialog):**
  «سيُحذف حسابك المحفوظ من هذا الهاتف، ولن يفتح التطبيق دون اتصال حتى تسجّل الدخول من جديد.»
- **Offline variant:** «…وتبقى جلستك على الخادم حتى تنتهي خلال ٧ أيام.»
- **States:** online / offline wording; buttons unchanged.

## 9. Settings: offline days left

- **Where:** a row on `/more/security`.
- **Copy:** «الدخول دون اتصال متاح حتى {التاريخ} (بقي {n} أيام)»; once
  expired: «غير متاح — اتصل لتجديده».
- **Format:** Arabic date format; the row reads right to left.
