import '../../../core/access/capability.dart';
import '../../../core/sync/pending_operation.dart';
import '../../../core/sync/sync_state.dart';
import '../../announcement/domain/announcement_models.dart';
import '../../conflict/domain/needs_review_item.dart';
import '../../detachment/domain/storage_status.dart';
import '../../inventory/domain/inventory_models.dart';
import '../../shift/domain/attendance_policy.dart';
import '../../shift/domain/shift_models.dart';
import '../../shift/domain/shift_selectors.dart';
import 'notification_models.dart';

/// The Notifications Center's decision layer, as pure functions.
///
/// Nothing here touches Flutter, Riverpod, or a repository. Three rules
/// govern all of it — the same two the dashboard alerts follow, plus the one
/// a persistent feed adds:
///
/// 1. **No notification without a record.** Every kind is derived from data
///    actually loaded. A section that failed to load raises nothing rather
///    than guessing.
/// 2. **No notification a user may not see.** [visibleNotifications] drops
///    the kinds whose subject the session's grants do not cover, resolved
///    through [Capabilities.canIn] like every other check in the app. The
///    sync kinds are ungated: those are the user's *own* queued writes.
/// 3. **A stable id per condition.** Read state is keyed by
///    [AppNotification.id], and the feed is rebuilt from scratch on every
///    load, so the id must be a function of the condition and not of the
///    fetch.

/// How far ahead a shift is worth a reminder. Matches the intent of the
/// `shiftReminders` preference in Settings ("before your shift starts"),
/// widened from an hour because this is a list the user opens rather than a
/// push that arrives.
const Duration shiftReminderWindow = Duration(hours: 6);

/// The keys that make the shift management sheet worth opening — the same
/// set the dashboard uses to decide whether its shift cards are tappable.
const Set<String> shiftSheetCapabilities = {
  Cap.shiftManage,
  Cap.shiftAssign,
  Cap.shiftDelete,
  Cap.shiftAttendanceRecord,
  Cap.shiftAttendanceOverride,
};

// ---------------------------------------------------------------------------
// Builders — one per source of truth.
// ---------------------------------------------------------------------------

/// Shift-derived notifications for one detachment.
///
/// Uncapped on purpose: the repository that calls this has no session, and
/// filtering belongs in one place — [visibleNotifications].
List<AppNotification> buildShiftNotifications({
  required String detachmentId,
  required List<Shift> shifts,
  required DateTime now,
}) {
  final out = <AppNotification>[];

  for (final shift in shifts) {
    if (shift.detachmentId != detachmentId) continue;
    final target = ShiftTarget(
      detachmentId: detachmentId,
      shiftId: shift.id,
    );

    // Short of people, and still fixable: a shift that has already finished
    // cannot be staffed any more, so a gap on it is history.
    if (shift.end.isAfter(now) && shift.hasCoverageGap) {
      out.add(AppNotification(
        id: notificationId(NotificationKind.shiftUnderstaffed, shift.id),
        kind: NotificationKind.shiftUnderstaffed,
        occurredAt: shift.start,
        count: shift.gap,
        recordLabel: shift.centerName,
        target: target,
      ));
    }

    // Finished, attendance still blank, and the ordinary window still open —
    // after it closes this is no longer something a tap fixes.
    if (!shift.end.isAfter(now) &&
        AttendanceWindow.of(shift, now: now).isOpen) {
      final awaiting = attendanceOf(shift).awaiting;
      if (awaiting > 0) {
        out.add(AppNotification(
          id: notificationId(
            NotificationKind.shiftAttendanceMissing,
            shift.id,
          ),
          kind: NotificationKind.shiftAttendanceMissing,
          occurredAt: shift.end,
          count: awaiting,
          recordLabel: shift.centerName,
          target: target,
        ));
      }
    }

    // Starting soon. `isAfter(now)` and not further out than the window —
    // a shift already running is reported by the dashboard, not reminded of.
    final untilStart = shift.start.difference(now);
    if (!untilStart.isNegative && untilStart <= shiftReminderWindow) {
      out.add(AppNotification(
        id: notificationId(NotificationKind.shiftStartingSoon, shift.id),
        kind: NotificationKind.shiftStartingSoon,
        occurredAt: shift.start,
        recordLabel: shift.centerName,
        target: target,
      ));
    }
  }

  return out;
}

/// Stock-derived notifications for one detachment.
///
/// **One row per item, worst condition wins** — the same worst-wins fold
/// [storageStatusOf] uses for the detachment's one-word verdict. An item that
/// has run out and also happens to be expiring is first an item that has run
/// out, and telling the user twice about one bottle is noise, not coverage.
List<AppNotification> buildStockNotifications({
  required String detachmentId,
  required List<InventoryItem> items,
  required DateTime now,
}) {
  final out = <AppNotification>[];

  for (final item in items) {
    if (item.detachmentId != detachmentId) continue;
    final target = StorageTarget(detachmentId: detachmentId, itemId: item.id);

    if (item.level == StockLevel.empty) {
      out.add(AppNotification(
        id: notificationId(NotificationKind.stockDepleted, item.id),
        kind: NotificationKind.stockDepleted,
        // The record carries no event time; the condition is true now.
        occurredAt: now,
        recordLabel: item.name,
        target: target,
      ));
      continue;
    }

    if (item.level == StockLevel.low) {
      out.add(AppNotification(
        id: notificationId(NotificationKind.stockLow, item.id),
        kind: NotificationKind.stockLow,
        occurredAt: now,
        count: item.currentStock,
        recordLabel: item.name,
        target: target,
      ));
      continue;
    }

    // Expiry is the one stock fact with a real date on the record, so the
    // row is anchored to it — which is also what puts it in the "coming up"
    // group instead of pretending it happened today.
    final expiresOn = item.expiresOn;
    if (expiresOn == null) continue;
    final days = _wholeDaysBetween(now, expiresOn);
    if (days <= storageExpiringWithinDays) {
      out.add(AppNotification(
        id: notificationId(NotificationKind.stockExpiring, item.id),
        kind: NotificationKind.stockExpiring,
        occurredAt: expiresOn,
        recordLabel: item.name,
        target: target,
      ));
    }
  }

  return out;
}

/// Client-owned notifications, read straight off the local outbox.
///
/// These are the user's *own* queued writes, so they are as true offline as
/// they are online and no repository is involved. [needsReviewRecordLabel]
/// resolves the operation's opaque tags to real copy — the same mapping the
/// Needs Review inbox uses, so the two surfaces name a record identically.
List<AppNotification> buildSyncNotifications({
  required List<PendingOperation> operations,
}) {
  final out = <AppNotification>[];

  for (final op in operations) {
    final label = needsReviewRecordLabel(
      entityType: op.entityType,
      kind: op.kind,
    );
    // The attempt that produced the verdict; `createdAt` only for a record
    // restored without attempt bookkeeping.
    final at = op.lastAttemptAt ?? op.createdAt;

    if (op.needsReview) {
      out.add(AppNotification(
        id: notificationId(NotificationKind.syncConflict, op.operationId),
        kind: NotificationKind.syncConflict,
        occurredAt: at,
        recordLabel: label,
        target: const ReviewTarget(),
      ));
      continue;
    }

    if (op.state == SyncState.failed) {
      out.add(AppNotification(
        id: notificationId(NotificationKind.syncFailed, op.operationId),
        kind: NotificationKind.syncFailed,
        occurredAt: at,
        count: op.attemptCount,
        recordLabel: label,
        target: const SyncTarget(),
      ));
    }
  }

  return out;
}

/// Announcement-derived notifications for one detachment.
///
/// The Notifications Center is the announcement system's **history** surface,
/// so this builder is deliberately indiscriminate about lifetime: an expired
/// announcement and a withdrawn one produce a row exactly like an active one.
/// Losing a Home promotion, running past an expiry, or being withdrawn all stop
/// *placements*; none of them un-tells a detachment something it was told. The
/// only thing that removes one of these rows is an administrator clearing
/// notification history deliberately, which the caller applies through
/// [clearedIds].
///
/// Each row is built already read — announcements carry no read state at all
/// (see [AppNotification.tracksReadState]).
List<AppNotification> buildAnnouncementNotifications({
  required String detachmentId,
  required List<Announcement> announcements,
  Set<String> clearedIds = const {},
}) {
  final out = <AppNotification>[];

  for (final a in announcements) {
    if (!a.targets(detachmentId)) continue;
    final id = notificationId(NotificationKind.announcement, a.id);
    if (clearedIds.contains(id)) continue;
    out.add(AppNotification(
      id: id,
      kind: NotificationKind.announcement,
      // The moment the notice was sent. Real, on the record, and what puts an
      // announcement in the right day group rather than pretending it is
      // today's.
      occurredAt: a.publishedAt,
      // The row shows the notice itself — the text *is* the record. Truncated
      // for scanning by the row; the full text is one tap away.
      recordLabel: a.text,
      target: AnnouncementTarget(announcementId: a.id),
      isRead: true,
    ));
  }

  return out;
}

// ---------------------------------------------------------------------------
// Access, read state, ordering.
// ---------------------------------------------------------------------------

/// The capability that has to be held for a kind to be shown at all.
///
/// An empty set means "always visible". Mirrors `buildDashboardAlerts`: a
/// volunteer is not told a shift is understaffed when assigning is not theirs
/// to do, and is not told about the store at all when the store is not theirs
/// to touch. [NotificationKind.shiftStartingSoon] is the informational case —
/// anyone who can see the detachment may know a shift is about to start.
Set<String> requiredCapabilities(NotificationKind kind) => switch (kind) {
      NotificationKind.syncConflict => const {},
      NotificationKind.syncFailed => const {},
      NotificationKind.shiftUnderstaffed => const {
          Cap.shiftAssign,
          Cap.shiftManage,
        },
      NotificationKind.shiftAttendanceMissing => const {
          Cap.shiftAttendanceRecord,
          Cap.shiftAttendanceOverride,
        },
      NotificationKind.shiftStartingSoon => const {Cap.detachmentView},
      // Seeing a notice addressed to a detachment follows from being able to
      // see that detachment, which any scoped grant implies. There is
      // deliberately no `announcement.view` key — it would gate nothing.
      NotificationKind.announcement => const {Cap.detachmentView},
      NotificationKind.stockDepleted ||
      NotificationKind.stockLow ||
      NotificationKind.stockExpiring =>
        const {Cap.inventoryAdjust, Cap.inventoryItemManage},
    };

/// Drops every row the session's grants do not cover.
///
/// TODO(security): a UX gate, like every capability check in this app. A real
/// backend must not put a notification in the feed the caller may not see —
/// see the contract at the top of `capability.dart`.
List<AppNotification> visibleNotifications(
  List<AppNotification> items, {
  required String detachmentId,
  required Capabilities capabilities,
}) {
  return [
    for (final n in items)
      if (_visible(n, detachmentId, capabilities)) n,
  ];
}

bool _visible(
  AppNotification n,
  String detachmentId,
  Capabilities capabilities,
) {
  final required = requiredCapabilities(n.kind);
  if (required.isEmpty) return true;
  // A targeted row is checked inside the detachment it actually points at,
  // never the one that happens to be on screen.
  final scope = switch (n.target) {
    ShiftTarget(:final detachmentId) => detachmentId,
    StorageTarget(:final detachmentId) => detachmentId,
    _ => detachmentId,
  };
  return capabilities.canAnyIn(scope, required);
}

/// Stamps the stored read set onto a freshly derived feed.
///
/// Rows that do not track read state are passed through untouched — an
/// announcement is built read and stays read, whatever is or is not in the
/// stored set.
List<AppNotification> applyReadState(
  List<AppNotification> items,
  Set<String> readIds,
) =>
    [
      for (final n in items)
        if (!n.tracksReadState)
          n
        else
          n.isRead == readIds.contains(n.id)
              ? n
              : n.copyWith(isRead: readIds.contains(n.id)),
    ];

/// How many rows still want the user's attention — the number the badge
/// shows. Derived from the same list the screen renders, which is what makes
/// the two impossible to disagree.
int unreadCount(List<AppNotification> items) {
  var n = 0;
  for (final item in items) {
    if (item.tracksReadState && !item.isRead) n++;
  }
  return n;
}

/// Which day bucket a row belongs to.
enum NotificationGroup { upcoming, today, yesterday, earlier }

/// The bucket, by calendar day — never by elapsed hours. A shift at 00:30
/// tomorrow is tomorrow's, even when it is ninety minutes away.
NotificationGroup notificationGroupOf(DateTime occurredAt, DateTime now) {
  final day = dateOnly(occurredAt);
  final today = dateOnly(now);
  if (day.isAfter(today)) return NotificationGroup.upcoming;
  if (day == today) return NotificationGroup.today;
  if (day == today.subtract(const Duration(days: 1))) {
    return NotificationGroup.yesterday;
  }
  return NotificationGroup.earlier;
}

/// The order the groups are rendered in. Coming-up first: a shift that starts
/// in four hours is a decision, and yesterday's is a record.
const List<NotificationGroup> notificationGroupOrder = [
  NotificationGroup.upcoming,
  NotificationGroup.today,
  NotificationGroup.yesterday,
  NotificationGroup.earlier,
];

/// One rendered section: a day bucket and its rows, already ordered.
class NotificationSection {
  const NotificationSection({required this.group, required this.items});

  final NotificationGroup group;
  final List<AppNotification> items;
}

/// Buckets and orders the feed for rendering.
///
/// Chronological inside a bucket, not severity-ordered: severity is carried
/// by the icon and its tint, and a list that reshuffles by importance is a
/// list the user cannot find yesterday's row in twice running. Upcoming runs
/// soonest-first (the next thing to happen is the top of the list); the past
/// buckets run newest-first. Ties break on id so the order is total and a
/// rebuild never swaps two rows.
List<NotificationSection> groupNotifications(
  List<AppNotification> items,
  DateTime now,
) {
  final buckets = <NotificationGroup, List<AppNotification>>{};
  for (final item in items) {
    buckets
        .putIfAbsent(notificationGroupOf(item.occurredAt, now), () => [])
        .add(item);
  }

  final sections = <NotificationSection>[];
  for (final group in notificationGroupOrder) {
    final rows = buckets[group];
    if (rows == null || rows.isEmpty) continue;
    final ascending = group == NotificationGroup.upcoming;
    rows.sort((a, b) {
      final byTime = ascending
          ? a.occurredAt.compareTo(b.occurredAt)
          : b.occurredAt.compareTo(a.occurredAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    sections.add(NotificationSection(group: group, items: rows));
  }
  return sections;
}

// ---------------------------------------------------------------------------
// Destinations.
// ---------------------------------------------------------------------------

/// Where a row leads. Every value maps to a surface that **already exists** —
/// the centre opens nothing of its own, and a row with nowhere meaningful to
/// go gets [NoDestination] rather than a dead chevron.

sealed class NotificationDestination {
  const NotificationDestination();
}

/// Informational: the row renders no chevron and does not respond to a tap.
class NoDestination extends NotificationDestination {
  const NoDestination();
}

/// The existing shift management sheet.
class OpenShiftSheet extends NotificationDestination {
  const OpenShiftSheet({required this.detachmentId, required this.shiftId});
  final String detachmentId;
  final String shiftId;
}

/// One of the existing detachment detail tabs, e.g. `shifts` or `storage`.
class OpenDetachmentTab extends NotificationDestination {
  const OpenDetachmentTab({required this.detachmentId, required this.tab});
  final String detachmentId;
  final String tab;
}

/// The existing Needs Review inbox.
class OpenNeedsReview extends NotificationDestination {
  const OpenNeedsReview();
}

/// The existing sync screen in Settings.
class OpenSyncScreen extends NotificationDestination {
  const OpenSyncScreen();
}

/// One announcement, as a read-only context view over the row itself.
///
/// The only destination in this file that is not another screen: an
/// announcement has no record elsewhere to open, so what a tap gives is the
/// full text the row had to truncate. The alternative — sending the reader to
/// one of the detachments the notice happens to name — is precisely the
/// arbitrary navigation Point 14 §21 forbids.
class OpenAnnouncement extends NotificationDestination {
  const OpenAnnouncement({required this.announcementId});
  final String announcementId;
}

/// Resolves a row's destination against the session's grants.
///
/// The gate degrades rather than blocks: a volunteer who may see that a shift
/// starts soon, but may not staff or mark it, is taken to the schedule tab
/// instead of a management sheet where every control would be disabled.
/// Nothing here bypasses a capability — the sheet's own controls are still
/// gated one at a time.
NotificationDestination destinationFor(
  AppNotification notification,
  Capabilities capabilities,
) {
  switch (notification.target) {
    case null:
      return const NoDestination();
    case ShiftTarget(:final detachmentId, :final shiftId):
      return capabilities.canAnyIn(detachmentId, shiftSheetCapabilities)
          ? OpenShiftSheet(detachmentId: detachmentId, shiftId: shiftId)
          : OpenDetachmentTab(detachmentId: detachmentId, tab: 'shifts');
    case StorageTarget(:final detachmentId):
      // The tab, not the item form: editing an item needs
      // `inventory.item.manage`, which a medic who may only adjust stock does
      // not hold. The tab lists the item and is the surface that owns it.
      return OpenDetachmentTab(detachmentId: detachmentId, tab: 'storage');
    case ReviewTarget():
      return const OpenNeedsReview();
    case SyncTarget():
      return const OpenSyncScreen();
    case AnnouncementTarget(:final announcementId):
      return OpenAnnouncement(announcementId: announcementId);
  }
}

int _wholeDaysBetween(DateTime from, DateTime to) =>
    dateOnly(to).difference(dateOnly(from)).inDays;
