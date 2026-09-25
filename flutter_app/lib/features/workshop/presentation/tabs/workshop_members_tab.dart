import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

enum _PayFilter { all, paid, unpaid }

/// The «المتطوعون والزوار» tab: the volunteers and visitors, who are not team
/// members and are known only by name. The workshop's own team members live
/// on the «الفريق وأدواره» tab (`WorkshopTeamTab`).
class WorkshopMembersTab extends StatelessWidget {
  const WorkshopMembersTab({super.key, required this.workshopId});

  final String workshopId;

  @override
  Widget build(BuildContext context) => WorkshopRegisterView(
        workshopId: workshopId,
        kind: ParticipantKind.guest,
      );
}

/// One half of the workshop's register — its team members (typed by name,
/// each with a role) or its volunteers and visitors — listed with search,
/// the paid/unpaid filter and the attendance / payment sheet.
///
/// Both halves are added on a full page: «إضافة عضو» for a team member,
/// «إضافة متطوع» for a volunteer. Nobody here is picked from the roster or
/// shared with another workshop. Every control is gated on its own
/// `workshop.*` key and closed while the workshop is archived. A free
/// workshop shows no payment at all. [footer] follows the list — the team
/// tab puts the workshop's organisers there.
class WorkshopRegisterView extends ConsumerStatefulWidget {
  const WorkshopRegisterView({
    super.key,
    required this.workshopId,
    required this.kind,
    this.footer,
  });

  final String workshopId;
  final ParticipantKind kind;
  final Widget? footer;

  @override
  ConsumerState<WorkshopRegisterView> createState() =>
      _WorkshopRegisterViewState();
}

class _WorkshopRegisterViewState extends ConsumerState<WorkshopRegisterView> {
  final _search = TextEditingController();
  _PayFilter _pay = _PayFilter.all;
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

  void _clearFilters() => setState(() {
        _query = '';
        _search.clear();
        _pay = _PayFilter.all;
      });

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
    // Until the workshop is read its fee is unknown; payment stays hidden
    // rather than flashing in and out.
    final paying = (workshop?.registrationFee ?? 0) > 0;

    final team = widget.kind == ParticipantKind.member;
    final inPart = participants.where((p) => p.kind == widget.kind).toList();
    final unpaidInPart = inPart.where((p) => !p.isPaid).length;

    final byPay = !paying
        ? inPart
        : switch (_pay) {
            _PayFilter.all => inPart,
            _PayFilter.paid => inPart.where((p) => p.isPaid).toList(),
            _PayFilter.unpaid => inPart.where((p) => !p.isPaid).toList(),
          };
    final needle = memberSearchKey(_query);
    final filtered = needle.isEmpty
        ? byPay
        : byPay
            .where((participant) =>
                memberSearchKey(participant.name).contains(needle))
            .toList();

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
          // How full the workshop is comes first: everyone on the register,
          // team members and volunteers alike, takes a seat.
          AppMeta(
            semanticsLabel: workshop == null
                ? '${S.totalParticipants}: ${AppNumber.count(participants.length)}'
                : '${AppNumber.count(participants.length)} '
                    '${S.workshopSeatsTaken} '
                    '${AppNumber.count(workshop.capacity)}',
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
            ],
          ),
          if (canManage) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: team
                  ? FilledButton.icon(
                      key: const Key('workshop-add-member'),
                      onPressed: () => context
                          .push('/workshop/${widget.workshopId}/members/new'),
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text(S.workshopAddMember),
                    )
                  : FilledButton.icon(
                      key: const Key('workshop-add-volunteer'),
                      onPressed: () => context.push(
                          '/workshop/${widget.workshopId}/volunteers/new'),
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text(S.workshopAddVolunteer),
                    ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (inPart.isNotEmpty) ...[
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
            if (paying) ...[
              const SizedBox(height: AppSpacing.sm),
              AppFilterBar(
                semanticLabel: S.workshopPaymentSection,
                children: [
                  AppFilterChip(
                    label: S.filterAll,
                    selected: _pay == _PayFilter.all,
                    onSelected: (_) => setState(() => _pay = _PayFilter.all),
                  ),
                  AppFilterChip(
                    label: S.paymentPaid,
                    selected: _pay == _PayFilter.paid,
                    onSelected: (_) => setState(() => _pay = _PayFilter.paid),
                  ),
                  AppFilterChip(
                    key: const Key('workshop-filter-unpaid'),
                    label: '${S.paymentUnpaid} '
                        '(${AppNumber.count(unpaidInPart)})',
                    selected: _pay == _PayFilter.unpaid,
                    onSelected: (_) => setState(() => _pay = _PayFilter.unpaid),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
          ],
          if (filtered.isEmpty)
            inPart.isEmpty
                ? (team
                    ? const EmptyState(
                        key: Key('workshop-participants-empty'),
                        icon: Icons.people_outline_rounded,
                        title: S.emptyParticipants,
                        body: S.emptyParticipantsSub,
                      )
                    : const EmptyState(
                        key: Key('workshop-visitors-empty'),
                        icon: Icons.badge_outlined,
                        title: S.emptyWorkshopVisitors,
                        body: S.emptyWorkshopVisitorsSub,
                      ))
                : EmptyState(
                    key: const Key('workshop-participants-no-results'),
                    icon: Icons.search_off_rounded,
                    title: S.noMatchingWorkshopParticipants,
                    body: S.noMatchingWorkshopParticipantsSub,
                    actionLabel: S.clearWorkshopParticipantFilters,
                    onAction: _clearFilters,
                  )
          else ...[
            for (int i = 0; i < filtered.length; i++) ...[
              Stagger(
                index: i,
                child: _ParticipantCard(
                  participant: filtered[i],
                  showPayment: paying,
                  onTap: (canManage || canAttend || (canPay && paying))
                      ? () => _personSheet(
                            filtered[i],
                            canManage: canManage,
                            canAttend: canAttend,
                            canPay: canPay && paying,
                          )
                      : null,
                ),
              ),
              if (i != filtered.length - 1)
                const SizedBox(height: AppSpacing.sm),
            ],
          ],
          if (widget.footer != null) widget.footer!,
        ],
      ),
    );
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
          attendanceChoices: WorkshopAttendanceChoices.register,
          onAttendance: canAttend
              ? (state) => apply(sheetContext,
                  () => repo.setParticipantAttendance(participant.id, state))
              : null,
          payment: participant.paymentStatus,
          binaryPayment: true,
          onPayment: canPay
              ? (status) => apply(sheetContext,
                  () => repo.setParticipantPayment(participant.id, status))
              : null,
          // Only a team member has a role and a page; a volunteer or visitor
          // is removed and added again.
          onEdit: canManage && participant.kind == ParticipantKind.member
              ? () {
                  Navigator.of(sheetContext).pop();
                  context.push('/workshop/${widget.workshopId}'
                      '/members/${participant.id}/edit');
                }
              : null,
          editLabel: S.workshopEditMember,
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
  const _ParticipantCard({
    required this.participant,
    required this.showPayment,
    required this.onTap,
  });

  final WorkshopParticipant participant;
  final bool showPayment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (attendanceKind, attendanceLabel) = switch (participant.attendance) {
      AttendanceState.checkedIn => (StatusKind.ok, S.checkedIn),
      AttendanceState.checkedOut => (StatusKind.info, S.checkedOut),
      AttendanceState.absent => (StatusKind.crit, S.workshopNotComing),
      AttendanceState.notCheckedIn => (StatusKind.muted, S.notCheckedIn),
    };
    final member = participant.kind == ParticipantKind.member;
    return WorkshopPersonRow(
      initials: participant.initials,
      guest: !member,
      name: participant.name,
      // The payment chip rides on the context line, never beside the
      // attendance chip: two trailing chips do not fit at 320dp.
      context_: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          AppMeta(parts: [
            AppMetaText(member
                ? (participant.role ?? WorkshopRole.member).label
                : S.kindGuest),
          ]),
          if (showPayment)
            StatusChip(
              kind: participant.isPaid ? StatusKind.ok : StatusKind.crit,
              label: participant.isPaid ? S.paymentPaid : S.paymentUnpaid,
            ),
        ],
      ),
      trailing: StatusChip(kind: attendanceKind, label: attendanceLabel),
      onTap: onTap,
    );
  }
}
