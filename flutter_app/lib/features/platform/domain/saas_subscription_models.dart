library;

import 'package:flutter/foundation.dart';

/// The commercial lifecycle. It is deliberately independent from tenant
/// access/lifecycle: an active tenant may be in grace, while a suspended
/// tenant may carry an inactive subscription.
enum SubscriptionStatus {
  trial('trial'),
  active('active'),
  grace('grace'),

  /// Needed for an ended commercial relationship which is neither a tenant
  /// suspension nor a deletion. The Point 9 lifecycle policy remains the
  /// only owner of operational access state.
  inactive('inactive');

  const SubscriptionStatus(this.wire);
  final String wire;

  static SubscriptionStatus? parse(String? wire) {
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return null;
  }
}

/// Stable business identifiers. Arabic labels live in presentation code.
enum PlanLimitKey {
  detachmentGroups('detachment_groups'),
  detachments('detachments'),
  admins('admins'),
  members('members'),
  workshops('workshops'),
  storageBytes('storage_bytes');

  const PlanLimitKey(this.wire);
  final String wire;

  bool get isBytes => this == PlanLimitKey.storageBytes;

  static PlanLimitKey? parse(String? wire) {
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return null;
  }
}

@immutable
class PlanLimits {
  // Runtime validation of every typed key prevents this constructor from
  // being const even though the resulting value is immutable.
  // ignore: prefer_const_constructors_in_immutables
  PlanLimits(Map<PlanLimitKey, int> values)
      : values = Map.unmodifiable(values) {
    for (final key in PlanLimitKey.values) {
      if (!this.values.containsKey(key)) {
        throw ArgumentError('missing plan limit: ${key.wire}');
      }
      if (this.values[key]! < 0) {
        throw ArgumentError.value(this.values[key], key.wire);
      }
    }
  }

  final Map<PlanLimitKey, int> values;

  int operator [](PlanLimitKey key) => values[key]!;

  PlanLimits copyWithValue(PlanLimitKey key, int value) {
    if (value < 0) throw ArgumentError.value(value, key.wire);
    return PlanLimits({...values, key: value});
  }

  factory PlanLimits.fromJson(Map<String, dynamic> json) => PlanLimits({
        for (final key in PlanLimitKey.values)
          key: (json[key.wire] as num).toInt(),
      });

  Map<String, dynamic> toJson() => {
        for (final entry in values.entries) entry.key.wire: entry.value,
      };
}

@immutable
class SaasPlan {
  const SaasPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.defaultLimits,
    this.recommended = false,
    this.selectable = true,
  });

  final String id;
  final String name;
  final String description;
  final PlanLimits defaultLimits;
  final bool recommended;
  final bool selectable;

  factory SaasPlan.fromJson(Map<String, dynamic> json) => SaasPlan(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        defaultLimits:
            PlanLimits.fromJson(json['defaultLimits'] as Map<String, dynamic>),
        recommended: json['recommended'] as bool? ?? false,
        selectable: json['selectable'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'defaultLimits': defaultLimits.toJson(),
        'recommended': recommended,
        'selectable': selectable,
      };
}

sealed class SaasPlanAssignment {
  const SaasPlanAssignment();

  String? get planId;
  bool get hasPlan => planId != null;
}

class NoSaasPlan extends SaasPlanAssignment {
  const NoSaasPlan();

  @override
  String? get planId => null;
}

class AssignedSaasPlan extends SaasPlanAssignment {
  const AssignedSaasPlan(this.id);
  final String id;

  @override
  String get planId => id;
}

@immutable
class SaasSubscription {
  SaasSubscription({
    required this.status,
    required this.plan,
    required this.version,
    this.trialEndsAt,
    this.renewsAt,
    this.graceEndsAt,
    Map<PlanLimitKey, int> limitOverrides = const {},
  }) : limitOverrides = Map.unmodifiable(limitOverrides) {
    if (version < 1) throw ArgumentError.value(version, 'version');
    for (final entry in this.limitOverrides.entries) {
      if (entry.value < 0) {
        throw ArgumentError.value(entry.value, entry.key.wire);
      }
    }
  }

  final SubscriptionStatus status;
  final SaasPlanAssignment plan;

  /// Optimistic-concurrency token. A future backend may replace the integer
  /// with an opaque ETag without changing controller semantics.
  final int version;
  final DateTime? trialEndsAt;
  final DateTime? renewsAt;
  final DateTime? graceEndsAt;
  final Map<PlanLimitKey, int> limitOverrides;

  DateTime? get relevantDate => switch (status) {
        SubscriptionStatus.trial => trialEndsAt,
        SubscriptionStatus.active => renewsAt,
        SubscriptionStatus.grace => graceEndsAt,
        SubscriptionStatus.inactive => null,
      };

  int effectiveLimit(PlanLimitKey key, SaasPlan planDefinition) =>
      limitOverrides[key] ?? planDefinition.defaultLimits[key];

  bool hasOverride(PlanLimitKey key) => limitOverrides.containsKey(key);

  SaasSubscription copyWith({
    SubscriptionStatus? status,
    SaasPlanAssignment? plan,
    int? version,
    DateTime? trialEndsAt,
    bool clearTrialEndsAt = false,
    DateTime? renewsAt,
    bool clearRenewsAt = false,
    DateTime? graceEndsAt,
    bool clearGraceEndsAt = false,
    Map<PlanLimitKey, int>? limitOverrides,
  }) =>
      SaasSubscription(
        status: status ?? this.status,
        plan: plan ?? this.plan,
        version: version ?? this.version,
        trialEndsAt: clearTrialEndsAt ? null : trialEndsAt ?? this.trialEndsAt,
        renewsAt: clearRenewsAt ? null : renewsAt ?? this.renewsAt,
        graceEndsAt: clearGraceEndsAt ? null : graceEndsAt ?? this.graceEndsAt,
        limitOverrides: limitOverrides ?? this.limitOverrides,
      );

  factory SaasSubscription.fromJson(Map<String, dynamic> json) {
    final status = SubscriptionStatus.parse(json['status'] as String?);
    if (status == null) {
      throw FormatException('unknown subscription status', json['status']);
    }
    final rawPlanId = json['planId'];
    final rawOverrides = json['limitOverrides'] as Map<String, dynamic>? ?? {};
    return SaasSubscription(
      status: status,
      plan: rawPlanId == null
          ? const NoSaasPlan()
          : AssignedSaasPlan(rawPlanId as String),
      version: (json['version'] as num).toInt(),
      trialEndsAt: _optionalDate(json['trialEndsAt']),
      renewsAt: _optionalDate(json['renewsAt']),
      graceEndsAt: _optionalDate(json['graceEndsAt']),
      limitOverrides: {
        for (final entry in rawOverrides.entries)
          PlanLimitKey.parse(entry.key) ??
                  (throw FormatException('unknown plan limit', entry.key)):
              (entry.value as num).toInt(),
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status.wire,
        if (plan.planId != null) 'planId': plan.planId,
        'version': version,
        if (trialEndsAt != null)
          'trialEndsAt': trialEndsAt!.toUtc().toIso8601String(),
        if (renewsAt != null) 'renewsAt': renewsAt!.toUtc().toIso8601String(),
        if (graceEndsAt != null)
          'graceEndsAt': graceEndsAt!.toUtc().toIso8601String(),
        'limitOverrides': {
          for (final entry in limitOverrides.entries)
            entry.key.wire: entry.value,
        },
      };
}

@immutable
class TenantPlanUsage {
  TenantPlanUsage(Map<PlanLimitKey, int> values)
      : values = Map.unmodifiable(values) {
    for (final key in PlanLimitKey.values) {
      if (!this.values.containsKey(key)) {
        throw ArgumentError('missing tenant usage: ${key.wire}');
      }
      if (this.values[key]! < 0) {
        throw ArgumentError.value(this.values[key], key.wire);
      }
    }
  }

  final Map<PlanLimitKey, int> values;
  int operator [](PlanLimitKey key) => values[key]!;

  bool isAbove(PlanLimitKey key, int limit) => this[key] > limit;
  double ratio(PlanLimitKey key, int limit) {
    if (limit == 0) return this[key] == 0 ? 0 : 1;
    return (this[key] / limit).clamp(0, 1).toDouble();
  }

  Map<String, dynamic> toJson() => {
        for (final entry in values.entries) entry.key.wire: entry.value,
      };
}

@immutable
class TenantSubscriptionDetails {
  const TenantSubscriptionDetails({
    required this.tenantId,
    required this.tenantName,
    required this.subscription,
    required this.currentPlan,
  });

  final String tenantId;
  final String tenantName;
  final SaasSubscription subscription;
  final SaasPlan? currentPlan;
}

@immutable
class TenantLimitsSnapshot {
  const TenantLimitsSnapshot({
    required this.tenantId,
    required this.tenantName,
    required this.subscription,
    required this.plan,
    required this.usage,
  });

  final String tenantId;
  final String tenantName;
  final SaasSubscription subscription;
  final SaasPlan plan;
  final TenantPlanUsage usage;

  int effectiveLimit(PlanLimitKey key) =>
      subscription.effectiveLimit(key, plan);
  bool isBelowUsage(PlanLimitKey key, int proposed) =>
      usage.isAbove(key, proposed);
}

@immutable
class SubscriptionVersionedCommand {
  const SubscriptionVersionedCommand({
    required this.tenantId,
    required this.expectedVersion,
  });
  final String tenantId;
  final int expectedVersion;
}

class ActivateSubscriptionCommand extends SubscriptionVersionedCommand {
  const ActivateSubscriptionCommand({
    required super.tenantId,
    required super.expectedVersion,
    required this.planId,
  });
  final String planId;
}

class ExtendTrialCommand extends SubscriptionVersionedCommand {
  const ExtendTrialCommand({
    required super.tenantId,
    required super.expectedVersion,
    required this.newEndsAt,
  });
  final DateTime newEndsAt;
}

class ChangePlanCommand extends SubscriptionVersionedCommand {
  const ChangePlanCommand({
    required super.tenantId,
    required super.expectedVersion,
    required this.planId,
  });
  final String planId;
}

class UpdateLimitOverrideCommand extends SubscriptionVersionedCommand {
  const UpdateLimitOverrideCommand({
    required super.tenantId,
    required super.expectedVersion,
    required this.key,
    this.overrideValue,
  });
  final PlanLimitKey key;

  /// Null means reset to the selected plan's default.
  final int? overrideValue;
}

DateTime? _optionalDate(Object? raw) {
  if (raw == null) return null;
  if (raw is! String) throw const FormatException('timestamp must be a string');
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) throw FormatException('invalid timestamp', raw);
  return parsed.toUtc();
}
