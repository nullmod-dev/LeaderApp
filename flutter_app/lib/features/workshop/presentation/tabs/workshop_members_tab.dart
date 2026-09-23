import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/access/capability.dart';
import '../../../../core/access/capability_guard.dart';
import '../../../../core/format/app_number.dart';
import '../../../../core/motion/stagger.dart';
import '../../../../core/result/result.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/async_result.dart';
import '../../../../core/widgets/app_meta.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/filter_chips.dart';
import '../../../../core/widgets/offline_banner.dart' show StaleBadge;
import '../../../../core/widgets/refresh_indicator.dart';
import '../../../../core/widgets/sheet_scaffold.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../l10n/strings.dart';
import '../../../shell/main_shell.dart';
import '../../../team/domain/member_search.dart';
import '../../../team/domain/team_models.dart';
import '../../data/workshop_providers.dart';
import '../../domain/workshop_models.dart';
import '../../domain/workshop_stats.dart';
import '../widgets/workshop_people.dart';

enum _ParticipantFilter { all, members, guests }

/// The workshop's register: members of the team and guests from outside it.
///
/// Members are added from the tenant's roster by id; guests by name. Taking
/// somebody off the register never touches the roster. Every control is gated
/// on its own `workshop.*` key and closed while the workshop is archived.
class WorkshopMembersTab extends ConsumerStatefulWidget {
  const WorkshopMembersTab({super.key, required this.workshopId});

  final String workshopId;

  @override
  ConsumerState<WorkshopMembersTab> createState() => _WorkshopMembersTabState();
}

class _WorkshopMembersTabState extends ConsumerState<WorkshopMembersTab> {
  final _search = TextEditingController();
  _ParticipantFilter _filter = _ParticipantFilter.all;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _open() =>
      ref.watch(workshopModeProvider(widget.workshopId)) == WorkshopMode.active;

  @override
  Widget build(BuildContext context) {
    return AppRefreshIndicator(
      onRefresh: () =>
          ref.refresh(workshopParticipantsProvider(widget.workshopId).future),
      child: AsyncResultView<List<WorkshopParticipant>>(
        value: ref.watch(workshopParticipantsProvider(widget.workshopId)),
        onRetry: () => ref.invalidate(workshopParticipantsProvider),
        builder: (context, participants, stale) =>
            _content(context, participants, stale),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    List<WorkshopParticipant> participants,
    bool stale,
  ) {
    final open = _open();
    final canManage = open && ref.capabilities.can(Cap.workshopPeopleManage);
    final canAttend =
        open && ref.capabilities.can(Cap.workshopAttendanceRecord);
    final canPay = open && ref.capabilities.can(Cap.workshopPaymentRecord);
    final workshop =
        ref.watch(workshopByIdProvider(widget.workshopId)).whenOrNull(
              data: (r) => r.when(
                success: (Workshop w, {bool stale = false}) => w,
                failure: (_, __) => null,
                offline: (cached) => cached,
              ),
            );

    final byKind = switch (_filter) {
      _ParticipantFilter.all => participants,
      _ParticipantFilter.members =>
        participants.where((p) => p.kind == ParticipantKind.member).toList(),
      _ParticipantFilter.guests =>
        participants.where((p) => p.kind == ParticipantKind.guest).toList(),
    };
    final needle = memberSearchKey(_query);
    final filtered = needle.isEmpty
        ? byKind
        : byKind
            .where((participant) =>
                memberSearchKey(participant.name).contains(needle))
            .toList();
    final guests =
        participants.where((p) => p.kind == ParticipantKind.guest).length;

    return FloatingNavPadding(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (stale)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.md),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: StaleBadge(),
              ),
            ),
          // The count first: how full the workshop is, and how many of those
          // are guests, is what someone opening the register wants to know.
          AppMeta(
            semanticsLabel: workshop == null
                ? '${S.totalParticipants}: ${AppNumber.count(participants.length)}'
                : '${AppNumber.count(participants.length)} '
                    '${S.workshopSeatsTaken} '
                    '${AppNumber.count(workshop.capacity)}، '
                    '${S.guests} ${AppNumber.count(guests)}',
            parts: [
              if (workshop == null)
                AppMetaText.total(S.totalParticipants, participants.length,
                    emphasis: true)
              else
                AppMetaText(
                  '${AppNumber.count(participants.length)} '
                  '${S.workshopSeatsTaken} '
                  '${AppNumber.count(workshop.capacity)}',
                  emphasis: true,
                ),
              AppMetaText.count(guests, label: S.guests),
            ],
          ),
          if (canManage) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  onPressed: () => _addMembers(participants, workshop),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text(S.workshopAddMember),
                ),
                OutlinedButton.icon(
                  onPressed: _addGuest,
                  icon: const Icon(Icons.badge_outlined),
                  label: const Text(S.workshopAddGuest),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (participants.isNotEmpty) ...[
            TextField(
              key: const Key('workshop-participants-search'),
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: S.searchWorkshopParticipants,
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: S.membersClearSearch,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppFilterBar(
              semanticLabel: S.filterByStatus,
              children: [
                AppFilterChip(
                  label: S.filterAll,
                  selected: _filter == _ParticipantFilter.all,
                  onSelected: (_) =>
                      setState(() => _filter = _ParticipantFilter.all),
                ),
                AppFilterChip(
                  label: S.filterMembers,
                  selected: _filter == _ParticipantFilter.members,
                  onSelected: (_) =>
                      setState(() => _filter = _ParticipantFilter.members),
                ),
                AppFilterChip(
                  label: S.filterGuests,
                  selected: _filter == _ParticipantFilter.guests,
                  onSelected: (_) =>
                      setState(() => _filter = _ParticipantFilter.guests),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (filtered.isEmpty)
            participants.isEmpty
                ? const EmptyState(
                    key: Key('workshop-participants-empty'),
                    icon: Icons.people_outline_rounded,
                    title: S.emptyParticipants,
                    body: S.emptyParticipantsSub,
                  )
                : EmptyState(
                    key: const Key('workshop-participants-no-results'),
                    icon: Icons.search_off_rounded,
                    title: S.noMatchingWorkshopParticipants,
                    body: S.noMatchingWorkshopParticipantsSub,
                    actionLabel: S.clearWorkshopParticipantFilters,
                    onAction: () => setState(() {
                      _query = '';
                      _search.clear();
                      _filter = _ParticipantFilter.all;
                    }),
                  )
          else ...[
            for (int i = 0; i < filtered.length; i++) ...[
              Stagger(
                index: i,
                child: _ParticipantCard(
                  participant: filtered[i],
                  onTap: (canManage || canAttend || canPay)
                      ? () => _personSheet(
                            filtered[i],
                            canManage: canManage,
                            canAttend: canAttend,
                            canPay: canPay,
                          )
                      : null,
                ),
              ),
              if (i != filtered.length - 1)
                const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _addMembers(
    List<WorkshopParticipant> participants,
    Workshop? workshop,
  ) async {
    final ids = await pickWorkshopMembers(
      context,
      title: S.workshopPickMembersTitle,
      registeredIds: {
        for (final p in participants)
          if (p.memberId != null) p.memberId!,
      },
      organizerIds: {
        for (final m in workshop?.organizingTeam ?? const <TeamMember>[]) m.id,
      },
      seatsLeft: workshop == null
          ? null
          : (workshop.capacity - participants.length)
              .clamp(0, workshop.capacity),
    );
    if (ids == null || ids.isEmpty || !mounted) return;
    final result = await ref
        .read(workshopRepositoryProvider)
        .addMemberParticipants(widget.workshopId, ids);
    if (!mounted) return;
    refreshWorkshop(ref, widget.workshopId);
    reportWorkshopResult(context, result, success: S.workshopAdded);
  }

  Future<void> _addGuest() async {
    final name = await askWorkshopGuestName(context);
    if (name == null || name.isEmpty || !mounted) return;
    final result = await ref
        .read(workshopRepositoryProvider)
        .addGuestParticipant(widget.workshopId, name);
    if (!mounted) return;
    refreshWorkshop(ref, widget.workshopId);
    reportWorkshopResult(context, result, success: S.workshopAdded);
  }

  Future<void> _personSheet(
    WorkshopParticipant participant, {
    required bool canManage,
    required bool canAttend,
    required bool canPay,
  }) async {
    final repo = ref.read(workshopRepositoryProvider);
    Future<void> apply(
      BuildContext sheetContext,
      Future<Result<Object?>> Function() command,
    ) async {
      final result = await command();
      if (!mounted) return;
      refreshWorkshop(ref, widget.workshopId);
      if (!sheetContext.mounted) return;
      if (reportWorkshopResult(sheetContext, result)) {
        Navigator.of(sheetContext).pop();
      }
    }

    await showAppSheet<void>(
      context: context,
      title: '${participant.name} · ${S.workshopPersonActions}',
      child: Builder(
        builder: (sheetContext) => WorkshopPersonActions(
          attendance: participant.attendance,
          onAttendance: canAttend
              ? (state) => apply(sheetContext,
                  () => repo.setParticipantAttendance(participant.id, state))
              : null,
          payment: participant.paymentStatus,
          onPayment: canPay
              ? (status) => apply(sheetContext,
                  () => repo.setParticipantPayment(participant.id, status))
              : null,
          removeLabel: S.workshopRemoveParticipant,
          onRemove: canManage
              ? () async {
                  final go = await confirmWorkshopRemoval(
                    sheetContext,
                    title: S.workshopRemoveConfirmTitle,
                    name: participant.name,
                    body: participant.kind == ParticipantKind.member
                        ? S.workshopRemoveMemberBody
                        : S.workshopRemoveGuestBody,
                  );
                  if (!go || !sheetContext.mounted) return;
                  final result = await repo.removeParticipant(participant.id);
                  if (!mounted) return;
                  refreshWorkshop(ref, widget.workshopId);
                  if (!sheetContext.mounted) return;
                  if (reportWorkshopResult(sheetContext, result,
                      success: S.workshopRemoved)) {
                    Navigator.of(sheetContext).pop();
                  }
                }
              : null,
        ),
      ),
    );
  }
}

class _ParticipantCard extends StatelessWidget {
  const _ParticipantCard({required this.participant, required this.onTap});

  final WorkshopParticipant participant;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (attendanceKind, attendanceLabel) = switch (participant.attendance) {
      AttendanceState.checkedIn => (StatusKind.ok, S.checkedIn),
      AttendanceState.checkedOut => (StatusKind.info, S.checkedOut),
      AttendanceState.absent => (StatusKind.crit, S.absent),
      AttendanceState.notCheckedIn => (StatusKind.muted, S.notCheckedIn),
    };
    return WorkshopPersonRow(
      initials: participant.initials,
      guest: participant.kind == ParticipantKind.guest,
      name: participant.name,
      context_: AppMeta(parts: [
        AppMetaText(participant.kind == ParticipantKind.member
            ? S.kindMember
            : S.kindGuest),
        if (participant.paymentStatus != null)
          AppMetaText(participant.paymentStatus.label),
      ]),
      trailing: StatusChip(kind: attendanceKind, label: attendanceLabel),
      onTap: onTap,
    );
  }
}
