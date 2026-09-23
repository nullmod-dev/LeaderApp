import 'package:flutter/foundation.dart';

/// Backend-neutral state of one known platform health signal.
enum PlatformHealthStatus {
  healthy('healthy'),
  degraded('degraded'),
  unavailable('unavailable'),
  unknown('unknown');

  const PlatformHealthStatus(this.wire);
  final String wire;

  /// Unsupported future values remain visible as unknown and never become
  /// healthy by accident.
  static PlatformHealthStatus parse(String wire) => values.firstWhere(
        (value) => value.wire == wire,
        orElse: () => PlatformHealthStatus.unknown,
      );
}

@immutable
class PlatformHealthSignal {
  PlatformHealthSignal({
    required this.id,
    required this.label,
    required this.status,
    required this.summary,
    required DateTime observedAt,
  }) : observedAt = observedAt.toUtc();

  final String id;
  final String label;
  final PlatformHealthStatus status;
  final String summary;

  /// When this individual condition was observed, normalized to UTC.
  final DateTime observedAt;

  factory PlatformHealthSignal.fromJson(Map<String, dynamic> json) =>
      PlatformHealthSignal(
        id: json['id'] as String,
        label: json['label'] as String,
        status: PlatformHealthStatus.parse(json['status'] as String),
        summary: json['summary'] as String,
        observedAt: _date(json['observedAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'status': status.wire,
        'summary': summary,
        'observedAt': observedAt.toIso8601String(),
      };
}

@immutable
class PlatformHealthSnapshot {
  PlatformHealthSnapshot({
    required DateTime generatedAt,
    required List<PlatformHealthSignal> signals,
    required this.isPartial,
  })  : generatedAt = generatedAt.toUtc(),
        signals = List.unmodifiable(signals);

  /// When the backend generated this snapshot, normalized to UTC.
  final DateTime generatedAt;
  final List<PlatformHealthSignal> signals;

  /// True when the snapshot remains usable but one or more expected signals
  /// could not be supplied. This is distinct from platform degradation.
  final bool isPartial;

  PlatformHealthStatus get overallStatus =>
      deriveOverallPlatformHealth(signals);

  factory PlatformHealthSnapshot.fromJson(Map<String, dynamic> json) =>
      PlatformHealthSnapshot(
        generatedAt: _date(json['generatedAt']),
        signals: (json['signals'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(PlatformHealthSignal.fromJson)
            .toList(),
        isPartial: json['isPartial'] as bool,
      );

  Map<String, dynamic> toJson() => {
        'generatedAt': generatedAt.toIso8601String(),
        'signals': signals.map((signal) => signal.toJson()).toList(),
        'isPartial': isPartial,
      };
}

/// Derives one conservative status without involving presentation state.
PlatformHealthStatus deriveOverallPlatformHealth(
  Iterable<PlatformHealthSignal> signals,
) {
  if (signals.isEmpty) return PlatformHealthStatus.unknown;
  if (signals.any(
    (signal) => signal.status == PlatformHealthStatus.unavailable,
  )) {
    return PlatformHealthStatus.unavailable;
  }
  if (signals.any(
    (signal) => signal.status == PlatformHealthStatus.degraded,
  )) {
    return PlatformHealthStatus.degraded;
  }
  if (signals.any((signal) => signal.status == PlatformHealthStatus.unknown)) {
    return PlatformHealthStatus.unknown;
  }
  return PlatformHealthStatus.healthy;
}

DateTime _date(Object? raw) {
  if (raw is! String) throw const FormatException('timestamp must be a string');
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) throw FormatException('invalid timestamp', raw);
  return parsed.toUtc();
}
