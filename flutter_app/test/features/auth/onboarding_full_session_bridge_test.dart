import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/result/result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mtm/features/admin_management/data/simple_admin_providers.dart';
import 'package:mtm/features/admin_management/domain/simple_admin_models.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/mock_auth_repository.dart';
import 'package:mtm/features/auth/data/mock_onboarding_repository.dart';
import 'package:mtm/features/auth/data/onboarding_controller.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/onboarding_models.dart';

/// Point 17B — the bridge from a completed onboarding journey into the
/// **existing** full session (`currentUser()`), and the security property
/// that makes it safe: every field on the resulting [AuthUser] comes from a
/// backend authorization, never from anything typed on a form.
///
/// This exercises the real, unoverridden provider graph
/// (`onboardingRepositoryProvider` → `MockOnboardingRepository`,
/// `authRepositoryProvider` → `MockAuthRepository`) — the same wiring
/// `main.dart` runs — because the bridge is exactly the seam between those
/// two default providers.
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  OnboardingController ctrl() =>
      container.read(onboardingControllerProvider.notifier);

  Future<AuthUser?> currentUser() async {
    final r = await container.read(currentUserResultProvider.future);
    return r.when(
      success: (data, {stale = false}) => data,
      failure: (_, __) => null,
      offline: (cached) => cached,
    );
  }

  test('a returning, already-set-up account is bridged on sign-in alone',
      () async {
    final r = await ctrl().signInWithPassword(
      email: OnboardingFixtures.readyEmail,
      password: kMockFixturePassword,
    );
    expect((r as Success).data, isA<EntryReady>());

    final user = await currentUser();
    expect(user, isNotNull);
    expect(user!.role, AuthRole.admin);
    expect(user.saasTenantId, OnboardingFixtures.hilalTenantId);
    expect(user.orgName, 'فرق الهلال الطبية');
    expect(user.email, OnboardingFixtures.readyEmail);
    // `az_hilal_ready` was seeded with no explicit grant.
    expect(user.capabilities, Capabilities.none);
    expect(container.read(authRepositoryProvider), isA<MockAuthRepository>());
  });

  test(
      'a Main Admin seat setup produces a full session with the seat\'s own grant',
      () async {
    await ctrl().signUpWithPassword(
      email: OnboardingFixtures.nabdMainAdminEmail,
      password: 'a-good-password',
    );
    await ctrl().verifyEmail(kMockVerificationCode);
    await ctrl().linkTeam(OnboardingFixtures.nabdCode);

    // The display name typed here must not leak into role or capability —
    // only the account's name field.
    final r = await ctrl().completeSetup(displayName: 'اسم اختبار عشوائي');
    expect((r as Success).data, isA<EntryReady>());

    final user = await currentUser();
    expect(user, isNotNull);
    expect(user!.name, 'اسم اختبار عشوائي');
    expect(user.role, AuthRole.mainAdmin);
    expect(user.saasTenantId, OnboardingFixtures.nabdTenantId);
    expect(user.capabilities, const Capabilities(global: Cap.all));
  });

  test(
      'a Simple Admin invitation produces exactly the invitation\'s grant, '
      'never the setup form\'s input', () async {
    await ctrl().signUpWithPassword(
      email: OnboardingFixtures.hilalInviteeEmail,
      password: 'a-good-password',
    );
    // Auto-linked on verification — no Team Code call anywhere in this test.
    await ctrl().verifyEmail(kMockVerificationCode);

    final r = await ctrl().completeSetup(displayName: 'اسم آخر لا صلة له');
    expect((r as Success).data, isA<EntryReady>());

    final user = await currentUser();
    expect(user, isNotNull);
    expect(user!.role, AuthRole.admin);
    expect(user.saasTenantId, OnboardingFixtures.hilalTenantId);
    // The exact preset from `OnboardingFixtures.authorizations['az_hilal_admin']`
    // — proof the grant came from the authorization, not the display name
    // field (which has no capability of its own to leak).
    expect(user.capabilities.global, contains(Cap.memberInvite));
    expect(user.capabilities.global, contains(Cap.shiftPublish));
    expect(user.capabilities.global, isNot(contains(Cap.adminManage)));
  });

  test(
      'Point 18B: setup consumes the Simple Admin invitation atomically — '
      'accepted, one account, idempotent', () async {
    final store = container.read(simpleAdminStoreProvider);
    const invitationId = 'az_hilal_admin';
    expect(store.invitations[invitationId]!.status,
        SimpleAdminInvitationStatus.pending);
    final accountsBefore = store.accounts.length;

    await ctrl().signUpWithPassword(
      email: OnboardingFixtures.hilalInviteeEmail,
      password: 'a-good-password',
    );
    await ctrl().verifyEmail(kMockVerificationCode);
    final r = await ctrl().completeSetup(displayName: 'نورة');
    expect((r as Success).data, isA<EntryReady>());

    final invitation = store.invitations[invitationId]!;
    expect(invitation.status, SimpleAdminInvitationStatus.accepted,
        reason: 'never left pending after its invitee finished setup');
    expect(store.accounts.length, accountsBefore + 1);
    final user = (await currentUser())!;
    final account = store.accounts[user.id]!;
    expect(account.email, OnboardingFixtures.hilalInviteeEmail);
    expect(account.tenantId, invitation.tenantId);
    expect(account.capabilities, invitation.capabilities,
        reason: 'the backend-assigned grant, not anything the invitee chose');
    expect(account.status, SimpleAdminAccountStatus.active);

    // A retried completion is the same logical success at most: it can
    // never add a second admin relationship or revive the invitation.
    await ctrl().completeSetup(displayName: 'نورة');
    expect(store.accounts.length, accountsBefore + 1);
    expect(store.invitations[invitationId]!.status,
        SimpleAdminInvitationStatus.accepted);
    // And the consumed invitation no longer links anyone.
    final repo = container.read(onboardingRepositoryProvider);
    expect(repo, isA<MockOnboardingRepository>());
    expect(
        (repo as MockOnboardingRepository)
            .additionalAuthorizations
            .map((a) => a.id),
        isNot(contains(invitationId)));
  });
}
