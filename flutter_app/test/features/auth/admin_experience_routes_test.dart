import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_presets.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/startup/startup_destination.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/widgets/glass_bottom_nav.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/demo_personas.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/l10n/strings.dart';

/// The half of the admin split a person cannot check by looking: that hiding a
/// destination is not what keeps a session out of it.
///
/// Every case below asks the router directly, the way a deep link, a restored
/// navigation stack or a `context.go` from an alert would. What the two
/// dashboards *look* like is Ahmed's to inspect; what is tested here is that
/// the scoped experience cannot be typed around.

/// The seeded detachment the scoped admin is granted.
const _mine = 'd_dam_central';

/// A seeded detachment they are not.
const _theirs = 'd_homs';

AuthUser _user(Capabilities caps) => AuthUser(
      id: 'u',
      name: 'مشرف',
      email: 'admin@mtm.org',
      role: AuthRole.mainAdmin,
      saasTenantId: kDemoSaasTenantId,
      capabilities: caps,
      orgName: 'MTM',
    );

/// Every key, organisation-wide — the main admin the mock issues.
final _full = _user(const Capabilities(global: Cap.all));

/// A sub-Admin over exactly one detachment, from the shipped preset.
final _scoped =
    _user(CapabilityPreset.subAdmin.grant(detachments: const [_mine]));

/// Signed in and granted nothing. A real state: an account created and not yet
/// given anything.
final _bare = _user(Capabilities.none);

void main() {
  group('a scoped admin cannot deep-link past the destinations it is not shown',
      () {
    for (final entry in const {
      // The container hierarchy: organisation-level, so it is not refused
      // outright but redirected to the detachments that are actually theirs.
      '/detachment-groups': '/detachment',
      '/detachment-groups/new': '/detachment',
      '/detachment-groups/t_damascus': '/detachment',
      '/detachment-groups/t_damascus/edit': '/detachment',
      '/detachment-groups/t_damascus/detachment/new': '/detachment',
      // (Point 15: `/more/organization` and `/more/plan` are no longer
      // here. Both roles read them; the organisation-wide usage figures are
      // withheld by the read itself — `organization_plan_access_test.dart`.)
      // Lifecycle acts a sub-Admin deliberately does not hold.
      '/detachment/$_mine/edit': '/home',
      // Another detachment entirely — nothing in it is theirs to open.
      '/detachment/$_theirs/team': '/home',
      '/detachment/$_theirs/shifts': '/home',
      '/detachment/$_theirs/storage': '/home',
      '/detachment/$_theirs/stats': '/home',
      '/detachment/$_theirs/member/new': '/home',
      '/detachment/$_theirs/report': '/home',
    }.entries) {
      testWidgets('${entry.key} lands on ${entry.value}', (tester) async {
        final router = await _boot(tester, _scoped);
        router.go(entry.key);
        await _settle(tester);
        expect(_at(router), entry.value);
      });
    }
  });

  group('a scoped admin still reaches everything genuinely granted', () {
    for (final location in [
      '/home',
      '/detachment',
      '/detachment/$_mine/team',
      '/detachment/$_mine/shifts',
      '/detachment/$_mine/storage',
      '/detachment/$_mine/stats',
      '/detachment/$_mine/member/new',
      '/detachment/$_mine/storage/new',
      '/detachment/$_mine/report',
      '/more',
      '/more/profile',
      '/more/security',
      '/more/sync',
      '/more/themes',
      '/more/notifications',
      // Their own queued writes, which are theirs whatever else they hold.
      '/needs-review',
      '/notifications',
    ]) {
      testWidgets('$location opens', (tester) async {
        final router = await _boot(tester, _scoped);
        router.go(location);
        await _settle(tester);
        expect(_at(router), location);
      });
    }
  });

  group('a main admin reaches the organisation-level destinations', () {
    for (final location in [
      '/detachment-groups',
      '/detachment-groups/new',
      '/detachment-groups/t_damascus',
      '/detachment-groups/t_damascus/edit',
      '/more/organization',
      '/more/plan',
      '/detachment/$_mine/edit',
      '/detachment/$_theirs/team',
      '/detachment/$_theirs/report',
      '/workshop/new',
    ]) {
      testWidgets('$location opens', (tester) async {
        final router = await _boot(tester, _full);
        router.go(location);
        await _settle(tester);
        expect(_at(router), location);
      });
    }
  });

  testWidgets('a session granted nothing is refused every gated destination',
      (tester) async {
    // Signed in, so the gate is not "unknown" — it has a real answer and the
    // answer is no. Nothing here may fail open.
    final router = await _boot(tester, _bare);
    for (final location in [
      '/detachment/$_mine/team',
      '/detachment/$_mine/shifts',
      '/detachment/$_mine/report',
      '/detachment/$_mine/storage/new',
    ]) {
      router.go(location);
      await _settle(tester);
      expect(_at(router), isNot(location), reason: '$location opened');
    }
  });

  testWidgets('inventory item management is a separate key from adjusting',
      (tester) async {
    // §11: "do not assume every Simple Admin can edit inventory". A medic who
    // logs movements does not get the item form, and the store itself stays
    // open to them.
    final router = await _boot(
      tester,
      _user(const Capabilities(scoped: {
        _mine: {Cap.inventoryAdjust}
      })),
    );

    router.go('/detachment/$_mine/storage');
    await _settle(tester);
    expect(_at(router), '/detachment/$_mine/storage');

    router.go('/detachment/$_mine/storage/new');
    await _settle(tester);
    expect(_at(router), '/home');
  });

  testWidgets('the export composer rests on statistics and nothing weaker',
      (tester) async {
    // The domain has no separate export capability, so a report is gated on
    // the statistics key it is a file of. What must not happen is a report
    // opening for a session that may run the detachment but not read its
    // numbers.
    final operator = await _boot(
      tester,
      _user(const Capabilities(scoped: {
        _mine: {Cap.shiftManage, Cap.memberView, Cap.inventoryAdjust}
      })),
    );
    operator.go('/detachment/$_mine/report');
    await _settle(tester);
    expect(_at(operator), '/home');
  });

  testWidgets('a grant that narrows mid-session closes the route behind it',
      (tester) async {
    final session = _Session(_full);
    final router = await _boot(tester, null, session: session);

    const location = '/detachment/$_mine/edit';
    router.go(location);
    await _settle(tester);
    expect(_at(router), location);

    session.user = _scoped;
    session.container!.invalidate(currentUserResultProvider);
    await _settle(tester);

    // The screen it is standing on is gone, and it cannot be asked for again.
    expect(_at(router), isNot(location));
    router.go(location);
    await _settle(tester);
    expect(_at(router), '/home');
  });

  group('navigation and settings adapt to the experience', () {
    testWidgets('a main admin is offered the container hierarchy and workshops',
        (tester) async {
      await _boot(tester, _full);
      final labels = _navLabels(tester);
      expect(
          labels, [S.navHome, S.navDetachmentGroups, S.navWorkshop, S.navMore]);
    });

    testWidgets(
        'a scoped admin without workshop work loses the workshops tab and '
        'is named for the list it actually opens', (tester) async {
      await _boot(
        tester,
        _user(const Capabilities(scoped: {_mine: Cap.scoped})),
      );
      final labels = _navLabels(tester);
      expect(labels, [S.navHome, S.detachmentListTitle, S.navMore]);
      expect(labels, isNot(contains(S.navWorkshop)));
    });

    testWidgets('a scoped admin with workshop work keeps the workshops tab',
        (tester) async {
      await _boot(tester, _scoped);
      expect(_navLabels(tester), contains(S.navWorkshop));
    });

    // Organization remains the context door for both roles; Plan is reached
    // from there, while Settings exposes one subscription/pricing row.
    testWidgets('a main admin has organization and one pricing destination',
        (tester) async {
      final full = await _boot(tester, _full);
      full.go('/more');
      await _settle(tester);
      expect(find.byKey(const Key('settings-org-row')), findsOneWidget);
      expect(find.byKey(const Key('settings-pricing-row')), findsOneWidget);
      expect(find.byKey(const Key('settings-plan-row')), findsNothing);
    });

    testWidgets('a scoped admin has organization and one pricing destination',
        (tester) async {
      final router = await _boot(tester, _scoped);
      router.go('/more');
      await _settle(tester);
      expect(find.byKey(const Key('settings-org-row')), findsOneWidget);
      expect(find.byKey(const Key('settings-pricing-row')), findsOneWidget);
      expect(find.byKey(const Key('settings-plan-row')), findsNothing);
    });
  });

  // Point 1 renamed the local grouping concept from "tenant" to
  // DetachmentGroup and moved its routes to `/detachment-groups`. The old
  // paths survive as redirect-only routes so a link written before the rename
  // still lands somewhere real — and, crucially, lands where the *canonical*
  // route would have sent the same session, guard included.
  group('the legacy tenant routes redirect onto the canonical ones', () {
    for (final entry in const {
      '/tenant': '/detachment-groups',
      '/tenant/new': '/detachment-groups/new',
      '/tenant/t_damascus': '/detachment-groups/t_damascus',
      '/tenant/t_damascus/edit': '/detachment-groups/t_damascus/edit',
      '/tenant/t_damascus/detachment/new':
          '/detachment-groups/t_damascus/detachment/new',
    }.entries) {
      testWidgets('${entry.key} lands on ${entry.value}', (tester) async {
        final router = await _boot(tester, _full);
        router.go(entry.key);
        await _settle(tester);
        expect(_at(router), entry.value);
      });
    }

    testWidgets('a scoped admin is still sent past them to its detachments',
        (tester) async {
      // The redirect is a rewrite, not a way around the guard: the capability
      // check on the canonical route runs afterwards and answers the same.
      final router = await _boot(tester, _scoped);
      for (final location in _legacyTenantPaths) {
        router.go(location);
        await _settle(tester);
        expect(_at(router), '/detachment', reason: '$location opened');
      }
    });

    testWidgets('none of them loops', (tester) async {
      // A redirect that pointed back into `/tenant` would exhaust go_router's
      // redirect limit and throw rather than navigate. Walking every legacy
      // path in one session is the cheapest proof that none does.
      final router = await _boot(tester, _full);
      for (final location in _legacyTenantPaths) {
        router.go(location);
        await _settle(tester);
        expect(_at(router), startsWith('/detachment-groups'));
      }
    });
  });

  // The announcement routes span detachments rather than living inside one, so
  // they are guarded on `announcement.publish` held **anywhere**. Asking the
  // organisation-wide question instead would have refused exactly the person
  // the key was granted to.
  group('the announcement routes are guarded on the key held anywhere', () {
    /// The sub-Admin preset deliberately withholds `announcement.publish`
    /// (`CAPABILITIES.md` §10): a key added after a preset was written is
    /// granted by nobody until somebody grants it.
    testWidgets('a sub-Admin without the key is refused both routes',
        (tester) async {
      final router = await _boot(tester, _scoped);
      for (final location in ['/announcements', '/announcements/new']) {
        router.go(location);
        await _settle(tester);
        expect(_at(router), '/home', reason: '$location opened');
      }
    });

    testWidgets('a scoped admin granted the key in one detachment gets in',
        (tester) async {
      final router = await _boot(
        tester,
        _user(const Capabilities(scoped: {
          _mine: {Cap.detachmentView, Cap.announcementPublish}
        })),
      );
      for (final location in ['/announcements', '/announcements/new']) {
        router.go(location);
        await _settle(tester);
        expect(_at(router), location);
      }
    });

    testWidgets('a main admin gets in', (tester) async {
      final router = await _boot(tester, _full);
      router.go('/announcements');
      await _settle(tester);
      expect(_at(router), '/announcements');
    });

    testWidgets('a session granted nothing is refused', (tester) async {
      final router = await _boot(tester, _bare);
      router.go('/announcements/new');
      await _settle(tester);
      // Since Point 3 an empty grant is a startup state of its own: the
      // session never enters the tenant application at all, so the refusal
      // lands on the designed «no access assigned» screen instead of the
      // dashboard. Still a refusal, and still route-level — see
      // `core/startup/startup_destination.dart`.
      expect(_at(router), StartupDestination.tenantNoAccess.location);
    });

    testWidgets('revoking the key mid-session closes the route behind it',
        (tester) async {
      final session = _Session(_user(const Capabilities(scoped: {
        _mine: {Cap.detachmentView, Cap.announcementPublish}
      })));
      final router = await _boot(tester, null, session: session);

      router.go('/announcements');
      await _settle(tester);
      expect(_at(router), '/announcements');

      session.user = _scoped;
      session.container!.invalidate(currentUserResultProvider);
      await _settle(tester);

      expect(_at(router), isNot('/announcements'));
      router.go('/announcements');
      await _settle(tester);
      expect(_at(router), '/home');
    });
  });
}

// -----------------------------------------------------------------------------

/// Every pre-rename location the redirect table covers.
const _legacyTenantPaths = <String>[
  '/tenant',
  '/tenant/new',
  '/tenant/t_damascus',
  '/tenant/t_damascus/edit',
  '/tenant/t_damascus/detachment/new',
];

String _at(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

List<String> _navLabels(WidgetTester tester) => tester
    .widget<GlassBottomNav>(find.byType(GlassBottomNav))
    .destinations
    .map((d) => d.label)
    .toList();

/// A session answer a test can change mid-flight.
class _Session {
  _Session(this.user);
  AuthUser user;
  ProviderContainer? container;
}

Future<GoRouter> _boot(
  WidgetTester tester,
  AuthUser? user, {
  _Session? session,
}) async {
  // The same two pre-existing debug complaints the settings and auth-gate
  // suites already tolerate for this layout: the floating bottom nav
  // overflowing a narrow test surface, and `ListTile` inside a decorated
  // settings card. Neither predates nor concerns this file.
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

  tester.view.physicalSize = const Size(1080, 3600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      // Answered without the mock repository's simulated latency: these tests
      // are about the redirect, not about loading.
      currentUserResultProvider.overrideWith(
        (ref) async => Success<AuthUser?>(session?.user ?? user!),
      ),
      sessionsProvider.overrideWith(
        (ref) async => const Success<List<Session>>([]),
      ),
    ],
  );
  addTearDown(container.dispose);
  session?.container = container;

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
  return router;
}

/// Bounded pumps rather than `pumpAndSettle`: the real router boots the real
/// screens, and the mock repositories behind them answer after a simulated
/// 400–800 ms, chained.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 600));
  }
}
