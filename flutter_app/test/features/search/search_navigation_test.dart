import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/demo_personas.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/detachment/presentation/detachment_detail_shell.dart';
import 'package:mtm/features/detachment/presentation/detachment_member_status_page.dart';
import 'package:mtm/features/detachment/presentation/tabs/detachment_shifts_tab.dart';
import 'package:mtm/features/detachment/presentation/tabs/detachment_team_tab.dart';
import 'package:mtm/features/search/domain/search_models.dart';
import 'package:mtm/features/search/presentation/global_search_page.dart';
import 'package:mtm/features/team/data/team_providers.dart';
import 'package:mtm/l10n/strings.dart';

/// Where a result goes, and what happens when it cannot go there.
///
/// Every destination asserted here is a surface that already existed before
/// Global Search did — the point of the test is that no new detail screen was
/// invented, and that a row whose record has gone fails as a sentence rather
/// than as a crash or an empty page.

const _mine = 'd_dam_central';
const _member = 'm1';
const _item = 'i1';

AuthUser _user(Capabilities caps) => AuthUser(
      id: 'u',
      name: 'مشرف',
      email: 'admin@mtm.org',
      role: AuthRole.mainAdmin,
      // Feature availability fails closed for an unknown tenant. Use the
      // canonical all-enabled developer tenant explicitly in this legacy
      // navigation harness instead of relying on the old implicit default.
      saasTenantId: kDemoSaasTenantId,
      capabilities: caps,
      orgName: 'MTM',
    );

final _full = _user(const Capabilities(global: Cap.all));

/// May see the detachment and move its stock, and nothing about its roster.
final _storekeeper = _user(const Capabilities(scoped: {
  _mine: {Cap.inventoryAdjust}
}));

void main() {
  group('the capability is re-asked at the moment of the tap', () {
    const member = MemberDestination(detachmentId: _mine, memberId: _member);
    const detachment = DetachmentDestination(detachmentId: _mine);
    const shift = ShiftDestination(detachmentId: _mine, shiftId: 'sh1');
    const item = InventoryDestination(detachmentId: _mine, itemId: _item);

    test(
        'a roster destination needs member.view, the rest need detachment.view',
        () {
      const roster = Capabilities(scoped: {
        _mine: {Cap.memberView}
      });
      const stock = Capabilities(scoped: {
        _mine: {Cap.inventoryAdjust}
      });

      expect(destinationAllowed(member, roster), isTrue);
      expect(destinationAllowed(member, stock), isFalse);
      // Any scoped grant implies `detachment.view`, so the other three open.
      for (final destination in [detachment, shift, item]) {
        expect(destinationAllowed(destination, stock), isTrue);
      }
    });

    test(
        'a grant that no longer covers the detachment closes every '
        'destination in it', () {
      const elsewhere = Capabilities(scoped: {
        'd_homs': {Cap.memberView}
      });
      for (final destination in [member, detachment, shift, item]) {
        expect(destinationAllowed(destination, elsewhere), isFalse);
      }
      for (final destination in [member, detachment, shift, item]) {
        expect(destinationAllowed(destination, Capabilities.none), isFalse);
      }
    });

    test('a detachment result opens the tab this session can actually reach',
        () {
      expect(
        detachmentTabFor(
          const Capabilities(scoped: {
            _mine: {Cap.memberView}
          }),
          _mine,
        ),
        'team',
      );
      // The roster route would refuse this session, so the row must not aim
      // at it — the schedule opens on `detachment.view` alone.
      expect(
        detachmentTabFor(
          const Capabilities(scoped: {
            _mine: {Cap.inventoryAdjust}
          }),
          _mine,
        ),
        'shifts',
      );
    });
  });

  group('a result opens the surface that already owns the record', () {
    testWidgets('a member opens the existing member page', (tester) async {
      await _search(tester, _full, 'كنعان');

      await tester.tap(find.byKey(const Key('search-result-$_member')));
      await _settle(tester);

      // The page the roster opens, not a copy of it made for search.
      expect(find.byType(DetachmentMemberStatusPage), findsOneWidget);
    });

    testWidgets('a detachment opens the existing detail shell', (tester) async {
      await _search(tester, _full, 'الشعلان');

      await tester.tap(find.byKey(const Key('search-result-$_mine')));
      await _settle(tester);

      expect(find.byType(DetachmentDetailShell), findsOneWidget);
      expect(find.byType(DetachmentTeamTab), findsOneWidget);
    });

    testWidgets('a detachment a storekeeper finds opens on the tab they hold',
        (tester) async {
      await _search(tester, _storekeeper, 'الشعلان');

      await tester.tap(find.byKey(const Key('search-result-$_mine')));
      await _settle(tester);

      // Not the roster tab: its route refuses a session without `member.view`,
      // and a row that bounced to `/home` would look like search being broken.
      expect(find.byType(DetachmentDetailShell), findsOneWidget);
      expect(find.byType(DetachmentShiftsTab), findsOneWidget);
      expect(find.byType(DetachmentTeamTab), findsNothing);
    });

    testWidgets('a shift opens the existing shift management sheet',
        (tester) async {
      await _search(tester, _full, 'المهاجرين');

      await tester.tap(find.byType(SearchResultRow).first);
      await _settle(tester);

      expect(find.textContaining(S.manageShiftTitle), findsOneWidget);
    });

    testWidgets('a stock item opens the existing item sheet', (tester) async {
      await _search(tester, _full, 'أدرينالين');

      await tester.tap(find.byKey(const Key('search-result-$_item')));
      await _settle(tester);

      // The sheet's own content, not the row that opened it.
      expect(find.textContaining(S.currentStock), findsOneWidget);
    });
  });

  testWidgets(
      'a result whose record was deleted after the search says so and '
      'goes nowhere', (tester) async {
    await _search(tester, _full, 'كنعان');
    final container = _containerOf(tester);

    // Deleted from another screen — or another device — while the results
    // were on screen. Pumped rather than awaited directly: the mock's latency
    // runs on the test binding's clock, so nothing resolves without a pump.
    final deleted = container.read(teamRepositoryProvider).delete(_member);
    await _settle(tester);
    await deleted;

    await tester.tap(find.byKey(const Key('search-result-$_member')));
    // Long enough for the re-read (260-580 ms) and short enough that the
    // snack bar has not timed itself out again.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text(S.globalSearchResultGone), findsOneWidget);
    expect(find.byType(DetachmentMemberStatusPage), findsNothing);

    // Let the invalidated index finish rebuilding before the test tears the
    // binding down, so no timer outlives it.
    await _settle(tester);
  });

  testWidgets(
      'a session with nothing searchable gets a restricted state, not '
      'an empty list', (tester) async {
    // A grant that is real but searches nothing: it may publish an
    // announcement and holds no detachment, member, statistics or workshop
    // key. Deliberately not `Capabilities.none` any more — since Point 3 an
    // *empty* grant is a startup state of its own (`/access-not-assigned`) and
    // never reaches a tenant screen, so it could not exercise this one.
    await _boot(
      tester,
      _user(const Capabilities(global: {Cap.announcementPublish})),
    );
    expect(find.byKey(const Key('search-restricted')), findsOneWidget);
    expect(find.byKey(const Key('global-search-field')), findsOneWidget);
  });

  testWidgets('a query below the floor is a state of its own, never a search',
      (tester) async {
    await _search(tester, _full, 'ك');
    expect(find.byKey(const Key('search-short-query')), findsOneWidget);
    expect(find.byKey(const Key('search-results')), findsNothing);
  });

  testWidgets('the dashboard offers exactly one way in', (tester) async {
    final router = await _boot(tester, _full);
    router.go('/home');
    await _settle(tester);

    expect(find.byKey(const Key('global-search-action')), findsOneWidget);
  });

  testWidgets('a session with nothing searchable is offered no magnifier',
      (tester) async {
    final router = await _boot(tester, _user(Capabilities.none));
    router.go('/home');
    await _settle(tester);

    expect(find.byKey(const Key('global-search-action')), findsNothing);
  });
}

// -----------------------------------------------------------------------------

ProviderContainer _containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
      listen: false,
    );

/// Boots the real router with a real session and lands on Global Search.
Future<GoRouter> _boot(WidgetTester tester, AuthUser user) async {
  // The same two pre-existing debug complaints the settings and auth-gate
  // suites already tolerate for this layout.
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
      currentUserResultProvider.overrideWith(
        (ref) async => Success<AuthUser?>(user),
      ),
      sessionsProvider.overrideWith(
        (ref) async => const Success<List<Session>>([]),
      ),
    ],
  );
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
  router.go(GlobalSearchPage.routePath);
  await _settle(tester);
  return router;
}

Future<GoRouter> _search(
  WidgetTester tester,
  AuthUser user,
  String query,
) async {
  final router = await _boot(tester, user);
  await tester.enterText(
    find.byKey(const Key('global-search-field')),
    query,
  );
  await _settle(tester);
  return router;
}

/// Bounded pumps rather than `pumpAndSettle`: the real router boots the real
/// screens, the mock repositories answer after a simulated 200–800 ms, and the
/// loading skeleton shimmers forever while they do.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 600));
  }
}
