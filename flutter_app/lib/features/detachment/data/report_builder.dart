import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/app_date.dart';
import '../../../core/format/app_number.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../../../l10n/strings.dart';
import '../../inventory/data/inventory_providers.dart';
import '../../inventory/domain/inventory_format.dart';
import '../../inventory/domain/inventory_models.dart';
import '../../shift/data/shift_providers.dart';
import '../../shift/domain/shift_models.dart';
import '../../team/data/team_providers.dart';
import '../../team/domain/team_models.dart';
import '../../detachment_group/data/detachment_group_providers.dart';
import '../../detachment_group/domain/detachment_group_models.dart';
import '../domain/detachment_models.dart';
import '../domain/report_models.dart';
import 'detachment_providers.dart';

/// Cache key for a built report: which detachment, and exactly which choices.
class ReportQuery {
  const ReportQuery({required this.detachmentId, required this.spec});

  final String detachmentId;
  final ReportSpec spec;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReportQuery &&
          other.detachmentId == detachmentId &&
          other.spec == spec;

  @override
  int get hashCode => Object.hash(detachmentId, spec);
}

/// Builds the document from the same repositories the screens read.
///
/// Nothing here computes a figure of its own: a report that disagrees with
/// the screen it came from is worse than no report, so every number is the
/// one already on a tab, re-laid-out.
final reportProvider = FutureProvider.autoDispose
    .family<Result<ReportDocument>, ReportQuery>((ref, q) async {
  final id = q.detachmentId;
  final spec = q.spec;
  final now = ref.watch(clockProvider)();

  final detachmentResult =
      await ref.read(detachmentRepositoryProvider).byId(id);
  final detachment = _dataOf<Detachment>(detachmentResult);
  if (detachment == null) {
    return const Failure('لم يُعثر على المفرزة.', code: 'not_found');
  }

  final groupResult = await ref
      .read(detachmentGroupRepositoryProvider)
      .byId(detachment.detachmentGroupId);
  final detachmentGroupName = _dataOf<DetachmentGroup>(groupResult)?.name ?? '';

  final blocks = <ReportBlock>[];

  // ---- Summary -----------------------------------------------------------
  if (spec.has(ReportSection.summary)) {
    blocks.add(ReportFacts(S.secSummary, [
      (S.detachmentName, detachment.name),
      (S.detachmentGroup, detachmentGroupName),
      (S.detachmentRegion, detachment.region),
      (S.detachmentCenter, detachment.mainCenter),
      (S.memberCount, toArabicIndic('${detachment.memberCount}')),
      (S.coverage, AppNumber.percent(detachment.coveragePercent)),
      (
        S.status,
        detachment.status == DetachmentStatus.active
            ? S.statusActive
            : S.statusArchived
      ),
      (S.exportRange, spec.range.label),
    ]));
  }

  // ---- Members -----------------------------------------------------------
  if (spec.has(ReportSection.members)) {
    final roster = _dataOf<List<TeamMember>>(
            await ref.read(teamRepositoryProvider).listForDetachment(id)) ??
        const <TeamMember>[];
    blocks.add(ReportTable(
      S.secMembers,
      [
        S.memberName,
        S.memberDepartment,
        S.memberNumber,
        S.memberRole,
        S.attendanceProgress
      ],
      [
        for (final m in roster)
          [
            m.name,
            m.department,
            toArabicIndic(m.personalNumber),
            _roleLabel(m.role),
            _attendanceLabel(m.attendance),
          ],
      ],
    ));
  }

  // ---- Shifts ------------------------------------------------------------
  // The range decides how many weeks are walked. Whole weeks, because the
  // schedule is stored and read a week at a time.
  if (spec.has(ReportSection.shifts)) {
    final weeks = (spec.range.days / 7).ceil();
    final thisWeek = startOfWeek(DateTime.now());
    final rows = <List<String>>[];
    for (int w = weeks - 1; w >= 0; w--) {
      final weekStart = thisWeek.subtract(Duration(days: 7 * w));
      final shifts = _dataOf<List<Shift>>(await ref
              .read(shiftRepositoryProvider)
              .listForWeek(id, weekStart)) ??
          const <Shift>[];
      for (final s in shifts) {
        rows.add([
          AppDate.weekdayOf(s.date),
          AppDate.dayMonth(s.date),
          AppDate.minuteRange(s.startMinutes, s.endMinutes),
          s.centerName,
          toArabicIndic('${s.assigned}'),
          toArabicIndic('${s.needed}'),
          toArabicIndic('${s.gap}'),
        ]);
      }
    }
    blocks.add(ReportTable(
      S.secShifts,
      [
        S.weekOf,
        S.workshopDate,
        S.shiftPeriod,
        S.shiftCenter,
        S.assignedLabel,
        S.shiftNeeded,
        S.coverageGap,
      ],
      rows,
    ));
  }

  // ---- Storage -----------------------------------------------------------
  final wantsStock =
      spec.has(ReportSection.storage) || spec.has(ReportSection.storageLow);
  if (wantsStock) {
    final items = _dataOf<List<InventoryItem>>(await ref
            .read(inventoryRepositoryProvider)
            .listForDetachment(id)) ??
        const <InventoryItem>[];

    List<List<String>> tableOf(Iterable<InventoryItem> source) => [
          for (final i in source)
            [
              i.name,
              stockBreakdownLabel(i),
              toArabicIndic('${i.unitsPerStrip}'),
              toArabicIndic('${i.minimum}'),
              i.expiresOn == null ? S.noExpiry : AppDate.dayMonth(i.expiresOn!),
              _levelLabel(i.level),
            ],
        ];
    const columns = [
      S.itemName,
      S.currentStock,
      S.unitsPerStrip,
      S.minimumLevel,
      S.expiresOn,
      S.status,
    ];

    if (spec.has(ReportSection.storage)) {
      blocks.add(ReportTable(S.secStorage, columns, tableOf(items)));
    }
    if (spec.has(ReportSection.storageLow)) {
      blocks.add(ReportTable(
        S.secStorageLow,
        columns,
        tableOf(items.where((i) => i.level != StockLevel.ok)),
      ));
    }
  }

  // ---- Attendance --------------------------------------------------------
  if (spec.has(ReportSection.attendance)) {
    final today = dateOnly(now);
    final from = addDays(today, -(spec.range.days - 1));
    final shifts = _dataOf<List<Shift>>(
          await ref.read(shiftRepositoryProvider).listForRange(id, from, today),
        ) ??
        const <Shift>[];
    final attendance = AttendanceStatistics.fromShifts(shifts);
    blocks.add(ReportFacts(S.secAttendance, [
      (S.presentTotal, toArabicIndic('${attendance.presentCount}')),
      (S.absentTotal, toArabicIndic('${attendance.absentCount}')),
      (S.completedTotal, toArabicIndic('${attendance.completedCount}')),
      (S.pendingTotal, toArabicIndic('${attendance.pendingCount}')),
      (S.attendancePercent, AppNumber.percent(attendance.attendancePercent)),
    ]));

    // The legacy report's first table was one row per **active roster
    // member**, including anyone with no reviewed day at all (its query left
    // joined attendance onto the roster). Reproduced here by walking the
    // roster and looking each member's summary up, rather than by walking
    // only the members who happen to appear on a shift.
    final attendanceRoster = _dataOf<List<TeamMember>>(
            await ref.read(teamRepositoryProvider).listForDetachment(id)) ??
        const <TeamMember>[];
    final summaryById = {
      for (final member in attendance.members) member.memberId: member,
    };
    final summaryOrder = <MemberAttendanceSummary?>[
      for (final member in attendanceRoster) summaryById.remove(member.id),
    ];
    blocks.add(ReportTable(
      S.attendanceSummary,
      [
        S.memberName,
        S.memberRole,
        S.memberDepartment,
        S.presentTotal,
        S.absentTotal,
        S.completedTotal,
      ],
      [
        for (final (index, summary) in summaryOrder.indexed)
          [
            attendanceRoster[index].name,
            _roleLabel(attendanceRoster[index].role),
            attendanceRoster[index].department,
            toArabicIndic('${summary?.presentCount ?? 0}'),
            toArabicIndic('${summary?.absentCount ?? 0}'),
            toArabicIndic('${summary?.completedCount ?? 0}'),
          ],
        // Anyone who worked a shift inside the range but is no longer on the
        // roster still has to be accounted for; dropping them would make the
        // totals above disagree with the table under them.
        for (final summary in summaryById.values)
          [
            summary.memberName,
            _roleLabel(summary.role),
            '',
            toArabicIndic('${summary.presentCount}'),
            toArabicIndic('${summary.absentCount}'),
            toArabicIndic('${summary.completedCount}'),
          ],
      ],
    ));

    for (final member in attendance.members) {
      blocks.add(ReportTable(
        '${member.memberName} · ${_roleLabel(member.role)}',
        [
          S.attendanceDate,
          S.status,
          S.checkInTime,
          S.checkOutTime,
        ],
        [
          // Oldest first, as the legacy history table printed it.
          for (final record in member.recordsOldestFirst)
            [
              AppDate.dayMonth(record.shiftDate),
              _attendanceLabel(record.status),
              record.checkInAt == null
                  ? '—'
                  : AppDate.dayMonthTime(record.checkInAt!),
              record.checkOutAt == null
                  ? '—'
                  : AppDate.dayMonthTime(record.checkOutAt!),
            ],
        ],
      ));
    }
    // Only the days that actually have a reviewed record. Walking the whole
    // range instead would print a row of "0٪" for every day the detachment
    // ran no shift — over a quarter that is most of the section, and it reads
    // as ninety days of failure rather than as no data.
    final labels = <String>[];
    final values = <int>[];
    for (var offset = 0; offset < spec.range.days; offset++) {
      final day = addDays(from, offset);
      final reviewed = attendance.records
          .where((record) =>
              dateOnly(record.shiftDate) == day &&
              (record.isPresent || record.isAbsent))
          .toList();
      if (reviewed.isEmpty) continue;
      final present = reviewed.where((record) => record.isPresent).length;
      labels.add(AppDate.dayMonth(day));
      values.add(((present / reviewed.length) * 100).round());
    }
    if (values.isNotEmpty) {
      blocks.add(ReportSeries(
        S.attendancePercent,
        labels,
        values,
        suffix: S.percentSign,
      ));
    }
  }

  // ---- Series ------------------------------------------------------------
  final wantsSeries =
      spec.has(ReportSection.coverage) || spec.has(ReportSection.consumption);
  if (wantsSeries) {
    final stats = _dataOf<DetachmentStats>(
        await ref.read(detachmentRepositoryProvider).stats(id));
    if (stats != null) {
      // The mock keeps seven days of history. A longer range is honoured by
      // labelling what is actually there rather than by inventing the rest —
      // a report that pads itself is a report nobody can trust.
      final labels = _dayLabels(stats.attendanceSeries.length);
      if (spec.has(ReportSection.coverage)) {
        blocks.add(ReportSeries(S.secCoverage, labels, stats.coverageSeries,
            suffix: S.percentSign));
      }
      if (spec.has(ReportSection.consumption)) {
        blocks.add(ReportSeries(S.secConsumption, labels, stats.stockSeries));
      }
    }
  }

  return Success(ReportDocument(
    detachmentName: detachment.name,
    detachmentGroupName: detachmentGroupName,
    generatedAt: now,
    range: spec.range,
    blocks: blocks,
  ));
});

/// The last [count] days ending today, oldest first.
List<String> _dayLabels(int count) {
  final today = dateOnly(DateTime.now());
  return [
    for (int i = count - 1; i >= 0; i--) AppDate.dayMonth(addDays(today, -i)),
  ];
}

T? _dataOf<T>(Result<T> result) => result.when(
      success: (data, {stale = false}) => data,
      failure: (_, __) => null,
      offline: (cached) => cached,
    );

String _roleLabel(TeamRole role) => switch (role) {
      TeamRole.shiftSupervisor => S.roleShiftSupervisor,
      TeamRole.administrator => S.roleAdministrator,
      TeamRole.followUp => S.roleFollowUp,
      TeamRole.member => S.roleMember,
    };

String _attendanceLabel(AttendanceState state) => switch (state) {
      AttendanceState.checkedIn => S.checkedIn,
      AttendanceState.checkedOut => S.checkedOut,
      AttendanceState.absent => S.absent,
      AttendanceState.notCheckedIn => S.notCheckedIn,
    };

String _levelLabel(StockLevel level) => switch (level) {
      StockLevel.ok => S.stockOk,
      StockLevel.low => S.stockLowLabel,
      StockLevel.empty => S.stockEmpty,
    };
