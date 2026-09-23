import 'package:flutter/foundation.dart';

/// The Notifications Center's value layer.
///
/// Everything here is a **projection of a record that already exists** in
/// another repository — a shift that is short, an item under its minimum, a
/// queued write that came back conflicted. There is no notification table in
/// this build and nothing here is invented to fill the screen: a kind exists
/// only where the app can point at the record behind it. See
/// `notification_selectors.dart` for the rules and `API_CONTRACT.md`
/// § Notifications for the wire shape a real backend would serve.
///
/// Deliberately carries **no copy**: the Arabic lives in `strings.dart` and is
/// resolved by the widget, exactly as `DashboardAlert` does, so a test can
/// assert on a value without matching translated text.

/// What the centre is allowed to raise. One kind per real condition.
enum NotificationKind {
  /// A pending write came back classified as a stale write and waits for a
  /// human decision. Sourced from the outbox, so it is true offline too.
  syncConflict,

  /// A queued write's last push attempt failed and it is still owed.
  syncFailed,

  /// A shift that has not ended yet has fewer people assigned than it needs.
  shiftUnderstaffed,

  /// A finished shift still has assignees with no attendance recorded, and
  /// the ordinary one-hour window has not closed.
  shiftAttendanceMissing,

  /// A shift at this detachment starts inside [shiftReminderWindow].
  shiftStartingSoon,

  /// A stock item has run out.
  stockDepleted,

  /// A stock item is at or below its minimum.
  stockLow,

  /// A stock item is inside `storageExpiringWithinDays` of its expiry date.
  stockExpiring,

  /// An internal announcement was published to this detachment.
  ///
  /// The one kind that is a **record in its own right** rather than a
  /// projection of a condition: an administrator wrote it, so it does not
  /// resolve and it does not disappear when something is fixed. That is why it
  /// is also the only kind that is *history* — see [tracksReadState] and
  /// `announcement_selectors.dart`.
  announcement,
}

/// How loudly a kind reads. Colour and icon only — it never reorders the
/// list, which stays chronological inside its day group so the feed is
/// predictable to scan.
enum NotificationSeverity { critical, warning, info }

extension NotificationKindSeverity on NotificationKind {
  NotificationSeverity get severity => switch (this) {
        NotificationKind.syncConflict => NotificationSeverity.critical,
        NotificationKind.stockDepleted => NotificationSeverity.critical,
        NotificationKind.syncFailed => NotificationSeverity.warning,
        NotificationKind.shiftUnderstaffed => NotificationSeverity.warning,
        NotificationKind.shiftAttendanceMissing => NotificationSeverity.warning,
        NotificationKind.stockLow => NotificationSeverity.warning,
        NotificationKind.stockExpiring => NotificationSeverity.warning,
        NotificationKind.shiftStartingSoon => NotificationSeverity.info,
        NotificationKind.announcement => NotificationSeverity.info,
      };
}

/// Where a notification points. **Ids only** — never a snapshot of the
/// record. A row is a pointer, and the record it points at is re-read at the
/// moment the user taps it; that is what makes a deleted shift a handled
/// state instead of a crash (see `notifications_center_page.dart`).
@immutable
sealed class NotificationTarget {
  const NotificationTarget();

  Map<String, dynamic> toJson();

  static NotificationTarget? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    switch (j['type']) {
      case 'shift':
        return ShiftTarget(
          detachmentId: j['detachmentId'] as String,
          shiftId: j['shiftId'] as String,
        );
      case 'storage':
        return StorageTarget(
          detachmentId: j['detachmentId'] as String,
          itemId: j['itemId'] as String?,
        );
      case 'review':
        return const ReviewTarget();
      case 'sync':
        return const SyncTarget();
      case 'announcement':
        return AnnouncementTarget(
            announcementId: j['announcementId'] as String);
      // An unrecognised target is dropped, not guessed: the row then renders
      // as informational rather than sending the user somewhere arbitrary.
      default:
        return null;
    }
  }
}

/// One shift, opened through the existing shift management sheet.
@immutable
class ShiftTarget extends NotificationTarget {
  const ShiftTarget({required this.detachmentId, required this.shiftId});

  final String detachmentId;
  final String shiftId;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'shift',
        'detachmentId': detachmentId,
        'shiftId': shiftId,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShiftTarget &&
          other.detachmentId == detachmentId &&
          other.shiftId == shiftId;

  @override
  int get hashCode => Object.hash('shift', detachmentId, shiftId);
}

/// One detachment's store, optionally a single item inside it.
@immutable
class StorageTarget extends NotificationTarget {
  const StorageTarget({required this.detachmentId, this.itemId});

  final String detachmentId;
  final String? itemId;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'storage',
        'detachmentId': detachmentId,
        if (itemId != null) 'itemId': itemId,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StorageTarget &&
          other.detachmentId == detachmentId &&
          other.itemId == itemId;

  @override
  int get hashCode => Object.hash('storage', detachmentId, itemId);
}

/// One announcement, opened as a read-only context view.
///
/// **Deliberately not a detachment id.** An announcement can address several
/// detachments, and picking one of them to open would send the reader to a
/// place the notice was not about. What the row opens is the notice itself —
/// its full text, who it was addressed to, and when it stops — which is a safe
/// context view rather than navigation into unrelated content.
@immutable
class AnnouncementTarget extends NotificationTarget {
  const AnnouncementTarget({required this.announcementId});

  final String announcementId;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'announcement',
        'announcementId': announcementId,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnnouncementTarget && other.announcementId == announcementId;

  @override
  int get hashCode => Object.hash('announcement', announcementId);
}

/// The Needs Review inbox.
@immutable
class ReviewTarget extends NotificationTarget {
  const ReviewTarget();

  @override
  Map<String, dynamic> toJson() => const {'type': 'review'};

  @override
  bool operator ==(Object other) => other is ReviewTarget;

  @override
  int get hashCode => 'review'.hashCode;
}

/// The sync screen in Settings.
@immutable
class SyncTarget extends NotificationTarget {
  const SyncTarget();

  @override
  Map<String, dynamic> toJson() => const {'type': 'sync'};

  @override
  bool operator ==(Object other) => other is SyncTarget;

  @override
  int get hashCode => 'sync'.hashCode;
}

/// One row of the Notifications Center.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.occurredAt,
    this.count = 0,
    this.recordLabel,
    this.target,
    this.isRead = false,
  });

  /// Stable for as long as the condition is: `stockLow:i_3`, not a fresh
  /// uuid per fetch. Read state is keyed by this, and a derived feed is
  /// rebuilt on every load — an id that changed with it would silently
  /// un-read every row. Built by [notificationId].
  final String id;

  final NotificationKind kind;

  /// The moment the row is anchored to, and the only thing the day grouping
  /// reads. Real wherever the record carries one — a shift's start or end,
  /// an expiry date, the sync attempt that failed. For a pure *state*
  /// condition (an item under its minimum) the record holds no timestamp, so
  /// this is the moment the condition was observed, which is honestly
  /// "today".
  final DateTime occurredAt;

  /// The magnitude behind the row — volunteers still missing, attendance
  /// still unrecorded, units left. Zero when the kind has no count.
  final int count;

  /// A real name from the record: a centre, a stock item, the kind of record
  /// a conflicted write touches. Never an id, never a backend tag.
  final String? recordLabel;

  /// Null for a purely informational row — the list then renders no chevron
  /// and the row does not respond to a tap.
  final NotificationTarget? target;

  final bool isRead;

  NotificationSeverity get severity => kind.severity;

  bool get isActionable => target != null;

  /// Whether this row participates in read/unread at all.
  ///
  /// False for [NotificationKind.announcement], and that is a product ruling,
  /// not an oversight: announcements carry **no read state, no receipts and no
  /// badge** (Point 14 §15). An announcement row is therefore built already
  /// read, [applyReadState] leaves it alone, and [unreadCount] does not count
  /// it — so publishing a notice never lights the bell for a row nobody is
  /// expected to acknowledge, and the unread behaviour of every other kind is
  /// untouched.
  bool get tracksReadState => kind != NotificationKind.announcement;

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        kind: kind,
        occurredAt: occurredAt,
        count: count,
        recordLabel: recordLabel,
        target: target,
        isRead: isRead ?? this.isRead,
      );

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        kind: NotificationKind.values.firstWhere(
          (k) => k.name == j['kind'],
          // An unknown kind from a newer server is dropped by the caller
          // rather than rendered as something it is not.
          orElse: () => NotificationKind.syncFailed,
        ),
        occurredAt: DateTime.parse(j['occurredAt'] as String),
        count: (j['count'] as int?) ?? 0,
        recordLabel: j['recordLabel'] as String?,
        target: NotificationTarget.fromJson(
          j['target'] as Map<String, dynamic>?,
        ),
        isRead: (j['isRead'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'occurredAt': occurredAt.toIso8601String(),
        'count': count,
        if (recordLabel != null) 'recordLabel': recordLabel,
        if (target != null) 'target': target!.toJson(),
        'isRead': isRead,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppNotification &&
          other.id == id &&
          other.kind == kind &&
          other.occurredAt == occurredAt &&
          other.count == count &&
          other.recordLabel == recordLabel &&
          other.target == target &&
          other.isRead == isRead;

  @override
  int get hashCode =>
      Object.hash(id, kind, occurredAt, count, recordLabel, target, isRead);

  @override
  String toString() => 'AppNotification(${kind.name}, $id, read: $isRead)';
}

/// The one place a notification id is built.
///
/// `<kind>:<record id>` — one row per condition per record, stable across
/// reloads. Two shifts short on the same day therefore produce two distinct
/// rows (the same sibling-key bug the dashboard alerts already hit), and a
/// row the user marked read stays read while the condition lasts.
String notificationId(NotificationKind kind, String recordId) =>
    '${kind.name}:$recordId';
