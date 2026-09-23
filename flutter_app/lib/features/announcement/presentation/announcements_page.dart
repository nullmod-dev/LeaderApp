import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/capability_guard.dart';
import '../../../core/format/app_date.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/clock.dart';
import '../../../core/widgets/async_result.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/refresh_indicator.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../data/announcement_providers.dart';
import '../domain/announcement_models.dart';
import '../domain/announcement_selectors.dart';
import 'announcement_compose_page.dart';
import 'announcement_copy.dart';
import 'announcement_sheet.dart';

/// The announcements this session may manage, and the one action that manages
/// them: stop.
///
/// **Not a second Notifications Center.** The centre is where an announcement
/// is *read*, by everyone it was addressed to, forever. This screen is where it
/// is *acted on*, by someone who may publish — which is a different question,
/// asked by a different person, about a different set of rows. The two would be
/// the same screen only if reading and stopping were the same act.
///
/// Every row is scoped by the same rule the rest of the app uses: an
/// announcement appears here when the session holds `announcement.publish` in
/// at least one of the detachments it addresses. A scoped administrator
/// therefore manages their own detachment's notices and never sees, let alone
/// stops, another detachment's.
class AnnouncementsPage extends ConsumerWidget {
  const AnnouncementsPage({super.key});

  /// A root route beside the Notifications Center and for the same reason: a
  /// full surface the user opens deliberately, so it covers the bottom nav.
  static const routePath = '/announcements';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final canPublish = ref.watch(canPublishAnnouncementsProvider);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text(S.announcementsTitle),
        actions: [
          if (canPublish)
            IconButton(
              key: const Key('announcements-new'),
              tooltip: S.announcementNew,
              icon: const Icon(Icons.add_rounded),
              onPressed: () => context.push(AnnouncementComposePage.routePath),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        // A session with no publish grant anywhere gets a designed state, not
        // a bounce: it may well hold `detachment.view` and read every one of
        // these notices in the Notifications Center. What it cannot do is stop
        // one, and that is what this screen says.
        child: canPublish
            ? const _ManageList()
            : const EmptyState(
                key: Key('announcements-restricted'),
                icon: Icons.lock_outline_rounded,
                title: S.announcementsRestrictedTitle,
                body: S.announcementsRestrictedBody,
              ),
      ),
    );
  }
}

class _ManageList extends ConsumerWidget {
  const _ManageList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capabilitiesProvider);
    final now = ref.watch(clockProvider)();

    return AppRefreshIndicator(
      onRefresh: () async {
        ref.invalidate(announcementListProvider);
        await ref.read(announcementListProvider.future);
      },
      child: AsyncResultView<List<Announcement>>(
        value: ref.watch(announcementListProvider),
        onRetry: () => ref.invalidate(announcementListProvider),
        builder: (context, all, stale) {
          // Narrowed here rather than in the repository, through the same
          // resolver every other check uses: an announcement is manageable
          // where its author's key is held, in one of the detachments it names.
          final rows = manageableAnnouncements(
            [
              for (final a in all)
                if (canManageAnnouncement(a, caps)) a,
            ],
            now,
          );

          if (rows.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
              children: const [
                EmptyState(
                  key: Key('announcements-empty'),
                  icon: Icons.campaign_outlined,
                  title: S.announcementsEmptyTitle,
                  body: S.announcementsEmptyBody,
                ),
              ],
            );
          }

          return ListView.builder(
            key: const Key('announcements-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            itemCount: rows.length,
            itemBuilder: (context, i) => Stagger(
              index: i,
              child: _AnnouncementCard(announcement: rows[i], now: now),
            ),
          );
        },
      ),
    );
  }
}

class _AnnouncementCard extends ConsumerWidget {
  const _AnnouncementCard({required this.announcement, required this.now});

  final Announcement announcement;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final a = announcement;
    final active = isAnnouncementActive(a, now);
    final promoted = isPromotedOnHome(a, now);
    final busy = ref.watch(announcementControllerProvider).isWithdrawing(a.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        key: Key('announcement-card-${a.id}'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A Wrap, not a Row with a Spacer: two chips and a timestamp
            // overflow a narrow phone in Arabic, and a header that clips is a
            // header that hides which of "stopped" and "ended" happened.
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusChip(
                  kind: active ? StatusKind.ok : StatusKind.muted,
                  label: announcementStateLabel(a, now),
                ),
                if (promoted)
                  const StatusChip(
                    kind: StatusKind.info,
                    label: S.announcementOnHomeNow,
                  ),
                Text(
                  AppDate.dayMonthTime(a.publishedAt),
                  style: TextStyle(color: c.ink3, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              a.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.ink, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${announcementTargetsLabel(a.detachmentIds.length)} · '
              '${announcementEndsLabel(a)}',
              style: TextStyle(color: c.ink3, fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.sm),
            // A Wrap for the same reason the header is one: «إيقاف الإعلان»
            // beside «التفاصيل» does not fit a narrow phone, and two buttons on
            // two lines is better than one button clipped off the edge.
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  key: Key('announcement-open-${a.id}'),
                  onPressed: () =>
                      showAnnouncementSheet(context: context, announcement: a),
                  child: const Text(S.details),
                ),
                // Only an announcement that is still being delivered can be
                // stopped. An expired or already-withdrawn one renders no
                // button rather than an inert one.
                if (active)
                  TextButton(
                    key: Key('announcement-withdraw-${a.id}'),
                    onPressed:
                        busy ? null : () => _confirmWithdraw(context, ref),
                    style: TextButton.styleFrom(foregroundColor: c.crit),
                    child: const Text(S.announcementWithdraw),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmWithdraw(BuildContext context, WidgetRef ref) async {
    final c = context.c;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(S.announcementWithdrawTitle),
        content: const Text(S.announcementWithdrawBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(S.cancel),
          ),
          TextButton(
            key: const Key('announcement-withdraw-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: c.crit),
            child: const Text(S.announcementWithdraw),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final outcome = await ref
        .read(announcementControllerProvider.notifier)
        .withdraw(announcement.id);
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    switch (outcome) {
      case AnnouncementSaved():
        messenger.showSnackBar(
          const SnackBar(content: Text(S.announcementWithdrawn)),
        );
      case AnnouncementFailed(:final message):
        // The announcement is still active and the list still says so — the
        // failure changed nothing, which is exactly what the row must keep
        // showing.
        messenger.showSnackBar(SnackBar(content: Text(message)));
      case AnnouncementOffline():
        messenger.showSnackBar(
          const SnackBar(content: Text(S.announcementNeedsConnection)),
        );
      case AnnouncementRefusedOutcome(:final reason):
        messenger.showSnackBar(
          SnackBar(content: Text(announcementRefusalMessage(reason))),
        );
      case AnnouncementIgnored():
        break;
    }
  }
}
