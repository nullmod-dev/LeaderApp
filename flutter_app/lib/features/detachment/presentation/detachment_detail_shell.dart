import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/capability.dart';
import '../../../core/access/capability_guard.dart';
import '../../../core/motion/transitions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/animated_tab_bar.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/swipe_tabs.dart';
import '../../../l10n/strings.dart';
import '../../announcement/presentation/widgets/detachment_announcement_strip.dart';
import '../../inventory/data/inventory_providers.dart';
import '../../inventory/domain/inventory_models.dart';
import '../../detachment_group/data/detachment_group_providers.dart';
import '../../detachment_group/domain/detachment_group_models.dart';
import '../data/detachment_providers.dart';
import '../domain/detachment_models.dart';
import '../domain/detachment_tabs.dart';
import '../domain/storage_status.dart';
import '../../tenant_feature/data/tenant_feature_providers.dart';
import '../../tenant_feature/domain/tenant_feature_models.dart';

/// Shell around a single detachment: the detachment name with the detachment
/// group it belongs to underneath it, a persistent tab bar, and the active tab
/// body.
///
/// The detachment group line is not decoration. Two detachments in different
/// detachment groups can share a name, and the person looking at the screen has
/// to be able to tell which container they are working inside before they
/// change anything.
class DetachmentDetailShell extends ConsumerWidget {
  const DetachmentDetailShell({
    super.key,
    required this.detachmentId,
    required this.location,
    required this.child,
  });

  final String detachmentId;
  final String location;
  final Widget child;

  static const _tabs = [
    (path: 'team', label: S.detachmentTeam),
    (path: 'shifts', label: S.detachmentShifts),
    (path: 'storage', label: S.detachmentStorage),
    (path: 'stats', label: S.detachmentStats),
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
    final inventoryEnabled = ref.watch(
      tenantFeatureAvailableProvider(TenantFeatureKey.inventory),
    );
    final statisticsEnabled = ref.watch(
      tenantFeatureAvailableProvider(TenantFeatureKey.statisticsReports),
    );
    final announcementsEnabled = ref.watch(
      tenantFeatureAvailableProvider(TenantFeatureKey.announcements),
    );
    // Two separate axes, applied in the canonical order: the module must exist
    // for this organisation (Feature Flag), then this session must be able to
    // open the tab (capability). A tab the grant does not open is not offered
    // — the roster's route would bounce the session to Home, and a statistics
    // tab without `stats.view` only ever shows its denied state. The tab the
    // session is *standing on* is always kept, so a direct link or a grant
    // narrowing mid-session never leaves the bar with nothing selected; the
    // route guard, not the bar, is what refuses it.
    final caps = ref.watch(capabilitiesProvider);
    final tabs = [
      for (final tab in _tabs)
        if (tab.path != 'storage' || inventoryEnabled)
          if (tab.path != 'stats' || statisticsEnabled)
            if (location.endsWith('/${tab.path}') ||
                detachmentTabOffered(caps, detachmentId, tab.path))
              tab,
    ];
    final detachment =
        ref.watch(detachmentByIdProvider(detachmentId)).whenOrNull(
              data: (r) => r.when(
                success: (Detachment d, {bool stale = false}) => d,
                failure: (_, __) => null,
                offline: (cached) => cached,
              ),
            );
    final detachmentGroupName = detachment == null
        ? null
        : ref
            .watch(detachmentGroupByIdProvider(detachment.detachmentGroupId))
            .whenOrNull(
              data: (r) => r.when(
                success: (DetachmentGroup t, {bool stale = false}) => t.name,
                failure: (_, __) => null,
                offline: (cached) => cached?.name,
              ),
            );

    // Resolved through `DetachmentAccess`, so an archived detachment closes
    // the same controls here that it closes inside the tabs. The lifecycle
    // key survives archiving on purpose — it is the key that undoes it.
    final onEdit = ref.accessIn(detachmentId).canAny(
      const {Cap.detachmentEdit, Cap.detachmentArchive},
    )
        ? () => context.push('/detachment/$detachmentId/edit')
        : null;

    final idx = _currentIndexFromLocation(tabs);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(detachment?.name ?? '...',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (detachmentGroupName != null)
              Text('${S.belongsTo} $detachmentGroupName',
                  style: TextStyle(color: c.ink3, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          // The route behind this refuses the same two keys, so the button
          // was never a way in — but a control that opens a form nothing on
          // it can save is exactly the dead affordance the house rule forbids.
          if (onEdit != null)
            IconButton(
              key: const Key('detachment-edit-action'),
              tooltip: S.editDetachment,
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
        ],
      ),
      body: Column(children: [
        _StatusStrip(detachmentId: detachmentId, detachment: detachment),
        // The detachment-level announcement placement. Under the status strip
        // and above the tab bar, so it is on every tab and belongs to the
        // detachment rather than to one of its sections. Renders nothing when
        // no announcement is placed here, which is the ordinary case.
        if (announcementsEnabled)
          DetachmentAnnouncementStrip(detachmentId: detachmentId),
        AnimatedTabBar(
          tabs: tabs.map((t) => t.label).toList(),
          currentIndex: idx,
          onChanged: (i) => context.go(
            '/detachment/$detachmentId/${tabs[i].path}',
          ),
        ),
        Expanded(
          child: SwipeTabs(
            currentIndex: idx,
            tabCount: tabs.length,
            onSwitch: (i) =>
                context.go('/detachment/$detachmentId/${tabs[i].path}'),
            child: TabSwitchTransition(index: idx, child: child),
          ),
        ),
      ]),
    );
  }
}

/// The thin line under the app bar, on every tab: where this detachment
/// stands right now.
///
/// Two facts, because they answer two different questions a lead opens the
/// screen with. The lifecycle chip (نشطة / مفرزة منتهية) is the one the
/// legacy details header carried, and a finished detachment adds a second,
/// equally quiet chip saying the screen is read-only — that is the whole
/// visual treatment history gets, because a completed record is not an error.
/// The storage chip is new — a worst-wins rollup of the stock the detachment
/// holds, so "something is wrong in the store" is visible without opening the
/// storage tab.
class _StatusStrip extends ConsumerWidget {
  const _StatusStrip({required this.detachmentId, required this.detachment});

  final String detachmentId;
  final Detachment? detachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;

    // Null while the detachment itself is still loading — the strip stays
    // empty rather than guessing a lifecycle state.
    if (detachment == null) return const SizedBox.shrink();

    final archived = detachment!.status == DetachmentStatus.archived;

    final inventoryEnabled = ref.watch(
      tenantFeatureAvailableProvider(TenantFeatureKey.inventory),
    );
    final stock = inventoryEnabled
        ? ref.watch(inventoryListProvider(detachmentId)).whenOrNull(
              data: (r) => r.when(
                success: (List<InventoryItem> items, {bool stale = false}) =>
                    items,
                failure: (_, __) => null,
                offline: (cached) => cached,
              ),
            )
        : null;
    final storage = stock == null ? null : storageStatusOf(stock);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          StatusChip(
            key: const Key('detachment-lifecycle-chip'),
            kind: archived ? StatusKind.muted : StatusKind.ok,
            label: archived ? S.historicalDetachment : S.statusActive,
          ),
          // Calm, not a warning: a finished detachment is a normal record,
          // and the only thing worth saying about it is that nothing on the
          // screen will change it.
          if (archived)
            const StatusChip(
              key: Key('detachment-read-only-chip'),
              kind: StatusKind.muted,
              label: S.historicalReadOnly,
            ),
          if (storage != null)
            StatusChip(
              kind: _storageKind(storage),
              label: _storageLabel(storage),
            ),
        ],
      ),
    );
  }

  StatusKind _storageKind(StorageStatus s) => switch (s) {
        StorageStatus.healthy => StatusKind.ok,
        StorageStatus.expiring => StatusKind.warn,
        StorageStatus.low => StatusKind.warn,
        StorageStatus.depleted => StatusKind.crit,
        StorageStatus.empty => StatusKind.muted,
      };

  String _storageLabel(StorageStatus s) => switch (s) {
        StorageStatus.healthy => S.storageStatusHealthy,
        StorageStatus.expiring => S.storageStatusExpiring,
        StorageStatus.low => S.storageStatusLow,
        StorageStatus.depleted => S.storageStatusDepleted,
        StorageStatus.empty => S.storageStatusEmpty,
      };
}
