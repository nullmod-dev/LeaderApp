import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/app_date.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/sync/outbox_controller.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/forward_chevron.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../l10n/strings.dart';
import '../data/conflict_outbox_resolver.dart';
import '../data/conflict_review_controller.dart';
import '../domain/conflict_models.dart';
import '../domain/needs_review_item.dart';
import 'conflict_resolution_page.dart';

/// The Needs Review inbox — the explicit list of local changes waiting on a
/// human decision (roadmap §4/§5).
///
/// ## Why it is a list the user opens, never a screen that opens itself
///
/// Auto Sync classifies a conflict in the background while the user is doing
/// something else — often mid-shift, in the field. It preserves the
/// operation, records safe review metadata, updates the quiet count in
/// Settings, and stops. It never navigates. This page is the other end of
/// that: the user decides when to come and review, opens the list from the
/// Settings attention row, and picks a conflict. Nothing here is reachable
/// automatically.
///
/// ## What it shows
///
/// Every conflicted operation, newest first, whether or not safe metadata
/// was captured for it — see [NeedsReviewItem] for why the join runs from
/// the outbox outwards. A row with metadata opens the Task 1
/// differences-first screen; a row without it says so plainly and stays
/// non-interactive, because offering "استخدام تعديلي" / "استخدام النسخة
/// الحالية" with nothing to compare would be asking for an uninformed,
/// irreversible choice.
///
/// ## Coming back
///
/// A decision is applied by `conflictDecisionHandlerProvider` before the
/// conflict screen closes. `reviewLater` applies nothing on purpose, so the
/// operation is still conflicted and the row is still here on the way back —
/// unresolved local work cannot be lost by walking away from it.
class NeedsReviewPage extends ConsumerWidget {
  const NeedsReviewPage({super.key});

  static const routePath = '/needs-review';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final items = ref.watch(needsReviewItemsProvider);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text(S.needsReviewTitle)),
      body: SafeArea(
        top: false,
        child: items.when(
          loading: () => const SkeletonList(),
          // `needsReviewItemsProvider` joins two independent sources
          // (`outboxProvider`, `conflictReviewProvider`); either one can be
          // the one that actually failed to load, so retry must reload both
          // rather than assume it was the review store.
          error: (_, __) {
            return ErrorStateView(
              onRetry: () {
                ref.invalidate(outboxProvider);
                ref.invalidate(conflictReviewProvider);
              },
            );
          },
          data: (rows) => rows.isEmpty
              ? const EmptyState(
                  key: Key('needs-review-empty'),
                  icon: Icons.fact_check_outlined,
                  title: S.needsReviewEmptyTitle,
                  body: S.needsReviewEmptyBody,
                )
              : _list(context, ref, rows),
        ),
      ),
    );
  }

  Widget _list(
    BuildContext context,
    WidgetRef ref,
    List<NeedsReviewItem> rows,
  ) {
    return ListView.separated(
      key: const Key('needs-review-list'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      itemCount: rows.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) {
        if (i == 0) return const _Intro();
        final item = rows[i - 1];
        return Stagger(
          index: i - 1,
          child: _ReviewCard(
            item: item,
            onOpen: item.isReviewable ? () => _open(context, ref, item) : null,
          ),
        );
      },
    );
  }

  /// Opens the Task 1 screen for one conflict, rebuilt from stored metadata.
  ///
  /// The route is pushed (not replaced) so returning lands back on this
  /// list, and it carries the shared decision handler so `useLocal` /
  /// `useCurrent` / `reviewLater` are applied to the one outbox both sync
  /// paths drain.
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    NeedsReviewItem item,
  ) async {
    final entry = item.entry;
    if (entry == null) return;
    final result = await context.push<Object?>(
      ConflictResolutionPage.locationFor(item.conflictId),
      extra: ConflictResolutionRouteArgs(
        conflict: entry.toPresentation(),
        onDecision: ref.read(conflictDecisionHandlerProvider),
      ),
    );
    // The conflict screen closed because what it was showing is no longer
    // what is stored — it was decided elsewhere, or the record moved again.
    // It has already told the user which; this list's job is to stop showing
    // the stale row. Both sources are re-read because either can be the one
    // that moved.
    if (result is ConflictResolutionException && result.isStale) {
      await ref.read(outboxProvider.notifier).refresh();
      await ref.read(conflictReviewProvider.notifier).refresh();
    }
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.xs),
      child: Text(
        S.needsReviewIntro,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: c.ink2, height: 1.55),
      ),
    );
  }
}

/// One conflicted change. Renders only feature-approved copy and a coarse
/// relative time — never the operation id that routes the tap.
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.item, this.onOpen});

  final NeedsReviewItem item;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    final reviewable = onOpen != null;

    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: reviewable ? c.warn : c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: reviewable ? c.warnTint : c.surface2,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(
              reviewable
                  ? Icons.compare_arrows_rounded
                  : Icons.cloud_off_rounded,
              size: 20,
              color: reviewable ? c.warn : c.ink3,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: t.titleSmall),
                if (item.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle!,
                    style: t.bodySmall?.copyWith(color: c.ink3),
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${S.needsReviewDetectedPrefix}${_detectedAgo(item.detectedAt)}',
                  style: TextStyle(color: c.ink3, fontSize: 12),
                ),
                if (!reviewable) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    S.needsReviewUnavailable,
                    style: TextStyle(
                      color: c.ink2,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    S.needsReviewUnavailableBody,
                    style: TextStyle(color: c.ink3, fontSize: 12, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
          if (reviewable) ...[
            const SizedBox(width: AppSpacing.sm),
            const ForwardChevron(),
          ],
        ],
      ),
    );

    if (!reviewable) {
      // Still announced, so a screen-reader user learns the change is
      // waiting and why it cannot be opened — just not as a control.
      return Semantics(
        container: true,
        key: Key('needs-review-blocked-${item.conflictId}'),
        child: card,
      );
    }

    // One composed announcement for the row, with the activation action on
    // the same node: `excludeSemantics` drops the subtree's own nodes,
    // including the gesture detector's tap action, so it is re-added here.
    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: '${S.needsReviewOpen}، ${item.title}',
      onTap: onOpen,
      child: PressScale(
        key: Key('needs-review-item-${item.conflictId}'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: card,
      ),
    );
  }
}

/// Coarse "when did this show up", in the same vocabulary the Settings sync
/// card uses for its last-sync line. Never an exact wire timestamp.
String _detectedAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return S.now;
  if (d.inMinutes < 60) {
    return S.minsAgo.replaceFirst('%d', toArabicIndic('${d.inMinutes}'));
  }
  if (d.inHours < 24) {
    return S.hoursAgo.replaceFirst('%d', toArabicIndic('${d.inHours}'));
  }
  return AppDate.dayMonth(t);
}
