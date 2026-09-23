import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/session_revoke_controller.dart';
import 'package:mtm/features/auth/data/sign_out_controller.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/auth_repository.dart';

/// Ending a session is the one destructive action on the Security screen, and
/// everything that can go wrong with it is invisible on screen: a second tap
/// sending a second request, a list that drops a row the server never
/// removed, a `401` that leaves the app looking signed in. Those are what
/// these test — at the controller, where the rules actually live.
void main() {
  test('a confirmed revoke re-reads the session list', () async {
    final repo = _FakeAuthRepo();
    final container = _container(repo);
    await _readSessions(container);
    expect(repo.listCalls, 1);

    final outcome =
        await container.read(sessionRevokeControllerProvider.notifier).revoke(
              's_2',
            );

    expect(outcome, SessionRevokeOutcome.revoked);
    expect(repo.revokeCalls, ['s_2']);
    await _readSessions(container);
    expect(repo.listCalls, 2, reason: 'the list is re-read after a success');
  });

  test('a failed revoke leaves the session where it was', () async {
    final repo = _FakeAuthRepo(revokeAnswer: const Failure('boom'));
    final container = _container(repo);
    await _readSessions(container);

    final outcome =
        await container.read(sessionRevokeControllerProvider.notifier).revoke(
              's_2',
            );

    expect(outcome, SessionRevokeOutcome.failed);
    // Not re-read: the row on screen is still the truth, and quietly
    // dropping it would tell the admin a device was locked out when it was
    // not.
    await _readSessions(container);
    expect(repo.listCalls, 1);
  });

  test('a second tap on the same session sends only one request', () async {
    final repo = _FakeAuthRepo();
    final container = _container(repo);
    final notifier = container.read(sessionRevokeControllerProvider.notifier);

    // Both started before either can finish — the shape of a double tap.
    final first = notifier.revoke('s_2');
    final second = notifier.revoke('s_2');

    expect(await second, isNull, reason: 'the duplicate is dropped');
    expect(await first, SessionRevokeOutcome.revoked);
    expect(repo.revokeCalls, ['s_2']);
  });

  test(
      'a session already revoked elsewhere is reported, not treated as an '
      'error, and the list is refreshed', () async {
    final repo = _FakeAuthRepo(
      revokeAnswer: const Failure('gone', code: 'not_found'),
    );
    final container = _container(repo);
    await _readSessions(container);

    final outcome =
        await container.read(sessionRevokeControllerProvider.notifier).revoke(
              's_2',
            );

    expect(outcome, SessionRevokeOutcome.alreadyGone);
    await _readSessions(container);
    expect(repo.listCalls, 2, reason: 'the stale row has to go');
  });

  test('a refused revoke changes nothing', () async {
    final repo = _FakeAuthRepo(
      revokeAnswer: const Failure('no', code: 'not_permitted'),
    );
    final container = _container(repo);
    await _readSessions(container);

    expect(
      await container.read(sessionRevokeControllerProvider.notifier).revoke(
            's_2',
          ),
      SessionRevokeOutcome.notPermitted,
    );
    await _readSessions(container);
    expect(repo.listCalls, 1);
  });

  test('offline is answered honestly and queues nothing', () async {
    final repo = _FakeAuthRepo(revokeAnswer: const Offline());
    final container = _container(repo);
    await _readSessions(container);

    expect(
      await container.read(sessionRevokeControllerProvider.notifier).revoke(
            's_2',
          ),
      SessionRevokeOutcome.offline,
    );
    // One attempt, made and failed. Nothing retried, nothing deferred: a
    // session revocation is not an outbox operation.
    expect(repo.revokeCalls, ['s_2']);
    await _readSessions(container);
    expect(repo.listCalls, 1);
  });

  test('a revoke rejected as expired closes the authenticated app', () async {
    final repo = _FakeAuthRepo(
      revokeAnswer: const Failure('nope', code: 'authentication_expired'),
    );
    final container = _container(repo);
    // A live gate, as the router holds it.
    container.listen(authGateProvider, (_, __) {});
    await _readSessions(container);
    await container.read(currentUserResultProvider.future);
    expect(container.read(authGateProvider), AuthGate.signedIn);
    expect(repo.meCalls, 1);

    // From here on the server rejects this session for everything.
    repo.meAnswer = const Failure<AuthUser?>(
      'expired',
      code: 'authentication_expired',
    );

    final outcome =
        await container.read(sessionRevokeControllerProvider.notifier).revoke(
              's_2',
            );
    expect(outcome, SessionRevokeOutcome.sessionExpired);

    // The account read was invalidated by the controller — that, and only
    // that, is what moves the router's gate.
    await container.read(currentUserResultProvider.future);
    expect(repo.meCalls, greaterThan(1));
    expect(container.read(authGateProvider), AuthGate.expired,
        reason: 'the app must not keep looking authenticated');
  });

  group('sign-out', () {
    test('a second tap sends only one request', () async {
      final repo = _FakeAuthRepo();
      final container = _container(repo);
      final notifier = container.read(signOutControllerProvider.notifier);

      final first = notifier.signOut();
      final second = notifier.signOut();

      expect(await second, isNull);
      expect((await first)?.isSuccess, isTrue);
      expect(repo.signOutCalls, 1);
    });

    test('a sign-out the server rejects as expired still clears the session',
        () async {
      // The token this request carried is already gone server-side. Reporting
      // "could not sign out" and leaving the app authenticated is the one
      // outcome that must not happen.
      final repo = _FakeAuthRepo(
        signOutAnswer: const Failure<void>(
          'expired',
          code: 'authentication_expired',
        ),
      );
      final container = _container(repo);
      container.listen(authGateProvider, (_, __) {});
      await container.read(currentUserResultProvider.future);
      expect(container.read(authGateProvider), AuthGate.signedIn);

      // The session is gone server-side, so the next account read says so.
      repo.meAnswer = const Success<AuthUser?>(null);
      final result =
          await container.read(signOutControllerProvider.notifier).signOut();
      expect(result?.isFailure, isTrue);

      await container.read(currentUserResultProvider.future);
      expect(repo.meCalls, greaterThan(1),
          reason: 'the session read must be cleared, not left cached');
      expect(container.read(authGateProvider), AuthGate.signedOut);
    });

    test('a sign-out that fails for any other reason keeps the session',
        () async {
      final repo = _FakeAuthRepo(signOutAnswer: const Failure<void>('boom'));
      final container = _container(repo);
      container.listen(authGateProvider, (_, __) {});
      await container.read(currentUserResultProvider.future);
      final before = repo.meCalls;

      final result =
          await container.read(signOutControllerProvider.notifier).signOut();

      expect(result?.isFailure, isTrue);
      expect(repo.meCalls, before, reason: 'the session was not re-read');
      expect(container.read(authGateProvider), AuthGate.signedIn,
          reason: 'nothing was signed out, so nothing may be cleared');
    });
  });
}

ProviderContainer _container(AuthRepository repo) {
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

/// Reads the session list and keeps it subscribed, so an invalidation from
/// the controller actually causes a re-fetch rather than being dropped on the
/// floor by an unwatched provider.
Future<void> _readSessions(ProviderContainer container) async {
  container.listen(sessionsProvider, (_, __) {});
  await container.read(sessionsProvider.future);
}

const _me = AuthUser(
  id: 'u_1',
  name: 'مشرف',
  email: 'admin@mtm.org',
  role: AuthRole.mainAdmin,
  saasTenantId: 'saas_test',
  capabilities: Capabilities(global: {Cap.orgEdit}),
  orgName: 'MTM',
);

final _sessions = <Session>[
  Session(
    id: 's_cur',
    device: 'هاتف المشرف',
    ipMasked: '176.29.xx.xx',
    locationLabel: 'دمشق, سوريا',
    startedAt: DateTime(2026, 9, 6, 8),
    current: true,
  ),
  Session(
    id: 's_2',
    device: 'حاسوب المكتب',
    ipMasked: '82.137.xx.xx',
    locationLabel: 'حمص, سوريا',
    startedAt: DateTime(2026, 9, 3, 9),
    current: false,
  ),
];

class _FakeAuthRepo implements AuthRepository {
  _FakeAuthRepo({
    this.revokeAnswer = const Success<void>(null),
    this.signOutAnswer = const Success<void>(null),
  });

  Result<void> revokeAnswer;
  Result<void> signOutAnswer;
  Result<AuthUser?> meAnswer = const Success<AuthUser?>(_me);

  int listCalls = 0;
  int signOutCalls = 0;
  int meCalls = 0;
  final List<String> revokeCalls = [];

  @override
  Future<Result<List<Session>>> listSessions() async {
    listCalls++;
    return Success(List.of(_sessions));
  }

  @override
  Future<Result<void>> revokeSession(String id) async {
    revokeCalls.add(id);
    // A turn of the event loop, so two calls started together really do
    // overlap rather than running to completion one after the other.
    await Future<void>.delayed(Duration.zero);
    return revokeAnswer;
  }

  @override
  Future<Result<void>> signOut() async {
    signOutCalls++;
    await Future<void>.delayed(Duration.zero);
    return signOutAnswer;
  }

  @override
  Future<Result<AuthUser?>> currentUser() async {
    meCalls++;
    return meAnswer;
  }

  @override
  Future<Result<MfaSetupData>> beginMfaSetup() async => const Failure('unused');

  @override
  Future<Result<void>> verifyMfa(String code) async => const Success(null);

  @override
  Future<Result<void>> requestPasswordReset(String email) async =>
      const Success(null);

  @override
  Future<Result<void>> verifyResetOtp(String email, String code) async =>
      const Success(null);

  @override
  Future<Result<void>> setNewPassword(String password) async =>
      const Success(null);

  @override
  Future<Result<void>> confirmNewDevice({required bool itsMe}) async =>
      const Success(null);

  @override
  Future<Result<AuthUser>> signIn({
    required String emailOrUsername,
    required String password,
  }) async =>
      const Success(_me);
}
