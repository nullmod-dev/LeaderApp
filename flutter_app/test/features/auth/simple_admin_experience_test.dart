import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/admin_experience.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_presets.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/core/problem/problem.dart';
import 'package:mtm/core/problem/problem_presentation.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/widgets/animated_tab_bar.dart';
import 'package:mtm/core/widgets/glass_bottom_nav.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/demo_personas.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/session_access.dart';
import 'package:mtm/features/detachment/data/detachment_providers.dart';
import 'package:mtm/features/detachment/domain/detachment_tabs.dart';
import 'package:mtm/features/detachment/presentation/detachment_edit_page.dart';
import 'package:mtm/features/detachment/presentation/tabs/detachment_shifts_tab.dart';
import 'package:mtm/features/detachment/presentation/tabs/detachment_team_tab.dart';
import 'package:mtm/features/inventory/presentation/inventory_item_edit_page.dart';
import 'package:mtm/features/notification/domain/notification_models.dart';
import 'package:mtm/features/notification/domain/notification_selectors.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/platform/data/tenant_lifecycle_providers.dart';
import 'package:mtm/features/platform/presentation/platform_shell.dart';
import 'package:mtm/features/search/data/search_providers.dart';
import 'package:mtm/features/search/domain/search_models.dart';
import 'package:mtm/features/shell/main_shell.dart';
import 'package:mtm/features/tenant_feature/data/tenant_feature_providers.dart';
import 'package:mtm/features/tenant_feature/domain/tenant_feature_models.dart';
import 'package:mtm/features/tenant_feature/presentation/feature_disabled_page.dart';
import 'package:mtm/l10n/strings.dart';

import '../platform/platform_harness.dart';

/// POINT 16 — the Simple Admin experience, audited from the account's side.
///
/// Every account here is `role: admin` (the Simple Admin surface) unless a
/// test says otherwise, and every one enters through the real router and the
/// startup classifier — never by pumping a screen. The fixtures are a compact
/// capability matrix (§40), built from the keys `capability.dart` actually
/// defines; none is invented for the test.
///
/// What this file proves is the order the product rests on: session → account
/// → tenant lifecycle → surface → Feature Flag → capability → plan limit. Role
/// only chooses the surface; inside it, two accounts holding the same keys are
/// shown the same thing whatever their role (§41).

/// A detachment every fixture below is granted.
const _mine = 'd_dam_central';
const _mineName = 'مفرزة دمشق المركزية';

/// One no fixture is granted.
const _theirs = 'd_coast';

AuthUser _simple(Capabilities caps, {AuthRole role = AuthRole.admin}) =>
    AuthUser(
      id: 'u_simple_fixture',
      name: 'مشرف مساعد',
      email: 'simple@mtm.org',
      role: role,
      saasTenantId: kDemoSaasTenantId,
      capabilities: caps,
      orgName: 'MTM',
    );

Capabilities _in(Set<String> keys) => Capabilities(scoped: {_mine: keys});

/// A. Minimal — sees one detachment, holds nothing else.
final _minimal = _simple(_in(const {Cap.detachmentView}));

/// B. Operations — runs the schedule and the roster, nothing else.
final _operations = _simple(_in(const {
  Cap.detachmentView,
  Cap.memberView,
  Cap.shiftManage,
  Cap.shiftAssign,
  Cap.shiftAttendanceRecord,
}));

/// C. Inventory — the store, both keys, and no roster.
final _inventory = _simple(_in(const {
  Cap.detachmentView,
  Cap.inventoryAdjust,
  Cap.inventoryItemManage,
}));

/// D. Reports — reads the numbers, changes nothing.
final _reports = _simple(_in(const {Cap.detachmentView, Cap.statsView}));

/// E. Broad — the shipped sub-Admin preset plus `announcement.publish`, which
/// every preset withholds until someone grants it (`CAPABILITIES.md` §10).
final _broad = _simple(() {
  final preset = CapabilityPreset.subAdmin.grant(detachments: const [_mine]);
  return preset.copyWith(scoped: {
    _mine: {...preset.scoped[_mine]!, Cap.announcementPublish},
  });
}());

/// The session a test can change mid-flight: the account, its lifecycle
/// envelope, or an expired authentication.
class _Session {
  _Session(this.user);
  AuthUser user;
  SessionAccess access = SessionAccess.normal;
  bool expired = false;
}

Future<(ProviderContainer, GoRouter)> _boot(
  WidgetTester tester,
  AuthUser user, {
  _Session? session,
  Set<TenantFeatureKey> disabled = const {},
  // Wide by default: these are routing and visibility checks, and flutter_test
  // draws every glyph as a full-em square, which makes some pre-existing rows
  // overflow at phone widths. The layout group below sets 320/390 itself.
  double width = 800,
  double textScale = 1,
}) async {
  ignoreKnownTenantComplaints();
  final s = session ?? _Session(user);
  final container = ProviderContainer(overrides: [
    currentUserResultProvider.overrideWith((ref) async => s.expired
        ? const Failure<AuthUser?>('gone', code: 'authentication_expired')
        : Success<AuthUser?>(s.user)),
    // The composed envelope the classifier actually reads. (Under the mock
    // auth repository it re-derives tenant status from the canonical store,
    // so overriding the raw `sessionAccessProvider` would be overwritten.)
    effectiveSessionAccessProvider.overrideWith((ref) => s.access),
    sessionsProvider.overrideWith(
      (ref) async => const Success<List<Session>>([]),
    ),
  ]);
  addTearDown(container.dispose);

  // Deterministic modules: all four on, then the ones the test turns off.
  final store = container.read(platformTenantStoreProvider);
  for (final key in TenantFeatureKey.values) {
    store.updateFeature(kDemoSaasTenantId, key, !disabled.contains(key));
  }
  container.read(tenantFeatureRevisionProvider.notifier).changed();

  final router = await bootPlatform(
    tester,
    container,
    width: width,
    height: 1400,
    textScale: textScale,
  );
  return (container, router);
}

Future<void> _settle(WidgetTester tester) => settlePlatform(tester);

/// Visits every location and records where the router actually left it.
///
/// A redirect is decided synchronously inside `go`, so a hop only has to
/// outlast the page transition (so two shells are never mounted at once) to
/// read where the router landed. The screens' mock reads are left to the one
/// full settle at the end, which is what keeps a thirty-route walk from
/// costing minutes of rendering.
Future<Map<String, String>> _walk(
  WidgetTester tester,
  GoRouter router,
  Iterable<String> locations,
) async {
  final landed = <String, String>{};
  for (final location in locations) {
    router.go(location);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    landed[location] = locationOf(router);
  }
  await _settle(tester);
  return landed;
}

/// Unmounts the app and runs the fake clock past every mock latency and
/// promotion timer, for a test that booted more than one app.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(hours: 2));
}

T _data<T>(Result<T> result) => result.when(
      success: (data, {stale = false}) => data,
      failure: (message, _) => throw StateError(message),
      offline: (cached) => cached ?? (throw StateError('offline')),
    );

List<String> _tabs(WidgetTester tester) =>
    tester.widget<AnimatedTabBar>(find.byType(AnimatedTabBar)).tabs;

List<String> _nav(WidgetTester tester) => tester
    .widget<GlassBottomNav>(find.byType(GlassBottomNav))
    .destinations
    .map((d) => d.label)
    .toList();

void main() {
  // ---------------------------------------------------------------------------
  // §12 / §56 — the control plane is not reachable from the Simple Admin
  // surface, by any path.
  // ---------------------------------------------------------------------------
  group('Super Admin isolation', () {
    const t = kDemoSaasTenantId;
    const platform = [
      '/platform',
      '/platform/tenants',
      '/platform/tenants/new',
      '/platform/tenants/$t',
      '/platform/tenants/$t/subscription',
      '/platform/tenants/$t/limits',
      '/platform/tenants/$t/features',
      '/platform/tenants/$t/main-admin',
      '/platform/tenants/$t/main-admin/replace',
      '/platform/operations',
      '/platform/health',
      '/platform/alerts',
      '/platform/audit',
      '/platform/access',
      '/platform/access/request',
      '/platform/reports',
      '/platform/reports/usage_limits',
      '/platform/more',
      '/platform/more/profile',
    ];

    for (final (label, user) in [
      ('the Simple Admin persona', simpleAdmin),
      ('the broadest Simple Admin fixture', _broad),
    ]) {
      testWidgets('$label is turned around from every /platform path',
          (tester) async {
        final (_, router) = await _boot(tester, user);
        final landed = await _walk(tester, router, platform);
        for (final entry in landed.entries) {
          expect(entry.value, '/home', reason: '${entry.key} was not refused');
        }
        expect(find.byType(PlatformShell), findsNothing);
        expect(find.byType(MainShell), findsOneWidget);
      });
    }
  });

  // ---------------------------------------------------------------------------
  // §8 / §37 — the route inventory, by capability fixture. Deep links, not
  // taps: a hidden row is decluttering, the guard is the gate.
  // ---------------------------------------------------------------------------
  group('direct routes follow the grant, fixture by fixture', () {
    const always = {
      '/home': '/home',
      '/detachment': '/detachment',
      '/detachment/$_mine/shifts': '/detachment/$_mine/shifts',
      '/detachment/$_mine/storage': '/detachment/$_mine/storage',
      // The statistics route opens on `detachment.view` and renders its own
      // permission state; it is the *tab* that is withheld (below).
      '/detachment/$_mine/stats': '/detachment/$_mine/stats',
      '/more': '/more',
      '/more/profile': '/more/profile',
      '/more/security': '/more/security',
      '/more/sync': '/more/sync',
      '/more/notifications': '/more/notifications',
      '/more/organization': '/more/organization',
      '/more/plan': '/more/plan',
      '/more/org': '/more/organization',
      '/notifications': '/notifications',
      '/needs-review': '/needs-review',
      '/search': '/search',
      // Never a Simple Admin's without `detachment.create`.
      '/detachment-groups': '/detachment',
      '/detachment-groups/new': '/detachment',
      // Another detachment: nothing in it is theirs.
      '/detachment/$_theirs/shifts': '/home',
      '/detachment/$_theirs/team': '/home',
      '/detachment/$_theirs/storage': '/home',
      // Lifecycle acts no fixture holds.
      '/detachment/$_mine/edit': '/home',
    };

    final cases = <String, (AuthUser, Map<String, String>)>{
      'A minimal': (
        _minimal,
        {
          '/detachment/$_mine/team': '/home',
          '/detachment/$_mine/member/new': '/home',
          '/detachment/$_mine/storage/new': '/home',
          '/detachment/$_mine/report': '/home',
          // go_router runs the parent `report` guard for the child route.
          '/detachment/$_mine/report/preview': '/home',
          '/announcements': '/home',
          '/announcements/new': '/home',
          '/workshop/new': '/workshop',
        },
      ),
      'B operations': (
        _operations,
        {
          '/detachment/$_mine/team': '/detachment/$_mine/team',
          '/detachment/$_mine/member/new': '/home',
          '/detachment/$_mine/storage/new': '/home',
          '/detachment/$_mine/report': '/home',
          '/announcements': '/home',
        },
      ),
      'C inventory': (
        _inventory,
        {
          '/detachment/$_mine/team': '/home',
          '/detachment/$_mine/storage/new': '/detachment/$_mine/storage/new',
          '/detachment/$_mine/report': '/home',
        },
      ),
      'D reports': (
        _reports,
        {
          '/detachment/$_mine/team': '/home',
          '/detachment/$_mine/report': '/detachment/$_mine/report',
          '/detachment/$_mine/report/preview':
              '/detachment/$_mine/report/preview',
          '/detachment/$_mine/storage/new': '/home',
        },
      ),
      'E broad': (
        _broad,
        {
          '/detachment/$_mine/team': '/detachment/$_mine/team',
          '/detachment/$_mine/member/new': '/detachment/$_mine/member/new',
          '/detachment/$_mine/storage/new': '/detachment/$_mine/storage/new',
          '/detachment/$_mine/report': '/detachment/$_mine/report',
          '/announcements': '/announcements',
          '/announcements/new': '/announcements/new',
          '/workshop/new': '/workshop/new',
        },
      ),
    };

    for (final MapEntry(key: name, value: (user, extra)) in cases.entries) {
      testWidgets(name, (tester) async {
        final (_, router) = await _boot(tester, user);
        final expected = {...always, ...extra};
        final landed = await _walk(tester, router, expected.keys);
        for (final entry in expected.entries) {
          expect(landed[entry.key], entry.value, reason: entry.key);
        }
      });
    }
  });

  // ---------------------------------------------------------------------------
  // §9 / §36 — what is offered matches what opens. The two High findings.
  // ---------------------------------------------------------------------------
  group('navigation offers only what the grant opens', () {
    testWidgets(
        'H1: a Simple Admin without member.view opens their detachment on '
        'the schedule, not on a roster that bounces them to Home',
        (tester) async {
      final (_, router) = await _boot(tester, _minimal);
      router.go('/detachment');
      await _settle(tester);
      await tester.tap(find.text(_mineName));
      await _settle(tester);
      // The card *pushes*, so the delegate's base location is still the
      // list; what matters is which tab mounted — and that nothing bounced.
      expect(find.byType(DetachmentShiftsTab), findsOneWidget);
      expect(find.byType(DetachmentTeamTab), findsNothing);
      expect(locationOf(router), isNot('/home'));
      expect(_tabs(tester), [S.detachmentShifts, S.detachmentStorage]);
    });

    testWidgets('with member.view the same card opens the roster',
        (tester) async {
      final (_, router) = await _boot(tester, _operations);
      router.go('/detachment');
      await _settle(tester);
      await tester.tap(find.text(_mineName));
      await _settle(tester);
      expect(find.byType(DetachmentTeamTab), findsOneWidget);
    });

    testWidgets('the tab bar follows the grant, fixture by fixture',
        (tester) async {
      final expected = <AuthUser, List<String>>{
        _minimal: [S.detachmentShifts, S.detachmentStorage],
        _operations: [
          S.detachmentTeam,
          S.detachmentShifts,
          S.detachmentStorage,
        ],
        _reports: [S.detachmentShifts, S.detachmentStorage, S.detachmentStats],
        _broad: [
          S.detachmentTeam,
          S.detachmentShifts,
          S.detachmentStorage,
          S.detachmentStats,
        ],
      };
      for (final entry in expected.entries) {
        final (_, router) = await _boot(tester, entry.key);
        router.go('/detachment/$_mine/shifts');
        await _settle(tester);
        expect(_tabs(tester), entry.value);
      }
      await _finish(tester);
    });

    testWidgets(
        'M1: a direct stats link without stats.view keeps its tab and says '
        'permission, never "no statistics yet"', (tester) async {
      final (_, router) = await _boot(tester, _operations);
      router.go('/detachment/$_mine/stats');
      await _settle(tester);
      expect(locationOf(router), '/detachment/$_mine/stats');
      expect(
        find.byKey(const Key('detachment-stats-not-permitted')),
        findsOneWidget,
      );
      expect(find.text(S.statsNotPermittedTitle), findsOneWidget);
      expect(find.text(S.noStatsSub), findsNothing);
      // The bar still has the tab the session is standing on, selected.
      final bar = tester.widget<AnimatedTabBar>(find.byType(AnimatedTabBar));
      expect(bar.tabs[bar.currentIndex], S.detachmentStats);
    });

    testWidgets('the workshops tab appears only with workshop work',
        (tester) async {
      await _boot(tester, _minimal);
      expect(_nav(tester), [S.navHome, S.detachmentListTitle, S.navMore]);
      await _boot(tester, _broad);
      expect(_nav(tester),
          [S.navHome, S.detachmentListTitle, S.navWorkshop, S.navMore]);
      await _finish(tester);
    });

    testWidgets('Home quick actions are exactly the reachable ones',
        (tester) async {
      const all = [
        'dashboard-action-shifts',
        'dashboard-action-members',
        'dashboard-action-storage',
        'dashboard-action-stats',
        'dashboard-action-announcements',
        'dashboard-action-detachments',
        'dashboard-action-org',
      ];
      final expected = <AuthUser, Set<String>>{
        _minimal: {'dashboard-action-shifts', 'dashboard-action-storage'},
        _broad: {
          'dashboard-action-shifts',
          'dashboard-action-members',
          'dashboard-action-storage',
          'dashboard-action-stats',
          'dashboard-action-announcements',
        },
      };
      for (final entry in expected.entries) {
        final (_, router) = await _boot(tester, entry.key);
        router.go('/home');
        await _settle(tester);
        for (final key in all) {
          expect(
            find.byKey(Key(key)),
            entry.value.contains(key) ? findsOneWidget : findsNothing,
            reason: key,
          );
        }
        // No organisation-wide section for a scoped session.
        expect(find.byKey(const Key('dashboard-organisation')), findsNothing);
      }
      await _finish(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // §15 / §56 — a missing mutation key closes the mutation, not only the door.
  // ---------------------------------------------------------------------------
  group('mutation UX follows the key that authorizes it', () {
    testWidgets(
        'H2: detachment.archive without detachment.edit changes status '
        'only — details stay read-only and a save cannot rename',
        (tester) async {
      final archiver = _simple(_in(const {
        Cap.detachmentView,
        Cap.detachmentArchive,
      }));
      final (container, router) = await _boot(tester, archiver);
      router.go('/detachment');
      await _settle(tester);
      router.push('/detachment/$_mine/edit');
      await _settle(tester);
      expect(find.byType(DetachmentEditPage), findsOneWidget);
      expect(
        find.byKey(const Key('detachment-status-only-note')),
        findsOneWidget,
      );
      final fields = tester.widgetList<TextFormField>(
        find.descendant(
          of: find.byType(DetachmentEditPage),
          matching: find.byType(TextFormField),
        ),
      );
      expect(fields, isNotEmpty);
      expect(fields.every((f) => f.enabled == false), isTrue);

      // Someone else renames the detachment while the form is open. A
      // status-only save must not write the stale seeded name back.
      final repo = container.read(detachmentRepositoryProvider);
      // Real time, not fake: the mock repository answers after a delay.
      await tester.runAsync(() async {
        final current = _data(await repo.byId(_mine));
        await repo.update(current.copyWith(name: 'اسم جديد من جهاز آخر'));
      });

      await tester.ensureVisible(find.widgetWithText(FilledButton, S.save));
      await tester.tap(find.widgetWithText(FilledButton, S.save));
      await _settle(tester);
      final saved =
          await tester.runAsync(() async => _data(await repo.byId(_mine)));
      expect(saved!.name, 'اسم جديد من جهاز آخر');
    });

    testWidgets('with detachment.edit the details are editable, no note',
        (tester) async {
      final editor = _simple(_in(const {
        Cap.detachmentView,
        Cap.detachmentEdit,
      }));
      final (_, router) = await _boot(tester, editor);
      router.go('/detachment');
      await _settle(tester);
      router.push('/detachment/$_mine/edit');
      await _settle(tester);
      expect(
        find.byKey(const Key('detachment-status-only-note')),
        findsNothing,
      );
      final fields = tester.widgetList<TextFormField>(
        find.descendant(
          of: find.byType(DetachmentEditPage),
          matching: find.byType(TextFormField),
        ),
      );
      expect(fields.every((f) => f.enabled != false), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // §14 / §56 — a disabled module cannot be reached by any door, whatever the
  // grant.
  // ---------------------------------------------------------------------------
  group('Feature Flags fail closed for a Simple Admin', () {
    testWidgets('every module route lands on the feature-disabled state',
        (tester) async {
      final (_, router) = await _boot(
        tester,
        _broad,
        disabled: TenantFeatureKey.values.toSet(),
      );
      for (final location in [
        '/detachment/$_mine/storage',
        '/detachment/$_mine/storage/new',
        '/detachment/$_mine/stats',
        '/detachment/$_mine/report',
        '/workshop',
        '/workshop/new',
        '/announcements',
        '/announcements/new',
      ]) {
        router.go(location);
        await _settle(tester);
        expect(locationOf(router), FeatureDisabledPage.routePath,
            reason: location);
        expect(find.byType(FeatureDisabledPage), findsOneWidget);
      }
      // The core schedule is not a module and stays open.
      router.go('/detachment/$_mine/shifts');
      await _settle(tester);
      expect(locationOf(router), '/detachment/$_mine/shifts');
      expect(_tabs(tester), [S.detachmentTeam, S.detachmentShifts]);
    });

    testWidgets(
        'M2: notification preferences offer no switch for a disabled module',
        (tester) async {
      final (_, router) = await _boot(
        tester,
        _broad,
        disabled: const {
          TenantFeatureKey.inventory,
          TenantFeatureKey.workshops
        },
      );
      router.go('/more/notifications');
      await _settle(tester);
      expect(find.byKey(const Key('notif-pref-shifts')), findsOneWidget);
      expect(find.byKey(const Key('notif-pref-joins')), findsOneWidget);
      expect(find.byKey(const Key('notif-pref-stock')), findsNothing);
      expect(find.byKey(const Key('notif-pref-workshops')), findsNothing);
      expect(find.text(S.notifStockAlerts), findsNothing);
    });

    testWidgets('with the modules on, both switches are back', (tester) async {
      final (_, router) = await _boot(tester, _broad);
      router.go('/more/notifications');
      await _settle(tester);
      expect(find.byKey(const Key('notif-pref-stock')), findsOneWidget);
      expect(find.byKey(const Key('notif-pref-workshops')), findsOneWidget);
    });

    testWidgets('search offers no inventory category while it is off',
        (tester) async {
      final (container, _) = await _boot(
        tester,
        _broad,
        disabled: const {TenantFeatureKey.inventory},
      );
      expect(
        container.read(searchableCategoriesProvider),
        isNot(contains(AdminDataCategory.inventory)),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // §16 / §35 / §56 — three different refusals, three different sentences.
  // ---------------------------------------------------------------------------
  group('M3: plan limit, feature and permission are distinct refusals', () {
    final permission = resolveProblem(Problem.fromJson(const {
      'code': 'not_permitted',
    }));
    final limit = resolveProblem(Problem.fromJson(const {
      'code': 'plan_limit_reached',
      'detail': 'Limit exceeded: members 40/40',
    }));
    final feature = resolveProblem(Problem.fromJson(const {
      'error': {'code': 'feature_disabled', 'message': 'FEATURE_OFF'},
    }));

    test('the wire codes are recognised, not fallen back', () {
      expect(ProblemCode.parse('plan_limit_reached'),
          ProblemCode.planLimitReached);
      expect(
          ProblemCode.parse('feature_disabled'), ProblemCode.featureDisabled);
      expect(limit, isNot(ProblemView.fallback));
      expect(feature, isNot(ProblemView.fallback));
    });

    test('each has its own title and sentence', () {
      expect({permission.title, limit.title, feature.title}, hasLength(3));
      expect(
          {permission.message, limit.message, feature.message}, hasLength(3));
      expect(limit.message, S.errPlanLimit);
      expect(feature.message, S.errFeatureDisabled);
    });

    test('neither organisation-wide refusal blames the account', () {
      for (final view in [limit, feature]) {
        expect(view.title, isNot(contains('صلاحية')));
        expect(view.message, isNot(contains('صلاحية')));
      }
    });

    test('none is retryable, and no server text leaks', () {
      for (final view in [permission, limit, feature]) {
        expect(view.retryable, isFalse);
      }
      expect(limit.message, isNot(contains('Limit exceeded')));
      expect(feature.message, isNot(contains('FEATURE_OFF')));
    });
  });

  // ---------------------------------------------------------------------------
  // §17 / §18 / §38 / §56 — lifecycle and session close the operational app,
  // and no old stack brings it back.
  // ---------------------------------------------------------------------------
  group('lifecycle and session outrank every grant', () {
    for (final (status, location) in [
      (SaasTenantStatus.suspended, '/tenant-suspended'),
      (SaasTenantStatus.deletionPending, '/tenant-deletion-pending'),
      (SaasTenantStatus.deleted, '/tenant-deleted'),
    ]) {
      testWidgets('tenant ${status.name} closes an open detachment',
          (tester) async {
        final session = _Session(_broad);
        final (container, router) =
            await _boot(tester, _broad, session: session);
        router.go('/detachment/$_mine/team');
        await _settle(tester);
        expect(locationOf(router), '/detachment/$_mine/team');

        session.access = SessionAccess(tenant: status);
        container.invalidate(effectiveSessionAccessProvider);
        await _settle(tester);
        expect(locationOf(router), location);
        expect(find.byType(MainShell), findsNothing);

        // Deep links, a notification's destination, a search result's
        // destination and Back all meet the same wall.
        for (final attempt in [
          '/detachment/$_mine/team',
          '/detachment/$_mine/storage',
          '/notifications',
          '/search',
          '/more/organization',
        ]) {
          router.go(attempt);
          await _settle(tester);
          expect(locationOf(router), location, reason: attempt);
        }
        expect(router.canPop(), isFalse);
      });
    }

    testWidgets('an expired session closes the operational app',
        (tester) async {
      final session = _Session(_broad);
      final (container, router) = await _boot(tester, _broad, session: session);
      router.go('/detachment/$_mine/storage');
      await _settle(tester);
      expect(find.byType(MainShell), findsOneWidget);

      session.expired = true;
      container.invalidate(currentUserResultProvider);
      await _settle(tester);
      expect(locationOf(router), '/session-expired');
      expect(find.byType(MainShell), findsNothing);

      router.go('/detachment/$_mine/storage');
      await _settle(tester);
      expect(locationOf(router), '/session-expired');
    });

    testWidgets(
        'a key revoked under an open form closes it, and Back cannot '
        'bring it back', (tester) async {
      final session = _Session(_inventory);
      final (container, router) =
          await _boot(tester, _inventory, session: session);
      router.go('/detachment/$_mine/storage');
      await _settle(tester);
      router.push('/detachment/$_mine/storage/new');
      await _settle(tester);
      expect(find.byType(InventoryItemEditPage), findsOneWidget);

      session.user = _simple(_in(const {
        Cap.detachmentView,
        Cap.inventoryAdjust,
      }));
      container.invalidate(currentUserResultProvider);
      await _settle(tester);
      expect(find.byType(InventoryItemEditPage), findsNothing);

      if (router.canPop()) {
        router.pop();
        await _settle(tester);
      }
      expect(find.byType(InventoryItemEditPage), findsNothing);
      router.go('/detachment/$_mine/storage/new');
      await _settle(tester);
      expect(locationOf(router), '/home');
    });
  });

  // ---------------------------------------------------------------------------
  // §27 / §28 / §56 — a notification or a search result is never a way round
  // the grant. Pure: these are the functions both screens resolve through.
  // ---------------------------------------------------------------------------
  group('notifications and search cannot bypass the grant', () {
    final now = DateTime.utc(2026, 9, 12, 9);
    AppNotification stock(String detachmentId) => AppNotification(
          id: 'stockLow:i_$detachmentId',
          kind: NotificationKind.stockLow,
          occurredAt: now,
          target: StorageTarget(detachmentId: detachmentId, itemId: 'i_1'),
        );
    AppNotification shift(String detachmentId) => AppNotification(
          id: 'shiftUnderstaffed:s_$detachmentId',
          kind: NotificationKind.shiftUnderstaffed,
          occurredAt: now,
          target: ShiftTarget(detachmentId: detachmentId, shiftId: 's_1'),
        );

    test('stock rows need an inventory key; shift rows a shift key', () {
      final feed = [stock(_mine), shift(_mine)];
      List<NotificationKind> kinds(AuthUser user) => [
            for (final n in visibleNotifications(
              feed,
              detachmentId: _mine,
              capabilities: user.capabilities,
            ))
              n.kind,
          ];
      expect(kinds(_minimal), isEmpty);
      expect(kinds(_operations), [NotificationKind.shiftUnderstaffed]);
      expect(kinds(_inventory), [NotificationKind.stockLow]);
    });

    test('a row pointing into another detachment is dropped', () {
      final rows = visibleNotifications(
        [stock(_theirs), shift(_theirs)],
        detachmentId: _mine,
        capabilities: _broad.capabilities,
      );
      expect(rows, isEmpty);
    });

    test(
        'a shift row degrades to the schedule for a session that cannot '
        'act on it', () {
      final destination = destinationFor(shift(_mine), _minimal.capabilities);
      expect(destination, isA<OpenDetachmentTab>());
      expect((destination as OpenDetachmentTab).tab, 'shifts');
      expect(destinationFor(shift(_mine), _operations.capabilities),
          isA<OpenShiftSheet>());
    });

    test('search re-asks the grant at the tap, in the record\'s detachment',
        () {
      const member = MemberDestination(detachmentId: _mine, memberId: 'm_1');
      const theirs = MemberDestination(detachmentId: _theirs, memberId: 'm_2');
      expect(destinationAllowed(member, _minimal.capabilities), isFalse);
      expect(destinationAllowed(member, _operations.capabilities), isTrue);
      expect(destinationAllowed(theirs, _broad.capabilities), isFalse);
      const item = InventoryDestination(detachmentId: _theirs, itemId: 'i');
      expect(destinationAllowed(item, _broad.capabilities), isFalse);
    });

    test('a detachment result lands on a tab its route will open', () {
      expect(detachmentTabFor(_minimal.capabilities, _mine), 'shifts');
      expect(detachmentTabFor(_operations.capabilities, _mine), 'team');
      for (final user in [_minimal, _operations, _inventory, _reports]) {
        final tab = detachmentTabFor(user.capabilities, _mine);
        expect(detachmentTabOffered(user.capabilities, _mine, tab), isTrue);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // §41 — equal keys, equal experience. Role picks the surface, nothing more.
  // ---------------------------------------------------------------------------
  testWidgets('a Main Admin holding fixture B keys sees what B sees',
      (tester) async {
    Future<(List<String>, Map<String, String>)> observe(AuthUser user) async {
      final (_, router) = await _boot(tester, user);
      router.go('/detachment/$_mine/shifts');
      await _settle(tester);
      final tabs = _tabs(tester);
      final landed = await _walk(tester, router, const [
        '/detachment/$_mine/team',
        '/detachment/$_mine/member/new',
        '/detachment/$_mine/report',
        '/detachment/$_mine/edit',
        '/detachment-groups',
      ]);
      return (tabs, landed);
    }

    final simple = await observe(_operations);
    final main = await observe(
      _simple(_operations.capabilities, role: AuthRole.mainAdmin),
    );
    expect(main.$1, simple.$1);
    expect(main.$2, simple.$2);
    await _finish(tester);
  });

  // ---------------------------------------------------------------------------
  // §13 / §44 / §57 — the Simple Admin's own context is accurate and safe.
  // ---------------------------------------------------------------------------
  group('the Simple Admin persona reads its own context', () {
    testWidgets('the account names its role accurately', (tester) async {
      final (_, router) = await _boot(tester, simpleAdmin);
      router.go('/more/profile');
      await _settle(tester);
      expect(find.text(S.roleSimpleAdmin), findsWidgets);
      expect(find.text(S.roleMainAdmin), findsNothing);
    });

    testWidgets(
        'Organization shows no Team Code and no Main Admin email; Plan '
        'withholds usage', (tester) async {
      final (_, router) = await _boot(tester, simpleAdmin);
      router.go('/more/organization');
      await _settle(tester);
      expect(locationOf(router), '/more/organization');
      expect(find.textContaining(S.platformTenantTeamCode), findsNothing);
      expect(find.textContaining(mainAdmin.email), findsNothing);

      router.go('/more/plan');
      await _settle(tester);
      expect(locationOf(router), '/more/plan');
      expect(find.text(S.planUsageHiddenNote), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // §45 / §46 — the changed surfaces at 320dp × 1.6 and 390dp, RTL.
  // ---------------------------------------------------------------------------
  group('changed surfaces lay out at narrow widths and large text', () {
    for (final (width, scale) in [(320.0, 1.6), (390.0, 1.0)]) {
      testWidgets('${width.toInt()}dp × $scale', (tester) async {
        final archiver = _simple(_in(const {
          Cap.detachmentView,
          Cap.detachmentArchive,
          Cap.memberView,
        }));
        final (_, router) = await _boot(
          tester,
          archiver,
          width: width,
          textScale: scale,
          disabled: const {TenantFeatureKey.workshops},
        );
        // The changed surfaces: the capability-narrowed tab bar (over the
        // statistics permission state), the notification preferences, and
        // the status-only edit form below. The schedule tab's own body is
        // not a Point 16 change — see HANDOFF, Point 16 §known issues.
        for (final location in [
          '/detachment/$_mine/stats',
          '/more/notifications',
        ]) {
          router.go(location);
          await _settle(tester);
          expect(tester.takeException(), isNull, reason: location);
        }
        router.go('/detachment/$_mine/stats');
        await _settle(tester);
        router.push('/detachment/$_mine/edit');
        await _settle(tester);
        expect(
          find.byKey(const Key('detachment-status-only-note')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
