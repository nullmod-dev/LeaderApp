library;

import 'package:flutter/foundation.dart';

enum PlatformAuditActorKind {
  platformAdministrator('platform_administrator'),
  system('system'),
  unknown('unknown');

  const PlatformAuditActorKind(this.wire);
  final String wire;

  static PlatformAuditActorKind parse(Object? wire) => values.firstWhere(
        (value) => value.wire == wire,
        orElse: () => PlatformAuditActorKind.unknown,
      );
}

@immutable
sealed class PlatformAuditActor {
  const PlatformAuditActor();

  PlatformAuditActorKind get kind;

  factory PlatformAuditActor.fromJson(Map<String, dynamic> json) {
    switch (PlatformAuditActorKind.parse(json['kind'])) {
      case PlatformAuditActorKind.platformAdministrator:
        return PlatformAuditAdministratorActor(
          id: json['id'] as String,
          displayName: json['displayName'] as String,
        );
      case PlatformAuditActorKind.system:
        return const PlatformAuditSystemActor();
      case PlatformAuditActorKind.unknown:
        return const PlatformAuditUnknownActor();
    }
  }

  Map<String, dynamic> toJson();
}

/// A deliberately narrow administrator snapshot: no email or session data.
@immutable
final class PlatformAuditAdministratorActor extends PlatformAuditActor {
  const PlatformAuditAdministratorActor({
    required this.id,
    required this.displayName,
  })  : assert(id != ''),
        assert(displayName != '');

  final String id;
  final String displayName;

  @override
  PlatformAuditActorKind get kind =>
      PlatformAuditActorKind.platformAdministrator;

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind.wire,
        'id': id,
        'displayName': displayName,
      };
}

/// A system actor carries no credential, process identity, or session data.
@immutable
final class PlatformAuditSystemActor extends PlatformAuditActor {
  const PlatformAuditSystemActor();

  @override
  PlatformAuditActorKind get kind => PlatformAuditActorKind.system;

  @override
  Map<String, dynamic> toJson() => {'kind': kind.wire};
}

/// Safe fallback for an actor kind introduced by a newer backend.
@immutable
final class PlatformAuditUnknownActor extends PlatformAuditActor {
  const PlatformAuditUnknownActor();

  @override
  PlatformAuditActorKind get kind => PlatformAuditActorKind.unknown;

  @override
  Map<String, dynamic> toJson() => {'kind': kind.wire};
}

enum PlatformAuditAction {
  tenantRegistered('tenant_registered'),
  subscriptionActivated('subscription_activated'),
  trialExtended('trial_extended'),
  trialEnded('trial_ended'),
  subscriptionMovedToGrace('subscription_moved_to_grace'),
  planChanged('plan_changed'),
  limitOverrideChanged('limit_override_changed'),
  featureFlagChanged('feature_flag_changed'),
  tenantSuspended('tenant_suspended'),
  tenantReactivated('tenant_reactivated'),
  deletionRequested('deletion_requested'),
  deletionCancelled('deletion_cancelled'),
  deletionFinalized('deletion_finalized'),
  breakGlassActivated('break_glass_activated'),
  breakGlassEnded('break_glass_ended'),
  breakGlassExpired('break_glass_expired'),
  breakGlassRevoked('break_glass_revoked'),
  mainAdminSetupResent('main_admin_setup_resent'),
  mainAdminSuspended('main_admin_suspended'),
  mainAdminReactivated('main_admin_reactivated'),
  mainAdminReplacementStarted('main_admin_replacement_started'),
  mainAdminReplacementCancelled('main_admin_replacement_cancelled'),
  mainAdminReplaced('main_admin_replaced'),
  // Customer Demo. Backend-authored in production: the client never writes an
  // audit event, and none of these carries anything from inside a demo
  // workspace or any session credential — an id, an actor and a timestamp.
  customerDemoPolicyChanged('customer_demo_policy_changed'),
  customerDemoSessionStarted('customer_demo_session_started'),
  customerDemoSessionTerminated('customer_demo_session_terminated'),
  // System-actored: time ends a trial, nobody does. It is recorded all the
  // same, because "why did this user lose access" has to be answerable.
  customerDemoSessionExpired('customer_demo_session_expired'),
  unknown('unknown');

  const PlatformAuditAction(this.wire);
  final String wire;

  static PlatformAuditAction parse(Object? wire) => values.firstWhere(
        (value) => value.wire == wire,
        orElse: () => PlatformAuditAction.unknown,
      );
}

enum PlatformAuditCategory {
  tenantManagement('tenant_management'),
  subscription('subscription'),
  entitlement('entitlement'),
  lifecycle('lifecycle'),
  emergencyAccess('emergency_access'),
  accountManagement('account_management'),
  customerDemo('customer_demo'),
  unknown('unknown');

  const PlatformAuditCategory(this.wire);
  final String wire;

  static PlatformAuditCategory parse(Object? wire) => values.firstWhere(
        (value) => value.wire == wire,
        orElse: () => PlatformAuditCategory.unknown,
      );
}

extension PlatformAuditActionCategory on PlatformAuditAction {
  PlatformAuditCategory get category => switch (this) {
        PlatformAuditAction.tenantRegistered =>
          PlatformAuditCategory.tenantManagement,
        PlatformAuditAction.subscriptionActivated ||
        PlatformAuditAction.trialExtended ||
        PlatformAuditAction.trialEnded ||
        PlatformAuditAction.subscriptionMovedToGrace ||
        PlatformAuditAction.planChanged =>
          PlatformAuditCategory.subscription,
        PlatformAuditAction.limitOverrideChanged ||
        PlatformAuditAction.featureFlagChanged =>
          PlatformAuditCategory.entitlement,
        PlatformAuditAction.tenantSuspended ||
        PlatformAuditAction.tenantReactivated ||
        PlatformAuditAction.deletionRequested ||
        PlatformAuditAction.deletionCancelled ||
        PlatformAuditAction.deletionFinalized =>
          PlatformAuditCategory.lifecycle,
        PlatformAuditAction.breakGlassActivated ||
        PlatformAuditAction.breakGlassEnded ||
        PlatformAuditAction.breakGlassExpired ||
        PlatformAuditAction.breakGlassRevoked =>
          PlatformAuditCategory.emergencyAccess,
        PlatformAuditAction.mainAdminSetupResent ||
        PlatformAuditAction.mainAdminSuspended ||
        PlatformAuditAction.mainAdminReactivated ||
        PlatformAuditAction.mainAdminReplacementStarted ||
        PlatformAuditAction.mainAdminReplacementCancelled ||
        PlatformAuditAction.mainAdminReplaced =>
          PlatformAuditCategory.accountManagement,
        PlatformAuditAction.customerDemoPolicyChanged ||
        PlatformAuditAction.customerDemoSessionStarted ||
        PlatformAuditAction.customerDemoSessionTerminated ||
        PlatformAuditAction.customerDemoSessionExpired =>
          PlatformAuditCategory.customerDemo,
        PlatformAuditAction.unknown => PlatformAuditCategory.unknown,
      };
}

enum PlatformAuditTargetResource {
  tenant('tenant'),
  subscription('subscription'),
  planAssignment('plan_assignment'),
  tenantFeature('tenant_feature'),
  tenantLimit('tenant_limit'),
  tenantLifecycle('tenant_lifecycle'),
  breakGlassGrant('break_glass_grant'),
  mainAdminAccount('main_admin_account'),
  customerDemoPolicy('customer_demo_policy'),
  customerDemoSession('customer_demo_session'),
  unknown('unknown');

  const PlatformAuditTargetResource(this.wire);
  final String wire;

  static PlatformAuditTargetResource parse(Object? wire) => values.firstWhere(
        (value) => value.wire == wire,
        orElse: () => PlatformAuditTargetResource.unknown,
      );
}

@immutable
class PlatformAuditTarget {
  const PlatformAuditTarget({
    required this.type,
    required this.id,
    this.displayName,
  }) : assert(type == PlatformAuditTargetResource.unknown || id != '');

  final PlatformAuditTargetResource type;
  final String id;
  final String? displayName;

  factory PlatformAuditTarget.fromJson(Map<String, dynamic> json) {
    final type = PlatformAuditTargetResource.parse(json['type']);
    if (type == PlatformAuditTargetResource.unknown) {
      return const PlatformAuditTarget(
        type: PlatformAuditTargetResource.unknown,
        id: '',
      );
    }
    return PlatformAuditTarget(
      type: type,
      id: json['id'] is String ? json['id'] as String : '',
      displayName:
          json['displayName'] is String ? json['displayName'] as String : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.wire,
        'id': id,
        if (displayName != null) 'displayName': displayName,
      };
}

@immutable
class PlatformAuditTenantReference {
  const PlatformAuditTenantReference({
    required this.id,
    required this.displayName,
    required this.isDeleted,
  })  : assert(id != ''),
        assert(displayName != '');

  final String id;
  final String displayName;
  final bool isDeleted;

  factory PlatformAuditTenantReference.fromJson(Map<String, dynamic> json) =>
      PlatformAuditTenantReference(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
        isDeleted: json['isDeleted'] as bool,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'isDeleted': isDeleted,
      };
}

enum PlatformAuditChangeField {
  lifecycleStatus('lifecycle_status'),
  subscriptionStatus('subscription_status'),
  planAssignment('plan_assignment'),
  featureEnabled('feature_enabled'),
  limitOverride('limit_override'),
  accountStatus('account_status'),
  loginIdentity('login_identity'),
  demoAvailability('demo_availability'),
  demoDefaultDuration('demo_default_duration'),
  unknown('unknown');

  const PlatformAuditChangeField(this.wire);
  final String wire;

  static PlatformAuditChangeField parse(Object? wire) => values.firstWhere(
        (value) => value.wire == wire,
        orElse: () => PlatformAuditChangeField.unknown,
      );
}

enum PlatformAuditValueKind {
  text('text'),
  boolean('bool'),
  integer('integer'),
  redacted('redacted');

  const PlatformAuditValueKind(this.wire);
  final String wire;
}

@immutable
sealed class PlatformAuditValue {
  const PlatformAuditValue();

  PlatformAuditValueKind get kind;
  Map<String, dynamic> toJson();
}

@immutable
final class PlatformAuditTextValue extends PlatformAuditValue {
  const PlatformAuditTextValue(this.value);
  final String value;

  @override
  PlatformAuditValueKind get kind => PlatformAuditValueKind.text;

  @override
  Map<String, dynamic> toJson() => {'kind': kind.wire, 'value': value};
}

@immutable
final class PlatformAuditBoolValue extends PlatformAuditValue {
  const PlatformAuditBoolValue(this.value);
  final bool value;

  @override
  PlatformAuditValueKind get kind => PlatformAuditValueKind.boolean;

  @override
  Map<String, dynamic> toJson() => {'kind': kind.wire, 'value': value};
}

@immutable
final class PlatformAuditIntegerValue extends PlatformAuditValue {
  const PlatformAuditIntegerValue(this.value);
  final int value;

  @override
  PlatformAuditValueKind get kind => PlatformAuditValueKind.integer;

  @override
  Map<String, dynamic> toJson() => {'kind': kind.wire, 'value': value};
}

@immutable
final class PlatformAuditRedactedValue extends PlatformAuditValue {
  const PlatformAuditRedactedValue();

  @override
  PlatformAuditValueKind get kind => PlatformAuditValueKind.redacted;

  @override
  Map<String, dynamic> toJson() => {'kind': kind.wire};
}

/// The single boundary for deciding what change data may enter this model.
abstract final class PlatformAuditSafetyPolicy {
  static const PlatformAuditRedactedValue redacted =
      PlatformAuditRedactedValue();

  static bool isForbiddenFieldName(Object? rawName) {
    if (rawName is! String) return true;
    final normalized = rawName.toLowerCase().replaceAll(
          RegExp('[^a-z0-9]'),
          '',
        );
    if (normalized.isEmpty) return true;
    return normalized.contains('password') ||
        normalized.contains('temppassword') ||
        normalized.contains('temporarypassword') ||
        normalized.contains('otp') ||
        normalized.contains('token') ||
        normalized.contains('secret') ||
        normalized.contains('authorization') ||
        normalized.contains('session') ||
        normalized.contains('credential') ||
        normalized.contains('cookie') ||
        normalized.contains('bearer') ||
        normalized.contains('teamcode');
  }

  static PlatformAuditValue parseValue(
    PlatformAuditChangeField field,
    Object? raw,
  ) {
    if (raw is! Map) return redacted;
    final json = raw.cast<Object?, Object?>();
    final kind = json['kind'];
    final value = json['value'];

    return switch (field) {
      PlatformAuditChangeField.lifecycleStatus ||
      PlatformAuditChangeField.subscriptionStatus ||
      PlatformAuditChangeField.planAssignment ||
      PlatformAuditChangeField.accountStatus =>
        kind == PlatformAuditValueKind.text.wire && value is String
            ? PlatformAuditTextValue(value)
            : redacted,
      PlatformAuditChangeField.featureEnabled =>
        kind == PlatformAuditValueKind.boolean.wire && value is bool
            ? PlatformAuditBoolValue(value)
            : redacted,
      PlatformAuditChangeField.limitOverride =>
        kind == PlatformAuditValueKind.integer.wire && value is int
            ? PlatformAuditIntegerValue(value)
            : redacted,
      // Demo availability is the same shape as a feature flag, and the demo
      // window is an integer count of minutes — never a formatted duration
      // string, so an audit reader is not parsing «يوم واحد» back into a
      // number to tell two revisions apart.
      PlatformAuditChangeField.demoAvailability =>
        kind == PlatformAuditValueKind.boolean.wire && value is bool
            ? PlatformAuditBoolValue(value)
            : redacted,
      PlatformAuditChangeField.demoDefaultDuration =>
        kind == PlatformAuditValueKind.integer.wire && value is int
            ? PlatformAuditIntegerValue(value)
            : redacted,
      PlatformAuditChangeField.loginIdentity => redacted,
      PlatformAuditChangeField.unknown => redacted,
    };
  }

  /// Applies the same fail-safe rules to values created inside Flutter.
  ///
  /// This prevents a caller from pairing, for example, a text value with the
  /// boolean feature field and bypassing the wire parser's redaction.
  static PlatformAuditValue? sanitizeValue(
    PlatformAuditChangeField field,
    PlatformAuditValue? value,
  ) {
    if (value == null || value is PlatformAuditRedactedValue) return value;
    final valid = switch (field) {
      PlatformAuditChangeField.lifecycleStatus ||
      PlatformAuditChangeField.subscriptionStatus ||
      PlatformAuditChangeField.planAssignment ||
      PlatformAuditChangeField.accountStatus =>
        value is PlatformAuditTextValue,
      PlatformAuditChangeField.featureEnabled =>
        value is PlatformAuditBoolValue,
      PlatformAuditChangeField.limitOverride =>
        value is PlatformAuditIntegerValue,
      PlatformAuditChangeField.demoAvailability =>
        value is PlatformAuditBoolValue,
      PlatformAuditChangeField.demoDefaultDuration =>
        value is PlatformAuditIntegerValue,
      PlatformAuditChangeField.loginIdentity => false,
      PlatformAuditChangeField.unknown => false,
    };
    return valid ? value : redacted;
  }
}

@immutable
class PlatformAuditChange {
  const PlatformAuditChange({
    required this.field,
    PlatformAuditValue? before,
    PlatformAuditValue? after,
  })  : _before = before,
        _after = after;

  final PlatformAuditChangeField field;
  final PlatformAuditValue? _before;
  final PlatformAuditValue? _after;

  /// Always policy-sanitized, including for directly constructed mock data.
  PlatformAuditValue? get before =>
      PlatformAuditSafetyPolicy.sanitizeValue(field, _before);

  /// Always policy-sanitized, including for directly constructed mock data.
  PlatformAuditValue? get after =>
      PlatformAuditSafetyPolicy.sanitizeValue(field, _after);

  factory PlatformAuditChange.fromJson(Map<String, dynamic> json) {
    final rawField = json['field'];
    final forbidden = PlatformAuditSafetyPolicy.isForbiddenFieldName(rawField);
    final parsedField = forbidden
        ? PlatformAuditChangeField.unknown
        : PlatformAuditChangeField.parse(rawField);
    final redactAll =
        forbidden || parsedField == PlatformAuditChangeField.unknown;

    PlatformAuditValue? valueFor(String key) {
      if (!json.containsKey(key)) return null;
      if (redactAll) return PlatformAuditSafetyPolicy.redacted;
      return PlatformAuditSafetyPolicy.parseValue(parsedField, json[key]);
    }

    return PlatformAuditChange(
      field: parsedField,
      before: valueFor('before'),
      after: valueFor('after'),
    );
  }

  Map<String, dynamic> toJson() => {
        'field': field.wire,
        if (before != null) 'before': before!.toJson(),
        if (after != null) 'after': after!.toJson(),
      };
}

@immutable
class PlatformAuditEvent {
  PlatformAuditEvent({
    required this.id,
    required DateTime occurredAt,
    required this.actor,
    required this.action,
    required this.target,
    this.tenant,
    required List<PlatformAuditChange> changes,
  })  : assert(id != ''),
        occurredAt = occurredAt.toUtc(),
        changes = List.unmodifiable(changes);

  final String id;
  final DateTime occurredAt;
  final PlatformAuditActor actor;
  final PlatformAuditAction action;
  PlatformAuditCategory get category => action.category;
  final PlatformAuditTarget target;
  final PlatformAuditTenantReference? tenant;
  final List<PlatformAuditChange> changes;

  factory PlatformAuditEvent.fromJson(Map<String, dynamic> json) =>
      PlatformAuditEvent(
        id: json['id'] as String,
        occurredAt: _date(json['occurredAt']),
        actor: json['actor'] is Map<String, dynamic>
            ? PlatformAuditActor.fromJson(
                json['actor'] as Map<String, dynamic>,
              )
            : const PlatformAuditUnknownActor(),
        action: PlatformAuditAction.parse(json['action']),
        target: json['target'] is Map<String, dynamic>
            ? PlatformAuditTarget.fromJson(
                json['target'] as Map<String, dynamic>,
              )
            : const PlatformAuditTarget(
                type: PlatformAuditTargetResource.unknown,
                id: '',
              ),
        tenant: json['tenant'] is Map<String, dynamic>
            ? PlatformAuditTenantReference.fromJson(
                json['tenant'] as Map<String, dynamic>,
              )
            : null,
        changes: json['changes'] is List
            ? (json['changes'] as List<dynamic>)
                .whereType<Map<String, dynamic>>()
                .map(PlatformAuditChange.fromJson)
                .toList()
            : const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'occurredAt': occurredAt.toIso8601String(),
        'actor': actor.toJson(),
        'action': action.wire,
        'category': category.wire,
        'target': target.toJson(),
        if (tenant != null) 'tenant': tenant!.toJson(),
        'changes': [for (final change in changes) change.toJson()],
      };
}

@immutable
class PlatformAuditQuery {
  PlatformAuditQuery({
    DateTime? from,
    DateTime? before,
    this.actorKind,
    this.actorId,
    this.action,
    this.category,
    this.tenantId,
    this.targetType,
    this.search = '',
    this.cursor,
    this.limit = 50,
  })  : assert(limit >= 1 && limit <= 100),
        assert(
          from == null ||
              before == null ||
              from.toUtc().isBefore(before.toUtc()),
        ),
        from = from?.toUtc(),
        before = before?.toUtc() {
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 100');
    }
    if (this.from != null &&
        this.before != null &&
        !this.from!.isBefore(this.before!)) {
      throw ArgumentError('from must be earlier than before');
    }
  }

  /// Inclusive lower bound, normalized to UTC.
  final DateTime? from;

  /// Exclusive upper bound, normalized to UTC.
  final DateTime? before;
  final PlatformAuditActorKind? actorKind;
  final String? actorId;
  final PlatformAuditAction? action;
  final PlatformAuditCategory? category;
  final String? tenantId;
  final PlatformAuditTargetResource? targetType;

  /// Searches only event id, actor display name, target id/display name, and
  /// tenant id/display name. Change fields and values are never searchable.
  final String search;
  final String? cursor;
  final int limit;

  PlatformAuditQuery get firstPage => PlatformAuditQuery(
        from: from,
        before: before,
        actorKind: actorKind,
        actorId: actorId,
        action: action,
        category: category,
        tenantId: tenantId,
        targetType: targetType,
        search: search,
        limit: limit,
      );

  @override
  bool operator ==(Object other) =>
      other is PlatformAuditQuery &&
      other.from == from &&
      other.before == before &&
      other.actorKind == actorKind &&
      other.actorId == actorId &&
      other.action == action &&
      other.category == category &&
      other.tenantId == tenantId &&
      other.targetType == targetType &&
      other.search == search &&
      other.cursor == cursor &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(
        from,
        before,
        actorKind,
        actorId,
        action,
        category,
        tenantId,
        targetType,
        search,
        cursor,
        limit,
      );
}

@immutable
class PlatformAuditPage {
  PlatformAuditPage({
    required List<PlatformAuditEvent> items,
    this.nextCursor,
  }) : items = List.unmodifiable(items);

  final List<PlatformAuditEvent> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;

  factory PlatformAuditPage.fromJson(Map<String, dynamic> json) =>
      PlatformAuditPage(
        items: (json['items'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(PlatformAuditEvent.fromJson)
            .toList(),
        nextCursor: json['nextCursor'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'items': [for (final item in items) item.toJson()],
        if (nextCursor != null) 'nextCursor': nextCursor,
      };
}

DateTime _date(Object? raw) {
  if (raw is! String) throw const FormatException('timestamp must be a string');
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) throw FormatException('invalid timestamp', raw);
  return parsed.toUtc();
}
