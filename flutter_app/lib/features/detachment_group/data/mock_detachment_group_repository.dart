import 'dart:math';

import '../../../core/result/result.dart';
import '../../detachment/domain/detachment_models.dart';
import '../../detachment/domain/detachment_repository.dart';
import '../domain/detachment_group_models.dart';
import '../domain/detachment_group_repository.dart';

/// In-memory detachment groups.
///
/// It reads the detachments through [DetachmentRepository] rather than keeping
/// its own copy of the counts, so the number on a detachment group card and the
/// list of detachments behind it are the same fact read twice — the same
/// arrangement `MockShiftRepository` uses for the roster.
class MockDetachmentGroupRepository implements DetachmentGroupRepository {
  MockDetachmentGroupRepository(this._detachments, {List<DetachmentGroup>? groups})
      : _seed = List.of(groups ?? _defaultSeed());

  final DetachmentRepository _detachments;
  final _rand = Random(51);

  final List<DetachmentGroup> _seed;

  static List<DetachmentGroup> _defaultSeed() => [
    DetachmentGroup(
      id: 't_damascus',
      name: 'الهلال الأحمر — فرع دمشق',
      createdAt: DateTime(2024, 3, 12),
      notes: 'يضم مفرزات المدينة وريفها.',
    ),
    DetachmentGroup(
      id: 't_central',
      name: 'فرق الوسط التطوعية',
      createdAt: DateTime(2024, 9, 2),
      notes: 'حمص وما حولها.',
    ),
    DetachmentGroup(
      id: 't_coast',
      name: 'تجمّع الساحل الإسعافي',
      createdAt: DateTime(2025, 1, 20),
    ),
  ];

  Future<void> _latency() => Future<void>.delayed(
        Duration(milliseconds: 200 + _rand.nextInt(240)),
      );

  /// Every detachment, grouped by detachment group, in one read.
  ///
  /// One call for the whole list rather than one per detachment group: the
  /// counts are derived, and deriving them must not cost a round trip per row.
  Future<Map<String, List<Detachment>>> _byGroup() async {
    final result = await _detachments.list();
    final all = result.when(
      success: (data, {stale = false}) => data,
      failure: (_, __) => const <Detachment>[],
      offline: (cached) => cached ?? const <Detachment>[],
    );
    final grouped = <String, List<Detachment>>{};
    for (final d in all) {
      grouped.putIfAbsent(d.detachmentGroupId, () => []).add(d);
    }
    return grouped;
  }

  /// Rolls the detachment figures up onto a detachment group. An archived
  /// detachment still counts as belonging to the detachment group, but
  /// contributes no coverage — averaging a dormant zero into a live number
  /// would read as a failure.
  DetachmentGroup _withCounts(DetachmentGroup t, List<Detachment> all) {
    final live = all.where((d) => d.status == DetachmentStatus.active).toList();
    final coverage = live.isEmpty
        ? 0
        : (live.fold<int>(0, (sum, d) => sum + d.coveragePercent) / live.length)
            .round();
    return t.copyWith(
      detachmentCount: all.length,
      memberCount: all.fold<int>(0, (sum, d) => sum + d.memberCount),
      coveragePercent: coverage,
    );
  }

  @override
  Future<Result<List<DetachmentGroup>>> list({String? query}) async {
    await _latency();
    Iterable<DetachmentGroup> out = _seed;
    if (query != null && query.trim().isNotEmpty) {
      final q = query.trim();
      out = out.where(
        (t) => t.name.contains(q) || (t.notes?.contains(q) ?? false),
      );
    }
    final grouped = await _byGroup();
    return Success([
      for (final t in out) _withCounts(t, grouped[t.id] ?? const []),
    ]);
  }

  @override
  Future<Result<DetachmentGroup>> byId(String id) async {
    await _latency();
    final i = _seed.indexWhere((t) => t.id == id);
    if (i < 0) return const Failure('لم يُعثر على الجهة.', code: 'not_found');
    final grouped = await _byGroup();
    return Success(_withCounts(_seed[i], grouped[id] ?? const []));
  }

  @override
  Future<Result<DetachmentGroup>> create(
      {required String name, String? notes}) async {
    await _latency();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const Failure('اسم الجهة مطلوب.', code: 'validation');
    }
    if (_seed.any((t) => t.name == trimmed)) {
      return const Failure('توجد جهة بهذا الاسم.', code: 'conflict');
    }
    final t = DetachmentGroup(
      id: 't_${DateTime.now().millisecondsSinceEpoch}',
      name: trimmed,
      createdAt: DateTime.now(),
      notes: (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
    );
    _seed.add(t);
    return Success(t);
  }

  @override
  Future<Result<DetachmentGroup>> update(DetachmentGroup group) async {
    await _latency();
    final i = _seed.indexWhere((t) => t.id == group.id);
    if (i < 0) return const Failure('لم يُعثر على الجهة.', code: 'not_found');
    if (group.name.trim().isEmpty) {
      return const Failure('اسم الجهة مطلوب.', code: 'validation');
    }
    if (_seed.any((t) => t.id != group.id && t.name == group.name.trim())) {
      return const Failure('توجد جهة بهذا الاسم.', code: 'conflict');
    }
    _seed[i] = group;
    return Success(group);
  }

  @override
  Future<Result<void>> delete(String id) async {
    await _latency();
    final i = _seed.indexWhere((t) => t.id == id);
    if (i < 0) return const Failure('لم يُعثر على الجهة.', code: 'not_found');
    // Cascade before removing the parent, so a failure part-way through leaves
    // the detachment group in place rather than orphaning its detachments.
    final cascade = await _detachments.deleteAllInGroup(id);
    if (cascade.isFailure) {
      return const Failure('تعذّر حذف مفرزات الجهة.', code: 'conflict');
    }
    _seed.removeAt(i);
    return const Success(null);
  }
}
