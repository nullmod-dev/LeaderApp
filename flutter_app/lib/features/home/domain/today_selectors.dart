import '../../../core/access/capability.dart';
import '../../detachment/domain/storage_status.dart';
import '../../shift/domain/attendance_policy.dart';
import '../../shift/domain/shift_selectors.dart';
import 'home_models.dart';

/// The dashboard's alert layer, as pure functions.
///
/// Nothing here touches Flutter, Riverpod, or a repository: given a
/// [HomeSummary], a clock, and the session's grants, these decide which
/// conditions are worth raising. The time-based questions underneath them —
/// what is running now, what is next, how attendance stands — belong to the
/// shift domain and live in `shift/domain/shift_selectors.dart`.

/// What the dashboard is allowed to raise. One kind per real condition — the
/// dashboard never invents an alert out of data it does not have.
enum DashboardAlertKind {
  /// A pending write hit a stale-write conflict and waits for a human.
  needsReview,

  /// The last sync run failed for a reason other than connectivity, and work
  /// is still queued.
  failedSync,

  /// A shift today has fewer people assigned than it needs.
  understaffedShift,

  /// A shift that has already ended still has assignees with no attendance
  /// recorded, and the one-hour ordinary window has not closed yet.
  missingAttendance,

  /// Stock is below minimum, or an item has run out.
  lowStock,

  /// Stock levels are fine but something is close to expiring.
  expiringStock,

  /// Local changes are queued and waiting for the next sync run.
  pendingSync,
}

/// Severity order, worst first. The dashboard renders alerts in this order and
/// never sorts them again somewhere else.
const List<DashboardAlertKind> dashboardAlertOrder = [
  DashboardAlertKind.needsReview,
  DashboardAlertKind.failedSync,
  DashboardAlertKind.understaffedShift,
  DashboardAlertKind.missingAttendance,
  DashboardAlertKind.lowStock,
  DashboardAlertKind.expiringStock,
  DashboardAlertKind.pendingSync,
];

/// One raised condition, with just enough to render and open it.
///
/// Deliberately carries no copy: the Arabic lives in `strings.dart` and is
/// resolved by the widget, so this stays a pure value that a test can assert
/// on without matching translated text.
class DashboardAlert {
  const DashboardAlert({required this.kind, this.count = 0, this.shiftId});

  final DashboardAlertKind kind;

  /// How many records are behind the alert — assignees still missing, items
  /// below minimum, operations queued. Zero when the kind is not a count.
  final int count;

  /// The shift an alert points at, when it points at one.
  final String? shiftId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DashboardAlert &&
          other.kind == kind &&
          other.count == count &&
          other.shiftId == shiftId;

  @override
  int get hashCode => Object.hash(kind, count, shiftId);

  @override
  String toString() =>
      'DashboardAlert(${kind.name}, count: $count, shiftId: $shiftId)';
}

/// Builds the alert list for one dashboard render.
///
/// Two rules govern everything here:
///
/// 1. **No alert without a record.** Every kind below is derived from data
///    actually loaded — a shift that is genuinely short, an item genuinely
///    below its minimum, an operation genuinely queued. Nothing is raised
///    speculatively, and a section the session could not load raises nothing
///    rather than guessing.
/// 2. **No alert a user cannot act on.** The operational kinds are gated on
///    the capability that fixes them, resolved through [Capabilities.canIn]
///    like every other check in the app. A volunteer is not told a shift is
///    understaffed when assigning is not theirs to do. The sync kinds are
///    ungated: those are the user's *own* queued writes.
List<DashboardAlert> buildDashboardAlerts({
  required HomeSummary summary,
  required DateTime now,
  required Capabilities capabilities,
  int pendingOperations = 0,
  int operationsNeedingReview = 0,
  bool lastSyncFailed = false,
}) {
  final detachmentId = summary.detachmentId;
  final canStaff = capabilities.canAnyIn(
    detachmentId,
    const {Cap.shiftAssign, Cap.shiftManage},
  );
  final canRecordAttendance = capabilities.canAnyIn(
    detachmentId,
    const {Cap.shiftAttendanceRecord, Cap.shiftAttendanceOverride},
  );
  final canSeeStock = capabilities.canAnyIn(
    detachmentId,
    const {Cap.inventoryAdjust, Cap.inventoryItemManage},
  );

  final alerts = <DashboardAlert>[];

  if (operationsNeedingReview > 0) {
    alerts.add(DashboardAlert(
      kind: DashboardAlertKind.needsReview,
      count: operationsNeedingReview,
    ));
  }
  if (lastSyncFailed && pendingOperations > 0) {
    alerts.add(DashboardAlert(
      kind: DashboardAlertKind.failedSync,
      count: pendingOperations,
    ));
  }

  final today = shiftsOnDay(summary.shifts, now);

  if (canStaff) {
    for (final shift in today) {
      // A shift that has already finished cannot be staffed any more, so a
      // gap on it is history, not a decision waiting to be made.
      if (!shift.end.isAfter(now)) continue;
      if (!shift.hasCoverageGap) continue;
      alerts.add(DashboardAlert(
        kind: DashboardAlertKind.understaffedShift,
        count: shift.gap,
        shiftId: shift.id,
      ));
    }
  }

  if (canRecordAttendance) {
    for (final shift in today) {
      // Only a finished shift can be missing attendance — one still running
      // is simply not over yet. And only while the ordinary one-hour window
      // is open, because after that this is no longer something a tap fixes.
      if (shift.end.isAfter(now)) continue;
      if (!AttendanceWindow.of(shift, now: now).isOpen) continue;
      final missing = attendanceOf(shift).awaiting;
      if (missing == 0) continue;
      alerts.add(DashboardAlert(
        kind: DashboardAlertKind.missingAttendance,
        count: missing,
        shiftId: shift.id,
      ));
    }
  }

  if (canSeeStock) {
    switch (summary.storageStatus) {
      case StorageStatus.depleted:
      case StorageStatus.low:
        alerts.add(DashboardAlert(
          kind: DashboardAlertKind.lowStock,
          count: summary.lowStockCount,
        ));
      case StorageStatus.expiring:
        alerts.add(DashboardAlert(
          kind: DashboardAlertKind.expiringStock,
          count: summary.expiringSoonCount,
        ));
      case StorageStatus.healthy:
      case StorageStatus.empty:
        break;
    }
  }

  // Queued work is worth saying once, and only when it is not already being
  // reported as a failure.
  if (pendingOperations > 0 && !lastSyncFailed) {
    alerts.add(DashboardAlert(
      kind: DashboardAlertKind.pendingSync,
      count: pendingOperations,
    ));
  }

  alerts.sort((a, b) => dashboardAlertOrder
      .indexOf(a.kind)
      .compareTo(dashboardAlertOrder.indexOf(b.kind)));
  return alerts;
}
