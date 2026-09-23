import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/format/app_date.dart';
import '../../../../core/format/app_time.dart';
import '../../../../core/motion/animated_counter.dart';
import '../../../../core/sync/outbox_controller.dart';
import '../../../../core/sync/sync_coordinator.dart';
import '../../../../core/sync/sync_overview.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/forward_chevron.dart';
import '../../../../features/conflict/presentation/needs_review_page.dart';
import '../../../../l10n/strings.dart';

/// The Sync Center card (roadmap §6) — the one canonical answer to "is my
/// work saved and sent?".
///
/// It answers five questions in the order an admin asks them: am I
/// connected, is everything sent, what is still waiting, did anything fail,
/// and is anything waiting on me. One headline, one supporting sentence, the
/// counts that matter, and one obvious button.
///
/// "مزامنة الآن" is the **fallback** control — normal work syncs
/// automatically; this forces it. It drives the same [SyncCoordinator] the
/// automatic path uses, over the same outbox. It does not create a second
/// queue and it cannot duplicate an operation: the coordinator joins a
/// concurrent call onto the run already in flight, and the button holds a
/// local guard so one impatient double-tap cannot produce two reports.
///
/// Nothing here names an operation id, an idempotency key, a revision or a
/// backend state (§10, §16). While a sync is running the button is disabled,
/// but nothing else on the screen is — navigation rows stay live (§13).
class SyncSettingsSection extends ConsumerStatefulWidget {
  const SyncSettingsSection({super.key});

  @override
  ConsumerState<SyncSettingsSection> createState() =>
      _SyncSettingsSectionState();
}

class _SyncSettingsSectionState extends ConsumerState<SyncSettingsSection> {
  /// Guards the tap itself. The coordinator already collapses concurrent
  /// runs into one; this keeps a second tap from queueing a second *report*
  /// of that one run.
  bool _requesting = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final overview = ref.watch(syncOverviewProvider);

    // The outbox is still being read, or could not be. Either way the screen
    // must not claim everything is synced — that is the one lie an offline
    // first app cannot afford.
    final value = overview.valueOrNull;
    if (value == null) {
      return _StatusShell(
        child: overview.hasError
            ? _LoadFailed(onRetry: () => ref.invalidate(outboxProvider))
            : const _StatusLoading(),
      );
    }

    return _StatusShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(overview: value),
          const SizedBox(height: AppSpacing.md),
          _Headline(overview: value),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _bodyFor(value.health),
            style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.sm),
          _LastSyncLine(lastSyncedAt: value.lastSyncedAt),
          if (value.waitingCount > 0 || value.failedCount > 0) ...[
            const SizedBox(height: AppSpacing.md),
            _Counts(overview: value),
          ],
          if (value.reviewCount > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            _ConflictAttentionRow(count: value.reviewCount),
          ],
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              key: const Key('sync-now-button'),
              onPressed:
                  value.isSyncing || _requesting ? null : () => _syncNow(value),
              icon: const Icon(Icons.sync_rounded, size: 18),
              // Retrying is the same run over the same operations — the
              // architecture retries a failed change with its original
              // identity — so this relabels one button rather than offering
              // a second control that does the same thing.
              label: Text(
                value.failedCount > 0 && value.waitingCount == 0
                    ? S.retry
                    : S.syncNow,
              ),
            ),
          ),
          if (value.isOffline) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              S.syncNeedsInternet,
              key: const Key('sync-needs-internet'),
              style: TextStyle(color: c.ink3, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _syncNow(SyncOverview overview) async {
    if (_requesting) return;
    setState(() => _requesting = true);
    final messenger = ScaffoldMessenger.of(context);
    final SyncRunSummary summary;
    try {
      summary = await ref
          .read(syncCoordinatorProvider.notifier)
          .syncNow(trigger: SyncTrigger.manual);
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
    if (!context.mounted) return;

    // Honest feedback only — never a fabricated "synced" when nothing
    // actually reached a server (§12). Pending work is preserved by the
    // coordinator in every branch below.
    final String note;
    switch (summary.outcome) {
      case SyncRunOutcome.allSynced:
        note = S.syncDoneNote;
      case SyncRunOutcome.nothingPending:
        note = S.syncAllSynced;
      case SyncRunOutcome.offline:
        note = S.syncOfflineNote;
      case SyncRunOutcome.needsReview:
        note = S.syncNeedsReviewNote;
      case SyncRunOutcome.partial:
        note = S.syncPartialNote;
      case SyncRunOutcome.failed:
        note = S.syncFailedNote;
    }
    messenger.showSnackBar(SnackBar(content: Text(note)));
  }
}

String _bodyFor(SyncHealth health) => switch (health) {
      SyncHealth.syncing => S.syncBodySyncing,
      SyncHealth.needsReview => S.syncBodyNeedsReview,
      SyncHealth.offline => S.syncBodyOffline,
      SyncHealth.failed => S.syncBodyFailed,
      SyncHealth.pending => S.syncBodyPending,
      SyncHealth.upToDate => S.syncBodyUpToDate,
    };

/// The card the whole Sync Center lives in, so its loading, error and ready
/// states share one frame instead of three different-shaped screens.
class _StatusShell extends StatelessWidget {
  const _StatusShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: child,
      ),
    );
  }
}

class _StatusLoading extends StatelessWidget {
  const _StatusLoading();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      key: const Key('sync-status-loading'),
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            S.syncStatusLoading,
            style: TextStyle(color: c.ink3, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

/// The outbox could not be read. The changes themselves are untouched — only
/// the view of them failed — so the copy says exactly that and offers the
/// one useful action.
class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    return Column(
      key: const Key('sync-status-error'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.error_outline_rounded, color: c.crit),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(S.syncLoadFailedTitle, style: t.titleSmall)),
        ]),
        const SizedBox(height: AppSpacing.xs),
        Text(
          S.syncLoadFailedBody,
          style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const Key('sync-status-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text(S.retry),
          ),
        ),
      ],
    );
  }
}

/// The section label, the state icon, and — only when a sync attempt has
/// actually proved one — the connection chip.
class _Header extends StatelessWidget {
  const _Header({required this.overview});

  final SyncOverview overview;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final settled = overview.health == SyncHealth.upToDate;
    return Row(
      children: [
        Icon(
          settled ? Icons.cloud_done_outlined : Icons.sync_rounded,
          color: c.ink2,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            S.syncStatusLabel,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (overview.isSyncing)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (overview.connection != SyncConnection.unknown)
          _ConnectionChip(online: overview.connection == SyncConnection.online),
      ],
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = online ? c.ok : c.ink3;
    return Container(
      key: Key(online ? 'sync-connection-online' : 'sync-connection-offline'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: online ? c.okTint : c.surface2,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            size: 14,
            color: fg,
          ),
          const SizedBox(width: 4),
          Text(
            online ? S.syncConnected : S.syncDisconnected,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The one line the screen is read for.
class _Headline extends StatelessWidget {
  const _Headline({required this.overview});

  final SyncOverview overview;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (String text, Color color) = switch (overview.health) {
      SyncHealth.syncing => (S.syncInProgress, c.ink),
      SyncHealth.needsReview => (S.syncHeadlineNeedsReview, c.warn),
      SyncHealth.offline => (S.syncHeadlineOffline, c.ink2),
      SyncHealth.failed => (S.syncHeadlineFailed, c.crit),
      SyncHealth.pending => (S.syncHeadlinePending, c.ink2),
      SyncHealth.upToDate => (S.syncAllSynced, c.ok),
    };
    return Text(
      text,
      key: const Key('sync-state-line'),
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(color: color, fontWeight: FontWeight.w600),
    );
  }
}

/// When a sync last actually got something through. Never a wire timestamp:
/// `اليوم ١٩:٣٢` today, `أمس ١٩:٣٢` yesterday, the day and month before that.
///
/// The day and its clock carry no mark between them: a ` · ` beside a time
/// beginning «٠» is the same glyph as the digit (UI audit P1-11), and the
/// clock is isolated by [AppTime] so its colon cannot be reordered.
class _LastSyncLine extends StatelessWidget {
  const _LastSyncLine({required this.lastSyncedAt});

  final DateTime? lastSyncedAt;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final at = lastSyncedAt;
    return Text(
      at == null ? S.syncNever : '${S.syncLastSuccessPrefix}${_stamp(at)}',
      key: const Key('sync-last-success'),
      style: TextStyle(color: c.ink3, fontSize: 12),
    );
  }

  static String _stamp(DateTime t) {
    final days = AppDate.daysFromNow(t);
    final day =
        days == 0 || days == -1 ? AppDate.relativeDays(t) : AppDate.dayMonth(t);
    return '$day ${AppTime.time(t)}';
  }
}

/// The counts, in the words the user would use. Only what is non-zero: a row
/// of zeroes is a diagnostics panel, not an answer.
class _Counts extends StatelessWidget {
  const _Counts({required this.overview});

  final SyncOverview overview;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        if (overview.waitingCount > 0)
          _CountPill(
            key: const Key('sync-count-waiting'),
            icon: Icons.schedule_rounded,
            label: overview.waitingCount == 1
                ? S.syncPendingOne
                : S.syncPendingMany.replaceFirst(
                    '%d', toArabicIndic('${overview.waitingCount}')),
            color: c.ink2,
            background: c.surface2,
          ),
        if (overview.failedCount > 0)
          _CountPill(
            key: const Key('sync-count-failed'),
            icon: Icons.cloud_off_rounded,
            label: overview.failedCount == 1
                ? S.syncFailedOne
                : S.syncFailedMany.replaceFirst(
                    '%d', toArabicIndic('${overview.failedCount}')),
            color: c.crit,
            background: c.critTint,
          ),
      ],
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Quiet attention state for operations waiting on a human conflict
/// decision (roadmap §4/§5), and the one way into the Needs Review inbox.
///
/// Still quiet: it appears only when there is something to review, it never
/// interrupts, and it never blocks the rest of the screen — the status above
/// it and the sync button below it stay fully usable. It reads the same
/// count the list is built from, so the number here and the rows there
/// cannot disagree.
///
/// Tapping is an explicit human action, which is exactly the condition under
/// which the conflict surfaces may be opened at all — Auto Sync still has no
/// route into them.
class _ConflictAttentionRow extends StatelessWidget {
  const _ConflictAttentionRow({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final label = count == 1
        ? S.syncReviewOne
        : S.syncReviewMany.replaceFirst('%d', toArabicIndic('$count'));

    void open() => context.push(NeedsReviewPage.routePath);

    // One composed announcement for the whole row ("N changes need review,
    // open the review list") instead of the count line read on its own, with
    // the activation action kept on the same node — `excludeSemantics` drops
    // the subtree's own nodes, including the InkWell's.
    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: '$label، ${S.syncReviewOpenHint}',
      onTap: open,
      child: Material(
        color: c.warnTint,
        borderRadius: BorderRadius.circular(AppRadii.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('sync-conflict-attention'),
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(Icons.compare_arrows_rounded, size: 18, color: c.warn),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    label,
                    key: const Key('sync-conflict-attention-label'),
                    style: TextStyle(
                      color: c.warn,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ForwardChevron(size: 18, color: c.warn),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
