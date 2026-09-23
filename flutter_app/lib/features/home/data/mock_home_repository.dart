import '../../../core/result/result.dart';
import '../../detachment/domain/detachment_repository.dart';
import '../../detachment/domain/storage_status.dart';
import '../../inventory/domain/inventory_models.dart';
import '../../inventory/domain/inventory_repository.dart';
import '../../shift/domain/shift_models.dart';
import '../../team/domain/team_repository.dart';
import '../domain/home_models.dart';
import '../domain/home_repository.dart';
import '../../shift/domain/shift_repository.dart';

/// Builds the dashboard snapshot by joining the repositories that already own
/// the data — the same thing a real backend does behind
/// `GET /api/v1/home/summary`.
///
/// It composes rather than seeds (the pattern `MockShiftRepository` already
/// uses for the roster) and that is the point: the earlier version of this
/// class returned its own hard-coded detachment name, shift, and decision
/// list, so the dashboard showed figures that existed nowhere else in the app
/// and carried no id anything could be opened by. Every number below is now
/// read from the same mock the tab it links to reads from.
class MockHomeRepository implements HomeRepository {
  MockHomeRepository({
    required DetachmentRepository detachments,
    required ShiftRepository shifts,
    InventoryRepository? inventory,
    required TeamRepository team,
  })  : _detachments = detachments,
        _shifts = shifts,
        _inventory = inventory,
        _team = team;

  final DetachmentRepository _detachments;
  final ShiftRepository _shifts;
  final InventoryRepository? _inventory;
  final TeamRepository _team;

  @override
  Future<Result<HomeSummary>> summary(String detachmentId) async {
    final detachment = await _detachments.byId(detachmentId);
    // A detachment that cannot be read is the whole screen's failure — the
    // dashboard has nothing to be *about* without it. Its sections degrade
    // individually below.
    final record = detachment.when(
      success: (data, {stale = false}) => data,
      failure: (_, __) => null,
      offline: (cached) => cached,
    );
    if (record == null) {
      return detachment.when(
        success: (_, {stale = false}) => const Failure(
          'تعذّر تحميل بيانات المفرزة.',
          code: 'not_found',
        ),
        failure: (message, code) => Failure(message, code: code),
        offline: (_) => const Offline(),
      );
    }

    final now = DateTime.now();
    final today = dateOnly(now);
    final shifts = await _shifts.listForRange(
      detachmentId,
      today.subtract(const Duration(days: 1)),
      today.add(const Duration(days: 1)),
    );
    final items = _inventory == null
        ? const Success<List<InventoryItem>>([])
        : await _inventory.listForDetachment(detachmentId);
    final roster = await _team.listForDetachment(detachmentId);

    final shiftList = _dataOr(shifts, const <Shift>[])..sort(_byStart);
    final itemList = _dataOr(items, const <InventoryItem>[]);

    return Success(HomeSummary(
      detachmentId: record.id,
      detachmentName: record.name,
      region: record.region,
      mainCenter: record.mainCenter,
      shifts: shiftList,
      rosterCount: _dataOr(roster, const []).length,
      storageStatus: storageStatusOf(itemList),
      lowStockCount: itemList.where((i) => i.level != StockLevel.ok).length,
      expiringSoonCount: itemList.where((i) {
        final days = i.daysToExpiry;
        return days != null && days <= storageExpiringWithinDays;
      }).length,
    ));
  }

  /// A section that failed degrades to "nothing known" rather than taking the
  /// screen down with it: the schedule still renders when the store is
  /// unreachable, and `today_selectors.dart` raises no alert for a section it
  /// has no records for.
  static List<T> _dataOr<T>(Result<List<T>> result, List<T> fallback) =>
      result.when(
        success: (data, {stale = false}) => List<T>.of(data),
        failure: (_, __) => List<T>.of(fallback),
        offline: (cached) => List<T>.of(cached ?? fallback),
      );

  static int _byStart(Shift a, Shift b) => a.start.compareTo(b.start);
}
