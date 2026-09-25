import 'package:flutter/material.dart';

import '../../../../core/motion/press_scale.dart';
import '../../../../core/result/result.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../l10n/strings.dart';
import '../../../team/domain/team_models.dart';
import '../../domain/workshop_models.dart';

/// The people-management pieces the two workshop people tabs share: the
/// person row, the paid switch, the removal confirmation and the attendance /
/// payment choices.
///
/// Nobody is picked from the roster: team members and volunteers are typed
/// by name on their own page and belong to one workshop.

/// Shows the outcome of a workshop command. `true` when it succeeded.
bool reportWorkshopResult(
  BuildContext context,
  Result<Object?> result, {
  String? success,
}) {
  final messenger = ScaffoldMessenger.of(context);
  return result.when(
    success: (_, {stale = false}) {
      if (success != null) {
        messenger.showSnackBar(SnackBar(content: Text(success)));
      }
      return true;
    },
    failure: (message, _) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return false;
    },
    offline: (_) {
      messenger.showSnackBar(const SnackBar(content: Text(S.offlineTitle)));
      return false;
    },
  );
}

/// The monogram every workshop person row starts with.
class WorkshopAvatar extends StatelessWidget {
  const WorkshopAvatar(
      {super.key, required this.initials, required this.guest});

  final String initials;
  final bool guest;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: guest ? c.infoTint : c.primaryTint,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: guest ? c.info : c.primary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// One person's row on a workshop: monogram, name, a line of context, and a
/// status chip.
///
/// The chip moves under the name once the text is scaled up, because at
/// 320 dp and 1.6x there is no honest way to keep a name and a status on one
/// line — and truncating either is what makes a roster unreadable.
class WorkshopPersonRow extends StatelessWidget {
  const WorkshopPersonRow({
    super.key,
    required this.initials,
    required this.guest,
    required this.name,
    required this.context_,
    required this.trailing,
    this.onTap,
  });

  final String initials;
  final bool guest;
  final String name;

  /// The line under the name: what kind of participant, or a role.
  final Widget context_;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 18;
    final identity = Row(children: [
      WorkshopAvatar(initials: initials, guest: guest),
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: TextStyle(
                color: c.ink,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            context_,
          ],
        ),
      ),
      if (!stacked) ...[
        const SizedBox(width: AppSpacing.sm),
        trailing,
      ],
    ]);

    return PressScale(
      onTap: onTap,
      enabled: onTap != null,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  identity,
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: trailing,
                  ),
                ],
              )
            : identity,
      ),
    );
  }
}

/// The "paid the workshop fee" switch on the team-member and volunteer
/// pages. Off means unpaid. [feeLabel] is the fee as
/// text, printed under the title.
class WorkshopPaidSwitch extends StatelessWidget {
  const WorkshopPaidSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.feeLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? feeLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: value ? c.ok : c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: SwitchListTile.adaptive(
        key: const Key('workshop-paid-switch'),
        value: value,
        onChanged: onChanged,
        contentPadding:
            const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        title: Text(
          S.workshopPaidSwitch,
          style: TextStyle(
            color: c.ink,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusChip(
              kind: value ? StatusKind.ok : StatusKind.crit,
              label: value ? S.paymentPaid : S.paymentUnpaid,
            ),
            if (feeLabel != null)
              Text(feeLabel!, style: TextStyle(color: c.ink3, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// Confirms taking somebody off a workshop. `true` to go ahead.
Future<bool> confirmWorkshopRemoval(
  BuildContext context, {
  required String title,
  required String name,
  required String body,
}) async {
  final c = context.c;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text('$name\n\n$body'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(S.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: c.crit),
          child: const Text(S.workshopRemove),
        ),
      ],
    ),
  );
  return ok == true;
}

/// One attendance choice a person sheet offers: the state it records, its
/// label and its icon.
typedef WorkshopAttendanceChoice = (AttendanceState, String, IconData);

/// The attendance choices each workshop list offers.
abstract final class WorkshopAttendanceChoices {
  /// The organising team: the full set.
  static const List<WorkshopAttendanceChoice> all = [
    (AttendanceState.checkedIn, S.checkedIn, Icons.check_circle_rounded),
    (AttendanceState.checkedOut, S.checkedOut, Icons.logout_rounded),
    (AttendanceState.absent, S.absent, Icons.cancel_rounded),
    (AttendanceState.notCheckedIn, S.notCheckedIn, Icons.remove_circle_outline),
  ];

  /// The register — team members and volunteers/visitors: came, or is not
  /// coming. Same states, workshop-only wording.
  static const List<WorkshopAttendanceChoice> register = [
    (AttendanceState.checkedIn, S.checkedIn, Icons.check_circle_rounded),
    (AttendanceState.absent, S.workshopNotComing, Icons.cancel_rounded),
  ];
}

/// What one person's sheet offers. A `null` handler hides that section, so
/// the sheet only ever shows what this session may actually do.
///
/// The defaults are the organising team's sheet; the register passes its own
/// [attendanceChoices], [binaryPayment] and [onEdit].
class WorkshopPersonActions extends StatelessWidget {
  const WorkshopPersonActions({
    super.key,
    required this.attendance,
    this.onAttendance,
    this.attendanceChoices = WorkshopAttendanceChoices.all,
    this.payment,
    this.onPayment,
    this.binaryPayment = false,
    this.onEdit,
    this.editLabel,
    this.onRemove,
    required this.removeLabel,
  });

  final AttendanceState attendance;
  final ValueChanged<AttendanceState>? onAttendance;
  final List<WorkshopAttendanceChoice> attendanceChoices;
  final PaymentStatus? payment;
  final void Function(PaymentStatus?)? onPayment;

  /// Only paid / unpaid, with a missing record shown as unpaid.
  final bool binaryPayment;
  final VoidCallback? onEdit;
  final String? editLabel;
  final VoidCallback? onRemove;
  final String removeLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (onAttendance != null) ...[
          const SectionHeader(
              padding: _sheetHeaderPadding, title: S.workshopAttendanceSection),
          for (final (state, label, icon) in attendanceChoices)
            _ChoiceRow(
              label: label,
              icon: icon,
              selected: state == attendance,
              onTap: () => onAttendance!(state),
            ),
        ],
        if (onPayment != null) ...[
          const SectionHeader(
              padding: _sheetHeaderPadding, title: S.workshopPaymentSection),
          for (final (status, label, icon) in [
            (PaymentStatus.paid, S.paymentPaid, Icons.payments_rounded),
            (PaymentStatus.unpaid, S.paymentUnpaid, Icons.money_off_rounded),
            if (!binaryPayment)
              (null, S.paymentUnspecified, Icons.help_outline_rounded),
          ])
            _ChoiceRow(
              label: label,
              icon: icon,
              selected: binaryPayment
                  ? (status == PaymentStatus.paid) ==
                      (payment == PaymentStatus.paid)
                  : status == payment,
              onTap: () => onPayment!(status),
            ),
        ],
        if (onEdit != null) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: onEdit,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.edit_outlined),
            label: Text(editLabel ?? S.workshopEditMember),
          ),
        ],
        if (onRemove != null) ...[
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            onPressed: onRemove,
            style: TextButton.styleFrom(
              foregroundColor: c.crit,
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.person_remove_outlined),
            label: Text(removeLabel),
          ),
        ],
      ],
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        button: true,
        selected: selected,
        child: PressScale(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: selected ? c.primaryTint : c.surface,
              border: Border.all(color: selected ? c.primary : c.line),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Row(children: [
              Icon(icon, color: selected ? c.primary : c.ink2),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? c.primary : c.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check_rounded, color: c.primary),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A section eyebrow inside a bottom sheet, which owns a tighter vertical
/// rhythm than a scrolling page does.
const _sheetHeaderPadding = EdgeInsetsDirectional.fromSTEB(
  AppSpacing.xs,
  AppSpacing.sm,
  AppSpacing.xs,
  AppSpacing.sm,
);
