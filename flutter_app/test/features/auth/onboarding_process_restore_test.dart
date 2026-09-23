import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/startup/startup_destination.dart';
import 'package:mtm/core/startup/startup_providers.dart';
import 'package:mtm/core/storage/secure_store.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/mock_auth_repository.dart';
import 'package:mtm/features/auth/data/mock_onboarding_repository.dart';
import 'package:mtm/features/auth/data/onboarding_controller.dart';
import 'package:mtm/features/auth/data/persistent_demo_session_store.dart';
import 'package:mtm/features/auth/data/secure_auth_state_store.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/onboarding_models.dart';

/// Point 17C process-death coverage. Every relaunch creates a new provider
/// graph and new repositories. Only the secure device vault and the two mock
/// backend services survive, matching local-process/remote-server ownership.
void main() {
  late InMemorySecureStore device;
  late MockOnboardingServer onboardingServer;
  late MockAuthSessionServer authServer;
  late List<ProviderContainer> launches;

  setUp(() {
    device = InMemorySecureStore();
    onboardingServer = MockOnboardingServer();
    authServer = MockAuthSessionServer();
    launches = [];
  });

  tearDown(() {
    for (final container in launches.reversed) {
      container.dispose();
    }
  });

  ProviderContainer launch() {
    final container = ProviderContainer(overrides: [
      secureStoreProvider.overrideWithValue(device),
      mockOnboardingServerProvider.overrideWithValue(onboardingServer),
      mockAuthSessionServerProvider.overrideWithValue(authServer),
      demoSessionStoreProvider.overrideWithValue(const NoDemoSessionStore()),
    ]);
    launches.add(container);
    return container;
  }

  OnboardingController controller(ProviderContainer container) =>
      container.read(onboardingControllerProvider.notifier);

  Future<StartupDestination> destination(ProviderContainer container) async {
    await container.read(currentUserResultProvider.future);
    return container.read(startupDestinationProvider);
  }

  test('pending verification is revalidated and resumes after process death',
      () async {
    final first = launch();
    await controller(first).signUpWithPassword(
      email: 'restore.challenge@example.org',
      password: 'super-secret-password',
    );
    final before = onboardingServer.serverCalls;

    final second = launch();
    await controller(second).restore();

    expect(
        second.read(authEntryStateProvider), isA<EntryVerificationPending>());
    expect(onboardingServer.serverCalls, before + 1,
        reason: 'local challenge metadata is not final authority');
    expect(await destination(second), StartupDestination.emailVerification);
    expect(device.values.values.join('|'),
        isNot(contains('super-secret-password')));
  });

  test('restricted unlinked session is re-queried and resumes at Team Code',
      () async {
    final first = launch();
    await controller(first).signInWithPassword(
      email: OnboardingFixtures.verifiedUnlinkedEmail,
      password: kMockFixturePassword,
    );
    final before = onboardingServer.serverCalls;

    final second = launch();
    await controller(second).restore();

    expect(
        (second.read(authEntryStateProvider) as EntryOnboarding).snapshot.link,
        TenantLinkStatus.unlinked);
    expect(onboardingServer.serverCalls, before + 1);
    expect(await destination(second), StartupDestination.teamLink);
  });

  test('invitation-bound Simple Admin restores linked and setup-incomplete',
      () async {
    final first = launch();
    await controller(first).signUpWithPassword(
      email: OnboardingFixtures.hilalInviteeEmail,
      password: 'simple-admin-password',
    );
    await controller(first).verifyEmail(kMockVerificationCode);
    final firstState = first.read(authEntryStateProvider) as EntryOnboarding;
    expect(firstState.snapshot.link, TenantLinkStatus.linked);
    expect(firstState.snapshot.tenant!.role, AuthRole.admin);

    final second = launch();
    await controller(second).restore();
    final restored = second.read(authEntryStateProvider) as EntryOnboarding;
    expect(restored.snapshot.link, TenantLinkStatus.linked);
    expect(restored.snapshot.setup, AccountSetupStatus.required);
    expect(await destination(second), StartupDestination.firstTimeSetup);
  });

  test('completed Main Admin full session is restored through AuthRepository',
      () async {
    final first = launch();
    await controller(first).signUpWithPassword(
      email: OnboardingFixtures.nabdMainAdminEmail,
      password: 'main-admin-password',
    );
    await controller(first).verifyEmail(kMockVerificationCode);
    await controller(first).linkTeam(OnboardingFixtures.nabdCode);
    final completed =
        await controller(first).completeSetup(displayName: 'هدى الشمري');
    expect((completed as Success).data, isA<EntryReady>());
    expect(device.values, contains(SecureAuthStateStore.fullSessionKey));
    expect(device.values, isNot(contains(SecureAuthStateStore.onboardingKey)));

    final second = launch();
    final user = await second.read(currentUserProvider.future);
    await controller(second).restore();

    expect(user?.role, AuthRole.mainAdmin);
    expect(user?.saasTenantId, OnboardingFixtures.nabdTenantId);
    expect(second.read(authEntryStateProvider), const EntryNone());
    expect(await destination(second), StartupDestination.tenantSurface);
  });

  test('corrupted persisted onboarding state is removed and grants nothing',
      () async {
    device = InMemorySecureStore({
      SecureAuthStateStore.onboardingKey:
          '{"version":1,"kind":"restricted","token":"x"}',
    });
    final container = launch();
    await controller(container).restore();

    expect(container.read(authEntryStateProvider), const EntryNone());
    expect(device.values, isNot(contains(SecureAuthStateStore.onboardingKey)));
    expect(await destination(container), StartupDestination.signedOut);
  });

  test('revoked restricted session closes after authoritative restore',
      () async {
    final first = launch();
    await controller(first).signInWithPassword(
      email: OnboardingFixtures.verifiedUnlinkedEmail,
      password: kMockFixturePassword,
    );
    final token = (await SecureAuthStateStore(device).readOnboarding()
            as StoredRestrictedSession)
        .token;
    onboardingServer.revokeRestrictedSession(token);

    final second = launch();
    await controller(second).restore();
    expect(second.read(authEntryStateProvider),
        const EntryNone(notice: EntryNotice.sessionEnded));
    expect(await destination(second), StartupDestination.signedOut);
  });

  test('revoked full session restores as expired, never as a local account',
      () async {
    final first = launch();
    await controller(first).signInWithPassword(
      email: OnboardingFixtures.readyEmail,
      password: kMockFixturePassword,
    );
    final token = authServer.lastIssuedToken!;
    authServer.revoke(token);

    final second = launch();
    final result = await second.read(currentUserResultProvider.future);
    expect(result, isA<Failure<AuthUser?>>());
    expect(second.read(authGateProvider), AuthGate.expired);
    expect(await destination(second), StartupDestination.sessionExpired);
    expect(device.values, isNot(contains(SecureAuthStateStore.fullSessionKey)));
  });

  test('ephemeral onboarding evidence never enters the secure vault', () async {
    final container = launch();
    await controller(container).signUpWithPassword(
      email: OnboardingFixtures.nabdMainAdminEmail,
      password: 'never-persist-this-password',
    );
    await controller(container).verifyEmail(kMockVerificationCode);
    await controller(container).linkTeam(OnboardingFixtures.nabdCode);
    final dump = device.values.values.join('|');
    for (final forbidden in [
      'never-persist-this-password',
      kMockVerificationCode,
      OnboardingFixtures.nabdCode,
      '$kMockGoogleVerifiedPrefix${OnboardingFixtures.nabdMainAdminEmail}',
    ]) {
      expect(dump, isNot(contains(forbidden)));
    }
  });
}
