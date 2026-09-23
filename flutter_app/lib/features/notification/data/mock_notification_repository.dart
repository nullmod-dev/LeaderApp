import '../../../core/result/result.dart';
import '../../inventory/domain/inventory_models.dart';
import '../../inventory/domain/inventory_repository.dart';
import '../../shift/domain/shift_models.dart';
import '../../shift/domain/shift_repository.dart';
import '../domain/notification_models.dart';
import '../domain/notification_repository.dart';
import '../domain/notification_selectors.dart';

/// Builds the record-derived feed by joining the repositories that already
/// own the data — the same thing a real backend does behind
/// `GET /api/v1/notifications`.
///
/// It **composes rather than seeds**, the pattern `MockHomeRepository`
/// already uses, and that is the whole point: there is no notification table
/// in this build, so a seeded list would put rows on screen that exist
/// nowhere else in the app and carry no id anything could be opened by. Every
/// row below is derived from the same mock the surface it links to reads
/// from, and disappears the moment its condition is resolved.
class MockNotificationRepository implements NotificationRepository {
  MockNotificationRepository({
    required ShiftRepository shifts,
    InventoryRepository? inventory,
    DateTime Function()? clock,
  })  : _shifts = shifts,
        _inventory = inventory,
        _clock = clock ?? DateTime.now;

  final ShiftRepository _shifts;
  final InventoryRepository? _inventory;
  final DateTime Function() _clock;

  /// Yesterday through tomorrow — the same three-day window the dashboard
  /// summary reads, so the two surfaces cannot disagree about a shift.
  /// Yesterday because a night shift that ended at 02:00 can still be inside
  /// its attendance window; tomorrow because a reminder six hours ahead can
  /// cross midnight.
  static const Duration _lookBehind = Duration(days: 1);
  static const Duration _lookAhead = Duration(days: 1);

  @override
  Future<Result<List<AppNotification>>> feed(String detachmentId) async {
    final now = _clock();
    final today = dateOnly(now);

    final shifts = await _shifts.listForRange(
      detachmentId,
      today.subtract(_lookBehind),
      today.add(_lookAhead),
    );
    final items = _inventory == null
        ? const Success<List<InventoryItem>>([])
        : await _inventory.listForDetachment(detachmentId);

    // Null means the section could not be read at all — a failure, or offline
    // with nothing cached. Either section alone degrades to "nothing known",
    // so an unreachable store never takes the schedule's rows down with it.
    final shiftRows = _readable(shifts);
    final itemRows = _readable(items);

    if (shiftRows == null && itemRows == null) {
      // Nothing to be a feed *about*. Offline outranks failure: a device with
      // no connectivity is not a broken screen, and the two say very
      // different things to the person holding it.
      if (shifts is Offline<List<Shift>> ||
          items is Offline<List<InventoryItem>>) {
        return const Offline();
      }
      if (shifts case Failure<List<Shift>>(:final message, :final code)) {
        return Failure(message, code: code);
      }
      if (items
          case Failure<List<InventoryItem>>(:final message, :final code)) {
        return Failure(message, code: code);
      }
      return const Offline();
    }

    final rows = [
      ...buildShiftNotifications(
        detachmentId: detachmentId,
        shifts: shiftRows ?? const [],
        now: now,
      ),
      ...buildStockNotifications(
        detachmentId: detachmentId,
        items: itemRows ?? const [],
        now: now,
      ),
    ];

    // A partial answer says so rather than passing a half-loaded feed off as
    // complete: no connectivity on either section is offline-with-cache, and
    // a section served from cache after a failed refresh is stale. Both land
    // on the same shared badge, and neither blanks the screen.
    if (shifts is Offline<List<Shift>> ||
        items is Offline<List<InventoryItem>>) {
      return Offline(cached: rows);
    }
    return Success(rows, stale: _isStale(shifts) || _isStale(items));
  }

  /// The rows a section yielded, or null when it yielded nothing at all.
  static List<T>? _readable<T>(Result<List<T>> result) => result.when(
        success: (data, {stale = false}) => List<T>.of(data),
        failure: (_, __) => null,
        offline: (cached) => cached == null ? null : List<T>.of(cached),
      );

  static bool _isStale<T>(Result<T> result) => result.when(
        success: (_, {stale = false}) => stale,
        failure: (_, __) => false,
        offline: (_) => true,
      );
}
