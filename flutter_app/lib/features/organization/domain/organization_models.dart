/// The tenant-facing read of the signed-in session's **own** organisation —
/// Point 15's Organization and Plan screens.
///
/// A projection, not a second record. The canonical subscriber is the
/// platform's `SaasTenant` (Points 6–9) and its `SaasSubscription` (Point 7);
/// this is the narrow, read-only slice a Main Admin or Simple Admin may see of
/// it. It deliberately has nowhere to put what the tenant side must never
/// receive: no Team Code, no Main Admin login email or account state, no
/// suspension or deletion reason, no version token, no history, no price.
///
/// **It fails safe rather than refusing.** The platform models throw on an
/// unknown wire value, because a Super Admin acting on a misread record is
/// dangerous. A tenant administrator is only *reading*, and a newer backend
/// value must not blank the whole screen — so an unrecognised lifecycle,
/// subscription status, plan or limit key parses to an explicit
/// *unsupported* value that the screens render as such. It never becomes
/// `active`, never becomes Basic, never becomes unlimited.
///
/// Feature availability is **not** part of this read. The one tenant-side
/// answer to "does this organisation have this module" is
/// `currentTenantFeatureAccessProvider`, which navigation already obeys; a
/// second copy here could only disagree with it.
library;

import 'package:flutter/foundation.dart';

import '../../../core/access/saas_tenant_status.dart';
import '../../platform/domain/saas_subscription_models.dart';

export '../../../core/access/saas_tenant_status.dart';
export '../../platform/domain/saas_subscription_models.dart'
    show PlanLimitKey, SubscriptionStatus;

/// The closed plan catalogue: exactly Basic, Standard and Advanced.
///
/// Keyed by the platform plan id, so a plan this build does not know stays
/// unknown ([OrganizationPlanUnsupported]) instead of being read as the
/// nearest tier.
enum PlanTier {
  basic('mtm_core'),
  standard('mtm_standard'),
  advanced('mtm_advanced');

  const PlanTier(this.planId);

  /// The platform plan id. Never rendered.
  final String planId;

  static PlanTier? fromPlanId(String? planId) {
    for (final tier in values) {
      if (tier.planId == planId) return tier;
    }
    return null;
  }
}

/// Which plan the organisation is on — three honest answers, no null.
sealed class OrganizationPlan {
  const OrganizationPlan();

  /// `null` on the wire is an explicit "no plan assigned" (Point 7's
  /// `NoSaasPlan`); a string this build does not know is unsupported.
  static OrganizationPlan fromWire(Object? raw) {
    if (raw == null) return const OrganizationPlanNone();
    final tier = raw is String ? PlanTier.fromPlanId(raw) : null;
    if (tier != null) return OrganizationPlanKnown(tier);
    return OrganizationPlanUnsupported(raw is String ? raw : null);
  }

  String? get wire;
}

final class OrganizationPlanNone extends OrganizationPlan {
  const OrganizationPlanNone();

  @override
  String? get wire => null;
}

final class OrganizationPlanKnown extends OrganizationPlan {
  const OrganizationPlanKnown(this.tier);
  final PlanTier tier;

  @override
  String get wire => tier.planId;

  @override
  bool operator ==(Object other) =>
      other is OrganizationPlanKnown && other.tier == tier;

  @override
  int get hashCode => tier.hashCode;
}

/// A plan id this build does not recognise. Shown as unknown, never guessed.
final class OrganizationPlanUnsupported extends OrganizationPlan {
  const OrganizationPlanUnsupported([this.rawId]);

  /// Kept only so a re-serialised snapshot stays unsupported. Never rendered.
  final String? rawId;

  @override
  String? get wire => rawId;
}

/// The commercial state, kept apart from tenant access by construction.
@immutable
class OrganizationSubscription {
  const OrganizationSubscription({
    required this.status,
    required this.plan,
    this.trialEndsAt,
    this.renewsAt,
    this.graceEndsAt,
  });

  /// `null` when the wire value is one this build does not know.
  final SubscriptionStatus? status;
  final OrganizationPlan plan;
  final DateTime? trialEndsAt;
  final DateTime? renewsAt;
  final DateTime? graceEndsAt;

  /// The one date that matters for [status], exactly as Point 7 defines it.
  DateTime? get relevantDate => switch (status) {
        SubscriptionStatus.trial => trialEndsAt,
        SubscriptionStatus.active => renewsAt,
        SubscriptionStatus.grace => graceEndsAt,
        SubscriptionStatus.inactive || null => null,
      };
}

/// Where usage stands against the effective limit. Factual only: there is no
/// "near limit" band, because no threshold has been approved (the same rule
/// as the Point 13 usage report).
enum LimitStanding {
  within,

  /// Usage equals the limit — nothing more of this kind can be added.
  atLimit,

  /// Usage exceeds the limit (after a lower override). Nothing was deleted.
  overLimit,

  /// The limit is known, the usage figure is not part of this read.
  limitOnly,

  /// No effective limit was reported for this key.
  unavailable,
}

/// One typed plan limit as the organisation sees it.
@immutable
class OrganizationLimit {
  OrganizationLimit({
    required this.key,
    required this.effective,
    this.planDefault,
    this.overridden = false,
    this.usage,
  }) {
    for (final value in [effective, planDefault, usage]) {
      if (value != null && value < 0) {
        throw ArgumentError.value(value, key.wire);
      }
    }
  }

  final PlanLimitKey key;

  /// `override ?? plan default`, **computed by the backend** (the mock uses
  /// `SaasSubscription.effectiveLimit`, the one implementation of that rule).
  /// Null when no limit was reported. There is no unlimited sentinel: Point 7
  /// ruled that none is needed and that zero is a real limit.
  final int? effective;

  final int? planDefault;

  /// Whether a platform override is in effect for this key.
  final bool overridden;

  /// The organisation-wide figure, or null when this session is not shown it.
  final int? usage;

  LimitStanding get standing {
    final limit = effective;
    if (limit == null) return LimitStanding.unavailable;
    final used = usage;
    if (used == null) return LimitStanding.limitOnly;
    if (used > limit) return LimitStanding.overLimit;
    if (used == limit) return LimitStanding.atLimit;
    return LimitStanding.within;
  }

  /// 0–1 for a progress track; null when there is nothing to draw. Zero-safe
  /// in the same way as `TenantPlanUsage.ratio`.
  double? get ratio {
    final limit = effective;
    final used = usage;
    if (limit == null || used == null) return null;
    if (limit == 0) return used == 0 ? 0 : 1;
    return (used / limit).clamp(0, 1).toDouble();
  }

  factory OrganizationLimit.fromJson(
    PlanLimitKey key,
    Map<String, dynamic> json,
  ) {
    int? count(String field) {
      final raw = json[field];
      return raw is num && raw >= 0 ? raw.toInt() : null;
    }

    final effective = count('effective');
    return OrganizationLimit(
      key: key,
      effective: effective,
      planDefault: count('planDefault'),
      overridden: effective != null && json['overridden'] == true,
      usage: count('usage'),
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key.wire,
        if (effective != null) 'effective': effective,
        if (planDefault != null) 'planDefault': planDefault,
        'overridden': overridden,
        if (usage != null) 'usage': usage,
      };
}

/// Every known limit key, in catalogue order, plus a count of what was not
/// understood.
@immutable
class OrganizationLimits {
  OrganizationLimits({
    required List<OrganizationLimit> items,
    required this.usageIncluded,
    this.unsupportedCount = 0,
  }) : items = List.unmodifiable(items);

  final List<OrganizationLimit> items;

  /// Whether organisation-wide usage figures are part of this read. They are
  /// withheld from a session without `org.edit` — the capability that already
  /// gates organisation-wide figures (`CAPABILITIES.md`).
  final bool usageIncluded;

  /// Limit keys on the wire that this build does not know. Never rendered as
  /// rows; counted so the screen can say something is missing.
  final int unsupportedCount;

  factory OrganizationLimits.fromJson(Map<String, dynamic> json) {
    final raw = json['items'] as List<dynamic>? ?? const [];
    final byKey = <PlanLimitKey, OrganizationLimit>{};
    var unsupported = 0;
    for (final entry in raw.whereType<Map<String, dynamic>>()) {
      final key = PlanLimitKey.parse(entry['key'] as String?);
      if (key == null) {
        unsupported++;
        continue;
      }
      byKey[key] = OrganizationLimit.fromJson(key, entry);
    }
    return OrganizationLimits(
      // A known key the server left out is shown as unavailable, never as a
      // default or an unlimited value.
      items: [
        for (final key in PlanLimitKey.values)
          byKey[key] ?? OrganizationLimit(key: key, effective: null),
      ],
      usageIncluded: json['usageIncluded'] == true,
      unsupportedCount: unsupported,
    );
  }

  Map<String, dynamic> toJson() => {
        'usageIncluded': usageIncluded,
        'items': [for (final item in items) item.toJson()],
      };
}

/// The whole tenant-facing read.
@immutable
class OrganizationSnapshot {
  const OrganizationSnapshot({
    required this.tenantId,
    required this.displayName,
    required this.lifecycle,
    required this.subscription,
    required this.limits,
    required this.readAt,
    this.createdAt,
    this.mainAdminName,
  });

  /// The opaque tenant id. Shown as a support reference; it identifies and
  /// authorizes nothing.
  final String tenantId;

  /// The organisation's own name for itself (`SaasTenant.displayName`) — not
  /// `AuthUser.orgName`, which is a free-typed display string.
  final String displayName;

  /// `null` when the wire value is one this build does not know.
  final SaasTenantStatus? lifecycle;

  final DateTime? createdAt;

  /// The current Main Admin's display name only. No login email, no account
  /// state, no setup or replacement detail — those are Platform-only (Point
  /// 14) and a tenant contract that permits them does not exist.
  final String? mainAdminName;

  final OrganizationSubscription subscription;
  final OrganizationLimits limits;

  /// When the backend produced this read. Shown on a cached copy.
  final DateTime readAt;

  factory OrganizationSnapshot.fromJson(Map<String, dynamic> json) {
    final org = json['organization'] as Map<String, dynamic>;
    final sub = json['subscription'] as Map<String, dynamic>? ?? const {};
    final admin = json['mainAdmin'];
    return OrganizationSnapshot(
      tenantId: org['tenantId'] as String,
      displayName: org['displayName'] as String,
      lifecycle: SaasTenantStatus.parse(org['lifecycleStatus'] as String?),
      createdAt: _date(org['createdAt']),
      mainAdminName: admin is Map<String, dynamic>
          ? admin['displayName'] as String?
          : null,
      subscription: OrganizationSubscription(
        status: SubscriptionStatus.parse(sub['status'] as String?),
        plan: OrganizationPlan.fromWire(sub['planId']),
        trialEndsAt: _date(sub['trialEndsAt']),
        renewsAt: _date(sub['renewsAt']),
        graceEndsAt: _date(sub['graceEndsAt']),
      ),
      limits: OrganizationLimits.fromJson(
        json['limits'] as Map<String, dynamic>? ?? const {},
      ),
      readAt: _date(json['readAt']) ??
          (throw const FormatException('readAt is required')),
    );
  }

  Map<String, dynamic> toJson() => {
        'organization': {
          'tenantId': tenantId,
          'displayName': displayName,
          if (lifecycle != null) 'lifecycleStatus': lifecycle!.wire,
          if (createdAt != null) 'createdAt': _iso(createdAt!),
        },
        if (mainAdminName != null) 'mainAdmin': {'displayName': mainAdminName},
        'subscription': {
          if (subscription.status != null) 'status': subscription.status!.wire,
          'planId': subscription.plan.wire,
          if (subscription.trialEndsAt != null)
            'trialEndsAt': _iso(subscription.trialEndsAt!),
          if (subscription.renewsAt != null)
            'renewsAt': _iso(subscription.renewsAt!),
          if (subscription.graceEndsAt != null)
            'graceEndsAt': _iso(subscription.graceEndsAt!),
        },
        'limits': limits.toJson(),
        'readAt': _iso(readAt),
      };
}

String _iso(DateTime value) => value.toUtc().toIso8601String();

/// A malformed optional date is dropped, not guessed.
DateTime? _date(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
