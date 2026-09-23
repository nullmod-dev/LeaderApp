import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/platform/data/mock_platform_overview_repository.dart';
import 'package:mtm/features/platform/domain/platform_overview_models.dart';

void main() {
  final now = DateTime.utc(2026, 9, 8, 16);

  Future<PlatformOverviewSnapshot> load(DateTime instant) async {
    final result = await MockPlatformOverviewRepository(
      clock: () => instant,
      latency: Duration.zero,
    ).loadOverview();
    return result.when(
      success: (data, {stale = false}) => data,
      failure: (message, code) => throw TestFailure(message),
      offline: (cached) => throw TestFailure('unexpected offline result'),
    );
  }

  test('the populated mock is deterministic from the injected clock', () async {
    final first = await load(now);
    final second = await load(now);

    expect(first.toJson(), second.toJson());
    expect(first.generatedAt, now.subtract(const Duration(minutes: 6)));
    expect(first.recentActivity.first.occurredAt,
        now.subtract(const Duration(minutes: 38)));
  });

  test('all relative times move only when the injected clock moves', () async {
    final later = now.add(const Duration(days: 4));
    final first = await load(now);
    final second = await load(later);

    expect(second.generatedAt.difference(first.generatedAt),
        const Duration(days: 4));
    for (var index = 0; index < first.recentActivity.length; index++) {
      expect(
        second.recentActivity[index].occurredAt
            .difference(first.recentActivity[index].occurredAt),
        const Duration(days: 4),
      );
    }
  });

  test('tenant and demo summary counts are internally consistent', () async {
    final snapshot = await load(now);
    final tenants = snapshot.tenants;
    final demos = snapshot.demos;

    expect(
      tenants.total,
      tenants.activeSubscriptions +
          tenants.activeTrials +
          tenants.gracePeriod +
          tenants.suspended,
    );
    expect(demos.active, demos.simple + demos.full);
    expect(tenants.deletionPending, 0);
    expect(demos.expiringSoon, lessThanOrEqualTo(demos.active));
  });

  test('recent activity is newest first with stable identities', () async {
    final activity = (await load(now)).recentActivity;

    expect(activity.map((item) => item.id).toSet().length, activity.length);
    for (var index = 1; index < activity.length; index++) {
      expect(
        activity[index - 1].occurredAt.isBefore(activity[index].occurredAt),
        isFalse,
      );
    }
    expect(activity.first.type, PlatformActivityType.demoStarted);
  });

  test('the offline mock is explicit about cache availability', () async {
    final withCache = await MockPlatformOverviewRepository(
      clock: () => now,
      mode: MockPlatformOverviewMode.offlineWithCache,
      latency: Duration.zero,
    ).loadOverview();
    final withoutCache = await MockPlatformOverviewRepository(
      clock: () => now,
      mode: MockPlatformOverviewMode.offlineWithoutCache,
      latency: Duration.zero,
    ).loadOverview();

    expect(withCache, isA<Offline<PlatformOverviewSnapshot>>());
    expect((withCache as Offline<PlatformOverviewSnapshot>).cached, isNotNull);
    expect(withoutCache, isA<Offline<PlatformOverviewSnapshot>>());
    expect(
      (withoutCache as Offline<PlatformOverviewSnapshot>).cached,
      isNull,
    );
  });
}
