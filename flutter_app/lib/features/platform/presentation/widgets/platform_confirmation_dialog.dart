import 'package:flutter/material.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../../../core/widgets/reading_column.dart';
import '../../../../l10n/strings.dart';

/// The platform surface's confirmation helpers.
///
/// The dialog itself now lives in `core/widgets/confirmation_dialog.dart` —
/// this pattern was the strongest in the product, so Phase 1 of the UI
/// quality programme promoted it rather than copying it. What stays here is
/// the platform's own vocabulary: the two helper signatures its call sites
/// already use, its `platform-confirmation-*` widget keys, and the two-step
/// final-deletion flow below, which is specific to deleting a tenant and is
/// not a general primitive.

/// The platform's name for [ConfirmationSeverity]. An alias, not a copy, so
/// the two surfaces cannot end up with two ideas of what «destructive» is.
typedef PlatformConfirmationSeverity = ConfirmationSeverity;

/// The widget keys the platform tests and renders address this dialog by.
const _platformKeys = 'platform-confirmation';

/// Consequential platform confirmation with explicit change/non-change copy.
/// Warning operations use the warning palette; this is not a delete dialog.
Future<bool> showPlatformConfirmation({
  required BuildContext context,
  required String title,
  required String change,
  required String unchanged,
  required String confirmLabel,
  String? effective,
  bool warning = false,
}) async {
  return showPlatformConfirmationSpec(
    context: context,
    title: title,
    change: change,
    unchanged: unchanged,
    confirmLabel: confirmLabel,
    effective: effective,
    severity: warning
        ? PlatformConfirmationSeverity.warning
        : PlatformConfirmationSeverity.normal,
  );
}

Future<bool> showPlatformConfirmationSpec({
  required BuildContext context,
  required String title,
  required String change,
  required String unchanged,
  required String confirmLabel,
  String? identity,
  bool identityLtr = false,
  String? effective,
  PlatformConfirmationSeverity severity = PlatformConfirmationSeverity.normal,
  // Override where the confirm label itself starts with «إلغاء» (cancel a
  // replacement), so the two buttons never read as the same word.
  String dismissLabel = S.cancel,
}) =>
    showAppConfirmation(
      context: context,
      title: title,
      change: change,
      unchanged: unchanged,
      confirmLabel: confirmLabel,
      identity: identity,
      identityLtr: identityLtr,
      effective: effective,
      severity: severity,
      dismissLabel: dismissLabel,
      keyPrefix: _platformKeys,
    );

/// The second step for final destructive deletion. The first step is the
/// consequence review above; this step requires both an explicit acknowledgement
/// and the exact tenant name. Neither is treated as authentication.
Future<bool> showPlatformFinalDeletionConfirmation({
  required BuildContext context,
  required String title,
  required String identity,
  required String change,
  required String unchanged,
  required String effective,
  required String confirmLabel,
  required String typedConfirmation,
}) async {
  final reviewed = await showPlatformConfirmationSpec(
    context: context,
    title: title,
    identity: identity,
    change: change,
    unchanged: unchanged,
    effective: effective,
    confirmLabel: 'متابعة إلى التأكيد',
    severity: PlatformConfirmationSeverity.destructive,
  );
  if (!reviewed || !context.mounted) return false;

  final answer = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => _FinalDeletionStepDialog(
      title: title,
      identity: identity,
      confirmLabel: confirmLabel,
      typedConfirmation: typedConfirmation,
    ),
  );
  return answer ?? false;
}

class _FinalDeletionStepDialog extends StatefulWidget {
  const _FinalDeletionStepDialog({
    required this.title,
    required this.identity,
    required this.confirmLabel,
    required this.typedConfirmation,
  });

  final String title;
  final String identity;
  final String confirmLabel;
  final String typedConfirmation;

  @override
  State<_FinalDeletionStepDialog> createState() =>
      _FinalDeletionStepDialogState();
}

class _FinalDeletionStepDialogState extends State<_FinalDeletionStepDialog> {
  final _controller = TextEditingController();
  var _acknowledged = false;
  var _typed = '';
  var _touched = false;

  bool get _nameMatches => _typed == widget.typedConfirmation;
  bool get _valid => _acknowledged && _nameMatches;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_valid) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const Key('final-delete-confirmation-step'),
        scrollable: true,
        title: Text(widget.title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kDialogMaxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.identity,
                key: const Key('final-delete-identity'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'اكتب اسم الفريق نفسه تماماً، ثم أكّد فهم نتيجة العملية.',
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const Key('final-delete-typed-confirmation'),
                controller: _controller,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                onChanged: (value) => setState(() {
                  _typed = value;
                  _touched = true;
                }),
                decoration: InputDecoration(
                  labelText: 'اسم الفريق للتأكيد',
                  hintText: widget.typedConfirmation,
                  helperText: 'المطابقة حرفية، ولا تُغيّر المسافات أو الحروف.',
                  errorText: _touched && _typed.isNotEmpty && !_nameMatches
                      ? 'اسم الفريق غير مطابق.'
                      : null,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              CheckboxListTile(
                key: const Key('final-delete-acknowledgement'),
                contentPadding: EdgeInsets.zero,
                value: _acknowledged,
                onChanged: (value) =>
                    setState(() => _acknowledged = value ?? false),
                title: const Text(
                  'أفهم أن الاستعادة بعد تنفيذ الخادم قد تكون مستحيلة.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(S.cancel),
          ),
          FilledButton(
            key: const Key('final-delete-submit'),
            style: FilledButton.styleFrom(
              backgroundColor: c.crit,
              foregroundColor: c.bg,
            ),
            onPressed: _valid ? _submit : null,
            child: Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }
}
