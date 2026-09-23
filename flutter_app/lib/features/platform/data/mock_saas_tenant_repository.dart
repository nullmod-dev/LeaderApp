import '../../../core/problem/problem.dart';
import '../../../core/result/result.dart';
import '../../../l10n/strings.dart';
import '../domain/saas_tenant_models.dart';
import '../domain/saas_tenant_repository.dart';
import '../domain/saas_tenant_validation.dart';
import 'platform_tenant_store.dart';

/// Which state the mock answers in.
///
/// One switch for reads *and* the write, because that is how the real
/// condition behaves: a device with no connectivity cannot list subscribers
/// and cannot register one either, and a mock that let the create succeed
/// while the list was offline would be modelling something that cannot happen.
enum MockSaasTenantMode {
  loaded,

  /// The platform genuinely has no subscribers yet. Distinct from "the search
  /// matched nothing", which the loaded mode produces on its own.
  empty,

  /// No connectivity, with the process-memory copy to show. **Not a durable
  /// cache claim** — see [PlatformTenantStore].
  offlineWithCache,

  /// No connectivity and nothing to show.
  offlineWithoutCache,

  failure,
}

/// The frontend's stand-in for the platform subscriber service.
///
/// Reads and writes [PlatformTenantStore], which it does **not** own: the
/// store is injected so the Point 5 overview counts the same records this
/// repository lists. Every timestamp comes from the store's injected clock.
///
/// Lifecycle writes are intentionally absent here: Point 9 routes them
/// through the dedicated repository over the same [PlatformTenantStore].
class MockSaasTenantRepository implements SaasTenantRepository {
  MockSaasTenantRepository({
    required this.store,
    this.mode = MockSaasTenantMode.loaded,
    this.latency = const Duration(milliseconds: 340),
  });

  final PlatformTenantStore store;
  final MockSaasTenantMode mode;
  final Duration latency;

  Future<void> _wait() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }

  @override
  Future<Result<SaasTenantPage>> list(SaasTenantQuery query) async {
    await _wait();
    return switch (mode) {
      MockSaasTenantMode.loaded => Success(store.page(query)),
      MockSaasTenantMode.empty => Success(SaasTenantPage(
          items: const [],
          total: 0,
        )),
      MockSaasTenantMode.offlineWithCache => Offline(cached: store.page(query)),
      MockSaasTenantMode.offlineWithoutCache => const Offline(),
      MockSaasTenantMode.failure =>
        Failure(S.platformTenantsLoadFailed, code: ProblemCode.server.wire),
    };
  }

  @override
  Future<Result<SaasTenant>> byId(String tenantId) async {
    await _wait();
    final tenant = store.byId(tenantId);
    return switch (mode) {
      MockSaasTenantMode.loaded ||
      MockSaasTenantMode.empty =>
        tenant == null ? _notFound<SaasTenant>() : Success(tenant),
      // A record that was never cached is not "offline with a copy" — the
      // screen must be able to tell those two apart.
      MockSaasTenantMode.offlineWithCache => Offline(cached: tenant),
      MockSaasTenantMode.offlineWithoutCache => const Offline(),
      MockSaasTenantMode.failure =>
        Failure(S.platformTenantsLoadFailed, code: ProblemCode.server.wire),
    };
  }

  @override
  Future<Result<List<SaasTenantEvent>>> statusHistory(String tenantId) async {
    await _wait();
    final tenant = store.byId(tenantId);
    return switch (mode) {
      MockSaasTenantMode.loaded || MockSaasTenantMode.empty => tenant == null
          ? _notFound<List<SaasTenantEvent>>()
          : Success(store.historyOf(tenant)),
      MockSaasTenantMode.offlineWithCache => Offline(
          cached: tenant == null ? null : store.historyOf(tenant),
        ),
      MockSaasTenantMode.offlineWithoutCache => const Offline(),
      MockSaasTenantMode.failure => Failure(
          S.platformTenantsLoadFailed,
          code: ProblemCode.server.wire,
        ),
    };
  }

  @override
  Future<Result<SaasTenant>> create(SaasTenantDraft draft) async {
    // Normalized before anything is judged, so the uniqueness check and the
    // stored record see the same string the operator would read back.
    final normalized = draft.normalized;

    // Validated here as well as in the form. The form's copy is a courtesy to
    // the person typing; this is the gate, and it is what a direct call hits.
    final invalid = validateDraft(normalized);
    if (invalid.isNotEmpty) {
      return Failure(
        S.platformTenantCreateInvalid,
        code: ProblemCode.validation.wire,
      );
    }

    await _wait();

    if (mode == MockSaasTenantMode.offlineWithCache ||
        mode == MockSaasTenantMode.offlineWithoutCache) {
      // **Not queued.** The sync outbox exists and would have accepted a
      // pending operation, and that is exactly why it is refused: there is no
      // platform endpoint for a queued registration to reach, so an operation
      // enqueued now would sit there while the operator believed a customer
      // had been created. The honest answer is that this cannot be done
      // offline.
      return const Offline();
    }
    if (mode == MockSaasTenantMode.failure) {
      return Failure(
        S.platformTenantCreateFailed,
        code: ProblemCode.server.wire,
      );
    }

    if (store.isTeamCodeTaken(normalized.teamCode)) {
      return Failure(
        S.platformTenantCodeTaken,
        code: SaasTenantProblemCode.teamCodeConflict.wire,
      );
    }

    return Success(store.create(normalized));
  }

  Failure<T> _notFound<T>() => Failure<T>(
        S.platformTenantNotFoundBody,
        code: ProblemCode.notFound.wire,
      );
}
