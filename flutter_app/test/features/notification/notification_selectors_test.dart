import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/sync/pending_operation.dart';
import 'package:mtm/core/sync/sync_state.dart';
import 'package:mtm/features/inventory/domain/inventory_models.dart';
import 'package:mtm/features/notification/domain/notification_models.dart';
import 'package:mtm/features/notification/domain/notification_selectors.dart';
import 'package:mtm/features/shift/domain/shift_models.dart';
import 'package:mtm/features/team/domain/team_models.dart';

/// The Notifications Center's decision layer.
///
/// Everything the screen shows is decided here, and almost none of it can be
/// produced by hand on a device: a shift exactly on its attendance lock
/// boundary, a stock item that is both empty and expiring, a feed rebuilt at
/// a different clock, a volunteer's filtered view, a day boundary at
/// midnight. Layout is not tested — the rows are ordinary rows.

const _det = 'd1';
const _other = 'd2';

const _operator = Capabilities(scoped: {_det: Cap.scoped});
const _volunteer = Capabilities(
  scoped: {
    _det: {Cap.detachmentView, Cap.memberView},
  },
);

/// Now, fixed at a mid-morning that is nowhere near a day boundary.
final _now = DateTime(2026, 9, 5, 10, 0);

TeamMember _member(String id, AttendanceState state) => TeamMember(
      id: id,
      name: 'عضو $id',
      initials: 'ع',
      role: TeamRole.member,
      detachmentId: _det,
      attendance: state,
    );

/// A shift running from [startsIn] for [length], with [needed] places.
Shift _shift({
  String id = 'sh_1',
  String detachmentId = _det,
  required Duration startsIn,
  Duration length = const Duration(hours: 4),
  int needed = 2,
  List<TeamMember> attendees = const [],
}) {
  final start = _now.add(startsIn);
  final end = start.add(length);
  return Shift(
    id: id,
    detachmentId: detachmentId,
    date: dateOnly(start),
    centerName: 'مركز الشعلان',
    startMinutes: start.hour * 60 + start.minute,
    endMinutes: end.hour * 60 + end.minute,
    needed: needed,
    attendees: attendees,
  );
}

InventoryItem _item({
  String id = 'i_1',
  String detachmentId = _det,
  String name = 'شاش طبي',
  int stock = 10,
  StockLevel level = StockLevel.ok,
  DateTime? expiresOn,
}) =>
    InventoryItem(
      id: id,
      detachmentId: detachmentId,
      name: name,
      unit: 'قطعة',
      currentStock: stock,
      minimum: 5,
      expiresOn: expiresOn,
      level: level,
    );

PendingOperation _op(
  String id, {
  SyncState state = SyncState.pending,
  String kind = 'shift.assign',
  String? entityType = 'shift',
  DateTime? attemptedAt,
}) =>
    PendingOperation.create(
      kind: kind,
      entityType: entityType,
      entityId: 'sh_1',
      idFactory: () => id,
      clock: () => _now.subtract(const Duration(hours: 2)),
    ).copyWith(state: state, lastAttemptAt: attemptedAt, attemptCount: 1);

Set<NotificationKind> _kinds(List<AppNotification> rows) =>
    {for (final row in rows) row.kind};

AppNotification _only(List<AppNotification> rows, NotificationKind kind) =>
    rows.firstWhere((row) => row.kind == kind);

void main() {
  group('shift-derived rows', () {
    test('a coming shift that is short raises exactly one understaffed row',
        () {
      final rows = buildShiftNotifications(
        detachmentId: _det,
        shifts: [
          _shift(startsIn: const Duration(hours: 20), needed: 3),
        ],
        now: _now,
      );

      final row = _only(rows, NotificationKind.shiftUnderstaffed);
      expect(row.count, 3, reason: 'three places still open');
      expect(
          row.target, const ShiftTarget(detachmentId: _det, shiftId: 'sh_1'));
      expect(row.occurredAt, _now.add(const Duration(hours: 20)));
    });

    test('a shift that has already ended raises no understaffed row', () {
      // History, not a decision: nobody can be assigned to it any more.
      final rows = buildShiftNotifications(
        detachmentId: _det,
        shifts: [
          _shift(startsIn: const Duration(hours: -6), needed: 3),
        ],
        now: _now,
      );

      expect(_kinds(rows), isNot(contains(NotificationKind.shiftUnderstaffed)));
    });

    test('attendance is raised for a finished shift inside its window', () {
      final rows = buildShiftNotifications(
        detachmentId: _det,
        // Ended thirty minutes ago; the one-hour grace window is still open.
        shifts: [
          _shift(
            startsIn: const Duration(hours: -4, minutes: -30),
            attendees: [
              _member('a', AttendanceState.checkedOut),
              _member('b', AttendanceState.notCheckedIn),
              _member('c', AttendanceState.notCheckedIn),
            ],
          ),
        ],
        now: _now,
      );

      final row = _only(rows, NotificationKind.shiftAttendanceMissing);
      expect(row.count, 2);
      expect(row.occurredAt, _now.subtract(const Duration(minutes: 30)));
    });

    test('attendance is not raised once the correction window has closed', () {
      // Ended two hours ago: past the one-hour grace, so this is no longer
      // something a tap fixes and the row would be a dead end.
      final rows = buildShiftNotifications(
        detachmentId: _det,
        shifts: [
          _shift(
            startsIn: const Duration(hours: -6),
            attendees: [_member('a', AttendanceState.notCheckedIn)],
          ),
        ],
        now: _now,
      );

      expect(
        _kinds(rows),
        isNot(contains(NotificationKind.shiftAttendanceMissing)),
      );
    });

    test('a reminder is raised inside the window and not outside it', () {
      final soon = buildShiftNotifications(
        detachmentId: _det,
        shifts: [_shift(startsIn: const Duration(hours: 3))],
        now: _now,
      );
      final distant = buildShiftNotifications(
        detachmentId: _det,
        shifts: [
          _shift(startsIn: shiftReminderWindow + const Duration(minutes: 1))
        ],
        now: _now,
      );
      final running = buildShiftNotifications(
        detachmentId: _det,
        shifts: [_shift(startsIn: const Duration(hours: -1))],
        now: _now,
      );

      expect(_kinds(soon), contains(NotificationKind.shiftStartingSoon));
      expect(
        _kinds(distant),
        isNot(contains(NotificationKind.shiftStartingSoon)),
      );
      expect(
        _kinds(running),
        isNot(contains(NotificationKind.shiftStartingSoon)),
        reason: 'a shift already running is not something to be reminded of',
      );
    });

    test('a shift belonging to another detachment is skipped', () {
      final rows = buildShiftNotifications(
        detachmentId: _det,
        shifts: [
          _shift(detachmentId: _other, startsIn: const Duration(hours: 2)),
        ],
        now: _now,
      );

      expect(rows, isEmpty);
    });

    test('two shifts short on one day produce two distinct ids', () {
      // The sibling-key bug the dashboard alerts already hit once: a key on
      // the kind alone is a hard crash when one day carries two of them.
      final rows = buildShiftNotifications(
        detachmentId: _det,
        shifts: [
          _shift(id: 'sh_1', startsIn: const Duration(hours: 2), needed: 3),
          _shift(id: 'sh_2', startsIn: const Duration(hours: 8), needed: 4),
        ],
        now: _now,
      );

      final understaffed = [
        for (final row in rows)
          if (row.kind == NotificationKind.shiftUnderstaffed) row.id,
      ];
      expect(understaffed.toSet().length, 2);
    });
  });

  group('stock-derived rows', () {
    test('an item that is empty and also expiring raises one row, the worst',
        () {
      final rows = buildStockNotifications(
        detachmentId: _det,
        items: [
          _item(
            level: StockLevel.empty,
            stock: 0,
            expiresOn: _now.add(const Duration(days: 3)),
          ),
        ],
        now: _now,
      );

      expect(rows.length, 1);
      expect(rows.single.kind, NotificationKind.stockDepleted);
    });

    test('an expiring row is anchored to the real expiry date', () {
      final expiry = _now.add(const Duration(days: 12));
      final rows = buildStockNotifications(
        detachmentId: _det,
        items: [_item(expiresOn: expiry)],
        now: _now,
      );

      expect(rows.single.kind, NotificationKind.stockExpiring);
      expect(rows.single.occurredAt, expiry);
      expect(
        notificationGroupOf(rows.single.occurredAt, _now),
        NotificationGroup.upcoming,
      );
    });

    test('an item outside the expiry horizon raises nothing', () {
      final rows = buildStockNotifications(
        detachmentId: _det,
        items: [_item(expiresOn: _now.add(const Duration(days: 90)))],
        now: _now,
      );

      expect(rows, isEmpty);
    });

    test('a low item carries the stock actually left', () {
      final rows = buildStockNotifications(
        detachmentId: _det,
        items: [_item(level: StockLevel.low, stock: 2)],
        now: _now,
      );

      expect(rows.single.kind, NotificationKind.stockLow);
      expect(rows.single.count, 2);
      expect(rows.single.recordLabel, 'شاش طبي');
    });
  });

  group('outbox-derived rows', () {
    test('a conflicted operation points at the review inbox', () {
      final rows = buildSyncNotifications(
        operations: [
          _op('op1', state: SyncState.conflict, attemptedAt: _now),
        ],
      );

      expect(rows.single.kind, NotificationKind.syncConflict);
      expect(rows.single.target, const ReviewTarget());
      expect(rows.single.occurredAt, _now);
    });

    test('a failed operation points at the sync screen', () {
      final rows = buildSyncNotifications(
        operations: [_op('op1', state: SyncState.failed, attemptedAt: _now)],
      );

      expect(rows.single.kind, NotificationKind.syncFailed);
      expect(rows.single.target, const SyncTarget());
    });

    test('an operation merely waiting to sync raises nothing', () {
      // Queued work is normal, not a notification. The dashboard and Settings
      // already carry the count.
      expect(buildSyncNotifications(operations: [_op('op1')]), isEmpty);
    });
  });

  group('ids are a function of the condition, not of the fetch', () {
    test('the same conditions rebuilt an hour later keep their ids', () {
      List<String> idsAt(DateTime now) => [
            ...buildShiftNotifications(
              detachmentId: _det,
              shifts: [
                _shift(
                    startsIn: now.difference(_now) + const Duration(hours: 20),
                    needed: 3)
              ],
              now: now,
            ),
            ...buildStockNotifications(
              detachmentId: _det,
              items: [_item(level: StockLevel.low, stock: 2)],
              now: now,
            ),
          ].map((row) => row.id).toList()
            ..sort();

      // A regenerated id would silently un-read every row the user had
      // already seen, because read state is keyed by it.
      expect(idsAt(_now), idsAt(_now.add(const Duration(hours: 1))));
    });
  });

  group('capability filtering', () {
    List<AppNotification> feed() => [
          ...buildShiftNotifications(
            detachmentId: _det,
            shifts: [
              _shift(startsIn: const Duration(hours: 3), needed: 3),
            ],
            now: _now,
          ),
          ...buildStockNotifications(
            detachmentId: _det,
            items: [_item(level: StockLevel.low, stock: 2)],
            now: _now,
          ),
          ...buildSyncNotifications(
            operations: [
              _op('op1', state: SyncState.failed, attemptedAt: _now),
            ],
          ),
        ];

    test('an operator sees every kind the records raise', () {
      final rows = visibleNotifications(
        feed(),
        detachmentId: _det,
        capabilities: _operator,
      );

      expect(
        _kinds(rows),
        containsAll(const {
          NotificationKind.shiftUnderstaffed,
          NotificationKind.shiftStartingSoon,
          NotificationKind.stockLow,
          NotificationKind.syncFailed,
        }),
      );
    });

    test('a volunteer is not told about staffing or the store', () {
      final rows = visibleNotifications(
        feed(),
        detachmentId: _det,
        capabilities: _volunteer,
      );

      expect(_kinds(rows), isNot(contains(NotificationKind.shiftUnderstaffed)));
      expect(_kinds(rows), isNot(contains(NotificationKind.stockLow)));
      // What they may know, they still know: the shift they may work, and
      // their own queued write.
      expect(_kinds(rows), contains(NotificationKind.shiftStartingSoon));
      expect(_kinds(rows), contains(NotificationKind.syncFailed));
    });

    test('a row is gated inside the detachment it points at', () {
      // Grants are per detachment. A row about another detachment's store
      // must not ride in on the grants held for the one on screen.
      final rows = visibleNotifications(
        buildStockNotifications(
          detachmentId: _other,
          items: [_item(detachmentId: _other, level: StockLevel.low)],
          now: _now,
        ),
        detachmentId: _det,
        capabilities: _operator,
      );

      expect(rows, isEmpty);
    });
  });

  group('read state and the unread count', () {
    final rows = [
      AppNotification(
        id: 'a',
        kind: NotificationKind.stockLow,
        occurredAt: _now,
      ),
      AppNotification(
        id: 'b',
        kind: NotificationKind.stockLow,
        occurredAt: _now,
      ),
    ];

    test('stored ids are stamped onto a freshly derived feed', () {
      final stamped = applyReadState(rows, {'a'});

      expect(stamped.firstWhere((r) => r.id == 'a').isRead, isTrue);
      expect(stamped.firstWhere((r) => r.id == 'b').isRead, isFalse);
      expect(unreadCount(stamped), 1);
    });

    test('a stored id for a condition that is gone counts for nothing', () {
      expect(unreadCount(applyReadState(rows, {'a', 'vanished'})), 1);
    });
  });

  group('day grouping', () {
    test('the boundary is the calendar day, not elapsed hours', () {
      final now = DateTime(2026, 9, 5, 23, 30);

      expect(
        notificationGroupOf(DateTime(2026, 9, 5, 23, 59, 59), now),
        NotificationGroup.today,
      );
      expect(
        // Thirty minutes away, and still tomorrow's.
        notificationGroupOf(DateTime(2026, 9, 6), now),
        NotificationGroup.upcoming,
      );
      expect(
        notificationGroupOf(DateTime(2026, 9, 4), now),
        NotificationGroup.yesterday,
      );
      expect(
        notificationGroupOf(DateTime(2026, 9, 3, 23, 59), now),
        NotificationGroup.earlier,
      );
    });

    test('groups run coming-up first, then backwards through the past', () {
      AppNotification at(String id, DateTime when) => AppNotification(
            id: id,
            kind: NotificationKind.stockLow,
            occurredAt: when,
          );

      final sections = groupNotifications(
        [
          at('earlier', _now.subtract(const Duration(days: 4))),
          at('today-early', _now.subtract(const Duration(hours: 5))),
          at('later', _now.add(const Duration(days: 3))),
          at('today-late', _now.subtract(const Duration(minutes: 5))),
          at('soon', _now.add(const Duration(days: 1))),
          at('yesterday', _now.subtract(const Duration(days: 1))),
        ],
        _now,
      );

      expect(
        [for (final s in sections) s.group],
        const [
          NotificationGroup.upcoming,
          NotificationGroup.today,
          NotificationGroup.yesterday,
          NotificationGroup.earlier,
        ],
      );
      // Soonest first while it is still ahead of you...
      expect(
        [for (final row in sections.first.items) row.id],
        const ['soon', 'later'],
      );
      // ...newest first once it is behind you.
      expect(
        [for (final row in sections[1].items) row.id],
        const ['today-late', 'today-early'],
      );
    });

    test('rows at the same instant order by id, so a rebuild cannot swap them',
        () {
      final sections = groupNotifications(
        [
          AppNotification(
            id: 'b',
            kind: NotificationKind.stockLow,
            occurredAt: _now,
          ),
          AppNotification(
            id: 'a',
            kind: NotificationKind.stockLow,
            occurredAt: _now,
          ),
        ],
        _now,
      );

      expect([for (final row in sections.single.items) row.id], ['a', 'b']);
    });
  });

  group('destinations', () {
    AppNotification withTarget(NotificationTarget? target) => AppNotification(
          id: 'n',
          kind: NotificationKind.shiftUnderstaffed,
          occurredAt: _now,
          target: target,
        );

    test('a shift row opens the management sheet when the grants allow it', () {
      final destination = destinationFor(
        withTarget(const ShiftTarget(detachmentId: _det, shiftId: 'sh_1')),
        _operator,
      );

      expect(destination, isA<OpenShiftSheet>());
      expect((destination as OpenShiftSheet).shiftId, 'sh_1');
    });

    test('without the shift grants it degrades to the schedule tab', () {
      // Not blocked — degraded. A sheet where every control is disabled is a
      // worse answer than the read-only surface that owns the record.
      final destination = destinationFor(
        withTarget(const ShiftTarget(detachmentId: _det, shiftId: 'sh_1')),
        _volunteer,
      );

      expect(destination, isA<OpenDetachmentTab>());
      expect((destination as OpenDetachmentTab).tab, 'shifts');
    });

    test('a stock row opens the store tab, never the item form', () {
      // Editing an item needs `inventory.item.manage`, which a medic who may
      // only adjust stock does not hold.
      final destination = destinationFor(
        withTarget(const StorageTarget(detachmentId: _det, itemId: 'i_1')),
        _operator,
      );

      expect((destination as OpenDetachmentTab).tab, 'storage');
    });

    test('sync rows reuse the review inbox and the sync screen', () {
      expect(
        destinationFor(withTarget(const ReviewTarget()), _operator),
        isA<OpenNeedsReview>(),
      );
      expect(
        destinationFor(withTarget(const SyncTarget()), _operator),
        isA<OpenSyncScreen>(),
      );
    });

    test('a row with no target leads nowhere', () {
      expect(destinationFor(withTarget(null), _operator), isA<NoDestination>());
      expect(withTarget(null).isActionable, isFalse);
    });
  });
}
