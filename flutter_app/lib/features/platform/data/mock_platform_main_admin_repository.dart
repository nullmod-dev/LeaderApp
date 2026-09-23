import '../../../core/problem/problem.dart';
import '../../../core/result/result.dart';
import '../../../l10n/strings.dart';
import '../domain/platform_main_admin_models.dart';
import '../domain/platform_main_admin_repository.dart';
import '../domain/saas_tenant_models.dart';
import 'platform_main_admin_fixtures.dart';
import 'platform_tenant_store.dart';

enum MockMainAdminMode {
  loaded,
  stale,
  offline,
  failure,
  notPermitted,
  recentAuthRequired,

  /// Reads return a seat whose account status this build does not know.
  unsupportedState,
}

/// Process-memory stand-in for the backend's Main Admin account service.
///
/// Reads tenant identity and lifecycle from the canonical
/// [PlatformTenantStore] on every call and never writes lifecycle,
/// subscription, features, limits or history. The only store write is the
/// Main Admin **contact summary** after the seat moves to a new account or
/// setup completes ([PlatformTenantStore.updateMainAdminContact]). Appends
/// nothing to Platform Audit, touches no session, queues nothing, and holds
/// no credential of any kind.
class MockPlatformMainAdminRepository implements PlatformMainAdminRepository {
  MockPlatformMainAdminRepository({
    required this.store,
    required this.clock,
    required this.permitted,
    this.mode = MockMainAdminMode.loaded,
    this.latency = const Duration(milliseconds: 280),
    this.setupValidity = kProvisionalMainAdminSetupValidity,
    this.scenarios = true,
  });

  final PlatformTenantStore store;
  final DateTime Function() clock;

  /// Whether the calling session is a `super_admin`, asked on every call. The
  /// backend decides this from its own session; the mock is told.
  final bool Function() permitted;
  final MockMainAdminMode mode;
  final Duration latency;
  final Duration? setupValidity;

  /// Seed the representative fixture scenarios ([MainAdminFixtures]).
  final bool scenarios;

  final Map<String, MainAdminSeatState> _seats = {};
  final Map<String, MainAdminAccountSnapshot> _lastRead = {};
  final Map<String, _CachedMutation> _idempotency = {};
  int _issued = 0;

  DateTime get _now => clock().toUtc();

  Future<void> _wait() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }

  @override
  Future<Result<MainAdminAccountSnapshot>> load(String tenantId) async {
    await _wait();
    if (!permitted() || mode == MockMainAdminMode.notPermitted) {
      return _failure(MainAdminProblemCode.notPermitted);
    }
    if (mode == MockMainAdminMode.offline) {
      return Offline(cached: _lastRead[tenantId]);
    }
    if (mode == MockMainAdminMode.failure) return _serverFailure();

    final tenant = store.byId(tenantId);
    if (tenant == null) return _missing(tenantId);
    var snapshot = _snapshot(tenant);
    if (mode == MockMainAdminMode.unsupportedState) {
      final current = snapshot.current;
      snapshot = snapshot.copyWith(
        current: MainAdminAccount(
          accountId: current.accountId,
          displayName: current.displayName,
          loginEmail: current.loginEmail,
          status: MainAdminAccountStatus.unknown,
          createdAt: current.createdAt,
        ),
      );
    }
    _lastRead[tenantId] = snapshot;
    return Success(snapshot, stale: mode == MockMainAdminMode.stale);
  }

  @override
  Future<Result<MainAdminMutationResult>> resendSetup(
    ResendMainAdminSetupCommand command,
  ) =>
      _mutate(
        command,
        [command.target.wire],
        (snapshot) => switch (command.target) {
          MainAdminSetupTarget.current => MainAdminPolicy.resendSetup(
              snapshot: snapshot,
              now: _now,
              validity: setupValidity,
            ),
          MainAdminSetupTarget.replacement =>
            MainAdminPolicy.resendReplacementSetup(
              snapshot: snapshot,
              now: _now,
              validity: setupValidity,
            ),
        },
      );

  @override
  Future<Result<MainAdminMutationResult>> suspend(
    SuspendMainAdminCommand command,
  ) =>
      _mutate(
        command,
        [normalizeMainAdminReason(command.reason)],
        (snapshot) => MainAdminPolicy.suspend(
          snapshot: snapshot,
          reason: command.reason,
          now: _now,
        ),
      );

  @override
  Future<Result<MainAdminMutationResult>> reactivate(
    ReactivateMainAdminCommand command,
  ) =>
      _mutate(
        command,
        const [],
        (snapshot) => MainAdminPolicy.reactivate(snapshot: snapshot, now: _now),
      );

  @override
  Future<Result<MainAdminMutationResult>> replace(
    ReplaceMainAdminCommand command,
  ) {
    final identity = command.designate.normalized;
    return _mutate(
      command,
      [
        identity.displayName,
        identity.loginEmail,
        normalizeMainAdminReason(command.reason),
      ],
      precheck: (snapshot) => identity.isWellFormed &&
              identity.loginEmail != snapshot.current.loginEmail &&
              _emailTaken(identity.loginEmail)
          ? MainAdminProblemCode.identityUnavailable
          : null,
      (snapshot) {
        final serial = ++_issued;
        return MainAdminPolicy.replace(
          snapshot: snapshot,
          designate: identity,
          reason: command.reason,
          designateAccountId: 'ma_new_$serial',
          replacementId: 'mar_new_$serial',
          now: _now,
          validity: setupValidity,
        );
      },
    );
  }

  @override
  Future<Result<MainAdminMutationResult>> cancelReplacement(
    CancelMainAdminReplacementCommand command,
  ) =>
      _mutate(
        command,
        [command.replacementId],
        precheck: (snapshot) =>
            snapshot.replacement?.id == command.replacementId
                ? null
                : MainAdminProblemCode.invalidTransition,
        (snapshot) =>
            MainAdminPolicy.cancelReplacement(snapshot: snapshot, now: _now),
      );

  /// **Mock-only stand-in for a Point 17 backend event**: the designate
  /// completed first-time setup, so the seat transfers. Not on the repository
  /// interface — no Super Admin command can cause it.
  MainAdminTransitionDecision simulateReplacementSetupCompleted(
    String tenantId,
  ) =>
      _backendEvent(
        tenantId,
        (snapshot) =>
            MainAdminPolicy.completeReplacement(snapshot: snapshot, now: _now),
      );

  /// **Mock-only stand-in for a Point 17 backend event**: the current
  /// `pending_setup` account completed first-time setup.
  MainAdminTransitionDecision simulateSetupCompleted(String tenantId) =>
      _backendEvent(
        tenantId,
        (snapshot) =>
            MainAdminPolicy.completeSetup(snapshot: snapshot, now: _now),
      );

  // -------------------------------------------------------------------------

  Future<Result<MainAdminMutationResult>> _mutate(
    MainAdminCommand command,
    List<Object?> payload,
    MainAdminTransitionDecision Function(MainAdminAccountSnapshot) decide, {
    MainAdminProblemCode? Function(MainAdminAccountSnapshot)? precheck,
  }) async {
    await _wait();
    if (!permitted() || mode == MockMainAdminMode.notPermitted) {
      return _failure(MainAdminProblemCode.notPermitted);
    }
    if (mode == MockMainAdminMode.offline) return const Offline();
    if (mode == MockMainAdminMode.failure) return _serverFailure();
    if (mode == MockMainAdminMode.recentAuthRequired) {
      return _failure(MainAdminProblemCode.recentAuthenticationRequired);
    }
    if (command.tenantId.trim().isEmpty ||
        command.expectedRevision < 1 ||
        command.idempotencyKey.trim().isEmpty) {
      return _validationFailure();
    }

    final fingerprint = [
      command.action.wire,
      command.tenantId,
      command.expectedRevision,
      ...payload,
    ].join('|');
    final cached = _idempotency[command.idempotencyKey];
    if (cached != null) {
      return cached.fingerprint == fingerprint
          ? Success(cached.result.asIdempotentReplay())
          : _failure(MainAdminProblemCode.idempotencyConflict);
    }

    final tenant = store.byId(command.tenantId);
    if (tenant == null) return _missing(command.tenantId);
    final snapshot = _snapshot(tenant);
    if (snapshot.revision != command.expectedRevision) {
      return _failure(MainAdminProblemCode.staleMainAdmin);
    }
    final pre = precheck?.call(snapshot);
    if (pre != null) return _failure(pre);

    final decision = decide(snapshot);
    switch (decision) {
      case MainAdminTransitionRefused(:final problem):
        return _failure(_codeFor(problem));
      case MainAdminTransitionAllowed(:final snapshot, :final effect):
        _commit(snapshot, effect);
        final result = MainAdminMutationResult(
          snapshot: snapshot,
          effect: effect,
          changed: true,
        );
        _idempotency[command.idempotencyKey] =
            _CachedMutation(fingerprint: fingerprint, result: result);
        return Success(result);
    }
  }

  MainAdminTransitionDecision _backendEvent(
    String tenantId,
    MainAdminTransitionDecision Function(MainAdminAccountSnapshot) decide,
  ) {
    final tenant = store.byId(tenantId);
    if (tenant == null) {
      return const MainAdminTransitionRefused(
        MainAdminTransitionProblem.tenantDeleted,
      );
    }
    final decision = decide(_snapshot(tenant));
    if (decision
        case MainAdminTransitionAllowed(:final snapshot, :final effect)) {
      _commit(snapshot, effect);
    }
    return decision;
  }

  void _commit(
      MainAdminAccountSnapshot snapshot, MainAdminMutationEffect effect) {
    final tenantId = snapshot.tenant.tenantId;
    _seats[tenantId] = MainAdminSeatState(
      revision: snapshot.revision,
      current: snapshot.current,
      replacement: snapshot.replacement,
    );
    if (effect == MainAdminMutationEffect.replaced ||
        effect == MainAdminMutationEffect.setupCompleted) {
      final current = snapshot.current;
      store.updateMainAdminContact(
        tenantId,
        MainAdminContact(
          name: current.displayName,
          email: current.loginEmail,
          provisioning: current.status == MainAdminAccountStatus.pendingSetup
              ? MainAdminProvisioning.pendingSetup
              : MainAdminProvisioning.active,
        ),
      );
    }
  }

  MainAdminAccountSnapshot _snapshot(SaasTenant tenant) {
    final seat = _seats.putIfAbsent(
      tenant.id,
      () => MainAdminFixtures.derive(
        tenant,
        now: _now,
        validity: setupValidity,
        scenarios: scenarios,
      ),
    );
    return MainAdminAccountSnapshot(
      tenant: MainAdminTenantReference(
        tenantId: tenant.id,
        displayName: tenant.displayName,
        lifecycleStatus: tenant.tenantStatus,
        lifecycleVersion: tenant.tenantVersion,
      ),
      revision: seat.revision,
      current: seat.current,
      replacement: seat.replacement,
      readAt: _now,
    );
  }

  /// Whether [email] already identifies any seat holder or designate on the
  /// platform. A backend checks every MTM account; the mock checks what it
  /// can see.
  bool _emailTaken(String email) {
    for (final tenant in store.tenants) {
      if (normalizeMainAdminEmail(tenant.mainAdmin.email) == email) return true;
      _snapshot(tenant); // materializes seeded designates before comparing
    }
    for (final seat in _seats.values) {
      if (seat.current.loginEmail == email) return true;
      if (seat.replacement?.designate.loginEmail == email) return true;
    }
    return false;
  }

  Failure<T> _missing<T>(String tenantId) => _failure(
        store.tombstoneById(tenantId) != null
            ? MainAdminProblemCode.tenantAlreadyDeleted
            : MainAdminProblemCode.tenantNotFound,
      );

  static MainAdminProblemCode _codeFor(MainAdminTransitionProblem problem) =>
      switch (problem) {
        MainAdminTransitionProblem.tenantNotEligible =>
          MainAdminProblemCode.tenantNotEligible,
        MainAdminTransitionProblem.tenantDeleted =>
          MainAdminProblemCode.tenantAlreadyDeleted,
        MainAdminTransitionProblem.invalidTransition ||
        MainAdminTransitionProblem.unsupportedState =>
          MainAdminProblemCode.invalidTransition,
        MainAdminTransitionProblem.invalidReason =>
          MainAdminProblemCode.invalidReason,
        MainAdminTransitionProblem.invalidIdentity =>
          MainAdminProblemCode.invalidIdentity,
        MainAdminTransitionProblem.replacementAlreadyPending =>
          MainAdminProblemCode.replacementAlreadyPending,
      };

  static Failure<T> _failure<T>(MainAdminProblemCode code) =>
      Failure(_messages[code]!, code: code.wire);

  static Failure<T> _validationFailure<T>() => Failure(
        'طلب إدارة حساب المدير الرئيسي غير صالح.',
        code: ProblemCode.validation.wire,
      );

  static Failure<T> _serverFailure<T>() => Failure(
        'تعذّر إتمام العملية بأمان.',
        code: ProblemCode.server.wire,
      );

  static const _messages = {
    MainAdminProblemCode.tenantNotFound: 'الفريق غير موجود.',
    MainAdminProblemCode.tenantNotEligible:
        'لا يسمح وضع الفريق الحالي بهذا الإجراء.',
    MainAdminProblemCode.tenantAlreadyDeleted: 'اكتمل حذف الفريق.',
    MainAdminProblemCode.invalidTransition:
        'لا تسمح حالة الحساب الحالية بهذا الإجراء.',
    MainAdminProblemCode.invalidReason: 'أدخل سببًا إداريًا موجزًا وصالحًا.',
    MainAdminProblemCode.invalidIdentity:
        'تحقق من اسم المدير الجديد وبريده الإلكتروني.',
    MainAdminProblemCode.identityUnavailable:
        'هذا البريد الإلكتروني مرتبط بحساب آخر في ${S.productNameAr}.',
    MainAdminProblemCode.replacementAlreadyPending:
        'يوجد استبدال قيد الانتظار لهذا الفريق.',
    MainAdminProblemCode.setupResendThrottled:
        'أُرسلت دعوة مؤخرًا. أعد المحاولة لاحقًا.',
    MainAdminProblemCode.staleMainAdmin:
        'تغيّرت حالة الحساب. حدّث الصفحة ثم أعد المحاولة.',
    MainAdminProblemCode.idempotencyConflict:
        'أُعيد استخدام معرّف العملية لطلب مختلف.',
    MainAdminProblemCode.recentAuthenticationRequired:
        'يتطلب هذا الإجراء تسجيل دخول حديثًا.',
    MainAdminProblemCode.notPermitted:
        'لا تملك الجلسة صلاحية تنفيذ هذا الإجراء.',
  };
}

class _CachedMutation {
  const _CachedMutation({required this.fingerprint, required this.result});

  final String fingerprint;
  final MainAdminMutationResult result;
}
