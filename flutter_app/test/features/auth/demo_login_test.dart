import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_guard.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/dev_test_credentials.dart';
import 'package:mtm/features/auth/data/demo_personas.dart';
import 'package:mtm/features/auth/data/demo_sign_in_controller.dart';
import 'package:mtm/features/auth/data/in_memory_demo_session_store.dart';
import 'package:mtm/features/auth/data/mock_auth_repository.dart';
import 'package:mtm/features/auth/data/mock_onboarding_repository.dart';
import 'package:mtm/features/auth/data/sign_out_controller.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/auth_repository.dart';
import 'package:mtm/features/auth/domain/demo_session_store.dart';
import 'package:mtm/features/auth/presentation/login_page.dart';
import 'package:mtm/features/platform/presentation/platform_shell.dart';
import 'package:mtm/l10n/strings.dart';

/// Point 2 — development demo accounts: how they are entered, what they
/// restore, and the guarantee that a release build has none of it.
///
/// The high-value questions, in the order they can go wrong:
///
/// 1. Does mock login still hand every input the same full administrator?
///    (It used to. That is the behaviour this point exists to end.)
/// 2. Does a selected persona survive a restart, and does sign-out actually
///    end it rather than leave it on file?
/// 3. Can a release configuration reach a demo persona — through the login
///    screen, through credentials, or through a record a debug build left on
///    the device?
///
/// A ProviderContainer built over the *same* store instance is an app
/// relaunch, the idiom `forced_upgrade_test.dart` established: the repository
/// is rebuilt (its in-memory session is gone) while the persisted record is
/// not.

/// `Result` has no value accessor — every caller in the app branches with
/// `when`. These tests only ever want "what came back, or null".
extension _ResultValue<T> on Result<T> {
  T? get valueOrNull => when(
        success: (data, {stale = false}) => data,
        failure: (_, __) => null,
        offline: (cached) => cached,
      );
}

/// A container wired to [store], in either configuration.
ProviderContainer _container(
  DemoSessionStore store, {
  bool demoAccounts = true,
}) {
  final container = ProviderContainer(overrides: [
    demoSessionStoreProvider.overrideWithValue(store),
    demoAccountsEnabledProvider.overrideWithValue(demoAccounts),
  ]);
  addTearDown(container.dispose);
  return container;
}

Future<AuthUser?> _session(ProviderContainer container) =>
    container.read(currentUserProvider.future);

void main() {
  group('the three device-test accounts map to their exact roles', () {
    // Pinned literally, because "every credential authenticates as its own
    // persona" — the group below — stays true even if two addresses swap
    // roles between them. These are the three addresses typed into a phone
    // during a device check, and this is the only place that states which
    // role each one must come back as. The passwords are read from the
    // table rather than repeated here.
    const expected = <String, AuthRole>{
      'nullmod.dev@gmail.com': AuthRole.superAdmin,
      'pbea4007@mtu.edu.iq': AuthRole.mainAdmin,
      'hamodekaherhm@gmail.com': AuthRole.admin,
    };

    test('each address authenticates as the role it is meant to be', () async {
      for (final entry in expected.entries) {
        final credential = DevTestCredentials.forEmail(entry.key);
        expect(credential, isNotNull, reason: entry.key);
        final repository =
            MockAuthRepository(demoSessions: InMemoryDemoSessionStore());
        final result = await repository.signIn(
          emailOrUsername: entry.key,
          password: credential!.password,
        );
        final user = result.valueOrNull;
        expect(user, isNotNull, reason: entry.key);
        expect(user!.email, entry.key);
        expect(user.role, entry.value, reason: entry.key);
      }
    });

    test('the tenant pair shares one SaasTenant and the owner has none', () {
      expect(DemoPersona.superAdmin.user.saasTenantId, isNull);
      expect(
        DemoPersona.mainAdmin.user.saasTenantId,
        DemoPersona.simpleAdmin.user.saasTenantId,
      );
      // The Simple Admin stays scoped. The restriction is the point of the
      // account, not an obstacle to testing with it.
      expect(
        DemoPersona.simpleAdmin.user.capabilities.global,
        isNot(contains(Cap.adminManage)),
      );
      expect(DemoPersona.mainAdmin.user.capabilities.global,
          contains(Cap.adminManage));
    });

    test('a wrong password is refused for every one of them', () async {
      for (final email in expected.keys) {
        final repository =
            MockAuthRepository(demoSessions: InMemoryDemoSessionStore());
        final result = await repository.signIn(
          emailOrUsername: email,
          password: 'not-the-development-password',
        );
        expect(result.isFailure, isTrue, reason: email);
        expect(
          await repository.currentUser().then((r) => r.valueOrNull),
          isNull,
          reason: email,
        );
      }
    });
  });

  group('mock credential sign-in no longer collapses to one account', () {
    test('each persona address authenticates as that exact account', () async {
      for (final credential in DevTestCredentials.values) {
        final persona = credential.persona;
        final repository =
            MockAuthRepository(demoSessions: InMemoryDemoSessionStore());
        final result = await repository.signIn(
          emailOrUsername: credential.email,
          password: credential.password,
        );
        final user = result.valueOrNull;
        expect(user, isNotNull, reason: persona.wire);
        expect(user!.id, persona.user.id);
        expect(user.role, persona.user.role);
        expect(user.saasTenantId, persona.user.saasTenantId);
      }
    });

    test('two different addresses do not produce the same account', () async {
      final repository =
          MockAuthRepository(demoSessions: InMemoryDemoSessionStore());
      final main = await repository.signIn(
        emailOrUsername: DevTestCredentials.mainAdmin.email,
        password: DevTestCredentials.mainAdmin.password,
      );
      final simple = await repository.signIn(
        emailOrUsername: DevTestCredentials.simpleAdmin.email,
        password: DevTestCredentials.simpleAdmin.password,
      );
      expect(main.valueOrNull!.id, isNot(simple.valueOrNull!.id));
      expect(
        main.valueOrNull!.capabilities,
        isNot(simple.valueOrNull!.capabilities),
      );
    });

    test('an arbitrary address is refused, not promoted', () async {
      // The old behaviour handed *anything* the full organisation-wide grant.
      // The one outcome that must never come back is an unknown credential
      // resolving to an administrator — least of all the platform owner.
      final repository =
          MockAuthRepository(demoSessions: InMemoryDemoSessionStore());
      final result = await repository.signIn(
        emailOrUsername: 'whoever@example.org',
        password: 'password',
      );
      expect(result.isFailure, isTrue);
      expect(result.valueOrNull, isNull);
      expect(await repository.currentUser().then((r) => r.valueOrNull), isNull);
    });

    test('the existing password rule is preserved', () async {
      final repository =
          MockAuthRepository(demoSessions: InMemoryDemoSessionStore());
      final result = await repository.signIn(
        emailOrUsername: DemoPersona.mainAdmin.user.email,
        password: 'abc',
      );
      expect(result.isFailure, isTrue);
    });

    test('a plausible but wrong development password is refused', () async {
      final repository =
          MockAuthRepository(demoSessions: InMemoryDemoSessionStore());
      final result = await repository.signIn(
        emailOrUsername: DevTestCredentials.mainAdmin.email,
        password: 'definitely-not-the-development-password',
      );
      expect(result.isFailure, isTrue);
      expect(await repository.currentUser().then((r) => r.valueOrNull), isNull);
    });
  });

  group('persona selection', () {
    test('selecting a persona returns that user and becomes the session',
        () async {
      for (final persona in DemoPersona.values) {
        final container = _container(InMemoryDemoSessionStore(seed: null));
        final result = await container
            .read(demoSignInControllerProvider.notifier)
            .signInAs(persona);

        expect(result!.valueOrNull!.id, persona.user.id, reason: persona.wire);
        // Not a parallel session: the app's own session provider is what
        // changed, which is what every capability check reads.
        expect((await _session(container))!.id, persona.user.id);
        expect(
          container.read(capabilitiesProvider),
          persona.user.capabilities,
        );
      }
    });

    test('Main Admin and Simple Admin produce different live grants', () async {
      final mainContainer = _container(InMemoryDemoSessionStore(seed: null));
      await mainContainer
          .read(demoSignInControllerProvider.notifier)
          .signInAs(DemoPersona.mainAdmin);
      await _session(mainContainer);

      final simpleContainer = _container(InMemoryDemoSessionStore(seed: null));
      await simpleContainer
          .read(demoSignInControllerProvider.notifier)
          .signInAs(DemoPersona.simpleAdmin);
      await _session(simpleContainer);

      // The difference a person can see: organisation editing, and how many
      // detachments the list will show.
      expect(mainContainer.read(adminViewProvider).isFull, isTrue);
      expect(simpleContainer.read(adminViewProvider).isFull, isFalse);
      expect(
        mainContainer.read(capabilitiesProvider).can(Cap.orgEdit),
        isTrue,
      );
      expect(
        simpleContainer.read(capabilitiesProvider).can(Cap.orgEdit),
        isFalse,
      );
      expect(
        simpleContainer.read(adminViewProvider).namedDetachmentIds,
        kDemoSimpleAdminDetachments,
      );
    });

    test('a second tap while one is running is dropped, not queued', () async {
      final container = _container(InMemoryDemoSessionStore(seed: null));
      final controller = container.read(demoSignInControllerProvider.notifier);
      final first = controller.signInAs(DemoPersona.mainAdmin);
      final second = controller.signInAs(DemoPersona.simpleAdmin);

      expect(await second, isNull, reason: 'the duplicate returns null');
      expect((await first)!.valueOrNull!.id, DemoPersona.mainAdmin.user.id);
      // And the dropped tap did not overwrite the session behind the first.
      expect((await _session(container))!.id, DemoPersona.mainAdmin.user.id);
    });
  });

  group('development session persistence', () {
    for (final persona in DemoPersona.values) {
      test('a selected ${persona.wire} survives a restart', () async {
        final store = InMemoryDemoSessionStore(seed: null);

        final first = _container(store);
        await first
            .read(demoSignInControllerProvider.notifier)
            .signInAs(persona);
        expect((await _session(first))!.id, persona.user.id);

        // Relaunch: a new container, and a new repository, over the record
        // the previous run left on the device.
        final second = _container(store);
        final restored = await _session(second);
        expect(restored, isNotNull);
        expect(restored!.id, persona.user.id);
        expect(restored.role, persona.user.role);
        expect(restored.saasTenantId, persona.user.saasTenantId);
      });
    }

    test('only the persona id is persisted, not the account', () async {
      final store = InMemoryDemoSessionStore(seed: null);
      final container = _container(store);
      await container
          .read(demoSignInControllerProvider.notifier)
          .signInAs(DemoPersona.simpleAdmin);

      // A capability set on disk would be a second source of truth for a
      // grant the fixture already states.
      expect(await store.read(), DemoPersona.simpleAdmin.wire);
    });

    test('a store naming no known persona restores nothing', () async {
      final container = _container(InMemoryDemoSessionStore(seed: null));
      expect(await _session(container), isNull);
    });
  });

  group('sign-out', () {
    test('sign-out clears the persona and the restart stays signed out',
        () async {
      final store = InMemoryDemoSessionStore(seed: null);
      final first = _container(store);
      await first
          .read(demoSignInControllerProvider.notifier)
          .signInAs(DemoPersona.simpleAdmin);
      expect((await _session(first))!.id, DemoPersona.simpleAdmin.user.id);

      // The ordinary sign-out — there is no demo-specific exit.
      final result =
          await first.read(signOutControllerProvider.notifier).signOut();
      expect(result!.isSuccess, isTrue);

      // Gone from this session…
      expect(await _session(first), isNull);
      expect(first.read(capabilitiesProvider), Capabilities.none);
      // …and off the device, so nothing restores it.
      expect(await store.read(), isNull);

      final second = _container(store);
      expect(await _session(second), isNull);
    });

    test('signing out of one persona does not enter another', () async {
      final store = InMemoryDemoSessionStore(seed: null);
      final container = _container(store);
      await container
          .read(demoSignInControllerProvider.notifier)
          .signInAs(DemoPersona.mainAdmin);
      await _session(container);
      await container.read(signOutControllerProvider.notifier).signOut();

      final after = await _session(container);
      expect(after, isNull);
      expect(container.read(authGateProvider), AuthGate.signedOut);
    });

    test('the seeded first-run device boots into the Main Admin persona',
        () async {
      // The mock has always come up signed in; that assumption now lives in
      // the store's seed rather than in a hard-coded session, which is what
      // lets sign-out survive a relaunch at all.
      final container = _container(InMemoryDemoSessionStore());
      final user = await _session(container);
      expect(user!.id, DemoPersona.mainAdmin.user.id);
      expect(user.role, AuthRole.mainAdmin);
    });
  });

  group('release configuration', () {
    test('a stored persona is refused, not restored', () async {
      // The scenario: a debug build ran on this device and left a record.
      final store = InMemoryDemoSessionStore(seed: DemoPersona.mainAdmin);
      final container = _container(store, demoAccounts: false);

      expect(await _session(container), isNull);
      expect(container.read(authGateProvider), AuthGate.signedOut);
      expect(container.read(capabilitiesProvider), Capabilities.none);
    });

    test('a demo credential is not a production auth fallback', () async {
      final repository = MockAuthRepository(
        demoSessions: InMemoryDemoSessionStore(seed: null),
        demoAccountsEnabled: false,
      );
      for (final credential in DevTestCredentials.values) {
        final result = await repository.signIn(
          emailOrUsername: credential.email,
          password: credential.password,
        );
        expect(result.isFailure, isTrue, reason: credential.persona.wire);
      }
      expect(await repository.currentUser().then((r) => r.valueOrNull), isNull);
    });

    test('persona selection itself is refused', () async {
      final container = _container(
        InMemoryDemoSessionStore(seed: null),
        demoAccounts: false,
      );
      final result = await container
          .read(demoSignInControllerProvider.notifier)
          .signInAs(DemoPersona.superAdmin);
      expect(result!.isFailure, isTrue);
      expect(await _session(container), isNull);
    });

    test('a build wired to a real repository has no persona path', () async {
      final container = ProviderContainer(overrides: [
        demoAccountsEnabledProvider.overrideWithValue(true),
        authRepositoryProvider.overrideWithValue(_NoDemoRepository()),
      ]);
      addTearDown(container.dispose);

      final result = await container
          .read(demoSignInControllerProvider.notifier)
          .signInAs(DemoPersona.mainAdmin);
      expect(result!.isFailure, isTrue);
    });

    test('the onboarding mock refuses dev credentials when its gate is off',
        () async {
      final repository = MockOnboardingRepository(
        clock: () => DateTime.utc(2026, 9, 13),
        enabled: false,
      );
      for (final credential in DevTestCredentials.values) {
        final result = await repository.signInWithPassword(
          email: credential.email,
          password: credential.password,
        );
        expect(result.isFailure, isTrue, reason: credential.persona.wire);
      }
    });
  });

  group('the login screen', () {
    testWidgets('has no persona shortcuts in a development configuration',
        (tester) async {
      await _pumpLogin(tester, demoAccounts: true);

      expect(find.text(S.demoAccountsTitle), findsNothing);
      expect(find.text(S.demoSuperAdmin), findsNothing);
      expect(find.text(S.demoMainAdmin), findsNothing);
      expect(find.text(S.demoSimpleAdmin), findsNothing);
      expect(find.text(S.signIn), findsOneWidget);
      expect(find.text(S.createAccount), findsOneWidget);
    });

    testWidgets('has no persona shortcuts in a release configuration',
        (tester) async {
      await _pumpLogin(tester, demoAccounts: false);

      expect(find.text(S.demoAccountsTitle), findsNothing);
      expect(find.text(S.demoSuperAdmin), findsNothing);
      expect(find.text(S.demoMainAdmin), findsNothing);
      expect(find.text(S.demoSimpleAdmin), findsNothing);
      expect(find.text(S.signIn), findsOneWidget);
    });

    for (final credential in DevTestCredentials.values) {
      testWidgets(
          'typed ${credential.persona.wire} credentials use normal Login',
          (tester) async {
        final (container, router) = await _pumpRoutedLogin(tester);
        await tester.enterText(_loginField(S.emailLabel), credential.email);
        await tester.enterText(
          _loginField(S.passwordLabel),
          credential.password,
        );
        // Login is a full-height screen; on the 800 x 600 test surface the
        // CTA sits below the fold, exactly as it would on a short phone.
        await tester.ensureVisible(find.text(S.signIn));
        await tester.pump();
        await tester.tap(find.text(S.signIn));
        await _settle(tester);

        final expectedLocation = credential.persona == DemoPersona.superAdmin
            ? PlatformShell.location
            : '/home';
        expect(_at(router), expectedLocation);
        expect(
          container.read(currentUserProvider).valueOrNull?.id,
          credential.user.id,
        );
        expect(
          container.read(capabilitiesProvider),
          credential.user.capabilities,
        );
      });
    }
  });
}

String _at(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

/// Login labels its fields above the input rather than inside the
/// decoration, so match either shape: the `AuthScaffold` screens still use
/// `labelText`, Login uses [LoginField.keyFor].
Finder _loginField(String label) => find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          (widget.decoration?.labelText == label ||
              widget.key == LoginField.keyFor(label)),
    );

Future<(ProviderContainer, GoRouter)> _pumpRoutedLogin(
  WidgetTester tester,
) async {
  final ignore = _ignoreKnownPreexistingComplaints();
  addTearDown(ignore);
  tester.view.physicalSize = const Size(1080, 3600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: [
    demoAccountsEnabledProvider.overrideWithValue(true),
    demoSessionStoreProvider
        .overrideWithValue(InMemoryDemoSessionStore(seed: null)),
  ]);
  addTearDown(container.dispose);
  final router = container.read(appRouterProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(PaletteId.medical),
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await _settle(tester);
  expect(_at(router), '/login');
  return (container, router);
}

/// Bounded pumps: the real screens boot behind the router and their mock
/// repositories answer after a simulated 400–800 ms.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 600));
  }
}

/// The pre-existing debug complaints the other router tests tolerate by name:
/// the floating bottom nav on a narrow test surface and `ListTile` inside a
/// decorated settings card. Returns the tear-down that restores the handler.
void Function() _ignoreKnownPreexistingComplaints() {
  final inherited = FlutterError.onError;
  FlutterError.onError = (details) {
    final report = details.toString();
    if (report.contains('overflowed') &&
        report.contains('glass_bottom_nav.dart')) {
      return;
    }
    if (report.contains('ListTile background color or ink splashes')) return;
    inherited?.call(details);
  };
  return () => FlutterError.onError = inherited;
}

Future<void> _pumpLogin(
  WidgetTester tester, {
  required bool demoAccounts,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        demoAccountsEnabledProvider.overrideWithValue(demoAccounts),
        demoSessionStoreProvider
            .overrideWithValue(InMemoryDemoSessionStore(seed: null)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(PaletteId.medical),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const Directionality(
            textDirection: TextDirection.rtl,
            child: LoginPage(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// A repository with no demo accounts — what a shipping build wires in.
class _NoDemoRepository implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}
