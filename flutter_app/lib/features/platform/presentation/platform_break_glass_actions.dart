import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/strings.dart';
import '../../auth/presentation/sign_out_action.dart';
import '../data/platform_break_glass_providers.dart';
import '../domain/platform_break_glass_models.dart';
import '../domain/platform_break_glass_repository.dart';
import 'platform_break_glass_copy.dart';
import 'widgets/platform_confirmation_dialog.dart';

Future<bool> confirmAndEndBreakGlass(
  BuildContext context,
  WidgetRef ref,
  BreakGlassGrant grant,
) async {
  final confirmed = await showPlatformConfirmation(
    context: context,
    title: S.breakGlassEndTitle.replaceFirst(
      '%s',
      grant.tenant.displayName,
    ),
    change: S.breakGlassEndChange,
    unchanged: S.breakGlassEndUnchanged,
    effective: S.breakGlassEndEffective,
    confirmLabel: S.breakGlassEndFullAction,
    warning: true,
  );
  if (!confirmed || !context.mounted) return false;

  final outcome =
      await ref.read(breakGlassActionControllerProvider.notifier).end(
            EndBreakGlassCommand(
              grantId: grant.id,
              expectedRevision: grant.revision,
              idempotencyKey: breakGlassEndIdempotencyKey(
                grantId: grant.id,
                expectedRevision: grant.revision,
              ),
            ),
          );
  if (!context.mounted) return false;
  final ended = await showBreakGlassOutcome(context, ref, outcome);
  // The strip vanishes wherever the operator is; say why, once.
  if (ended && context.mounted) _snack(context, S.breakGlassEndedSnack);
  return ended;
}

Future<bool> showBreakGlassOutcome(
  BuildContext context,
  WidgetRef ref,
  BreakGlassActionOutcome outcome,
) async {
  switch (outcome) {
    case BreakGlassActionSucceeded():
      return true;
    case BreakGlassActionIgnored():
      return false;
    case BreakGlassActionOffline():
      _snack(context, S.breakGlassOfflineAction);
      return false;
    case BreakGlassActionStale():
      _snack(context, S.breakGlassStaleAction);
      return false;
    case BreakGlassActionNotPermitted():
      _snack(context, S.breakGlassNotPermittedAction);
      return false;
    case BreakGlassActionInvalid(:final code):
      _snack(context, BreakGlassCopy.problem(code));
      return false;
    case BreakGlassActionFailed():
      _snack(context, S.breakGlassFailedAction);
      return false;
    case BreakGlassActionRecentAuthRequired():
      await _showRecentAuth(context, ref);
      return false;
  }
}

void _snack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

Future<void> _showRecentAuth(BuildContext context, WidgetRef ref) async {
  final signOut = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) => AlertDialog(
      key: const Key('break-glass-recent-auth'),
      title: const Text(S.breakGlassRecentAuthTitle),
      content: const Text(S.breakGlassRecentAuthBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text(S.close),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text(S.signOut),
        ),
      ],
    ),
  );
  if (signOut == true && context.mounted) {
    await signOutAndLeave(context, ref);
  }
}
