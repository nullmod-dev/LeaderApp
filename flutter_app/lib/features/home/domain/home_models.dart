import '../../detachment/domain/storage_status.dart';
import '../../shift/domain/shift_models.dart';

/// Today's operational snapshot for **one** detachment — the shape the Home
/// dashboard renders.
///
/// Every figure here is a projection of records that already exist in another
/// repository (the detachment, its schedule, its store), never a number
/// invented for the dashboard. `MockHomeRepository` composes them exactly the
/// way a real backend would join its own tables, so a count on this screen
/// cannot disagree with the tab it links to.
///
/// **Which detachment.** One at a time, per `DETACHMENT-SCOPING.md` §4 — the
/// summary is fetched for the active detachment and carries its id, so every
/// card on the dashboard has a real record to open.
class HomeSummary {
  const HomeSummary({
    required this.detachmentId,
    required this.detachmentName,
    required this.region,
    required this.mainCenter,
    required this.shifts,
    required this.rosterCount,
    required this.storageStatus,
    required this.lowStockCount,
    required this.expiringSoonCount,
  });

  final String detachmentId;
  final String detachmentName;
  final String region;
  final String mainCenter;

  /// Yesterday, today, and tomorrow's shifts, ordered by start time.
  ///
  /// Three days rather than one because "now" and "next" are questions about
  /// the clock, not about the calendar: a 20:00–02:00 shift started yesterday
  /// is still running at 01:00 today, and when today's last shift has ended
  /// the next one the user cares about is tomorrow's first. The selectors in
  /// `today_selectors.dart` resolve both from real timestamps.
  final List<Shift> shifts;

  final int rosterCount;

  /// The same fold the detachment detail's storage strip shows, so the two
  /// verdicts cannot disagree.
  final StorageStatus storageStatus;

  /// Items at or below their minimum, including the ones that ran out.
  final int lowStockCount;

  /// Items inside [storageExpiringWithinDays] of their expiry date.
  final int expiringSoonCount;

  factory HomeSummary.fromJson(Map<String, dynamic> j) => HomeSummary(
        detachmentId: j['detachmentId'] as String,
        detachmentName: j['detachmentName'] as String,
        region: (j['region'] as String?) ?? '',
        mainCenter: (j['mainCenter'] as String?) ?? '',
        shifts: ((j['shifts'] as List?) ?? const [])
            .map((e) => Shift.fromJson(e as Map<String, dynamic>))
            .toList(),
        rosterCount: (j['rosterCount'] as int?) ?? 0,
        storageStatus: StorageStatus.values.firstWhere(
          (s) => s.name == j['storageStatus'],
          orElse: () => StorageStatus.empty,
        ),
        lowStockCount: (j['lowStockCount'] as int?) ?? 0,
        expiringSoonCount: (j['expiringSoonCount'] as int?) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'detachmentId': detachmentId,
        'detachmentName': detachmentName,
        'region': region,
        'mainCenter': mainCenter,
        'shifts': [for (final s in shifts) s.toJson()],
        'rosterCount': rosterCount,
        'storageStatus': storageStatus.name,
        'lowStockCount': lowStockCount,
        'expiringSoonCount': expiringSoonCount,
      };
}
