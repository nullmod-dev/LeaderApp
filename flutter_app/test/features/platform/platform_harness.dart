import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/announcement/data/announcement_providers.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/demo_personas.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/detachment/data/detachment_providers.dart';
import 'package:mtm/features/detachment_group/data/detachment_group_providers.dart';
import 'package:mtm/features/home/data/home_providers.dart';
import 'package:mtm/features/inventory/data/inventory_providers.dart';
import 'package:mtm/features/notification/data/notification_providers.dart';
import 'package:mtm/features/shift/data/shift_providers.dart';
import 'package:mtm/features/team/data/team_providers.dart';
import 'package:mtm/features/workshop/data/workshop_providers.dart';

/// Booting the real app at the real router, for the Point 4 platform tests.
///
/// Shared by the three platform test files so they cannot drift about *how*
/// the surface is entered — every one of them goes in through
/// `appRouterProvider` and the startup classifier, never by pumping a screen
/// directly. A test that pumped `PlatformShell` on its own would pass while
/// the redirect that is supposed to protect it was broken.

/// The three real personas, so the tests assert against the accounts the app
/// actually ships rather than invented ones.
final superAdmin = DemoPersona.superAdmin.user;
final mainAdmin = DemoPersona.mainAdmin.user;
final simpleAdmin = DemoPersona.simpleAdmin.user;

/// A tenant account carrying every key — used where the point is that even the
/// strongest tenant session is refused the platform.
const fullTenantAdmin = AuthUser(
  id: 'u_tenant_full',
  name: 'مشرف',
  email: 'admin@mtm.org',
  role: AuthRole.mainAdmin,
  saasTenantId: 'saas_test',
  capabilities: Capabilities(global: Cap.all),
  orgName: 'MTM',
);

/// Records every tenant operational repository that was built.
///
/// The instrument behind `§16`: the platform shell must not *initialise* the
/// tenant data layer, and "did not render tenant widgets" is a weaker claim
/// than "never constructed the repository behind them". Riverpod builds a
/// `Provider` the first time it is read, so an empty list is proof that
/// nothing under `/platform` asked.
class TenantRepositoryWatch {
  final List<String> built = [];

  List<Override> get overrides => [
        // Each one throws as well as records: if a future change does read one
        // of these on the platform surface, the test does not merely fail an
        // assertion at the end — it fails loudly at the moment of the read,
        // with the stack that caused it.
        detachmentRepositoryProvider
            .overrideWith((ref) => _refuse('detachment')),
        detachmentGroupRepositoryProvider
            .overrideWith((ref) => _refuse('detachmentGroup')),
        teamRepositoryProvider.overrideWith((ref) => _refuse('team')),
        shiftRepositoryProvider.overrideWith((ref) => _refuse('shift')),
        inventoryRepositoryProvider.overrideWith((ref) => _refuse('inventory')),
        workshopRepositoryProvider.overrideWith((ref) => _refuse('workshop')),
        homeRepositoryProvider.overrideWith((ref) => _refuse('home')),
        announcementRepositoryProvider
            .overrideWith((ref) => _refuse('announcement')),
        notificationRepositoryProvider
            .overrideWith((ref) => _refuse('notification')),
      ];

  Never _refuse(String name) {
    built.add(name);
    throw StateError('tenant repository "$name" was built');
  }
}

/// A container holding [user] as the signed-in session.
ProviderContainer platformContainer(
  AuthUser? user, {
  TenantRepositoryWatch? watch,
  List<Override> overrides = const [],
}) {
  final container = ProviderContainer(overrides: [
    // Answered synchronously: these tests are about routing and layout, not
    // about the mock repository's simulated latency.
    currentUserResultProvider.overrideWith((ref) async => Success(user)),
    sessionsProvider.overrideWith(
      (ref) async => const Success<List<Session>>([]),
    ),
    ...?watch?.overrides,
    ...overrides,
  ]);
  addTearDown(container.dispose);
  return container;
}

/// Pumps the real app over [container] at a chosen size, direction and text
/// scale.
///
/// [width] and [height] are logical pixels — the unit the shell's breakpoint
/// is written in — so a test says «320 dp» and gets 320 dp.
Future<GoRouter> bootPlatform(
  WidgetTester tester,
  ProviderContainer container, {
  double width = 400,
  double height = 800,
  double textScale = 1,
  bool reduceMotion = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);

  final router = container.read(appRouterProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(PaletteId.medical),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          // The app is Arabic-first: every platform test runs in the layout
          // the product ships, not a mirrored afterthought.
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
  await settlePlatform(tester);
  return router;
}

/// Bounded pumps rather than `pumpAndSettle`: the shared Security screen boots
/// a mock repository behind a simulated delay, and `pumpAndSettle` would time
/// out on a screen that is legitimately still loading.
Future<void> settlePlatform(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 600));
  }
}

String locationOf(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

/// The pre-existing debug complaints the router tests already tolerate by
/// name. None comes from the platform surface; they are here so a platform
/// test booting the tenant app (to prove it is refused) does not fail on
/// somebody else's overflow.
void ignoreKnownTenantComplaints() {
  final inherited = FlutterError.onError;
  FlutterError.onError = (details) {
    final report = details.toString();
    if (report.contains('overflowed') &&
        (report.contains('glass_bottom_nav.dart') ||
            report.contains('login_page.dart'))) {
      return;
    }
    if (report.contains('ListTile background color or ink splashes')) return;
    inherited?.call(details);
  };
  addTearDown(() => FlutterError.onError = inherited);
}
