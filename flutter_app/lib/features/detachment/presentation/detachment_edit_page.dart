import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/capability.dart';
import '../../../core/access/capability_guard.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_result.dart';
import '../../../core/widgets/section_header.dart';
import '../../../l10n/strings.dart';
import '../data/detachment_providers.dart';
import '../domain/detachment_models.dart';

/// Create (`id == null`) or edit an existing detachment.
///
/// The same form serves both, because the fields are identical; only the
/// status control and the capability the save button resolves against differ.
class DetachmentEditPage extends ConsumerStatefulWidget {
  const DetachmentEditPage(
      {super.key, required this.id, this.detachmentGroupId});

  final String? id;

  /// The detachment group to create inside. Required when [id] is null — a
  /// detachment has no meaning outside one — and ignored when editing, because
  /// a detachment does not move between detachment groups.
  final String? detachmentGroupId;

  @override
  ConsumerState<DetachmentEditPage> createState() => _DetachmentEditPageState();
}

class _DetachmentEditPageState extends ConsumerState<DetachmentEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _region = TextEditingController();
  final _center = TextEditingController();
  final _notes = TextEditingController();

  DetachmentStatus _status = DetachmentStatus.active;
  Detachment? _existing;
  bool _seeded = false;
  bool _saving = false;

  bool get _isNew => widget.id == null;

  @override
  void dispose() {
    _name.dispose();
    _region.dispose();
    _center.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _seed(Detachment d) {
    _existing = d;
    if (_seeded) return;
    _seeded = true;
    _name.text = d.name;
    _region.text = d.region;
    _center.text = d.mainCenter;
    _notes.text = d.notes ?? '';
    _status = d.status;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(_isNew ? S.newDetachment : S.editDetachment),
      ),
      body: _isNew
          ? _form(existing: null)
          : AsyncResultView<Detachment>(
              value: ref.watch(detachmentByIdProvider(widget.id!)),
              onRetry: () => ref.invalidate(detachmentByIdProvider),
              builder: (context, d, stale) {
                _seed(d);
                return _form(existing: d);
              },
            ),
    );
  }

  Widget _form({required Detachment? existing}) {
    // Creating is an organisation-level act; editing is scoped to the
    // detachment being edited.
    //
    // On a *finished* detachment the two come apart. `detachment.edit` is
    // closed — renaming or re-describing a record that has ended is a
    // historical correction and this domain has no workflow for one. The
    // lifecycle key is not closed, because it is the key that reopens the
    // detachment; without it archiving would be a door with no handle on the
    // inside. So the fields go read-only and the save button survives only
    // for the session that may change the status.
    //
    // The same split holds on an *active* detachment (Point 16): a session
    // holding `detachment.archive` without `detachment.edit` opens this form
    // for the status control alone, so the detail fields stay read-only and
    // `_save` writes only the status. Before, the fields were editable and a
    // rename went out under a key the session did not hold.
    final access = _isNew ? null : ref.accessIn(widget.id!);
    final historical = access?.isHistorical ?? false;
    final canArchive = _isNew ? false : access!.can(Cap.detachmentArchive);
    // `DetachmentAccess` already closes `detachment.edit` on a finished
    // detachment, so this one flag covers both reasons a field is read-only.
    final canEditDetails = _isNew || access!.can(Cap.detachmentEdit);
    final onSave = _isNew
        ? ref.whenCan(Cap.detachmentCreate, _save)
        : (canEditDetails || canArchive ? _save : null);
    // Archiving keeps the record and its history; deleting removes the
    // container and everything inside it. Two different acts, so the
    // destructive one sits apart from the form and asks first.
    final onDelete =
        _isNew ? null : access!.when(Cap.detachmentArchive, _confirmDelete);

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (historical)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.md),
              child: _FormNote(
                key: Key('detachment-historical-note'),
                icon: Icons.history_rounded,
                text: S.historicalDetachmentFormNote,
              ),
            )
          else if (!canEditDetails)
            // Read-only for a reason the session can act on, so it is said
            // once, in the same quiet note the historical form uses.
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.md),
              child: _FormNote(
                key: Key('detachment-status-only-note'),
                icon: Icons.lock_outline_rounded,
                text: S.detachmentStatusOnlyNote,
              ),
            ),
          _Field(
            controller: _name,
            label: S.detachmentName,
            hint: S.detachmentNamePlaceholder,
            enabled: canEditDetails,
          ),
          const SizedBox(height: AppSpacing.md),
          _Field(
            controller: _region,
            label: S.detachmentRegion,
            hint: S.detachmentRegionPlaceholder,
            enabled: canEditDetails,
          ),
          const SizedBox(height: AppSpacing.md),
          _Field(
            controller: _center,
            label: S.detachmentCenter,
            hint: S.detachmentCenterPlaceholder,
            enabled: canEditDetails,
          ),
          const SizedBox(height: AppSpacing.md),
          _Field(
            controller: _notes,
            label: '${S.detachmentNotes} · ${S.optional}',
            hint: S.detachmentNotesPlaceholder,
            required: false,
            maxLines: 3,
            enabled: canEditDetails,
          ),
          if (!_isNew) ...[
            const SectionHeader(title: S.status),
            _StatusPicker(
              value: _status,
              // A detachment's lifecycle is a separate capability from its
              // details, so the control is shown read-only rather than hidden.
              onChanged: canArchive ? (s) => setState(() => _status = s) : null,
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
          FilledButton(
            onPressed: _saving ? null : onSave,
            child: Text(_saving ? S.savedOk : S.save),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: _saving ? null : () => context.pop(),
            child: const Text(S.cancel),
          ),
          if (onDelete != null) ...[
            const SizedBox(height: AppSpacing.xxl),
            OutlinedButton.icon(
              onPressed: _saving ? null : onDelete,
              icon: Icon(Icons.delete_outline_rounded,
                  size: 20, color: context.c.crit),
              label: Text(S.deleteDetachment,
                  style: TextStyle(color: context.c.crit)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: context.c.crit.withValues(alpha: 0.5)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final d = _existing;
    if (d == null) return;
    final c = context.c;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(S.deleteDetachment),
        content: Text('${d.name}\n\n${S.deleteDetachmentBody}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(S.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: c.crit),
            child: const Text(S.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    final result = await ref.read(detachmentRepositoryProvider).delete(d.id);
    if (!mounted) return;
    setState(() => _saving = false);

    result.when(
      success: (_, {stale = false}) {
        ref.invalidate(detachmentListProvider);
        ref.invalidate(detachmentByIdProvider);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(S.detachmentDeleted)));
        // Land on the detachment group this detachment belonged to, not on the
        // detail shell behind this form — that route no longer resolves.
        context.go('/detachment-groups/${d.detachmentGroupId}');
      },
      failure: (message, _) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message))),
      offline: (_) => ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(S.offlineTitle))),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final repo = ref.read(detachmentRepositoryProvider);
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();

    final Result<Detachment> result;
    if (_isNew) {
      result = await repo.create(
        detachmentGroupId: widget.detachmentGroupId!,
        name: _name.text.trim(),
        region: _region.text.trim(),
        mainCenter: _center.text.trim(),
        notes: notes,
      );
    } else {
      final current = await repo.byId(widget.id!);
      final existing = current.when(
        success: (d, {stale = false}) => d,
        failure: (_, __) => null,
        offline: (cached) => cached,
      );
      if (existing == null) {
        result = const Failure('لم يُعثر على المفرزة.', code: 'not_found');
      } else if (!ref.accessIn(widget.id!).can(Cap.detachmentEdit)) {
        // Status only. The details go back exactly as the repository holds
        // them now — not as this form seeded them — so a session without
        // `detachment.edit` can neither rename the detachment nor overwrite
        // a rename made elsewhere since the form opened.
        result = await repo.update(existing.copyWith(status: _status));
      } else {
        result = await repo.update(existing.copyWith(
          name: _name.text.trim(),
          region: _region.text.trim(),
          mainCenter: _center.text.trim(),
          notes: notes,
          status: _status,
        ));
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);

    result.when(
      success: (_, {stale = false}) {
        ref.invalidate(detachmentListProvider);
        ref.invalidate(detachmentByIdProvider);
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

/// One quiet line explaining why the form above it does not type.
/// Why the form's detail fields are read-only: the detachment has finished,
/// or this session may change its status but not its details.
class _FormNote extends StatelessWidget {
  const _FormNote({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: c.ink3),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
          ),
        ),
      ]),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.required = true,
    this.maxLines = 1,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool required;
  final int maxLines;

  /// False on a finished detachment: the record is read, and the only thing
  /// the form can still change is the lifecycle below it.
  final bool enabled;

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
          maxLines: maxLines,
          enabled: enabled,
          decoration: InputDecoration(hintText: hint),
          validator: (v) =>
              required && (v == null || v.trim().isEmpty) ? S.required : null,
        ),
      ],
    );
  }
}

class _StatusPicker extends StatelessWidget {
  const _StatusPicker({required this.value, required this.onChanged});

  final DetachmentStatus value;
  final ValueChanged<DetachmentStatus>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(children: [
      for (final s in DetachmentStatus.values) ...[
        Expanded(
          child: GestureDetector(
            onTap: onChanged == null ? null : () => onChanged!(s),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: s == value ? c.primaryTint : c.surface,
                border: Border.all(color: s == value ? c.primary : c.line),
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              child: Opacity(
                opacity: onChanged == null ? 0.38 : 1,
                child: Text(
                  s == DetachmentStatus.active
                      ? S.statusActive
                      : S.statusArchived,
                  style: TextStyle(
                    color: s == value ? c.primary : c.ink2,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (s != DetachmentStatus.values.last)
          const SizedBox(width: AppSpacing.sm),
      ],
    ]);
  }
}
