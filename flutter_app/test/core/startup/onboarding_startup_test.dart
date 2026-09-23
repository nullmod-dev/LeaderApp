import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_guard.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/startup/startup_destination.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/mock_onboarding_repository.dart';
import 'package:mtm/features/auth/data/onboarding_controller.dart';
import 'package:mtm/features/auth/data/sign_out_controller.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/onboarding_models.dart';
import 'package:mtm/features/auth/domain/session_access.dart';
import 'package:mtm/features/auth/presentation/link_team_page.dart';
import 'package:mtm/features/auth/presentation/status_pages.dart';
import 'package:mtm/features/shell/main_shell.dart';

/// Point 17A — machine E: where a pre-session identity belongs, and the
/// router wall that keeps it there.
void main() {
  final now = DateTime.utc(2026, 9, 12, 9);

  StartupDestination resolve({
    AuthGate gate = AuthGate.signedOut,
    AuthUser? user,
    AuthEntryState entry = const EntryNone(),
    SessionAccess access = SessionAccess.normal,
    bool upgradeBlocks = false,
  }) =>
      resolveStartup(StartupInputs(
        gate: gate,
        now: now,
        user: user,
        entry: entry,
        access: access,
        upgradeBlocks: upgradeBlocks,
        hasTenantCapability: user?.capabilities.hasAny ?? false,
      ));

  OnboardingSnapshot snap({
    AccountStatus account = AccountStatus.pendingSetup,
    TenantLinkStatus link = TenantLinkStatus.unlinked,
    AuthRole role = AuthRole.admin,
    SaasTenantStatus tenant = SaasTenantStatus.active,
    AccountSetupStatus setup = AccountSetupStatus.required,
    Map<OnboardingField, String> unsupported = const {},
  }) =>
      OnboardingSnapshot(
        accountId: 'acc_1',
        email: 'x@mtm.test',
        methods: const {AuthMethod.password},
        account: account,
        link: link,
        tenant: link == TenantLinkStatus.linked
            ? LinkedTenant(displayName: 'فريق', role: role, status: tenant)
            : null,
        setup: setup,
        unsupported: unsupported,
      );

  EntryOnboarding onboarding(OnboardingSnapshot s) => EntryOnboarding(s);

  final challenge =
      VerificationChallenge(handle: 'vc_1', maskedEmail: 'x***@mtm.test');

  group('the partial-onboarding table (deterministic)', () {
    final rows = <(String, AuthEntryState, StartupDestination)>[
      ('signed out', const EntryNone(), StartupDestination.signedOut),
      (
        'signed out after an ended journey',
        const EntryNone(notice: EntryNotice.verificationEnded),
        StartupDestination.signedOut
      ),
      (
        'stored journey not read yet',
        const EntryRestoring(),
        StartupDestination.restoring
      ),
      (
        'refused onboarding payload',
        const EntryInvalid(),
        StartupDestination.invalidSession
      ),
      (
        'created, address unverified',
        EntryVerificationPending(challenge),
        StartupDestination.emailVerification
      ),
      ('verified, unlinked', onboarding(snap()), StartupDestination.teamLink),
      (
        'verified, link withdrawn before setup',
        onboarding(snap(link: TenantLinkStatus.withdrawn)),
        StartupDestination.teamLink
      ),
      (
        'linked, setup incomplete (Simple Admin)',
        onboarding(snap(link: TenantLinkStatus.linked)),
        StartupDestination.firstTimeSetup
      ),
      (
        'Main Admin pending setup',
        onboarding(
            snap(link: TenantLinkStatus.linked, role: AuthRole.mainAdmin)),
        StartupDestination.firstTimeSetup
      ),
      (
        'setup complete, full session not yet exchanged',
        onboarding(snap(
            link: TenantLinkStatus.linked,
            account: AccountStatus.active,
            setup: AccountSetupStatus.completed)),
        StartupDestination.firstTimeSetup
      ),
      (
        'suspended account',
        onboarding(snap(account: AccountStatus.suspended)),
        StartupDestination.accountSuspended
      ),
      (
        'revoked account',
        onboarding(snap(account: AccountStatus.revoked)),
        StartupDestination.accountRevoked
      ),
      (
        'linked, tenant suspended',
        onboarding(snap(
            link: TenantLinkStatus.linked, tenant: SaasTenantStatus.suspended)),
        StartupDestination.tenantSuspended
      ),
      (
        'linked, tenant deletion pending',
        onboarding(snap(
            link: TenantLinkStatus.linked,
            tenant: SaasTenantStatus.deletionPending)),
        StartupDestination.tenantDeletionPending
      ),
      (
        'linked, tenant deleted',
        onboarding(snap(
            link: TenantLinkStatus.linked, tenant: SaasTenantStatus.deleted)),
        StartupDestination.tenantDeleted
      ),
      (
        'an unreadable lifecycle value',
        onboarding(
            snap(unsupported: const {OnboardingField.accountStatus: 'locked'})),
        StartupDestination.unsupportedAccessState
      ),
    ];

    for (final (label, entry, expected) in rows) {
      test(label, () {
        expect(resolve(entry: entry), expected);
        // Same inputs, same answer — and the same answer when the full-session
        // read is merely unknown (offline, nothing cached).
        expect(resolve(entry: entry), expected);
        if (entry is! EntryNone) {
          expect(resolve(gate: AuthGate.unknown, entry: entry), expected,
              reason: 'offline must not drop a pre-session identity into '
                  'the go-where-you-asked behaviour');
        }
      });
    }
  });

  group('precedence inside the journey', () {
    test('account lifecycle outranks the link and the tenant', () {
      expect(
        resolve(
            entry: onboarding(snap(
                account: AccountStatus.suspended,
                link: TenantLinkStatus.linked,
                tenant: SaasTenantStatus.deleted))),
        StartupDestination.accountSuspended,
      );
    });

    test('tenant lifecycle outranks setup', () {
      expect(
        resolve(
            entry: onboarding(snap(
                link: TenantLinkStatus.linked,
                role: AuthRole.mainAdmin,
                tenant: SaasTenantStatus.suspended))),
        StartupDestination.tenantSuspended,
      );
    });

    test('an unsupported value outranks everything in the snapshot', () {
      expect(
        resolve(
            entry: onboarding(snap(
                account: AccountStatus.revoked,
                unsupported: const {OnboardingField.linkStatus: '?'}))),
        StartupDestination.unsupportedAccessState,
      );
    });

    test('no snapshot can ever produce a product or demo surface', () {
      const forbidden = {
        StartupDestination.tenantSurface,
        StartupDestination.platformSurface,
        StartupDestination.demoActive,
        StartupDestination.demoExpired,
        StartupDestination.tenantNoAccess,
        StartupDestination.unresolved,
        StartupDestination.signedOut,
      };
      for (final account in AccountStatus.values) {
        for (final link in TenantLinkStatus.values) {
          for (final role in [AuthRole.mainAdmin, AuthRole.admin]) {
            for (final tenant in SaasTenantStatus.values) {
              for (final setup in AccountSetupStatus.values) {
                if (link != TenantLinkStatus.linked &&
                    setup == AccountSetupStatus.completed) {
                  continue; // structurally invalid; the parser refuses it
                }
                final d = onboardingDestination(snap(
                    account: account,
                    link: link,
                    role: role,
                    tenant: tenant,
                    setup: setup));
                expect(forbidden, isNot(contains(d)),
                    reason: '$account $link $role $tenant $setup');
                expect(d.isProductSurface, isFalse);
              }
            }
          }
        }
      }
    });
  });

  group('the journey against the rest of the table', () {
    test('forced upgrade and an expired full session outrank it', () {
      final entry = onboarding(snap());
      expect(resolve(entry: entry, upgradeBlocks: true),
          StartupDestination.forcedUpgrade);
      expect(resolve(gate: AuthGate.expired, entry: entry),
          StartupDestination.sessionExpired);
      expect(resolve(gate: AuthGate.restoring, entry: entry),
          StartupDestination.restoring);
    });

    test('a full session wins over any stale entry state', () {
      for (final entry in [
        onboarding(snap()),
        EntryVerificationPending(challenge),
        const EntryInvalid(),
      ]) {
        expect(resolve(gate: AuthGate.signedIn, user: _mainAdmin, entry: entry),
            StartupDestination.tenantSurface);
        expect(
            resolve(gate: AuthGate.signedIn, user: _superAdmin, entry: entry),
            StartupDestination.platformSurface,
            reason: 'Super Admin routes to Platform, never through a link');
        expect(
          resolve(
              gate: AuthGate.signedIn,
              user: _demo,
              entry: entry,
              access: const SessionAccess(demo: DemoMode.active)),
          StartupDestination.demoActive,
          reason: 'a demo session is never asked for a Team Code',
        );
      }
    });

    test('a returning, finished account goes straight to its surface', () {
      expect(resolve(gate: AuthGate.signedIn, user: _mainAdmin),
          StartupDestination.tenantSurface);
      expect(resolve(gate: AuthGate.signedIn, user: _superAdmin),
          StartupDestination.platformSurface);
    });

    test('offline with no account and no journey is unchanged', () {
      expect(resolve(gate: AuthGate.unknown), StartupDestination.unresolved);
    });

    test('the two new locations are single, startup-only pages', () {
      expect(StartupDestination.emailVerification.location, '/verify-email');
      expect(StartupDestination.teamLink.location, '/link-team');
      for (final d in [
        StartupDestination.emailVerification,
        StartupDestination.teamLink,
      ]) {
        expect(d.ownsSubtree, isFalse);
        expect(d.isProductSurface, isFalse);
        expect(startupStatusPages.containsKey(d.location), isTrue);
      }
    });
  });

  group('the router wall', () {
    const tenantRoutes = [
      '/home',
      '/detachment',
      '/detachment/d_dam_central/team',
      '/members',
      '/more',
      '/more/organization',
      '/platform',
      '/platform/tenants',
    ];

    Future<(ProviderContainer, GoRouter)> boot(
      WidgetTester tester, {
      Result<AuthUser?> session = const Success<AuthUser?>(null),
    }) async {
      final inherited = FlutterError.onError;
      FlutterError.onError = (details) {
        final report = details.toString();
        if (report.contains('overflowed')) return;
        inherited?.call(details);
      };
      addTearDown(() => FlutterError.onError = inherited);
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final repo = MockOnboardingRepository(clock: () => now);
      final container = ProviderContainer(overrides: [
        currentUserResultProvider.overrideWith((ref) async => session),
        sessionsProvider
            .overrideWith((ref) async => const Success<List<Session>>([])),
        onboardingRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(PaletteId.medical),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ));
      await settle(tester);
      return (container, router);
    }

    String at(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;

    testWidgets('a verified, unlinked identity is held on /link-team',
        (tester) async {
      final (container, router) = await boot(tester);
      expect(at(router), '/login');
      await container
          .read(onboardingControllerProvider.notifier)
          .signInWithPassword(
              email: OnboardingFixtures.verifiedUnlinkedEmail,
              password: kMockFixturePassword);
      await settle(tester);
      expect(at(router), '/link-team');
      expect(find.byType(LinkTeamPage), findsOneWidget);
      expect(container.read(capabilitiesProvider), Capabilities.none);

      for (final route in tenantRoutes) {
        router.go(route);
        await settle(tester);
        expect(at(router), '/link-team', reason: route);
        expect(find.byType(MainShell), findsNothing, reason: route);
      }
    });

    testWidgets('an unverified identity is held on /verify-email',
        (tester) async {
      final (container, router) = await boot(tester);
      await container
          .read(onboardingControllerProvider.notifier)
          .signInWithPassword(
              email: OnboardingFixtures.unverifiedEmail,
              password: kMockFixturePassword);
      await settle(tester);
      expect(at(router), '/verify-email');
      for (final route in [...tenantRoutes, '/link-team', '/account-setup']) {
        router.go(route);
        await settle(tester);
        expect(at(router), '/verify-email', reason: route);
      }
    });

    testWidgets('a suspended onboarding account cannot deep-link around',
        (tester) async {
      final (container, router) = await boot(tester);
      await container
          .read(onboardingControllerProvider.notifier)
          .signInWithPassword(
              email: OnboardingFixtures.suspendedEmail,
              password: kMockFixturePassword);
      await settle(tester);
      expect(at(router), '/account-suspended');
      for (final route in [...tenantRoutes, '/link-team', '/verify-email']) {
        router.go(route);
        await settle(tester);
        expect(at(router), '/account-suspended', reason: route);
      }
    });

    testWidgets('a linked account in setup is held on /account-setup',
        (tester) async {
      final (container, router) = await boot(tester);
      await container
          .read(onboardingControllerProvider.notifier)
          .signInWithPassword(
              email: OnboardingFixtures.linkedSetupEmail,
              password: kMockFixturePassword);
      await settle(tester);
      expect(at(router), '/account-setup');
      router.go('/home');
      await settle(tester);
      expect(at(router), '/account-setup');
      expect(find.byType(MainShell), findsNothing);
    });

    testWidgets('sign-out from a holding screen ends the journey',
        (tester) async {
      final (container, router) = await boot(tester);
      await container
          .read(onboardingControllerProvider.notifier)
          .signInWithPassword(
              email: OnboardingFixtures.verifiedUnlinkedEmail,
              password: kMockFixturePassword);
      await settle(tester);
      expect(at(router), '/link-team');
      await container.read(signOutControllerProvider.notifier).signOut();
      await settle(tester);
      expect(container.read(authEntryStateProvider), const EntryNone());
      expect(at(router), '/login');
    });

    testWidgets('a signed-in tenant account cannot open the journey screens',
        (tester) async {
      final (_, router) =
          await boot(tester, session: const Success<AuthUser?>(_mainAdmin));
      for (final route in ['/verify-email', '/link-team', '/account-setup']) {
        router.go(route);
        await settle(tester);
        expect(at(router), '/home', reason: route);
      }
    });
  });
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 600));
  }
}

const _mainAdmin = AuthUser(
  id: 'u_main',
  name: 'مشرف',
  email: 'admin@mtm.org',
  role: AuthRole.mainAdmin,
  saasTenantId: 'saas_test',
  capabilities: Capabilities(global: Cap.all),
  orgName: 'MTM',
);

const _superAdmin = AuthUser(
  id: 'u_platform',
  name: 'مدير منصة',
  email: 'nullmod.dev@gmail.com',
  role: AuthRole.superAdmin,
  saasTenantId: null,
  capabilities: Capabilities.none,
  orgName: 'MTM',
);

/// Customer Demo is a full session with `demoMode`, its own role and no
/// SaasTenant. Both identity and access state must agree before it can open.
const _demo = AuthUser(
  id: 'u_demo',
  name: 'تجربة',
  email: 'demo@mtm.app',
  role: AuthRole.customerDemo,
  saasTenantId: null,
  capabilities: Capabilities.none,
  orgName: 'Demo',
);
