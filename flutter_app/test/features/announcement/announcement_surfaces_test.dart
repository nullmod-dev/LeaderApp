import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/auth/data/demo_personas.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';

/// Every surface Point 14 adds, opened against the **shipped mock fixtures**,
/// in RTL, at a real phone width.
///
/// This is the "I must be able to open it and look at it" rule turned into a
/// test. Each case asserts only that the surface reaches its populated state —
/// not what it looks like, which is Ahmed's to inspect — and any layout
/// overflow inside one of them fails the test rather than waiting to be seen on
/// a device. The fixtures in `MockAnnouncementRepository` are what make that
/// possible: a seeded announcement per state, so none of these screens is empty
/// in a development build.

/// The dashboard resolves its detachment deterministically: the first by name,
/// which in the shipped mock is the coast («مفرزة الساحل» sorts before حمص,
/// دمشق and ريف). Seed `a_seed_7` addresses it and is Home-placed inside its
/// first hour, which is why the promoted card is visible on open.
const _defaultDetachment = 'd_coast';

/// The detachment the multi-target and detachment-placed seeds address.
const _damascus = 'd_dam_central';

const _mainAdmin = AuthUser(
  id: 'u',
  name: 'أحمد عبد الكريم',
  email: 'admin@mtm.org',
  role: AuthRole.mainAdmin,
  saasTenantId: kDemoSaasTenantId,
  capabilities: Capabilities(global: Cap.all),
  orgName: 'MTM',
);

void main() {
  testWidgets('the dashboard shows the promoted announcement on open',
      (tester) async {
    await _boot(tester);
    // One card, from a seed published twelve minutes ago — inside its hour.
    expect(find.byKey(const Key('home-announcement')), findsOneWidget);
    // Exactly one promotion for this detachment, so no "and N others" line.
    expect(find.byKey(const Key('home-announcement-more')), findsNothing);
  });

  testWidgets('the detachment surface shows its own placed announcement',
      (tester) async {
    final router = await _boot(tester);
    router.go('/detachment/$_damascus/shifts');
    await _settle(tester);
    expect(find.byKey(const Key('detachment-announcement')), findsOneWidget);
  });

  testWidgets('a detachment with no placed announcement shows no strip',
      (tester) async {
    final router = await _boot(tester);
    // The coast's seed is Home-placed only, so the strip must not appear.
    router.go('/detachment/$_defaultDetachment/shifts');
    await _settle(tester);
    expect(find.byKey(const Key('detachment-announcement')), findsNothing);
  });

  testWidgets(
      'the Notifications Center lists the announcement and offers '
      'the clear action', (tester) async {
    final router = await _boot(tester);
    router.go('/notifications');
    await _settle(tester);

    expect(
      find.byKey(const Key('notification-announcement:a_seed_7')),
      findsOneWidget,
    );
    // There is announcement history to clear, so the action is offered.
    expect(find.byKey(const Key('notifications-clear')), findsOneWidget);
  });

  testWidgets('the management list opens populated', (tester) async {
    final router = await _boot(tester);
    router.go('/announcements');
    await _settle(tester);

    expect(find.byKey(const Key('announcements-list')), findsOneWidget);
    expect(find.byKey(const Key('announcements-empty')), findsNothing);
    // The active seed offers a withdraw control; the expired one does not.
    expect(
      find.byKey(const Key('announcement-withdraw-a_seed_5')),
      findsNothing,
    );
  });

  testWidgets('the compose form opens with one detachment already selected',
      (tester) async {
    final router = await _boot(tester);
    router.go('/announcements/new');
    await _settle(tester);

    expect(find.byKey(const Key('announcement-text-field')), findsOneWidget);
    // One target by default — never all of them, never none.
    expect(
      find.byKey(const Key('announcement-target-$_defaultDetachment')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('announcement-add-target')), findsOneWidget);
    expect(
      find.byKey(const Key('announcement-placement-home')),
      findsOneWidget,
    );

    // The rest of the form is below the fold on a phone, which is itself worth
    // knowing: scrolling to the publish button is what a person does.
    await tester.scrollUntilVisible(
      find.byKey(const Key('announcement-publish')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.byKey(const Key('announcement-publish')), findsOneWidget);
    // A finite lifetime is preselected, so the shortest publish is "type and
    // press".
    expect(
      find.byKey(const Key('announcement-expiry-preview')),
      findsOneWidget,
    );
  });
}

// -----------------------------------------------------------------------------

Future<GoRouter> _boot(WidgetTester tester) async {
  // The two pre-existing debug complaints the router suites already tolerate
  // for this layout. Anything else — including an overflow inside one of the
  // announcement surfaces — still fails the test.
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

  // A real phone, not the 800×600 default: a narrow surface is where an
  // Arabic label and a chip stop fitting beside each other.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: [
    currentUserResultProvider
        .overrideWith((ref) async => const Success<AuthUser?>(_mainAdmin)),
    sessionsProvider
        .overrideWith((ref) async => const Success<List<Session>>([])),
  ]);
  addTearDown(container.dispose);

  final router = container.read(appRouterProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(PaletteId.teal),
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await _settle(tester);
  return router;
}

/// Bounded pumps rather than `pumpAndSettle`: the real mock repositories answer
/// after a simulated delay, chained, and the dashboard's announcement card
/// schedules a timer for the end of its promotion — which `pumpAndSettle` would
/// wait an hour for.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 600));
  }
}
