import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/access/capability.dart';
import '../../../../core/access/capability_guard.dart';
import '../../../../core/motion/stagger.dart';
import '../../../../core/result/result.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/async_result.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/refresh_indicator.dart';
import '../../../../core/widgets/sheet_scaffold.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../l10n/strings.dart';
import '../../../shell/main_shell.dart';
import '../../../team/domain/team_models.dart';
import '../../data/workshop_providers.dart';
import '../../domain/workshop_models.dart';
import '../widgets/workshop_people.dart';

/// The workshop's organising team: roster members who run it rather than
/// attend it.
///
/// Managed through `workshop.people.manage`, the same key as the register —
/// legacy keeps the whole register on one screen — and their attendance
/// through `workshop.attendance.record`. Organisers hold no payment record:
/// the team runs the workshop, it does not buy a seat at it. Somebody is
/// either an organiser or a participant, never both, so the statistics count
/// each person once.
class WorkshopTeamTab extends ConsumerWidget {
  const WorkshopTeamTab({super.key, required this.workshopId});

  final String workshopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open =
        ref.watch(workshopModeProvider(workshopId)) == WorkshopMode.active;
    final canManage = open && ref.capabilities.can(Cap.workshopPeopleManage);
    final canAttend =
        open && ref.capabilities.can(Cap.workshopAttendanceRecord);

    return AppRefreshIndicator(
      onRefresh: () => ref.refresh(workshopByIdProvider(workshopId).future),
      child: AsyncResultView<Workshop>(
        value: ref.watch(workshopByIdProvider(workshopId)),
        onRetry: () => ref.invalidate(workshopByIdProvider),
        builder: (context, w, stale) {
          if (w.organizingTeam.isEmpty) {
            return FloatingNavPadding(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  EmptyState(
                    icon: Icons.groups_outlined,
                    title: S.emptyWorkshopTeam,
                    body: S.emptyWorkshopTeamSub,
                    actionLabel: canManage ? S.workshopAddOrganizer : null,
                    onAction: canManage
                        ? () => _addOrganizers(context, ref, w)
                        : null,
                  ),
                ],
              ),
            );
          }
          return FloatingNavPadding(
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (canManage) ...[
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.icon(
                      onPressed: () => _addOrganizers(context, ref, w),
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text(S.workshopAddOrganizer),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                for (int i = 0; i < w.organizingTeam.length; i++) ...[
                  Stagger(
                    index: i,
                    child: _OrganiserCard(
                      member: w.organizingTeam[i],
                      onTap: (canManage || canAttend)
                          ? () => _organiserSheet(
                                context,
                                ref,
                                w.organizingTeam[i],
                                canManage: canManage,
                                canAttend: canAttend,
                              )
                          : null,
                    ),
                  ),
                  if (i != w.organizingTeam.length - 1)
                    const SizedBox(height: 10),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _addOrganizers(
    BuildContext context,
    WidgetRef ref,
    Workshop workshop,
  ) async {
    final register =
        await ref.read(workshopRepositoryProvider).participants(workshop.id);
    if (!context.mounted) return;
    final registeredIds = register.when(
      success: (list, {stale = false}) => list,
      failure: (_, __) => const <WorkshopParticipant>[],
      offline: (cached) => cached ?? const <WorkshopParticipant>[],
    );
    final ids = await pickWorkshopMembers(
      context,
      title: S.workshopPickOrganizersTitle,
      registeredIds: {
        for (final p in registeredIds)
          if (p.memberId != null) p.memberId!,
      },
      organizerIds: {for (final m in workshop.organizingTeam) m.id},
    );
    if (ids == null || ids.isEmpty || !context.mounted) return;
    final result = await ref
        .read(workshopRepositoryProvider)
        .addOrganizers(workshop.id, ids);
    if (!context.mounted) return;
    refreshWorkshop(ref, workshop.id);
    reportWorkshopResult(context, result, success: S.workshopAdded);
  }

  Future<void> _organiserSheet(
    BuildContext context,
    WidgetRef ref,
    TeamMember member, {
    required bool canManage,
    required bool canAttend,
  }) async {
    final repo = ref.read(workshopRepositoryProvider);
    Future<void> apply(
      BuildContext sheetContext,
      Future<Result<Object?>> Function() command, {
      String? success,
    }) async {
      final result = await command();
      if (!sheetContext.mounted) return;
      refreshWorkshop(ref, workshopId);
      if (reportWorkshopResult(sheetContext, result, success: success)) {
        Navigator.of(sheetContext).pop();
      }
    }

    await showAppSheet<void>(
      context: context,
      title: '${member.name} · ${S.workshopAttendanceSection}',
      child: Builder(
        builder: (sheetContext) => WorkshopPersonActions(
          attendance: member.attendance,
          onAttendance: canAttend
              ? (state) => apply(
                    sheetContext,
                    () => repo.setOrganizerAttendance(
                        workshopId, member.id, state),
                  )
              : null,
          removeLabel: S.workshopRemoveOrganizer,
          onRemove: canManage
              ? () async {
                  final go = await confirmWorkshopRemoval(
                    sheetContext,
                    title: S.workshopRemoveOrganizerTitle,
                    name: member.name,
                    body: S.workshopRemoveOrganizerBody,
                  );
                  if (!go || !sheetContext.mounted) return;
                  await apply(
                    sheetContext,
                    () => repo.removeOrganizer(workshopId, member.id),
                    success: S.workshopRemoved,
                  );
                }
              : null,
        ),
      ),
    );
  }
}

class _OrganiserCard extends StatelessWidget {
  const _OrganiserCard({required this.member, required this.onTap});

  final TeamMember member;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final roleLabel = switch (member.role) {
      TeamRole.shiftSupervisor => S.roleShiftSupervisor,
      TeamRole.administrator => S.roleAdministrator,
      TeamRole.followUp => S.roleFollowUp,
      TeamRole.member => S.roleMember,
    };
    final (kind, label) = switch (member.attendance) {
      AttendanceState.checkedIn => (StatusKind.ok, S.checkedIn),
      AttendanceState.checkedOut => (StatusKind.info, S.checkedOut),
      AttendanceState.absent => (StatusKind.crit, S.absent),
      AttendanceState.notCheckedIn => (StatusKind.muted, S.notCheckedIn),
    };
    return WorkshopPersonRow(
      initials: member.initials,
      guest: false,
      name: member.name,
      context_: Text(
        roleLabel,
        style: TextStyle(color: context.c.ink3, fontSize: 12),
      ),
      trailing: StatusChip(kind: kind, label: label),
      onTap: onTap,
    );
  }
}
