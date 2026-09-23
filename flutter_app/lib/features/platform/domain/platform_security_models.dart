import 'package:flutter/foundation.dart';

enum PlatformSecurityAlertSeverity {
  info('info'),
  warning('warning'),
  critical('critical'),
  unknown('unknown');

  const PlatformSecurityAlertSeverity(this.wire);
  final String wire;

  /// Unsupported future values remain explicit and never become low-risk.
  static PlatformSecurityAlertSeverity parse(String wire) => values.firstWhere(
        (value) => value.wire == wire,
        orElse: () => PlatformSecurityAlertSeverity.unknown,
      );
}

/// Point 10 currently has evidence only for authentication-related alerts.
/// Additional categories require an explicit backend/product contract.
enum PlatformSecurityAlertCategory {
  authentication('authentication'),
  unknown('unknown');

  const PlatformSecurityAlertCategory(this.wire);
  final String wire;

  static PlatformSecurityAlertCategory parse(String wire) => values.firstWhere(
        (value) => value.wire == wire,
        orElse: () => PlatformSecurityAlertCategory.unknown,
      );
}

/// A privacy-limited platform reference, never a tenant operational record.
@immutable
class PlatformSecurityTenantReference {
  PlatformSecurityTenantReference({
    required this.id,
    required this.displayName,
    required this.isDeleted,
    DateTime? deletedAt,
  })  : assert(isDeleted || deletedAt == null),
        deletedAt = deletedAt?.toUtc();

  final String id;
  final String displayName;
  final bool isDeleted;
  final DateTime? deletedAt;

  factory PlatformSecurityTenantReference.fromJson(
    Map<String, dynamic> json,
  ) =>
      PlatformSecurityTenantReference(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
        isDeleted: json['isDeleted'] as bool,
        deletedAt: json['deletedAt'] == null ? null : _date(json['deletedAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'isDeleted': isDeleted,
        if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
      };
}

/// A current read-only security awareness item.
///
/// This is deliberately not a Point 11 actor-attributed audit event and has
/// no acknowledgement, resolution, assignment, evidence, or mutation state.
@immutable
class PlatformSecurityAlert {
  PlatformSecurityAlert({
    required this.id,
    required this.severity,
    required this.category,
    required this.title,
    required this.description,
    required DateTime detectedAt,
    this.affectedTenant,
  }) : detectedAt = detectedAt.toUtc();

  final String id;
  final PlatformSecurityAlertSeverity severity;
  final PlatformSecurityAlertCategory category;
  final String title;
  final String description;
  final DateTime detectedAt;
  final PlatformSecurityTenantReference? affectedTenant;

  factory PlatformSecurityAlert.fromJson(Map<String, dynamic> json) =>
      PlatformSecurityAlert(
        id: json['id'] as String,
        severity:
            PlatformSecurityAlertSeverity.parse(json['severity'] as String),
        category:
            PlatformSecurityAlertCategory.parse(json['category'] as String),
        title: json['title'] as String,
        description: json['description'] as String,
        detectedAt: _date(json['detectedAt']),
        affectedTenant: json['affectedTenant'] == null
            ? null
            : PlatformSecurityTenantReference.fromJson(
                json['affectedTenant'] as Map<String, dynamic>,
              ),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'severity': severity.wire,
        'category': category.wire,
        'title': title,
        'description': description,
        'detectedAt': detectedAt.toIso8601String(),
        if (affectedTenant != null) 'affectedTenant': affectedTenant!.toJson(),
      };
}

enum PlatformSecuritySummaryState {
  noAlerts,
  informational,
  warning,
  critical,
  unknown,
}

@immutable
class PlatformSecuritySnapshot {
  PlatformSecuritySnapshot({
    required DateTime generatedAt,
    required List<PlatformSecurityAlert> alerts,
  })  : generatedAt = generatedAt.toUtc(),
        alerts = List.unmodifiable(alerts);

  final DateTime generatedAt;
  final List<PlatformSecurityAlert> alerts;

  PlatformSecuritySummaryState get summaryState =>
      derivePlatformSecuritySummary(alerts);

  factory PlatformSecuritySnapshot.fromJson(Map<String, dynamic> json) =>
      PlatformSecuritySnapshot(
        generatedAt: _date(json['generatedAt']),
        alerts: (json['alerts'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(PlatformSecurityAlert.fromJson)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'generatedAt': generatedAt.toIso8601String(),
        'alerts': alerts.map((alert) => alert.toJson()).toList(),
      };
}

/// Conservative aggregate for Point 10 and the Point 5 overview projection.
PlatformSecuritySummaryState derivePlatformSecuritySummary(
  Iterable<PlatformSecurityAlert> alerts,
) {
  if (alerts.isEmpty) return PlatformSecuritySummaryState.noAlerts;
  if (alerts.any(
    (alert) => alert.severity == PlatformSecurityAlertSeverity.critical,
  )) {
    return PlatformSecuritySummaryState.critical;
  }
  if (alerts.any(
    (alert) => alert.severity == PlatformSecurityAlertSeverity.unknown,
  )) {
    return PlatformSecuritySummaryState.unknown;
  }
  if (alerts.any(
    (alert) => alert.severity == PlatformSecurityAlertSeverity.warning,
  )) {
    return PlatformSecuritySummaryState.warning;
  }
  return PlatformSecuritySummaryState.informational;
}

DateTime _date(Object? raw) {
  if (raw is! String) throw const FormatException('timestamp must be a string');
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) throw FormatException('invalid timestamp', raw);
  return parsed.toUtc();
}
