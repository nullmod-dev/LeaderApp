import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/access/capability.dart';
import '../../../core/format/app_date.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/clock.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../../detachment/data/detachment_providers.dart';
import '../../detachment/domain/detachment_models.dart';
import '../data/announcement_providers.dart';
import '../domain/announcement_models.dart';
import '../domain/announcement_selectors.dart';
import 'announcement_copy.dart';

/// The full announcement, read-only.
///
/// **A context view, not navigation.** A notification row shows two lines of a
/// notice that may run to several; opening one has to give the reader the rest
/// of the words, not send them into a detachment the notice merely happened to
/// name. That is the whole reason `OpenAnnouncement` exists as a destination
/// separate from every other one in `notification_selectors.dart`: an
/// announcement addressed to three detachments has no single place to go, and
/// picking one of them arbitrarily is exactly the behaviour Point 14 §21
/// forbids.
///
/// It resolves the announcement **at the moment it is opened**, so a notice
/// withdrawn or cleared between the feed loading and the tap ends in a sentence
/// rather than a stale screen — the caller handles that, see [openAnnouncement].
Future<void> showAnnouncementSheet({
  required BuildContext context,
  required Announcement announcement,
}) {
  return showAppSheet<void>(
    context: context,
    title: S.announcementLabel,
    child: _AnnouncementBody(announcement: announcement),
  );
}

/// Re-reads [announcementId] and shows it, or reports that it is gone.
///
/// Returns true when the sheet was shown. The false case is the stale-pointer
/// path every destination in this app has to handle: no crash, no dead end, no
/// unrelated content — one sentence and the list refreshes behind it.
Future<bool> openAnnouncement(
  BuildContext context,
  WidgetRef ref,
  String announcementId,
) async {
  final result =
      await ref.read(announcementRepositoryProvider).byId(announcementId);
  if (!context.mounted) return false;

  final announcement = result.when(
    success: (Announcement data, {bool stale = false}) => data,
    failure: (_, __) => null,
    offline: (cached) => cached,
  );
  if (announcement == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(S.announcementGone)),
    );
    return false;
  }

  await showAnnouncementSheet(context: context, announcement: announcement);
  return true;
}

class _AnnouncementBody extends ConsumerWidget {
  const _AnnouncementBody({required this.announcement});

  final Announcement announcement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final now = ref.watch(clockProvider)();
    final active = isAnnouncementActive(announcement, now);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            StatusChip(
              key: const Key('announcement-state-chip'),
              kind: announcement.isWithdrawn
                  ? StatusKind.muted
                  : active
                      ? StatusKind.ok
                      : StatusKind.muted,
              label: announcementStateLabel(announcement, now),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                AppDate.dayMonthTime(announcement.publishedAt),
                style: TextStyle(color: c.ink3, fontSize: 12),
              ),
            ),
          ]),
          const SizedBox(height: AppSpacing.lg),
          // The notice itself, unabridged and unstyled. Plain text is the whole
          // content model — there is nothing here to render but the words.
          SelectableText(
            announcement.text,
            key: const Key('announcement-sheet-text'),
            style: TextStyle(color: c.ink, fontSize: 15, height: 1.6),
          ),
          const SizedBox(height: AppSpacing.xl),
          _MetaRow(
            icon: Icons.flag_outlined,
            label: S.announcementTargets,
            child: _TargetNames(ids: announcement.detachmentIds),
          ),
          const SizedBox(height: AppSpacing.md),
          _MetaRow(
            icon: Icons.schedule_rounded,
            label: S.announcementDuration,
            child: Text(
              announcementEndsLabel(announcement),
              style: TextStyle(color: c.ink2, fontSize: 13),
            ),
          ),
          if (announcement.authorName != null) ...[
            const SizedBox(height: AppSpacing.md),
            _MetaRow(
              icon: Icons.person_outline_rounded,
              label: S.settingsProfile,
              child: Text(
                announcement.authorName!,
                style: TextStyle(color: c.ink2, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Detachment **names**, never ids.
///
/// Resolved one at a time through the provider the rest of the app reads, so a
/// detachment that has since been renamed reads with its current name and one
/// that can no longer be read falls back to nothing rather than leaking an
/// internal id onto the screen.
class _TargetNames extends ConsumerWidget {
  const _TargetNames({required this.ids});

  final List<String> ids;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final names = <String>[
      for (final id in ids)
        ref.watch(detachmentByIdProvider(id)).whenOrNull(
                  data: (r) => r.when(
                    success: (Detachment d, {bool stale = false}) => d.name,
                    failure: (_, __) => null,
                    offline: (cached) => cached?.name,
                  ),
                ) ??
            '',
    ]..removeWhere((n) => n.isEmpty);

    return Text(
      names.isEmpty ? announcementTargetsLabel(ids.length) : names.join('، '),
      style: TextStyle(color: c.ink2, fontSize: 13, height: 1.5),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: c.ink3),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 96,
          child: Text(label, style: TextStyle(color: c.ink3, fontSize: 12)),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// The capability an announcement's management controls rest on. Exported so
/// the management list and the compose form name one key rather than two.
const String announcementManageCapability = Cap.announcementPublish;
