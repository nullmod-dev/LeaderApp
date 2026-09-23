import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/platform/data/mock_platform_break_glass_repository.dart';
import 'package:mtm/features/platform/data/mock_saas_tenant_repository.dart';
import 'package:mtm/features/platform/data/mock_tenant_lifecycle_repository.dart';
import 'package:mtm/features/platform/data/platform_break_glass_fixtures.dart';
import 'package:mtm/features/platform/data/platform_break_glass_providers.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/platform/domain/platform_area.dart';
import 'package:mtm/features/platform/domain/tenant_lifecycle_models.dart';
import 'package:mtm/features/platform/presentation/platform_break_glass_page.dart';
import 'package:mtm/features/platform/presentation/platform_break_glass_request_page.dart';
import 'package:mtm/features/platform/presentation/platform_break_glass_copy.dart';
import 'package:mtm/features/platform/presentation/platform_operations_page.dart';
import 'package:mtm/features/platform/presentation/platform_operations_routes.dart';
import 'package:mtm/features/platform/presentation/platform_shell.dart';
import 'package:mtm/l10n/strings.dart';

import 'platform_harness.dart';

void main() {
  late DateTime now;

  setUp(() => now = DateTime.utc(2026, 9, 11, 12));

  ProviderContainer configured({
    BreakGlassFixtureScenario seed = BreakGlassFixtureScenario.none,
    MockBreakGlassMode mode = MockBreakGlassMode.loaded,
    Duration latency = Duration.zero,
  }) =>
      platformContainer(
        superAdmin,
        overrides: [
          clockProvider.overrideWithValue(() => now),
          breakGlassMockConfigProvider.overrideWithValue(
            BreakGlassMockConfig(seed: seed, mode: mode, latency: latency),
          ),
        ],
      );

  Future<GoRouter> open(
    WidgetTester tester, {
    BreakGlassFixtureScenario seed = BreakGlassFixtureScenario.none,
    MockBreakGlassMode mode = MockBreakGlassMode.loaded,
    String location = PlatformOperationsRoutes.access,
    double width = 390,
    double textScale = 1,
    bool reduceMotion = false,
  }) async {
    final router = await bootPlatform(
      tester,
      configured(seed: seed, mode: mode),
      width: width,
      height: 1000,
      textScale: textScale,
      reduceMotion: reduceMotion,
    );
    router.go(location);
    await settlePlatform(tester);
    return router;
  }

  testWidgets('management starts with current no-grant state and separate flow',
      (tester) async {
    final router = await open(tester);

    expect(find.byType(PlatformBreakGlassPage), findsOneWidget);
    expect(find.text(S.breakGlassTitle), findsOneWidget,
        reason: 'the app-bar owns the page title; the body does not repeat it');
    expect(find.byKey(const Key('break-glass-none')), findsOneWidget);
    expect(find.text(S.breakGlassFactReadOnly), findsOneWidget);
    expect(find.byKey(const Key('break-glass-tenant')), findsNothing);

    await tester.tap(find.byKey(const Key('break-glass-request')));
    await settlePlatform(tester);
    expect(router.canPop(), isTrue);
    expect(find.byType(PlatformBreakGlassRequestPage), findsOneWidget);
  });

  for (final state in [
    (BreakGlassFixtureScenario.expired, 'break-glass-expired'),
    (BreakGlassFixtureScenario.ended, 'break-glass-ended'),
    (BreakGlassFixtureScenario.unsupported, 'break-glass-unsupported'),
  ]) {
    testWidgets('management renders ${state.$1.name} safely', (tester) async {
      await open(tester, seed: state.$1);
      expect(find.byKey(Key(state.$2)), findsOneWidget);
      expect(find.byKey(const Key('break-glass-end')), findsNothing);
    });
  }

  for (final state in [
    (MockBreakGlassMode.offline, 'break-glass-offline'),
    (MockBreakGlassMode.failure, 'break-glass-failure'),
    (MockBreakGlassMode.notPermitted, 'break-glass-not-permitted'),
  ]) {
    testWidgets('management renders ${state.$1.name} without authority',
        (tester) async {
      await open(tester, mode: state.$1);
      expect(find.byKey(Key(state.$2)), findsOneWidget);
      expect(find.byKey(const Key('break-glass-request')), findsNothing);
    });
  }

  testWidgets('stale possibly-live grant is shown but not usable',
      (tester) async {
    await open(
      tester,
      seed: BreakGlassFixtureScenario.active,
      mode: MockBreakGlassMode.stale,
    );

    expect(find.byKey(const Key('break-glass-unverified')), findsOneWidget);
    expect(find.text(S.breakGlassUnverified), findsOneWidget);
    expect(find.byKey(const Key('break-glass-end')), findsNothing);
    expect(find.byKey(const Key('platform-break-glass-strip')), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const Key('platform-break-glass-strip-end')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('active state exposes stable remaining-time context',
      (tester) async {
    await open(tester, seed: BreakGlassFixtureScenario.active);
    expect(find.text(S.breakGlassRemainingTime), findsOneWidget);
    expect(find.text(S.breakGlassRemainingLessThanHour), findsOneWidget);
  });

  testWidgets('near-expiry state exposes a stable minute bucket',
      (tester) async {
    await open(tester, seed: BreakGlassFixtureScenario.nearExpiry);
    expect(find.text(S.breakGlassRemainingMinutes.replaceFirst('%d', '٤')),
        findsOneWidget);
  });

  test('remaining-time copy uses stable minute and hour buckets', () {
    expect(
      BreakGlassCopy.remainingContext(
        now.add(const Duration(seconds: 40)),
        now,
      ),
      S.breakGlassRemainingLessThanMinute,
    );
    expect(
      BreakGlassCopy.remainingContext(
        now.add(const Duration(minutes: 10)),
        now,
      ),
      S.breakGlassRemainingMinutes.replaceFirst('%d', '١٠'),
    );
    expect(
      BreakGlassCopy.remainingContext(
        now.add(const Duration(minutes: 42)),
        now,
      ),
      S.breakGlassRemainingLessThanHour,
    );
  });

  testWidgets('request lists active teams only and validates the reason',
      (tester) async {
    await open(tester, location: PlatformOperationsRoutes.accessRequest);

    await tester.tap(find.byKey(const Key('break-glass-tenant')));
    await tester.pumpAndSettle();
    expect(find.textContaining('فرق الهلال الطبية'), findsWidgets);
    expect(find.textContaining('فريق الركن الطبي'), findsNothing,
        reason: 'the suspended tenant is never a valid choice');
    await tester.tap(find.textContaining('فرق الهلال الطبية').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('break-glass-activate')));
    await tester.pump();
    expect(find.text(S.breakGlassReasonRequired), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('break-glass-reason')),
      List.filled(281, 'س').join(),
    );
    await tester.tap(find.byKey(const Key('break-glass-activate')));
    await tester.pump();
    expect(find.text(S.breakGlassReasonTooLong), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('break-glass-reason')),
      'تعذّر وصول مسؤول الفريق إلى سجلات المناوبات',
    );
    await tester.tap(find.byKey(const Key('break-glass-activate')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget,
        reason: 'activation has exactly one confirmation');
    expect(find.text('فرق الهلال الطبية'), findsOneWidget);
    expect(find.textContaining('حدود الخطة'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching:
            find.textContaining('تعذّر وصول مسؤول الفريق إلى سجلات المناوبات'),
      ),
      findsOneWidget,
      reason: 'the confirmation names the reason being recorded',
    );
    await tester.tap(
      find.widgetWithText(FilledButton, S.breakGlassActivateAction).last,
    );
    await settlePlatform(tester);
    expect(find.byKey(const Key('break-glass-active')), findsOneWidget);
    expect(find.byKey(const Key('platform-break-glass-strip')), findsOneWidget);
    expect(find.byType(PlatformBreakGlassRequestPage), findsNothing);
  });

  testWidgets('activation returns to management without losing the back stack',
      (tester) async {
    final router = await open(tester, location: PlatformArea.operations.route);
    // Emergency access is the last group on the grouped operations landing.
    final row = find.byKey(const Key('platform-operations-break-glass'));
    await tester.scrollUntilVisible(row, 200);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await settlePlatform(tester);
    await tester.tap(find.byKey(const Key('break-glass-request')));
    await settlePlatform(tester);
    await tester.tap(find.byKey(const Key('break-glass-tenant')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('فرق الهلال الطبية').last);
    await tester.enterText(
      find.byKey(const Key('break-glass-reason')),
      'حاجة إدارية موثقة',
    );
    await tester.tap(find.byKey(const Key('break-glass-activate')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, S.breakGlassActivateAction).last,
    );
    await settlePlatform(tester);

    // Pushed pages do not move go_router's reported base location, so the
    // assertion is on the page, as in `platform_operations_test.dart`.
    expect(find.byType(PlatformBreakGlassPage), findsOneWidget);
    expect(find.byType(PlatformBreakGlassRequestPage), findsNothing);
    expect(find.byKey(const Key('break-glass-active')), findsOneWidget);
    expect(router.canPop(), isTrue,
        reason: 'Operations is still beneath the management page');
    router.pop();
    await settlePlatform(tester);
    expect(find.byType(PlatformOperationsPage), findsOneWidget);
    expect(find.textContaining('فرق الهلال الطبية'), findsWidgets,
        reason: 'the Operations row summarizes the live grant');
  });

  test('picker offers active tenants only, whatever their lifecycle', () async {
    final container = platformContainer(
      superAdmin,
      overrides: [
        clockProvider.overrideWithValue(() => now),
        saasTenantRepositoryProvider.overrideWith(
          (ref) => MockSaasTenantRepository(
            store: ref.watch(platformTenantStoreProvider),
            latency: Duration.zero,
          ),
        ),
      ],
    );
    final store = container.read(platformTenantStoreProvider);
    final lifecycle = MockTenantLifecycleRepository(
      store: store,
      clock: () => now,
      latency: Duration.zero,
    );
    for (final id in ['saas_najd', 'saas_sahel']) {
      final tenant = store.byId(id)!;
      await lifecycle.beginDeletion(BeginTenantDeletionCommand(
        tenantId: id,
        expectedVersion: tenant.tenantVersion,
        idempotencyKey: 'begin-$id',
        reason: 'طلب حذف موثق',
      ));
    }
    now = now.add(kProvisionalTenantDeletionGrace);
    final pending = store.byId('saas_sahel')!;
    await lifecycle.finalizeDeletion(FinalizeTenantDeletionCommand(
      tenantId: pending.id,
      expectedVersion: pending.tenantVersion,
      idempotencyKey: 'finalize-sahel',
    ));
    expect(store.lifecycleStatusOf('saas_rukn'), SaasTenantStatus.suspended);
    expect(
        store.lifecycleStatusOf('saas_najd'), SaasTenantStatus.deletionPending);
    expect(store.byId('saas_sahel'), isNull);

    final result =
        await container.read(breakGlassEligibleTenantsProvider('').future);
    final ids = result.when(
      success: (items, {stale = false}) => [
        for (final tenant in items)
          if (tenant.tenantStatus == SaasTenantStatus.active)
            tenant.id
          else
            fail('${tenant.id} is ${tenant.tenantStatus}'),
      ],
      failure: (_, __) => fail('eligible tenants failed'),
      offline: (_) => fail('eligible tenants offline'),
    );
    expect(ids, contains('saas_hilal'));
    expect(ids, isNot(anyOf(contains('saas_rukn'), contains('saas_najd'))));
    expect(ids, isNot(contains('saas_sahel')));
  });

  testWidgets('management and request initialize no tenant repository',
      (tester) async {
    final watch = TenantRepositoryWatch();
    final router = await bootPlatform(
      tester,
      platformContainer(
        superAdmin,
        watch: watch,
        overrides: [
          clockProvider.overrideWithValue(() => now),
          breakGlassMockConfigProvider.overrideWithValue(
            const BreakGlassMockConfig(
              seed: BreakGlassFixtureScenario.active,
              latency: Duration.zero,
            ),
          ),
        ],
      ),
      height: 1000,
    );
    for (final route in [
      PlatformOperationsRoutes.access,
      PlatformOperationsRoutes.accessRequest,
    ]) {
      router.go(route);
      await settlePlatform(tester);
      expect(watch.built, isEmpty, reason: route);
    }
    await tester.tap(find.byKey(const Key('break-glass-tenant')));
    await tester.pumpAndSettle();
    expect(watch.built, isEmpty);
  });

  testWidgets('the strip clears the status bar once, not twice',
      (tester) async {
    tester.view.padding = const FakeViewPadding(top: 40);
    addTearDown(tester.view.resetPadding);
    await open(tester, seed: BreakGlassFixtureScenario.active);

    final strip = tester.getRect(
      find.byKey(const Key('platform-break-glass-strip')),
    );
    final label = tester.getRect(
      find.byKey(const Key('platform-break-glass-strip-open')),
    );
    final appBar = tester.getRect(find.byType(AppBar));
    expect(strip.top, 0);
    expect(label.top, greaterThanOrEqualTo(40),
        reason: 'strip content sits below the status bar');
    expect(appBar.top, strip.bottom);
    expect(appBar.height, kToolbarHeight,
        reason: 'the page does not reserve the status bar a second time');
  });

  testWidgets('strip announces emergency context and keeps 48dp targets',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester, seed: BreakGlassFixtureScenario.active);

    final strip = find.byKey(const Key('platform-break-glass-strip'));
    final node = tester.getSemantics(strip);
    expect(node.label, contains(S.breakGlassActiveTitle));
    expect(node.label, contains(S.breakGlassReadOnlyScope));
    expect(node.flagsCollection.isLiveRegion, isTrue);
    expect(
      tester
          .getSize(find.byKey(const Key('platform-break-glass-strip-open')))
          .height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester
          .getSize(find.byKey(const Key('platform-break-glass-strip-end')))
          .height,
      greaterThanOrEqualTo(48),
    );
    semantics.dispose();
  });

  testWidgets('strip motion stays within the short motion token',
      (tester) async {
    await open(tester, seed: BreakGlassFixtureScenario.active);
    final switcher = tester.widget<AnimatedSwitcher>(find.ancestor(
      of: find.byKey(const Key('platform-break-glass-strip')),
      matching: find.byType(AnimatedSwitcher),
    ));
    expect(switcher.duration, greaterThan(Duration.zero));
    expect(switcher.duration,
        lessThanOrEqualTo(const Duration(milliseconds: 200)));
  });

  testWidgets('strip motion becomes immediate when reduced', (tester) async {
    await open(
      tester,
      seed: BreakGlassFixtureScenario.active,
      reduceMotion: true,
    );
    final switcher = tester.widget<AnimatedSwitcher>(find.ancestor(
      of: find.byKey(const Key('platform-break-glass-strip')),
      matching: find.byType(AnimatedSwitcher),
    ));
    expect(switcher.duration, Duration.zero);
    expect(switcher.reverseDuration, Duration.zero);
  });

  testWidgets('a Super Admin sign-out warns that it ends emergency access',
      (tester) async {
    final router = await open(tester, seed: BreakGlassFixtureScenario.active);
    router.go('/platform/more');
    await settlePlatform(tester);
    final signOut = find.text(S.signOut);
    await tester.ensureVisible(signOut);
    await tester.tap(signOut);
    await tester.pumpAndSettle();
    expect(find.textContaining('وصول طارئ'), findsOneWidget);
  });

  testWidgets('recent-auth result never pretends Flutter can satisfy it',
      (tester) async {
    await open(
      tester,
      location: PlatformOperationsRoutes.accessRequest,
      mode: MockBreakGlassMode.recentAuthRequired,
    );
    await tester.tap(find.byKey(const Key('break-glass-tenant')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('فرق الهلال الطبية').last);
    await tester.enterText(
      find.byKey(const Key('break-glass-reason')),
      'حاجة إدارية موثقة',
    );
    await tester.tap(find.byKey(const Key('break-glass-activate')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, S.breakGlassActivateAction).last,
    );
    await settlePlatform(tester);

    expect(find.byKey(const Key('break-glass-recent-auth')), findsOneWidget);
    expect(find.textContaining('سجّل الخروج'), findsOneWidget);
  });

  testWidgets('offline activation is refused and never queued', (tester) async {
    await open(
      tester,
      location: PlatformOperationsRoutes.accessRequest,
      mode: MockBreakGlassMode.offline,
    );
    await tester.tap(find.byKey(const Key('break-glass-tenant')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('فرق الهلال الطبية').last);
    await tester.enterText(
      find.byKey(const Key('break-glass-reason')),
      'حاجة إدارية موثقة',
    );
    await tester.tap(find.byKey(const Key('break-glass-activate')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, S.breakGlassActivateAction).last,
    );
    await settlePlatform(tester);
    expect(find.text(S.breakGlassOfflineAction), findsOneWidget);
    expect(find.byType(PlatformBreakGlassRequestPage), findsOneWidget);
  });

  testWidgets('active grant persists across Platform pages and ends once',
      (tester) async {
    final router = await open(tester, seed: BreakGlassFixtureScenario.active);

    expect(find.byKey(const Key('break-glass-active')), findsOneWidget);
    expect(find.byKey(const Key('platform-break-glass-strip')), findsOneWidget);
    expect(find.textContaining('فرق الهلال الطبية'), findsWidgets);

    router.go('/platform/more');
    await settlePlatform(tester);
    expect(find.byKey(const Key('platform-break-glass-strip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('platform-break-glass-strip-end')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(
      find.widgetWithText(FilledButton, S.breakGlassEndFullAction),
    );
    await settlePlatform(tester);
    expect(find.byKey(const Key('platform-break-glass-strip')), findsNothing);
    expect(find.text(S.breakGlassEndedSnack), findsOneWidget,
        reason: 'the strip leaving is announced, not silent');

    router.go(PlatformOperationsRoutes.access);
    await settlePlatform(tester);
    expect(find.byKey(const Key('break-glass-ended')), findsOneWidget);
  });

  testWidgets('one-shot expiry removes the indicator and usable authority',
      (tester) async {
    final container = configured(seed: BreakGlassFixtureScenario.active);
    final router = await bootPlatform(tester, container, height: 1000);
    router.go(PlatformOperationsRoutes.access);
    await settlePlatform(tester);
    final grant = container.read(breakGlassAccessProvider).grant!;
    expect(container.read(breakGlassAccessProvider).isUsable, isTrue);

    now = grant.expiresAt;
    await tester
        .pump(grant.expiresAt.difference(DateTime.utc(2026, 9, 11, 12)));
    await settlePlatform(tester);

    expect(container.read(breakGlassAccessProvider).isUsable, isFalse);
    expect(find.byKey(const Key('platform-break-glass-strip')), findsNothing);
    expect(find.byKey(const Key('break-glass-expired')), findsOneWidget);
  });

  testWidgets('management Audit link opens the emergency-access filter',
      (tester) async {
    await open(tester);
    final audit = find.byKey(const Key('break-glass-audit'));
    await tester.drag(find.byType(ListView).last, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(audit);
    await settlePlatform(tester);
    // Arabic-Indic, like every other count in the product.
    expect(find.text('تصفية (١)'), findsOneWidget);
  });

  testWidgets('functional layout builds at phone and wide widths',
      (tester) async {
    await open(tester, width: 320);
    expect(find.byType(PlatformBreakGlassPage), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    await tester.pumpAndSettle();
    expect(find.byType(PlatformShell), findsOneWidget);
  });

  testWidgets('320dp at 1.6 text scale keeps management usable',
      (tester) async {
    await open(
      tester,
      seed: BreakGlassFixtureScenario.active,
      width: 320,
      textScale: 1.6,
    );
    expect(tester.takeException(), isNull);
    expect(
      tester
          .getSize(find.byKey(const Key('platform-break-glass-strip-open')))
          .height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('320dp at 1.6 text scale keeps request usable', (tester) async {
    await open(
      tester,
      location: PlatformOperationsRoutes.accessRequest,
      width: 320,
      textScale: 1.6,
    );
    expect(find.byType(PlatformBreakGlassRequestPage), findsOneWidget);
    expect(find.byKey(const Key('break-glass-tenant-search')), findsOneWidget);
    expect(find.byKey(const Key('break-glass-reason')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
