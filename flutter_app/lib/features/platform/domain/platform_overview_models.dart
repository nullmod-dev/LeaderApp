import 'package:flutter/foundation.dart';

import 'platform_health_models.dart';

export 'platform_health_models.dart';

enum AttentionSeverity {
  info('info'),
  warning('warning'),
  critical('critical');

  const AttentionSeverity(this.wire);
  final String wire;

  static AttentionSeverity parse(String wire) =>
      values.firstWhere((value) => value.wire == wire);
}

enum PlatformAttentionCategory {
  subscription('subscription'),
  trial('trial'),
  demo('demo'),
  security('security'),
  health('health'),
  backgroundJob('background_job'),
  tenantLifecycle('tenant_lifecycle');

  const PlatformAttentionCategory(this.wire);
  final String wire;

  static PlatformAttentionCategory parse(String wire) =>
      values.firstWhere((value) => value.wire == wire);
}

/// A real section landing that exists in the Point 4 shell.
///
/// Models carry this typed intent rather than a route string or an Arabic
/// label. Presentation maps it onto the registered route, so a backend value
/// can never manufacture a deep link to a future screen.
enum PlatformOverviewTarget {
  tenants('tenants'),
  operations('operations'),
  health('health'),
  security('security');

  const PlatformOverviewTarget(this.wire);
  final String wire;

  static PlatformOverviewTarget parse(String wire) =>
      values.firstWhere((value) => value.wire == wire);
}

enum CustomerDemoType {
  simple('simple'),
  full('full');

  const CustomerDemoType(this.wire);
  final String wire;

  static CustomerDemoType parse(String wire) =>
      values.firstWhere((value) => value.wire == wire);
}

enum PlatformActivityType {
  tenantCreated('tenant_created'),
  subscriptionChanged('subscription_changed'),
  demoStarted('demo_started'),
  demoExpired('demo_expired'),
  securityAlert('security_alert'),
  platformHealthChanged('platform_health_changed');

  const PlatformActivityType(this.wire);
  final String wire;

  static PlatformActivityType parse(String wire) =>
      values.firstWhere((value) => value.wire == wire);
}

@immutable
class PlatformTenantSummary {
  const PlatformTenantSummary({
    required this.total,
    required this.activeSubscriptions,
    required this.activeTrials,
    required this.gracePeriod,
    required this.suspended,
    required this.deletionPending,
  })  : assert(total >= 0),
        assert(activeSubscriptions >= 0),
        assert(activeTrials >= 0),
        assert(gracePeriod >= 0),
        assert(suspended >= 0),
        assert(deletionPending >= 0),
        assert(activeSubscriptions + activeTrials + gracePeriod <= total),
        assert(suspended + deletionPending <= total);

  final int total;
  final int activeSubscriptions;
  final int activeTrials;
  final int gracePeriod;
  final int suspended;
  final int deletionPending;

  int get requiringAttention => gracePeriod + suspended + deletionPending;

  factory PlatformTenantSummary.fromJson(Map<String, dynamic> json) =>
      PlatformTenantSummary(
        total: json['total'] as int,
        activeSubscriptions: json['activeSubscriptions'] as int,
        activeTrials: json['activeTrials'] as int,
        gracePeriod: json['gracePeriod'] as int,
        suspended: json['suspended'] as int,
        deletionPending: json['deletionPending'] as int,
      );

  Map<String, dynamic> toJson() => {
        'total': total,
        'activeSubscriptions': activeSubscriptions,
        'activeTrials': activeTrials,
        'gracePeriod': gracePeriod,
        'suspended': suspended,
        'deletionPending': deletionPending,
      };
}

@immutable
class PlatformDemoSummary {
  const PlatformDemoSummary({
    required this.active,
    required this.simple,
    required this.full,
    required this.expiringSoon,
  })  : assert(active >= 0),
        assert(simple >= 0),
        assert(full >= 0),
        assert(expiringSoon >= 0),
        assert(active == simple + full),
        assert(expiringSoon <= active);

  final int active;
  final int simple;
  final int full;
  final int expiringSoon;

  factory PlatformDemoSummary.fromJson(Map<String, dynamic> json) =>
      PlatformDemoSummary(
        active: json['active'] as int,
        simple: json['simple'] as int,
        full: json['full'] as int,
        expiringSoon: json['expiringSoon'] as int,
      );

  Map<String, dynamic> toJson() => {
        'active': active,
        'simple': simple,
        'full': full,
        'expiringSoon': expiringSoon,
      };
}

@immutable
class PlatformAttentionItem {
  const PlatformAttentionItem({
    required this.id,
    required this.severity,
    required this.category,
    required this.title,
    required this.description,
    required this.occurredAt,
    this.target,
    this.tenantId,
    this.scheduledFor,
  }) : assert(tenantId == null || target == PlatformOverviewTarget.tenants);

  final String id;
  final AttentionSeverity severity;
  final PlatformAttentionCategory category;
  final String title;
  final String description;
  final DateTime occurredAt;
  final PlatformOverviewTarget? target;

  /// Present only when the typed target is one concrete tenant detail. The
  /// presentation still builds the route; backend data never supplies one.
  final String? tenantId;

  /// Optional lifecycle deadline used for stable day-level context.
  final DateTime? scheduledFor;

  factory PlatformAttentionItem.fromJson(Map<String, dynamic> json) =>
      PlatformAttentionItem(
        id: json['id'] as String,
        severity: AttentionSeverity.parse(json['severity'] as String),
        category: PlatformAttentionCategory.parse(json['category'] as String),
        title: json['title'] as String,
        description: json['description'] as String,
        occurredAt: _date(json['occurredAt']),
        target: json['target'] == null
            ? null
            : PlatformOverviewTarget.parse(json['target'] as String),
        tenantId: json['tenantId'] as String?,
        scheduledFor:
            json['scheduledFor'] == null ? null : _date(json['scheduledFor']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'severity': severity.wire,
        'category': category.wire,
        'title': title,
        'description': description,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        if (target != null) 'target': target!.wire,
        if (tenantId != null) 'tenantId': tenantId,
        if (scheduledFor != null)
          'scheduledFor': scheduledFor!.toUtc().toIso8601String(),
      };
}

@immutable
class PlatformActivityEvent {
  const PlatformActivityEvent({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.occurredAt,
  });

  final String id;
  final PlatformActivityType type;
  final String title;
  final String description;
  final DateTime occurredAt;

  factory PlatformActivityEvent.fromJson(Map<String, dynamic> json) =>
      PlatformActivityEvent(
        id: json['id'] as String,
        type: PlatformActivityType.parse(json['type'] as String),
        title: json['title'] as String,
        description: json['description'] as String,
        occurredAt: _date(json['occurredAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.wire,
        'title': title,
        'description': description,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
      };
}

@immutable
class PlatformUsageSummary {
  const PlatformUsageSummary({
    required this.storageUsedBytes,
    required this.storageAllowanceBytes,
  })  : assert(storageUsedBytes >= 0),
        assert(storageAllowanceBytes > 0),
        assert(storageUsedBytes <= storageAllowanceBytes);

  final int storageUsedBytes;
  final int storageAllowanceBytes;

  double get storageRatio => storageUsedBytes / storageAllowanceBytes;

  factory PlatformUsageSummary.fromJson(Map<String, dynamic> json) =>
      PlatformUsageSummary(
        storageUsedBytes: json['storageUsedBytes'] as int,
        storageAllowanceBytes: json['storageAllowanceBytes'] as int,
      );

  Map<String, dynamic> toJson() => {
        'storageUsedBytes': storageUsedBytes,
        'storageAllowanceBytes': storageAllowanceBytes,
      };
}

/// The single backend-friendly read consumed by `/platform`.
@immutable
class PlatformOverviewSnapshot {
  PlatformOverviewSnapshot({
    required this.generatedAt,
    required this.tenants,
    required this.demos,
    required List<PlatformHealthSignal> health,
    required List<PlatformAttentionItem> attention,
    required List<PlatformActivityEvent> recentActivity,
    this.usage,
  })  : health = List.unmodifiable(health),
        attention = List.unmodifiable(attention),
        recentActivity = List.unmodifiable(recentActivity);

  final DateTime generatedAt;
  final PlatformTenantSummary tenants;
  final PlatformDemoSummary demos;
  final List<PlatformHealthSignal> health;
  final List<PlatformAttentionItem> attention;
  final List<PlatformActivityEvent> recentActivity;
  final PlatformUsageSummary? usage;

  bool get isMinimal =>
      tenants.total == 0 &&
      demos.active == 0 &&
      health.isEmpty &&
      attention.isEmpty &&
      recentActivity.isEmpty &&
      usage == null;

  PlatformHealthStatus get overallHealth => deriveOverallPlatformHealth(health);

  factory PlatformOverviewSnapshot.empty(DateTime generatedAt) =>
      PlatformOverviewSnapshot(
        generatedAt: generatedAt,
        tenants: const PlatformTenantSummary(
          total: 0,
          activeSubscriptions: 0,
          activeTrials: 0,
          gracePeriod: 0,
          suspended: 0,
          deletionPending: 0,
        ),
        demos: const PlatformDemoSummary(
          active: 0,
          simple: 0,
          full: 0,
          expiringSoon: 0,
        ),
        health: const [],
        attention: const [],
        recentActivity: const [],
      );

  factory PlatformOverviewSnapshot.fromJson(Map<String, dynamic> json) =>
      PlatformOverviewSnapshot(
        generatedAt: _date(json['generatedAt']),
        tenants: PlatformTenantSummary.fromJson(
          json['tenants'] as Map<String, dynamic>,
        ),
        demos: PlatformDemoSummary.fromJson(
          json['demos'] as Map<String, dynamic>,
        ),
        health: (json['health'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(PlatformHealthSignal.fromJson)
            .toList(),
        attention: (json['attention'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(PlatformAttentionItem.fromJson)
            .toList(),
        recentActivity: (json['recentActivity'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(PlatformActivityEvent.fromJson)
            .toList(),
        usage: json['usage'] == null
            ? null
            : PlatformUsageSummary.fromJson(
                json['usage'] as Map<String, dynamic>,
              ),
      );

  Map<String, dynamic> toJson() => {
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'tenants': tenants.toJson(),
        'demos': demos.toJson(),
        'health': health.map((item) => item.toJson()).toList(),
        'attention': attention.map((item) => item.toJson()).toList(),
        'recentActivity': recentActivity.map((item) => item.toJson()).toList(),
        if (usage != null) 'usage': usage!.toJson(),
      };
}

DateTime _date(Object? raw) {
  if (raw is! String) throw const FormatException('timestamp must be a string');
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) throw FormatException('invalid timestamp', raw);
  return parsed.toUtc();
}
