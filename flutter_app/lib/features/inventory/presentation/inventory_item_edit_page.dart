import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/capability.dart';
import '../../../core/format/app_date.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_result.dart';
import '../../../core/widgets/confirmation_dialog.dart';
import '../../../l10n/strings.dart';
import '../../detachment/data/detachment_providers.dart';
import '../data/inventory_providers.dart';
import '../domain/inventory_models.dart';

/// Create (`itemId == null`) or edit one stock item.
///
/// The quantity field only exists when creating. After that, stock moves
/// through inflows and outflows and nowhere else — an editable quantity is a
/// number with no movement behind it, which is exactly the thing an inventory
/// is supposed to prevent.
class InventoryItemEditPage extends ConsumerStatefulWidget {
  const InventoryItemEditPage({
    super.key,
    required this.detachmentId,
    required this.itemId,
  });

  final String detachmentId;
  final String? itemId;

  @override
  ConsumerState<InventoryItemEditPage> createState() => _S();
}

class _S extends ConsumerState<InventoryItemEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _unit = TextEditingController();
  final _opening = TextEditingController(text: '0');
  final _minimum = TextEditingController(text: '5');
  final _unitsPerStrip = TextEditingController(text: '1');
  final _stripsPerCarton = TextEditingController(text: '1');

  DateTime? _expiry;
  InventoryItem? _existing;
  bool _seeded = false;
  bool _busy = false;
  PackagingUnit _packagingUnit = PackagingUnit.individual;

  bool get _isNew => widget.itemId == null;

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _opening.dispose();
    _minimum.dispose();
    _unitsPerStrip.dispose();
    _stripsPerCarton.dispose();
    super.dispose();
  }

  void _seed(InventoryItem item) {
    _existing = item;
    if (_seeded) return;
    _seeded = true;
    _name.text = item.name;
    _unit.text = item.unit;
    _minimum.text = '${item.minimum}';
    _unitsPerStrip.text = '${item.unitsPerStrip}';
    _stripsPerCarton.text = '${item.stripsPerCarton}';
    _packagingUnit = item.preferredUnit;
    _expiry = item.expiresOn;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(_isNew ? S.newItem : S.editItem)),
      body: _isNew
          ? _form()
          : AsyncResultView<InventoryItem>(
              value: ref.watch(inventoryItemProvider(widget.itemId!)),
              onRetry: () => ref.invalidate(inventoryItemProvider),
              builder: (context, item, stale) {
                _seed(item);
                return _form();
              },
            ),
    );
  }

  Widget _form() {
    final c = context.c;
    // Through `DetachmentAccess`, so the store of a detachment that has ended
    // keeps its history and gains nothing: the form opens read-only and
    // neither button has a handler behind it.
    final access = ref.accessIn(widget.detachmentId);
    final onSave = access.when(Cap.inventoryItemManage, _save);
    final onDelete =
        _isNew ? null : access.when(Cap.inventoryItemManage, _confirmDelete);

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _Field(
            controller: _name,
            label: S.itemName,
            hint: S.itemNamePlaceholder,
          ),
          const SizedBox(height: AppSpacing.md),
          _PackagingPicker(
            value: _packagingUnit,
            onChanged: (value) => setState(() => _packagingUnit = value),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_isNew) ...[
            _Field(
              controller: _opening,
              label: switch (_packagingUnit) {
                PackagingUnit.individual => S.individualUnitsCount,
                PackagingUnit.strip => S.stripsCount,
                PackagingUnit.carton => S.cartonsCount,
              },
              hint: S.quantityPlaceholder,
              number: true,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_packagingUnit != PackagingUnit.individual) ...[
            _Field(
              controller: _unitsPerStrip,
              label: S.unitsPerStrip,
              hint: S.quantityPlaceholder,
              number: true,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_packagingUnit == PackagingUnit.carton) ...[
            _Field(
              controller: _stripsPerCarton,
              label: S.stripsPerCarton,
              hint: S.quantityPlaceholder,
              number: true,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          _Field(
            controller: _minimum,
            label: S.itemMinimum,
            hint: S.quantityPlaceholder,
            number: true,
            help: S.itemMinimumHelp,
          ),
          const SizedBox(height: AppSpacing.md),
          _ExpiryField(
            value: _expiry,
            onPick: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _expiry ?? now.add(const Duration(days: 180)),
                firstDate: now.subtract(const Duration(days: 365)),
                lastDate: now.add(const Duration(days: 365 * 8)),
              );
              if (picked != null) setState(() => _expiry = picked);
            },
            onClear: () => setState(() => _expiry = null),
          ),
          const SizedBox(height: AppSpacing.xxl),
          FilledButton(
            onPressed: _busy ? null : onSave,
            child: Text(_isNew ? S.addItem : S.saveChanges),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: _busy ? null : () => context.pop(),
            child: const Text(S.cancel),
          ),
          if (onDelete != null) ...[
            const SizedBox(height: AppSpacing.xxl),
            OutlinedButton.icon(
              onPressed: _busy ? null : onDelete,
              icon: Icon(Icons.delete_outline_rounded, size: 20, color: c.crit),
              label: Text(S.deleteItem, style: TextStyle(color: c.crit)),
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: c.crit.withValues(alpha: 0.5))),
            ),
          ],
        ],
      ),
    );
  }

  /// Numbers may be typed in either numeral set — the field shows Arabic-Indic
  /// and a phone keypad emits Western, so both have to parse.
  int? _intOf(TextEditingController field) =>
      int.tryParse(toWesternDigits(field.text.trim()));

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final minimum = _intOf(_minimum);
    final opening = _isNew ? _intOf(_opening) : 0;
    final unitsPerStrip =
        _packagingUnit == PackagingUnit.individual ? 1 : _intOf(_unitsPerStrip);
    final stripsPerCarton =
        _packagingUnit == PackagingUnit.carton ? _intOf(_stripsPerCarton) : 1;
    if (minimum == null ||
        opening == null ||
        unitsPerStrip == null ||
        stripsPerCarton == null ||
        unitsPerStrip <= 0 ||
        stripsPerCarton <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(S.invalidNumber)));
      return;
    }
    // A strip that holds one unit, or a carton that holds one strip, is not a
    // package — it is the metadata missing. Say so here rather than saving a
    // medicine whose stock reads in strips but counts in loose units.
    if (!MedicinePackaging(
      unitsPerStrip: unitsPerStrip,
      stripsPerCarton: stripsPerCarton,
    ).supports(_packagingUnit)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(S.packagingMetadataRequired)));
      return;
    }

    setState(() => _busy = true);
    final repo = ref.read(inventoryRepositoryProvider);
    final Result<InventoryItem> result = _isNew
        ? await repo.create(
            detachmentId: widget.detachmentId,
            name: _name.text.trim(),
            unit: S.baseUnits,
            openingStock: opening,
            minimum: minimum,
            openingUnit: _packagingUnit,
            unitsPerStrip: unitsPerStrip,
            stripsPerCarton: stripsPerCarton,
            expiresOn: _expiry,
          )
        : await repo.update(
            id: widget.itemId!,
            name: _name.text.trim(),
            unit: _unit.text.trim().isEmpty ? S.baseUnits : _unit.text.trim(),
            minimum: minimum,
            unitsPerStrip: unitsPerStrip,
            stripsPerCarton: stripsPerCarton,
            preferredUnit: _packagingUnit,
            expiresOn: _expiry,
          );

    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      success: (_, {stale = false}) {
        ref.invalidate(inventoryListProvider);
        ref.invalidate(inventoryItemProvider);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(S.itemSaved)));
        context.pop();
      },
      failure: (message, _) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message))),
      offline: (_) => ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(S.offlineTitle))),
    );
  }

  Future<void> _confirmDelete() async {
    final item = _existing;
    if (item == null) return;
    final ok = await showAppConfirmation(
      context: context,
      title: S.deleteItem,
      identity: item.name,
      change: S.deleteItemBody,
      unchanged: S.deleteItemUnchanged,
      confirmLabel: S.delete,
      severity: ConfirmationSeverity.destructive,
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    final result = await ref.read(inventoryRepositoryProvider).delete(item.id);
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      success: (_, {stale = false}) {
        ref.invalidate(inventoryListProvider);
        ref.invalidate(inventoryItemProvider);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(S.itemDeleted)));
        context.pop();
      },
      failure: (message, _) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message))),
      offline: (_) => ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(S.offlineTitle))),
    );
  }
}

class _PackagingPicker extends StatelessWidget {
  const _PackagingPicker({required this.value, required this.onChanged});

  final PackagingUnit value;
  final ValueChanged<PackagingUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    const options = [
      (PackagingUnit.individual, S.packagingIndividual),
      (PackagingUnit.strip, S.packagingStrip),
      (PackagingUnit.carton, S.packagingCarton),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.packagingUnit, style: TextStyle(color: c.ink2, fontSize: 13)),
        const SizedBox(height: 6),
        Row(children: [
          for (final (unit, label) in options) ...[
            Expanded(
              child: ChoiceChip(
                label: Text(label, textAlign: TextAlign.center),
                selected: value == unit,
                onSelected: (_) => onChanged(unit),
              ),
            ),
            if (unit != PackagingUnit.carton) const SizedBox(width: 6),
          ],
        ]),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.number = false,
    this.help,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool number;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: c.ink2, fontSize: 13)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(hintText: hint),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return S.required;
            if (number && int.tryParse(toWesternDigits(v.trim())) == null) {
              return S.invalidNumber;
            }
            return null;
          },
        ),
        if (help != null) ...[
          const SizedBox(height: 6),
          Text(help!,
              style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5)),
        ],
      ],
    );
  }
}

class _ExpiryField extends StatelessWidget {
  const _ExpiryField({
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${S.itemExpiry} · ${S.optional}',
            style: TextStyle(color: c.ink2, fontSize: 13)),
        const SizedBox(height: 6),
        InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line2),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Row(children: [
              Icon(Icons.event_outlined, size: 18, color: c.ink3),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value == null ? S.itemNoExpiry : AppDate.dayMonth(value!),
                  style: TextStyle(
                      color: value == null ? c.ink3 : c.ink, fontSize: 14),
                ),
              ),
              if (value != null)
                IconButton(
                  tooltip: S.clearItemExpiry,
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: Icon(Icons.close_rounded, size: 18, color: c.ink3),
                  onPressed: onClear,
                ),
            ]),
          ),
        ),
      ],
    );
  }
}
