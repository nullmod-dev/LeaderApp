import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/storage/secure_store.dart';
import 'package:mtm/features/auth/data/mock_onboarding_repository.dart';
import 'package:mtm/features/auth/data/secure_auth_state_store.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/onboarding_models.dart';
import 'package:mtm/features/auth/domain/onboarding_repository.dart';
import 'package:mtm/features/auth/domain/session_access.dart';
import 'package:mtm/features/platform/data/mock_platform_main_admin_repository.dart';
import 'package:mtm/features/platform/data/platform_main_admin_fixtures.dart';
import 'package:mtm/features/platform/data/platform_tenant_store.dart';
import 'package:mtm/features/platform/domain/platform_main_admin_models.dart';
import 'package:mtm/features/platform/domain/platform_main_admin_repository.dart';

/// Point 17A — the onboarding repository's semantics, against the
/// deterministic mock that documents what the backend must do.
void main() {
  var now = DateTime.utc(2026, 9, 12, 9);
  late MockOnboardingRepository repo;
  var online = true;
  var keys = 0;
  String key() => 'k${keys++}';

  setUp(() {
    now = DateTime.utc(2026, 9, 12, 9);
    online = true;
    repo = MockOnboardingRepository(clock: () => now, online: () => online);
  });

  T ok<T>(Result<T> r) {
    expect(r, isA<Success<T>>(), reason: '$r');
    return (r as Success<T>).data;
  }

  OnboardingProblemCode? problem(Result<Object?> r) =>
      r is OnboardingFailure ? r.problem : null;

  Future<VerificationChallenge> signUp(String email,
          {String password = 'a-good-password'}) async =>
      ok(await repo.signUpWithPassword(
          email: email, password: password, idempotencyKey: key()));

  Future<OnboardingSnapshot> verified(VerificationChallenge c) async {
    final outcome = ok(await repo.verifyEmail(
        challenge: c, code: kMockVerificationCode, idempotencyKey: key()));
    return (outcome as EntryContinueOnboarding).snapshot;
  }

  Future<OnboardingSnapshot> link(String code) async =>
      ok(await repo.linkTeam(teamCode: code, idempotencyKey: key()));

  group('email/password sign-up', () {
    test('creates no session — only a challenge for the address', () async {
      final c = await signUp('New.Person@Example.org');
      expect(c.maskedEmail, 'n***@example.org');
      expect(repo.fullSessionsIssued, 0);
      expect(
          (await repo.refresh()).when(
            success: (_, {stale = false}) => 'session',
            failure: (_, code) => code,
            offline: (_) => 'offline',
          ),
          'authentication_expired');
    });

    test('an already-registered address gets the identical answer', () async {
      final fresh = await signUp('someone.new@example.org');
      final existing = await signUp(OnboardingFixtures.verifiedUnlinkedEmail);
      // Same shape, same fields, same cooldown — nothing distinguishes them.
      expect(existing.toJson().keys, fresh.toJson().keys);
      expect(existing.resendAvailableAt, fresh.resendAvailableAt);
      expect(existing.attemptsRemaining, fresh.attemptsRemaining);
      // …and the decoy can never be satisfied, even with the right code.
      final r = await repo.verifyEmail(
          challenge: existing,
          code: kMockVerificationCode,
          idempotencyKey: key());
      expect(problem(r), OnboardingProblemCode.verificationCodeInvalid);
    });

    test('an unverified credential is replaced, never trusted', () async {
      final c = await signUp(OnboardingFixtures.unverifiedEmail,
          password: 'replacement-pass');
      final s = await verified(c);
      expect(s.accountId, 'acc_unverified');
      await repo.abandon();
      expect(
          problem(await repo.signInWithPassword(
              email: OnboardingFixtures.unverifiedEmail,
              password: kMockFixturePassword)),
          OnboardingProblemCode.invalidCredentials);
    });

    test('the backend password policy is authoritative', () async {
      final r = await repo.signUpWithPassword(
          email: 'x@example.org', password: 'short', idempotencyKey: key());
      expect(problem(r), OnboardingProblemCode.passwordRejected);
    });

    test('a repeated submit replays; a changed body under one key conflicts',
        () async {
      final first = await repo.signUpWithPassword(
          email: 'dup@example.org',
          password: 'a-good-password',
          idempotencyKey: 'same');
      final again = await repo.signUpWithPassword(
          email: 'dup@example.org',
          password: 'a-good-password',
          idempotencyKey: 'same');
      expect(ok(again), ok(first));
      final accountId = repo.accountIdFor('dup@example.org');
      final changed = await repo.signUpWithPassword(
          email: 'other@example.org',
          password: 'a-good-password',
          idempotencyKey: 'same');
      expect(problem(changed), OnboardingProblemCode.idempotencyConflict);
      expect(repo.accountIdFor('dup@example.org'), accountId);
      expect(repo.accountIdFor('other@example.org'), isNull);
    });
  });

  group('email/password sign-in', () {
    test('wrong password, unknown address and Google-only look identical',
        () async {
      final results = [
        await repo.signInWithPassword(
            email: OnboardingFixtures.readyEmail, password: 'wrong-password'),
        await repo.signInWithPassword(
            email: 'nobody@example.org', password: kMockFixturePassword),
        await repo.signInWithPassword(
            email: OnboardingFixtures.googleOnlyEmail,
            password: kMockFixturePassword),
      ];
      for (final r in results) {
        expect(problem(r), OnboardingProblemCode.invalidCredentials);
        expect((r as Failure).message, (results.first as Failure).message);
      }
    });

    test('each partial state resumes at its own step', () async {
      final unverified = ok(await repo.signInWithPassword(
          email: OnboardingFixtures.unverifiedEmail,
          password: kMockFixturePassword));
      expect(unverified, isA<EntryVerificationRequired>());

      final unlinked = ok(await repo.signInWithPassword(
          email: OnboardingFixtures.verifiedUnlinkedEmail,
          password: kMockFixturePassword)) as EntryContinueOnboarding;
      expect(unlinked.snapshot.link, TenantLinkStatus.unlinked);

      final setup = ok(await repo.signInWithPassword(
          email: OnboardingFixtures.linkedSetupEmail,
          password: kMockFixturePassword)) as EntryContinueOnboarding;
      expect(setup.snapshot.link, TenantLinkStatus.linked);
      expect(setup.snapshot.setup, AccountSetupStatus.required);
    });

    test('a finished account skips every step: a full session', () async {
      final r = ok(await repo.signInWithPassword(
          email: OnboardingFixtures.readyEmail,
          password: kMockFixturePassword));
      expect(r, isA<EntryReady>());
      expect(repo.fullSessionsIssued, 1);
    });

    test('the backend throttles repeated failures (retry-after is data)',
        () async {
      for (var i = 0; i < kMockFailureBudget; i++) {
        await repo.signInWithPassword(
            email: OnboardingFixtures.readyEmail, password: 'wrong-password');
      }
      final r = await repo.signInWithPassword(
          email: OnboardingFixtures.readyEmail, password: kMockFixturePassword);
      expect(problem(r), OnboardingProblemCode.rateLimited);
      expect((r as OnboardingFailure).retryAvailableAt, now.add(kMockLockout));
      now = now.add(kMockLockout);
      expect(
          ok(await repo.signInWithPassword(
              email: OnboardingFixtures.readyEmail,
              password: kMockFixturePassword)),
          isA<EntryReady>());
    });
  });

  group('email verification', () {
    test('a wrong code narrows the attempts; exhaustion ends the challenge',
        () async {
      final c = await signUp('try@example.org');
      for (var left = kMockVerificationAttempts - 1; left > 0; left--) {
        final r = await repo.verifyEmail(
            challenge: c, code: '000000', idempotencyKey: key());
        expect(problem(r), OnboardingProblemCode.verificationCodeInvalid);
        expect((r as OnboardingFailure).attemptsRemaining, left);
      }
      final last = await repo.verifyEmail(
          challenge: c, code: '000000', idempotencyKey: key());
      expect(problem(last), OnboardingProblemCode.verificationChallengeEnded);
      final after = await repo.verifyEmail(
          challenge: c, code: kMockVerificationCode, idempotencyKey: key());
      expect(problem(after), OnboardingProblemCode.verificationChallengeEnded);
    });

    test('an expired code asks for a resend; resend honours its cooldown',
        () async {
      final c = await signUp('late@example.org');
      final early =
          await repo.resendVerification(challenge: c, idempotencyKey: key());
      expect(problem(early), OnboardingProblemCode.verificationResendThrottled);
      expect(
          (early as OnboardingFailure).retryAvailableAt, c.resendAvailableAt);

      now = now.add(kMockCodeValidity);
      final expired = await repo.verifyEmail(
          challenge: c, code: kMockVerificationCode, idempotencyKey: key());
      expect(problem(expired), OnboardingProblemCode.verificationCodeExpired);

      final fresh = ok(
          await repo.resendVerification(challenge: c, idempotencyKey: key()));
      expect(fresh.handle, c.handle);
      expect(fresh.expiresAt, now.add(kMockCodeValidity));
      expect((await verified(fresh)).link, TenantLinkStatus.unlinked);
    });

    test('the pending challenge survives a restart without the network',
        () async {
      final c = await signUp('restart@example.org');
      online = false;
      final restored = await repo.restore();
      expect(restored, isA<Offline<AuthEntryState>>());
      expect((restored as Offline<AuthEntryState>).cached,
          EntryVerificationPending(c));
    });

    test('verification completed on another device ends this challenge',
        () async {
      final c = await signUp('two.devices@example.org');
      repo.verifyElsewhere('two.devices@example.org');
      final r = await repo.verifyEmail(
          challenge: c, code: kMockVerificationCode, idempotencyKey: key());
      expect(problem(r), OnboardingProblemCode.verificationChallengeEnded);
      // Signing in now resumes at the next step — nothing is repeated.
      final again = ok(await repo.signInWithPassword(
          email: 'two.devices@example.org', password: 'a-good-password'));
      expect(again, isA<EntryContinueOnboarding>());
    });
  });

  group('Google', () {
    Future<Result<AuthEntryOutcome>> google(String token) =>
        repo.signInWithGoogle(GoogleIdentityAssertion(token),
            idempotencyKey: key());

    test('a new verified Google identity skips MTM verification', () async {
      final r = ok(await google('${kMockGoogleVerifiedPrefix}g.new@gmail.com'))
          as EntryContinueOnboarding;
      expect(r.snapshot.methods, {AuthMethod.google});
      expect(r.snapshot.link, TenantLinkStatus.unlinked);
    });

    test('an unverified Google address still needs the MTM code', () async {
      final r =
          ok(await google('${kMockGoogleUnverifiedPrefix}g.unv@example.org'));
      expect(r, isA<EntryVerificationRequired>());
    });

    test('a returning Google account signs straight in', () async {
      final r = ok(await google(
          '$kMockGoogleVerifiedPrefix${OnboardingFixtures.googleOnlyEmail}'));
      expect(
          (r as EntryContinueOnboarding).snapshot.accountId, 'acc_google_only');
    });

    test('a verified password account is never merged automatically', () async {
      final r = await google(
          '$kMockGoogleVerifiedPrefix${OnboardingFixtures.readyEmail}');
      expect(problem(r), OnboardingProblemCode.authMethodLinkRequired);
      expect(repo.fullSessionsIssued, 0);
    });

    test('an unverified password account yields to the verified Google claim',
        () async {
      final r = ok(await google(
              '$kMockGoogleVerifiedPrefix${OnboardingFixtures.unverifiedEmail}'))
          as EntryContinueOnboarding;
      expect(r.snapshot.accountId, 'acc_unverified',
          reason: 'the canonical account id survives the method change');
      expect(r.snapshot.methods, {AuthMethod.google});
    });

    test('a provisioned Main Admin can claim the seat account with Google',
        () async {
      final r = ok(await google(
              '$kMockGoogleVerifiedPrefix${OnboardingFixtures.nabdMainAdminEmail}'))
          as EntryContinueOnboarding;
      expect(r.snapshot.accountId, OnboardingFixtures.nabdMainAdminAccountId);
    });

    test('an unverifiable token is refused', () async {
      expect(problem(await google('eyJ.forged.token')),
          OnboardingProblemCode.googleAssertionRejected);
    });
  });

  group('Team Code link', () {
    Future<void> asUnlinked(String email) async =>
        verified(await signUp(email));

    test('links an invited Simple Admin; role comes from the invitation',
        () async {
      await asUnlinked(OnboardingFixtures.hilalInviteeEmail);
      final s = await link('mtm 4k7p qx92');
      expect(s.link, TenantLinkStatus.linked);
      expect(s.tenant!.role, AuthRole.admin);
      expect(s.tenant!.displayName, 'فرق الهلال الطبية');
      expect(s.setup, AccountSetupStatus.required);
      expect(s.displayNameSuggestion, 'نورة الدوسري');
    });

    test('a valid code without an invitation is indistinguishable from none',
        () async {
      await asUnlinked('stranger@example.org');
      final unknown = await repo.linkTeam(
          teamCode: OnboardingFixtures.unknownCode, idempotencyKey: key());
      final real = await repo.linkTeam(
          teamCode: OnboardingFixtures.hilalCode, idempotencyKey: key());
      expect(problem(unknown), OnboardingProblemCode.teamLinkRefused);
      expect(problem(real), OnboardingProblemCode.teamLinkRefused);
      expect((real as Failure).message, (unknown as Failure).message);
    });

    test('the Team Code alone never grants a role', () async {
      // The hilal code is valid, but this account holds no authorization.
      await asUnlinked('holds.the.code@example.org');
      final r = await repo.linkTeam(
          teamCode: OnboardingFixtures.hilalCode, idempotencyKey: key());
      expect(r, isNot(isA<Success<OnboardingSnapshot>>()));
      final s = ok(await repo.refresh());
      expect(s.link, TenantLinkStatus.unlinked);
      expect(s.tenant, isNull);
    });

    test('malformed is refused and spends no attempt', () async {
      await asUnlinked(OnboardingFixtures.hilalInviteeEmail);
      for (var i = 0; i < kMockFailureBudget * 2; i++) {
        final r =
            await repo.linkTeam(teamCode: 'MTM-00', idempotencyKey: key());
        expect(problem(r), OnboardingProblemCode.teamCodeMalformed);
      }
      expect((await link(OnboardingFixtures.hilalCode)).link,
          TenantLinkStatus.linked);
    });

    test('an expired invitation is told only to its invitee', () async {
      await asUnlinked(OnboardingFixtures.hilalExpiredInviteeEmail);
      final r = await repo.linkTeam(
          teamCode: OnboardingFixtures.hilalCode, idempotencyKey: key());
      expect(problem(r), OnboardingProblemCode.invitationExpired);
    });

    test('a suspended tenant does not complete a link', () async {
      await asUnlinked(OnboardingFixtures.ruknInviteeEmail);
      final r = await repo.linkTeam(
          teamCode: OnboardingFixtures.ruknCode, idempotencyKey: key());
      expect(problem(r), OnboardingProblemCode.tenantUnavailable);
    });

    test('a deleted tenant\'s code stops resolving', () async {
      repo.deleteTenant(OnboardingFixtures.hilalTenantId);
      await asUnlinked(OnboardingFixtures.hilalInviteeEmail);
      final r = await repo.linkTeam(
          teamCode: OnboardingFixtures.hilalCode, idempotencyKey: key());
      expect(problem(r), OnboardingProblemCode.teamLinkRefused);
    });

    test('a replay is safe; another tenant is refused without naming it',
        () async {
      await asUnlinked(OnboardingFixtures.hilalInviteeEmail);
      await link(OnboardingFixtures.hilalCode);
      // Same code again (a retry after a lost response): the same state.
      expect((await link('MTM-4K7P-QX92')).link, TenantLinkStatus.linked);
      final other = await repo.linkTeam(
          teamCode: OnboardingFixtures.nabdCode, idempotencyKey: key());
      expect(problem(other), OnboardingProblemCode.accountAlreadyLinked);
      expect((other as Failure).message, isNot(contains('نبض')));
    });

    test('brute force is throttled by the backend', () async {
      await asUnlinked('guesser@example.org');
      for (var i = 0; i < kMockFailureBudget; i++) {
        await repo.linkTeam(
            teamCode: OnboardingFixtures.unknownCode, idempotencyKey: key());
      }
      final r = await repo.linkTeam(
          teamCode: OnboardingFixtures.hilalCode, idempotencyKey: key());
      expect(problem(r), OnboardingProblemCode.rateLimited);
      expect((r as OnboardingFailure).retryAvailableAt, isNotNull);
    });

    test('a suspended account cannot link mid-journey', () async {
      await asUnlinked(OnboardingFixtures.hilalInviteeEmail);
      repo.setAccountStatus(
          OnboardingFixtures.hilalInviteeEmail, AccountStatus.suspended);
      final r = await repo.linkTeam(
          teamCode: OnboardingFixtures.hilalCode, idempotencyKey: key());
      expect(problem(r), OnboardingProblemCode.accountUnavailable);
      expect(ok(await repo.refresh()).account, AccountStatus.suspended);
    });

    test('no refusal message ever echoes the code', () async {
      await asUnlinked('echo@example.org');
      for (final code in [
        OnboardingFixtures.unknownCode,
        OnboardingFixtures.hilalCode,
        'MTM-00',
      ]) {
        final r = await repo.linkTeam(teamCode: code, idempotencyKey: key());
        expect((r as Failure).message, isNot(contains('MTM')));
        expect(r.toString(), isNot(contains(code)));
      }
    });
  });

  group('Point 17C — invitation-bound Simple Admin never needs a Team Code',
      () {
    const invitationId = 'az_hilal_admin';

    test('an invitation that becomes linkable after verification links on '
        'refresh', () async {
      repo.setTenantStatus(
          OnboardingFixtures.hilalTenantId, SaasTenantStatus.suspended);
      final before =
          await verified(await signUp(OnboardingFixtures.hilalInviteeEmail));
      expect(before.link, TenantLinkStatus.unlinked);

      repo.setTenantStatus(
          OnboardingFixtures.hilalTenantId, SaasTenantStatus.active);
      final after = ok(await repo.refresh());
      expect(after.link, TenantLinkStatus.linked);
      expect(after.tenant!.role, AuthRole.admin);
    });

    test('an invitation issued after verification links on restore', () async {
      final server = MockOnboardingServer();
      final vault = SecureAuthStateStore(InMemorySecureStore());
      repo = MockOnboardingRepository(
          clock: () => now, server: server, authState: vault);
      const email = 'invited.later@hilal-medical.org';
      expect((await verified(await signUp(email))).link,
          TenantLinkStatus.unlinked);

      // The issuer sends the invitation; the next process reads the same
      // backend with the same stored restricted session.
      repo = MockOnboardingRepository(
        clock: () => now,
        server: server,
        authState: vault,
        additionalAuthorizations: const [
          MockAuthorization(
            id: 'admin_inv_late',
            tenantId: OnboardingFixtures.hilalTenantId,
            email: email,
            role: AuthRole.admin,
            suggestedName: 'مدعو لاحقاً',
            capabilities: Capabilities(global: {Cap.detachmentView}),
            expiresIn: Duration(days: 7),
          ),
        ],
      );
      final restored = ok(await repo.restore()) as EntryOnboarding;
      expect(restored.snapshot.link, TenantLinkStatus.linked);
      expect(restored.snapshot.tenant!.displayName, 'فرق الهلال الطبية');
    });

    test('an invitation cancelled after the server started never links',
        () async {
      final server = MockOnboardingServer();
      MockOnboardingRepository(clock: () => now, server: server);
      repo = MockOnboardingRepository(
        clock: () => now,
        server: server,
        excludedAuthorizationIds: const {invitationId},
      );
      final s =
          await verified(await signUp(OnboardingFixtures.hilalInviteeEmail));
      expect(s.link, TenantLinkStatus.unlinked);
      expect(s.tenant, isNull);
    });

    test('cancelled mid-setup withdraws the link', () async {
      final server = MockOnboardingServer();
      final vault = SecureAuthStateStore(InMemorySecureStore());
      repo = MockOnboardingRepository(
          clock: () => now, server: server, authState: vault);
      expect(
          (await verified(await signUp(OnboardingFixtures.hilalInviteeEmail)))
              .link,
          TenantLinkStatus.linked);
      repo = MockOnboardingRepository(
        clock: () => now,
        server: server,
        authState: vault,
        excludedAuthorizationIds: const {invitationId},
      );
      final restored = ok(await repo.restore()) as EntryOnboarding;
      expect(restored.snapshot.link, TenantLinkStatus.withdrawn);
      expect(
          problem(await repo.completeSetup(
              displayName: 'نورة', idempotencyKey: key())),
          OnboardingProblemCode.setupUnavailable);
    });
  });

  group('Main Admin setup, against the Point 14 seat', () {
    late PlatformTenantStore store;
    late MockPlatformMainAdminRepository seats;

    setUp(() {
      store = PlatformTenantStore(clock: () => now);
      seats = MockPlatformMainAdminRepository(
        store: store,
        clock: () => now,
        permitted: () => true,
        latency: Duration.zero,
      );
      repo = MockOnboardingRepository(
        clock: () => now,
        online: () => online,
        seatActivation: (tenantId, kind) {
          final decision = switch (kind) {
            MainAdminAuthorizationKind.initialSeat =>
              seats.simulateSetupCompleted(tenantId),
            MainAdminAuthorizationKind.replacementDesignate =>
              seats.simulateReplacementSetupCompleted(tenantId),
          };
          return switch (decision) {
            MainAdminTransitionAllowed() => null,
            MainAdminTransitionRefused(:final problem) =>
              problem == MainAdminTransitionProblem.tenantNotEligible
                  ? OnboardingProblemCode.tenantUnavailable
                  : OnboardingProblemCode.setupUnavailable,
          };
        },
      );
    });

    Future<MainAdminAccountSnapshot> seat(String tenantId) async =>
        ok(await seats.load(tenantId));

    test('the fixtures describe the same people on both sides', () {
      for (final t in OnboardingFixtures.tenants) {
        final platform = store.byId(t.id)!;
        expect(platform.teamCode, t.teamCode, reason: t.id);
        expect(platform.displayName, t.displayName, reason: t.id);
        expect(platform.lifecycle.status, t.status, reason: t.id);
      }
      expect(store.byId(OnboardingFixtures.nabdTenantId)!.mainAdmin.email,
          OnboardingFixtures.nabdMainAdminEmail);
      expect(MainAdminFixtures.designateEmail,
          OnboardingFixtures.najdDesignateEmail);
      expect(MainAdminFixtures.accountIdFor(OnboardingFixtures.nabdTenantId),
          OnboardingFixtures.nabdMainAdminAccountId);
    });

    test('pending_setup → verify → Team Code → setup → active', () async {
      expect((await seat(OnboardingFixtures.nabdTenantId)).current.status,
          MainAdminAccountStatus.pendingSetup);
      final s =
          await verified(await signUp(OnboardingFixtures.nabdMainAdminEmail));
      expect(s.accountId, OnboardingFixtures.nabdMainAdminAccountId,
          reason: 'the provisioned account is claimed, not duplicated');
      final linked = await link(OnboardingFixtures.nabdCode);
      expect(linked.tenant!.role, AuthRole.mainAdmin);
      expect(linked.displayNameSuggestion, 'هدى الشمري');

      // Nothing activates on the link — only on setup completion.
      expect((await seat(OnboardingFixtures.nabdTenantId)).current.status,
          MainAdminAccountStatus.pendingSetup);

      final done = ok(await repo.completeSetup(
          displayName: 'هدى الشمري', idempotencyKey: 'setup-1'));
      expect(done, isA<EntryReady>());
      expect((await seat(OnboardingFixtures.nabdTenantId)).current.status,
          MainAdminAccountStatus.active);

      // A duplicate tap replays the answer; no second session, no second event.
      final replay = ok(await repo.completeSetup(
          displayName: 'هدى الشمري', idempotencyKey: 'setup-1'));
      expect(replay, isA<EntryReady>());
      expect(repo.fullSessionsIssued, 1);
      // A new key after the exchange: the onboarding session is spent.
      final spent = await repo.completeSetup(
          displayName: 'هدى الشمري', idempotencyKey: 'setup-2');
      expect((spent as Failure).code, 'authentication_expired');
    });

    test('a pending replacement transfers the seat and revokes the holder',
        () async {
      final before = await seat(OnboardingFixtures.najdTenantId);
      final formerHolder = before.current.accountId;
      expect(before.replacement, isNotNull);

      await verified(await signUp(OnboardingFixtures.najdDesignateEmail));
      await link(OnboardingFixtures.najdCode);
      final done = ok(await repo.completeSetup(
          displayName: 'ريم القحطاني', idempotencyKey: key()));
      expect(done, isA<EntryReady>());

      final after = await seat(OnboardingFixtures.najdTenantId);
      expect(after.current.loginEmail, OnboardingFixtures.najdDesignateEmail);
      expect(after.current.status, MainAdminAccountStatus.active);
      expect(after.current.accountId, isNot(formerHolder));
      expect(after.replacement, isNull);
    });

    test('a replacement cancelled on the Platform refuses the designate',
        () async {
      final before = await seat(OnboardingFixtures.najdTenantId);
      ok(await seats.cancelReplacement(CancelMainAdminReplacementCommand(
        tenantId: OnboardingFixtures.najdTenantId,
        expectedRevision: before.revision,
        idempotencyKey: 'cancel-1',
        replacementId: before.replacement!.id,
      )));
      await verified(await signUp(OnboardingFixtures.najdDesignateEmail));
      await link(OnboardingFixtures.najdCode);
      final r = await repo.completeSetup(
          displayName: 'ريم القحطاني', idempotencyKey: key());
      expect(problem(r), OnboardingProblemCode.setupUnavailable);
      expect((await seat(OnboardingFixtures.najdTenantId)).current.loginEmail,
          before.current.loginEmail,
          reason: 'the seat never moved');
    });

    test('an immediate replacement withdraws the old invitee mid-setup',
        () async {
      await verified(await signUp(OnboardingFixtures.nabdMainAdminEmail));
      await link(OnboardingFixtures.nabdCode);
      // Point 14 immediate mode: the never-activated holder's invitation is
      // invalidated at once. The backend withdraws the link.
      repo.withdrawAuthorization('az_nabd_seat');
      final s = ok(await repo.refresh());
      expect(s.link, TenantLinkStatus.withdrawn);
      expect(
          problem(await repo.completeSetup(
              displayName: 'هدى', idempotencyKey: key())),
          OnboardingProblemCode.setupUnavailable);
      expect(
          problem(await repo.linkTeam(
              teamCode: OnboardingFixtures.nabdCode, idempotencyKey: key())),
          OnboardingProblemCode.teamLinkRefused);
    });

    test('a tenant suspended during setup blocks completion and the seat',
        () async {
      await verified(await signUp(OnboardingFixtures.nabdMainAdminEmail));
      await link(OnboardingFixtures.nabdCode);
      repo.setTenantStatus(
          OnboardingFixtures.nabdTenantId, SaasTenantStatus.suspended);
      final r = await repo.completeSetup(
          displayName: 'هدى الشمري', idempotencyKey: key());
      expect(problem(r), OnboardingProblemCode.tenantUnavailable);
      expect(
          ok(await repo.refresh()).tenant!.status, SaasTenantStatus.suspended);
      expect((await seat(OnboardingFixtures.nabdTenantId)).current.status,
          MainAdminAccountStatus.pendingSetup);
    });

    test('a tenant deleted during setup withdraws the link', () async {
      await verified(await signUp(OnboardingFixtures.nabdMainAdminEmail));
      await link(OnboardingFixtures.nabdCode);
      repo.deleteTenant(OnboardingFixtures.nabdTenantId);
      expect(ok(await repo.refresh()).link, TenantLinkStatus.withdrawn);
    });

    test('setup completed on another device ends this onboarding session',
        () async {
      await verified(await signUp(OnboardingFixtures.nabdMainAdminEmail));
      await link(OnboardingFixtures.nabdCode);
      repo.completeSetupElsewhere(OnboardingFixtures.nabdMainAdminEmail);
      expect(problem(await repo.refresh()),
          OnboardingProblemCode.setupAlreadyCompleted);
    });
  });

  group('offline — nothing is attempted, nothing is queued', () {
    test('every trust transition answers Offline and reaches no server',
        () async {
      final c = await signUp('before.offline@example.org');
      final calls = repo.serverCalls;
      online = false;
      final results = <Result<Object?>>[
        await repo.signUpWithPassword(
            email: 'o@example.org',
            password: 'a-good-password',
            idempotencyKey: key()),
        await repo.signInWithPassword(
            email: OnboardingFixtures.readyEmail,
            password: kMockFixturePassword),
        await repo.signInWithGoogle(
            const GoogleIdentityAssertion('${kMockGoogleVerifiedPrefix}o@x.io'),
            idempotencyKey: key()),
        await repo.verifyEmail(
            challenge: c, code: kMockVerificationCode, idempotencyKey: key()),
        await repo.resendVerification(challenge: c, idempotencyKey: key()),
        await repo.linkTeam(
            teamCode: OnboardingFixtures.hilalCode, idempotencyKey: key()),
        await repo.completeSetup(displayName: 'x', idempotencyKey: key()),
        await repo.refresh(),
      ];
      for (final r in results) {
        expect(r, isA<Offline<Object?>>(), reason: '$r');
      }
      expect(repo.serverCalls, calls);
      expect(repo.accountIdFor('o@example.org'), isNull);
      online = true;
      // The challenge is exactly where it was.
      expect(ok(await repo.restore()), EntryVerificationPending(c));
    });
  });

  test('a release configuration onboards nobody', () async {
    final release = MockOnboardingRepository(clock: () => now, enabled: false);
    expect(ok(await release.restore()), const EntryNone());
    final r = await release.signInWithPassword(
        email: OnboardingFixtures.readyEmail, password: kMockFixturePassword);
    expect((r as Failure).code, 'not_permitted');
    expect(release.fullSessionsIssued, 0);
  });
}
