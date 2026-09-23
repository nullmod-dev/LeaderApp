import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import 'reading_column.dart';

/// How much a confirmation is asking for.
///
/// Three levels, because the product has three: an ordinary state change, an
/// operation with a consequence somebody else will feel, and one that
/// destroys a record.
enum ConfirmationSeverity {
  /// A reversible change. The default filled button.
  normal,

  /// A consequential but recoverable operation — suspending access, ending a
  /// trial. `warn` ground.
  warning,

  /// Deletes or closes something. `crit` ground.
  destructive,
}

/// The one consequential confirmation in this app.
///
/// **Why this shape.** A confirmation that only repeats the button's own
/// label («حذف؟ / حذف») asks the user to agree with a word, not with an
/// outcome. This one states three things, in the order somebody deciding
/// actually needs them:
///
///  1. **which record** — [identity], on its own line, selectable, so the
///     name being deleted is not buried in a sentence;
///  2. **what changes** — [change];
///  3. **what does not** — [unchanged], which is the half that stops a
///     cautious person abandoning a correct operation.
///
/// [effective] adds *when*, for operations that are not immediate.
///
/// The confirm button carries the severity as a filled ground, never as a
/// coloured `TextButton` label sitting at equal weight beside «إلغاء» — the
/// pattern the tenant side used in thirteen hand-rolled `AlertDialog`s before
/// this existed (UI audit P1-3). The platform surface has had this rigour
/// since Point 6; this is that dialog, lifted into `core/` so the Main Admin
/// deleting a member gets the same care as a Super Admin suspending a team.
///
/// **What it is deliberately not.** Not a general dialog framework. No custom
/// body widget, no form, no list — anything that needs those is a screen or a
/// sheet, not a confirmation.
Future<bool> showAppConfirmation({
  required BuildContext context,
  required String title,
  required String change,
  required String unchanged,
  required String confirmLabel,

  /// The record being acted on. Selectable, so a support conversation can
  /// quote it.
  String? identity,

  /// Isolates [identity] left-to-right — a Team Code, an email, an id. An
  /// Arabic name must not be forced LTR, so this is opt-in.
  bool identityLtr = false,

  /// When the change takes effect, if not immediately.
  String? effective,
  ConfirmationSeverity severity = ConfirmationSeverity.normal,

  /// Overridden only where the confirm label itself begins with «إلغاء»
  /// (cancelling an invitation, cancelling a replacement), so the two buttons
  /// never read as the same word.
  String dismissLabel = S.cancel,

  /// Prefix for the three widget keys, so a surface that already has tests
  /// written against its own names keeps them.
  String keyPrefix = 'app-confirmation',
}) async {
  final answer = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) {
      final c = dialogContext.c;
      return AlertDialog(
        scrollable: true,
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kDialogMaxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (identity != null) ...[
                Directionality(
                  textDirection: identityLtr
                      ? TextDirection.ltr
                      : Directionality.of(dialogContext),
                  child: SelectableText(
                    identity,
                    key: Key('$keyPrefix-identity'),
                    textAlign: TextAlign.start,
                    style: Theme.of(dialogContext).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              _Line(icon: Icons.sync_alt_rounded, text: change),
              const SizedBox(height: AppSpacing.md),
              _Line(icon: Icons.shield_outlined, text: unchanged),
              if (effective != null) ...[
                const SizedBox(height: AppSpacing.md),
                _Line(icon: Icons.schedule_rounded, text: effective),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: Key('$keyPrefix-dismiss'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dismissLabel),
          ),
          FilledButton(
            key: Key('$keyPrefix-confirm'),
            style: switch (severity) {
              ConfirmationSeverity.normal => null,
              ConfirmationSeverity.warning => FilledButton.styleFrom(
                  backgroundColor: c.warn,
                  foregroundColor: c.bg,
                ),
              ConfirmationSeverity.destructive => FilledButton.styleFrom(
                  backgroundColor: c.crit,
                  foregroundColor: c.bg,
                ),
            },
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return answer ?? false;
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: context.c.ink3),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.55,
                  ),
            ),
          ),
        ],
      );
}
