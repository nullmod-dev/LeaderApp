import '../../team/domain/team_models.dart';

/// Who appended a correction, captured at correction time.
///
/// Deliberately not a reference to `AuthUser` — a correction has to keep
/// reading the same way after the person who made it is renamed, and this
/// file must not import the auth feature (it is owned by shift attendance,
/// same as everything else in this file).
///
/// [id] is for internal traceability only — never render it. [displayName]
/// is the one safe value for the UI ("who corrected it").
class AttendanceCorrectionAuthor {
  const AttendanceCorrectionAuthor({
    required this.id,
    required this.displayName,
  });

  final String id;
  final String displayName;

  factory AttendanceCorrectionAuthor.fromJson(Map<String, dynamic> j) =>
      AttendanceCorrectionAuthor(
        id: j['id'] as String,
        displayName: j['displayName'] as String,
      );

  Map<String, dynamic> toJson() => {'id': id, 'displayName': displayName};
}

/// One member's attendance facts at a point in time — the before or after
/// half of a correction.
class AttendanceSnapshot {
  const AttendanceSnapshot({
    required this.status,
    this.checkInAt,
    this.checkOutAt,
  });

  final AttendanceState status;
  final DateTime? checkInAt;
  final DateTime? checkOutAt;

  factory AttendanceSnapshot.of(TeamMember member) => AttendanceSnapshot(
        status: member.attendance,
        checkInAt: member.checkInAt,
        checkOutAt: member.checkOutAt,
      );

  factory AttendanceSnapshot.fromJson(Map<String, dynamic> j) =>
      AttendanceSnapshot(
        status: attendanceStateFromWire(j['status'] as String),
        checkInAt: j['checkInAt'] == null
            ? null
            : DateTime.parse(j['checkInAt'] as String),
        checkOutAt: j['checkOutAt'] == null
            ? null
            : DateTime.parse(j['checkOutAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'status': status.name,
        if (checkInAt != null) 'checkInAt': checkInAt!.toIso8601String(),
        if (checkOutAt != null) 'checkOutAt': checkOutAt!.toIso8601String(),
      };
}

/// One append-only correction to a member's attendance on one shift.
///
/// Written once by [MockShiftRepository.addAttendanceCorrection] and never
/// edited or removed afterwards — the repository interface has no method
/// that takes a correction id. [reason] is required and already normalized
/// (non-empty, whitespace-collapsed — see [normalizeCorrectionReason]) by the
/// time an instance exists.
class AttendanceCorrection {
  const AttendanceCorrection({
    required this.id,
    required this.shiftId,
    required this.memberId,
    required this.before,
    required this.after,
    required this.reason,
    required this.author,
    required this.correctedAt,
  });

  final String id;
  final String shiftId;
  final String memberId;
  final AttendanceSnapshot before;
  final AttendanceSnapshot after;
  final String reason;
  final AttendanceCorrectionAuthor author;
  final DateTime correctedAt;

  factory AttendanceCorrection.fromJson(Map<String, dynamic> j) =>
      AttendanceCorrection(
        id: j['id'] as String,
        shiftId: j['shiftId'] as String,
        memberId: j['memberId'] as String,
        before:
            AttendanceSnapshot.fromJson(j['before'] as Map<String, dynamic>),
        after: AttendanceSnapshot.fromJson(j['after'] as Map<String, dynamic>),
        reason: j['reason'] as String,
        author: AttendanceCorrectionAuthor.fromJson(
          j['author'] as Map<String, dynamic>,
        ),
        correctedAt: DateTime.parse(j['correctedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'shiftId': shiftId,
        'memberId': memberId,
        'before': before.toJson(),
        'after': after.toJson(),
        'reason': reason,
        'author': author.toJson(),
        'correctedAt': correctedAt.toIso8601String(),
      };
}

/// Collapses leading, trailing, and repeated whitespace, and rejects a blank
/// reason outright — rejected, never silently accepted with a placeholder.
/// Returns `null` when [value] has no content; the caller must not construct
/// a correction in that case.
String? normalizeCorrectionReason(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  return normalized.isEmpty ? null : normalized;
}
