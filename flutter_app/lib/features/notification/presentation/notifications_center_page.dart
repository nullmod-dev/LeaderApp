import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/capability.dart';
import '../../../core/access/capability_guard.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_result.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../../core/widgets/refresh_indicator.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../l10n/strings.dart';
import '../../announcement/presentation/announcement_sheet.dart';
import '../../conflict/presentation/needs_review_page.dart';
import '../../detachment/domain/detachment_models.dart';
import '../../home/data/home_providers.dart';
import '../../shift/data/shift_providers.dart';
import '../../shift/domain/shift_models.dart';
import '../../shift/presentation/shift_manage_sheet.dart';
import '../../announcement/data/announcement_providers.dart';
import '../data/notification_providers.dart';
import '../domain/notification_models.dart';
import '../domain/notification_selectors.dart';
import 'notification_copy.dart';
import 'widgets/notification_row.dart';

/// The Notifications Center — one list of everything in the user's detachment
/// that is asking for attention, and the one place read state lives.
///
/// ## What is in it, and what is not
///
/// Every row is derived from a record that exists somewhere else in this app:
/// a shift that is short, a shift whose attendance was never recorded, a
/// shift about to start, a stock item under its minimum or near its expiry, a
/// queued write that failed or came back conflicted. Since 2026-09-07 it also
/// carries **internal announcements** — the one kind that is a record rather
/// than a condition, written by an administrator and stored, and therefore the
/// one kind that is history rather than something that resolves. There is still
/// no notification backend in this build, so there are no assignment or
/// cancellation events and no join requests: those are things a server emits,
/// and inventing them would put rows on screen that point at nothing.
/// `HANDOFF.md` records the gap.
///
/// ## Read state, and the kind that has none
///
/// Announcements carry no read/unread at all — no dot, no badge contribution,
/// no receipts (Point 14 §15). Every other kind is untouched: the bell still
/// counts them, "mark all read" still marks them, and nothing about that
/// behaviour changed.
///
/// ## Clearing
///
/// «مسح الإشعارات» removes **announcement history and nothing else**, and says
/// so before it runs. The other kinds are projections of live conditions: an
/// understaffed shift cleared today would re-derive on the next load, and the
/// only way to make it stick would be to delete the shift. See
/// `notification_history_store.dart`.
///
/// ## Where a row leads
///
/// Nowhere new. Every destination is a surface that already exists — the
/// shift management sheet, a detachment tab, the Needs Review inbox, the sync
/// screen — resolved by [destinationFor] against the session's grants, which
/// degrade the destination rather than blocking the row. A row whose record
/// has been deleted since the feed was built does not crash and does not open
/// an empty screen: it says the record is gone and refreshes the list.
///
/// ## Coming back
///
/// The feed provider stays alive while the dashboard's bell is on screen, so
/// returning from a destination re-renders rather than refetching. Read state
/// is not lost by walking away: it is stored the moment a row is opened.
class NotificationsCenterPage extends ConsumerWidget {
  const NotificationsCenterPage({super.key});

  /// A root route, like the Needs Review inbox it sits beside: a full surface
  /// the user opens deliberately, so it covers the bottom nav.
  static const routePath = '/notifications';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text(S.notificationsTitle),
        actions: const [_MarkAllReadAction(), _ClearHistoryAction()],
      ),
      body: SafeArea(
        top: false,
        child: AsyncResultView<Detachment?>(
          value: ref.watch(activeDetachmentProvider),
          onRetry: () => ref.invalidate(dashboardDetachmentsProvider),
          loading: const SkeletonList(),
          builder: (context, detachment, stale) => detachment == null
              // Not an error: a session with no detachment has nothing to be
              // notified about, and it says what would fix it.
              ? const EmptyState(
                  key: Key('notifications-no-detachment'),
                  icon: Icons.flag_outlined,
                  title: S.dashboardNoDetachmentTitle,
                  body: S.dashboardNoDetachmentBody,
                )
              : _Feed(detachmentId: detachment.id),
        ),
      ),
    );
  }
}

/// Marks every unread row read in one write.
///
/// Rendered only when there is something to mark, so the bar never offers an
/// action that would do nothing, and disabled while a write is in flight so a
/// double tap cannot queue a second one.
class _MarkAllReadAction extends ConsumerStatefulWidget {
  const _MarkAllReadAction();

  @override
  ConsumerState<_MarkAllReadAction> createState() => _MarkAllReadActionState();
}

class _MarkAllReadActionState extends ConsumerState<_MarkAllReadAction> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final detachment = ref.watch(activeDetachmentProvider).valueOrNull?.when(
          success: (data, {stale = false}) => data,
          failure: (_, __) => null,
          offline: (cached) => cached,
        );
    if (detachment == null) return const SizedBox.shrink();

    final rows = _rowsOf(ref.watch(notificationFeedProvider(detachment.id)));
    final unread = [
      for (final row in rows)
        if (!row.isRead) row.id,
    ];
    if (unread.isEmpty) return const SizedBox.shrink();

    return TextButton(
      key: const Key('notifications-mark-all'),
      onPressed: _busy ? null : () => _markAll(unread),
      child: const Text(S.notificationsMarkAllRead),
    );
  }

  Future<void> _markAll(List<String> ids) async {
    setState(() => _busy = true);
    final result =
        await ref.read(notificationReadIdsProvider.notifier).markRead(ids);
    if (!mounted) return;
    setState(() => _busy = false);
    final messenger = ScaffoldMessenger.of(context);
    result.when(
      success: (_, {stale = false}) => messenger.showSnackBar(
        const SnackBar(content: Text(S.notificationsMarkAllReadDone)),
      ),
      failure: (message, _) =>
          messenger.showSnackBar(SnackBar(content: Text(message))),
      offline: (_) => messenger.showSnackBar(
        const SnackBar(content: Text(S.offlineTitle)),
      ),
    );
  }
}

/// «مسح الإشعارات» — removes the announcement history from this list.
///
/// Three things make it safe, and all three are deliberate:
///
/// 1. **It is explicit.** A confirmation dialog that names what goes and what
///    stays, never a one-tap destructive clear.
/// 2. **It can only reach announcements.** The ids come from
///    [clearableNotificationIds], which is built from the rendered feed and
///    admits one kind. No shift, stock item, conflict or outbox operation is
///    reachable from here, let alone deleted.
/// 3. **It is scoped.** The ids come from the *visible* feed, which was already
///    narrowed by the session's grants — so a scoped administrator clears the
///    announcement history they can see and nothing beyond it.
///
/// Rendered only when there is announcement history to clear, so the bar never
/// offers an action that would do nothing, and disabled while a write is in
/// flight so a second confirmation cannot queue a second one.
class _ClearHistoryAction extends ConsumerStatefulWidget {
  const _ClearHistoryAction();

  @override
  ConsumerState<_ClearHistoryAction> createState() =>
      _ClearHistoryActionState();
}

class _ClearHistoryActionState extends ConsumerState<_ClearHistoryAction> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final detachment = ref.watch(activeDetachmentProvider).valueOrNull?.when(
          success: (data, {stale = false}) => data,
          failure: (_, __) => null,
          offline: (cached) => cached,
        );
    if (detachment == null) return const SizedBox.shrink();

    final clearable = clearableNotificationIds(
      _rowsOf(ref.watch(notificationFeedProvider(detachment.id))),
    );
    if (clearable.isEmpty) return const SizedBox.shrink();

    return IconButton(
      key: const Key('notifications-clear'),
      tooltip: S.notificationsClear,
      icon: const Icon(Icons.delete_sweep_outlined),
      onPressed: _busy ? null : () => _confirm(clearable),
    );
  }

  Future<void> _confirm(List<String> ids) async {
    final c = context.c;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(S.notificationsClearTitle),
        content: const Text(S.notificationsClearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(S.cancel),
          ),
          TextButton(
            key: const Key('notifications-clear-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: c.crit),
            child: const Text(S.notificationsClear),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final result =
        await ref.read(notificationClearedIdsProvider.notifier).clear(ids);
    if (!mounted) return;
    setState(() => _busy = false);

    final messenger = ScaffoldMessenger.of(context);
    result.when(
      success: (count, {stale = false}) => messenger.showSnackBar(
        SnackBar(
          content: Text(
            count == 0 ? S.notificationsClearNothing : S.notificationsClearDone,
          ),
        ),
      ),
      failure: (message, _) =>
          messenger.showSnackBar(SnackBar(content: Text(message))),
      offline: (_) => messenger.showSnackBar(
        const SnackBar(content: Text(S.offlineTitle)),
      ),
    );
  }
}

class _Feed extends ConsumerStatefulWidget {
  const _Feed({required this.detachmentId});

  final String detachmentId;

  @override
  ConsumerState<_Feed> createState() => _FeedState();
}

class _FeedState extends ConsumerState<_Feed> {
  /// One row at a time. Opening a row writes read state and then navigates;
  /// without this a second tap during that round trip opens the destination
  /// twice, which on a sheet means two sheets to dismiss.
  bool _opening = false;

  String get _id => widget.detachmentId;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return AppRefreshIndicator(
      onRefresh: () async {
        ref.invalidate(notificationSourceProvider(_id));
        await ref.read(notificationSourceProvider(_id).future);
      },
      child: AsyncResultView<List<AppNotification>>(
        value: ref.watch(notificationFeedProvider(_id)),
        onRetry: () => ref.invalidate(notificationSourceProvider(_id)),
        loading: const SkeletonList(),
        builder: (context, rows, stale) =>
            rows.isEmpty ? _empty(stale) : _list(rows, now, stale),
      ),
    );
  }

  /// Scrollable even when there is nothing in it, so the pull-to-refresh
  /// gesture still works on the state the user most wants to refresh.
  Widget _empty(bool stale) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
        children: [
          if (stale)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.md),
              child: Center(child: StaleBadge()),
            ),
          const EmptyState(
            key: Key('notifications-empty'),
            icon: Icons.notifications_none_rounded,
            title: S.notificationsEmptyTitle,
            body: S.notificationsEmptyBody,
          ),
        ],
      );

  Widget _list(List<AppNotification> rows, DateTime now, bool stale) {
    // Day headers and rows flattened into one lazily built list: a feed can
    // grow long, and a Column of everything would build every row on the
    // first frame. Each entry knows where it sits in its group, so the rows
    // of one day read as a single card without the list losing its laziness.
    final entries = <Object>[
      if (stale) const _StaleHeader(),
      for (final section in groupNotifications(rows, now)) ...[
        section.group,
        for (var i = 0; i < section.items.length; i++)
          _RowEntry(
            notification: section.items[i],
            isFirst: i == 0,
            isLast: i == section.items.length - 1,
          ),
      ],
    ];

    return ListView.builder(
      key: const Key('notifications-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        if (entry is _StaleHeader) {
          return const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.xs),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: StaleBadge(),
            ),
          );
        }
        if (entry is NotificationGroup) {
          return SectionHeader(
            key: Key('notifications-group-${entry.name}'),
            title: notificationGroupLabel(entry),
          );
        }

        final row = entry as _RowEntry;
        final destination =
            destinationFor(row.notification, ref.watch(capabilitiesProvider));
        return Stagger(
          index: i,
          child: _GroupedCard(
            isFirst: row.isFirst,
            isLast: row.isLast,
            child: NotificationRow(
              // Keyed by the notification, not by its position: the list
              // reorders as conditions resolve, and a positional key would
              // carry one row's state onto another.
              key: Key('notification-${row.notification.id}'),
              notification: row.notification,
              now: now,
              // An informational row is still tappable — that is how it gets
              // marked read — but it opens nothing and says so by drawing no
              // chevron.
              opensDestination: destination is! NoDestination,
              onTap: () => _open(row.notification, destination),
            ),
          ),
        );
      },
    );
  }

  /// Opens a row: read state first, then the destination.
  ///
  /// Read state is written even when the destination turns out to be gone —
  /// the user has seen the row either way, and a notification that will not
  /// stop counting itself unread is worse than one that led nowhere.
  Future<void> _open(
    AppNotification notification,
    NotificationDestination destination,
  ) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      // A kind that carries no read state is opened without one being written.
      // An announcement is not "seen" by this app — no receipt, no stored id,
      // nothing for a future badge to be built on by accident.
      final read = notification.tracksReadState
          ? await ref
              .read(notificationReadIdsProvider.notifier)
              .markRead([notification.id])
          : const Success(0);
      if (!mounted) return;
      read.when(
        success: (_, {stale = false}) {},
        failure: (message, _) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message))),
        offline: (_) => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(S.offlineTitle)),
        ),
      );
      if (!mounted) return;
      await _navigate(destination);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _navigate(NotificationDestination destination) async {
    switch (destination) {
      case NoDestination():
        return;
      case OpenNeedsReview():
        // Pushed, so returning lands back on this list.
        context.push(NeedsReviewPage.routePath);
      case OpenSyncScreen():
        // The sync screen lives inside the More tab, so this is a branch
        // switch rather than a push — the same move the dashboard's sync
        // alert makes.
        context.go('/more/sync');
      case OpenDetachmentTab(:final detachmentId, :final tab):
        context.go('/detachment/$detachmentId/$tab');
      case OpenShiftSheet(:final detachmentId, :final shiftId):
        await _openShiftSheet(detachmentId, shiftId);
      case OpenAnnouncement(:final announcementId):
        // Re-read at the moment of the tap, exactly like the shift sheet: an
        // announcement can be withdrawn or removed between the feed loading
        // and the row being opened, and that has to be a sentence rather than
        // a stale screen. `openAnnouncement` reports it and returns false.
        final shown = await openAnnouncement(context, ref, announcementId);
        if (!shown && mounted) ref.invalidate(announcementListProvider);
    }
  }

  /// Re-reads the shift at the moment of the tap.
  ///
  /// The feed is a list of pointers, and a shift can be deleted between the
  /// load and the tap — by another device, or by this user on another screen.
  /// Resolving it here is what turns that into a sentence instead of a crash
  /// or an empty sheet.
  Future<void> _openShiftSheet(String detachmentId, String shiftId) async {
    final result = await ref.read(shiftRepositoryProvider).byId(shiftId);
    if (!mounted) return;

    final shift = result.when(
      success: (data, {stale = false}) => data,
      failure: (_, __) => null,
      offline: (cached) => cached,
    );
    if (shift == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(S.notificationsTargetGone)),
      );
      // The condition is gone with the record, so the row should be too.
      ref.invalidate(notificationSourceProvider(_id));
      return;
    }

    await _showSheet(shift, detachmentId);
  }

  Future<void> _showSheet(Shift shift, String detachmentId) {
    final caps = ref.read(capabilitiesProvider);
    return showShiftManageSheet(
      context: context,
      ref: ref,
      shift: shift,
      detachmentId: detachmentId,
      canAssign: caps.canIn(detachmentId, Cap.shiftAssign),
      canRecord: caps.canIn(detachmentId, Cap.shiftAttendanceRecord),
      canOverride: caps.canIn(detachmentId, Cap.shiftAttendanceOverride),
      canManage: caps.canIn(detachmentId, Cap.shiftManage),
      canDelete: caps.canIn(detachmentId, Cap.shiftDelete),
    );
  }
}

/// A marker entry, not a widget: it tells the flattened list where the stale
/// badge goes without giving the badge a place in the day grouping.
class _StaleHeader {
  const _StaleHeader();
}

/// One row of the flattened list, with where it sits in its day group.
class _RowEntry {
  const _RowEntry({
    required this.notification,
    required this.isFirst,
    required this.isLast,
  });

  final AppNotification notification;
  final bool isFirst;
  final bool isLast;
}

/// The list's surface: the rows of one day read as a single card.
///
/// Only the first row draws a top hairline and only the last rounds its
/// bottom, so adjacent rows share one divider instead of stacking two — the
/// artifact that makes a list of bordered cards look smudged.
class _GroupedCard extends StatelessWidget {
  const _GroupedCard({
    required this.isFirst,
    required this.isLast,
    required this.child,
  });

  final bool isFirst;
  final bool isLast;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    const radius = Radius.circular(AppRadii.lg);
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? AppSpacing.sm : 0),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(
            top: isFirst ? BorderSide(color: c.line) : BorderSide.none,
            bottom: BorderSide(color: c.line),
            left: BorderSide(color: c.line),
            right: BorderSide(color: c.line),
          ),
          borderRadius: BorderRadius.vertical(
            top: isFirst ? radius : Radius.zero,
            bottom: isLast ? radius : Radius.zero,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

/// The rows a feed result carries, whatever state it is in. A failure counts
/// as no rows rather than throwing: the screen behind this is already showing
/// the failure, and the bar simply has nothing to offer.
List<AppNotification> _rowsOf(
  AsyncValue<Result<List<AppNotification>>> value,
) {
  final result = value.valueOrNull;
  if (result == null) return const [];
  return result.when(
    success: (data, {stale = false}) => data,
    failure: (_, __) => const <AppNotification>[],
    offline: (cached) => cached ?? const [],
  );
}
