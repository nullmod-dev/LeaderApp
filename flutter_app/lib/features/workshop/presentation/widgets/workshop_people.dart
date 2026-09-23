import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/motion/animated_counter.dart';
import '../../../../core/motion/press_scale.dart';
import '../../../../core/result/result.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/async_result.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/sheet_scaffold.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../l10n/strings.dart';
import '../../../team/domain/member_search.dart';
import '../../../team/domain/team_models.dart';
import '../../data/workshop_providers.dart';
import '../../domain/workshop_models.dart';

/// The people-management pieces the two workshop people tabs share: the
/// roster picker, the guest-name sheet, the removal confirmation and the
/// attendance / payment choices.
///
/// Every person offered here comes off the tenant's roster by id — the picker
/// never mints a person, it only points at one.

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

/// Opens the roster picker and answers with the chosen member ids, or `null`
/// when the sheet is dismissed.
///
/// [registeredIds] and [organizerIds] are shown but cannot be picked — the
/// same person is never put on one workshop twice. [seatsLeft] caps how many
/// can be picked at once; `null` means no seat limit applies.
Future<List<String>?> pickWorkshopMembers(
  BuildContext context, {
  required String title,
  required Set<String> registeredIds,
  required Set<String> organizerIds,
  int? seatsLeft,
}) {
  return showAppSheet<List<String>>(
    context: context,
    title: title,
    expanded: true,
    child: WorkshopMemberPicker(
      registeredIds: registeredIds,
      organizerIds: organizerIds,
      seatsLeft: seatsLeft,
    ),
  );
}

class WorkshopMemberPicker extends ConsumerStatefulWidget {
  const WorkshopMemberPicker({
    super.key,
    required this.registeredIds,
    required this.organizerIds,
    this.seatsLeft,
  });

  final Set<String> registeredIds;
  final Set<String> organizerIds;
  final int? seatsLeft;

  @override
  ConsumerState<WorkshopMemberPicker> createState() =>
      _WorkshopMemberPickerState();
}

class _WorkshopMemberPickerState extends ConsumerState<WorkshopMemberPicker> {
  final _search = TextEditingController();
  final Set<String> _picked = {};
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _taken(String id) =>
      widget.registeredIds.contains(id) || widget.organizerIds.contains(id);

  bool get _atLimit =>
      widget.seatsLeft != null && _picked.length >= widget.seatsLeft!;

  List<WorkshopCandidate> _apply(List<WorkshopCandidate> all) {
    final needle = memberSearchKey(_query);
    final matches = [
      for (final c in all)
        if (needle.isEmpty ||
            memberSearchKey(c.member.name).contains(needle) ||
            memberSearchKey(c.member.department).contains(needle) ||
            memberSearchKey(c.detachment).contains(needle))
          c,
    ];
    // Who can still be added first; roster order otherwise.
    return [
      ...matches.where((c) => !_taken(c.member.id)),
      ...matches.where((c) => _taken(c.member.id)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AsyncResultView<List<WorkshopCandidate>>(
      value: ref.watch(workshopCandidatesProvider),
      onRetry: () => ref.invalidate(workshopCandidatesProvider),
      builder: (context, all, stale) {
        if (all.isEmpty) {
          return const EmptyState(
            icon: Icons.groups_outlined,
            title: S.workshopPickNone,
            body: S.workshopPickNoneSub,
          );
        }
        final shown = _apply(all);
        final noSeats = widget.seatsLeft != null && widget.seatsLeft! <= 0;
        return Column(children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: S.workshopPickSearch,
              ),
            ),
          ),
          if (noSeats || _atLimit)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  S.workshopPickNoSeats,
                  style: TextStyle(color: c.warn, fontSize: 13),
                ),
              ),
            ),
          Expanded(
            child: shown.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off_rounded,
                    title: S.workshopPickNoMatch,
                    body: '',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                    itemCount: shown.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) => _candidateRow(shown[i]),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _picked.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_picked.toList()),
                child: Text(
                  _picked.isEmpty
                      ? S.workshopPickEmptySelection
                      : '${S.workshopPickConfirm} '
                          '(${toArabicIndic('${_picked.length}')})',
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }

  Widget _candidateRow(WorkshopCandidate candidate) {
    final c = context.c;
    final m = candidate.member;
    final taken = _taken(m.id);
    final picked = _picked.contains(m.id);
    final enabled = !taken && (picked || !_atLimit);
    final subtitle = [
      candidate.detachment,
      if (m.department.trim().isNotEmpty) m.department.trim(),
    ].join(' · ');
    void toggle() => setState(() {
          if (!_picked.remove(m.id)) _picked.add(m.id);
        });

    return Semantics(
      button: !taken,
      selected: picked,
      enabled: enabled,
      child: PressScale(
        onTap: enabled ? toggle : null,
        enabled: enabled,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
          decoration: BoxDecoration(
            color: picked ? c.primaryTint : c.surface,
            border: Border.all(color: picked ? c.primary : c.line),
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: Row(children: [
            WorkshopAvatar(initials: m.initials, guest: false),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.name,
                    style: TextStyle(
                      color: taken ? c.ink3 : c.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.ink3, fontSize: 12),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (taken)
              StatusChip(
                kind: StatusKind.muted,
                label: widget.organizerIds.contains(m.id)
                    ? S.workshopPickAlreadyOrganizer
                    : S.workshopPickAlreadyParticipant,
              )
            else
              ExcludeSemantics(
                child: Checkbox(
                  value: picked,
                  onChanged: enabled ? (_) => toggle() : null,
                ),
              ),
          ]),
        ),
      ),
    );
  }
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

/// Asks for a guest's name. `null` when dismissed.
Future<String?> askWorkshopGuestName(BuildContext context) {
  return showAppSheet<String>(
    context: context,
    title: S.workshopAddGuest,
    child: const _GuestNameForm(),
  );
}

class _GuestNameForm extends StatefulWidget {
  const _GuestNameForm();

  @override
  State<_GuestNameForm> createState() => _GuestNameFormState();
}

class _GuestNameFormState extends State<_GuestNameForm> {
  final _name = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(normalizeMemberName(_name.text));
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          TextFormField(
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: S.workshopGuestName,
              hintText: S.workshopGuestNameHint,
            ),
            validator: (v) =>
                normalizeMemberName(v ?? '').isEmpty ? S.required : null,
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _submit,
            child: const Text(S.workshopAddGuest),
          ),
        ],
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

/// What one person's sheet offers. A `null` handler hides that section, so
/// the sheet only ever shows what this session may actually do.
class WorkshopPersonActions extends StatelessWidget {
  const WorkshopPersonActions({
    super.key,
    required this.attendance,
    this.onAttendance,
    this.payment,
    this.onPayment,
    this.onRemove,
    required this.removeLabel,
  });

  final AttendanceState attendance;
  final ValueChanged<AttendanceState>? onAttendance;
  final PaymentStatus? payment;
  final void Function(PaymentStatus?)? onPayment;
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
          for (final (state, label, icon) in const [
            (
              AttendanceState.checkedIn,
              S.checkedIn,
              Icons.check_circle_rounded
            ),
            (AttendanceState.checkedOut, S.checkedOut, Icons.logout_rounded),
            (AttendanceState.absent, S.absent, Icons.cancel_rounded),
            (
              AttendanceState.notCheckedIn,
              S.notCheckedIn,
              Icons.remove_circle_outline
            ),
          ])
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
          for (final (status, label, icon) in const [
            (PaymentStatus.paid, S.paymentPaid, Icons.payments_rounded),
            (PaymentStatus.unpaid, S.paymentUnpaid, Icons.money_off_rounded),
            (null, S.paymentUnspecified, Icons.help_outline_rounded),
          ])
            _ChoiceRow(
              label: label,
              icon: icon,
              selected: status == payment,
              onTap: () => onPayment!(status),
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
