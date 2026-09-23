# Leader — Pricing, Global Offers & Coupons (Point 19 — ARCHITECTURE)

Architecture and implementation handoff for the commercial surface: one
full-access Leader plan at four billing durations, Super-Admin-controlled global
offers, individual coupons, a contact-based subscription CTA, and a Demo
conversion entry.

**Status: implemented for the approved Flutter UI + local DEV/TEST scope on
2026-09-16.** Section 20 remains the implementation checklist; sections 1–19
record the reasoning and constraints. The backend/payment/redemption work in
§17 remains intentionally future scope.

**Read first:** `CLAUDE.md`, `BACKEND-HANDOFF.md` §0–§4, `CAPABILITIES.md` §1–§2,
`SCREEN-ROUTE-MATRIX.md`.

---

## 0. What this is not

There is no payment gateway, no subscription activation, no redemption
accounting, and no backend. Nothing in this design charges anybody or records
that anybody paid.

Explicitly out of scope, and deliberately not modelled: payment providers,
Stripe / Google Play Billing / Apple IAP, invoices, tax, VAT, refunds,
chargebacks, card tokens, recurring billing, proration, revenue analytics,
referral or affiliate programmes, multiple product tiers, AI features, and
coupon usage counters.

**The Flutter client is never financial authority.** Every price, discount and
validity verdict computed here is a *display* of a rule the backend will later
own and re-decide. §17 states that contract.

---

## 1. Canonical product rules

One Leader product. One full-access plan. Four billing durations.

| Duration | Wire id | Months | Base price | Cents | Effective monthly |
| --- | --- | --- | --- | --- | --- |
| شهر واحد | `monthly` | 1 | $6 | `600` | $6.00 |
| ٣ أشهر | `three_months` | 3 | $14 | `1400` | $4.67 |
| ٦ أشهر | `six_months` | 6 | $24 | `2400` | $4.00 |
| ١٢ شهراً | `twelve_months` | 12 | $40 | `4000` | $3.33 |

- **All four durations grant identical Leader capabilities.** There is no
  Basic / Pro / Premium split and no duration-gated feature. A duration buys
  time, never function. This is an invariant with a test (§19, `full-access`).
- The 12-month option carries the label «أفضل قيمة». It is a *value* claim
  derived from the effective monthly price, not a scarcity claim.
- Currency is USD, and the only currency. No conversion, no locale currency.

### 1.1 Promotion eligibility — current phase

Promotions may target **`monthly` and `three_months` only**. `six_months` and
`twelve_months` take no discount in this phase.

This is expressed as a catalog policy constant, not as an `if` in the pricing
page and not as a hard-coded pair in the validator:

```dart
const Set<BillingOptionId> kPromotionEligibleOptions = {
  BillingOptionId.monthly,
  BillingOptionId.threeMonths,
};
```

Every reader — the Super Admin creation form's target picker, the coupon
validator, the offer validator, the pricing page — reads that one set. Adding
`six_months` later is one line plus whatever tests pin the current policy, which
is the "not a migration nightmare" the brief asks for without building a rules
engine nobody needs yet.

---

## 2. Repository audit — what already exists

The audit found more reusable structure than expected. Almost nothing here is
new machinery; it is a new feature assembled from established seams.

### 2.1 There is no pricing surface today, and `/more/plan` is not one

`lib/features/organization/presentation/plan_page.dart` opens with an explicit
header comment: *"**Not a billing screen.** No price, currency, invoice, payment
method, upgrade, downgrade, cancel or renewal charge exists, and nothing here
suggests one."*

That page answers **"what am I on"**. The new page answers **"what can I buy"**.
They are different questions and stay two screens (§6.4). No pricing surface is
duplicated, because none exists yet.

### 2.2 Platform navigation is a closed four-area model

`lib/features/platform/domain/platform_area.dart`:

> *"Four, deliberately, and they are *areas* rather than actions… Points 5–13
> add pages *inside* these four; none of them adds a fifth."*

So the Super Admin commercial surface is **a page inside `operations`**, exactly
as Customer Demo management is (`/platform/operations/demo`). It adds no
`siblingSegment`, no `PlatformArea` value, and no bottom-bar destination.

### 2.3 `DemoControlPlane` is the template for the commerce control plane

`lib/features/demo/data/demo_control_plane.dart` +
`lib/features/platform/data/platform_demo_providers.dart` are an exact
precedent for what §9 needs, and the new code should read as a sibling of them:

- an in-memory `Notifier<State>`, documented as development-only, never
  persisted to `LocalStore`, replaced wholesale by a backend adapter;
- every mutation takes a nullable **actor** and returns
  `Failure(code: 'not_authorized')` when it is null;
- the actor is built in a `features/platform/data/…_providers.dart` file from
  the signed-in `super_admin` session and nowhere else — which is what keeps
  the control plane free of an `features/auth` import cycle;
- **the page never asks "am I a Super Admin" to decide what to draw.** It asks
  the control plane to act and handles the refusal, which is the same shape a
  backend will answer with.

Copy that structure. Do not invent a second authorization style.

### 2.4 Contacts already have one source of truth — and it already holds `@jjkkkj`

`lib/features/about/domain/support_contacts.dart` is pure Dart, holds
`supportEmail` and `supportTelegram = '@jjkkkj'`, builds `mailto:` / `tg:` /
`https://t.me/…` URIs, and is pinned by
`test/features/about/support_contacts_test.dart`.

`lib/core/platform/external_links.dart` is *"the app's **only** door out to
another application"* — a testable `ExternalLinkLauncher` returning
`ExternalLinkOutcome { opened, unsupported, failed }`, with the deliberate split
that URI *construction* is domain work living beside the contacts.

So: extend that file, add WhatsApp beside Telegram, and reuse the launcher. Do
not put a phone number in a widget. §8 specifies it.

### 2.5 The Super Admin dev credential seam already exists

`lib/features/auth/data/dev_test_credentials.dart` holds three
`DevTestCredential`s keyed to `DemoPersona`, guarded by `demoAccountsAllowed`
(`const false` outside debug, so the table tree-shakes out of a release
artefact). The Login screen ships **no** persona picker in any build —
`SCREEN-ROUTE-MATRIX.md` pins that: *"dev identities are typed through the
normal fields; no picker"*.

`DevTestCredentials.superAdmin` already exists. §16 **updates its two values**
and adds no new mechanism.

### 2.6 Reusable presentation primitives

| Need | Use | From |
| --- | --- | --- |
| Section heading | `SectionLabel` | `features/settings/presentation/widgets/settings_widgets.dart` |
| Grouped card | `SettingsSection` | ″ |
| Tappable row | `NavigationRow` | ″ |
| Selectable pill | `ChoicePill` | ″ (owns its selected/button/tap semantics) |
| State chip | `StatusChip` (`ok/warn/crit/info/muted`) | `core/widgets/status_chip.dart` |
| Explanatory note | pattern of `OrganizationNote` | `features/organization/presentation/organization_widgets.dart` |
| Wide-screen two-column | pattern of `OrganizationColumns` | ″ |
| Tabular figures | `AppTypography.digits` | `core/theme/app_typography.dart` |
| Colour / spacing / radii | `context.c`, `AppSpacing`, `AppRadii` | `core/theme/app_palette.dart` |

`OrganizationNote` and `OrganizationColumns` live in the organization feature
and read nothing from it. Codex should **not** import them across features and
should **not** move them; re-implement the two small equivalents locally in
`pricing_widgets.dart` (`PricingNote`, `PricingColumns`). This is the cheaper of
the two wrong answers: a shared-widget refactor touches Point 15 screens that
are complete and tested, and this brief says preserve existing files.

---

## 3. Money

**Integer minor units everywhere. Floating-point money never exists**, not even
transiently.

New value type, `lib/features/pricing/domain/money.dart`:

```dart
@immutable
final class Money {
  const Money.cents(this.cents) : assert(cents >= 0);
  final int cents;

  static const zero = Money.cents(0);

  Money operator -(Money other) => Money.cents(cents - other.cents);
  bool operator <(Money other) => cents < other.cents;
  // == / hashCode / compareTo
}
```

A type rather than a bare `int` because the failure this prevents is real:
`int` lets `600` (cents) and `6` (dollars) be added, and the compiler cannot
see it. Every price, discount, final price and saving in the app is a `Money`.

### 3.1 Percentage rounding — exact and deterministic

```dart
// Half-up on the DISCOUNT, then subtract.
int discountCents = ((baseCents * percent) + 50) ~/ 100;
int finalCents    = baseCents - discountCents;
```

Rounding the **discount** half-up (rather than the final price) resolves every
half-cent in the customer's favour, which is the convention and is the one
choice that can never be read as shaving a cent off a displayed offer.

Pinned cases (§19):

| Base | % | Discount | Final |
| --- | --- | --- | --- |
| `1400` | 10 | `140` | `1260` |
| `600` | 20 | `120` | `480` |
| `600` | 5 | `30` | `570` |
| `1400` | 33 | `462` | `938` |
| `600` | 1 | `6` | `594` |

All integer arithmetic. `baseCents * percent` for the values in this catalog is
far inside the 64-bit range; no overflow guard is warranted or wanted.

### 3.2 Effective monthly price — display only

```dart
int monthlyCents = (totalCents + (months ~/ 2)) ~/ months; // half-up
```

`1400/3 → 467` ($4.67) · `2400/6 → 400` ($4.00) · `4000/12 → 333` ($3.33) ·
`600/1 → 600` ($6.00).

**This is a derived display figure and is never a charge.** It is never sent
anywhere, never persisted, and never used as an input to another calculation.
It is computed from the *effective* price, so a promoted month shows the
promoted effective monthly rate.

### 3.3 Savings

Savings on a multi-month option compare it to paying monthly for the same span:

```dart
Money savings = Money.cents(monthlyBaseCents * months - effectiveCents);
```

`three_months`: `1800 - 1400 = 400` → «وفّر $4». Shown only when positive. The
`monthly` option therefore shows no duration saving — correct, it is the
baseline — though it still shows a promotional saving when one applies.

### 3.4 Formatting — and the digit ruling

`$6` when cents are zero, `$4.67` otherwise. Always `$` before the number.

**Ruling: Western digits for money, not Arabic-Indic**, and the price is wrapped
in an LTR isolate so it renders correctly inside an Arabic RTL paragraph.

The app otherwise uses Arabic-Indic figures via `toArabicIndic` (`٢٣ / ٤٠` on
Home and Plan). Money departs from that because `$` is a Latin currency mark and
`$٦.٦٧` mixes two numbering systems in one token; the About screen already
establishes the precedent that a Latin identifier is rendered LTR inside the
Arabic page. Use the Unicode isolate characters (`⁦` … `⁩`) or a
`Directionality(textDirection: TextDirection.ltr)` wrapper — `Text` alone will
reorder `$6.00` at the start of an RTL line.

> **Claude-provisional (P1).** Reversible in one formatter if Ahmed prefers
> Arabic-Indic prices. Nothing else depends on it.

Durations, counts and dates keep Arabic-Indic exactly as they are today.

---

## 4. Domain model

New directory `lib/features/pricing/domain/`.

### 4.1 Billing option — identity separate from price

```dart
enum BillingOptionId {
  monthly('monthly', 1),
  threeMonths('three_months', 3),
  sixMonths('six_months', 6),
  twelveMonths('twelve_months', 12);

  const BillingOptionId(this.wire, this.months);
  final String wire;
  final int months;

  static BillingOptionId? tryParse(String wire) { /* fail-closed, returns null */ }
  bool get promotionEligible => kPromotionEligibleOptions.contains(this);
}

@immutable
final class BillingOption {
  const BillingOption({required this.id, required this.basePrice});
  final BillingOptionId id;
  final Money basePrice;
  int get months => id.months;
}
```

**The price is not on the enum.** The enum is durable identity that a coupon, an
offer and a future wire payload all reference; the price is catalog data the
backend will own and change without any enum moving. Baking `600` into the enum
would make a price change an enum change.

`tryParse` returning `null` for an unknown wire matches `DemoSessionStatus` and
`TenantFeatureKey`: **callers fail closed** — an uninterpretable billing option
is not eligible for anything and is not rendered.

### 4.2 Discount — a sealed type, not a type-tag plus two nullables

The brief proposed `discountType` + `percentage?` + `finalPriceCents?`. Use a
sealed class instead:

```dart
sealed class Discount {
  const Discount();
}

final class PercentageDiscount extends Discount {
  const PercentageDiscount(this.percent);
  final int percent; // 1..90 inclusive; see §4.6
}

final class FixedFinalPriceDiscount extends Discount {
  const FixedFinalPriceDiscount(this.finalPrice);
  final Money finalPrice; // "first month for $2" == Money.cents(200)
}
```

Why the departure: the three-field shape has four representable states, two of
which are nonsense (`percentage` type with a null percentage; both values set).
A sealed hierarchy has exactly two, `switch` is exhaustive, and the compiler
rejects the third case at the point a future discount type is added. The repo
already models this way — `Result`, `OrganizationPlanNone/Known/Unsupported`.

`$2 first month` is `FixedFinalPriceDiscount(Money.cents(200))` — a *final
price*, never `base - 400`. That is the brief's money-safety requirement made
structural: there is no subtraction to get wrong.

### 4.3 Applying a discount

Pure function, no clock, no I/O:

```dart
Money applyDiscount(Discount discount, Money base) => switch (discount) {
  PercentageDiscount(:final percent) =>
      Money.cents(base.cents - (((base.cents * percent) + 50) ~/ 100)),
  FixedFinalPriceDiscount(:final finalPrice) => finalPrice,
};
```

### 4.4 Global offer

```dart
@immutable
final class GlobalOffer {
  const GlobalOffer({
    required this.id,
    required this.enabled,
    required this.target,
    required this.discount,
    required this.createdAt,
    this.title,
    this.endsAt,
  });

  final String id;
  final bool enabled;
  final BillingOptionId target;
  final Discount discount;
  final DateTime createdAt;
  final String? title;    // e.g. «جرّب أول شهر بـ $2»; falls back to a derived label
  final DateTime? endsAt; // optional, and only ever real — see §4.7

  bool isLiveAt(DateTime now) =>
      enabled && (endsAt == null || now.toUtc().isBefore(endsAt!.toUtc()));

  // toJson / fromJson in the shape of DemoPolicy: field-by-field fallback,
  // names never enum indices, unknown values fail closed.
}
```

### 4.5 Coupon and assignment

```dart
sealed class CouponAssignment {
  const CouponAssignment();
}

/// Anyone who knows the code.
final class CouponAssignmentPublic extends CouponAssignment {
  const CouponAssignmentPublic();
}

/// One named account. The durable key is the account id, never a display name
/// and never an email — see §4.8.
final class CouponAssignmentAccount extends CouponAssignment {
  const CouponAssignmentAccount(this.accountId);
  final String accountId;
}

@immutable
final class Coupon {
  const Coupon({
    required this.id,
    required this.code,        // ALWAYS the normalized form (§5)
    required this.enabled,
    required this.target,
    required this.discount,
    required this.assignment,
    required this.createdAt,
    this.note,                 // internal only; never rendered to a user
    this.expiresAt,
  });
  // …
  bool isLiveAt(DateTime now) =>
      enabled && (expiresAt == null || now.toUtc().isBefore(expiresAt!.toUtc()));
}
```

**Two aggregates, not one with a `scope` enum.** The brief suggested a
`PromotionScope`. A single class carrying `code` and `assignment` would make
both nullable and force every global-offer reader to null-check fields that can
never be set for it. What they genuinely share — `target` and `discount` — is
shared as those two types. The distinction the brief actually asks for ("do not
mix them into one ambiguous boolean") is preserved more strongly this way, not
less.

### 4.6 Promotion validity — the rule a discount must satisfy

A discount is valid against a base price when the final price is **strictly
above zero and strictly below the base**:

```dart
bool isSaneFor(Discount discount, Money base) {
  final result = applyDiscount(discount, base);
  return result.cents > 0 && result.cents < base.cents;
}
```

Consequences, and they are intentional:

- a free month (`$0`) is refused — this product has no free tier, and a $0
  "purchase" with no payment gateway is a state nothing can complete;
- a discount of 0% or a "discount" that raises the price is refused;
- percentage is additionally bounded `1..90` at creation, so the Super Admin
  form rejects `0`, `100` and `150` before the sanity check has to.

Enforced in **two places, deliberately**: at creation (`promotion_invalid`, so
bad data never enters the control plane) and at resolution (so a catalog price
change that retroactively breaks an offer makes the offer silently inert rather
than rendering `$0`). Belt and braces is correct here because the second case
cannot be prevented by the first.

### 4.7 Dates that exist only when they are real

`endsAt` / `expiresAt` are nullable and **absent by default**. When absent the
UI says nothing about time. There are no countdown timers, no "today only", no
fabricated urgency, no stock counters. If a date is present it is shown plainly
as a date. §13 restates this as a copy rule.

### 4.8 Targeted coupons key on `accountId`

`CouponAssignmentAccount` holds an **account id**, matched against
`AuthUser.id`. Never an email, never a display name — an email is a mutable
attribute and a display name is not unique, and the brief is explicit that the
durable key must not be either.

Under the mock, the Super Admin form takes an account id as free text (with the
three dev persona ids offered as quick-fills in debug builds only). A real
backend resolves an operator-typed email to an account id **server-side** and
stores the id; the client never performs that lookup. §17 records the contract.

---

## 5. Coupon code normalization

One function, `lib/features/pricing/domain/coupon_code.dart`:

```dart
final _pattern = RegExp(r'^[A-Z0-9-]{3,24}$');

/// The canonical form of a typed code, or null when it cannot be one.
String? normalizeCouponCode(String raw) {
  final collapsed = raw.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
  return _pattern.hasMatch(collapsed) ? collapsed : null;
}
```

- trim, remove **all** internal whitespace, uppercase;
- allowed alphabet `A–Z 0–9 -` only, length 3–24;
- ASCII-only is the point: a coupon has to survive being written on paper, read
  aloud on the phone, and typed on an Arabic keyboard. Arabic-Indic digits,
  Cyrillic `А`, and a Unicode hyphen that looks identical to `-` are exactly the
  characters that make a support call, so they are not codes;
- `toUpperCase()` is safe here because the pattern check runs *after* it and
  admits only ASCII — no Turkish-dotless-ı class of bug can reach storage.

`TRY2`, `LEADER10`, `TEAM-20` are valid. `try2` normalizes to `TRY2`.

**Applied at both ends:** the Super Admin form stores only normalized codes
(and refuses a malformed one with `coupon_code_invalid`); the user field
normalizes before lookup. Storage therefore contains exactly one spelling of
each code, and lookup is a plain equality match rather than a case-insensitive
scan.

A code that fails normalization is **not** a special error state to the user —
it is simply not a code we hold, and returns the ordinary invalid message (§6).

---

## 6. Validation and price resolution

### 6.1 Coupon validation rules, in order

`validateCoupon` is pure: `(state, rawCode, accountId, selectedOption, now)`.
It returns `Result<CouponResolution>` — the repo's own type — so refusals carry
a code and screens branch on the code, never on a message (`Problem` §code).

| # | Check | Failure code |
| --- | --- | --- |
| 1 | normalizes to a code shape | `coupon_not_found` |
| 2 | a coupon with that code exists | `coupon_not_found` |
| 3 | `enabled` | `coupon_disabled` |
| 4 | not past `expiresAt` (uses `clockProvider`) | `coupon_expired` |
| 5 | assignment allows this `accountId` | `coupon_not_assigned` |
| 6 | `target` is in `kPromotionEligibleOptions` | `coupon_not_eligible` |
| 7 | `isSaneFor(discount, targetBasePrice)` | `coupon_invalid_price` |

Order matters and is pinned by test: identity before state before eligibility.

**Codes 1, 2 and 5 share one user-facing message.** Internally they are three
codes (tests and a future audit trail need the distinction); on screen all three
say «الكوبون غير صالح أو غير متاح.» Telling someone "this code exists but is not
yours" turns the field into an oracle that confirms which codes are real, for no
user benefit — the action is identical in all three cases.

Code 6 gets its **own** message, because the user can act on it: the coupon is
real and theirs, it just belongs to a different duration. That is the brief's
STATE G, and the message names the duration it is for.

`coupon_disabled`, `coupon_expired` and `coupon_invalid_price` also collapse to
the shared invalid message on screen. Distinct codes, three messages total.

### 6.2 What "valid" produces

```dart
@immutable
final class CouponResolution {
  final Coupon coupon;
  final BillingOptionId target;
  final Money basePrice;
  final Money finalPrice;
  Money get savings => basePrice - finalPrice;
}
```

**Validation is not redemption.** It reads; it writes nothing; it decrements
nothing; it creates no subscription, no payment record and no state of any kind.
There is no usage counter in this model *at all* (§4, §17) precisely so that
nothing can be consumed by accident. §14 restates this.

### 6.3 Precedence — no stacking, best price wins, and the screen says which

**Ruling: at most one promotion applies to any option. Discounts never
compose.** The applied one is the one producing the lower final price;
on an exact tie the **global offer** wins (it needs no user action, so a coupon
that merely equals it changes nothing).

```
Global: 10% off $6   → $5.40
Coupon: TRY2         → $2.00
Applied: TRY2 → $2.00        (never 10% then TRY2)
```

The card always names the promotion in force — «عرض خاص», «خصم ٢٠٪», or the
offer's own `title` — so the user can see *why* the price is what it is.

**The coupon-is-worse case gets its own state** rather than a silent loss. When
a valid coupon loses to the active global offer, the screen keeps the better
price and says so: the coupon is confirmed valid, and the user is told the
current offer already beats it. Silently discarding a code somebody just typed
looks like the field is broken.

Resolution is a pure function over
`(catalog, liveGlobalOffers, couponResolution?)` returning one `PriceQuote` per
billing option:

```dart
@immutable
final class PriceQuote {
  final BillingOption option;
  final Money basePrice;
  final Money finalPrice;
  final AppliedPromotion? promotion;   // null ⇒ base price, no promo UI
  final Money durationSavings;         // §3.3, vs paying monthly
  Money get promotionSavings => basePrice - finalPrice;
  Money get effectiveMonthly => /* §3.2 over finalPrice */;
}

@immutable
final class AppliedPromotion {
  final PromotionSource source;  // enum { globalOffer, coupon }
  final String displayLabel;
  final String? code;            // present only for a coupon
}
```

A `PriceQuote` with `promotion == null` renders as a plain price — no struck-out
original, no badge. Only a real promotion draws promotional UI.

---

## 7. User-facing pricing page

**Route `/more/pricing` · title «الاشتراك والأسعار» · one canonical surface.**

Both a normal tenant session and a Customer Demo session open the *same* route
and the *same* page. There is no demo pricing page.

### 7.1 Entry points — exactly two

1. **More → «الاشتراك والأسعار»** — a `NavigationRow` in `SettingsPage`.
2. **The Demo trial bar** — «شاهد الخطط» (§12).

That is the whole list. The CTA does not appear on Home, on Detachments, on
Shifts, or as an interstitial.

#### Placement in `SettingsPage`, and why it is not in the org section

`SettingsPage` wraps its organisation rows (Organization, Plan, Simple Admins)
in `if (!demo)`. Pricing must be visible to a demo, so it cannot go in there —
and duplicating the row into a demo branch would be two call sites for one row.

Add a **new section of its own**, rendered unconditionally, immediately above
the organisation section:

```dart
const SectionLabel(S.sectionSubscription),   // «الاشتراك»
SettingsSection(children: [
  NavigationRow(
    key: const Key('settings-pricing-row'),
    icon: Icons.sell_outlined,
    label: S.pricingTitle,                   // «الاشتراك والأسعار»
    subtitle: S.pricingRowSub,               // «الخطط والأسعار وطرق الاشتراك»
    onTap: () => context.push(PricingPage.routePath),
  ),
]),
```

A demo sees this section and not the organisation one; a tenant admin sees both,
in the order buy-then-own, which reads correctly either way.

### 7.2 Page structure

```
Scaffold(appBar: «الاشتراك والأسعار»)
└── FloatingNavPadding                      ← required; the floating nav overlaps
    └── ListView(key: Key('pricing-page'))
        ├── _PricingIntro                   value proposition, one short paragraph
        ├── _ActiveOfferBanner?             only when a live global offer exists
        ├── _BillingOptions                 four _PlanCards, monthly → yearly
        │   └── _PlanCard ×4                selection is local page state
        ├── _CouponSection                  field + «تحقق من الكوبون» + result
        ├── _SubscriptionContact            «للاشتراك تواصل معنا» (§8)
        └── _FullAccessNote                 "every duration gives full Leader access"
```

Ordering rationale: the offer is announced before the prices it changes; the
coupon field sits *after* the cards because it modifies them and a user looks
for it having already seen a price; contact is last because it is the action.

Use the `OrganizationColumns` **pattern** (locally re-implemented as
`PricingColumns`) so that ≥900dp puts the cards and the coupon/contact column
side by side instead of stretching one column across a tablet.

### 7.3 `_PlanCard`

Shows: duration name · final price (large, tabular) · effective monthly ·
base price struck through **only when a promotion applies** · promotion label
chip · duration savings · «أفضل قيمة» ribbon on `twelve_months` · selected
state.

- Selection is **presentational only**. It changes which card is emphasised and
  which duration the contact block mentions. It creates nothing.
- The card is not a purchase button. Its semantics are a radio, not a
  submit — `ChoicePill` is the established primitive for "selected/button/tap
  semantics" and the card should follow it.
- The primary action on the page is **«للاشتراك تواصل معنا»**, never «ادفع
  الآن». No screen in this feature may use purchase verbs.

### 7.4 The nine states

| | State | Rendering |
| --- | --- | --- |
| A | Normal prices | four cards, base prices, no badges |
| B | Live global offer | banner + the targeted card shows original struck, new price, label |
| C | Coupon field empty | field + disabled «تحقق من الكوبون» button |
| D | Validating | button shows a spinner, field disabled; synchronous today, so this is a single frame — build it anyway, the backend makes it real |
| E | Coupon valid, better | success note naming the code + its duration; that card updates; any global offer on that option is replaced, not added |
| F | Coupon invalid | `StatusKind.warn` note, «الكوبون غير صالح أو غير متاح.», field keeps its text so it can be corrected, nothing else on the page changes |
| G | Valid, wrong duration | note naming the duration it *is* for; prices unchanged; not styled as an error |
| G′ | Valid but the offer is better | success note + "the current offer is already better"; the better price stands |
| H | Demo viewing | identical page; the trial bar is above it; no capability or role branch anywhere in the widget tree |
| I | Tenant viewing | identical page |

There is no loading state for the catalog (it is a const in this phase) and no
offline state (nothing is fetched). When the backend lands, both arrive at the
provider boundary and this page's `AsyncValue` handling is the only change.

**Failure states must be non-destructive.** An invalid coupon never clears the
field, never resets the selected duration, and never hides the contact block.

---

## 8. Subscription contact

**One source of truth. Extend `features/about/domain/support_contacts.dart`.**

Add beside the existing constants:

```dart
/// The subscription/sales mailbox. Distinct from [supportEmail] — see below.
const String subscriptionEmail = 'nullmod.dev@gmail.com';

/// As people write it locally. Displayed verbatim; [whatsAppUri] converts it.
const String subscriptionWhatsApp = '07701322947';

/// E.164 without the `+`: drop the national trunk `0`, prefix Iraq's `964`.
/// 07701322947 → 9647701322947. The trap worth a test: keeping the leading
/// zero, or omitting the country code, silently produces a link to nobody.
String whatsAppDigits() => '964${subscriptionWhatsApp.replaceFirst(RegExp(r'^0'), '')}';

Uri whatsAppAppUri() => Uri.parse('whatsapp://send?phone=${whatsAppDigits()}');
Uri whatsAppWebUri() => Uri.parse('https://wa.me/${whatsAppDigits()}');

Uri subscriptionEmailUri() => Uri(
      scheme: 'mailto',
      path: subscriptionEmail,
      query: Uri(queryParameters: {'subject': '${S.productNameEn} Subscription'}).query,
    );
```

Telegram is **shared** — subscription contact reuses the existing
`supportTelegram` / `telegramAppUri()` / `telegramWebUri()`. `@jjkkkj` is
already the value in the file.

WhatsApp follows the established Telegram two-step: try the app scheme, fall
back to `https://wa.me/…`, then offer copy — precisely the sequence
`about_page.dart` already implements for Telegram, through the same
`ExternalLinkLauncher`.

### 8.1 Support email vs subscription email

`supportEmail` is `medical.team.auth@gmail.com` and is pinned by
`support_contacts_test.dart`. The subscription email is
`nullmod.dev@gmail.com`.

**Ruling: keep both, as two named constants with two roles.** Support is "my
app is broken"; subscription is "I want to pay". They may currently reach the
same person, and that is fine — one of them can change without the other, which
is the reason to keep two names.

> **Claude-provisional (P2).** If Ahmed wants one address everywhere, change
> `supportEmail` and its pinning test, and point both constants at it. Nothing
> in this design depends on them differing.

### 8.2 Presentation

`SubscriptionContactSection` — a widget in the pricing feature reading those
constants, rendering three rows (Telegram · WhatsApp · Email), each with an open
action and a copy fallback, reusing the row/copy/outcome pattern of
`about_page.dart`'s `_Support`.

The block states plainly that subscription is completed by contacting Leader.
It never says "payment", never implies a card, and never claims an SLA.

---

## 9. Super Admin commercial management

**Route `/platform/operations/commerce` · row label «الأسعار والعروض».**

Under Operations, as a child of the area route — exactly like
`/platform/operations/demo`, and for the same reason: `PlatformArea` has four
values and gains no fifth. No new `siblingSegment` is registered (the area
claims children of its own route automatically).

Label choice: the sibling rows are short nouns («الصحة», «الأمان», «التدقيق»,
«التجربة», «التقارير»). «الأسعار والعروض» matches that register and — unlike the
brief's «الخطط والعروض» / «الاشتراكات والعروض» — collides with neither the
tenant's «الخطة والاشتراك» (`/more/plan`) nor the new «الاشتراك والأسعار».

### 9.1 Page structure

```
/platform/operations/commerce          hub: three sections
  ├── Base prices                      READ-ONLY (§9.2)
  ├── Global offers                    list + «إنشاء عرض عام»
  └── Coupons                          list + «إنشاء كوبون»
/platform/operations/commerce/offer            create
/platform/operations/commerce/offer/:id        edit
/platform/operations/commerce/coupon           create
/platform/operations/commerce/coupon/:id       edit
```

### 9.2 Base prices are read-only this phase

**Ruling: display only. No editing.**

The brief offered read-only or mock-editable and asked for a recommendation.
Read-only, because an editable price that persists to process memory is a
control that appears to work and silently does not: it survives no restart,
reaches no other device, and changes nothing any user would ever see. The repo
already holds this line — `PlatformAreaReadiness` documents *"says truthfully
what it will manage, and offers no control that does nothing"*.

The section shows the four prices and one sentence saying prices are managed by
the platform and are not editable from this build. When the backend lands, this
section gains real controls against a real endpoint.

### 9.3 Offer and coupon forms

**Global offer** — enabled toggle · target (`monthly` / `three_months` only,
from `kPromotionEligibleOptions`) · discount type (percentage / fixed final
price) · value · optional title · optional end date. Actions: create, edit,
enable, disable, remove.

**Coupon** — code (normalized live, §5) · enabled · target · discount type ·
value · assignment (anyone with the code / a specific account id) · optional
internal note · optional expiry. Same actions.

No campaign analytics, no redemption counts, no scheduling engine, no
A/B testing. A start date is **not** offered: `endsAt` answers "stop showing
this", which an operator genuinely needs, while a start date is a scheduler this
build cannot run (nothing wakes up to enable an offer) and would be a control
that does nothing.

### 9.4 Every destructive action confirms

Removing an offer or coupon, and disabling one that is live, go through a
confirmation dialog — the pattern `platform_demo_page.dart` already uses for
terminate / terminate-all / cleanup.

---

## 10. Control plane and providers

### 10.1 `CommerceControlPlane`

`lib/features/pricing/data/commerce_control_plane.dart` — a
`Notifier<CommerceState>`, modelled directly on `DemoControlPlane`, with the
same header warning: **development and test only, process memory, not
persisted, replaced by a backend adapter.**

Not persisted to `LocalStore`, for `DemoControlPlane`'s own stated reason: a
control-plane fact about *other people's* commercial offers has no business in
one device's storage, and persisting it would let a reinstall undo an operator's
action.

```dart
@immutable
final class CommerceState {
  final List<GlobalOffer> offers;   // newest first
  final List<Coupon> coupons;       // newest first

  GlobalOffer? liveOfferFor(BillingOptionId option, DateTime now);
  Coupon? couponByCode(String normalizedCode);
}

abstract final class CommerceCodes {
  static const notAuthorized     = 'not_authorized';
  static const offerNotFound     = 'offer_not_found';
  static const offerConflict     = 'offer_conflict';
  static const couponNotFound    = 'coupon_not_found';
  static const couponCodeTaken   = 'coupon_code_taken';
  static const couponCodeInvalid = 'coupon_code_invalid';
  static const promotionInvalid  = 'promotion_invalid';
}
```

Mutations, each `Result<T>` and each taking `{CommerceActor? actor}`, refusing
with `notAuthorized` when it is null:

`createOffer` · `updateOffer` · `setOfferEnabled` · `removeOffer` ·
`createCoupon` · `updateCoupon` · `setCouponEnabled` · `removeCoupon`

**Invariant — at most one live global offer per billing option.** "The active
eligible offer" must be a single thing or the pricing page has to pick
arbitrarily. Enabling or creating a second live offer for an option is
**refused** with `offerConflict`; it does not silently disable the other one.
Silently mutating a record the operator did not name is the kind of helpfulness
that loses somebody's configuration.

Coupon codes are unique: a second coupon with an existing normalized code is
refused with `couponCodeTaken`.

**Seed fixtures** (a `commerceControlPlaneSeedProvider`, overridable in tests,
following `demoControlPlaneSeedProvider`) so the Super Admin screens can be
reviewed with real rows rather than three empty lists — one disabled global
offer, one public coupon, one targeted coupon.

> Seeds must be **disabled by default** so the *user* pricing page's default
> state is State A (plain prices). A seeded live offer would make every
> screenshot and every unrelated test render a promotion.

### 10.2 Authorization — in the platform feature, never in a widget

`lib/features/platform/data/platform_commerce_providers.dart`, mirroring
`platform_demo_providers.dart`:

```dart
final platformCommerceActorProvider = Provider<CommerceActor?>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null || user.role != AuthRole.superAdmin) return null;
  return CommerceActor(accountId: user.id, displayName: user.name);
});

class PlatformCommerceActions { /* one method per mutation, injecting _actor */ }
final platformCommerceActionsProvider = Provider<PlatformCommerceActions>(…);
```

Main Admin, Simple Admin and Demo cannot build an actor, so every mutation they
could somehow reach returns `not_authorized`. This is **not** a tenant `Cap`:
`CAPABILITIES.md` is explicit that the 30 tenant keys are tenant-operational and
that platform authority is a different axis. Do not add a `Cap` for this.

### 10.3 User-facing providers

`lib/features/pricing/data/pricing_providers.dart`:

| Provider | Type | Purpose |
| --- | --- | --- |
| `pricingCatalogProvider` | `Provider<List<BillingOption>>` | the four priced options; **the backend seam** |
| `liveGlobalOffersProvider` | `Provider<Map<BillingOptionId, GlobalOffer>>` | live offers as of `clockProvider` |
| `couponEntryProvider` | `NotifierProvider<CouponEntry, CouponEntryState>` | field text, phase, last result |
| `priceQuotesProvider` | `Provider<List<PriceQuote>>` | §6.3 resolution, the page's single read |
| `selectedBillingOptionProvider` | `StateProvider<BillingOptionId>` | presentational selection; defaults to `twelveMonths` |

`CouponEntryState` is `{ String input, CouponPhase phase, Result<CouponResolution>? last }`
with `CouponPhase { idle, validating, done }` — states C/D/E/F/G.

The page reads `priceQuotesProvider` and renders. All resolution logic is pure
and lives in `domain/`, so it is unit-testable with no widget pump.

`pricingCatalogProvider` is the seam a backend adapter overrides. Today it
returns a const list; tomorrow it returns an `AsyncValue` from
`GET /pricing/catalog`. That is the only provider whose *type* changes when the
backend lands, and the page is written against a list it gets from a provider
rather than against a const, so the change is contained.

---

## 11. Routing

### 11.1 Tenant

In `_moreBranch` (`core/router/app_router.dart`), beside `plan`:

```dart
GoRoute(
  path: 'pricing',
  pageBuilder: (context, state) =>
      _sharedAxisPage(key: state.pageKey, child: const PricingPage()),
),
```

**`/more/pricing` must NOT be added to `_demoBlockedLocations`.** That is the
one-line mechanism by which a demo can view pricing, and it should carry a
comment saying so — the set currently blocks `/more/plan` and
`/more/organization`, and the next reader will reasonably wonder why this
sibling is absent.

### 11.2 Platform

Add to `_platformOperationsRoutes`, following the `demo` entry, with
`offer`/`coupon` create and `:id` edit as nested routes so back returns to the
hub.

`PlatformOperationsRoutes` gains:

```dart
static const String commerce = '$kPlatformRoot/operations/commerce';
static const String commerceOffer = '$commerce/offer';
static const String commerceCoupon = '$commerce/coupon';
```

and `commerce` is appended to `PlatformOperationsRoutes.all`.

No change to `platform_area.dart` — `PlatformArea.operations.contains()` already
matches children of `/platform/operations`.

### 11.3 Cross-surface

- A Super Admin reaching `/more/pricing` is turned around by the existing
  surface redirect, unchanged. The platform surface has its own commercial
  screen and does not need the customer-facing one.
- A tenant or demo session reaching `/platform/…` is refused by the existing
  classifier, unchanged.

---

## 12. Demo conversion

### 12.1 Where the CTA goes — one place

**`DemoTrialBar`**, the bar that already says "this is a trial" and already
travels above every screen of the shell. The offer belongs exactly where the
thought occurs, and the bar is the one surface that is demo-only, so nothing is
added to a tenant screen.

Add a `TextButton` «شاهد الخطط» (key `demo-see-plans`) alongside the existing
exit, routing to `PricingPage.routePath`.

**The layout rule must change with it.** The bar today is
`Row(notice, exit)` and stacks only when `textScaler.scale(14) > 18`. Three
children do not fit a 320dp row. Codex must widen the stack condition to:

```dart
final stacked = MediaQuery.textScalerOf(context).scale(14) > 16 ||
    MediaQuery.sizeOf(context).width < 360;
```

and, in the stacked branch, place the two buttons in a `Wrap` so they flow onto
separate lines rather than overflowing. **Exit must remain reachable in every
configuration** — that is the bar's documented invariant and the conversion CTA
does not get to compromise it.

The fuller phrasing «أعجبتك ليدر؟ شاهد خطط الاشتراك» does not fit a bar button.
Use it as the pricing page's intro line instead, where it has room; the button
says «شاهد الخطط».

### 12.2 Deliberately not on the demo-expired page

A closed demo has left the shell that hosts `/more/pricing`; the startup
classifier holds it at `/demo-expired`, which is outside the tenant branch. A
CTA there would need either a second pricing route on the root navigator or a
redirect exception — a real change to the startup contract for one button.

Noted as a genuine future opportunity (expiry *is* a good conversion moment),
explicitly deferred, and not silently dropped.

### 12.3 Demo commercial isolation is structural

A demo cannot create a `TenantSubscription`, a `SaasTenant`, payment state, or
any commercial record — **because no such write path exists on this surface**.
The pricing page has no mutation at all. The only writes in the feature are the
Super Admin control plane's, which demand an actor a demo identity cannot build.

This is stronger than a guard, and §19 tests it as a structural claim: pump the
pricing page in a demo session and assert `CommerceState` is unchanged *and*
that no tenant repository was constructed — reusing `TenantRepositoryWatch` from
`test/features/platform/platform_harness.dart`, which exists for precisely this
kind of assertion.

A demo may type a coupon. Public coupons validate; a targeted coupon does not
match the demo identity and returns the shared invalid message. No special case,
no branch.

---

## 13. Honest-pricing copy rules

Binding on every string in this feature:

- **Allowed:** original price, offer price, «عرض خاص», «خصم ٢٠٪», a real end
  date when one is configured, a real savings figure.
- **Forbidden:** countdown timers, "today only", "limited stock", "N people are
  viewing", fake original prices, any urgency not backed by a configured
  `endsAt`, and any purchase verb («ادفع الآن», «اشترك الآن» as a button that
  does not subscribe).
- A struck-through price appears **only** when a promotion actually applies.
- If no expiry is configured, the UI says nothing at all about time.
- The primary action is «للاشتراك تواصل معنا». It is honest about what pressing
  it does: it opens Telegram, WhatsApp, or mail.

All strings go in `lib/l10n/strings.dart` under a `// ---------- Pricing ----------`
group. No Arabic literal in widget code — the existing rule, no exception here.
Brand mentions read `S.productNameAr`, never a literal.

---

## 14. The redemption boundary

Stated once, plainly, because it is the easiest thing in this design to get
wrong later:

**«تحقق من الكوبون» validates and displays. It does not redeem.**

It does not consume a one-time coupon, does not decrement a counter (there is
no counter), does not mark anything used, does not activate a subscription and
does not record a payment. A user may validate the same coupon fifty times.

Redemption is a **backend** operation that happens **after** a successful
payment, in the same transaction that activates the subscription (§17). Any
future client change that consumes a coupon at validation time is a bug, and
a one-time coupon burned by a user who never paid is what it would cost.

---

## 15. Capabilities and authorization summary

| Actor | View `/more/pricing` | Validate a coupon | Open `/platform/operations/commerce` | Mutate offers/coupons |
| --- | --- | --- | --- | --- |
| Customer Demo | ✅ | ✅ | ❌ (surface) | ❌ (no actor) |
| Simple Admin | ✅ | ✅ | ❌ (surface) | ❌ (no actor) |
| Main Admin | ✅ | ✅ | ❌ (surface) | ❌ (no actor) |
| Super Admin | ❌ (surface redirect) | — | ✅ | ✅ |

- Viewing prices requires **no capability**. It is public product information to
  anyone holding a session, and gating it would hide the product from the people
  being asked to buy it.
- Mutation authority is **platform authority**, not a tenant `Cap`. No new key
  is added to `Cap`, and `CAPABILITIES.md` §2's separation is preserved.

---

## 16. Temporary Super Admin development credential

### DEVELOPMENT / DEBUG ONLY — NOT SECURITY

Reuse the existing seam. **Add no new credential mechanism.** Two value edits:

1. `lib/features/auth/data/demo_personas.dart` — `_superAdmin.email`:
   `'platform@mtm.app'` → `'nullmod.dev@gmail.com'`
2. `lib/features/auth/data/dev_test_credentials.dart` —
   `DevTestCredentials.superAdmin.password`:
   `'mtm-dev-super-2026'` → `'nullmod.dev@gmail.com'`

Everything else already holds:

- guarded by `demoAccountsAllowed` (`core/env/build_mode.dart`), `const false`
  outside debug, so the table is **tree-shaken out of a release artefact**;
- the Login screen renders **no** persona picker, card or shortcut in any build
  — dev identities are typed into the ordinary fields;
- the password is never rendered and never logged;
- `MockAuthRepository` consults `DevTestCredentials.forEmail` only behind that
  same flag.

**Codex must verify**, not assume, that nothing asserts the old values:

```bash
rg -n "platform@mtm\.app|mtm-dev-super-2026" flutter_app/
```

Update whatever that finds (expected: `demo_personas_test.dart`,
`demo_login_test.dart`, possibly `platform_more_test.dart`). Note that the Super
Admin's profile screen displays `user.email`, so it will now show
`nullmod.dev@gmail.com` — that is a real contact address and is fine.

### Security note — for the record, and for Codex

This credential is **embedded development test data**. The password equals the
email, which is trivially guessable, and anyone with a debug APK can extract the
whole table. **It is not security and must never be described as security.**

It exists only because there is no backend auth yet. When real authentication
lands, this table is deleted — not migrated, not "kept for convenience". The
whole file is designed to be removable: it is one `abstract final class`, three
constants, and one lookup behind a compile-time-false flag.

**Never** put this password in `BACKEND-HANDOFF.md`, `API_CONTRACT.md`,
`README.md`, or any user-facing or public product documentation. This section is
its only home.

---

## 17. Future backend contract

The backend owns, authoritatively:

base pricing catalog · global offers · coupons · coupon→account targeting ·
coupon validation · **coupon redemption** · usage limits and counters · expiry ·
the final price · subscription activation and renewal · the price actually paid.

### 17.1 What the client sends at purchase time

```
POST /billing/checkout
{ "billingOptionId": "monthly", "couponCode": "TRY2" }   // code optional
```

### 17.2 What the backend does

1. loads the authoritative base price for `billingOptionId`;
2. resolves the live global offer for that option;
3. validates the coupon — existence, enabled, expiry, **account assignment**,
   target eligibility, usage limits;
4. applies **the better of** offer and coupon — never both (§6.3);
5. computes the final price server-side;
6. processes payment;
7. **only after payment succeeds**, consumes the redemption and activates or
   renews the subscription;
8. **snapshots the price actually paid** on the subscription record, so a later
   price or offer change never rewrites history.

### 17.3 What the backend must never trust

The client-computed final price · the client-computed savings · any
client-asserted "coupon is valid" boolean · the client's view of eligibility ·
the client clock.

Every number this Flutter client renders is a *preview* of the backend's answer.
If they disagree, the backend is right and the client must show the backend's
figure.

### 17.4 Endpoint families to reserve

```
GET    /pricing/catalog
GET    /pricing/offers/active
POST   /pricing/coupons/validate        ← validate only; MUST NOT consume
GET    /platform/commerce/offers        POST /platform/commerce/offers
PATCH  /platform/commerce/offers/{id}   DELETE …
GET    /platform/commerce/coupons       POST /platform/commerce/coupons
PATCH  /platform/commerce/coupons/{id}  DELETE …
POST   /billing/checkout                ← the only endpoint that redeems
```

Audit events to reserve: `commerce_offer_created` / `_updated` / `_enabled` /
`_disabled` / `_removed`, `commerce_coupon_*` likewise, and
`commerce_coupon_redeemed` (backend-authored, at payment, never at validation).

### 17.5 Money on the wire

Integer minor units and an explicit currency, always:

```json
{ "amount": 600, "currency": "USD" }
```

Never a float, never a formatted string, never a bare number whose unit has to
be inferred.

---

## 18. Files

### 18.1 New — `lib/features/pricing/`

```
domain/money.dart                    Money, formatting, effective monthly, savings
domain/billing_option.dart           BillingOptionId, BillingOption, kPromotionEligibleOptions
domain/coupon_code.dart              normalizeCouponCode
domain/promotion.dart                Discount sealed, GlobalOffer, Coupon, CouponAssignment
domain/price_quote.dart              PriceQuote, AppliedPromotion, PromotionSource, resolution
domain/coupon_validation.dart        validateCoupon, CouponResolution, CouponValidationCodes
data/pricing_catalog.dart            const catalog + pricingCatalogProvider (backend seam)
data/commerce_control_plane.dart     CommerceState, CommerceCodes, CommerceControlPlane, seed
data/pricing_providers.dart          live offers, coupon entry, quotes, selection
presentation/pricing_page.dart       PricingPage (+ routePath)
presentation/pricing_widgets.dart    PlanCard, OfferBanner, CouponSection, PricingNote, PricingColumns
presentation/subscription_contact.dart
presentation/pricing_copy.dart       labels derived from domain values
```

### 18.2 New — platform side

```
lib/features/platform/data/platform_commerce_providers.dart
lib/features/platform/presentation/platform_commerce_page.dart
lib/features/platform/presentation/platform_offer_edit_page.dart
lib/features/platform/presentation/platform_coupon_edit_page.dart
lib/features/platform/presentation/platform_commerce_copy.dart
```

### 18.3 Modified

| File | Change |
| --- | --- |
| `lib/l10n/strings.dart` | new Pricing group; `sectionSubscription`; platform commerce strings |
| `lib/core/router/app_router.dart` | `/more/pricing`; commerce routes in `_platformOperationsRoutes`; comment on `_demoBlockedLocations` |
| `lib/features/platform/presentation/platform_operations_routes.dart` | `commerce*` constants, added to `all` |
| `lib/features/platform/presentation/platform_operations_page.dart` | «الأسعار والعروض» `NavigationRow` |
| `lib/features/settings/presentation/settings_page.dart` | new Subscription section + row (unconditional) |
| `lib/features/demo/presentation/demo_trial_bar.dart` | «شاهد الخطط» + widened stack rule (§12.1) |
| `lib/features/about/domain/support_contacts.dart` | `subscriptionEmail`, `subscriptionWhatsApp`, WhatsApp URIs |
| `lib/features/auth/data/demo_personas.dart` | Super Admin email (§16) |
| `lib/features/auth/data/dev_test_credentials.dart` | Super Admin password (§16) |
| `lib/features/organization/presentation/plan_page.dart` | *optional, last:* one link to `/more/pricing` from the explain note |

### 18.4 Not touched

`core/access/capability.dart` (no new `Cap`) · `platform_area.dart` (no fifth
area) · `features/platform/domain/saas_subscription_models.dart` (tenant
subscription records are a different concern) · anything under
`features/organization/domain/`.

---

## 19. Test matrix

New directory `test/features/pricing/`.

| File | Covers |
| --- | --- |
| `money_test.dart` | cents arithmetic; §3.1 rounding table; effective monthly `600/1400/2400/4000`; savings; `$6` vs `$4.67` formatting; LTR isolate present |
| `billing_catalog_test.dart` | the four prices are exactly `600/1400/2400/4000`; `months` correct; **all four grant identical access**; `kPromotionEligibleOptions == {monthly, threeMonths}`; `tryParse` fails closed |
| `coupon_code_test.dart` | trim · internal whitespace · `try2→TRY2` · `TEAM-20` valid · length bounds · Arabic-Indic digits rejected · Cyrillic look-alike rejected · Unicode hyphen rejected |
| `promotion_domain_test.dart` | `Discount` exhaustiveness; `applyDiscount` both variants; `FixedFinalPriceDiscount(200)` on `$6`; `isSaneFor` rejects `$0`, ≥ base, 0%, 100% |
| `coupon_validation_test.dart` | all 7 rules **in order**; each code; not-found/not-assigned/disabled share one message; wrong-target has its own; targeted-correct-user passes; targeted-wrong-user fails; expired |
| `price_resolution_test.dart` | no stacking (10% + TRY2 → TRY2 only); best price wins; tie → global offer; coupon-worse → G′; ineligible durations never discounted; `promotion == null` ⇒ base |
| `commerce_control_plane_test.dart` | every mutation; `not_authorized` with a null actor; `offer_conflict`; `coupon_code_taken`; `promotion_invalid`; seeds disabled by default |
| `pricing_page_test.dart` | states **A–I** incl. G′; selection is presentational; primary action is contact not pay; invalid coupon keeps the field text; no purchase verb anywhere |
| `pricing_contact_test.dart` | `whatsAppDigits() == '9647701322947'`; wa.me URI; `whatsapp://` app URI; telegram reuse; `subscriptionEmail` exact; mailto encoding; all three render |
| `pricing_appearance_test.dart` | 320dp · 390dp · 1.6× · 2.0× · RTL · six palettes · dark · eye-protect — **no overflow**. Model on `platform_appearance_test.dart` |

Extended:

| File | Added |
| --- | --- |
| `test/features/platform/platform_commerce_test.dart` *(new)* | Super Admin opens the area; forms create/edit/enable/disable/remove; target picker offers only eligible durations; base prices read-only; destructive actions confirm |
| `test/features/platform/platform_routing_test.dart` | tenant + demo refused `/platform/operations/commerce` |
| `test/features/demo/demo_pricing_conversion_test.dart` *(new)* | «شاهد الخطط» present and routes to `/more/pricing`; demo renders the page; **`CommerceState` unchanged**; **no tenant repository constructed** (`TenantRepositoryWatch`); trial bar keeps Exit reachable at 320dp/2.0× |
| `test/features/about/support_contacts_test.dart` | new WhatsApp/subscription constants and URIs |
| `test/features/auth/demo_personas_test.dart`, `demo_login_test.dart` | new Super Admin credential; still no rendered shortcut; release-mode guard intact |
| `test/features/settings/…` (whichever pins the More hub) | pricing row present for **both** demo and tenant |

Baseline is **2222 passing**. The suite must be green at that count plus the
new tests when the feature lands.

---

## 20. CODEX IMPLEMENTATION HANDOFF

### 20.1 Product rules — non-negotiable

1. One Leader plan. Four durations: `$6 / $14 / $24 / $40` = `600 / 1400 / 2400 / 4000` cents.
2. All four durations grant **identical** capabilities. No duration-gated feature.
3. `twelve_months` is labelled «أفضل قيمة».
4. Promotions may target **`monthly` and `three_months` only**, read from `kPromotionEligibleOptions`.
5. Two discount types: percentage, and fixed **final** price.
6. Money is integer cents. Floating-point money never exists.
7. Percentage rounding: `discount = ((base * pct) + 50) ~/ 100`, then subtract.
8. **No stacking.** Best eligible price wins; tie → global offer; the screen names which applies.
9. Validation **never** redeems, consumes, activates or charges.
10. Demo may **view** pricing and validate coupons; it may create no commercial state.
11. Primary action is «للاشتراك تواصل معنا». No purchase verbs anywhere.
12. No fake urgency, countdowns, stock, or unconfigured expiry claims.
13. Commercial mutation is **platform authority**, not a tenant `Cap`.

### 20.2 Order of implementation

Each step compiles and its tests pass before the next begins. Steps 1–4 are pure
Dart with no Flutter import and should be fully green before any widget exists.

| # | Step | Deliverable | Gate |
| --- | --- | --- | --- |
| 1 | `domain/money.dart` | `Money`, rounding, effective monthly, savings, formatting | `money_test.dart` |
| 2 | `domain/billing_option.dart` + `data/pricing_catalog.dart` | enum, `BillingOption`, eligibility set, const catalog, provider | `billing_catalog_test.dart` |
| 3 | `domain/coupon_code.dart`, `domain/promotion.dart` | normalization, `Discount` sealed, `GlobalOffer`, `Coupon`, assignment, `isSaneFor` | `coupon_code_test.dart`, `promotion_domain_test.dart` |
| 4 | `domain/price_quote.dart`, `domain/coupon_validation.dart` | resolution + validation, both pure | `price_resolution_test.dart`, `coupon_validation_test.dart` |
| 5 | `data/commerce_control_plane.dart` | `Notifier`, codes, actor-gated mutations, disabled seeds | `commerce_control_plane_test.dart` |
| 6 | `data/pricing_providers.dart` | live offers, coupon entry, quotes, selection | — |
| 7 | `support_contacts.dart` + strings | WhatsApp/subscription constants and URIs; Pricing string group | `pricing_contact_test.dart` |
| 8 | `presentation/pricing_page.dart` + widgets | the page, states A–I | `pricing_page_test.dart` |
| 9 | Route `/more/pricing` + `SettingsPage` row | tenant + demo entry | settings/router tests |
| 10 | `demo_trial_bar.dart` CTA + stack rule | «شاهد الخطط» | `demo_pricing_conversion_test.dart` |
| 11 | `platform_commerce_providers.dart` | actor + actions | — |
| 12 | Platform commerce pages + routes + ops row | hub, offer form, coupon form | `platform_commerce_test.dart`, `platform_routing_test.dart` |
| 13 | Dev credential (§16) | two value edits + grep-and-fix the pins | auth tests |
| 14 | Appearance sweep | 320/390dp, 1.6×/2.0×, RTL, six palettes, dark, eye-protect | `pricing_appearance_test.dart` |
| 15 | *Optional:* Plan → Pricing link | one button on `/more/plan` | existing org tests stay green |

### 20.3 Traps — read before starting

- **`FloatingNavPadding`** wraps the body of every page inside the shell. A page
  without it is overlapped by the floating nav at the bottom.
- **Do not add `/more/pricing` to `_demoBlockedLocations`.** That absence *is*
  the demo-can-view mechanism; comment it so nobody "fixes" it.
- **Do not add a `PlatformArea` value.** Four areas, closed. Commerce is a page
  inside Operations.
- **Do not add a `Cap` key.** Platform authority is a separate axis.
- **The demo trial bar's stack rule must widen** before the third control is
  added, or it overflows at 320dp. Exit stays reachable in every configuration.
- **Money needs an LTR isolate** inside the Arabic RTL paragraph, or `$6.00`
  reorders at the start of a line.
- **WhatsApp number:** drop the leading `0`, prefix `964` → `9647701322947`.
  Keeping the zero produces a link to nobody, and it fails silently.
- **`toUpperCase()` before the ASCII pattern check**, never after.
- **`OrganizationNote` / `OrganizationColumns` are not shared widgets.**
  Re-implement small local equivalents; do not import across features and do not
  move them.
- **Seed offers ship disabled**, or every unrelated screenshot renders a
  promotion.
- **No Arabic literal in widget code.** Everything through `S`.

### 20.4 Validation commands

```bash
cd flutter_app

# during development, per step
flutter test test/features/pricing/
flutter analyze lib/features/pricing/

# before declaring the step done
flutter test test/features/pricing/ test/features/platform/ \
             test/features/demo/ test/features/auth/ test/features/about/

# full gate — must be green, baseline 2222 + new
flutter analyze
flutter test
```

Docs-only or non-runtime changes: `git diff --check`.

**Never** `git commit`, `push`, `stash`, `reset`, or `clean`. The working tree
is intentionally dirty and must be preserved.

### 20.5 Non-goals — do not build these

Payment gateways · Stripe / Google Play Billing / Apple IAP · subscription
activation · coupon redemption or usage counters · invoices · tax / VAT ·
refunds · chargebacks · card tokens · recurring billing · proration · revenue
analytics · campaign analytics · referral or affiliate programmes · multiple
product tiers · AI features · editable base prices · offer start-date
scheduling · a second pricing page · a demo-specific pricing page.

---

## 21. Open rulings — Claude-provisional, pending Ahmed

Made so the design is complete and Codex is unblocked. Each is cheap to reverse.

| # | Ruling | Reverse by |
| --- | --- | --- |
| **P1** | Money uses **Western** digits + `$`, LTR-isolated, not Arabic-Indic (§3.4) | one formatter |
| **P2** | `supportEmail` and `subscriptionEmail` stay **two** constants with two roles (§8.1) | point both at one address; update the pinning test |
| **P3** | Base prices are **read-only** in the Super Admin UI this phase (§9.2) | add controls when a real endpoint exists |
| **P4** | Platform row label is **«الأسعار والعروض»** (§9) | one string |
| **P5** | Tie between offer and coupon → **global offer** wins (§6.3) | one comparison |
| **P6** | A valid-but-worse coupon shows state **G′** rather than being discarded (§6.3) | one branch + one string |
| **P7** | `not_found` / `not_assigned` / `disabled` share **one** user-facing message (§6.1) | split the messages |
| **P8** | **No** `maxUses` / usage counter is modelled; documented as backend-owned (§14, §17) | add when redemption exists |
| **P9** | Conversion CTA lives **only** in the trial bar; demo-expired deferred (§12.2) | §12.2 names the cost |
| **P10** | At most **one** live offer per option; a second is **refused**, not auto-disabled (§10.1) | change the refusal to a swap |
| **P11** | Offers get `endsAt` but **no** start date (§9.3) | needs a scheduler to be meaningful |
| **P12** | Pricing row sits in its **own** Settings section, above the org section (§7.1) | move the row |
