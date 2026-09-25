import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/access/capability.dart';
import '../../../../core/access/capability_guard.dart';
import '../../../../core/result/result.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/sheet_scaffold.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../l10n/strings.dart';
import '../../../team/domain/team_models.dart';
import '../../data/workshop_providers.dart';
import '../../domain/workshop_models.dart';
import '../widgets/workshop_people.dart';
import 'workshop_members_tab.dart';

/// The «الفريق وأدواره» tab: the workshop's own team members — typed by
/// name on the «إضافة عضو» page, each with one of five roles and a paid
/// flag — with their attendance and payment.
///
/// Nobody is picked from the roster any more. Organisers put on the
/// workshop before that change still appear under them in [_Organisers],
/// where they can be checked in or removed but no new one can be added.
class WorkshopTeamTab extends StatelessWidget {
  const WorkshopTeamTab({super.key, required this.workshopId});

  final String workshopId;

  @override
  Widget build(BuildContext context) => WorkshopRegisterView(
        workshopId: workshopId,
        kind: ParticipantKind.member,
        footer: _Organisers(workshopId: workshopId),
      );
}

/// The workshop's organisers: roster members who run it rather than attend
/// it. Hidden when there are none.
///
/// Managed through `workshop.people.manage` and their attendance through
/// `workshop.attendance.record`. Organisers hold no payment record: the team
/// runs the workshop, it does not buy a seat at it.
class _Organisers extends ConsumerWidget {
  const _Organisers({required this.workshopId});

  final String workshopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open =
        ref.watch(workshopModeProvider(workshopId)) == WorkshopMode.active;
    final canManage = open && ref.capabilities.can(Cap.workshopPeopleManage);
    final canAttend =
        open && ref.capabilities.can(Cap.workshopAttendanceRecord);
    final organisers = ref.watch(workshopByIdProvider(workshopId)).whenOrNull(
              data: (r) => r.when(
                success: (Workshop w, {bool stale = false}) => w.organizingTeam,
                failure: (_, __) => null,
                offline: (cached) => cached?.organizingTeam,
              ),
            ) ??
        const <TeamMember>[];
    if (organisers.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xl),
        const SectionHeader(title: S.workshopOrganizersSection),
        for (int i = 0; i < organisers.length; i++) ...[
          _OrganiserCard(
            member: organisers[i],
            onTap: (canManage || canAttend)
                ? () => _organiserSheet(
                      context,
                      ref,
                      organisers[i],
                      canManage: canManage,
                      canAttend: canAttend,
                    )
                : null,
          ),
          if (i != organisers.length - 1) const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
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
