import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/forward_chevron.dart';
import '../../../../l10n/strings.dart';
import '../../data/announcement_providers.dart';
import '../announcement_copy.dart';
import '../announcement_sheet.dart';

/// The detachment-level placement: one line under the detachment's status
/// strip, on every tab, while an announcement placed there is still active.
///
/// **No new detachment submodule.** The detachment surface already carries a
/// thin status strip that answers "where does this detachment stand"; a notice
/// addressed to it belongs in the same band, at the same weight, and disappears
/// the moment the announcement expires or is withdrawn. Nothing about the
/// tabs, the tab bar or any tab's content changes — when there is nothing to
/// show, this renders nothing and the shell is exactly what it was.
///
/// Unlike the Home promotion this one has no one-hour clock: it lasts as long
/// as the announcement's own expiry, which is what "داخل المفرزة" tells the
/// author it will do.
class DetachmentAnnouncementStrip extends ConsumerWidget {
  const DetachmentAnnouncementStrip({super.key, required this.detachmentId});

  final String detachmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final rows = ref.watch(detachmentAnnouncementsProvider(detachmentId));
    if (rows.isEmpty) return const SizedBox.shrink();

    final top = rows.first;
    final others = rows.length - 1;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => showAnnouncementSheet(context: context, announcement: top),
        child: Container(
          key: const Key('detachment-announcement'),
          width: double.infinity,
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: c.infoTint,
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.campaign_outlined, size: 16, color: c.info),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      top.text,
                      // Two lines here, not three: this band sits above the tab
                      // bar and the tab's own content, and it must not become
                      // the thing the screen is about.
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.ink,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                    if (others > 0)
                      Text(
                        announcementHomeMoreLabel(others),
                        style: TextStyle(color: c.info, fontSize: 11),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: ForwardChevron(size: 18, semanticLabel: S.details),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
