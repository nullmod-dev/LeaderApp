import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/startup/startup_destination.dart';
import 'package:mtm/core/startup/startup_providers.dart';
import 'package:mtm/core/sync/outbox_controller.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/demo_personas.dart';
import 'package:mtm/features/auth/data/demo_sign_in_controller.dart';
import 'package:mtm/features/auth/data/in_memory_demo_session_store.dart';
import 'package:mtm/features/auth/data/mock_auth_repository.dart';
import 'package:mtm/features/auth/data/mock_onboarding_repository.dart';
import 'package:mtm/features/auth/data/onboarding_controller.dart';
import 'package:mtm/features/auth/data/sign_out_controller.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/onboarding_models.dart';
import 'package:mtm/features/auth/domain/onboarding_repository.dart';
import 'package:mtm/features/auth/domain/session_access.dart';

/// Records the idempotency key of every mutation it forwards.
class _RecordingRepository extends MockOnboardingRepository {
  _RecordingRepository({required super.clock, required super.online});

  final List<String> keys = [];

  @override
  Future<Result<VerificationChallenge>> signUpWithPassword({
    required String email,
    required String password,
    required String idempotencyKey,
  }) {
    keys.add(idempotencyKey);
    return super.signUpWithPassword(
        email: email, password: password, idempotencyKey: idempotencyKey);
  }

  @override
  Future<Result<OnboardingSnapshot>> linkTeam({
    required String teamCode,
    required String idempotencyKey,
  }) {
    keys.add(idempotencyKey);
    return super.linkTeam(teamCode: teamCode, idempotencyKey: idempotencyKey);
  }
}

/// Point 17A — the controller that drives machines A–D and feeds E.
void main() {
  final now = DateTime.utc(2026, 9, 12, 9);
  late _RecordingRepository repo;
  late ProviderContainer container;
  late int userReads;
  var online = true;

  ProviderContainer build() {
    final c = ProviderContainer(overrides: [
      onboardingRepositoryProvider.overrideWithValue(repo),
      currentUserResultProvider.overrideWith((ref) async {
        userReads++;
        return const Success<AuthUser?>(null);
      }),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    online = true;
    userReads = 0;
    repo = _RecordingRepository(clock: () => now, online: () => online);
    container = build();
  });

  OnboardingController ctrl() =>
      container.read(onboardingControllerProvider.notifier);
  AuthEntryState state() => container.read(authEntryStateProvider);
  StartupDestination destination() =>
      container.read(startupDestinationProvider);

  Future<void> toUnlinked(String email) async {
    await ctrl().signUpWithPassword(email: email, password: 'a-good-password');
    await ctrl().verifyEmail(kMockVerificationCode);
  }

  test('starts with no journey; the shipped startup is unchanged', () async {
    expect(state(), const EntryNone());
    await container.read(currentUserResultProvider.future);
    expect(destination(), StartupDestination.signedOut);
  });

  group('sign-up → verify → link → setup', () {
    // The initial Main Admin seat — Team Code stays required for it (Point
    // 17A "F. Team Code"), unlike a Simple Admin invitation (see the
    // "invitation-bound link" group below, HANDOFF.md "POINT 17B" §4.3).
    test('each trust transition moves the state, and startup follows',
        () async {
      final c = await ctrl().signUpWithPassword(
          email: ' Huda@Nabd-Team.org ', password: 'a-good-password');
      expect(c, isA<Success<VerificationChallenge>>());
      expect(state(), isA<EntryVerificationPending>());
      await container.read(currentUserResultProvider.future);
      expect(destination(), StartupDestination.emailVerification);

      await ctrl().verifyEmail('٢٤٦ ٨١٠'); // Arabic-Indic digits, spaced
      expect((state() as EntryOnboarding).snapshot.link,
          TenantLinkStatus.unlinked);
      expect(destination(), StartupDestination.teamLink);

      await ctrl().linkTeam('mtm 5jqx 2twd');
      final linked = (state() as EntryOnboarding).snapshot;
      expect(linked.tenant!.role, AuthRole.mainAdmin);
      expect(destination(), StartupDestination.firstTimeSetup);

      final readsBefore = userReads;
      final done = await ctrl().completeSetup(displayName: 'هدى الشمري');
      expect((done as Success).data, isA<EntryReady>());
      expect(state(), const EntryNone());
      await container.read(currentUserResultProvider.future);
      expect(userReads, greaterThan(readsBefore),
          reason: 'a full session is re-read, never assumed');
    });

    test('a Simple Admin invitation links on verification — no Team Code',
        () async {
      final c = await ctrl().signUpWithPassword(
          email: ' Noura@Hilal-Medical.org ', password: 'a-good-password');
      expect(c, isA<Success<VerificationChallenge>>());
      await container.read(currentUserResultProvider.future);

      await ctrl().verifyEmail(kMockVerificationCode);
      final snapshot = (state() as EntryOnboarding).snapshot;
      expect(snapshot.link, TenantLinkStatus.linked);
      expect(snapshot.tenant!.role, AuthRole.admin);
      expect(snapshot.tenant!.displayName, 'فرق الهلال الطبية');
      // Straight to setup: the Team Code screen is never reached.
      expect(destination(), StartupDestination.firstTimeSetup);

      final done = await ctrl().completeSetup(displayName: 'نورة الدوسري');
      expect((done as Success).data, isA<EntryReady>());
    });

    test('a finished account signing in skips every step', () async {
      final r = await ctrl().signInWithPassword(
          email: OnboardingFixtures.readyEmail, password: kMockFixturePassword);
      expect((r as Success).data, isA<EntryReady>());
      expect(state(), const EntryNone());
      expect(repo.fullSessionsIssued, 1);
    });

    test('Google enters the same journey; collisions are not merged', () async {
      await ctrl().signInWithGoogle(const GoogleIdentityAssertion(
          '${kMockGoogleVerifiedPrefix}new.google@gmail.com'));
      await container.read(currentUserResultProvider.future);
      expect(destination(), StartupDestination.teamLink);
      await ctrl().abandon();

      final r = await ctrl().signInWithGoogle(const GoogleIdentityAssertion(
          '$kMockGoogleVerifiedPrefix${OnboardingFixtures.readyEmail}'));
      expect(onboardingErrorKindOf(r), OnboardingErrorKind.methodLinkRequired);
      expect(state(), const EntryNone());
    });
  });

  group('courtesy checks run before any request', () {
    test('malformed email, code and Team Code spend nothing', () async {
      final calls = repo.serverCalls;
      expect(
          onboardingErrorKindOf(await ctrl()
              .signUpWithPassword(email: 'nope', password: 'a-good-password')),
          OnboardingErrorKind.invalidInput);
      expect(repo.serverCalls, calls);

      await toUnlinked('checks@example.org');
      final after = repo.serverCalls;
      expect(onboardingErrorKindOf(await ctrl().linkTeam('MTM-12')),
          OnboardingErrorKind.teamCodeMalformed);
      expect(
          onboardingErrorKindOf(await ctrl().completeSetup(displayName: ' ')),
          OnboardingErrorKind.invalidInput);
      expect(repo.serverCalls, after);
    });
  });

  group('duplicates and retries', () {
    test('a double tap sends one request and shares its answer', () async {
      final calls = repo.serverCalls;
      final a = ctrl().signUpWithPassword(
          email: 'twice@example.org', password: 'a-good-password');
      final b = ctrl().signUpWithPassword(
          email: 'twice@example.org', password: 'a-good-password');
      final results = await Future.wait([a, b]);
      expect(repo.serverCalls, calls + 1);
      expect((results[0] as Success).data, (results[1] as Success).data);
    });

    test('a retry after a lost connection reuses the key; a new answer ends it',
        () async {
      online = false;
      final offline = await ctrl().signUpWithPassword(
          email: 'retry@example.org', password: 'a-good-password');
      expect(offline, isA<Offline<VerificationChallenge>>());
      online = true;
      await ctrl().signUpWithPassword(
          email: 'retry@example.org', password: 'a-good-password');
      expect(repo.keys[1], repo.keys[0], reason: 'same intent, same key');

      await ctrl().signUpWithPassword(
          email: 'retry@example.org', password: 'a-good-password');
      expect(repo.keys[2], isNot(repo.keys[1]),
          reason: 'after a definitive answer a new submit is a new intent');
    });

    test('changed input is a new key', () async {
      await toUnlinked('keys@example.org');
      await ctrl().linkTeam(OnboardingFixtures.unknownCode);
      await ctrl().linkTeam(OnboardingFixtures.hilalCode);
      expect(repo.keys.last, isNot(repo.keys[repo.keys.length - 2]));
    });
  });

  group('verification failures', () {
    test('a wrong code keeps the challenge and narrows the attempts', () async {
      await ctrl().signUpWithPassword(
          email: 'wrong@example.org', password: 'a-good-password');
      final r = await ctrl().verifyEmail('000000');
      expect(onboardingErrorKindOf(r),
          OnboardingErrorKind.verificationCodeInvalid);
      final pending = state() as EntryVerificationPending;
      expect(
          pending.challenge.attemptsRemaining, kMockVerificationAttempts - 1);
    });

    test('an ended challenge closes the journey with a notice', () async {
      await ctrl().signUpWithPassword(
          email: 'ended@example.org', password: 'a-good-password');
      for (var i = 0; i < kMockVerificationAttempts; i++) {
        await ctrl().verifyEmail('000000');
      }
      expect(state(), const EntryNone(notice: EntryNotice.verificationEnded));
      await container.read(currentUserResultProvider.future);
      expect(destination(), StartupDestination.signedOut);
    });

    test('resend inside the cooldown is refused with its retry instant',
        () async {
      await ctrl().signUpWithPassword(
          email: 'resend@example.org', password: 'a-good-password');
      final r = await ctrl().resendVerification();
      expect(onboardingErrorKindOf(r), OnboardingErrorKind.resendThrottled);
      expect((r as OnboardingFailure).retryAvailableAt,
          now.add(kMockResendCooldown));
    });
  });

  group('races resolve by refreshing authoritative state', () {
    test('a tenant suspended mid-setup routes to its blocking screen',
        () async {
      await toUnlinked(OnboardingFixtures.hilalInviteeEmail);
      await ctrl().linkTeam(OnboardingFixtures.hilalCode);
      repo.setTenantStatus(
          OnboardingFixtures.hilalTenantId, SaasTenantStatus.suspended);
      final r = await ctrl().completeSetup(displayName: 'نورة');
      expect(onboardingErrorKindOf(r), OnboardingErrorKind.tenantUnavailable);
      expect((state() as EntryOnboarding).snapshot.tenant!.status,
          SaasTenantStatus.suspended);
      await container.read(currentUserResultProvider.future);
      expect(destination(), StartupDestination.tenantSuspended);
    });

    test('an invitation withdrawn mid-setup returns to the link step',
        () async {
      await toUnlinked(OnboardingFixtures.hilalInviteeEmail);
      await ctrl().linkTeam(OnboardingFixtures.hilalCode);
      repo.withdrawAuthorization('az_hilal_admin');
      await ctrl().completeSetup(displayName: 'نورة');
      expect((state() as EntryOnboarding).snapshot.link,
          TenantLinkStatus.withdrawn);
      await container.read(currentUserResultProvider.future);
      expect(destination(), StartupDestination.teamLink);
    });

    test('an account suspended mid-journey is routed, not retried', () async {
      await toUnlinked(OnboardingFixtures.hilalInviteeEmail);
      repo.setAccountStatus(
          OnboardingFixtures.hilalInviteeEmail, AccountStatus.suspended);
      await ctrl().linkTeam(OnboardingFixtures.hilalCode);
      await container.read(currentUserResultProvider.future);
      expect(destination(), StartupDestination.accountSuspended);
    });

    test('setup finished on another device ends this journey', () async {
      await toUnlinked(OnboardingFixtures.hilalInviteeEmail);
      await ctrl().linkTeam(OnboardingFixtures.hilalCode);
      repo.completeSetupElsewhere(OnboardingFixtures.hilalInviteeEmail);
      await ctrl().refresh();
      expect(state(),
          const EntryNone(notice: EntryNotice.setupCompletedElsewhere));
    });
  });

  group('offline — typed unavailable, never queued', () {
    test('no trust transition is queued or changes state', () async {
      await toUnlinked(OnboardingFixtures.hilalInviteeEmail);
      final before = state();
      online = false;
      final results = <Result<Object?>>[
        await ctrl().linkTeam(OnboardingFixtures.hilalCode),
        await ctrl().completeSetup(displayName: 'نورة'),
        await ctrl().signInWithGoogle(const GoogleIdentityAssertion(
            '${kMockGoogleVerifiedPrefix}a@b.io')),
        await ctrl().signInWithPassword(
            email: OnboardingFixtures.readyEmail,
            password: kMockFixturePassword),
      ];
      for (final r in results) {
        expect(onboardingErrorKindOf(r), OnboardingErrorKind.offline);
      }
      expect(state(), before, reason: 'offline changes nothing');
      expect(await container.read(outboxStoreProvider).readAll(), isEmpty);
      await ctrl().refresh();
      expect((state() as EntryOnboarding).stale, isTrue);
    });

    test('sign-up and verification offline leave nothing behind', () async {
      online = false;
      await ctrl().signUpWithPassword(
          email: 'queued@example.org', password: 'a-good-password');
      expect(state(), const EntryNone());
      expect(repo.accountIdFor('queued@example.org'), isNull);
      expect(await container.read(outboxStoreProvider).readAll(), isEmpty);
    });
  });

  group('restart', () {
    test('a pending challenge resumes on the code step', () async {
      await ctrl().signUpWithPassword(
          email: 'relaunch@example.org', password: 'a-good-password');
      final held = (state() as EntryVerificationPending).challenge;
      container = build(); // a new process over the same device vault
      expect(state(), const EntryNone());
      await ctrl().restore();
      expect(state(), EntryVerificationPending(held));
    });

    test('an onboarding session resumes where it stood, stale when offline',
        () async {
      await toUnlinked(OnboardingFixtures.hilalInviteeEmail);
      await ctrl().linkTeam(OnboardingFixtures.hilalCode);
      container = build();
      online = false;
      await ctrl().restore();
      final s = state() as EntryOnboarding;
      expect(s.stale, isTrue);
      expect(s.snapshot.link, TenantLinkStatus.linked);
    });
  });

  group('privacy', () {
    test('no password, code or Team Code survives into state', () async {
      await ctrl().signUpWithPassword(
          email: OnboardingFixtures.hilalInviteeEmail,
          password: 'super-secret-pass');
      await ctrl().verifyEmail(kMockVerificationCode);
      await ctrl().linkTeam(OnboardingFixtures.hilalCode);
      final s = state() as EntryOnboarding;
      final text = '${s.snapshot} ${s.snapshot.toJson()}';
      expect(text, isNot(contains('super-secret-pass')));
      expect(text, isNot(contains(kMockVerificationCode)));
      expect(text, isNot(contains(OnboardingFixtures.hilalCode)));
    });
  });

  group('sign-out and demo boundaries', () {
    test('sign-out during onboarding ends the journey, not a full session',
        () async {
      await toUnlinked('leaving@example.org');
      final r =
          await container.read(signOutControllerProvider.notifier).signOut();
      expect(r, isA<Success<void>>());
      expect(state(), const EntryNone());
      expect((await repo.restore()), isA<Success<AuthEntryState>>());
      expect(((await repo.restore()) as Success).data, const EntryNone());
    });

    test('a development persona never touches onboarding state', () async {
      final demo = ProviderContainer(overrides: [
        onboardingRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(MockAuthRepository(
            demoSessions: InMemoryDemoSessionStore(seed: null))),
      ]);
      addTearDown(demo.dispose);
      final calls = repo.serverCalls;
      await demo
          .read(demoSignInControllerProvider.notifier)
          .signInAs(DemoPersona.mainAdmin);
      expect(demo.read(authEntryStateProvider), const EntryNone());
      expect(repo.serverCalls, calls,
          reason: 'no Team Code, no link, no '
              'onboarding identity is created for a demo');
    });
  });
}
