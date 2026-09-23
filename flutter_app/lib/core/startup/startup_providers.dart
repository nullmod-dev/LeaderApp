import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/app_version/data/app_version_providers.dart';
import '../../features/auth/data/auth_providers.dart';
import '../../features/auth/data/onboarding_controller.dart';
import '../../features/platform/data/tenant_lifecycle_providers.dart';
import '../access/capability_guard.dart';
import '../time/clock.dart';
import 'intro_gate.dart';
import 'startup_destination.dart';

/// The app's startup decision, as a provider.
///
/// The only thing this adds to [resolveStartup] is *where the inputs come
/// from*. Keeping that split is the point: the table of outcomes is a pure
/// function a test calls directly, and this is the twelve lines that read
/// four providers. Nothing may add a rule here — a new rule belongs in
/// `startup_destination.dart` where the priority is written down.
///
/// Watched by the router (through its `refreshListenable`), so every input
/// below is also a reason the router re-decides: the upgrade gate flipping,
/// the session read landing, a different account signing in, a grant
/// narrowing, or a lifecycle state arriving.
final startupDestinationProvider = Provider<StartupDestination>((ref) {
  return resolveStartup(StartupInputs(
    now: ref.watch(clockProvider)(),
    // The cold-launch brand hold. `IntroPhase.idle` in every process that did
    // not arm it, so this reads `false` for every test and harness.
    introHolding: ref.watch(introGateProvider) == IntroPhase.holding,
    upgradeBlocks: ref.watch(appVersionProvider).blocksApp,
    gate: ref.watch(authGateProvider),
    // The accepted account — `currentUserProvider` has already refused a
    // malformed payload, and `AuthGate.invalid` is what carries that refusal
    // into the decision.
    user: ref.watch(currentUserProvider).valueOrNull,
    access: ref.watch(effectiveSessionAccessProvider),
    hasTenantCapability: ref.watch(capabilitiesProvider).hasAny,
    // Point 17A — the pre-session journey; `EntryNone` until 17B wires the
    // controller's restore into startup.
    entry: ref.watch(authEntryStateProvider),
  ));
});
