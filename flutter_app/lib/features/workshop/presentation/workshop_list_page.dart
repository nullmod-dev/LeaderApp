import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/capability.dart';
import '../../../core/access/capability_guard.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/time/clock.dart';
import '../../../core/widgets/async_result.dart';
import '../../../core/widgets/app_meta.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/filter_chips.dart';
import '../../../core/widgets/refresh_indicator.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../../shell/main_shell.dart';
import '../data/workshop_providers.dart';
import '../domain/workshop_models.dart';

/// Workshops are organisation-level: they carry no detachment id, so nothing
/// on this screen is scoped and `workshop.create` is checked globally.
enum _Bucket { all, upcoming, past, archived }

class WorkshopListPage extends ConsumerStatefulWidget {
  const WorkshopListPage({super.key});

  @override
  ConsumerState<WorkshopListPage> createState() => _WorkshopListPageState();
}

class _WorkshopListPageState extends ConsumerState<WorkshopListPage> {
  final _search = TextEditingController();
  String _query = '';
  _Bucket _bucket = _Bucket.upcoming;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text(S.workshopsTitle),
        actions: [
          IconButton(
            tooltip: S.createWorkshop,
            icon: const Icon(Icons.add_rounded),
            onPressed: ref.whenCan(
              Cap.workshopCreate,
              () => context.push('/workshop/new'),
            ),
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
                hintText: S.searchWorkshops,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppFilterBar(
              semanticLabel: S.filterByStatus,
              children: [
                AppFilterChip(
                  label: S.filterAll,
                  selected: _bucket == _Bucket.all,
                  onSelected: (_) => setState(() => _bucket = _Bucket.all),
                ),
                AppFilterChip(
                  label: S.filterUpcoming,
                  selected: _bucket == _Bucket.upcoming,
                  onSelected: (_) => setState(() => _bucket = _Bucket.upcoming),
                ),
                AppFilterChip(
                  label: S.filterPast,
                  selected: _bucket == _Bucket.past,
                  onSelected: (_) => setState(() => _bucket = _Bucket.past),
                ),
                AppFilterChip(
                  label: S.filterArchived,
                  selected: _bucket == _Bucket.archived,
                  onSelected: (_) => setState(() => _bucket = _Bucket.archived),
                ),
              ],
            ),
          ]),
        ),
        Expanded(
          child: AppRefreshIndicator(
            onRefresh: () => ref.refresh(workshopListProvider.future),
            child: AsyncResultView<List<Workshop>>(
              value: ref.watch(workshopListProvider),
              onRetry: () => ref.invalidate(workshopListProvider),
              builder: (context, all, stale) =>
                  _list(_apply(all, ref.watch(clockProvider)())),
            ),
          ),
        ),
      ]),
    );
  }

  /// Search and bucket filtering happen on the client because the whole list
  /// is small; the repository takes no query parameters.
  ///
  /// An archived workshop appears only under its own filter: it is finished
  /// business, and leaving it in "all" would make the list read as the work
  /// still in hand plus everything that ever was.
  List<Workshop> _apply(List<Workshop> all, DateTime now) {
    final live = all.where((w) => !w.archived);
    Iterable<Workshop> out = switch (_bucket) {
      _Bucket.all => live,
      _Bucket.upcoming => live.where((w) => w.at.isAfter(now)),
      _Bucket.past => live.where((w) => !w.at.isAfter(now)),
      _Bucket.archived => all.where((w) => w.archived),
    };
    final q = _query.trim();
    if (q.isNotEmpty) {
      out = out.where((w) => w.name.contains(q) || w.location.contains(q));
    }
    return out.toList();
  }

  Widget _list(List<Workshop> items) {
    if (items.isEmpty) {
      if (_bucket == _Bucket.archived) {
        return const EmptyState(
          icon: Icons.inventory_2_outlined,
          title: S.emptyArchive,
          body: S.archiveHint,
        );
      }
      return EmptyState(
        icon: Icons.school_outlined,
        title: S.emptyWorkshops,
        body: S.emptyWorkshopsSub,
        actionLabel: S.createWorkshop,
        onAction: ref.whenCan(
          Cap.workshopCreate,
          () => context.push('/workshop/new'),
        ),
      );
    }
    return FloatingNavPadding(
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, i) => Stagger(
          index: i,
          child: WorkshopCard(workshop: items[i]),
        ),
      ),
    );
  }
}

/// Shared with the workshop detail header so the two never drift.
StatusKind workshopStatusKind(WorkshopStatus s) => switch (s) {
      WorkshopStatus.scheduled => StatusKind.info,
      WorkshopStatus.ongoing => StatusKind.ok,
      WorkshopStatus.done => StatusKind.muted,
    };

String workshopStatusLabel(WorkshopStatus s) => switch (s) {
      WorkshopStatus.scheduled => S.workshopScheduled,
      WorkshopStatus.ongoing => S.workshopOngoing,
      WorkshopStatus.done => S.workshopDone,
    };

class WorkshopCard extends StatelessWidget {
  const WorkshopCard({super.key, required this.workshop});

  final Workshop workshop;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    final w = workshop;
    final seatsLeft = (w.capacity - w.registered).clamp(0, w.capacity);
    return Hero(
      tag: 'workshop_${w.id}',
      child: Material(
        color: Colors.transparent,
        child: PressScale(
          onTap: () => GoRouter.of(context).push('/workshop/${w.id}/team'),
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
                    child: Icon(Icons.school_rounded, color: c.info),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(w.name,
                            style: t.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        AppMeta(parts: [
                          AppMetaText.dayTime(w.at),
                          AppMetaText(w.location),
                        ]),
                      ],
                    ),
                  ),
                  StatusChip(
                    kind: w.archived
                        ? StatusKind.muted
                        : workshopStatusKind(w.status),
                    label: w.archived
                        ? S.statusArchived
                        : workshopStatusLabel(w.status),
                  ),
                ]),
                const SizedBox(height: AppSpacing.md),
                // Wraps rather than sits on one line: at 320 dp with the text
                // scaled up, three figures and a chip do not fit across.
                Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _mini(
                        context,
                        S.registeredMembers,
                        '${toArabicIndic(w.registered.toString())}'
                        '/${toArabicIndic(w.capacity.toString())}'),
                    _mini(
                        context, S.guests, toArabicIndic(w.guests.toString())),
                    if (w.isFull)
                      const StatusChip(kind: StatusKind.warn, label: S.full)
                    else
                      Text(
                        '${toArabicIndic(seatsLeft.toString())} '
                        '${S.workshopSeatsLeft}',
                        style: TextStyle(color: c.ink3, fontSize: 12),
                      ),
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
    return Row(children: [
      Text(label, style: TextStyle(color: c.ink3, fontSize: 12)),
      const SizedBox(width: 6),
      Text(value, style: AppTypography.digits(c.ink, size: 14)),
    ]);
  }
}
