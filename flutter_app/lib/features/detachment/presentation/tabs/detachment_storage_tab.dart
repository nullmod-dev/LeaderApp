import '../../../../core/widgets/filter_chips.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/access/capability.dart';
import '../../../../core/format/app_time.dart';
import '../../../../core/motion/animated_counter.dart';
import '../../../../core/motion/press_scale.dart';
import '../../../../core/motion/stagger.dart';
import '../../../../core/sync/outbox_controller.dart';
import '../../../../core/sync/sync_scheduler.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/async_result.dart';
import '../../../../core/widgets/app_meta.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/refresh_indicator.dart';
import '../../../../core/widgets/sheet_scaffold.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../l10n/strings.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../inventory/data/inventory_providers.dart';
import '../../../inventory/domain/inventory_format.dart';
import '../../../inventory/domain/inventory_models.dart';
import '../../../shell/main_shell.dart';
import '../../data/detachment_providers.dart';

/// Stock held by one detachment.
///
/// Three filters, because the two questions anyone actually opens this screen
/// with are "what do I need to reorder" and "what is about to expire" — a
/// plain alphabetical list answers neither without reading every row.
class DetachmentStorageTab extends ConsumerStatefulWidget {
  const DetachmentStorageTab({super.key, required this.detachmentId});

  final String detachmentId;

  @override
  ConsumerState<DetachmentStorageTab> createState() => _StorageTabState();
}

enum _StockFilter { all, low, expiring }

String _packagingUnitLabel(PackagingUnit unit) => switch (unit) {
      PackagingUnit.individual => S.packagingIndividual,
      PackagingUnit.strip => S.packagingStrip,
      PackagingUnit.carton => S.packagingCarton,
    };

class _StorageTabState extends ConsumerState<DetachmentStorageTab> {
  final _search = TextEditingController();
  _StockFilter _filter = _StockFilter.all;
  String _query = '';

  String get detachmentId => widget.detachmentId;

  /// Thirty days is the reorder horizon used everywhere in this screen — the
  /// card's amber expiry text uses the same number, so the filter and the
  /// warning colour can never disagree.
  static const int _expiringWithinDays = 30;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<InventoryItem> _apply(List<InventoryItem> items) {
    Iterable<InventoryItem> out = items;
    if (_query.trim().isNotEmpty) {
      final q = _query.trim();
      out = out.where((i) => i.name.contains(q) || i.unit.contains(q));
    }
    out = switch (_filter) {
      _StockFilter.all => out,
      _StockFilter.low => out.where((i) => i.level != StockLevel.ok),
      _StockFilter.expiring => out.where((i) {
          final d = i.daysToExpiry;
          return d != null && d <= _expiringWithinDays;
        }),
    };
    return out.toList();
  }

  @override
  Widget build(BuildContext context) {
    // A finished detachment's store is a record of what it held, so both
    // keys resolve through `DetachmentAccess`: the movement history stays
    // readable and nothing on the screen can add to it.
    final access = ref.accessIn(detachmentId);
    final canAdjust = access.can(Cap.inventoryAdjust);
    final onAdd = access.when(
      Cap.inventoryItemManage,
      () => context.push('/detachment/$detachmentId/storage/new'),
    );

    return AppRefreshIndicator(
      onRefresh: () => ref.refresh(inventoryListProvider(detachmentId).future),
      child: AsyncResultView<List<InventoryItem>>(
        value: ref.watch(inventoryListProvider(detachmentId)),
        onRetry: () => ref.invalidate(inventoryListProvider),
        builder: (context, all, stale) {
          if (all.isEmpty) {
            // "أضف صنفا لتبدأ" is an instruction, and there is nothing to
            // start on a detachment that has ended — so history says what it
            // actually knows instead.
            return EmptyState(
              key: const Key('inventory-empty'),
              icon: Icons.inventory_2_outlined,
              title: access.isHistorical
                  ? S.historicalEmptyInventory
                  : S.emptyInventory,
              body: access.isHistorical
                  ? S.historicalEmptyInventorySub
                  : S.emptyInventorySub,
              actionLabel: onAdd == null ? null : S.addItem,
              onAction: onAdd,
            );
          }
          final items = _apply(all);
          return FloatingNavPadding(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
              children: [
                TextField(
                  key: const Key('inventory-search'),
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: S.searchItems,
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: S.membersClearSearch,
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                // The add action keeps its place at the end of the row; the
                // three filters wrap under it, so a longer filter label at a
                // large text scale never pushes the one control that creates
                // something off the screen — and no filter is ever clipped
                // out of reach, which is what the horizontal scroll this
                // replaced did at 320 dp.
                Row(children: [
                  Expanded(
                    child: AppFilterBar(
                      semanticLabel: S.filterByStatus,
                      children: [
                        AppFilterChip(
                          label: S.filterAll,
                          selected: _filter == _StockFilter.all,
                          onSelected: (_) =>
                              setState(() => _filter = _StockFilter.all),
                        ),
                        AppFilterChip(
                          label: S.filterLow,
                          selected: _filter == _StockFilter.low,
                          onSelected: (_) =>
                              setState(() => _filter = _StockFilter.low),
                        ),
                        AppFilterChip(
                          label: S.filterExpiring,
                          selected: _filter == _StockFilter.expiring,
                          onSelected: (_) =>
                              setState(() => _filter = _StockFilter.expiring),
                        ),
                      ],
                    ),
                  ),
                  if (onAdd != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    _AddButton(onTap: onAdd),
                  ],
                ]),
                const SizedBox(height: AppSpacing.md),
                if (items.isEmpty)
                  EmptyState(
                    key: const Key('inventory-no-results'),
                    icon: Icons.search_off_rounded,
                    title: S.noMatchingInventory,
                    body: S.noMatchingInventorySub,
                    actionLabel: S.clearInventoryFilters,
                    onAction: () => setState(() {
                      _query = '';
                      _search.clear();
                      _filter = _StockFilter.all;
                    }),
                  )
                else
                  for (int i = 0; i < items.length; i++) ...[
                    Stagger(
                      index: i,
                      child: _ItemCard(
                        item: items[i],
                        onTap: () =>
                            _itemSheet(context, ref, items[i], canAdjust),
                      ),
                    ),
                    if (i != items.length - 1) const SizedBox(height: 10),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _itemSheet(BuildContext context, WidgetRef ref,
          InventoryItem item, bool canAdjust) =>
      showInventoryItemSheet(
        context: context,
        detachmentId: detachmentId,
        item: item,
        canAdjust: canAdjust,
      );
}

/// Everything you can do to **one** stock item, opened by tapping its card.
///
/// Public because the storage tab is no longer the only way in: Global Search
/// opens the same sheet for an item result rather than growing a second stock
/// screen of its own. The body is unchanged — it invalidates the inventory
/// providers on a write and pushes the item form through the router, so it
/// behaves identically whichever surface opened it.
Future<void> showInventoryItemSheet({
  required BuildContext context,
  required String detachmentId,
  required InventoryItem item,
  required bool canAdjust,
}) =>
    showAppSheet<void>(
      context: context,
      title: item.name,
      child: _ItemSheetBody(
        detachmentId: detachmentId,
        item: item,
        canAdjust: canAdjust,
      ),
    );

StatusKind _kindFor(StockLevel level) => switch (level) {
      StockLevel.ok => StatusKind.ok,
      StockLevel.low => StatusKind.warn,
      StockLevel.empty => StatusKind.crit,
    };

String _labelFor(StockLevel level) => switch (level) {
      StockLevel.ok => S.stockOk,
      StockLevel.low => S.stockLowLabel,
      StockLevel.empty => S.stockEmpty,
    };

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, required this.onTap});

  final InventoryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final days = item.daysToExpiry;
    return PressScale(
      onTap: onTap,
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
              Expanded(
                child: Text(item.name,
                    style: TextStyle(
                        color: c.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w500)),
              ),
              StatusChip(
                  kind: _kindFor(item.level), label: _labelFor(item.level)),
            ]),
            const SizedBox(height: AppSpacing.sm),
            // Three facts of unpredictable width — a quantity, a unit name,
            // and an expiry phrase. They wrap rather than compete for one
            // line, so a long unit ("أسطوانة") cannot clip the expiry
            // warning beside it.
            AppMeta(
              parts: [
                AppMetaText(stockBreakdownLabel(item), emphasis: true),
                AppMetaText.total(S.minimumLevel, item.minimum),
                AppMetaText(
                  item.expiresOn == null
                      ? S.noExpiry
                      : days != null && days < 0
                          ? S.expired
                          : '${toArabicIndic('${days ?? 0}')} ${S.daysToExpiry}',
                  color: days != null &&
                          days <= _StorageTabState._expiringWithinDays
                      ? c.warn
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemSheetBody extends ConsumerStatefulWidget {
  const _ItemSheetBody({
    required this.detachmentId,
    required this.item,
    required this.canAdjust,
  });

  final String detachmentId;
  final InventoryItem item;
  final bool canAdjust;

  @override
  ConsumerState<_ItemSheetBody> createState() => _ItemSheetBodyState();
}

class _ItemSheetBodyState extends ConsumerState<_ItemSheetBody> {
  final _quantity = TextEditingController();
  final _reason = TextEditingController();
  MovementDirection _direction = MovementDirection.outflow;
  late PackagingUnit _packagingUnit;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _packagingUnit = widget.item.packaging.supports(widget.item.preferredUnit)
        ? widget.item.preferredUnit
        : PackagingUnit.individual;
  }

  List<PackagingUnit> get _availableUnits => [
        for (final unit in PackagingUnit.values)
          if (widget.item.packaging.supports(unit)) unit,
      ];

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final movements = ref.watch(inventoryMovementsProvider(widget.item.id));
    // Editing the item's definition is a different capability from moving its
    // stock: a medic logs a dispense, a lead decides what the detachment
    // stocks at all.
    final onEdit = ref.accessIn(widget.detachmentId).when(
      Cap.inventoryItemManage,
      () {
        Navigator.of(context).pop();
        context.push(
          '/detachment/${widget.detachmentId}/storage/${widget.item.id}/edit',
        );
      },
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: AppMeta(
                parts: [
                  AppMetaText(
                    '${S.currentStock}: ${stockBreakdownLabel(widget.item)}',
                    emphasis: true,
                  ),
                  AppMetaText.total(
                    '${S.minimumLevel} ${S.baseUnits}',
                    widget.item.minimum,
                  ),
                ],
              ),
            ),
            if (onEdit != null)
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text(S.edit),
                style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          if (widget.canAdjust) ...[
            Row(children: [
              Expanded(
                child: _DirectionButton(
                  label: S.movementIn,
                  icon: Icons.south_west_rounded,
                  selected: _direction == MovementDirection.inflow,
                  onTap: () =>
                      setState(() => _direction = MovementDirection.inflow),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _DirectionButton(
                  label: S.movementOut,
                  icon: Icons.north_east_rounded,
                  selected: _direction == MovementDirection.outflow,
                  onTap: () =>
                      setState(() => _direction = MovementDirection.outflow),
                ),
              ),
            ]),
            const SizedBox(height: AppSpacing.md),
            Text(S.packagingUnit,
                style: TextStyle(color: c.ink2, fontSize: 13)),
            const SizedBox(height: AppSpacing.sm),
            Row(children: [
              // Only the packaging this item is configured for. Offering
              // "carton" on a medicine with no carton size would record a
              // quantity that means something other than what it says.
              for (final unit in _availableUnits) ...[
                Expanded(
                  child: _DirectionButton(
                    label: _packagingUnitLabel(unit),
                    icon: switch (unit) {
                      PackagingUnit.individual => Icons.medication_outlined,
                      PackagingUnit.strip => Icons.view_week_outlined,
                      PackagingUnit.carton => Icons.inventory_2_outlined,
                    },
                    selected: _packagingUnit == unit,
                    onTap: () => setState(() => _packagingUnit = unit),
                  ),
                ),
                if (unit != _availableUnits.last)
                  const SizedBox(width: AppSpacing.xs),
              ],
            ]),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _quantity,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: S.quantity,
                hintText: S.quantityPlaceholder,
              ),
            ),
            if (_enteredQuantity != null && _enteredQuantity! > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${S.convertedQuantity}: '
                '${toArabicIndic('${widget.item.packaging.baseUnitsFor(_enteredQuantity!, _packagingUnit)}')} '
                '${S.baseUnits}',
                style: TextStyle(color: c.ink3, fontSize: 12),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(
                labelText: S.reason,
                hintText: S.reasonPlaceholder,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _record,
                child: const Text(S.record),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          Text(S.itemMovements,
              style: TextStyle(
                  color: c.ink3, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.sm),
          AsyncResultView<List<InventoryMovement>>(
            value: movements,
            onRetry: () => ref.invalidate(inventoryMovementsProvider),
            loading: const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
            builder: (context, list, stale) => list.isEmpty
                ? Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Text(S.noMovements,
                        style: TextStyle(color: c.ink3, fontSize: 13)),
                  )
                : Column(
                    children: [
                      for (final m in list) _MovementRow(movement: m),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  int? get _enteredQuantity =>
      int.tryParse(toWesternDigits(_quantity.text.trim()));

  Future<void> _record() async {
    final qty = _enteredQuantity;
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(S.positiveIntegerRequired)));
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final user = ref.read(currentUserProvider).valueOrNull;
    final result = await ref.read(inventoryRepositoryProvider).addMovement(
          itemId: widget.item.id,
          direction: _direction,
          quantity: qty,
          packagingUnit: _packagingUnit,
          source: 'mobile_app',
          performedBy: user?.id,
          performedByName: user?.name,
          reason: _reason.text.trim().isEmpty
              ? S.movementSheet
              : _reason.text.trim(),
        );
    ref.invalidate(inventoryListProvider);
    ref.invalidate(inventoryMovementsProvider);
    if (!mounted) return;
    setState(() => _saving = false);
    await result.when(
      // Local-first: the write is stored, so the user is done here. Register
      // the movement as pending synchronisation (the outbox is the single
      // source both Auto and Manual Sync drain — it is NOT a second write
      // path), nudge a background sync in case a transport is available, and
      // let the user go. Nothing here waits on a server.
      success: (_, {stale = false}) async {
        await ref.read(outboxProvider.notifier).enqueue(
              kind: 'inventory.movement.add',
              entityType: 'inventory_item',
              entityId: widget.item.id,
            );
        unawaited(ref.read(syncSchedulerProvider).request());
        navigator.pop();
        messenger.showSnackBar(
          const SnackBar(content: Text(S.savedPendingSync)),
        );
      },
      failure: (message, _) async =>
          messenger.showSnackBar(SnackBar(content: Text(message))),
      offline: (_) async =>
          messenger.showSnackBar(const SnackBar(content: Text(S.offlineTitle))),
    );
  }
}

class _DirectionButton extends StatelessWidget {
  const _DirectionButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.primaryTint : c.surface,
          border: Border.all(color: selected ? c.primary : c.line),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: selected ? c.primary : c.ink2),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: selected ? c.primary : c.ink2,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.movement});

  final InventoryMovement movement;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final inflow = movement.direction == MovementDirection.inflow;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: inflow ? c.okTint : c.warnTint,
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          child: Icon(
            inflow ? Icons.south_west_rounded : Icons.north_east_rounded,
            size: 15,
            color: inflow ? c.ok : c.warn,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(movement.reason,
                  style: TextStyle(color: c.ink, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(AppTime.dayTime(movement.at),
                  style: TextStyle(color: c.ink3, fontSize: 11)),
              if (movement.stockBefore != null && movement.stockAfter != null)
                Text(
                  '${S.stockBeforeAfter}: '
                  '${toArabicIndic('${movement.stockBefore}')} / '
                  '${toArabicIndic('${movement.stockAfter}')}',
                  style: TextStyle(color: c.ink3, fontSize: 11),
                ),
              if (movement.performedByName != null)
                Text(
                  '${S.recordedBy} ${movement.performedByName}',
                  style: TextStyle(color: c.ink3, fontSize: 11),
                ),
            ],
          ),
        ),
        Text(
          '${inflow ? '+' : '−'}${toArabicIndic(movement.quantity.toString())} '
          '${_packagingUnitLabel(movement.packagingUnit)}\n'
          '${toArabicIndic('${movement.convertedBaseUnitQuantity}')} ${S.baseUnits}',
          textAlign: TextAlign.end,
          style: AppTypography.digits(inflow ? c.ok : c.warn, size: 14),
        ),
      ]),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PressScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(10, 6, AppSpacing.md, 6),
        decoration: BoxDecoration(
          color: c.primaryTint,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add_rounded, size: 17, color: c.primary),
          const SizedBox(width: 5),
          Text(S.addItem,
              style: TextStyle(
                  color: c.primary, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
