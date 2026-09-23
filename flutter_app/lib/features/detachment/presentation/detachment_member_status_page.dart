import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/capability.dart';
import '../../../core/access/capability_guard.dart';
import '../../../core/format/app_date.dart';
import '../../../core/format/app_number.dart';
import '../../../core/format/app_time.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_result.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/forward_chevron.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../../shift/data/shift_providers.dart';
import '../../shift/domain/shift_models.dart';
import '../../shift/domain/shift_selectors.dart';
import '../../shift/presentation/shift_manage_sheet.dart';
import '../../team/data/team_providers.dart';
import '../data/detachment_providers.dart';
import '../../team/domain/team_models.dart';

/// One member's attendance history: where they stand right now, and a card
/// for every day they were put on a shift — check-in, check-out, present or
/// absent.
///
/// It reads the same [attendanceStatisticsProvider] the stats tab's
/// attendance section does, filtered to this one member, so a figure here can
/// never disagree with the roll-up two screens away. Viewing is open (the
/// roster card that opens it is); the edit affordance in the app bar is gated
/// on [Cap.memberEdit] and lands on the existing member form.
class DetachmentMemberStatusPage extends ConsumerStatefulWidget {
  const DetachmentMemberStatusPage({
    super.key,
    required this.detachmentId,
    required this.memberId,
  });

  final String detachmentId;
  final String memberId;

  @override
  ConsumerState<DetachmentMemberStatusPage> createState() =>
      _DetachmentMemberStatusPageState();
}

/// Windows offered for the history, mirroring the stats tab's ranges so the
/// two screens speak the same language.
enum _Range {
  week(7, S.rangeWeek),
  month(30, S.rangeMonth),
  quarter(90, S.rangeQuarter);

  const _Range(this.days, this.label);
  final int days;
  final String label;
}

class _DetachmentMemberStatusPageState
    extends ConsumerState<DetachmentMemberStatusPage> {
  _Range _range = _Range.month;

  String get detachmentId => widget.detachmentId;
  String get memberId => widget.memberId;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final onEdit = ref.accessIn(detachmentId).when(
          Cap.memberEdit,
          () => context.push('/detachment/$detachmentId/member/$memberId/edit'),
        );

    final today = dateOnly(DateTime.now());
    final query = AttendanceStatsQuery(
      detachmentId: detachmentId,
      from: addDays(today, -(_range.days - 1)),
      to: today,
      memberId: memberId,
    );

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text(S.memberStatusTitle),
        actions: [
          if (onEdit != null)
            IconButton(
              tooltip: S.editMember,
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
        children: [
          _MemberRecord(detachmentId: detachmentId, memberId: memberId),
          const SizedBox(height: AppSpacing.lg),
          _TodayAssignment(detachmentId: detachmentId, memberId: memberId),
          const SizedBox(height: AppSpacing.lg),
          Row(children: [
            for (final range in _Range.values) ...[
              Expanded(
                child: _RangeChip(
                  label: range.label,
                  selected: _range == range,
                  onTap: () => setState(() => _range = range),
                ),
              ),
              if (range != _Range.values.last)
                const SizedBox(width: AppSpacing.xs),
            ],
          ]),
          AsyncResultView<AttendanceStatistics>(
            value: ref.watch(attendanceStatisticsProvider(query)),
            onRetry: () => ref.invalidate(attendanceStatisticsProvider(query)),
            loading: const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            ),
            builder: (context, statistics, stale) => _History(
              range: _range,
              summary: _summaryFor(statistics, memberId),
            ),
          ),
        ],
      ),
    );
  }
}

/// The member's own record: identity, roster details, and contact.
///
/// A member deleted while this page is open is its own state rather than a
/// generic failure — the record is genuinely gone, so retrying it would only
/// fail again, and the only useful action is going back to the roster.
class _MemberRecord extends ConsumerWidget {
  const _MemberRecord({required this.detachmentId, required this.memberId});

  final String detachmentId;
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(memberByIdProvider(memberId));
    final result = value.valueOrNull;
    final removed = result != null &&
        result.when(
          success: (_, {stale = false}) => false,
          failure: (_, code) => code == 'not_found',
          offline: (_) => false,
        );

    if (removed) {
      return _MemberGone(
        key: const Key('member-removed'),
        onBack: () => context.pop(),
      );
    }

    return AsyncResultView<TeamMember>(
      value: value,
      onRetry: () => ref.invalidate(memberByIdProvider(memberId)),
      // Not `SkeletonList`: this sits inside the page's own ListView, and a
      // scrollable inside a scrollable has no bounded height to lay out in.
      loading: const _SectionSkeleton(height: 120),
      builder: (context, member, stale) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MemberHeader(member: member),
          const SizedBox(height: AppSpacing.md),
          _IdentityCard(member: member),
          const SizedBox(height: AppSpacing.md),
          _ContactCard(member: member, detachmentId: detachmentId),
        ],
      ),
    );
  }
}

class _MemberGone extends StatelessWidget {
  const _MemberGone({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.person_off_outlined,
        title: S.memberRemovedTitle,
        body: S.memberRemovedBody,
        actionLabel: S.memberBackToRoster,
        onAction: onBack,
      );
}

/// The roster fields that identify the member inside their detachment. Each
/// row is rendered only when the record actually carries it — a blank line
/// under a label says less than no line at all.
class _IdentityCard extends ConsumerWidget {
  const _IdentityCard({required this.member});

  final TeamMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The detachment this member belongs to, named rather than left as the id
    // in the route. Skipped entirely while it is still loading or could not
    // be read — a labelled blank line says less than no line.
    final detachmentName = ref
        .watch(detachmentByIdProvider(member.detachmentId))
        .valueOrNull
        ?.when(
          success: (data, {stale = false}) => data.name,
          failure: (_, __) => null,
          offline: (cached) => cached?.name,
        );

    final rows = <(IconData, String, String)>[
      if (detachmentName != null)
        (Icons.flag_outlined, S.memberDetachmentLabel, detachmentName),
      if (member.department.isNotEmpty)
        (Icons.category_outlined, S.memberDepartment, member.department),
      if (member.personalNumber.isNotEmpty)
        (
          Icons.badge_outlined,
          S.memberNumber,
          toArabicIndic(member.personalNumber)
        ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return _DetailCard(
      title: S.memberIdentitySection,
      children: [
        for (final (icon, label, value) in rows)
          _DetailRow(icon: icon, label: label, value: value),
      ],
    );
  }
}

/// Contact details, behind [Cap.memberContactView].
///
/// The capability exists precisely so a volunteer can see who is on their
/// shift without reading everyone's phone number, so a session without it is
/// told the data is withheld rather than being shown an empty card that looks
/// like missing data.
class _ContactCard extends ConsumerWidget {
  const _ContactCard({required this.member, required this.detachmentId});

  final TeamMember member;
  final String detachmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canSee = ref.capabilities.canIn(detachmentId, Cap.memberContactView);
    final phone = member.phoneMasked;

    return _DetailCard(
      key: const Key('member-contact'),
      title: S.memberContactSection,
      children: [
        if (!canSee)
          const _DetailNote(text: S.memberContactHidden)
        else if (phone == null || phone.isEmpty)
          const _DetailNote(text: S.memberNoPhone)
        else
          _DetailRow(
            icon: Icons.phone_outlined,
            label: S.memberPhone,
            value: phone,
            ltr: true,
          ),
      ],
    );
  }
}

/// Where this member stands on the schedule right now: the shift they are on,
/// or the next one they are assigned to.
///
/// Reads the detachment's own `todaysShiftsProvider` and narrows it to this
/// member — the Shifts module stays the source of truth, and tapping through
/// opens its existing management sheet rather than a member-side copy of it.
class _TodayAssignment extends ConsumerWidget {
  const _TodayAssignment({required this.detachmentId, required this.memberId});

  final String detachmentId;
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The management sheet is a set of writes, so it opens through
    // `DetachmentAccess`: on a finished detachment every one of these five
    // keys resolves false and the row stays a row.
    final access = ref.accessIn(detachmentId);
    final canOpen = access.canAny(const {
      Cap.shiftManage,
      Cap.shiftAssign,
      Cap.shiftDelete,
      Cap.shiftAttendanceRecord,
      Cap.shiftAttendanceOverride,
    });

    return AsyncResultView<List<Shift>>(
      value: ref.watch(todaysShiftsProvider(detachmentId)),
      onRetry: () => ref.invalidate(todaysShiftsProvider(detachmentId)),
      loading: const _SectionSkeleton(height: 72),
      builder: (context, shifts, stale) {
        final now = DateTime.now();
        final mine = [
          for (final shift in shifts)
            if (shift.attendees.any((a) => a.id == memberId)) shift,
        ];
        final shift = currentShiftOf(mine, now) ?? nextShiftOf(mine, now);

        return _DetailCard(
          key: const Key('member-today'),
          title: S.memberTodaySection,
          children: [
            if (shift == null)
              const _DetailNote(text: S.memberNoAssignmentToday)
            else
              _AssignmentRow(
                shift: shift,
                running: shift.isRunningNow,
                onOpen: canOpen
                    ? () => showShiftManageSheet(
                          context: context,
                          ref: ref,
                          shift: shift,
                          detachmentId: detachmentId,
                          canAssign: access.can(Cap.shiftAssign),
                          canRecord: access.can(Cap.shiftAttendanceRecord),
                          canOverride: access.can(Cap.shiftAttendanceOverride),
                          canManage: access.can(Cap.shiftManage),
                          canDelete: access.can(Cap.shiftDelete),
                        )
                    : null,
              ),
          ],
        );
      },
    );
  }
}

class _AssignmentRow extends StatelessWidget {
  const _AssignmentRow({
    required this.shift,
    required this.running,
    this.onOpen,
  });

  final Shift shift;
  final bool running;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final row = Row(children: [
      Icon(
        running ? Icons.play_circle_outline_rounded : Icons.upcoming_rounded,
        size: 18,
        color: running ? c.ok : c.ink2,
      ),
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              shift.centerName,
              style: TextStyle(
                color: c.ink,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              AppDate.minuteRange(shift.startMinutes, shift.endMinutes),
              style: AppTypography.digits(c.ink3, size: 12),
            ),
          ],
        ),
      ),
      if (onOpen != null) const ForwardChevron(size: 18),
    ]);

    if (onOpen == null) return row;
    return PressScale(
      key: const Key('member-open-shift'),
      onTap: onOpen,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: row,
    );
  }
}

/// A non-scrolling placeholder for one card-shaped section.
class _SectionSkeleton extends StatelessWidget {
  const _SectionSkeleton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) =>
      Skeleton(height: height, radius: AppRadii.lg);
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.eyebrow(c),
          ),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.ltr = false,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Phone numbers read left-to-right even inside an RTL page.
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, size: 16, color: c.ink3),
        const SizedBox(width: AppSpacing.sm),
        Text('$label:', style: TextStyle(color: c.ink3, fontSize: 12)),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: ltr
              ? Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      value,
                      style: AppTypography.digits(c.ink, size: 13),
                    ),
                  ),
                )
              : Text(
                  value,
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
      ]),
    );
  }
}

class _DetailNote extends StatelessWidget {
  const _DetailNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          text,
          style: TextStyle(color: context.c.ink3, fontSize: 12, height: 1.5),
        ),
      );
}

/// Identity plus the one live fact: their attendance state on the shift they
/// are on now, or the last one recorded.
class _MemberHeader extends StatelessWidget {
  const _MemberHeader({required this.member});

  final TeamMember member;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final kind = _attendanceKind(member.attendance);
    final (bg, fg) = _tint(context, kind);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Text(member.initials,
                  style: TextStyle(
                      color: fg, fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.name,
                      style: TextStyle(
                          color: c.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  _RoleChip(role: member.role),
                ],
              ),
            ),
          ]),
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            Text('${S.memberStatusCurrent}: ',
                style: TextStyle(color: c.ink3, fontSize: 12)),
            StatusChip(kind: kind, label: _attendanceLabel(member.attendance)),
          ]),
        ],
      ),
    );
  }

  static (Color, Color) _tint(BuildContext context, StatusKind kind) {
    final c = context.c;
    return switch (kind) {
      StatusKind.ok => (c.okTint, c.ok),
      StatusKind.warn => (c.warnTint, c.warn),
      StatusKind.crit => (c.critTint, c.crit),
      StatusKind.info => (c.infoTint, c.info),
      StatusKind.muted => (c.mutedTint, c.ink2),
    };
  }
}

/// Totals for the window, then one card per shift day, newest first.
class _History extends StatelessWidget {
  const _History({required this.range, required this.summary});

  final _Range range;
  final MemberAttendanceSummary? summary;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final records = summary?.records ?? const <AttendanceRecord>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _Metric(S.presentTotal, summary?.presentCount ?? 0),
            _Metric(S.absentTotal, summary?.absentCount ?? 0),
            _Metric(S.completedTotal, summary?.completedCount ?? 0),
            _Metric.percent(S.attendancePercent, _percent(summary)),
          ],
        ),
        const SectionHeader(title: S.memberAttendanceLog),
        if (records.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: Column(
              children: [
                Icon(Icons.event_busy_outlined, color: c.ink3, size: 26),
                const SizedBox(height: AppSpacing.sm),
                Text(S.noAttendanceRecords,
                    style: TextStyle(
                        color: c.ink2,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(S.noAttendanceRecordsSub,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.ink3, fontSize: 12)),
              ],
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(S.memberAttendanceLogSub,
                style: TextStyle(color: c.ink3, fontSize: 12)),
          ),
          for (int i = 0; i < records.length; i++) ...[
            Stagger(
              index: i,
              child: _DayCard(record: records[i]),
            ),
            if (i != records.length - 1) const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  static int _percent(MemberAttendanceSummary? s) {
    if (s == null) return 0;
    final reviewed = s.presentCount + s.absentCount;
    if (reviewed == 0) return 0;
    return ((s.presentCount / reviewed) * 100).round().clamp(0, 100);
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.record});

  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final kind = _attendanceKind(record.status);
    final present = record.isPresent;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppTime.weekdayDay(record.shiftDate),
                    style: TextStyle(
                        color: c.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(record.centerName,
                      style: TextStyle(color: c.ink3, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            StatusChip(kind: kind, label: _attendanceLabel(record.status)),
          ]),
          const SizedBox(height: AppSpacing.sm),
          if (present)
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                _TimePill(
                  label: S.checkInTime,
                  at: record.checkInAt,
                  color: c.ok,
                ),
                _TimePill(
                  label: S.checkOutTime,
                  at: record.checkOutAt,
                  color: record.checkOutAt == null ? c.ink3 : c.info,
                ),
              ],
            )
          else
            Text(S.notCheckedInShort,
                style: TextStyle(color: c.ink3, fontSize: 12)),
        ],
      ),
    );
  }
}

/// A label with a time. [AppTime] isolates the clock without changing the
/// direction of the surrounding Arabic row.
class _TimePill extends StatelessWidget {
  const _TimePill({required this.label, required this.at, required this.color});

  final String label;
  final DateTime? at;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label ', style: TextStyle(color: c.ink3, fontSize: 12)),
      Text(
        at == null ? '—' : AppTime.time(at!),
        style: AppTypography.digits(color, size: 13),
      ),
    ]);
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value) : percentage = false;
  const _Metric.percent(this.label, this.value) : percentage = true;

  final String label;
  final int value;
  final bool percentage;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: c.ink3, fontSize: 11)),
          const SizedBox(height: 2),
          Text(percentage ? AppNumber.percent(value) : AppNumber.count(value),
              style: AppTypography.digits(c.ink, size: 17)),
        ],
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.primaryTint : c.surface,
          border: Border.all(color: selected ? c.primary : c.line),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Text(label,
            style:
                TextStyle(color: selected ? c.primary : c.ink2, fontSize: 12)),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});

  final TeamRole role;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final label = switch (role) {
      TeamRole.shiftSupervisor => S.roleShiftSupervisor,
      TeamRole.administrator => S.roleAdministrator,
      TeamRole.followUp => S.roleFollowUp,
      TeamRole.member => S.roleMember,
    };
    final (bg, fg) = switch (role) {
      TeamRole.shiftSupervisor => (c.primaryTint, c.primary),
      TeamRole.administrator => (c.infoTint, c.info),
      TeamRole.followUp => (c.warnTint, c.warn),
      TeamRole.member => (c.mutedTint, c.ink2),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(AppRadii.pill)),
      child: Text(label,
          style:
              TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }
}

MemberAttendanceSummary? _summaryFor(
  AttendanceStatistics statistics,
  String memberId,
) {
  for (final member in statistics.members) {
    if (member.memberId == memberId) return member;
  }
  return null;
}

StatusKind _attendanceKind(AttendanceState s) => switch (s) {
      AttendanceState.checkedIn => StatusKind.ok,
      AttendanceState.checkedOut => StatusKind.info,
      AttendanceState.absent => StatusKind.crit,
      AttendanceState.notCheckedIn => StatusKind.muted,
    };

String _attendanceLabel(AttendanceState s) => switch (s) {
      AttendanceState.checkedIn => S.checkedIn,
      AttendanceState.checkedOut => S.checkedOut,
      AttendanceState.absent => S.absent,
      AttendanceState.notCheckedIn => S.notCheckedIn,
    };
