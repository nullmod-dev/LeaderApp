import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/capability.dart';
import '../../../core/access/capability_guard.dart';
import '../../../core/motion/transitions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/animated_tab_bar.dart';
import '../../../core/widgets/confirmation_dialog.dart';
import '../../../core/widgets/swipe_tabs.dart';
import '../../../l10n/strings.dart';
import '../data/workshop_providers.dart';
import 'widgets/workshop_people.dart';
import '../../tenant_feature/data/tenant_feature_providers.dart';
import '../../tenant_feature/domain/tenant_feature_models.dart';

/// Shell around a single workshop: title, the three tabs, and the active tab
/// body. Mirrors `DetachmentDetailShell` deliberately — the two detail
/// surfaces must feel identical.
class WorkshopDetailShell extends ConsumerWidget {
  const WorkshopDetailShell({
    super.key,
    required this.workshopId,
    required this.location,
    required this.child,
  });

  final String workshopId;
  final String location;
  final Widget child;

  static const _tabs = [
    (path: 'team', label: S.workshopTeam),
    (path: 'members', label: S.workshopMembers),
    (path: 'stats', label: S.workshopStats),
  ];

  int _currentIndexFromLocation(List<({String path, String label})> tabs) {
    for (int i = 0; i < tabs.length; i++) {
      if (location.endsWith('/${tabs[i].path}')) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final statisticsEnabled = ref.watch(
      tenantFeatureAvailableProvider(TenantFeatureKey.statisticsReports),
    );
    final tabs = [
      for (final tab in _tabs)
        if (tab.path != 'stats' || statisticsEnabled) tab,
    ];
    final async = ref.watch(workshopByIdProvider(workshopId));
    final mode = ref.watch(workshopModeProvider(workshopId));
    final archived = mode == WorkshopMode.archived;
    final idx = _currentIndexFromLocation(tabs);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: async.when(
          loading: () => const Text('...'),
          error: (_, __) => const Text(S.errTitle),
          data: (r) => r.when(
            success: (w, {stale = false}) => Text(w.name),
            failure: (_, __) => const Text(S.errTitle),
            offline: (cached) => Text(cached?.name ?? '...'),
          ),
        ),
        actions: [
          if (!archived)
            IconButton(
              tooltip: S.editWorkshop,
              icon: const Icon(Icons.edit_outlined),
              onPressed: ref.whenCan(
                Cap.workshopEdit,
                () => context.push('/workshop/$workshopId/edit'),
              ),
            ),
          if (mode != WorkshopMode.unknown)
            IconButton(
              tooltip: archived ? S.workshopRestore : S.workshopArchive,
              icon: Icon(
                  archived ? Icons.unarchive_outlined : Icons.archive_outlined),
              onPressed: ref.whenCan(
                Cap.workshopArchive,
                () => _setArchived(context, ref, archived: !archived),
              ),
            ),
        ],
      ),
      body: Column(children: [
        if (archived) const _ArchivedBanner(),
        AnimatedTabBar(
          tabs: tabs.map((t) => t.label).toList(),
          currentIndex: idx,
          onChanged: (i) => context.go('/workshop/$workshopId/${tabs[i].path}'),
        ),
        Expanded(
          child: SwipeTabs(
            currentIndex: idx,
            tabCount: tabs.length,
            onSwitch: (i) =>
                context.go('/workshop/$workshopId/${tabs[i].path}'),
            child: TabSwitchTransition(index: idx, child: child),
          ),
        ),
      ]),
    );
  }

  /// Archiving asks first — it closes every control on the workshop until
  /// somebody restores it. Restoring does not: it only gives the controls
  /// back.
  Future<void> _setArchived(
    BuildContext context,
    WidgetRef ref, {
    required bool archived,
  }) async {
    if (archived) {
      final go = await showAppConfirmation(
        context: context,
        title: S.workshopArchive,
        change: S.workshopArchiveChange,
        unchanged: S.workshopArchiveUnchanged,
        confirmLabel: S.workshopArchive,
        // Warning, not destructive: archiving closes the workshop to edits
        // and «استعادة الورشة» undoes it. Nothing is deleted.
        severity: ConfirmationSeverity.warning,
      );
      if (!go || !context.mounted) return;
    }
    final result = await ref
        .read(workshopRepositoryProvider)
        .setArchived(workshopId, archived: archived);
    if (!context.mounted) return;
    refreshWorkshop(ref, workshopId);
    reportWorkshopResult(
      context,
      result,
      success: archived ? S.workshopArchivedOk : S.workshopRestoredOk,
    );
  }
}

/// Says the workshop is closed to changes, once, at the top — rather than
/// leaving the user to discover it control by control.
class _ArchivedBanner extends StatelessWidget {
  const _ArchivedBanner();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      color: c.mutedTint,
      child: Row(children: [
        Icon(Icons.inventory_2_outlined, size: 18, color: c.ink3),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            S.workshopArchivedBanner,
            style: TextStyle(color: c.ink2, fontSize: 12),
          ),
        ),
      ]),
    );
  }
}
