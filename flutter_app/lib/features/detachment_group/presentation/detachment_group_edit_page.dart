import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/capability.dart';
import '../../../core/access/capability_guard.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_result.dart';
import '../../../l10n/strings.dart';
import '../../detachment/data/detachment_providers.dart';
import '../data/detachment_group_providers.dart';
import '../domain/detachment_group_models.dart';

/// Create (`id == null`) or edit a detachment group.
///
/// A name is the whole required form — that was the brief, and it is also the
/// right call: everything operational belongs to a detachment, so asking for
/// more here would be asking for data nobody has yet.
class DetachmentGroupEditPage extends ConsumerStatefulWidget {
  const DetachmentGroupEditPage({super.key, required this.id});

  final String? id;

  @override
  ConsumerState<DetachmentGroupEditPage> createState() =>
      _DetachmentGroupEditPageState();
}

class _DetachmentGroupEditPageState
    extends ConsumerState<DetachmentGroupEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _notes = TextEditingController();

  DetachmentGroup? _existing;
  bool _seeded = false;
  bool _busy = false;

  bool get _isNew => widget.id == null;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _seed(DetachmentGroup t) {
    _existing = t;
    if (_seeded) return;
    _seeded = true;
    _name.text = t.name;
    _notes.text = t.notes ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
          title: Text(_isNew ? S.newDetachmentGroup : S.editDetachmentGroup)),
      body: _isNew
          ? _form()
          : AsyncResultView<DetachmentGroup>(
              value: ref.watch(detachmentGroupByIdProvider(widget.id!)),
              onRetry: () => ref.invalidate(detachmentGroupByIdProvider),
              builder: (context, t, stale) {
                _seed(t);
                return _form();
              },
            ),
    );
  }

  Widget _form() {
    final c = context.c;
    final onSave = ref.whenCan(Cap.detachmentCreate, _save);
    final onDelete =
        _isNew ? null : ref.whenCan(Cap.adminManage, _confirmDelete);

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(S.detachmentGroupName,
              style: TextStyle(color: c.ink2, fontSize: 13)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _name,
            autofocus: _isNew,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
                hintText: S.detachmentGroupNamePlaceholder),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? S.required : null,
          ),
          const SizedBox(height: AppSpacing.md),
          Text('${S.detachmentGroupNotes} · ${S.optional}',
              style: TextStyle(color: c.ink2, fontSize: 13)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(
                hintText: S.detachmentGroupNotesPlaceholder),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            Icon(Icons.info_outline_rounded, size: 15, color: c.ink3),
            const SizedBox(width: 8),
            Expanded(
              child: Text(S.detachmentGroupHint,
                  style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5)),
            ),
          ]),
          const SizedBox(height: AppSpacing.xxl),
          FilledButton(
            onPressed: _busy ? null : onSave,
            child: Text(_isNew ? S.createDetachmentGroup : S.saveChanges),
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
              label: Text(S.deleteDetachmentGroup,
                  style: TextStyle(color: c.crit)),
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: c.crit.withValues(alpha: 0.5))),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);

    final repo = ref.read(detachmentGroupRepositoryProvider);
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();

    final Result<DetachmentGroup> result;
    if (_isNew) {
      result = await repo.create(name: _name.text.trim(), notes: notes);
    } else if (_existing == null) {
      result = const Failure('لم يُعثر على الجهة.', code: 'not_found');
    } else {
      result = await repo.update(
        _existing!.copyWith(name: _name.text.trim(), notes: notes),
      );
    }

    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      success: (_, {stale = false}) {
        ref.invalidate(detachmentGroupListProvider);
        ref.invalidate(detachmentGroupByIdProvider);
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

  Future<void> _confirmDelete() async {
    final group = _existing;
    if (group == null) return;
    final c = context.c;
    final detachments = toArabicIndic('${group.detachmentCount}');
    final members = toArabicIndic('${group.memberCount}');
    // The count is spelled out rather than implied. "Delete the detachment
    // group" and "delete four detachments and everything in them" are different
    // acts and the dialog has to say which one this is.
    final detail = group.detachmentCount == 0
        ? S.deleteDetachmentGroupBody
        : '${S.deleteDetachmentGroupBody}\n\n'
            '${S.detachmentGroupDetachments}: $detachments'
            ' · ${S.detachmentGroupMembers}: $members';

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(S.deleteDetachmentGroup),
        content: Text('${group.name}\n\n$detail'),
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

    setState(() => _busy = true);
    final result =
        await ref.read(detachmentGroupRepositoryProvider).delete(group.id);
    if (!mounted) return;
    setState(() => _busy = false);

    result.when(
      success: (_, {stale = false}) {
        ref.invalidate(detachmentGroupListProvider);
        ref.invalidate(detachmentGroupByIdProvider);
        ref.invalidate(detachmentListProvider);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(S.detachmentGroupDeleted)));
        // Back past the detachment group's own detachment list, which no longer
        // resolves — landing on a not-found screen after a successful delete
        // reads as a failure.
        context.go('/detachment-groups');
      },
      failure: (message, _) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message))),
      offline: (_) => ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(S.offlineTitle))),
    );
  }
}
