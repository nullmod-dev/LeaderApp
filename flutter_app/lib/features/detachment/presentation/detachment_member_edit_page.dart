import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/capability.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../core/motion/motion_tokens.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_result.dart';
import '../../../core/widgets/confirmation_dialog.dart';
import '../../../core/widgets/section_header.dart';
import '../../../l10n/strings.dart';
import '../../team/data/team_providers.dart';
import '../../team/domain/team_models.dart';
import '../data/detachment_providers.dart';

/// Add (`memberId == null`) or edit one member of a detachment.
///
/// One form serves both because the four fields are identical; only the
/// title, the capability the save button resolves against, and the presence
/// of the delete action differ.
class DetachmentMemberEditPage extends ConsumerStatefulWidget {
  const DetachmentMemberEditPage({
    super.key,
    required this.detachmentId,
    required this.memberId,
  });

  final String detachmentId;
  final String? memberId;

  @override
  ConsumerState<DetachmentMemberEditPage> createState() =>
      _DetachmentMemberEditPageState();
}

class _DetachmentMemberEditPageState
    extends ConsumerState<DetachmentMemberEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _department = TextEditingController();
  final _number = TextEditingController();

  TeamRole _role = TeamRole.member;
  bool _seeded = false;
  bool _saving = false;

  bool get _isNew => widget.memberId == null;

  @override
  void dispose() {
    _name.dispose();
    _department.dispose();
    _number.dispose();
    super.dispose();
  }

  void _seed(TeamMember m) {
    if (_seeded) return;
    _seeded = true;
    _name.text = m.name;
    _department.text = m.department;
    // Stored canonically in Western digits; the UI is Arabic-Indic.
    _number.text = toArabicIndic(m.personalNumber);
    _role = m.role;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(_isNew ? S.newMember : S.editMember),
      ),
      body: _isNew
          ? _form(existing: null)
          : AsyncResultView<TeamMember>(
              value: ref.watch(memberByIdProvider(widget.memberId!)),
              onRetry: () => ref.invalidate(memberByIdProvider),
              builder: (context, m, stale) {
                _seed(m);
                return _form(existing: m);
              },
            ),
    );
  }

  Widget _form({required TeamMember? existing}) {
    // Adding someone to a roster is the invite capability; changing the
    // details of someone already on it is the edit one. Both are scoped to
    // the detachment whose roster this is.
    //
    // Both resolve through `DetachmentAccess`, which is also what refuses the
    // form on a finished detachment: the roster of a detachment that has
    // ended is a record, and this domain has no historical-correction
    // workflow to open it with (§8 — reported, not invented).
    final access = ref.accessIn(widget.detachmentId);
    final onSave = _isNew
        ? access.when(Cap.memberInvite, _save)
        : access.when(Cap.memberEdit, _save);

    // The role is its own capability, so someone who may correct a spelling
    // is not thereby able to promote a member to detachment lead.
    final canAssignRole = access.can(Cap.memberRoleAssign);

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _Field(
            controller: _name,
            label: S.memberName,
            hint: S.memberNamePlaceholder,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          _Field(
            controller: _department,
            label: S.memberDepartment,
            hint: S.memberDepartmentPlaceholder,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          _Field(
            controller: _number,
            label: S.memberNumber,
            hint: S.memberNumberPlaceholder,
            help: S.memberNumberHelp,
            // The number is digits the member picks, so the numeric keyboard
            // is the right one and anything else is rejected at the source
            // rather than at save time.
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩]')),
            ],
          ),
          const SectionHeader(title: S.memberRole),
          _RoleSelector(
            value: _role,
            // Read-only rather than hidden: a member's role is part of
            // reading the record, even when changing it is not yours to do.
            onChanged: canAssignRole ? (r) => setState(() => _role = r) : null,
          ),
          const SizedBox(height: AppSpacing.xxl),
          FilledButton(
            onPressed: _saving ? null : onSave,
            child:
                Text(_saving ? S.savedOk : (_isNew ? S.save : S.saveChanges)),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: _saving ? null : () => context.pop(),
            child: const Text(S.cancel),
          ),
          if (existing != null) ...[
            const SizedBox(height: AppSpacing.xl),
            _DeleteRow(
              onDelete: access.when(
                Cap.memberDeactivate,
                () => _confirmDelete(existing),
              ),
              enabled: !_saving,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final repo = ref.read(teamRepositoryProvider);
    final name = _name.text.trim();
    final department = _department.text.trim();
    final number = toWesternDigits(_number.text.trim());

    final Result<TeamMember> result;
    if (_isNew) {
      result = await repo.create(
        detachmentId: widget.detachmentId,
        name: name,
        department: department,
        personalNumber: number,
        role: _role,
      );
    } else {
      final current = await repo.byId(widget.memberId!);
      final existing = current.when(
        success: (m, {stale = false}) => m,
        failure: (_, __) => null,
        offline: (cached) => cached,
      );
      if (existing == null) {
        result = const Failure('لم يُعثر على العضو.', code: 'not_found');
      } else {
        result = await repo.update(existing.copyWith(
          name: name,
          department: department,
          personalNumber: number,
          role: _role,
        ));
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);

    result.when(
      success: (_, {stale = false}) {
        ref.invalidate(teamListProvider);
        ref.invalidate(memberByIdProvider);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(S.savedOk)));
        context.pop();
      },
      failure: (message, _) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message))),
      offline: (_) => ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(S.offlineTitle))),
    );
  }

  Future<void> _confirmDelete(TeamMember member) async {
    final confirmed = await showAppConfirmation(
      context: context,
      title: S.deleteMember,
      // The member's name on its own line rather than concatenated into the
      // body with two newlines, which is how it used to be shown.
      identity: member.name,
      change: S.deleteMemberBody,
      unchanged: S.deleteMemberUnchanged,
      confirmLabel: S.delete,
      severity: ConfirmationSeverity.destructive,
    );
    if (!confirmed || !mounted) return;

    setState(() => _saving = true);
    final result = await ref.read(teamRepositoryProvider).delete(member.id);
    if (!mounted) return;
    setState(() => _saving = false);

    result.when(
      success: (_, {stale = false}) {
        ref.invalidate(teamListProvider);
        ref.invalidate(memberByIdProvider);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(S.memberDeleted)));
        context.pop();
      },
      failure: (message, _) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message))),
      offline: (_) => ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(S.offlineTitle))),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.help,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? help;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: c.ink2, fontSize: 13)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textInputAction: textInputAction,
          decoration: InputDecoration(hintText: hint),
          validator: (v) => (v == null || v.trim().isEmpty) ? S.required : null,
        ),
        if (help != null) ...[
          const SizedBox(height: 6),
          Text(help!, style: TextStyle(color: c.ink3, fontSize: 12)),
        ],
      ],
    );
  }
}

/// The four roles, one per row, each carrying its own icon and tint so the
/// list is scannable without reading every label.
class _RoleSelector extends StatelessWidget {
  const _RoleSelector({required this.value, required this.onChanged});

  final TeamRole value;
  final ValueChanged<TeamRole>? onChanged;

  static const _rows = [
    (
      TeamRole.shiftSupervisor,
      S.roleShiftSupervisor,
      Icons.workspace_premium_rounded
    ),
    (
      TeamRole.administrator,
      S.roleAdministrator,
      Icons.admin_panel_settings_rounded
    ),
    (TeamRole.followUp, S.roleFollowUp, Icons.follow_the_signs_rounded),
    (TeamRole.member, S.roleMember, Icons.person_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    // One container in the semantics tree: this is a radio group, not four
    // unrelated buttons.
    return Semantics(
      container: true,
      child: Opacity(
        opacity: onChanged == null ? 0.38 : 1,
        child: Column(children: [
          for (final (role, label, icon) in _rows) ...[
            _RoleRow(
              label: label,
              icon: icon,
              selected: role == value,
              onTap: onChanged == null ? null : () => onChanged!(role),
            ),
            if (role != _rows.last.$1) const SizedBox(height: AppSpacing.sm),
          ],
        ]),
      ),
    );
  }
}

class _RoleRow extends StatelessWidget {
  const _RoleRow({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: PressScale(
        onTap: onTap,
        enabled: onTap != null,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: AnimatedContainer(
          duration: effectiveDuration(context, MotionTokens.short),
          curve: effectiveCurve(context, MotionTokens.standard),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: selected ? c.primaryTint : c.surface,
            border: Border.all(
              color: selected ? c.primary : c.line,
              // The selected row carries a full ring rather than a heavier
              // one edge, so the group reads as one control in RTL and LTR
              // alike.
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: Row(children: [
            Icon(icon, size: 20, color: selected ? c.primary : c.ink2),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? c.primary : c.ink,
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            AnimatedOpacity(
              duration: effectiveDuration(context, MotionTokens.micro),
              opacity: selected ? 1 : 0,
              child: Icon(Icons.check_rounded, size: 20, color: c.primary),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Destructive actions sit apart from the save path, below it, in the
/// critical colour and never as the button the thumb lands on by default.
class _DeleteRow extends StatelessWidget {
  const _DeleteRow({required this.onDelete, required this.enabled});

  final VoidCallback? onDelete;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (onDelete == null) return const SizedBox.shrink();
    return Column(children: [
      Divider(color: c.line, height: 1),
      const SizedBox(height: AppSpacing.sm),
      TextButton.icon(
        onPressed: enabled ? onDelete : null,
        icon: Icon(Icons.delete_outline_rounded, size: 20, color: c.crit),
        label: Text(S.deleteMember, style: TextStyle(color: c.crit)),
      ),
    ]);
  }
}
