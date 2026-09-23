library;

import 'package:flutter/foundation.dart';

/// Stable product-module identifiers. UI labels are never business keys.
enum TenantFeatureKey {
  inventory('inventory'),
  statisticsReports('statistics_reports'),
  workshops('workshops'),
  announcements('announcements');

  const TenantFeatureKey(this.wire);
  final String wire;

  static TenantFeatureKey? parse(String? wire) {
    for (final key in values) {
      if (key.wire == wire) return key;
    }
    return null;
  }
}

enum TenantFeatureWarning { informational, workflow }

@immutable
class TenantFeatureDefinition {
  const TenantFeatureDefinition({
    required this.key,
    required this.arabicLabel,
    required this.description,
    required this.disableConsequence,
    required this.warning,
    required this.confirmDisable,
  });

  final TenantFeatureKey key;
  final String arabicLabel;
  final String description;
  final String disableConsequence;
  final TenantFeatureWarning warning;
  final bool confirmDisable;
}

/// The one canonical catalogue, in the order shown by Platform UI.
const List<TenantFeatureDefinition> tenantFeatureCatalog = [
  TenantFeatureDefinition(
    key: TenantFeatureKey.inventory,
    arabicLabel: 'المخزون',
    description: 'إدارة المواد والكميات والتنبيهات المرتبطة بالمخزون.',
    disableConsequence:
        'تختفي صفحات المخزون ونتائجه وتنبيهاته، مع بقاء السجلات محفوظة.',
    warning: TenantFeatureWarning.workflow,
    confirmDisable: true,
  ),
  TenantFeatureDefinition(
    key: TenantFeatureKey.statisticsReports,
    arabicLabel: 'الإحصاءات والتقارير',
    description: 'عرض الإحصاءات وإنشاء معاينات وتقارير المفرزات والورش.',
    disableConsequence:
        'تختفي الإحصاءات ومسارات التقارير والتصدير، ولا تُحذف السجلات.',
    warning: TenantFeatureWarning.informational,
    confirmDisable: true,
  ),
  TenantFeatureDefinition(
    key: TenantFeatureKey.workshops,
    arabicLabel: 'الورش',
    description: 'إدارة الورش وفرقها ومشاركيها وسير العمل المرتبط بها.',
    disableConsequence:
        'يختفي قسم الورش ومساراته، وتبقى بيانات الورش محفوظة حتى إعادة التفعيل.',
    warning: TenantFeatureWarning.workflow,
    confirmDisable: true,
  ),
  TenantFeatureDefinition(
    key: TenantFeatureKey.announcements,
    arabicLabel: 'الإعلانات',
    description: 'نشر الإعلانات وعرضها داخل الفريق وفي مركز التنبيهات.',
    disableConsequence:
        'تختفي أدوات الإعلانات وسجلها من تطبيق الفريق، وتبقى الإعلانات محفوظة.',
    warning: TenantFeatureWarning.workflow,
    confirmDisable: true,
  ),
];

TenantFeatureDefinition definitionOf(TenantFeatureKey key) =>
    tenantFeatureCatalog.firstWhere((definition) => definition.key == key);

/// Explicit new-tenant product default. It is not inferred from a plan.
const Set<TenantFeatureKey> defaultEnabledTenantFeatures = {
  TenantFeatureKey.inventory,
  TenantFeatureKey.announcements,
};

@immutable
class TenantFeatureState {
  const TenantFeatureState({
    required this.key,
    required this.enabled,
    required this.version,
    required this.updatedAt,
  });

  final TenantFeatureKey key;
  final bool enabled;
  final int version;
  final DateTime updatedAt;

  TenantFeatureState copyWith({
    bool? enabled,
    int? version,
    DateTime? updatedAt,
  }) =>
      TenantFeatureState(
        key: key,
        enabled: enabled ?? this.enabled,
        version: version ?? this.version,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'key': key.wire,
        'enabled': enabled,
        'version': version,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };
}

/// Typed feature state for one SaaS tenant.
///
/// A known key absent from [states] is disabled. Unknown wire keys are kept
/// only for diagnostics and never become a row or an entitlement.
@immutable
class TenantFeatureSet {
  TenantFeatureSet({
    required this.tenantId,
    required this.tenantName,
    required Map<TenantFeatureKey, TenantFeatureState> states,
    Set<String> unknownWireKeys = const {},
  })  : states = Map.unmodifiable(states),
        unknownWireKeys = Set.unmodifiable(unknownWireKeys);

  final String tenantId;
  final String tenantName;
  final Map<TenantFeatureKey, TenantFeatureState> states;
  final Set<String> unknownWireKeys;

  TenantFeatureState? stateOf(TenantFeatureKey key) => states[key];

  /// Fail closed for a known-but-missing key.
  bool isEnabled(TenantFeatureKey key) => states[key]?.enabled == true;

  TenantFeatureSet replace(TenantFeatureState state) => TenantFeatureSet(
        tenantId: tenantId,
        tenantName: tenantName,
        states: {...states, state.key: state},
        unknownWireKeys: unknownWireKeys,
      );

  factory TenantFeatureSet.fromJson(Map<String, dynamic> json) {
    final tenantId = json['tenantId'] as String;
    final tenantName = json['tenantName'] as String? ?? '';
    final states = <TenantFeatureKey, TenantFeatureState>{};
    final unknown = <String>{};
    for (final raw in json['features'] as List? ?? const []) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final rawKey = item['key'];
      if (rawKey is! String) continue;
      final key = TenantFeatureKey.parse(rawKey);
      if (key == null) {
        unknown.add(rawKey);
        continue;
      }
      final rawEnabled = item['enabled'];
      // Unsupported state/type is deliberately disabled, never guessed.
      final enabled = rawEnabled is bool ? rawEnabled : false;
      final rawVersion = item['version'];
      final rawUpdatedAt = item['updatedAt'];
      states[key] = TenantFeatureState(
        key: key,
        enabled: enabled,
        version: rawVersion is int && rawVersion > 0 ? rawVersion : 1,
        updatedAt: rawUpdatedAt is String
            ? DateTime.tryParse(rawUpdatedAt)?.toUtc() ?? DateTime.utc(1970)
            : DateTime.utc(1970),
      );
    }
    return TenantFeatureSet(
      tenantId: tenantId,
      tenantName: tenantName,
      states: states,
      unknownWireKeys: unknown,
    );
  }

  Map<String, dynamic> toJson() => {
        'tenantId': tenantId,
        'tenantName': tenantName,
        'features': [
          for (final definition in tenantFeatureCatalog)
            if (states[definition.key] case final state?) state.toJson(),
        ],
      };
}

@immutable
class SetTenantFeatureCommand {
  const SetTenantFeatureCommand({
    required this.tenantId,
    required this.key,
    required this.enabled,
    required this.expectedVersion,
  });

  final String tenantId;
  final TenantFeatureKey key;
  final bool enabled;
  final int expectedVersion;
}

/// Central route-family mapping. A disabled module cannot be reached merely
/// because a new button or deep link bypassed navigation filtering.
Set<TenantFeatureKey> tenantFeaturesForLocation(String location) {
  final path = Uri.tryParse(location)?.path ?? location;
  if (path == '/announcements' || path.startsWith('/announcements/')) {
    return const {TenantFeatureKey.announcements};
  }
  if (path == '/workshop' || path.startsWith('/workshop/')) {
    if (path.endsWith('/stats')) {
      return const {
        TenantFeatureKey.workshops,
        TenantFeatureKey.statisticsReports,
      };
    }
    return const {TenantFeatureKey.workshops};
  }
  if (path.startsWith('/detachment/')) {
    if (path.contains('/storage')) {
      return const {TenantFeatureKey.inventory};
    }
    if (path.contains('/stats') || path.contains('/report')) {
      return const {TenantFeatureKey.statisticsReports};
    }
  }
  return const {};
}
