import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion/press_scale.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_result.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/strings.dart';
import '../../team/domain/team_models.dart';
import '../data/workshop_providers.dart';
import '../data/workshop_stats_report.dart';
import '../domain/workshop_models.dart';
import '../domain/workshop_stats.dart';
import 'widgets/workshop_people.dart';
import '../../../core/widgets/offline_banner.dart';

/// Add (`participantId == null`) or edit one of a workshop's own team
/// members: a typed name, one of five roles, and whether they paid.
///
/// With [volunteer] it is the «إضافة متطوع» page instead: the same form
/// without a role, adding a volunteer or visitor — somebody who is not a
/// team member. Volunteers are only added here, never edited.
///
/// Edit mode loads the line by id from the register rather than taking it
/// through the route's `extra`, so a deep link or a restored page still
/// opens on the right person — or says plainly that it is gone.
class WorkshopMemberFormPage extends ConsumerStatefulWidget {
  const WorkshopMemberFormPage({
    super.key,
    required this.workshopId,
    this.participantId,
    this.volunteer = false,
  }) : assert(!volunteer || participantId == null,
            'a volunteer is added, never edited');

  final String workshopId;
  final String? participantId;
  final bool volunteer;

  @override
  ConsumerState<WorkshopMemberFormPage> createState() =>
      _WorkshopMemberFormPageState();
}

class _WorkshopMemberFormPageState
    extends ConsumerState<WorkshopMemberFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();

  WorkshopRole _role = WorkshopRole.member;
  bool _paid = false;
  bool _seeded = false;
  bool _saving = false;

  bool get _isNew => widget.participantId == null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Fills the form from the stored line once. Later rebuilds — a refresh,
  /// a stale copy arriving — never overwrite what the user has typed.
  void _seed(WorkshopParticipant p) {
    if (_seeded) return;
    _seeded = true;
    _name.text = p.name;
    _role = p.role ?? WorkshopRole.member;
    _paid = p.isPaid;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(widget.volunteer
            ? S.workshopAddVolunteer
            : _isNew
                ? S.workshopMemberFormNew
                : S.workshopMemberFormEdit),
      ),
      body: _isNew
          ? _form()
          : AsyncResultView<List<WorkshopParticipant>>(
              value: ref.watch(workshopParticipantsProvider(widget.workshopId)),
              onRetry: () => ref
                  .invalidate(workshopParticipantsProvider(widget.workshopId)),
              builder: (context, participants, stale) {
                final line = participants
                    .where((p) =>
                        p.id == widget.participantId &&
                        p.kind == ParticipantKind.member)
                    .firstOrNull;
                if (line == null) {
                  return EmptyState(
                    key: const Key('workshop-member-form-not-found'),
                    icon: Icons.person_off_outlined,
                    title: S.workshopMemberNotFound,
                    body: S.workshopMemberNotFoundSub,
                    actionLabel: S.back,
                    onAction: () => context.pop(),
                  );
                }
                _seed(line);
                return _form();
              },
            ),
    );
  }

  Widget _form() {
    final c = context.c;
    final workshop =
        ref.watch(workshopByIdProvider(widget.workshopId)).whenOrNull(
              data: (r) => r.when(
                success: (Workshop w, {bool stale = false}) => w,
                failure: (_, __) => null,
                offline: (cached) => cached,
              ),
            );
    final mode = ref.watch(workshopModeProvider(widget.workshopId));
    final archived = mode == WorkshopMode.archived;
    final open = mode == WorkshopMode.active;
    final fee = workshop?.registrationFee ?? 0;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (archived) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: c.mutedTint,
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              child: Row(children: [
                Icon(Icons.inventory_2_outlined, size: 18, color: c.ink3),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    S.workshopArchivedBanner,
                    style: TextStyle(color: c.ink2, fontSize: 12),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          _Labelled(
            label: S.workshopMemberName,
            child: TextFormField(
              key: const Key('workshop-member-name'),
              controller: _name,
              autofocus: _isNew,
              enabled: !archived,
              textInputAction: TextInputAction.done,
              decoration:
                  const InputDecoration(hintText: S.workshopMemberNameHint),
              validator: (v) =>
                  normalizeMemberName(v ?? '').isEmpty ? S.required : null,
            ),
          ),
          if (!widget.volunteer) ...[
            const SizedBox(height: AppSpacing.lg),
            _Labelled(
              label: S.workshopMemberRole,
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final role in WorkshopRole.values)
                    _RolePill(
                      label: role.label,
                      selected: _role == role,
                      onTap:
                          archived ? null : () => setState(() => _role = role),
                    ),
                ],
              ),
            ),
          ],
          // A free workshop has nothing to pay, so it asks nothing about it.
          if (fee > 0) ...[
            const SizedBox(height: AppSpacing.lg),
            WorkshopPaidSwitch(
              value: _paid,
              feeLabel: formatWorkshopAmount(fee),
              onChanged: archived ? null : (v) => setState(() => _paid = v),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
          FilledButton(
            onPressed: (_saving || !open) ? null : _save,
            child: const Text(S.save),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: _saving ? null : () => context.pop(),
            child: const Text(S.cancel),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final repo = ref.read(workshopRepositoryProvider);
    final Result<WorkshopParticipant> result = widget.volunteer
        ? await repo.addGuestParticipant(
            widget.workshopId,
            normalizeMemberName(_name.text),
            paid: _paid,
          )
        : _isNew
            ? await repo.addTeamMember(
                widget.workshopId,
                name: _name.text,
                role: _role,
                paid: _paid,
              )
            : await repo.updateTeamMember(
                widget.participantId!,
                name: _name.text,
                role: _role,
                paid: _paid,
              );

    if (!mounted) return;
    setState(() => _saving = false);

    // On failure the page stays, with everything the user typed kept.
    final messenger = ScaffoldMessenger.of(context);
    result.when(
      success: (_, {stale = false}) {
        refreshWorkshop(ref, widget.workshopId);
        messenger.showSnackBar(SnackBar(
          content: Text(_isNew ? S.workshopAdded : S.savedOk),
        ));
        context.pop();
      },
      failure: (message, _) =>
          messenger.showSnackBar(SnackBar(content: Text(message))),
      offline: (_) =>
          messenger.showSnackBar(actionNeedsConnectionSnackBar),
    );
  }
}

/// One role choice, in the same pill shape the workshop status uses, tall
/// enough to be a comfortable touch target.
class _RolePill extends StatelessWidget {
  const _RolePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      child: PressScale(
        onTap: onTap,
        enabled: onTap != null,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 64),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? c.primary : c.surface,
            border: Border.all(color: selected ? c.primary : c.line2),
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? c.primaryInk : c.ink2,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: c.ink2, fontSize: 13)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
