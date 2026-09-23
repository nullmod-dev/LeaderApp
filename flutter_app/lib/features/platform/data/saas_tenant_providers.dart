import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../domain/saas_tenant_models.dart';
import '../domain/saas_tenant_repository.dart';
import '../domain/saas_tenant_validation.dart';
import '../domain/tenant_lifecycle_models.dart';
import '../domain/team_code.dart';
import 'mock_saas_tenant_repository.dart';
import 'platform_tenant_store.dart';
import 'platform_overview_providers.dart';

/// The subscriber records, shared with the Point 5 overview.
///
/// **Not `autoDispose`.** It is the mock's whole state: a tenant registered on
/// the create screen must still be there when the operator returns to the
/// list, and an `autoDispose` store would forget it the moment the last screen
/// watching it left the tree. A real repository makes this provider a thin
/// client and the question disappears.
final platformTenantStoreProvider = Provider<PlatformTenantStore>((ref) {
  return PlatformTenantStore(clock: ref.watch(clockProvider));
});

final saasTenantRepositoryProvider = Provider<SaasTenantRepository>((ref) {
  return MockSaasTenantRepository(
      store: ref.watch(platformTenantStoreProvider));
});

/// One page of subscribers for one query.
///
/// A family keyed by the query itself, which is why [SaasTenantQuery] has
/// value equality: the list screen rebuilds on every keystroke, and without it
/// each rebuild would be a new provider and a new request for a query that had
/// not changed.
final saasTenantListProvider = FutureProvider.autoDispose
    .family<Result<SaasTenantPage>, SaasTenantQuery>((ref, query) {
  return ref.watch(saasTenantRepositoryProvider).list(query);
});

/// One subscriber, re-read when its screen is opened.
final saasTenantDetailProvider = FutureProvider.autoDispose
    .family<Result<SaasTenant>, String>((ref, tenantId) {
  return ref.watch(saasTenantRepositoryProvider).byId(tenantId);
});

/// The minimal deleted-resource projection retained by the Point 9 mock.
///
/// This is deliberately not folded into [saasTenantDetailProvider]: a
/// tombstone is not a `SaasTenant`, and treating it as one would make it far
/// too easy for full-resource fields to leak onto the deleted presentation.
final deletedTenantTombstoneProvider = Provider.autoDispose
    .family<DeletedTenantTombstone?, String>((ref, tenantId) {
  return ref.watch(platformTenantStoreProvider).tombstoneById(tenantId);
});

/// One subscriber's lifecycle history.
///
/// A second read rather than a field on the record, because history grows
/// without bound while the record does not — the shape a backend will want
/// even though the mock could have inlined it.
final saasTenantHistoryProvider = FutureProvider.autoDispose
    .family<Result<List<SaasTenantEvent>>, String>((ref, tenantId) {
  return ref.watch(saasTenantRepositoryProvider).statusHistory(tenantId);
});

/// A Team Code suggestion for the create form.
///
/// Deterministic from a seed the form supplies, so the screenshot in a test is
/// the same one a reviewer sees. It is a *suggestion*: the operator may accept
/// it or type their own, the repository is still the authority on uniqueness,
/// and the real code is generated server-side (`API_CONTRACT.md`).
String suggestTeamCode(int seed) => teamCodeFromSeed(seed);

// ---------------------------------------------------------------------------
// Creating a subscriber
// ---------------------------------------------------------------------------

/// What a create attempt did.
///
/// A value rather than a sentence: the test asserts on the outcome and the
/// widget resolves the Arabic from `strings.dart`.
sealed class SaasTenantCreateOutcome {
  const SaasTenantCreateOutcome();
}

/// Registered. Carries the stored record so the caller can open it.
class SaasTenantCreated extends SaasTenantCreateOutcome {
  const SaasTenantCreated(this.tenant);
  final SaasTenant tenant;
}

/// Refused by the shared validator before anything was sent, with the errors
/// keyed by field name so the form can put each one under its own input.
class SaasTenantCreateInvalid extends SaasTenantCreateOutcome {
  const SaasTenantCreateInvalid(this.fieldErrors);
  final Map<String, SaasTenantFieldError> fieldErrors;
}

/// The Team Code belongs to another subscriber. A field error in effect, and
/// separate because only the repository can reach this verdict.
class SaasTenantCodeTaken extends SaasTenantCreateOutcome {
  const SaasTenantCodeTaken();
}

/// The repository answered with a failure. The form keeps everything typed.
class SaasTenantCreateFailed extends SaasTenantCreateOutcome {
  const SaasTenantCreateFailed(this.message, {this.code});
  final String message;
  final String? code;
}

/// No connectivity. Registering a subscriber is **not** queued — see
/// [MockSaasTenantRepository.create].
class SaasTenantCreateOffline extends SaasTenantCreateOutcome {
  const SaasTenantCreateOffline();
}

/// A second submit arrived while the first was in flight and was dropped.
class SaasTenantCreateIgnored extends SaasTenantCreateOutcome {
  const SaasTenantCreateIgnored();
}

/// Registers subscribers, with the duplicate-submit guard and the invalidation
/// that keeps the list and the overview in step.
///
/// The guard lives here rather than in the form's `setState` because it has to
/// survive the widget: a form rebuilt mid-request — by a theme change, by a
/// rotation — must not become a second way to create the same customer.
class SaasTenantCreateController extends Notifier<bool> {
  /// True while a registration is in flight.
  @override
  bool build() => false;

  Future<SaasTenantCreateOutcome> create(SaasTenantDraft draft) async {
    if (state) return const SaasTenantCreateIgnored();

    final normalized = draft.normalized;
    final invalid = validateDraft(normalized);
    if (invalid.isNotEmpty) return SaasTenantCreateInvalid(invalid);

    state = true;
    try {
      final result =
          await ref.read(saasTenantRepositoryProvider).create(normalized);
      return result.when<SaasTenantCreateOutcome>(
        success: (tenant, {stale = false}) {
          // The two reads that are now wrong, invalidated explicitly. No event
          // bus: the store already holds one truth, and this is the app's
          // existing way of saying that a read of it is stale.
          //
          // `saasTenantListProvider` is a family and every live query is
          // invalidated, because a new subscriber may or may not match any of
          // them and deciding which would be guessing.
          ref.invalidate(saasTenantListProvider);
          ref.invalidate(platformOverviewProvider);
          return SaasTenantCreated(tenant);
        },
        failure: (message, code) => SaasTenantProblemCode.parse(code) ==
                SaasTenantProblemCode.teamCodeConflict
            ? const SaasTenantCodeTaken()
            : SaasTenantCreateFailed(message, code: code),
        offline: (_) => const SaasTenantCreateOffline(),
      );
    } finally {
      state = false;
    }
  }
}

final saasTenantCreateControllerProvider =
    NotifierProvider<SaasTenantCreateController, bool>(
  SaasTenantCreateController.new,
);
