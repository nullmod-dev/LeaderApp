import 'dart:math';

import '../../../core/result/result.dart';
import '../domain/detachment_models.dart';
import '../domain/detachment_repository.dart';

/// In-memory detachment data. Nothing in this file touches the network.
///
/// `memberCount` matches the roster seeded in `MockTeamRepository` for the
/// same id, so the list card and the Members tab never disagree.
class MockDetachmentRepository implements DetachmentRepository {
  /// [detachments] replaces the seed — the Customer Demo workspace passes its
  /// own two.
  MockDetachmentRepository({List<Detachment>? detachments})
      : _seed = List.of(detachments ?? _defaultSeed());

  final _rand = Random(11);

  final List<Detachment> _seed;

  static List<Detachment> _defaultSeed() => [
    const Detachment(
      id: 'd_dam_central',
      detachmentGroupId: 't_damascus',
      name: 'مفرزة دمشق المركزية',
      region: 'دمشق',
      mainCenter: 'مركز الشعلان',
      memberCount: 10,
      weeklyShiftCount: 21,
      coveragePercent: 92,
      status: DetachmentStatus.active,
      notes: 'أعلى تغطية في الأسبوعين الماضيين.',
    ),
    const Detachment(
      id: 'd_dam_rural',
      detachmentGroupId: 't_damascus',
      name: 'مفرزة ريف دمشق',
      region: 'ريف دمشق',
      mainCenter: 'مركز داريا',
      memberCount: 6,
      weeklyShiftCount: 15,
      coveragePercent: 78,
      status: DetachmentStatus.active,
      notes: 'نقص متكرر في الوردية المسائية.',
    ),
    const Detachment(
      id: 'd_homs',
      detachmentGroupId: 't_central',
      name: 'مفرزة حمص',
      region: 'حمص',
      mainCenter: 'مركز الوعر',
      memberCount: 5,
      weeklyShiftCount: 10,
      coveragePercent: 84,
      status: DetachmentStatus.active,
    ),
    const Detachment(
      id: 'd_coast',
      detachmentGroupId: 't_coast',
      name: 'مفرزة الساحل',
      region: 'اللاذقية',
      mainCenter: 'مركز اللاذقية',
      memberCount: 4,
      weeklyShiftCount: 12,
      coveragePercent: 88,
      status: DetachmentStatus.active,
    ),
    const Detachment(
      id: 'd_north_arch',
      detachmentGroupId: 't_central',
      name: 'مفرزة الشمال — مؤرشفة',
      region: 'حلب',
      mainCenter: 'مركز الأشرفية',
      // The roster it ended with, and no shifts *this* week — it has none,
      // which is what being finished means. Its last worked week is three
      // weeks back, seeded in `MockShiftRepository`.
      memberCount: 4,
      weeklyShiftCount: 0,
      coveragePercent: 0,
      status: DetachmentStatus.archived,
      notes: 'أُرشفت بعد دمج نشاطها مع مفرزة حمص.',
    ),
  ];

  /// Seven days of history per detachment, oldest first. Distinct per id so a
  /// screen that renders another detachment's numbers is visible immediately.
  static const Map<String, DetachmentStats> _stats = {
    'd_dam_central': DetachmentStats(
      attendanceSeries: [72, 78, 81, 88, 84, 92, 90],
      coverageSeries: [70, 74, 78, 82, 86, 90, 92],
      stockSeries: [12, 18, 9, 22, 15, 30, 24],
    ),
    'd_dam_rural': DetachmentStats(
      attendanceSeries: [61, 58, 66, 70, 64, 72, 75],
      coverageSeries: [58, 62, 61, 70, 74, 76, 78],
      stockSeries: [8, 6, 11, 7, 14, 9, 12],
    ),
    'd_homs': DetachmentStats(
      attendanceSeries: [80, 82, 79, 85, 88, 86, 84],
      coverageSeries: [76, 78, 80, 79, 83, 85, 84],
      stockSeries: [5, 9, 4, 6, 10, 7, 8],
    ),
    'd_coast': DetachmentStats(
      attendanceSeries: [88, 90, 86, 91, 89, 93, 88],
      coverageSeries: [82, 84, 85, 87, 88, 90, 88],
      stockSeries: [3, 7, 5, 9, 6, 11, 10],
    ),
    'd_north_arch': DetachmentStats(
      attendanceSeries: [0, 0, 0, 0, 0, 0, 0],
      coverageSeries: [0, 0, 0, 0, 0, 0, 0],
      stockSeries: [0, 0, 0, 0, 0, 0, 0],
    ),
  };

  // Records change rarely, so this list reads faster than the live ones.
  Future<void> _latency() => Future<void>.delayed(
        Duration(milliseconds: 220 + _rand.nextInt(280)),
      );

  @override
  Future<Result<List<Detachment>>> list({
    String? detachmentGroupId,
    DetachmentStatus? filter,
    String? query,
  }) async {
    await _latency();
    Iterable<Detachment> out = _seed;
    if (detachmentGroupId != null) {
      out = out.where((d) => d.detachmentGroupId == detachmentGroupId);
    }
    if (filter != null) out = out.where((d) => d.status == filter);
    if (query != null && query.trim().isNotEmpty) {
      final q = query.trim();
      out = out.where((d) =>
          d.name.contains(q) ||
          d.mainCenter.contains(q) ||
          d.region.contains(q));
    }
    return Success(out.toList());
  }

  @override
  Future<Result<Detachment>> byId(String id) async {
    await _latency();
    final i = _seed.indexWhere((e) => e.id == id);
    // An unknown id is a failure, never a fallback record. Returning
    // `_seed.first` here used to hand the caller another detachment's data.
    if (i < 0) return const Failure('لم يُعثر على المفرزة.', code: 'not_found');
    return Success(_seed[i]);
  }

  @override
  Future<Result<Detachment>> create({
    required String detachmentGroupId,
    required String name,
    required String region,
    required String mainCenter,
    String? notes,
  }) async {
    await _latency();
    final d = Detachment(
      id: 'd_${DateTime.now().millisecondsSinceEpoch}',
      detachmentGroupId: detachmentGroupId,
      name: name,
      region: region,
      mainCenter: mainCenter,
      memberCount: 0,
      weeklyShiftCount: 0,
      coveragePercent: 0,
      status: DetachmentStatus.active,
      notes: notes,
    );
    _seed.add(d);
    return Success(d);
  }

  @override
  Future<Result<Detachment>> update(Detachment d) async {
    await _latency();
    final i = _seed.indexWhere((e) => e.id == d.id);
    if (i < 0) return const Failure('لم يُعثر على المفرزة.', code: 'not_found');
    _seed[i] = d;
    return Success(d);
  }

  @override
  Future<Result<void>> delete(String id) async {
    await _latency();
    final i = _seed.indexWhere((e) => e.id == id);
    if (i < 0) return const Failure('لم يُعثر على المفرزة.', code: 'not_found');
    _seed.removeAt(i);
    // The roster, the schedule, and the stock are keyed by detachment id and
    // every one of their reads filters on it, so removing the container is
    // what makes them unreachable. Nothing else has to be swept.
    _runtimeStats.remove(id);
    return const Success(null);
  }

  @override
  Future<Result<int>> deleteAllInGroup(String detachmentGroupId) async {
    await _latency();
    final doomed =
        _seed.where((d) => d.detachmentGroupId == detachmentGroupId).toList();
    for (final d in doomed) {
      _seed.remove(d);
      _runtimeStats.remove(d.id);
    }
    return Success(doomed.length);
  }

  /// Series for detachments created at runtime. A brand-new detachment has no
  /// history, so it gets a flat week rather than another detachment's numbers.
  final Map<String, DetachmentStats> _runtimeStats = {};

  @override
  Future<Result<DetachmentStats>> stats(String id) async {
    await _latency();
    final s = _stats[id] ?? _runtimeStats[id];
    if (s != null) return Success(s);
    if (!_seed.any((d) => d.id == id)) {
      return const Failure('لا إحصائيات لهذه المفرزة.', code: 'not_found');
    }
    const flat = DetachmentStats(
      attendanceSeries: [0, 0, 0, 0, 0, 0, 0],
      coverageSeries: [0, 0, 0, 0, 0, 0, 0],
      stockSeries: [0, 0, 0, 0, 0, 0, 0],
    );
    _runtimeStats[id] = flat;
    return const Success(flat);
  }
}
