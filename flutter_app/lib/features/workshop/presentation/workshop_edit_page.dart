import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/capability.dart';
import '../../../core/access/capability_guard.dart';
import '../../../core/format/app_time.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/clock.dart';
import '../../../core/widgets/async_result.dart';
import '../../../l10n/strings.dart';
import '../data/workshop_providers.dart';
import '../domain/workshop_models.dart';
import 'workshop_list_page.dart';

/// Create (`id == null`) or edit a workshop. Both acts are organisation-level.
class WorkshopEditPage extends ConsumerStatefulWidget {
  const WorkshopEditPage({super.key, required this.id});

  final String? id;

  @override
  ConsumerState<WorkshopEditPage> createState() => _WorkshopEditPageState();
}

class _WorkshopEditPageState extends ConsumerState<WorkshopEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _capacity = TextEditingController();
  final _fee = TextEditingController();

  DateTime? _at;
  WorkshopStatus _status = WorkshopStatus.scheduled;
  bool _seeded = false;
  bool _saving = false;

  bool get _isNew => widget.id == null;

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _capacity.dispose();
    _fee.dispose();
    super.dispose();
  }

  void _seed(Workshop w) {
    if (_seeded) return;
    _seeded = true;
    _name.text = w.name;
    _location.text = w.location;
    _capacity.text = w.capacity.toString();
    _fee.text =
        w.registrationFee == 0 ? '' : w.registrationFee.toStringAsFixed(0);
    _at = w.at;
    _status = w.status;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(_isNew ? S.newWorkshop : S.editWorkshop)),
      body: _isNew
          ? _form()
          : AsyncResultView<Workshop>(
              value: ref.watch(workshopByIdProvider(widget.id!)),
              onRetry: () => ref.invalidate(workshopByIdProvider),
              builder: (context, w, stale) {
                _seed(w);
                return _form();
              },
            ),
    );
  }

  Widget _form() {
    final c = context.c;
    final onSave = ref.whenCan(
      _isNew ? Cap.workshopCreate : Cap.workshopEdit,
      _save,
    );
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _Labelled(
            label: S.workshopName,
            child: TextFormField(
              controller: _name,
              decoration:
                  const InputDecoration(hintText: S.workshopNamePlaceholder),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? S.required : null,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _Labelled(
            label: S.workshopDate,
            child: PressScale(
              onTap: _pickDateTime,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
                child: Row(children: [
                  Icon(Icons.event_rounded, size: 18, color: c.ink3),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _at == null ? S.pickDate : AppTime.dayTime(_at!),
                      style: TextStyle(
                        color: _at == null ? c.ink3 : c.ink,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _Labelled(
            label: S.workshopLocation,
            child: TextFormField(
              controller: _location,
              decoration: const InputDecoration(
                  hintText: S.workshopLocationPlaceholder),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? S.required : null,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _Labelled(
            label: S.workshopCapacity,
            child: TextFormField(
              controller: _capacity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  hintText: S.workshopCapacityPlaceholder),
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                return (n == null || n <= 0) ? S.workshopInvalidCapacity : null;
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _Labelled(
            label: S.workshopFee,
            child: TextFormField(
              controller: _fee,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: S.workshopFeeHint),
              validator: (v) {
                final raw = (v ?? '').trim();
                if (raw.isEmpty) return null;
                final n = num.tryParse(raw);
                return (n == null || n < 0) ? S.workshopInvalidFee : null;
              },
            ),
          ),
          // A workshop's status is set by hand: the record carries a start
          // time but no end, so nothing here can derive that it is over.
          if (!_isNew) ...[
            const SizedBox(height: AppSpacing.md),
            _Labelled(
              label: S.workshopStatusLabel,
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final status in WorkshopStatus.values)
                    _StatusPill(
                      label: workshopStatusLabel(status),
                      selected: _status == status,
                      onTap: () => setState(() => _status = status),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
          FilledButton(
            onPressed: _saving ? null : onSave,
            child: const Text(S.save),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: _saving ? null : () => context.pop(),
            child: const Text(S.cancel),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final now = ref.read(clockProvider)();
    final date = await showDatePicker(
      context: context,
      initialDate: _at ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at ?? now),
    );
    if (!mounted) return;
    setState(() {
      _at = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? (_at?.hour ?? 9),
        time?.minute ?? (_at?.minute ?? 0),
      );
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_at == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(S.workshopInvalidDate)));
      return;
    }
    setState(() => _saving = true);

    final repo = ref.read(workshopRepositoryProvider);
    final capacity = int.parse(_capacity.text.trim());
    final fee =
        _fee.text.trim().isEmpty ? 0.0 : num.parse(_fee.text.trim()).toDouble();

    final Result<Workshop> result;
    if (_isNew) {
      result = await repo.create(
        name: _name.text.trim(),
        at: _at!,
        location: _location.text.trim(),
        capacity: capacity,
        registrationFee: fee,
      );
    } else {
      final current = await repo.byId(widget.id!);
      final existing = current.when(
        success: (w, {stale = false}) => w,
        failure: (_, __) => null,
        offline: (cached) => cached,
      );
      if (existing == null) {
        result = const Failure('لم يُعثر على الورشة.', code: 'not_found');
      } else {
        result = await repo.update(existing.copyWith(
          name: _name.text.trim(),
          at: _at,
          location: _location.text.trim(),
          capacity: capacity,
          status: _status,
          registrationFee: fee,
        ));
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);

    result.when(
      success: (Workshop saved, {stale = false}) {
        refreshWorkshop(ref, saved.id);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(S.savedOk)));
        context.pop();
      },
      failure: (message, _) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message))),
      offline: (_) => ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(S.offlineTitle))),
    );
  }
}

/// The status choices, in the same pill shape the list filters use.
class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      selected: selected,
      child: PressScale(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? c.primary : c.surface,
            border: Border.all(color: selected ? c.primary : c.line2),
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? c.primaryInk : c.ink2,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: c.ink2, fontSize: 13)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
