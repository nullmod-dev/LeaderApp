import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/app_number.dart';
import '../../../core/format/app_time.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/widgets/app_meta.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../../team/domain/team_models.dart';
import '../data/shift_providers.dart';
import '../domain/shift_models.dart';
import 'shift_assign_sheet.dart';
import 'shift_edit_sheet.dart';

/// Everything you can do to **one** shift, opened by tapping its card.
///
/// The card is a summary; this is where the work happens. Nothing here is new
/// behaviour — assign (both methods), quick-fill, the full attendee list with
/// per-member attendance / check-in / check-out, edit and delete are the same
/// operations the card used to carry inline, gathered onto the surface they
/// belong to and each still gated by the same capability.
Future<void> showShiftManageSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Shift shift,
  required String detachmentId,
  required bool canAssign,
  required bool canRecord,
  required bool canOverride,
  required bool canManage,
  required bool canDelete,
}) async {
  await showAppSheet<void>(
    context: context,
    title: '${S.manageShiftTitle} · ${shift.centerName}',
    expanded: true,
    child: _ManageBody(
      shift: shift,
      detachmentId: detachmentId,
      canAssign: canAssign,
      canRecord: canRecord,
      canOverride: canOverride,
      canManage: canManage,
      canDelete: canDelete,
    ),
  );
}

class _ManageBody extends ConsumerStatefulWidget {
  const _ManageBody({
    required this.shift,
    required this.detachmentId,
    required this.canAssign,
    required this.canRecord,
    required this.canOverride,
    required this.canManage,
    required this.canDelete,
  });

  final Shift shift;
  final String detachmentId;
  final bool canAssign;
  final bool canRecord;
  final bool canOverride;
  final bool canManage;
  final bool canDelete;

  @override
  ConsumerState<_ManageBody> createState() => _ManageBodyState();
}

class _ManageBodyState extends ConsumerState<_ManageBody> {
  bool _busy = false;

  void _refresh() {
    ref.invalidate(weekShiftsProvider);
    ref.invalidate(todaysShiftsProvider);
    ref.invalidate(shiftByIdProvider(widget.shift.id));
    ref.invalidate(shiftCandidatesProvider(widget.shift.id));
    ref.invalidate(attendanceStatisticsProvider);
  }

  @override
  Widget build(BuildContext context) {
    // Stay live: an assign or an attendance edit done from a nested sheet
    // shows up here the moment that sheet closes.
    final async = ref.watch(shiftByIdProvider(widget.shift.id));
    final shift = async.maybeWhen(
      data: (r) => r.when(
        success: (s, {stale = false}) => s,
        failure: (_, __) => widget.shift,
        offline: (cached) => cached ?? widget.shift,
      ),
      orElse: () => widget.shift,
    );

    final c = context.c;
    final running = shift.isRunningNow;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
      children: [
        // ---- summary ---------------------------------------------------
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: running ? c.primary : c.line),
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
                      AppMeta(
                        parts: [
                          AppMetaText(AppTime.weekdayDay(shift.date)),
                          AppMetaText(
                            AppTime.minuteRange(
                              shift.startMinutes,
                              shift.endMinutes,
                            ),
                            emphasis: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                StatusChip(
                  kind: running
                      ? StatusKind.info
                      : shift.hasCoverageGap
                          ? StatusKind.warn
                          : StatusKind.ok,
                  label: running
                      ? S.now
                      : shift.hasCoverageGap
                          ? '${S.coverageGap} ${AppNumber.count(shift.gap)}'
                          : S.shiftCoverageOk,
                ),
              ]),
              const SizedBox(height: AppSpacing.md),
              _CoverageBar(shift: shift),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // ---- actions --------------------------------------------------
        if (widget.canAssign)
          _ActionButton(
            icon: Icons.person_add_alt_1_rounded,
            label: S.assignVolunteer,
            onTap: _busy ? null : () => _assign(shift),
          ),
        if (widget.canAssign && shift.hasCoverageGap) ...[
          const SizedBox(height: AppSpacing.sm),
          _ActionButton(
            icon: Icons.bolt_rounded,
            label: S.quickFill,
            filled: false,
            onTap: _busy ? null : () => _quickFill(shift),
          ),
        ],
        if (widget.canManage) ...[
          const SizedBox(height: AppSpacing.sm),
          _ActionButton(
            icon: Icons.edit_outlined,
            label: S.editShift,
            filled: false,
            onTap: _busy ? null : () => _edit(shift),
          ),
        ],
        if (widget.canDelete) ...[
          const SizedBox(height: AppSpacing.sm),
          _ActionButton(
            icon: Icons.delete_outline_rounded,
            label: S.deleteShift,
            filled: false,
            tone: c.crit,
            onTap: _busy ? null : () => _confirmDelete(shift),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),

        // ---- attendees ----------------------------------------------
        Row(children: [
          Text(S.shiftMembersSection,
              style: TextStyle(
                  color: c.ink2, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Text(
            AppNumber.ratio(shift.assigned, shift.needed),
            style: AppTypography.digits(c.ink3, size: 13),
          ),
        ]),
        const SizedBox(height: AppSpacing.sm),
        if (shift.attendees.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text(S.shiftNoAttendees,
                style: TextStyle(color: c.ink3, fontSize: 12)),
          )
        else
          for (final a in shift.attendees) ...[
            AttendeeRow(
              member: a,
              // Reachable with either capability: a record-only session opens
              // it while the window is open, an override-only session opens
              // it to add a correction once the window has closed. The sheet
              // itself decides which controls that capability actually
              // unlocks right now — see `AttendanceEditMode`.
              onTap: (widget.canRecord || widget.canOverride)
                  ? () => _attendance(shift, a)
                  : null,
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Future<void> _assign(Shift shift) async {
    await showAssignSheet(context: context, ref: ref, shift: shift);
    _refresh();
  }

  Future<void> _attendance(Shift shift, TeamMember member) async {
    await showAttendanceSheet(
      context: context,
      ref: ref,
      shift: shift,
      member: member,
      canUnassign: widget.canAssign,
    );
    _refresh();
  }

  Future<void> _edit(Shift shift) async {
    await showShiftEditor(
      context: context,
      detachmentId: widget.detachmentId,
      date: shift.date,
      defaultCenter: shift.centerName,
      existing: shift,
    );
    _refresh();
  }

  Future<void> _quickFill(Shift shift) async {
    setState(() => _busy = true);
    final result = await ref.read(shiftRepositoryProvider).quickFill(shift.id);
    _refresh();
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      success: (added, {stale = false}) =>
          _say(added == 0 ? S.quickFillNone : S.quickFillDone),
      failure: (message, _) => _say(message),
      offline: (_) => _say(S.offlineTitle),
    );
  }

  Future<void> _confirmDelete(Shift shift) async {
    final c = context.c;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(S.deleteShift),
        content: Text(
          '${shift.centerName}، '
          '${AppTime.minuteRange(shift.startMinutes, shift.endMinutes)}'
          '\n\n${S.deleteShiftBody}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(S.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: c.crit),
            child: const Text(S.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    await ref.read(shiftRepositoryProvider).delete(shift.id);
    _refresh();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(); // close the manage sheet
    messenger.showSnackBar(const SnackBar(content: Text(S.shiftDeleted)));
  }

  void _say(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = true,
    this.tone,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = tone ?? (filled ? c.primaryInk : c.primary);
    return SizedBox(
      width: double.infinity,
      child: filled
          ? FilledButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 18, color: fg),
              label: Text(label),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 18, color: fg),
              label: Text(label, style: TextStyle(color: fg)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                    color: (tone ?? c.line2)
                        .withValues(alpha: tone == null ? 1 : 0.5)),
              ),
            ),
    );
  }
}

/// Assigned against needed as a bar. Mirrors the one on the card so the two
/// surfaces read the same.
class _CoverageBar extends StatelessWidget {
  const _CoverageBar({required this.shift});

  final Shift shift;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fill = shift.needed == 0 ? 1.0 : shift.assigned / shift.needed;
    final color = fill >= 1
        ? c.ok
        : fill >= 0.7
            ? c.warn
            : c.crit;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: SizedBox(
        height: 6,
        child: Stack(children: [
          Container(color: c.surface3),
          FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: fill.clamp(0, 1),
            child: Container(color: color),
          ),
        ]),
      ),
    );
  }
}

/// A readable attendee line — avatar, full name, attendance status — used both
/// inside this sheet and (capped) on the shift card. Replaces the 12px pill,
/// which did not survive a long Arabic name.
class AttendeeRow extends StatelessWidget {
  const AttendeeRow({super.key, required this.member, required this.onTap});

  final TeamMember member;
  final VoidCallback? onTap;

  static StatusKind kindFor(AttendanceState s) => switch (s) {
        AttendanceState.checkedIn => StatusKind.ok,
        AttendanceState.checkedOut => StatusKind.info,
        AttendanceState.absent => StatusKind.crit,
        AttendanceState.notCheckedIn => StatusKind.muted,
      };

  static String labelFor(AttendanceState s) => switch (s) {
        AttendanceState.checkedIn => S.checkedIn,
        AttendanceState.checkedOut => S.checkedOut,
        AttendanceState.absent => S.absent,
        AttendanceState.notCheckedIn => S.notCheckedIn,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final kind = kindFor(member.attendance);
    final (bg, fg) = switch (kind) {
      StatusKind.ok => (c.okTint, c.ok),
      StatusKind.warn => (c.warnTint, c.warn),
      StatusKind.crit => (c.critTint, c.crit),
      StatusKind.info => (c.infoTint, c.info),
      StatusKind.muted => (c.mutedTint, c.ink2),
    };
    return PressScale(
      onTap: onTap,
      enabled: onTap != null,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Text(member.initials,
                style: TextStyle(
                    color: fg, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(member.name,
                style: TextStyle(
                    color: c.ink, fontSize: 14, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          StatusChip(kind: kind, label: labelFor(member.attendance)),
        ]),
      ),
    );
  }
}
