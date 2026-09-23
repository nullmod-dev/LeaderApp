import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/platform/data/mock_platform_health_repository.dart';
import 'package:mtm/features/platform/data/platform_operations_providers.dart';
import 'package:mtm/features/platform/domain/platform_health_models.dart';
import 'package:mtm/features/platform/domain/platform_health_repository.dart';
import 'package:mtm/features/platform/presentation/platform_operations_routes.dart';
import 'package:mtm/l10n/strings.dart';

import 'platform_harness.dart';

void main() {
  final now = DateTime.utc(2026, 9, 10, 16);

  ProviderContainer containerFor({
    MockPlatformHealthMode mode = MockPlatformHealthMode.degraded,
    PlatformHealthRepository? repository,
    TenantRepositoryWatch? watch,
  }) =>
      platformContainer(
        superAdmin,
        watch: watch,
        overrides: [
          clockProvider.overrideWithValue(() => now),
          platformHealthRepositoryProvider.overrideWith((ref) {
            return repository ??
                MockPlatformHealthRepository(
                  fixtures: ref.watch(platformOperationsFixturesProvider),
                  mode: mode,
                  latency: Duration.zero,
                );
          }),
        ],
      );

  Future<void> open(
    WidgetTester tester, {
    MockPlatformHealthMode mode = MockPlatformHealthMode.degraded,
    PlatformHealthRepository? repository,
    TenantRepositoryWatch? watch,
    double width = 390,
    double height = 1000,
    double textScale = 1,
  }) async {
    final container = containerFor(
      mode: mode,
      repository: repository,
      watch: watch,
    );
    final router = await bootPlatform(
      tester,
      container,
      width: width,
      height: height,
      textScale: textScale,
    );
    router.go(PlatformOperationsRoutes.health);
    await settlePlatform(tester);
  }

  testWidgets('loading is a designed state', (tester) async {
    await open(tester, repository: _PendingHealthRepository());

    expect(find.byKey(const Key('platform-health-loading')), findsOneWidget);
    expect(find.byKey(const Key('platform-health-loaded')), findsNothing);
  });

  testWidgets('healthy and degraded platform states stay distinct from failure',
      (tester) async {
    await open(tester, mode: MockPlatformHealthMode.healthy);
    expect(find.byKey(const Key('platform-health-loaded')), findsOneWidget);
    expect(find.text(S.platformHealthStatusHealthy), findsWidgets);
    expect(find.byKey(const Key('platform-health-failure')), findsNothing);

    await open(tester, mode: MockPlatformHealthMode.degraded);
    expect(find.text(S.platformHealthStatusDegraded), findsWidgets);
    expect(find.text(S.platformHealthAttention), findsOneWidget);
    expect(find.byKey(const Key('platform-health-failure')), findsNothing);
  });

  testWidgets('partial and unknown snapshots remain explicit', (tester) async {
    await open(tester, mode: MockPlatformHealthMode.partial);
    expect(find.byKey(const Key('platform-health-partial')), findsOneWidget);
    expect(find.text(S.platformHealthPartialTitle), findsOneWidget);
    expect(find.text(S.platformHealthStatusUnknown), findsWidgets);

    await open(tester, mode: MockPlatformHealthMode.unknown);
    expect(find.text(S.platformHealthStatusUnknown), findsWidgets);
    expect(find.text(S.platformHealthStatusHealthy), findsNothing);
  });

  testWidgets('stale and offline cache stay useful and labelled truthfully',
      (tester) async {
    await open(tester, mode: MockPlatformHealthMode.stale);
    expect(find.byKey(const Key('platform-health-loaded')), findsOneWidget);
    expect(find.text(S.platformHealthStale), findsOneWidget);

    await open(tester, mode: MockPlatformHealthMode.offlineWithCache);
    expect(find.byKey(const Key('platform-health-loaded')), findsOneWidget);
    expect(find.text(S.platformHealthOfflineCached), findsOneWidget);
  });

  testWidgets('offline without cache and failure are safe retry states',
      (tester) async {
    await open(tester, mode: MockPlatformHealthMode.offlineWithoutCache);
    expect(
      find.byKey(const Key('platform-health-offline-empty')),
      findsOneWidget,
    );
    expect(find.text(S.platformHealthStatusHealthy), findsNothing);

    await open(
      tester,
      repository: const _HealthResultRepository(
        Failure('Bearer secret raw stack trace', code: 'server'),
      ),
    );
    expect(find.byKey(const Key('platform-health-failure')), findsOneWidget);
    expect(find.text('Bearer secret raw stack trace'), findsNothing);
    expect(find.text(S.retry), findsOneWidget);
  });

  testWidgets('health status is announced as text, not color alone',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester, mode: MockPlatformHealthMode.degraded);

    final overall = tester.getSemantics(
      find.byKey(const Key('platform-health-overall')),
    );
    expect(overall.label, contains(S.platformHealthStatusDegraded));
    final signal = tester.getSemantics(
      find.byKey(const Key('platform-health-signal-background_jobs')),
    );
    expect(signal.label, contains(S.platformHealthStatusDegraded));
    expect(signal.label, contains(S.platformHealthAttention));
    expect(find.byTooltip(S.platformHealthRefresh), findsOneWidget);
    semantics.dispose();
  });

  for (final (label, width, scale) in [
    ('320dp at 1.6 text scale', 320.0, 1.6),
    ('600dp', 600.0, 1.0),
    ('900dp', 900.0, 1.0),
  ]) {
    testWidgets('$label renders without overflow', (tester) async {
      await open(
        tester,
        mode: MockPlatformHealthMode.partial,
        width: width,
        height: 1200,
        textScale: scale,
      );
      expect(find.byKey(const Key('platform-health-loaded')), findsOneWidget);
    });
  }

  testWidgets('health never initializes tenant operational repositories',
      (tester) async {
    final watch = TenantRepositoryWatch();
    await open(tester, watch: watch);
    expect(watch.built, isEmpty);
  });
}

class _PendingHealthRepository implements PlatformHealthRepository {
  final Completer<Result<PlatformHealthSnapshot>> _pending = Completer();

  @override
  Future<Result<PlatformHealthSnapshot>> loadHealth() => _pending.future;
}

class _HealthResultRepository implements PlatformHealthRepository {
  const _HealthResultRepository(this.result);

  final Result<PlatformHealthSnapshot> result;

  @override
  Future<Result<PlatformHealthSnapshot>> loadHealth() async => result;
}
