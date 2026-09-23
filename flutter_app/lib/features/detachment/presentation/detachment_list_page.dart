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
import '../../../core/widgets/filter_chips.dart';
import '../../../core/widgets/refresh_indicator.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../../shell/main_shell.dart';
import '../../detachment_group/data/detachment_group_providers.dart';
import '../../detachment_group/domain/detachment_group_models.dart';
import '../data/detachment_providers.dart';
import '../domain/detachment_models.dart';
import '../domain/detachment_tabs.dart';

/// The detachments of one detachment group.
///
/// [detachmentGroupId] is null only on the unscoped list — every detachment the
/// session can see, regardless of detachment group. Creating from that screen
/// has no detachment group to create *into*, so the create action only appears
/// when scoped.
class DetachmentListPage extends ConsumerStatefulWidget {
  const DetachmentListPage({super.key, this.detachmentGroupId});

  final String? detachmentGroupId;

  @override
  ConsumerState<DetachmentListPage> createState() => _S();
}

class _S extends ConsumerState<DetachmentListPage> {
  DetachmentStatus? _filter = DetachmentStatus.active;
  String _query = '';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String? get _detachmentGroupId => widget.detachmentGroupId;

  /// The archive reading of this list: finished detachments only.
  bool get _archiveOnly => _filter == DetachmentStatus.archived;

  bool get _searching => _query.trim().isNotEmpty;

  void _openNew() =>
      context.push('/detachment-groups/$_detachmentGroupId/detachment/new');

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final q = DetachmentListQuery(
      detachmentGroupId: _detachmentGroupId,
      filter: _filter,
      query: _query,
    );
    final onCreate = _detachmentGroupId == null
        ? null
        : ref.whenCan(Cap.detachmentCreate, _openNew);
    // The detachment group form saves on `detachment.create`, and its route
    // refuses anything less, so the button follows the same key rather than
    // opening a form the session can only look at.
    final onEditGroup = _detachmentGroupId == null
        ? null
        : ref.whenCan(
            Cap.detachmentCreate,
            () => context.push('/detachment-groups/$_detachmentGroupId/edit'),
          );

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: _detachmentGroupId == null
            ? const Text(S.detachmentListTitle)
            : _DetachmentGroupTitle(detachmentGroupId: _detachmentGroupId!),
        actions: [
          if (onEditGroup != null)
            IconButton(
              tooltip: S.editDetachmentGroup,
              icon: const Icon(Icons.tune_rounded),
              onPressed: onEditGroup,
            ),
          if (onCreate != null)
            IconButton(
              tooltip: S.createDetachment,
              icon: const Icon(Icons.add_rounded),
              onPressed: onCreate,
            ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
          child: Column(children: [
            TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: S.searchDetachments,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Wraps: three filters do not share one line at 320 dp with the
            // text scaled up.
            AppFilterBar(semanticLabel: S.filterByStatus, children: [
              AppFilterChip(
                  label: S.filterAll,
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null)),
              AppFilterChip(
                  label: S.filterActive,
                  selected: _filter == DetachmentStatus.active,
                  onSelected: (_) =>
                      setState(() => _filter = DetachmentStatus.active)),
              AppFilterChip(
                  label: S.filterArchived,
                  selected: _filter == DetachmentStatus.archived,
                  onSelected: (_) =>
                      setState(() => _filter = DetachmentStatus.archived)),
            ]),
          ]),
        ),
        // The archive is a different reading of the same list, so it says so
        // once, in plain words, rather than restyling every row. §25: the
        // person opening it should think "these are finished detachments, I
        // can review and export them" and nothing more technical than that.
        if (_archiveOnly)
          const Padding(
            padding: EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
            child: _ArchiveHint(),
          ),
        Expanded(
          child: AppRefreshIndicator(
            onRefresh: () => ref.refresh(detachmentListProvider(q).future),
            child: AsyncResultView<List<Detachment>>(
              value: ref.watch(detachmentListProvider(q)),
              onRetry: () => ref.invalidate(detachmentListProvider),
              builder: (context, items, stale) => _list(items, onCreate),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _list(List<Detachment> items, VoidCallback? onCreate) {
    if (items.isEmpty) return _empty(onCreate);
    // Each card opens on the tab this session may actually open there — the
    // roster needs `member.view`, and a scoped administrator without it would
    // otherwise be bounced to Home by the roster's own route guard.
    final caps = ref.watch(capabilitiesProvider);
    return FloatingNavPadding(
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, i) => Stagger(
          index: i,
          child: _DetachmentCard(
            d: items[i],
            tab: detachmentTabFor(caps, items[i].id),
          ),
        ),
      ),
    );
  }

  /// Nothing to show — but "nothing" means four different things here, and a
  /// create button offered on a search that found no match is the wrong
  /// answer to all but one of them.
  Widget _empty(VoidCallback? onCreate) {
    if (_searching) {
      return EmptyState(
        key: const Key('detachments-no-results'),
        icon: Icons.search_off_rounded,
        title: S.noMatchingDetachments,
        body: S.noMatchingDetachmentsSub,
        actionLabel: S.clearDetachmentSearch,
        onAction: () => setState(() {
          _query = '';
          _search.clear();
        }),
      );
    }
    if (_archiveOnly) {
      // Nothing has been archived yet — which is not a prompt to create
      // anything, so the archive's empty state carries no action.
      return const EmptyState(
        key: Key('archive-empty'),
        icon: Icons.inventory_rounded,
        title: S.emptyArchive,
        body: S.emptyArchiveSub,
      );
    }
    final scoped = _detachmentGroupId != null;
    return EmptyState(
      icon: Icons.flag_outlined,
      title: scoped ? S.detachmentGroupEmptyDetachments : S.emptyDetachments,
      body:
          scoped ? S.detachmentGroupEmptyDetachmentsSub : S.emptyDetachmentsSub,
      actionLabel: onCreate == null ? null : S.createDetachment,
      onAction: onCreate,
    );
  }
}

/// What the archive is, said once and quietly.
class _ArchiveHint extends StatelessWidget {
  const _ArchiveHint();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      key: const Key('archive-hint'),
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
            S.archiveHint,
            style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
          ),
        ),
      ]),
    );
  }
}

/// The detachment group's name as the screen title, so the container the list
/// belongs to is never in doubt. Falls back to the generic title while it loads
/// rather than to an empty app bar.
class _DetachmentGroupTitle extends ConsumerWidget {
  const _DetachmentGroupTitle({required this.detachmentGroupId});

  final String detachmentGroupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final name =
        ref.watch(detachmentGroupByIdProvider(detachmentGroupId)).whenOrNull(
                  data: (r) => r.when(
                    success: (DetachmentGroup t, {bool stale = false}) =>
                        t.name,
                    failure: (_, __) => null,
                    offline: (cached) => cached?.name,
                  ),
                ) ??
            S.detachmentGroupsTitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name,
            style: Theme.of(context).appBarTheme.titleTextStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        Text(S.detachments, style: TextStyle(color: c.ink3, fontSize: 12)),
      ],
    );
  }
}

class _DetachmentCard extends StatelessWidget {
  const _DetachmentCard({required this.d, required this.tab});
  final Detachment d;

  /// The detail tab the card opens on — see `detachmentTabFor`.
  final String tab;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    final archived = d.status == DetachmentStatus.archived;
    final coverageTone = d.coveragePercent >= 85
        ? StatusKind.ok
        : d.coveragePercent >= 70
            ? StatusKind.warn
            : StatusKind.crit;
    return Hero(
      tag: 'detachment_${d.id}',
      child: Material(
        color: Colors.transparent,
        child: PressScale(
          onTap: () => GoRouter.of(context).push('/detachment/${d.id}/$tab'),
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
                      color: archived ? c.mutedTint : c.primaryTint,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: Icon(Icons.flag_rounded,
                        color: archived ? c.ink3 : c.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.name,
                            style: t.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text('${d.region} · ${d.mainCenter}',
                            style: TextStyle(color: c.ink3, fontSize: 12)),
                      ],
                    ),
                  ),
                  StatusChip(
                    kind: archived ? StatusKind.muted : coverageTone,
                    label: archived
                        ? S.statusArchived
                        : AppNumber.percent(d.coveragePercent),
                  ),
                ]),
                const SizedBox(height: AppSpacing.md),
                // Wrap, not Row: "الشفتات هذا الأسبوع" plus a member count
                // does not fit one line on a narrow phone, and a clipped
                // figure is worse than a second line.
                Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.xs,
                  children: [
                    _mini(context, S.memberCount,
                        toArabicIndic(d.memberCount.toString())),
                    _mini(context, S.shiftCount,
                        toArabicIndic(d.weeklyShiftCount.toString())),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mini(BuildContext context, String label, String value) {
    final c = context.c;
    // The label gives way, never the figure: at 320 dp with large text
    // "الشفتات هذا الأسبوع" is wider than the card, and a clipped number
    // would be a wrong number.
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: Text(
          label,
          style: TextStyle(color: c.ink3, fontSize: 12),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: 6),
      Text(value, style: AppTypography.digits(c.ink, size: 14)),
    ]);
  }
}
