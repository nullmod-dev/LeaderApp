import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/access/capability.dart';
import '../../../../core/motion/animated_counter.dart';
import '../../../../core/motion/press_scale.dart';
import '../../../../core/motion/stagger.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/offline_banner.dart';
import '../../../../core/widgets/refresh_indicator.dart';
import '../../../../core/widgets/sheet_scaffold.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../l10n/strings.dart';
import '../../../shell/main_shell.dart';
import '../../../team/data/team_providers.dart';
import '../../../team/domain/member_search.dart';
import '../../../team/domain/team_models.dart';
import '../../data/detachment_providers.dart';

/// The detachment's roster: who is on it, and what each of them is.
///
/// A row carries the two things that identify a member on a roster — their
/// name and their role. Their department and their own number are part of
/// the record rather than part of the scan, so they live on the member's
/// page, one tap away.
///
/// Finding someone is the roster's other job once it grows past a screenful,
/// so search sits above the list and the facets that exist in the data
/// (role, section) live behind one filter control rather than as a permanent
/// bank of chips. Both are resolved in memory by `member_search.dart` — a
/// roster is tens of records, so a keystroke costs nothing and never touches
/// the network.
class DetachmentTeamTab extends ConsumerStatefulWidget {
  const DetachmentTeamTab({super.key, required this.detachmentId});

  final String detachmentId;

  @override
  ConsumerState<DetachmentTeamTab> createState() => _DetachmentTeamTabState();
}

class _DetachmentTeamTabState extends ConsumerState<DetachmentTeamTab> {
  final _search = TextEditingController();
  String _query = '';
  Set<TeamRole> _roles = const {};
  Set<String> _departments = const {};

  String get detachmentId => widget.detachmentId;

  bool get _hasFilters => _roles.isNotEmpty || _departments.isNotEmpty;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(teamListProvider(detachmentId));
    return AppRefreshIndicator(
      onRefresh: () async => ref.refresh(teamListProvider(detachmentId).future),
      child: async.when(
        loading: () => const SkeletonList(),
        error: (_, __) =>
            ErrorStateView(onRetry: () => ref.invalidate(teamListProvider)),
        data: (r) => r.when(
          success: (data, {stale = false}) => _body(data),
          failure: (m, _) => ErrorStateView(
              body: m, onRetry: () => ref.invalidate(teamListProvider)),
          offline: (cached) => cached == null
              ? const EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: S.offlineTitle,
                  body: S.noCachedCopy)
              : _body(cached, stale: true),
        ),
      ),
    );
  }

  void _openNew() => context.push('/detachment/$detachmentId/member/new');

  /// The roster card opens the member's page — their identity, contact,
  /// today's assignment and attendance history. Editing the record is one
  /// gated tap further, from that page's app bar.
  void _openMember(TeamMember m) =>
      context.push('/detachment/$detachmentId/member/${m.id}/status');

  Widget _body(List<TeamMember> members, {bool stale = false}) {
    // Adding is gated, and the gate is the same one the form resolves
    // against — an "add" that opens a page whose save button is dead is
    // worse than no "add" at all. It resolves through `DetachmentAccess`, so
    // a finished detachment closes it the way a missing grant does.
    final access = ref.accessIn(detachmentId);
    final onAdd = access.when(Cap.memberInvite, _openNew);

    // An empty roster is a different screen from a search that found
    // nothing: there is nothing to search, so the search bar is not shown.
    if (members.isEmpty) {
      return EmptyState(
        icon: Icons.group_outlined,
        title: access.isHistorical ? S.historicalEmptyTeam : S.emptyTeam,
        body: access.isHistorical ? S.historicalEmptyTeamSub : S.emptyTeamSub,
        actionLabel: onAdd == null ? null : S.addMember,
        onAction: onAdd,
      );
    }

    final visible = filterMembers(
      members,
      query: _query,
      roles: _roles,
      departments: _departments,
    );

    return Column(children: [
      // §9 honesty: `TeamRepository` answers with the roster as it stands
      // now, not a snapshot taken when the detachment closed. On a finished
      // detachment that difference matters, so the screen says so instead of
      // letting the list imply a history it does not have.
      if (access.isHistorical)
        const Padding(
          padding: EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
          child: _HistoricalRosterNote(),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
        child: _SearchBar(
          controller: _search,
          hasFilters: _hasFilters,
          onChanged: (value) => setState(() => _query = value),
          onFilters: () => _openFilters(members),
        ),
      ),
      if (_hasFilters)
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
          child: _ActiveFilterChips(
            roles: _roles,
            departments: _departments,
            onRemoveRole: (role) => setState(
              () => _roles = {..._roles}..remove(role),
            ),
            onRemoveDepartment: (department) => setState(
              () => _departments = {..._departments}..remove(department),
            ),
            onClear: () => setState(() {
              _roles = const {};
              _departments = const {};
            }),
          ),
        ),
      Expanded(
        child: visible.isEmpty
            ? EmptyState(
                key: const Key('members-no-results'),
                icon: Icons.search_off_rounded,
                title: S.noMatchingMembers,
                body: S.membersEmptySearchSub,
                actionLabel: S.membersClearFilters,
                onAction: () => setState(() {
                  _query = '';
                  _search.clear();
                  _roles = const {};
                  _departments = const {};
                }),
              )
            : FloatingNavPadding(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                      AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
                  // One extra row for the header, which carries the roster
                  // count and the add action.
                  itemCount: visible.length + 1,
                  separatorBuilder: (_, i) =>
                      SizedBox(height: i == 0 ? AppSpacing.md : 10),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return _RosterHeader(
                        shown: visible.length,
                        total: members.length,
                        stale: stale,
                        onAdd: onAdd,
                      );
                    }
                    final m = visible[i - 1];
                    return Stagger(
                      index: i - 1,
                      child: _MemberCard(
                        member: m,
                        onTap: () => _openMember(m),
                      ),
                    );
                  },
                ),
              ),
      ),
    ]);
  }

  Future<void> _openFilters(List<TeamMember> members) async {
    // Offer only facets this roster actually has. A section list that is
    // empty here means the roster carries no sections, not that the filter
    // is broken.
    final roles = rolesOf(members);
    final departments = departmentsOf(members);
    var pickedRoles = {..._roles};
    var pickedDepartments = {..._departments};

    await showAppSheet<void>(
      context: context,
      title: S.membersFiltersTitle,
      child: StatefulBuilder(
        builder: (context, setSheetState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _FilterGroup(
              label: S.membersFilterRole,
              options: [
                for (final role in roles) (role.name, roleLabel(role)),
              ],
              selected: {for (final role in pickedRoles) role.name},
              onToggle: (value) => setSheetState(() {
                final role = TeamRole.values.firstWhere((r) => r.name == value);
                pickedRoles = {...pickedRoles};
                pickedRoles.contains(role)
                    ? pickedRoles.remove(role)
                    : pickedRoles.add(role);
              }),
            ),
            if (departments.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              _FilterGroup(
                label: S.membersFilterDepartment,
                options: [for (final d in departments) (d, d)],
                selected: pickedDepartments,
                onToggle: (value) => setSheetState(() {
                  pickedDepartments = {...pickedDepartments};
                  pickedDepartments.contains(value)
                      ? pickedDepartments.remove(value)
                      : pickedDepartments.add(value);
                }),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setSheetState(() {
                    pickedRoles = {};
                    pickedDepartments = {};
                  }),
                  child: const Text(S.membersClearFilters),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton(
                  key: const Key('members-filters-apply'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(S.membersApply),
                ),
              ),
            ]),
          ],
        ),
      ),
    );

    if (!mounted) return;
    setState(() {
      _roles = pickedRoles;
      _departments = pickedDepartments;
    });
  }
}

String roleLabel(TeamRole role) => switch (role) {
      TeamRole.shiftSupervisor => S.roleShiftSupervisor,
      TeamRole.administrator => S.roleAdministrator,
      TeamRole.followUp => S.roleFollowUp,
      TeamRole.member => S.roleMember,
    };

/// One quiet line, not a banner: what the roster below actually is.
class _HistoricalRosterNote extends StatelessWidget {
  const _HistoricalRosterNote();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      key: const Key('historical-roster-note'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(children: [
        Icon(Icons.history_rounded, size: 16, color: c.ink3),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            S.historicalRosterNote,
            style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
          ),
        ),
      ]),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.hasFilters,
    required this.onChanged,
    required this.onFilters,
  });

  final TextEditingController controller;
  final bool hasFilters;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilters;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(children: [
      Expanded(
        child: TextField(
          key: const Key('members-search'),
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: S.searchMembers,
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: S.membersClearSearch,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Semantics(
        button: true,
        label: S.membersFilters,
        child: IconButton.filledTonal(
          key: const Key('members-filters'),
          tooltip: S.membersFilters,
          isSelected: hasFilters,
          onPressed: onFilters,
          icon: Icon(
            hasFilters ? Icons.filter_alt_rounded : Icons.filter_alt_outlined,
            color: hasFilters ? c.primary : c.ink2,
          ),
        ),
      ),
    ]);
  }
}

/// What is currently narrowing the list, each removable on its own. Colour is
/// not the only signal — every chip carries its own close affordance and
/// reads its label out.
class _ActiveFilterChips extends StatelessWidget {
  const _ActiveFilterChips({
    required this.roles,
    required this.departments,
    required this.onRemoveRole,
    required this.onRemoveDepartment,
    required this.onClear,
  });

  final Set<TeamRole> roles;
  final Set<String> departments;
  final ValueChanged<TeamRole> onRemoveRole;
  final ValueChanged<String> onRemoveDepartment;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final role in roles)
          _RemovableChip(
            label: roleLabel(role),
            onRemove: () => onRemoveRole(role),
          ),
        for (final department in departments)
          _RemovableChip(
            label: department,
            onRemove: () => onRemoveDepartment(department),
          ),
        TextButton(
          onPressed: onClear,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          ),
          child: const Text(S.membersClearFilters),
        ),
      ],
    );
  }
}

class _RemovableChip extends StatelessWidget {
  const _RemovableChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InputChip(
      label: Text(label, style: TextStyle(color: c.primary, fontSize: 12)),
      backgroundColor: c.primaryTint,
      side: BorderSide(color: c.primary.withValues(alpha: 0.35)),
      onDeleted: onRemove,
      deleteIcon: Icon(Icons.close_rounded, size: 16, color: c.primary),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _FilterGroup extends StatelessWidget {
  const _FilterGroup({
    required this.label,
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  /// `(value, label)` — the value identifies the option, the label is shown.
  final List<(String, String)> options;
  final String label;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.eyebrow(c),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final (value, optionLabel) in options)
              FilterChip(
                key: Key('members-filter-$value'),
                label: Text(optionLabel),
                selected: selected.contains(value),
                onSelected: (_) => onToggle(value),
                showCheckmark: true,
              ),
          ],
        ),
      ],
    );
  }
}

/// Roster count on one side, the add action on the other. The count is real
/// information — how big this detachment is — rather than a decorative title,
/// and it says how much of the roster the current search is showing.
class _RosterHeader extends StatelessWidget {
  const _RosterHeader({
    required this.shown,
    required this.total,
    required this.stale,
    required this.onAdd,
  });

  final int shown;
  final int total;
  final bool stale;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final label = shown == total
        ? '${S.memberCount} · ${toArabicIndic(total.toString())}'
        : S.membersShowingCount
            .replaceFirst('%d', toArabicIndic(shown.toString()))
            .replaceFirst('%d', toArabicIndic(total.toString()));

    return Row(children: [
      Expanded(
        // Wrap, not Row: the cached-copy badge is as wide as its own sentence,
        // so on a narrow phone (or at a large text scale) it takes the next
        // line instead of squeezing the count off the screen.
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              label,
              style: AppTypography.eyebrow(c),
            ),
            if (stale) const StaleBadge(),
          ],
        ),
      ),
      if (onAdd != null)
        PressScale(
          onTap: onAdd,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
            decoration: BoxDecoration(
              color: c.primaryTint,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add_rounded, size: 18, color: c.primary),
              const SizedBox(width: 6),
              Text(
                S.addMember,
                style: TextStyle(
                  color: c.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ]),
          ),
        ),
    ]);
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member, required this.onTap});

  final TeamMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PressScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Row(children: [
          MemberAvatar(
            initials: member.initials,
            kind: attendanceKindOf(member.attendance),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.name,
                    style: TextStyle(
                        color: c.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 3),
                // Role and section on one line, both allowed to shrink: a
                // narrow phone must elide them, never overflow the card.
                Row(children: [
                  Flexible(child: MemberRoleChip(role: member.role)),
                  if (member.department.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        member.department,
                        style: TextStyle(color: c.ink3, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ]),
              ],
            ),
          ),
          StatusChip(
            kind: attendanceKindOf(member.attendance),
            label: attendanceLabelOf(member.attendance),
          ),
        ]),
      ),
    );
  }
}

/// Shared roster vocabulary — the roster list and the member page both render
/// a role, an attendance state, and a monogram, and they must not drift.
StatusKind attendanceKindOf(AttendanceState s) => switch (s) {
      AttendanceState.checkedIn => StatusKind.ok,
      AttendanceState.checkedOut => StatusKind.info,
      AttendanceState.absent => StatusKind.crit,
      AttendanceState.notCheckedIn => StatusKind.muted,
    };

String attendanceLabelOf(AttendanceState s) => switch (s) {
      AttendanceState.checkedIn => S.checkedIn,
      AttendanceState.checkedOut => S.checkedOut,
      AttendanceState.absent => S.absent,
      AttendanceState.notCheckedIn => S.notCheckedIn,
    };

class MemberRoleChip extends StatelessWidget {
  const MemberRoleChip({super.key, required this.role});

  final TeamRole role;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
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
      child: Text(
        roleLabel(role),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    required this.initials,
    required this.kind,
    this.size = 40,
  });

  final String initials;
  final StatusKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (bg, fg) = switch (kind) {
      StatusKind.ok => (c.okTint, c.ok),
      StatusKind.warn => (c.warnTint, c.warn),
      StatusKind.crit => (c.critTint, c.crit),
      StatusKind.info => (c.infoTint, c.info),
      StatusKind.muted => (c.mutedTint, c.ink2),
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(initials,
          style: TextStyle(
            color: fg,
            fontSize: size * 0.35,
            fontWeight: FontWeight.w600,
          )),
    );
  }
}
