import '../domain/platform_audit_models.dart';
import '../../../l10n/strings.dart';

/// Immutable, clock-positioned platform audit examples for the local demo.
///
/// These snapshots contain only control-plane identifiers, display names and
/// typed changes. They deliberately contain no account, request, credential,
/// free-form reason or tenant-owned operational data.
class PlatformAuditFixtures {
  PlatformAuditFixtures({required DateTime Function() clock})
      : events = List.unmodifiable(_build(clock().toUtc()));

  final List<PlatformAuditEvent> events;

  static List<PlatformAuditEvent> _build(DateTime now) {
    const administrator = PlatformAuditAdministratorActor(
      id: 'u_demo_platform',
      displayName: 'مدير منصة ${S.productNameAr}',
    );
    const hilal = PlatformAuditTenantReference(
      id: 'saas_hilal',
      displayName: 'فرق الهلال الطبية',
      isDeleted: false,
    );
    const najd = PlatformAuditTenantReference(
      id: 'saas_najd',
      displayName: 'فريق نجد للاستجابة',
      isDeleted: false,
    );
    const retired = PlatformAuditTenantReference(
      id: 'saas_retired',
      displayName: 'فريق الريادة السابق',
      isDeleted: true,
    );

    PlatformAuditEvent event({
      required String id,
      required Duration ago,
      PlatformAuditActor actor = administrator,
      required PlatformAuditAction action,
      required PlatformAuditTarget target,
      PlatformAuditTenantReference? tenant,
      List<PlatformAuditChange> changes = const [],
    }) =>
        PlatformAuditEvent(
          id: id,
          occurredAt: now.subtract(ago),
          actor: actor,
          action: action,
          target: target,
          tenant: tenant,
          changes: changes,
        );

    const sameInstant = Duration(hours: 2);
    return [
      event(
        id: 'audit_011',
        ago: const Duration(minutes: 15),
        action: PlatformAuditAction.featureFlagChanged,
        target: const PlatformAuditTarget(
          type: PlatformAuditTargetResource.tenantFeature,
          id: 'tenant-feature:saas_hilal:workshops',
          displayName: 'وحدة الورش',
        ),
        tenant: hilal,
        changes: const [
          PlatformAuditChange(
            field: PlatformAuditChangeField.featureEnabled,
            before: PlatformAuditBoolValue(false),
            after: PlatformAuditBoolValue(true),
          ),
        ],
      ),
      event(
        id: 'audit_010',
        ago: const Duration(hours: 1),
        action: PlatformAuditAction.limitOverrideChanged,
        target: const PlatformAuditTarget(
          type: PlatformAuditTargetResource.tenantLimit,
          id: 'tenant-limit:saas_hilal:detachments',
          displayName: 'حد المفارز',
        ),
        tenant: hilal,
        changes: const [
          PlatformAuditChange(
            field: PlatformAuditChangeField.limitOverride,
            before: PlatformAuditIntegerValue(10),
            after: PlatformAuditIntegerValue(20),
          ),
        ],
      ),
      event(
        id: 'audit_009',
        ago: sameInstant,
        action: PlatformAuditAction.planChanged,
        target: const PlatformAuditTarget(
          type: PlatformAuditTargetResource.planAssignment,
          id: 'plan-assignment:saas_hilal',
          displayName: 'باقة فرق الهلال',
        ),
        tenant: hilal,
        changes: const [
          PlatformAuditChange(
            field: PlatformAuditChangeField.planAssignment,
            before: PlatformAuditTextValue('mtm_standard'),
            after: PlatformAuditTextValue('mtm_advanced'),
          ),
        ],
      ),
      event(
        id: 'audit_008',
        ago: sameInstant,
        action: PlatformAuditAction.tenantReactivated,
        target: const PlatformAuditTarget(
          type: PlatformAuditTargetResource.tenantLifecycle,
          id: 'tenant-lifecycle:saas_hilal',
          displayName: 'حالة فرق الهلال',
        ),
        tenant: hilal,
        changes: const [
          PlatformAuditChange(
            field: PlatformAuditChangeField.lifecycleStatus,
            before: PlatformAuditTextValue('suspended'),
            after: PlatformAuditTextValue('active'),
          ),
        ],
      ),
      event(
        id: 'audit_007',
        ago: const Duration(hours: 5),
        action: PlatformAuditAction.tenantSuspended,
        target: const PlatformAuditTarget(
          type: PlatformAuditTargetResource.tenantLifecycle,
          id: 'tenant-lifecycle:saas_hilal',
          displayName: 'حالة فرق الهلال',
        ),
        tenant: hilal,
        changes: const [
          PlatformAuditChange(
            field: PlatformAuditChangeField.lifecycleStatus,
            before: PlatformAuditTextValue('active'),
            after: PlatformAuditTextValue('suspended'),
          ),
        ],
      ),
      event(
        id: 'audit_006',
        ago: const Duration(days: 1),
        action: PlatformAuditAction.deletionCancelled,
        target: const PlatformAuditTarget(
          type: PlatformAuditTargetResource.tenantLifecycle,
          id: 'tenant-lifecycle:saas_najd',
          displayName: 'حالة فريق نجد',
        ),
        tenant: najd,
        changes: const [
          PlatformAuditChange(
            field: PlatformAuditChangeField.lifecycleStatus,
            before: PlatformAuditTextValue('deletion_pending'),
            after: PlatformAuditTextValue('active'),
          ),
        ],
      ),
      event(
        id: 'audit_005',
        ago: const Duration(days: 2),
        action: PlatformAuditAction.deletionRequested,
        target: const PlatformAuditTarget(
          type: PlatformAuditTargetResource.tenantLifecycle,
          id: 'tenant-lifecycle:saas_najd',
          displayName: 'حالة فريق نجد',
        ),
        tenant: najd,
        changes: const [
          PlatformAuditChange(
            field: PlatformAuditChangeField.lifecycleStatus,
            before: PlatformAuditTextValue('active'),
            after: PlatformAuditTextValue('deletion_pending'),
          ),
        ],
      ),
      event(
        id: 'audit_004',
        ago: const Duration(days: 4),
        action: PlatformAuditAction.tenantRegistered,
        target: const PlatformAuditTarget(
          type: PlatformAuditTargetResource.tenant,
          id: 'saas_najd',
          displayName: 'فريق نجد للاستجابة',
        ),
        tenant: najd,
      ),
      event(
        id: 'audit_003',
        ago: const Duration(days: 7),
        actor: const PlatformAuditSystemActor(),
        action: PlatformAuditAction.deletionFinalized,
        target: const PlatformAuditTarget(
          type: PlatformAuditTargetResource.tenantLifecycle,
          id: 'tenant-lifecycle:saas_retired',
          displayName: 'سجل حذف فريق الريادة',
        ),
        tenant: retired,
        changes: const [
          PlatformAuditChange(
            field: PlatformAuditChangeField.lifecycleStatus,
            before: PlatformAuditTextValue('deletion_pending'),
            after: PlatformAuditTextValue('deleted'),
          ),
        ],
      ),
      PlatformAuditEvent.fromJson({
        'id': 'audit_002',
        'occurredAt': now.subtract(const Duration(days: 9)).toIso8601String(),
        'actor': const {'kind': 'future_actor'},
        'action': 'future_action',
        'target': const {
          'type': 'future_resource',
          'id': 'future-resource-1',
          'displayName': 'مورد غير معروف',
        },
        'changes': const [
          {
            'field': 'future_private_field',
            'before': {'kind': 'text', 'value': 'discarded-at-boundary'},
            'after': {'kind': 'text', 'value': 'discarded-at-boundary'},
          },
        ],
      }),
    ];
  }
}
