import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/features/platform/domain/tenant_lifecycle_models.dart';

void main() {
  final now = DateTime.utc(2026, 9, 9, 12);

  SaasTenantLifecycle suspended({int version = 1}) => SaasTenantLifecycle(
        status: SaasTenantStatus.suspended,
        version: version,
        suspension: TenantSuspensionMetadata(
          suspendedAt: now.subtract(const Duration(days: 2)),
          reason: 'مراجعة إدارية',
        ),
      );

  SaasTenantLifecycle allowed(
    SaasTenantLifecycle current,
    TenantLifecycleAction action, {
    String? reason,
    DateTime? at,
  }) {
    final decision = TenantLifecyclePolicy.transition(
      current: current,
      action: action,
      now: at ?? now,
      reason: reason,
    );
    expect(decision, isA<TenantLifecycleTransitionAllowed>());
    return (decision as TenantLifecycleTransitionAllowed).next;
  }

  group('canonical parsing fails closed', () {
    test('recognises exactly the four operational states', () {
      expect(
        SaasTenantStatus.values.map((status) => status.wire),
        ['active', 'suspended', 'deletion_pending', 'deleted'],
      );
      expect(SaasTenantStatus.tryParse('archived'), isNull);
      expect(SaasTenantStatus.tryParse('pending_review'), isNull);
    });

    test('only active permits tenant operational access', () {
      expect(SaasTenantStatus.active.blocksTenantAccess, isFalse);
      for (final status in SaasTenantStatus.values.skip(1)) {
        expect(status.blocksTenantAccess, isTrue, reason: status.wire);
      }
    });
  });

  group('legal transition matrix', () {
    test('active to suspended', () {
      final next = allowed(
        SaasTenantLifecycle.active(version: 4),
        TenantLifecycleAction.suspend,
        reason: '  سبب   إداري  ',
      );
      expect(next.status, SaasTenantStatus.suspended);
      expect(next.version, 5);
      expect(next.suspension?.reason, 'سبب إداري');
    });

    test('suspended to active clears suspension metadata', () {
      final next =
          allowed(suspended(version: 4), TenantLifecycleAction.reactivate);
      expect(next.status, SaasTenantStatus.active);
      expect(next.version, 5);
      expect(next.suspension, isNull);
    });

    test('active to deletion pending records exact restore state', () {
      final next = allowed(
        SaasTenantLifecycle.active(version: 7),
        TenantLifecycleAction.beginDeletion,
        reason: 'طلب تعاقدي موثق',
      );
      expect(next.status, SaasTenantStatus.deletionPending);
      expect(next.deletion?.previousStatus, TenantDeletionRestoreStatus.active);
      expect(next.deletion?.requestedAt, now);
      expect(next.deletion?.scheduledFor,
          now.add(kProvisionalTenantDeletionGrace));
    });

    test('suspended to deletion pending preserves suspended restore state', () {
      final before = suspended(version: 2);
      final next = allowed(
        before,
        TenantLifecycleAction.beginDeletion,
        reason: 'إنهاء موثق',
      );
      expect(
          next.deletion?.previousStatus, TenantDeletionRestoreStatus.suspended);
      expect(next.suspension, same(before.suspension));
    });

    test('cancel pending restores active when active preceded request', () {
      final pending = allowed(
        SaasTenantLifecycle.active(version: 3),
        TenantLifecycleAction.beginDeletion,
        reason: 'سبب',
      );
      final restored = allowed(pending, TenantLifecycleAction.cancelDeletion,
          at: now.add(const Duration(days: 1)));
      expect(restored.status, SaasTenantStatus.active);
      expect(restored.version, 5);
    });

    test('cancel pending restores suspended with its original metadata', () {
      final before = suspended(version: 3);
      final pending = allowed(
        before,
        TenantLifecycleAction.beginDeletion,
        reason: 'سبب',
      );
      final restored = allowed(pending, TenantLifecycleAction.cancelDeletion,
          at: now.add(const Duration(days: 1)));
      expect(restored.status, SaasTenantStatus.suspended);
      expect(restored.suspension, same(before.suspension));
    });

    test('pending finalizes only when the configured window is effective', () {
      final pending = allowed(
        SaasTenantLifecycle.active(),
        TenantLifecycleAction.beginDeletion,
        reason: 'سبب',
      );
      final tooEarly = TenantLifecyclePolicy.transition(
        current: pending,
        action: TenantLifecycleAction.finalizeDeletion,
        now: now.add(const Duration(days: 29)),
      );
      expect(
        (tooEarly as TenantLifecycleTransitionRefused).problem,
        TenantLifecycleTransitionProblem.deletionNotEffective,
      );

      final deleted = allowed(
        pending,
        TenantLifecycleAction.finalizeDeletion,
        at: now.add(const Duration(days: 30)),
      );
      expect(deleted.status, SaasTenantStatus.deleted);
      expect(deleted.deletion?.deletedAt, now.add(const Duration(days: 30)));
    });

    test('cancel is refused once the configured window expires', () {
      final pending = allowed(
        SaasTenantLifecycle.active(),
        TenantLifecycleAction.beginDeletion,
        reason: 'سبب',
      );
      final decision = TenantLifecyclePolicy.transition(
        current: pending,
        action: TenantLifecycleAction.cancelDeletion,
        now: pending.deletion!.scheduledFor,
      );
      expect(
        (decision as TenantLifecycleTransitionRefused).problem,
        TenantLifecycleTransitionProblem.deletionWindowExpired,
      );
    });

    test('deleted rejects every normal action', () {
      final pending = allowed(
        SaasTenantLifecycle.active(),
        TenantLifecycleAction.beginDeletion,
        reason: 'سبب',
      );
      final deleted = allowed(
        pending,
        TenantLifecycleAction.finalizeDeletion,
        at: pending.deletion!.scheduledFor,
      );
      for (final action in TenantLifecycleAction.values) {
        final decision = TenantLifecyclePolicy.transition(
          current: deleted,
          action: action,
          now: pending.deletion!.scheduledFor,
          reason: 'سبب',
        );
        expect(decision, isA<TenantLifecycleTransitionRefused>(),
            reason: action.name);
      }
    });

    test('every other illegal transition is safely refused', () {
      final cases = [
        (SaasTenantLifecycle.active(), TenantLifecycleAction.reactivate),
        (SaasTenantLifecycle.active(), TenantLifecycleAction.cancelDeletion),
        (suspended(), TenantLifecycleAction.suspend),
        (suspended(), TenantLifecycleAction.finalizeDeletion),
      ];
      for (final (current, action) in cases) {
        expect(
          TenantLifecyclePolicy.transition(
            current: current,
            action: action,
            now: now,
            reason: 'سبب',
          ),
          isA<TenantLifecycleTransitionRefused>(),
          reason: '${current.status.wire} / ${action.name}',
        );
      }
    });
  });

  group('metadata safety', () {
    test('transition policy refuses a missing reason as a typed problem', () {
      final decision = TenantLifecyclePolicy.transition(
        current: SaasTenantLifecycle.active(),
        action: TenantLifecycleAction.suspend,
        now: now,
      );
      expect(
        (decision as TenantLifecycleTransitionRefused).problem,
        TenantLifecycleTransitionProblem.invalidReason,
      );
    });

    test('reason is required, normalized, and bounded', () {
      expect(
        () => TenantSuspensionMetadata(suspendedAt: now, reason: '   '),
        throwsArgumentError,
      );
      expect(
        () => TenantSuspensionMetadata(
          suspendedAt: now,
          reason: List.filled(
            kTenantLifecycleReasonMaxLength + 1,
            'x',
          ).join(),
        ),
        throwsArgumentError,
      );
    });

    test('lifecycle JSON round-trips deletion metadata', () {
      final pending = allowed(
        suspended(version: 9),
        TenantLifecycleAction.beginDeletion,
        reason: 'طلب موثق',
      );
      expect(
        SaasTenantLifecycle.fromJson(pending.toJson()).toJson(),
        pending.toJson(),
      );
    });
  });
}
