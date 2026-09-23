import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/widgets/offline_banner.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/domain/admin_account.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/auth_repository.dart';
import 'package:mtm/features/auth/presentation/session_expired_page.dart';
import 'package:mtm/features/settings/presentation/profile_page.dart';
import 'package:mtm/l10n/strings.dart';

import '../../entry_settle.dart';
import 'package:mtm/main.dart';

/// Point 5 — the administrator's own account screen.
///
/// The visible layout is Ahmed's to inspect. What is tested here is what a
/// person cannot see by looking: that the fields come from the authenticated
/// account and nothing is invented for a missing one, that the capability
/// summary follows the grant rather than a role label, that a session which
/// fails or expires is not rendered as an account, and — the part that has to
/// be right — that sign-out fires once, clears the session, and leaves no
/// protected screen reachable behind it.

const _full = AuthUser(
  id: 'u_1',
  name: 'ليلى ياسين',
  email: 'l.yaseen@mtm.org',
  role: AuthRole.mainAdmin,
  saasTenantId: 'saas_test',
  capabilities: Capabilities(global: Cap.all),
  orgName: 'فريق الإسعاف التطوعي · دمشق',
  avatarInitials: 'لي',
);

/// A sub-admin: everything they hold is inside one detachment, and neither
/// administration key is among it. `avatarInitials` is absent — the field is
/// optional on the wire, and this is the account that proves nothing is
/// invented to fill it.
const _scoped = AuthUser(
  id: 'u_2',
  name: 'سامر الحلبي',
  email: 's.halabi@mtm.org',
  // A Simple Admin: `admin` is the role, and it carries the *same*
  // `saasTenantId` as `_full` above — two administrators of one customer.
  role: AuthRole.admin,
  saasTenantId: 'saas_test',
  capabilities: Capabilities(scoped: {'d1': Cap.scoped}),
  orgName: 'فريق الإسعاف التطوعي · دمشق',
);

class _FakeAuth implements AuthRepository {
  _FakeAuth({
    this.me = const Success<AuthUser?>(_full),
    this.signOutResult = const Success<void>(null),
    this.signOutDelay = Duration.zero,
  });

  Result<AuthUser?> me;
  Result<void> signOutResult;
  Duration signOutDelay;
  int signOutCalls = 0;

  @override
  Future<Result<AuthUser?>> currentUser() async => me;

  @override
  Future<Result<void>> signOut() async {
    signOutCalls++;
    if (signOutDelay > Duration.zero) await Future<void>.delayed(signOutDelay);
    if (signOutResult.isSuccess) me = const Success<AuthUser?>(null);
    return signOutResult;
  }

  @override
  Future<Result<List<Session>>> listSessions() async =>
      const Success(<Session>[]);

  @override
  Future<Result<void>> revokeSession(String id) async => const Success(null);

  @override
  Future<Result<AuthUser>> signIn({
    required String emailOrUsername,
    required String password,
  }) async =>
      const Success(_full);

  @override
  Future<Result<MfaSetupData>> beginMfaSetup() async =>
      const Success(MfaSetupData(
        otpauthUrl: '',
        manualSecret: '',
        backupCodes: [],
      ));

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
}

/// The account screen on its own — enough for everything that does not
/// navigate.
Future<void> _pumpProfile(
  WidgetTester tester, {
  required Result<AuthUser?> me,
}) async {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  _ignoreKnownPreexistingComplaints();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuth(me: me)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: ProfilePage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The real app, for anything that has to prove where navigation ends up.
/// The two debug complaints `settings_hub_test.dart` already tolerates, for
/// the same reason: both predate this work — the hub's rows and the floating
/// nav have been built this way since Point 1 — and neither is in scope here.
void _ignoreKnownPreexistingComplaints() {
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
  addTearDown(() => FlutterError.onError = inherited);
}

Future<(GoRouter, ProviderContainer)> _boot(
  WidgetTester tester,
  _FakeAuth auth, {
  String at = '/more/profile',
}) async {
  _ignoreKnownPreexistingComplaints();

  // 540 x 1800 logical. Wide enough that the login screen this test lands on
  // lays out — its "request access" row overflows a 360-wide phone, which is
  // a pre-existing login-screen layout bug and not this screen's to fix.
  tester.view.physicalSize = const Size(1080, 3600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(auth)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MtmApp()),
  );
  await tester.pumpAndSettle();
  final router = container.read(appRouterProvider);
  router.go(at);
  await tester.pumpAndSettle();
  return (router, container);
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

/// The account screen's own sign-out button.
///
/// It sits below the fold on a phone, and a `ListView` only builds what is
/// near the viewport — so it has to be scrolled to before it exists to tap.
Finder _signOutButton() => find.widgetWithText(OutlinedButton, S.signOut);

Future<void> _revealSignOut(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    _signOutButton(),
    240,
    scrollable: find
        .descendant(
          of: find.byType(ProfilePage),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

/// Taps sign-out and confirms the dialog.
Future<void> _signOut(WidgetTester tester) async {
  await _revealSignOut(tester);
  await tester.tap(_signOutButton());
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, S.signOut));
}

void main() {
  group('the grant, summarised', () {
    test('reads the capability set, never a role name', () {
      // Full organisation-wide grant — what a main admin actually holds.
      final full = AdminAccountSummary.of(const Capabilities(global: Cap.all));
      expect(full.level, AdminAccessLevel.full);
      expect(full.managesAdmins, isTrue);
      expect(full.editsOrganisation, isTrue);

      // Everything inside one detachment, neither administration key.
      final scoped = AdminAccountSummary.of(
          const Capabilities(scoped: {'d1': Cap.scoped}));
      expect(scoped.level, AdminAccessLevel.detachmentScoped);
      expect(scoped.managesAdmins, isFalse);
      expect(scoped.detachmentCount, 1);

      // Some org-level keys, but not all of them.
      final partial = AdminAccountSummary.of(
        const Capabilities(global: {Cap.workshopCreate}),
      );
      expect(partial.level, AdminAccessLevel.organisation);
      expect(partial.managesAdmins, isFalse);

      // Signed in, granted nothing. A real state, not an error.
      expect(
        AdminAccountSummary.of(Capabilities.none).level,
        AdminAccessLevel.none,
      );
    });
  });

  testWidgets('shows the authenticated account, and only its real fields',
      (tester) async {
    await _pumpProfile(tester, me: const Success<AuthUser?>(_full));

    expect(find.text(_full.name), findsOneWidget);
    expect(find.text(_full.email), findsOneWidget);
    expect(find.text(_full.orgName), findsOneWidget);
    expect(find.text(_full.avatarInitials!), findsOneWidget);
    // A full grant, said as a grant.
    expect(find.text(S.profileAccessFull), findsWidgets);
    expect(find.text(S.profileScopeOrgWide), findsOneWidget);
    // Read-only, and it says so rather than hiding the absent edit action.
    expect(find.text(S.profileReadOnlyNote), findsOneWidget);
    // Nothing member-shaped leaked in from the Members module.
    expect(find.text(S.detachmentTeam), findsNothing);
  });

  // Point 2 — the account's product surface is now on the payload, so the
  // screen states it instead of leaving the reader to infer a rank from the
  // capability rows. The two must not be confused: a Main Admin whose grant
  // was narrowed is still a Main Admin.
  testWidgets('a Main Admin is named as one, not as a Simple Admin',
      (tester) async {
    await _pumpProfile(tester, me: const Success<AuthUser?>(_full));

    expect(find.text(S.profileRole), findsOneWidget);
    expect(find.text(S.roleMainAdmin), findsOneWidget);
    expect(find.text(S.roleSimpleAdmin), findsNothing);
    expect(find.text(S.roleSuperAdmin), findsNothing);
  });

  testWidgets('a Simple Admin is named as one, not as a Main Admin',
      (tester) async {
    await _pumpProfile(tester, me: const Success<AuthUser?>(_scoped));

    expect(find.text(S.roleSimpleAdmin), findsOneWidget);
    expect(find.text(S.roleMainAdmin), findsNothing);
    // And its narrowed grant is still reported truthfully alongside.
    expect(find.text(S.profileAccessScoped), findsWidgets);
  });

  testWidgets('a missing avatar is a glyph, never invented initials',
      (tester) async {
    await _pumpProfile(tester, me: const Success<AuthUser?>(_scoped));

    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
    // The old screen fell back to the app's own name as the initials.
    expect(find.text(S.appName), findsNothing);
  });

  testWidgets('a detachment-scoped admin is not shown as an organisation one',
      (tester) async {
    await _pumpProfile(tester, me: const Success<AuthUser?>(_scoped));

    expect(find.text(S.profileAccessScoped), findsWidgets);
    expect(find.text(S.profileAccessFull), findsNothing);
    expect(find.text(S.profileScopeOneDetachment), findsOneWidget);
    // Both administration keys are withheld, and both say so.
    expect(find.text(S.profileNotGranted), findsNWidgets(2));
    expect(find.text(S.profileGranted), findsNothing);
  });

  testWidgets('no session is an empty state, not a blank account',
      (tester) async {
    await _pumpProfile(tester, me: const Success<AuthUser?>(null));

    expect(find.text(S.profileNoSession), findsOneWidget);
    expect(find.text(_full.name), findsNothing);
  });

  testWidgets('offline renders the cached account, marked as cached',
      (tester) async {
    await _pumpProfile(tester, me: const Offline<AuthUser?>(cached: _full));

    expect(find.text(_full.name), findsOneWidget);
    expect(find.byType(StaleBadge), findsOneWidget);
  });

  testWidgets('offline with nothing cached shows the offline state',
      (tester) async {
    await _pumpProfile(tester, me: const Offline<AuthUser?>());

    expect(find.text(S.noCachedCopy), findsOneWidget);
    expect(find.text(_full.name), findsNothing);
  });

  testWidgets('a session that expires while the screen is open leaves it',
      (tester) async {
    final auth = _FakeAuth();
    final (router, container) = await _boot(tester, auth);
    expect(_location(router), '/more/profile');

    // The next read of the session comes back expired.
    auth.me = const Failure<AuthUser?>(
      'token expired',
      code: 'authentication_expired',
    );
    container.invalidate(currentUserResultProvider);
    await tester.pumpAndSettle();

    expect(find.byType(SessionExpiredPage), findsOneWidget);
    expect(_location(router), '/session-expired');
  });

  testWidgets('signing out leaves for login and shuts the protected routes',
      (tester) async {
    final auth = _FakeAuth();
    final (router, _) = await _boot(tester, auth);

    await _signOut(tester);
    // Bounded: the screen this lands on is the entry surface, which loops an
    // ambient pulse for as long as it is up.
    await settleEntry(tester);

    expect(auth.signOutCalls, 1);
    expect(_location(router), '/login');

    // The account screen was on a preserved bottom-nav branch stack a moment
    // ago. Going back to it must not open it.
    router.go('/more/profile');
    await settleEntry(tester);
    expect(_location(router), '/login');
    expect(find.byType(ProfilePage), findsNothing);

    // Nor may any other protected surface be reached.
    router.go('/detachment/d1/team');
    await settleEntry(tester);
    expect(_location(router), '/login');
  });

  testWidgets('a failed sign-out keeps the session and says so',
      (tester) async {
    final auth = _FakeAuth(
      signOutResult: const Failure<void>('boom', code: 'server'),
    );
    final (router, _) = await _boot(tester, auth);

    await _signOut(tester);
    await tester.pumpAndSettle();

    expect(auth.signOutCalls, 1);
    expect(_location(router), '/more/profile');
    expect(find.byType(SnackBar), findsOneWidget);
    // The app's own copy for the code, never the server's string.
    expect(find.text('boom'), findsNothing);
  });

  testWidgets('a second tap during sign-out does not fire a second request',
      (tester) async {
    final auth = _FakeAuth(signOutDelay: const Duration(milliseconds: 500));
    final (router, _) = await _boot(tester, auth);

    await _signOut(tester);
    // Mid-flight: the request is out, the answer has not come back.
    await tester.pump(const Duration(milliseconds: 50));

    // The button is inert while the request is in flight, and tapping it
    // again is dropped by the controller rather than queued.
    expect(tester.widget<OutlinedButton>(_signOutButton()).onPressed, isNull);
    await tester.tap(_signOutButton(), warnIfMissed: false);
    await tester.pump();

    // Let the one request that was actually made come back.
    await tester.pump(const Duration(seconds: 1));
    await settleEntry(tester);
    expect(auth.signOutCalls, 1);
    expect(_location(router), '/login');
  });
}
