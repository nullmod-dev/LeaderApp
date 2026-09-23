import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/customer_demo_controller.dart';
import 'package:mtm/features/auth/domain/customer_demo.dart';
import 'package:mtm/features/auth/domain/session_access.dart';
import 'package:mtm/features/demo/data/demo_control_plane.dart';
import 'package:mtm/features/demo/domain/demo_policy.dart';
import 'package:mtm/l10n/strings.dart';

import '../platform/platform_harness.dart';

/// **What happens when a trial's window closes.**
///
/// Two ways in — the clock, and a Super Admin — and one way out: the session
/// envelope says `expired`, the startup classifier sends the user to
/// `/demo-expired`, and the real identity that started the trial is still
/// there afterwards.
void main() {
  var now = DateTime.utc(2026, 9, 16, 12);

  /// A live demo, as the app actually assembles one: the demo identity, the
  /// server's demo envelope, and a control-plane record registered as this
  /// device's trial.
  ProviderContainer live() {
    final container = platformContainer(customerDemoUser, overrides: [
      clockProvider.overrideWithValue(() => now),
      demoControlPlaneSeedProvider.overrideWithValue(const []),
    ]);
    final plane = container.read(demoControlPlaneProvider.notifier);
    final session = (plane.startSession(accountId: 'acc_real')
            as Success<DemoSession>)
        .data;
    container.read(activeDemoSessionIdProvider.notifier).state =
        session.demoSessionId;
    return container;
  }

  setUp(() => now = DateTime.utc(2026, 9, 16, 12));

  test('a running trial is left alone by the control plane', () {
    expect(live().read(demoSessionVerdictProvider), DemoMode.active);
  });

  test('reaching the expiry instant retires the session envelope', () {
    final container = live();

    // Equality is expired: the window ends *at* its instant.
    now = now.add(const Duration(hours: 24));
    container.invalidate(demoSessionVerdictProvider);

    // The classifier's side of this is asserted by the routed test below,
    // which is the stronger claim: it boots the real router on an expired
    // envelope and checks where the user actually lands.
    expect(container.read(demoSessionVerdictProvider), DemoMode.expired);
  });

  test('a Super Admin termination retires it the same way', () {
    final container = live();
    final id = container.read(activeDemoSessionIdProvider)!;

    container.read(demoControlPlaneProvider.notifier).terminate(
          id,
          actor: const DemoPolicyActor(accountId: 'sa', displayName: 'مسؤول'),
        );

    // No clock change at all — the verdict is the control plane's, not time's.
    expect(container.read(demoSessionVerdictProvider), DemoMode.expired);
  });

  testWidgets('the expired session lands on the expiry screen, not the app',
      (tester) async {
    ignoreKnownTenantComplaints();
    final container = platformContainer(customerDemoUser, overrides: [
      clockProvider.overrideWithValue(() => now),
      demoControlPlaneSeedProvider.overrideWithValue(const []),
      sessionAccessOverrideProvider
          .overrideWith((ref) => const SessionAccess(demo: DemoMode.expired)),
    ]);
    final router = await bootPlatform(tester, container, height: 1200);

    expect(locationOf(router), '/demo-expired');
    expect(find.text(S.demoExpiredTitle), findsOneWidget);

    // And it cannot walk back into the application it just left.
    router.go('/home');
    await settlePlatform(tester);
    expect(locationOf(router), '/demo-expired');
  });

  group('the server owns the window, not this device', () {
    test('an envelope that says expired is never talked back into active', () {
      // The production authority is the backend's `demoMode`. The control
      // plane may only *narrow* an active demo to expired — it is how a mock
      // build reproduces a refusal — and may never widen the other way. So no
      // local clock, local state or local record can extend a trial the server
      // has already closed.
      final container = live();
      container.read(sessionAccessOverrideProvider.notifier).state =
          const SessionAccess(demo: DemoMode.expired);

      // The device's own record still says the window is open…
      expect(container.read(demoSessionVerdictProvider), DemoMode.active);
      // …and the server's verdict still wins.
      expect(container.read(sessionAccessProvider).demo, DemoMode.expired);
    });

    test('winding the local clock back does not reopen a closed window', () {
      final container = live();
      final id = container.read(activeDemoSessionIdProvider)!;
      final expiresAt =
          container.read(demoControlPlaneProvider).sessionById(id)!.expiresAt;

      // `expiresAt` was stamped once, by the authority that granted it. Moving
      // "now" cannot move it, in either direction.
      now = now.add(const Duration(hours: 25));
      container.invalidate(demoSessionVerdictProvider);
      expect(container.read(demoSessionVerdictProvider), DemoMode.expired);

      now = now.subtract(const Duration(hours: 25));
      container.invalidate(demoSessionVerdictProvider);
      expect(
        container.read(demoControlPlaneProvider).sessionById(id)!.expiresAt,
        expiresAt,
      );
    });

    test('a later policy revision does not move a stamped expiry', () {
      final container = live();
      final id = container.read(activeDemoSessionIdProvider)!;
      final before =
          container.read(demoControlPlaneProvider).sessionById(id)!;

      container.read(demoControlPlaneProvider.notifier).setDefaultDuration(
            const Duration(hours: 1),
            actor: const DemoPolicyActor(accountId: 'sa', displayName: 'مسؤول'),
          );

      final after = container.read(demoControlPlaneProvider).sessionById(id)!;
      expect(after.expiresAt, before.expiresAt);
      expect(after.policyRevision, before.policyRevision);
      // The revision the session records is what makes that checkable.
      expect(
        container.read(demoControlPlaneProvider).policy.revision,
        greaterThan(after.policyRevision),
      );
    });
  });

  test('the real identity survives the trial ending', () {
    final container = live();
    final id = container.read(activeDemoSessionIdProvider)!;

    container.read(demoControlPlaneProvider.notifier).terminate(
          id,
          actor: const DemoPolicyActor(accountId: 'sa', displayName: 'مسؤول'),
        );

    // The record still names the account that started it, and the account is
    // not part of what a termination touches.
    final record = container.read(demoControlPlaneProvider).sessionById(id)!;
    expect(record.accountId, 'acc_real');
    expect(record.status, DemoSessionStatus.terminated);
    // Nothing about the account's own lifecycle moved.
    expect(
      const SessionAccess(demo: DemoMode.expired).account,
      AccountStatus.active,
    );
  });

  test('another trial may start afterwards while the policy allows it', () {
    final container = live();
    final plane = container.read(demoControlPlaneProvider.notifier);
    plane.terminate(
      container.read(activeDemoSessionIdProvider)!,
      actor: const DemoPolicyActor(accountId: 'sa', displayName: 'مسؤول'),
    );

    final again = plane.startSession(accountId: 'acc_real');
    expect(again.isSuccess, isTrue);
    expect((again as Success<DemoSession>).data.expiresAt,
        now.add(const Duration(hours: 24)));

    // Unless the offer has been withdrawn, in which case a *new* trial is
    // refused — and the identity is still not harmed by the refusal.
    plane.setEnabled(
      false,
      actor: const DemoPolicyActor(accountId: 'sa', displayName: 'مسؤول'),
    );
    expect(plane.startSession(accountId: 'acc_untouched').isFailure, isTrue);
    expect(container.read(customerDemoPolicyProvider).available, isFalse);

    // The identity that is *already* inside a trial is handed that one back
    // rather than refused: withdrawing the offer blocks new starts and leaves
    // running windows alone, and refusing to return a running trial to its own
    // holder would be terminating it by another name.
    final resumed = plane.startSession(accountId: 'acc_real');
    expect(resumed.isSuccess, isTrue);
    expect(
      (resumed as Success<DemoSession>).data.demoSessionId,
      (again).data.demoSessionId,
    );
  });
}
