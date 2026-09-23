import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/demo/data/demo_control_plane.dart';
import 'package:mtm/features/demo/domain/demo_policy.dart';
import 'package:mtm/features/platform/data/platform_demo_providers.dart';
import 'package:mtm/features/platform/presentation/platform_demo_copy.dart';
import 'package:mtm/features/platform/presentation/platform_demo_page.dart';
import 'package:mtm/features/platform/presentation/platform_operations_routes.dart';
import 'package:mtm/l10n/strings.dart';

import 'platform_harness.dart';

/// The confirmation dialog's own confirm button. Matched by key, not by its
/// label: several of these labels also sit on the page behind the dialog.
final _confirm = find.byKey(const Key('platform-confirmation-confirm'));

/// Scrolls a control into view, then taps it.
Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await settlePlatform(tester);
}

/// `/platform/operations/demo` — «إدارة الحسابات التجريبية» as an operator
/// meets it: reached from Operations, showing the real policy, and acting on
/// the real control plane.
void main() {
  final now = DateTime.utc(2026, 9, 16, 12);

  DemoSession seeded({
    required String id,
    required String name,
    required Duration in_,
  }) =>
      DemoSession(
        demoSessionId: id,
        accountId: 'acc_$id',
        demoWorkspaceId: 'dws_$id',
        displayName: name,
        startedAt: now.subtract(const Duration(hours: 1)),
        expiresAt: now.add(in_),
        status: DemoSessionStatus.active,
        policyRevision: 1,
      );

  ProviderContainer container({List<DemoSession> seed = const []}) =>
      platformContainer(superAdmin, overrides: [
        clockProvider.overrideWithValue(() => now),
        demoControlPlaneSeedProvider.overrideWithValue(seed),
      ]);

  Future<ProviderContainer> open(
    WidgetTester tester, {
    List<DemoSession> seed = const [],
    double width = 400,
    double textScale = 1,
  }) async {
    ignoreKnownTenantComplaints();
    final c = container(seed: seed);
    final router = await bootPlatform(
      tester,
      c,
      width: width,
      height: 1400,
      textScale: textScale,
    );
    router.go(PlatformOperationsRoutes.demo);
    await settlePlatform(tester);
    return c;
  }

  testWidgets('Operations offers exactly one way into Demo management',
      (tester) async {
    ignoreKnownTenantComplaints();
    final c = container();
    final router = await bootPlatform(tester, c, height: 1400);
    router.go('/platform/operations');
    await settlePlatform(tester);

    expect(find.byKey(const Key('platform-operations-demo')), findsOneWidget);
    expect(find.text(S.platformOpsDemo), findsOneWidget);

    await _tap(tester, const Key('platform-operations-demo'));

    // Pushed inside the Operations branch, exactly as Health and Audit are:
    // the shell stays, and back returns to the area it was opened from.
    expect(find.byType(PlatformDemoPage), findsOneWidget);
    expect(router.canPop(), isTrue);
    expect(find.text(S.platformDemoTitle), findsWidgets);
  });

  testWidgets('the policy card opens on the 24-hour product default',
      (tester) async {
    await open(tester);

    expect(find.byKey(const Key('platform-demo-duration-value')),
        findsOneWidget);
    // «يوم واحد» — the default spoken in the unit it was set in, not «24h».
    expect(
      tester
          .widget<Text>(find.byKey(const Key('platform-demo-duration-value')))
          .data,
      PlatformDemoCopy.duration(const Duration(hours: 24)),
    );
    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const Key('platform-demo-enabled')),
    );
    expect(toggle.value, isTrue);
    // The state is in words as well as in the thumb's position.
    expect(find.text(S.platformDemoAvailabilityOn), findsOneWidget);
    expect(find.text(S.platformDemoPolicyNeverUpdated), findsOneWidget);
  });

  testWidgets('stepping the duration writes the policy for new sessions only',
      (tester) async {
    final running = seeded(
      id: 'running',
      name: 'زائر',
      in_: const Duration(hours: 20),
    );
    final c = await open(tester, seed: [running]);

    await _tap(tester, const Key('platform-demo-duration-increase'));

    final policy = c.read(demoPolicyProvider);
    expect(policy.defaultDuration, const Duration(hours: 48));
    expect(policy.revision, 2);
    expect(policy.updatedBy?.accountId, superAdmin.id);
    // The trial already running kept its own window.
    expect(
      c.read(demoControlPlaneProvider).sessionById('running')!.expiresAt,
      running.expiresAt,
    );
    expect(find.text(S.platformDemoDurationDone), findsOneWidget);
  });

  testWidgets('disabling is confirmed, blocks new trials, and ends none',
      (tester) async {
    final c = await open(
      tester,
      seed: [seeded(id: 'a', name: 'زائر', in_: const Duration(hours: 5))],
    );

    await _tap(tester, const Key('platform-demo-enabled'));

    // The confirmation says both halves: what stops, and what does not.
    expect(find.text(S.platformDemoDisableConfirmTitle), findsOneWidget);
    expect(find.text(S.platformDemoDisableConfirmUnchanged), findsOneWidget);
    // Still enabled until it is confirmed.
    expect(c.read(demoPolicyProvider).enabled, isTrue);

    await tester.tap(_confirm);
    await settlePlatform(tester);

    expect(c.read(demoPolicyProvider).enabled, isFalse);
    // The running trial is untouched — disabling is not a mass eviction.
    expect(c.read(activeDemoSessionsProvider), hasLength(1));
    expect(find.text(S.platformDemoAvailabilityOff), findsOneWidget);
  });

  testWidgets('the list is ordered by what expires soonest, not by arrival',
      (tester) async {
    // The operator reads this list to decide what to do about the trials that
    // are nearly over, so the most urgent one is the one that must be first —
    // whatever order the records arrived in.
    final c = await open(tester, seed: [
      seeded(id: 'late', name: 'زائر متأخر', in_: const Duration(hours: 20)),
      seeded(id: 'soon', name: 'زائر وشيك', in_: const Duration(hours: 1)),
      seeded(id: 'mid', name: 'زائر وسط', in_: const Duration(hours: 9)),
    ]);

    expect(
      c.read(activeDemoSessionsProvider).map((s) => s.demoSessionId).toList(),
      ['soon', 'mid', 'late'],
    );
    // And the row an operator reads is named by the person, never by the id.
    expect(find.text('زائر وشيك'), findsOneWidget);
    expect(find.textContaining('soon'), findsNothing);
  });

  testWidgets('a session row shows its window and terminates on confirmation',
      (tester) async {
    final c = await open(tester, seed: [
      seeded(id: 'a', name: 'زائر أول', in_: const Duration(hours: 5)),
      seeded(id: 'b', name: 'زائر ثانٍ', in_: const Duration(hours: 9)),
    ]);

    // Soonest to expire first — the order the list is read in.
    expect(c.read(activeDemoSessionsProvider).first.demoSessionId, 'a');
    expect(find.text('زائر أول'), findsOneWidget);
    expect(find.text(S.platformDemoSessionRemaining), findsWidgets);

    await _tap(tester, const Key('platform-demo-terminate-a'));
    expect(find.text(S.platformDemoTerminateConfirmTitle), findsOneWidget);
    // The confirmation promises the real account survives.
    expect(find.text(S.platformDemoTerminateConfirmUnchanged), findsOneWidget);

    await tester.tap(_confirm);
    await settlePlatform(tester);

    final remaining = c.read(activeDemoSessionsProvider);
    expect(remaining, hasLength(1));
    expect(remaining.single.demoSessionId, 'b');
    expect(
      c.read(demoControlPlaneProvider).sessionById('a')!.status,
      DemoSessionStatus.terminated,
    );
  });

  testWidgets('terminate-all empties the list and reports the count',
      (tester) async {
    final c = await open(tester, seed: [
      seeded(id: 'a', name: 'أ', in_: const Duration(hours: 2)),
      seeded(id: 'b', name: 'ب', in_: const Duration(hours: 4)),
    ]);

    await _tap(tester, const Key('platform-demo-terminate-all'));
    await tester.tap(_confirm);
    await settlePlatform(tester);

    expect(c.read(activeDemoSessionsProvider), isEmpty);
    expect(
      find.text(PlatformDemoCopy.count(S.platformDemoTerminatedAllDone, 2)),
      findsOneWidget,
    );
    expect(find.byKey(const Key('platform-demo-empty')), findsOneWidget);
  });

  testWidgets('cleaning drops expired records and keeps terminated ones',
      (tester) async {
    final c = await open(tester, seed: [
      seeded(id: 'gone', name: 'منتهٍ', in_: const Duration(hours: -3)),
      seeded(id: 'live', name: 'نشط', in_: const Duration(hours: 3)),
    ]);

    expect(c.read(demoSessionCountsProvider).expired, 1);

    await _tap(tester, const Key('platform-demo-clean-expired'));
    await tester.tap(_confirm);
    await settlePlatform(tester);

    final state = c.read(demoControlPlaneProvider);
    expect(state.sessionById('gone'), isNull);
    expect(state.sessionById('live'), isNotNull);
  });

  testWidgets('no session id, workspace id or token reaches the screen',
      (tester) async {
    await open(tester, seed: [
      seeded(id: 'sess_secret_1', name: 'زائر', in_: const Duration(hours: 3)),
    ]);

    // The row names the person, never the opaque identifiers behind them.
    expect(find.text('زائر'), findsOneWidget);
    expect(find.textContaining('sess_secret_1'), findsNothing);
    expect(find.textContaining('dws_'), findsNothing);
  });

  testWidgets('a non-Super-Admin never reaches the screen at all',
      (tester) async {
    ignoreKnownTenantComplaints();
    final c = platformContainer(fullTenantAdmin, overrides: [
      clockProvider.overrideWithValue(() => now),
      demoControlPlaneSeedProvider.overrideWithValue(const []),
    ]);
    final router = await bootPlatform(tester, c, height: 1400);

    router.go(PlatformOperationsRoutes.demo);
    await settlePlatform(tester);

    // Bounced by the platform gate, not by a role check inside the widget.
    expect(locationOf(router), isNot(PlatformOperationsRoutes.demo));
    expect(find.text(S.platformDemoTitle), findsNothing);
    // And the control plane would refuse it anyway: no actor, no authority.
    expect(c.read(platformDemoActorProvider), isNull);
    expect(
      c.read(platformDemoActionsProvider).setEnabled(false).isFailure,
      isTrue,
    );
    expect(c.read(demoPolicyProvider).enabled, isTrue);
  });

  testWidgets('it survives 320dp at a 1.6 text scale', (tester) async {
    await open(
      tester,
      width: 320,
      textScale: 1.6,
      seed: [seeded(id: 'a', name: 'زائر', in_: const Duration(hours: 3))],
    );

    expect(tester.takeException(), isNull);
    expect(find.text(S.platformDemoTitle), findsWidgets);
  });
}
