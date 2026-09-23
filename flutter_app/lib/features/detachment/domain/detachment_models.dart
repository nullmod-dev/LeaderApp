enum DetachmentStatus { active, archived }

class Detachment {
  const Detachment({
    required this.id,
    required this.detachmentGroupId,
    required this.name,
    required this.region,
    required this.mainCenter,
    required this.memberCount,
    required this.weeklyShiftCount,
    required this.coveragePercent,
    required this.status,
    this.notes,
  });

  final String id;

  /// The detachment group this detachment belongs to. Every detachment has
  /// exactly one; there is no unfiled detachment, because the detachment group
  /// is what a detachment is created *inside*.
  final String detachmentGroupId;

  final String name;
  final String region;
  final String mainCenter;
  final int memberCount;
  final int weeklyShiftCount;
  final int coveragePercent;
  final DetachmentStatus status;
  final String? notes;

  Detachment copyWith({
    String? name,
    String? region,
    String? mainCenter,
    int? memberCount,
    int? weeklyShiftCount,
    int? coveragePercent,
    DetachmentStatus? status,
    String? notes,
  }) =>
      Detachment(
        id: id,
        detachmentGroupId: detachmentGroupId,
        name: name ?? this.name,
        region: region ?? this.region,
        mainCenter: mainCenter ?? this.mainCenter,
        memberCount: memberCount ?? this.memberCount,
        weeklyShiftCount: weeklyShiftCount ?? this.weeklyShiftCount,
        coveragePercent: coveragePercent ?? this.coveragePercent,
        status: status ?? this.status,
        notes: notes ?? this.notes,
      );

  factory Detachment.fromJson(Map<String, dynamic> j) => Detachment(
        id: j['id'] as String,
        detachmentGroupId: j['detachmentGroupId'] as String,
        name: j['name'] as String,
        region: j['region'] as String,
        mainCenter: j['mainCenter'] as String,
        memberCount: j['memberCount'] as int,
        weeklyShiftCount: j['weeklyShiftCount'] as int,
        coveragePercent: j['coveragePercent'] as int,
        status:
            DetachmentStatus.values.firstWhere((s) => s.name == j['status']),
        notes: j['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'detachmentGroupId': detachmentGroupId,
        'name': name,
        'region': region,
        'mainCenter': mainCenter,
        'memberCount': memberCount,
        'weeklyShiftCount': weeklyShiftCount,
        'coveragePercent': coveragePercent,
        'status': status.name,
        if (notes != null) 'notes': notes,
      };
}

class DetachmentStats {
  const DetachmentStats({
    required this.attendanceSeries,
    required this.coverageSeries,
    required this.stockSeries,
  });

  /// Percent (0..100) per day of the last 7 days, oldest first.
  final List<int> attendanceSeries;

  /// Coverage percent per day of the last 7 days.
  final List<int> coverageSeries;

  /// Consumed units per day of the last 7 days.
  final List<int> stockSeries;

  factory DetachmentStats.fromJson(Map<String, dynamic> j) => DetachmentStats(
        attendanceSeries: (j['attendanceSeries'] as List).cast<int>(),
        coverageSeries: (j['coverageSeries'] as List).cast<int>(),
        stockSeries: (j['stockSeries'] as List).cast<int>(),
      );

  Map<String, dynamic> toJson() => {
        'attendanceSeries': attendanceSeries,
        'coverageSeries': coverageSeries,
        'stockSeries': stockSeries,
      };
}
