/// The app's single startup / session decision.
///
/// **Why this file exists.** Before it, "where does this launch belong" was
/// spread across `appRouterProvider`'s `redirect` as a chain of `if`s that
/// each knew one fact — the upgrade gate, then a three-arm switch on
/// `AuthGate`, then two lines about `super_admin`. Every new session state
/// (a suspended account, a deleted customer, a demo workspace, an account with
/// no assigned access) would have added another `if` to that chain, in an
/// order nobody had written down, inside a closure no test could call
/// directly. So the decision moved here: **one enum, one pure function, one
/// documented priority.** The router consumes the answer; it does not compute
/// one.
///
/// **It is pure.** [resolveStartup] takes a record and returns a value — no
/// `Ref`, no `BuildContext`, no provider read, no import of a screen. That is
/// what makes the whole state table testable without pumping a widget, and it
/// is why the canonical route strings live on [StartupDestination] rather than
/// on the pages: a decision layer that imported presentation could not stay
/// pure, and two spellings of `/platform` is how a redirect loop ships.
///
/// **It is a UX gate, like every access decision in this client.** It keeps a
/// session off a surface that would fail or mislead. The backend refuses the
/// request regardless — see the contract at the top of
/// `core/access/capability.dart`.
library;

import 'package:flutter/foundation.dart';

import '../access/saas_tenant_status.dart';
import '../../features/auth/data/auth_providers.dart' show AuthGate;
import '../../features/auth/domain/auth_models.dart';
import '../../features/auth/domain/onboarding_models.dart';
import '../../features/auth/domain/session_access.dart';
import '../../features/platform/domain/platform_area.dart';

/// Where a launch belongs.
///
/// One value per *user-visible outcome*, not one per input: two different
/// reasons that land a person on the same screen saying the same thing would
/// be one value here, and two reasons that need two different sentences are
/// two values however similar their causes look.
enum StartupDestination {
  /// The session read has not landed yet. A branded loading surface — never
  /// a protected screen, and never the login form, because we do not yet know
  /// that nobody is signed in.
  restoring(location: '/startup'),

  /// This build is refused by the version gate. Outranks everything: see the
  /// priority note on [resolveStartup].
  forcedUpgrade(location: '/upgrade-required'),

  /// There was a session and it is no longer valid.
  sessionExpired(location: '/session-expired'),

  /// An account payload this client cannot classify — a `super_admin` carrying
  /// a tenant id, a `main_admin` carrying none. Fails closed onto its own
  /// screen rather than quietly reading as signed out, so the person is told
  /// something is wrong with the account rather than being asked to sign in
  /// again into the same broken state.
  invalidSession(location: '/session-invalid'),

  /// The session envelope carried a **lifecycle value this build cannot
  /// interpret**, so no product surface may be opened on a guess.
  ///
  /// Not an account fault and not an authentication failure: the account is
  /// well-formed and the server answered. What is missing is this build's
  /// ability to say whether the state it named is more permissive or more
  /// restrictive than the ones it knows — and guessing "permissive" is how an
  /// old client hands a locked account the whole application. See
  /// `SessionAccess.unsupported`.
  unsupportedAccessState(location: '/session-unsupported'),

  /// Definitively nobody is signed in.
  signedOut(location: '/login'),

  /// Authentication is not finished: the server is waiting for a second
  /// factor. A hook — nothing in this build sets it. See
  /// [SessionAccess.mfaRequired].
  mfaRequired(location: '/mfa-challenge'),

  /// Access has been withdrawn from this account.
  accountRevoked(location: '/account-revoked'),

  /// This account is temporarily blocked.
  accountSuspended(location: '/account-suspended'),

  /// The customer this account belongs to no longer exists.
  tenantDeleted(location: '/tenant-deleted'),

  /// Final deletion is scheduled and ordinary tenant access is blocked.
  tenantDeletionPending(location: '/tenant-deletion-pending'),

  /// The customer this account belongs to is suspended.
  tenantSuspended(location: '/tenant-suspended'),

  /// Point 17A — the address has not been proved yet: a verification
  /// challenge is pending and **no session exists**. The code screen.
  emailVerification(location: '/verify-email'),

  /// Point 17A — verified, restricted onboarding session, linked to no
  /// tenant (or its link was withdrawn before setup). The Team Code screen.
  teamLink(location: '/link-team'),

  /// Linked, and first-use setup is not finished — or the full-session
  /// envelope says `pending_setup`. The account-setup screen, which in 17B
  /// also owns the final exchange of a completed onboarding session for a
  /// full one.
  firstTimeSetup(location: '/account-setup'),

  /// A customer demo session whose window has ended.
  demoExpired(location: '/demo-expired'),

  /// A customer demo session — the isolated full-product trial.
  ///
  /// It has **no location of its own**: the demo *is* the tenant application,
  /// so the session goes wherever it asks, exactly as [tenantSurface] does,
  /// and the same capability guards answer on every route. What makes it a
  /// demo is underneath: it has no `saasTenantId`, it holds the demo-only
  /// capability envelope, and every repository it reads is the in-memory
  /// `DemoWorkspace`. The startup-only wall in the router still keeps it out
  /// of `/platform` and off every classifier-owned status screen.
  demoActive(location: null),

  /// The platform control plane — `super_admin` and nobody else.
  ///
  /// The one destination that owns a **whole route subtree** rather than a
  /// single location: `/platform` is a shell with four branches and every page
  /// under it belongs to the same session (`features/platform/`). See
  /// [ownsSubtree].
  platformSurface(location: kPlatformRoot, ownsSubtree: true),

  /// A valid tenant account that holds no usable capability. An
  /// **authorization** outcome, not an account fault: valid, connected, and
  /// nothing assigned yet.
  tenantNoAccess(location: '/access-not-assigned'),

  /// The tenant application. The session goes wherever it asked, subject to
  /// the capability guards that already sit on each route.
  tenantSurface(location: null),

  /// **Nothing can be concluded, and nothing will be.**
  ///
  /// The session read answered and the answer was not evidence: an offline
  /// device with no cached account, or a transport error. Distinct from
  /// [restoring], which is still waiting and therefore still worth holding a
  /// loading screen for — this one has finished, and there is nothing more
  /// coming without connectivity.
  ///
  /// It redirects **nowhere**, which is the behaviour this offline-first app
  /// has always had and must keep: an app that parked a field user on a
  /// splash screen (or bounced them to a login form) because the network was
  /// down would be broken for exactly the conditions it is built for. What
  /// keeps that safe is not the router — it is that `capabilitiesProvider`
  /// resolves to `Capabilities.none` throughout, so every gated control and
  /// every guarded route is already refused and the screens render their own
  /// empty and offline states.
  unresolved(location: null);

  const StartupDestination({required this.location, this.ownsSubtree = false});

  /// The canonical route for this outcome, or `null` for [tenantSurface].
  final String? location;

  /// Whether [location] is the root of a subtree this outcome owns, rather
  /// than a single page.
  ///
  /// Only [platformSurface] sets it. Every other destination is one screen,
  /// and a screen that quietly acquired children would become unreachable the
  /// moment the router asked whether a session may sit on it.
  final bool ownsSubtree;

  /// Whether this outcome owns [here] — its own location, and everything
  /// beneath it when [ownsSubtree].
  ///
  /// The router asks this twice per navigation: *may this session stay where
  /// it asked*, and *is this a location only the classifier may send someone
  /// to*. Both readings have to agree about `/platform/tenants`, which is why
  /// they share one function rather than two `startsWith` expressions written
  /// a month apart.
  bool claims(String here) {
    final target = location;
    if (target == null) return false;
    if (here == target) return true;
    return ownsSubtree && here.startsWith('$target/');
  }

  /// Whether this outcome puts the person **inside** one of the two real
  /// product applications.
  ///
  /// The tenant shell and every tenant repository hang off this being true —
  /// see `MainShell`. Everything else is a holding or blocking surface that
  /// reads nothing.
  bool get isProductSurface =>
      this == StartupDestination.tenantSurface ||
      this == StartupDestination.platformSurface ||
      // The demo trial is the tenant application, read from an isolated
      // workspace — a product surface in every sense the shell cares about.
      this == StartupDestination.demoActive;

  /// Whether this outcome lets the app stay wherever it was asked to be.
  bool get keepsRequestedRoute => location == null;
}

/// Everything the decision is allowed to look at.
///
/// A record rather than a pile of positional arguments so a new input cannot
/// be silently added to one call site and forgotten at another, and so the
/// classifier's whole world is visible in one place.
@immutable
class StartupInputs {
  const StartupInputs({
    required this.gate,
    required this.now,
    this.user,
    this.introHolding = false,
    this.upgradeBlocks = false,
    this.access = SessionAccess.normal,
    this.hasTenantCapability = false,
    this.entry = const EntryNone(),
  });

  /// Whether the cold-launch brand intro is still on screen.
  ///
  /// Defaults to `false`, which is what every caller that does not run a real
  /// process launch gets — the classifier's whole table is unchanged for
  /// them. See `core/startup/intro_gate.dart` for why the hold is an input
  /// here rather than a delay inside the launch screen.
  final bool introHolding;

  /// Whether the forced-upgrade gate currently shuts the app.
  /// `AppVersionState.blocksApp` — not recomputed here.
  final bool upgradeBlocks;

  /// The injectable local clock instant used only to compare the
  /// server-issued session expiry. It is an input so this classifier remains
  /// pure and tests never depend on the machine clock.
  final DateTime now;

  /// What the session read concluded.
  final AuthGate gate;

  /// The account, when there is a well-formed one.
  ///
  /// `null` whenever [gate] is not [AuthGate.signedIn] — including for an
  /// account that was refused as malformed, which is why [gate] carries
  /// [AuthGate.invalid] separately: the refused payload is deliberately not
  /// exposed to anything downstream.
  final AuthUser? user;

  /// The server's lifecycle facts about this account, its customer and its
  /// demo mode. [SessionAccess.normal] for every session in this build.
  final SessionAccess access;

  /// Whether this session holds **any** capability at all, anywhere.
  ///
  /// Passed in rather than derived from [user] so the classifier never has to
  /// know how a grant is shaped — `Capabilities.hasAny` is the one place that
  /// question is answered.
  final bool hasTenantCapability;

  /// Point 17A — the pre-session journey on this device: a pending
  /// verification challenge or a restricted onboarding session.
  ///
  /// Consulted **only when there is no full session**. A full session means
  /// the server has already declared the account ready, so a stale entry
  /// state can never pull a signed-in account back into onboarding — and a
  /// pre-session identity can never reach a product surface, because it has
  /// no `AuthUser` for the rules below to classify.
  final AuthEntryState entry;
}

/// The one startup decision.
///
/// ## Priority, and why it is this order
///
///  0. **The cold-launch intro.** It is first because it is not an answer:
///     it is a hold, it can only ever resolve to [StartupDestination
///     .restoring] — the surface a launch already sits on — and it releases
///     itself after at most `IntroGate.ceiling`. Below (1) it would mean the
///     app could show the forced-upgrade screen, flash, and then show the
///     brand intro; above it, every real outcome is merely *late* by the
///     length of one animation, and each still applies in full the instant
///     the gate opens. Only a real process launch ever sets it.
///  1. **Forced upgrade.** It does not depend on a session, it resolves
///     synchronously from a verdict already persisted, and a build the backend
///     refuses must not spend a restoration on a session it may not use. This
///     is the documented deviation from "boot first": the existing gate
///     (`AppVersionController`) only ever *blocks when it has found a reason*,
///     so a launch that has not answered yet is not blocked and falls through
///     to (2) exactly as if this step were second.
///  2. **Restoring.** Until the session read lands nothing else is known, and
///     guessing here is what produces a flash of the wrong surface.
///  3. **Expired**, then (4) **invalid**, then (5) **signed out** — the three
///     authentication answers, ordered most-specific first. Expired and
///     invalid each say something a login form cannot.
///     **Point 17A:** "signed out" (and "unknown, no cached account") now
///     first asks the pre-session journey, in this order — see
///     [_entryDestination]:
///       a. stored journey not read yet → restoring;
///       b. refused onboarding payload → invalid;
///       c. verification pending → email verification;
///       d. onboarding session → unsupported value; account revoked,
///          suspended; not linked → Team Code; linked tenant deleted,
///          deletion pending, suspended; setup (incomplete *or* complete and
///          awaiting its full session) → account setup;
///       e. nothing → the ordinary answer (sign-in form, or unresolved).
///     Account lifecycle outranks the link, and tenant lifecycle outranks
///     setup — the same reasons as (7)–(12) below: a withdrawn account is
///     told that, and a blocked tenant does not invite anyone to finish.
///     Verification needs no rank of its own among them: a challenge exists
///     only *before* any session, so it can never coincide with (d).
/// 5a. **Server-issued session timestamp already elapsed.** The same expired
///     outcome as the repository's `authentication_expired`; checked locally
///     only when the optional envelope field is present.
/// 5b. **Unsupported access state.** Directly below the authentication
///     answers and above every authorization question, because it is the
///     statement *this build cannot evaluate the rest of this table*. Lower
///     would mean deciding MFA, a suspension or a surface out of an envelope
///     already known to be unreadable; higher would tell someone whose session
///     merely expired that their app is out of date.
///  6. **MFA required.** Authentication is still incomplete; an unfinished
///     challenge outranks every authorization question below it.
///  7. **Account revoked**, (8) **suspended** — the account's own lifecycle,
///     revocation first because it is the terminal one.
///  9. **Tenant deleted**, (10) **tenant deletion pending**, then (11)
///     **tenant suspended** — the customer's
///     lifecycle. After the account's: a person whose own access was withdrawn
///     is told that, not that their organisation is unavailable.
/// 12. **First-time / unlinked.** The account is fine and the customer is
///     fine; the account simply is not finished. Below the blocking states so
///     a suspended half-finished account is not invited to finish setting up.
/// 13. **Demo expired**, (14) **demo active** — before any role branch,
///     because a demo session must never be classified by a real surface's
///     rules even if it somehow carried a role.
/// 15. **Role → surface.** `super_admin` to the platform; everyone else to
///     the tenant application.
/// 16. **Tenant no-access.** Last, and only for a tenant account that got
///     this far: it is the narrowest outcome and every state above it is a
///     better explanation of the same empty screen.
/// 17. **The requested route**, which the existing capability guards then
///     answer for themselves.
StartupDestination resolveStartup(StartupInputs input) {
  if (input.introHolding) return StartupDestination.restoring;
  if (input.upgradeBlocks) return StartupDestination.forcedUpgrade;

  switch (input.gate) {
    case AuthGate.restoring:
      return StartupDestination.restoring;
    case AuthGate.expired:
      return StartupDestination.sessionExpired;
    case AuthGate.invalid:
      return StartupDestination.invalidSession;
    case AuthGate.signedOut:
      return _entryDestination(input.entry) ?? StartupDestination.signedOut;
    case AuthGate.unknown:
    case AuthGate.signedIn:
      break;
  }

  final user = input.user;
  if (user == null && input.gate == AuthGate.unknown) {
    // No full session could be read. A pre-session identity on this device
    // still routes to its own step — it must never fall into the "go where
    // you asked" behaviour below, which is for an offline tenant account.
    final entry = _entryDestination(input.entry);
    if (entry != null) return entry;
  }
  if (user == null) {
    // `AuthGate.unknown` with nothing cached: offline at a cold start, or a
    // transport error. Not evidence that anyone signed out, and not evidence
    // that anyone is signed in either — so nothing is decided. See
    // [StartupDestination.unresolved] for why this is not held on the loading
    // screen instead.
    return StartupDestination.unresolved;
  }

  // Fails closed a second time. `AuthGate.invalid` already catches this, and
  // it is repeated here because this function is also called directly by
  // tests and by the router with inputs assembled elsewhere: a malformed
  // account must not be able to reach a surface through any path.
  if (!user.isWellFormed) return StartupDestination.invalidSession;

  final access = input.access;

  // This is the same server-owned expiry fact as `authentication_expired`,
  // observed earlier from the optional session envelope. It is deliberately
  // not a client-generated lifetime and does not create a second timer.
  if (access.isExpiredAt(input.now)) {
    return StartupDestination.sessionExpired;
  }

  // Fails closed on forward compatibility. Every field below is read for a
  // gate, so a value this build could not parse means the gate cannot be
  // evaluated — and an unevaluated gate must not resolve to "open". An
  // *absent* field is not this: it takes its documented default, which is how
  // a backend that implements none of this envelope still reaches a surface.
  // See `SessionAccess.unsupported`.
  if (access.hasUnsupportedState) {
    return StartupDestination.unsupportedAccessState;
  }

  // Customer Demo is a fourth, isolated product identity. Both halves must
  // agree: a demo envelope on an administrator (or a demo role without the
  // envelope) is malformed and must never be allowed to fall through to a
  // tenant or Platform surface.
  final customerDemoRole = user.role == AuthRole.customerDemo;
  if (access.isDemo != customerDemoRole) {
    return StartupDestination.invalidSession;
  }

  if (access.mfaRequired) return StartupDestination.mfaRequired;

  switch (access.account) {
    case AccountStatus.revoked:
      return StartupDestination.accountRevoked;
    case AccountStatus.suspended:
      return StartupDestination.accountSuspended;
    case AccountStatus.pendingSetup:
    case AccountStatus.active:
      break;
  }

  // A demo session has no customer, so the tenant lifecycle below cannot
  // apply to it — but the account lifecycle above can, which is why the demo
  // branch sits here and not before it.
  if (!access.isDemo && user.role != AuthRole.superAdmin) {
    switch (access.tenant) {
      case SaasTenantStatus.deleted:
        return StartupDestination.tenantDeleted;
      case SaasTenantStatus.deletionPending:
        return StartupDestination.tenantDeletionPending;
      case SaasTenantStatus.suspended:
        return StartupDestination.tenantSuspended;
      case SaasTenantStatus.active:
        break;
    }
  }

  if (access.account == AccountStatus.pendingSetup) {
    return StartupDestination.firstTimeSetup;
  }

  switch (access.demo) {
    case DemoMode.expired:
      return StartupDestination.demoExpired;
    case DemoMode.active:
      return StartupDestination.demoActive;
    case DemoMode.none:
      break;
  }

  // Role selects the surface, and does nothing else. Nothing below or above
  // grants an action because of it — `Capabilities.canIn` still answers every
  // one of those, on the routes and in the screens.
  if (user.role == AuthRole.superAdmin) {
    return StartupDestination.platformSurface;
  }
  if (user.role == AuthRole.customerDemo) {
    return StartupDestination.invalidSession;
  }

  // A tenant account that holds nothing. Deliberately NOT read as suspended,
  // revoked or unfinished: an empty grant means nobody has assigned this
  // person anything yet, which is a different sentence and a different fix.
  if (!input.hasTenantCapability) return StartupDestination.tenantNoAccess;

  return StartupDestination.tenantSurface;
}

/// Point 17A — where a pre-session identity belongs, or `null` when there is
/// none. Pure, like everything in this file; the order is documented on
/// [resolveStartup].
StartupDestination? _entryDestination(AuthEntryState entry) {
  switch (entry) {
    case EntryNone():
      return null;
    case EntryRestoring():
      return StartupDestination.restoring;
    case EntryInvalid():
      return StartupDestination.invalidSession;
    case EntryVerificationPending():
      return StartupDestination.emailVerification;
    case EntryOnboarding(:final snapshot):
      return onboardingDestination(snapshot);
  }
}

/// The onboarding sub-classifier — exposed so its table is testable on its
/// own. Every answer is a pre-surface screen: nothing here can return
/// [StartupDestination.tenantSurface], [StartupDestination.platformSurface]
/// or a demo destination, because an onboarding session is not a product
/// session.
StartupDestination onboardingDestination(OnboardingSnapshot snapshot) {
  if (snapshot.hasUnsupportedState) {
    return StartupDestination.unsupportedAccessState;
  }
  switch (snapshot.account) {
    case AccountStatus.revoked:
      return StartupDestination.accountRevoked;
    case AccountStatus.suspended:
      return StartupDestination.accountSuspended;
    case AccountStatus.pendingSetup:
    case AccountStatus.active:
      break;
  }
  final tenant = snapshot.tenant;
  if (snapshot.link != TenantLinkStatus.linked || tenant == null) {
    return StartupDestination.teamLink;
  }
  switch (tenant.status) {
    case SaasTenantStatus.deleted:
      return StartupDestination.tenantDeleted;
    case SaasTenantStatus.deletionPending:
      return StartupDestination.tenantDeletionPending;
    case SaasTenantStatus.suspended:
      return StartupDestination.tenantSuspended;
    case SaasTenantStatus.active:
      break;
  }
  // Setup incomplete → finish it. Setup complete → the server owes a full
  // session; the setup screen owns that exchange and its retry, so the app is
  // never parked on a spinner waiting for it.
  return StartupDestination.firstTimeSetup;
}
