import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/l10n/strings.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/platform/data/mock_platform_overview_repository.dart';
import 'package:mtm/features/platform/data/mock_saas_tenant_repository.dart';
import 'package:mtm/features/platform/data/platform_overview_providers.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/platform/domain/platform_overview_models.dart';
import 'package:mtm/features/platform/domain/saas_tenant_models.dart';
import 'package:mtm/features/platform/domain/saas_subscription_models.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_create_page.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_detail_page.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_routes.dart';

import 'platform_harness.dart';

/// Point 6 — `/platform/tenants/new`, the one write this Point ships.
void main() {
  final now = DateTime.utc(2026, 9, 8, 16);

  List<Override> overrides({
    MockSaasTenantMode mode = MockSaasTenantMode.loaded,
  }) =>
      [
        clockProvider.overrideWithValue(() => now),
        saasTenantRepositoryProvider.overrideWith((ref) {
          return MockSaasTenantRepository(
            store: ref.watch(platformTenantStoreProvider),
            mode: mode,
            latency: Duration.zero,
          );
        }),
        platformOverviewRepositoryProvider.overrideWith((ref) {
          return MockPlatformOverviewRepository(
            clock: () => now,
            store: ref.watch(platformTenantStoreProvider),
            latency: Duration.zero,
          );
        }),
      ];

  Future<ProviderContainer> open(
    WidgetTester tester, {
    MockSaasTenantMode mode = MockSaasTenantMode.loaded,
  }) async {
    final container =
        platformContainer(superAdmin, overrides: overrides(mode: mode));
    final router = await bootPlatform(tester, container, height: 1600);
    router.go(SaasTenantRoutes.create);
    await settlePlatform(tester);
    return container;
  }

  Future<void> fill(
    WidgetTester tester, {
    String name = 'فريق الشمال الطبي',
    String adminName = 'أمل السبيعي',
    String email = 'amal@shamal.org',
    String? code,
  }) async {
    await tester.enterText(
        find.byKey(const Key('platform-tenant-name-field')), name);
    await tester.enterText(
        find.byKey(const Key('platform-tenant-admin-name-field')), adminName);
    await tester.enterText(
        find.byKey(const Key('platform-tenant-admin-email-field')), email);
    if (code != null) {
      await tester.enterText(
          find.byKey(const Key('platform-tenant-code-field')), code);
    }
    await tester.pump();
  }

  group('the form', () {
    testWidgets('offers four fields, a suggested code and one button',
        (tester) async {
      await open(tester);

      expect(find.byType(SaasTenantCreatePage), findsOneWidget);
      for (final key in const [
        'platform-tenant-name-field',
        'platform-tenant-admin-name-field',
        'platform-tenant-admin-email-field',
        'platform-tenant-code-field',
        'platform-tenant-code-suggest',
        'platform-tenant-submit',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      // The Team Code arrives pre-filled with a valid suggestion.
      final field = tester.widget<TextField>(
        find.byKey(const Key('platform-tenant-code-field')),
      );
      expect(field.controller!.text, startsWith('MTM-'));
    });

    testWidgets('asks for no plan, limit, flag or status', (tester) async {
      await open(tester);

      for (final label in const [
        'الخطة',
        'الحدود',
        'المزايا',
        'الحالة',
        'كلمة المرور',
        'كلمة مرور مؤقتة',
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
    });

    testWidgets('states what provisioning actually does', (tester) async {
      await open(tester);

      expect(find.byKey(const Key('platform-tenant-provisioning-note')),
          findsOneWidget);
      expect(find.textContaining('لا تُولّد المنصة كلمة مرور'), findsOneWidget);
    });

    testWidgets('suggesting another code changes it and stays valid',
        (tester) async {
      await open(tester);
      final finder = find.byKey(const Key('platform-tenant-code-field'));
      final first = tester.widget<TextField>(finder).controller!.text;

      await tester.tap(find.byKey(const Key('platform-tenant-code-suggest')));
      await tester.pump();

      final second = tester.widget<TextField>(finder).controller!.text;
      expect(second, isNot(first));
      expect(second, startsWith('MTM-'));
    });
  });

  group('validation', () {
    testWidgets('an empty form is refused at the fields, not sent',
        (tester) async {
      final container = await open(tester);
      await tester.enterText(
          find.byKey(const Key('platform-tenant-code-field')), '');
      await tester.tap(find.byKey(const Key('platform-tenant-submit')));
      await settlePlatform(tester);

      expect(find.text(S.platformTenantFieldRequired), findsWidgets);
      expect(container.read(platformTenantStoreProvider).tenants, hasLength(8));
    });

    testWidgets('a malformed email is named under its own field',
        (tester) async {
      await open(tester);
      await fill(tester, email: 'not-an-email');
      await tester.tap(find.byKey(const Key('platform-tenant-submit')));
      await settlePlatform(tester);

      expect(find.text(S.platformTenantFieldEmail), findsOneWidget);
    });

    testWidgets('a malformed Team Code is named under its own field',
        (tester) async {
      await open(tester);
      await fill(tester, code: 'ABC-1234');
      await tester.tap(find.byKey(const Key('platform-tenant-submit')));
      await settlePlatform(tester);

      expect(find.text(S.platformTenantFieldCode), findsOneWidget);
    });

    testWidgets('a Team Code already in use is refused by the repository',
        (tester) async {
      final container = await open(tester);
      await fill(tester, code: 'MTM-4K7P-QX92');
      await tester.tap(find.byKey(const Key('platform-tenant-submit')));
      await settlePlatform(tester);

      expect(find.text(S.platformTenantCodeTaken), findsWidgets);
      expect(container.read(platformTenantStoreProvider).tenants, hasLength(8));
    });
  });

  group('offline and failure', () {
    testWidgets('offline refuses without queueing and without a record',
        (tester) async {
      final container =
          await open(tester, mode: MockSaasTenantMode.offlineWithCache);
      await fill(tester);
      await tester.tap(find.byKey(const Key('platform-tenant-submit')));
      await settlePlatform(tester);

      expect(find.byKey(const Key('platform-tenant-create-banner')),
          findsOneWidget);
      expect(
          find.textContaining('لا يمكن إنشاء فريق بدون اتصال'), findsOneWidget);
      expect(container.read(platformTenantStoreProvider).tenants, hasLength(8));
      expect(find.byType(SaasTenantCreatePage), findsOneWidget);
    });

    testWidgets('a repository failure keeps everything typed', (tester) async {
      await open(tester, mode: MockSaasTenantMode.failure);
      await fill(tester);
      await tester.tap(find.byKey(const Key('platform-tenant-submit')));
      await settlePlatform(tester);

      expect(find.byKey(const Key('platform-tenant-create-banner')),
          findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
      final name = tester.widget<TextField>(
        find.byKey(const Key('platform-tenant-name-field')),
      );
      expect(name.controller!.text, 'فريق الشمال الطبي');
    });
  });

  group('success', () {
    testWidgets('registers the subscriber and opens its detail',
        (tester) async {
      final container = platformContainer(superAdmin, overrides: overrides());
      final router = await bootPlatform(tester, container, height: 2400);
      router.go(SaasTenantRoutes.create);
      await settlePlatform(tester);

      await fill(tester);
      await tester.tap(find.byKey(const Key('platform-tenant-submit')));
      await settlePlatform(tester);

      expect(find.byType(SaasTenantDetailPage), findsOneWidget);
      expect(find.byType(SaasTenantCreatePage), findsNothing);
      expect(find.text('فريق الشمال الطبي'), findsWidgets);
      // Since Point 14B the summary reads the new tenant's Main Admin seat:
      // a never-activated first admin is a pending-setup account.
      expect(find.text(S.mainAdminStatusPending), findsOneWidget);
      expect(find.text(S.mainAdminSummaryPending), findsOneWidget);
      expect(container.read(platformTenantStoreProvider).tenants, hasLength(9));
    });

    testWidgets('the list and the Platform Overview both move, no restart',
        (tester) async {
      final container = platformContainer(superAdmin, overrides: overrides());
      final router = await bootPlatform(tester, container, height: 2400);

      // The overview count before, read through the same provider the screen
      // reads.
      PlatformTenantSummary summary() {
        final value = container.read(platformOverviewProvider).requireValue;
        return value.when(
          success: (data, {stale = false}) => data.tenants,
          failure: (_, __) => throw TestFailure('failure'),
          offline: (_) => throw TestFailure('offline'),
        );
      }

      await container.read(platformOverviewProvider.future);
      expect(summary().total, 8);
      expect(summary().activeTrials, 2);

      router.go(SaasTenantRoutes.create);
      await settlePlatform(tester);
      await fill(tester);
      await tester.tap(find.byKey(const Key('platform-tenant-submit')));
      await settlePlatform(tester);

      await container.read(platformOverviewProvider.future);
      expect(summary().total, 9);
      expect(summary().activeTrials, 3);

      final page = await container
          .read(saasTenantListProvider(const SaasTenantQuery()).future);
      expect(
        page.when(
          success: (data, {stale = false}) => data.total,
          failure: (_, __) => -1,
          offline: (_) => -1,
        ),
        9,
      );
    });

    testWidgets('a second submit while one is in flight creates nothing extra',
        (tester) async {
      final container = platformContainer(
        superAdmin,
        overrides: [
          clockProvider.overrideWithValue(() => now),
          saasTenantRepositoryProvider.overrideWith((ref) {
            return MockSaasTenantRepository(
              store: ref.watch(platformTenantStoreProvider),
              // A real delay, so the second tap genuinely lands mid-flight.
              latency: const Duration(milliseconds: 300),
            );
          }),
        ],
      );
      final router = await bootPlatform(tester, container, height: 2400);
      router.go(SaasTenantRoutes.create);
      await settlePlatform(tester);
      await fill(tester);

      final submit = find.byKey(const Key('platform-tenant-submit'));
      await tester.tap(submit);
      await tester.pump();
      // The guard is the controller; the disabled button only shows it.
      expect(container.read(saasTenantCreateControllerProvider), isTrue);
      await tester.tap(submit, warnIfMissed: false);
      await settlePlatform(tester);

      expect(container.read(platformTenantStoreProvider).tenants, hasLength(9));
    });
  });

  group('the created record', () {
    testWidgets('starts in a trial with a pending Main Admin and no secret',
        (tester) async {
      final container = await open(tester);
      await fill(tester);
      await tester.tap(find.byKey(const Key('platform-tenant-submit')));
      await settlePlatform(tester);

      final created = container
          .read(platformTenantStoreProvider)
          .tenants
          .firstWhere((t) => t.id == 'saas_new_1');

      expect(created.tenantStatus, SaasTenantStatus.active);
      expect(created.subscription.status, SubscriptionStatus.trial);
      expect(
          created.mainAdmin.provisioning, MainAdminProvisioning.pendingSetup);
      expect(created.counts.detachments, 0);
      expect(created.toJson().toString().toLowerCase().contains('password'),
          isFalse);
    });
  });

  group('isolation', () {
    testWidgets('creating a subscriber builds no tenant repository',
        (tester) async {
      final watch = TenantRepositoryWatch();
      final container = platformContainer(
        superAdmin,
        watch: watch,
        overrides: overrides(),
      );
      final router = await bootPlatform(tester, container, height: 2400);
      router.go(SaasTenantRoutes.create);
      await settlePlatform(tester);
      await fill(tester);
      await tester.tap(find.byKey(const Key('platform-tenant-submit')));
      await settlePlatform(tester);

      expect(watch.built, isEmpty);
    });
  });
}
