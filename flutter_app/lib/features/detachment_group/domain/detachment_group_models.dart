/// A detachment group is the umbrella several detachments belong to — one
/// branch, one organisation, one operating area. Several detachments in the
/// same place, run by the same people, under one name.
///
/// **Not a `SaasTenant`.** The paying customer, the subscription and the
/// data-isolation boundary are a separate concept that the backend keys on
/// `tenantId`; a detachment group lives *inside* one and groups detachments
/// for the people who run them. This type was called `Tenant` until Point 1,
/// which is exactly the collision the rename removed.
///
/// Deliberately thin: creating one asks for a name and nothing else. Every
/// operational field lives on the detachments inside it, because that is
/// where the work happens.
enum DetachmentGroupStatus { active, archived }

class DetachmentGroup {
  const DetachmentGroup({
    required this.id,
    required this.name,
    required this.createdAt,
    this.notes,
    this.status = DetachmentGroupStatus.active,
    this.detachmentCount = 0,
    this.memberCount = 0,
    this.coveragePercent = 0,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final String? notes;
  final DetachmentGroupStatus status;

  /// The three roll-ups shown on the detachment group card. They are
  /// **derived**, not stored: `MockDetachmentGroupRepository` recomputes them
  /// from the detachments it is handed on every read, so a card can never show
  /// a count that the list underneath it disagrees with.
  final int detachmentCount;
  final int memberCount;
  final int coveragePercent;

  DetachmentGroup copyWith({
    String? name,
    String? notes,
    DetachmentGroupStatus? status,
    int? detachmentCount,
    int? memberCount,
    int? coveragePercent,
  }) =>
      DetachmentGroup(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        notes: notes ?? this.notes,
        status: status ?? this.status,
        detachmentCount: detachmentCount ?? this.detachmentCount,
        memberCount: memberCount ?? this.memberCount,
        coveragePercent: coveragePercent ?? this.coveragePercent,
      );

  factory DetachmentGroup.fromJson(Map<String, dynamic> j) => DetachmentGroup(
        id: j['id'] as String,
        name: j['name'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        notes: j['notes'] as String?,
        status: DetachmentGroupStatus.values
            .firstWhere((s) => s.name == j['status']),
        detachmentCount: (j['detachmentCount'] as int?) ?? 0,
        memberCount: (j['memberCount'] as int?) ?? 0,
        coveragePercent: (j['coveragePercent'] as int?) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        if (notes != null) 'notes': notes,
        'status': status.name,
        'detachmentCount': detachmentCount,
        'memberCount': memberCount,
        'coveragePercent': coveragePercent,
      };
}
