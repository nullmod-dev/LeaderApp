library;

import 'package:flutter/foundation.dart';

import '../../../core/access/saas_tenant_status.dart';

/// A deterministic mock default only. The backend must return the effective
/// platform policy and is free to use a different configured duration.
const Duration kProvisionalTenantDeletionGrace = Duration(days: 30);

const int kTenantLifecycleReasonMaxLength = 280;

enum TenantLifecycleAction {
  suspend,
  reactivate,
  beginDeletion,
  cancelDeletion,
  finalizeDeletion,
}

/// The only two states to which a pending deletion may be cancelled.
enum TenantDeletionRestoreStatus {
  active('active', SaasTenantStatus.active),
  suspended('suspended', SaasTenantStatus.suspended);

  const TenantDeletionRestoreStatus(this.wire, this.status);

  final String wire;
  final SaasTenantStatus status;

  static TenantDeletionRestoreStatus? parse(String? wire) {
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return null;
  }

  static TenantDeletionRestoreStatus fromStatus(SaasTenantStatus status) =>
      switch (status) {
        SaasTenantStatus.active => TenantDeletionRestoreStatus.active,
        SaasTenantStatus.suspended => TenantDeletionRestoreStatus.suspended,
        SaasTenantStatus.deletionPending ||
        SaasTenantStatus.deleted =>
          throw ArgumentError.value(status, 'status', 'not restorable'),
      };
}

@immutable
class TenantSuspensionMetadata {
  TenantSuspensionMetadata({
    required this.suspendedAt,
    required String reason,
  }) : reason = normalizeTenantLifecycleReason(reason) {
    validateTenantLifecycleReason(this.reason);
  }

  final DateTime suspendedAt;

  /// Platform-only administrative context. Tenant-facing screens stay generic.
  final String reason;

  factory TenantSuspensionMetadata.fromJson(Map<String, dynamic> json) =>
      TenantSuspensionMetadata(
        suspendedAt: _date(json['suspendedAt']),
        reason: json['reason'] as String,
      );

  Map<String, dynamic> toJson() => {
        'suspendedAt': suspendedAt.toUtc().toIso8601String(),
        'reason': reason,
      };
}

@immutable
class TenantDeletionMetadata {
  TenantDeletionMetadata({
    required this.requestedAt,
    required this.scheduledFor,
    required this.previousStatus,
    required String reason,
    this.deletedAt,
  }) : reason = normalizeTenantLifecycleReason(reason) {
    validateTenantLifecycleReason(this.reason);
    if (scheduledFor.toUtc().isBefore(requestedAt.toUtc())) {
      throw ArgumentError('scheduledFor must not precede requestedAt');
    }
  }

  final DateTime requestedAt;
  final DateTime scheduledFor;
  final TenantDeletionRestoreStatus previousStatus;

  /// Platform-only administrative context. It is not exposed to tenant users.
  final String reason;

  /// Present only after the backend-controlled final destructive operation.
  final DateTime? deletedAt;

  bool get isFinalized => deletedAt != null;

  TenantDeletionMetadata finalize(DateTime at) => TenantDeletionMetadata(
        requestedAt: requestedAt,
        scheduledFor: scheduledFor,
        previousStatus: previousStatus,
        reason: reason,
        deletedAt: at.toUtc(),
      );

  factory TenantDeletionMetadata.fromJson(Map<String, dynamic> json) {
    final previous =
        TenantDeletionRestoreStatus.parse(json['previousStatus'] as String?);
    if (previous == null) {
      throw FormatException(
        'unknown deletion restore status',
        json['previousStatus'],
      );
    }
    return TenantDeletionMetadata(
      requestedAt: _date(json['requestedAt']),
      scheduledFor: _date(json['scheduledFor']),
      previousStatus: previous,
      reason: json['reason'] as String,
      deletedAt: _optionalDate(json['deletedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'requestedAt': requestedAt.toUtc().toIso8601String(),
        'scheduledFor': scheduledFor.toUtc().toIso8601String(),
        'previousStatus': previousStatus.wire,
        'reason': reason,
        if (deletedAt != null)
          'deletedAt': deletedAt!.toUtc().toIso8601String(),
      };
}

/// Versioned lifecycle state embedded in the canonical tenant record.
///
/// Constructor invariants make impossible combinations unrepresentable: a
/// pending deletion always carries its schedule and restore state, an active
/// tenant carries neither deletion nor suspension metadata, and a deleted
/// state always has a finalization timestamp.
@immutable
class SaasTenantLifecycle {
  SaasTenantLifecycle({
    required this.status,
    required this.version,
    this.suspension,
    this.deletion,
  }) {
    if (version < 1) throw ArgumentError.value(version, 'version');
    switch (status) {
      case SaasTenantStatus.active:
        if (suspension != null || deletion != null) {
          throw ArgumentError('active lifecycle cannot carry metadata');
        }
      case SaasTenantStatus.suspended:
        if (suspension == null || deletion != null) {
          throw ArgumentError('suspended lifecycle requires suspension only');
        }
      case SaasTenantStatus.deletionPending:
        if (deletion == null || deletion!.isFinalized) {
          throw ArgumentError('pending deletion requires an open schedule');
        }
        if (deletion!.previousStatus == TenantDeletionRestoreStatus.suspended &&
            suspension == null) {
          throw ArgumentError('suspended restore requires suspension metadata');
        }
        if (deletion!.previousStatus == TenantDeletionRestoreStatus.active &&
            suspension != null) {
          throw ArgumentError(
              'active restore cannot carry suspension metadata');
        }
      case SaasTenantStatus.deleted:
        if (suspension != null || deletion == null || !deletion!.isFinalized) {
          throw ArgumentError('deleted lifecycle requires finalized deletion');
        }
    }
  }

  factory SaasTenantLifecycle.active({int version = 1}) =>
      SaasTenantLifecycle(status: SaasTenantStatus.active, version: version);

  final SaasTenantStatus status;

  /// Optimistic-concurrency token for lifecycle mutations only.
  final int version;
  final TenantSuspensionMetadata? suspension;
  final TenantDeletionMetadata? deletion;

  factory SaasTenantLifecycle.fromJson(Map<String, dynamic> json) {
    final status = SaasTenantStatus.parse(json['status'] as String?);
    if (status == null) {
      throw FormatException('unknown tenant lifecycle status', json['status']);
    }
    return SaasTenantLifecycle(
      status: status,
      version: (json['version'] as num).toInt(),
      suspension: json['suspension'] == null
          ? null
          : TenantSuspensionMetadata.fromJson(
              json['suspension'] as Map<String, dynamic>,
            ),
      deletion: json['deletion'] == null
          ? null
          : TenantDeletionMetadata.fromJson(
              json['deletion'] as Map<String, dynamic>,
            ),
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status.wire,
        'version': version,
        if (suspension != null) 'suspension': suspension!.toJson(),
        if (deletion != null) 'deletion': deletion!.toJson(),
      };
}

enum TenantLifecycleTransitionProblem {
  invalidTransition,
  invalidReason,
  deletionWindowExpired,
  deletionNotEffective,
}

sealed class TenantLifecycleTransitionDecision {
  const TenantLifecycleTransitionDecision();
}

class TenantLifecycleTransitionAllowed
    extends TenantLifecycleTransitionDecision {
  const TenantLifecycleTransitionAllowed(this.next);

  final SaasTenantLifecycle next;
}

class TenantLifecycleTransitionRefused
    extends TenantLifecycleTransitionDecision {
  const TenantLifecycleTransitionRefused(this.problem);

  final TenantLifecycleTransitionProblem problem;
}

/// The sole pure transition policy. Repositories ask it for a next state;
/// callers never assign a lifecycle enum directly.
abstract final class TenantLifecyclePolicy {
  static TenantLifecycleTransitionDecision transition({
    required SaasTenantLifecycle current,
    required TenantLifecycleAction action,
    required DateTime now,
    String? reason,
    Duration deletionGrace = kProvisionalTenantDeletionGrace,
  }) {
    final at = now.toUtc();
    final normalizedReason = normalizeTenantLifecycleReason(reason ?? '');
    if (action == TenantLifecycleAction.suspend ||
        action == TenantLifecycleAction.beginDeletion) {
      try {
        validateTenantLifecycleReason(normalizedReason);
      } on ArgumentError {
        return const TenantLifecycleTransitionRefused(
          TenantLifecycleTransitionProblem.invalidReason,
        );
      }
    }
    switch ((current.status, action)) {
      case (SaasTenantStatus.active, TenantLifecycleAction.suspend):
        return TenantLifecycleTransitionAllowed(SaasTenantLifecycle(
          status: SaasTenantStatus.suspended,
          version: current.version + 1,
          suspension: TenantSuspensionMetadata(
            suspendedAt: at,
            reason: normalizedReason,
          ),
        ));
      case (SaasTenantStatus.suspended, TenantLifecycleAction.reactivate):
        return TenantLifecycleTransitionAllowed(
          SaasTenantLifecycle.active(version: current.version + 1),
        );
      case (
          SaasTenantStatus.active || SaasTenantStatus.suspended,
          TenantLifecycleAction.beginDeletion
        ):
        return TenantLifecycleTransitionAllowed(SaasTenantLifecycle(
          status: SaasTenantStatus.deletionPending,
          version: current.version + 1,
          suspension: current.suspension,
          deletion: TenantDeletionMetadata(
            requestedAt: at,
            scheduledFor: at.add(deletionGrace),
            previousStatus:
                TenantDeletionRestoreStatus.fromStatus(current.status),
            reason: normalizedReason,
          ),
        ));
      case (
          SaasTenantStatus.deletionPending,
          TenantLifecycleAction.cancelDeletion
        ):
        final deletion = current.deletion!;
        if (!at.isBefore(deletion.scheduledFor.toUtc())) {
          return const TenantLifecycleTransitionRefused(
            TenantLifecycleTransitionProblem.deletionWindowExpired,
          );
        }
        return TenantLifecycleTransitionAllowed(
          deletion.previousStatus == TenantDeletionRestoreStatus.active
              ? SaasTenantLifecycle.active(version: current.version + 1)
              : SaasTenantLifecycle(
                  status: SaasTenantStatus.suspended,
                  version: current.version + 1,
                  suspension: current.suspension,
                ),
        );
      case (
          SaasTenantStatus.deletionPending,
          TenantLifecycleAction.finalizeDeletion
        ):
        final deletion = current.deletion!;
        if (at.isBefore(deletion.scheduledFor.toUtc())) {
          return const TenantLifecycleTransitionRefused(
            TenantLifecycleTransitionProblem.deletionNotEffective,
          );
        }
        return TenantLifecycleTransitionAllowed(SaasTenantLifecycle(
          status: SaasTenantStatus.deleted,
          version: current.version + 1,
          deletion: deletion.finalize(at),
        ));
      default:
        return const TenantLifecycleTransitionRefused(
          TenantLifecycleTransitionProblem.invalidTransition,
        );
    }
  }
}

String normalizeTenantLifecycleReason(String raw) =>
    raw.trim().replaceAll(RegExp(r'\s+'), ' ');

void validateTenantLifecycleReason(String reason) {
  if (reason.isEmpty) {
    throw ArgumentError.value(reason, 'reason', 'must not be empty');
  }
  if (reason.length > kTenantLifecycleReasonMaxLength) {
    throw ArgumentError.value(reason, 'reason', 'is too long');
  }
}

@immutable
class TenantLifecycleCommand {
  const TenantLifecycleCommand({
    required this.tenantId,
    required this.expectedVersion,
    required this.idempotencyKey,
  });

  final String tenantId;
  final int expectedVersion;
  final String idempotencyKey;
}

class SuspendTenantCommand extends TenantLifecycleCommand {
  const SuspendTenantCommand({
    required super.tenantId,
    required super.expectedVersion,
    required super.idempotencyKey,
    required this.reason,
  });

  final String reason;
}

class ReactivateTenantCommand extends TenantLifecycleCommand {
  const ReactivateTenantCommand({
    required super.tenantId,
    required super.expectedVersion,
    required super.idempotencyKey,
  });
}

class BeginTenantDeletionCommand extends TenantLifecycleCommand {
  const BeginTenantDeletionCommand({
    required super.tenantId,
    required super.expectedVersion,
    required super.idempotencyKey,
    required this.reason,
  });

  final String reason;
}

class CancelTenantDeletionCommand extends TenantLifecycleCommand {
  const CancelTenantDeletionCommand({
    required super.tenantId,
    required super.expectedVersion,
    required super.idempotencyKey,
  });
}

class FinalizeTenantDeletionCommand extends TenantLifecycleCommand {
  const FinalizeTenantDeletionCommand({
    required super.tenantId,
    required super.expectedVersion,
    required super.idempotencyKey,
  });
}

String tenantLifecycleIdempotencyKey({
  required String tenantId,
  required int expectedVersion,
  required TenantLifecycleAction action,
}) =>
    'tenant-lifecycle:$tenantId:${action.name}:$expectedVersion';

/// The minimal control-plane record retained after final deletion.
///
/// It contains no Team Code, Main Admin, subscription, feature configuration,
/// usage, limits, organisation counts, or tenant-operational record.
@immutable
class DeletedTenantTombstone {
  const DeletedTenantTombstone({
    required this.tenantId,
    required this.displayNameSnapshot,
    required this.deletedAt,
    required this.lifecycleVersion,
    required this.historyReference,
  });

  final String tenantId;
  final String displayNameSnapshot;
  final DateTime deletedAt;
  final int lifecycleVersion;

  /// Opaque reference to separately retained platform evidence. It is not the
  /// evidence itself and carries no actor, IP address, or operational data.
  final String historyReference;

  Map<String, dynamic> toJson() => {
        'tenantId': tenantId,
        'displayNameSnapshot': displayNameSnapshot,
        'status': SaasTenantStatus.deleted.wire,
        'deletedAt': deletedAt.toUtc().toIso8601String(),
        'lifecycleVersion': lifecycleVersion,
        'historyReference': historyReference,
      };
}

@immutable
class TenantLifecycleMutationResult {
  const TenantLifecycleMutationResult({
    required this.tenantId,
    required this.displayNameSnapshot,
    required this.lifecycle,
    required this.changed,
    this.tombstone,
    this.idempotentReplay = false,
  });

  final String tenantId;
  final String displayNameSnapshot;
  final SaasTenantLifecycle lifecycle;
  final bool changed;
  final DeletedTenantTombstone? tombstone;
  final bool idempotentReplay;

  TenantLifecycleMutationResult asIdempotentReplay() =>
      TenantLifecycleMutationResult(
        tenantId: tenantId,
        displayNameSnapshot: displayNameSnapshot,
        lifecycle: lifecycle,
        changed: false,
        tombstone: tombstone,
        idempotentReplay: true,
      );
}

DateTime _date(Object? raw) {
  if (raw is! String) throw const FormatException('timestamp must be a string');
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) throw FormatException('invalid timestamp', raw);
  return parsed.toUtc();
}

DateTime? _optionalDate(Object? raw) => raw == null ? null : _date(raw);
