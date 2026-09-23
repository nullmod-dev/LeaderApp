import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/reading_column.dart';
import '../../../l10n/strings.dart';
import '../../shell/main_shell.dart';
import 'widgets/sync_settings_section.dart';

/// The Sync Center (`/more/sync`) — one screen that answers "is my work
/// saved and sent?", and the single destination the dashboard's sync alerts
/// and the sync notifications lead to.
///
/// It hosts [SyncSettingsSection] inside its own scaffold and nothing else:
/// the status, the last successful sync, the counts, the one sync button and
/// the quiet Needs Review row all live in that one card, over the one outbox
/// and the one coordinator both sync paths use. Its loading and failure
/// states live there too, so this screen has no state of its own to get out
/// of step. Auto Sync still never navigates; Manual Sync still never
/// force-opens a conflict; the attention row still opens Needs Review only
/// on an explicit tap.
class SyncPage extends StatelessWidget {
  const SyncPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text(S.sectionSync)),
      // One column of label↔value rows: capped at the reading measure so a
      // tablet gains margins instead of a row whose label and value sit at
      // opposite ends of the window. Below 520 dp nothing changes.
      body: FloatingNavPadding(
        child: ReadingColumn(
            child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: const [SyncSettingsSection()],
        )),
      ),
    );
  }
}
