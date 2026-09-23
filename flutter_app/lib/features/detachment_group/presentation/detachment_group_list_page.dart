import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/capability.dart';
import '../../../core/access/capability_guard.dart';
import '../../../core/format/app_number.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_result.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/forward_chevron.dart';
import '../../../core/widgets/refresh_indicator.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../../shell/main_shell.dart';
import '../data/detachment_group_providers.dart';
import '../domain/detachment_group_models.dart';

/// The top of the hierarchy: the detachment groups a user works across.
///
/// A detachment group is the umbrella; the detachments are inside it. Opening
/// one lands on its detachments, which is the only reason this screen exists —
/// nothing operational happens at the detachment group level.
class DetachmentGroupListPage extends ConsumerStatefulWidget {
  const DetachmentGroupListPage({super.key});

  @override
  ConsumerState<DetachmentGroupListPage> createState() =>
      _DetachmentGroupListPageState();
}

class _DetachmentGroupListPageState
    extends ConsumerState<DetachmentGroupListPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Creating a detachment group is an organisation-level act, so it resolves
    // against the same key that creates a detachment: whoever may stand a
    // detachment up may stand up the umbrella it belongs to.
    final onCreate = ref.whenCan(
      Cap.detachmentCreate,
      () => context.push('/detachment-groups/new'),
    );

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text(S.detachmentGroupsTitle),
        actions: [
          if (onCreate != null)
            IconButton(
              tooltip: S.newDetachmentGroup,
              icon: const Icon(Icons.add_rounded),
              onPressed: onCreate,
            ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: S.searchDetachmentGroups,
            ),
          ),
        ),
        Expanded(
          child: AppRefreshIndicator(
            onRefresh: () =>
                ref.refresh(detachmentGroupListProvider(_query).future),
            child: AsyncResultView<List<DetachmentGroup>>(
              value: ref.watch(detachmentGroupListProvider(_query)),
              onRetry: () => ref.invalidate(detachmentGroupListProvider),
              builder: (context, groups, stale) =>
                  _list(context, groups, onCreate),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _list(BuildContext context, List<DetachmentGroup> groups,
      VoidCallback? onCreate) {
    if (groups.isEmpty) {
      return EmptyState(
        icon: Icons.account_balance_outlined,
        title: S.emptyDetachmentGroups,
        body: S.emptyDetachmentGroupsSub,
        actionLabel: onCreate == null ? null : S.createDetachmentGroup,
        onAction: onCreate,
      );
    }
    return FloatingNavPadding(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        itemCount: groups.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, i) {
          if (i == groups.length) return const _DetachmentGroupHint();
          return Stagger(
            index: i,
            child: _DetachmentGroupCard(
              group: groups[i],
              onOpen: () => context.push('/detachment-groups/${groups[i].id}'),
              onEdit: ref.whenCan(
                Cap.detachmentCreate,
                () => context.push('/detachment-groups/${groups[i].id}/edit'),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One line under the list saying what a detachment group *is*. Someone opening
/// this screen for the first time otherwise has to infer the hierarchy from two
/// nouns that sound alike in Arabic.
class _DetachmentGroupHint extends StatelessWidget {
  const _DetachmentGroupHint();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(children: [
        Icon(Icons.info_outline_rounded, size: 15, color: c.ink3),
        const SizedBox(width: 8),
        Expanded(
          child: Text(S.detachmentGroupHint,
              style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5)),
        ),
      ]),
    );
  }
}

class _DetachmentGroupCard extends StatelessWidget {
  const _DetachmentGroupCard({
    required this.group,
    required this.onOpen,
    required this.onEdit,
  });

  final DetachmentGroup group;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    final coverageTone = group.coveragePercent >= 85
        ? StatusKind.ok
        : group.coveragePercent >= 70
            ? StatusKind.warn
            : StatusKind.crit;

    return Hero(
      tag: 'detachment_group_${group.id}',
      child: Material(
        color: Colors.transparent,
        child: PressScale(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.infoTint,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: Icon(Icons.account_balance_rounded, color: c.info),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(group.name,
                            style: t.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        if (group.notes != null)
                          Text(group.notes!,
                              style: TextStyle(color: c.ink3, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  if (group.detachmentCount > 0)
                    StatusChip(
                      kind: coverageTone,
                      label: AppNumber.percent(group.coveragePercent),
                    ),
                  if (onEdit != null)
                    IconButton(
                      tooltip: S.edit,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.more_horiz_rounded, color: c.ink3),
                      onPressed: onEdit,
                    ),
                ]),
                const SizedBox(height: AppSpacing.md),
                Row(children: [
                  _Mini(
                    label: S.detachmentGroupDetachments,
                    value: toArabicIndic('${group.detachmentCount}'),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  _Mini(
                    label: S.detachmentGroupMembers,
                    value: toArabicIndic('${group.memberCount}'),
                  ),
                  const Spacer(),
                  const ForwardChevron(size: 20),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(children: [
      Text(label, style: TextStyle(color: c.ink3, fontSize: 12)),
      const SizedBox(width: 6),
      Text(value, style: AppTypography.digits(c.ink, size: 14)),
    ]);
  }
}
