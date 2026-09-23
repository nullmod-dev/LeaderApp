import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/problem/problem.dart';
import '../../../core/problem/problem_presentation.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings.dart';
import '../data/auth_providers.dart';
import '../domain/auth_models.dart';
import '../data/sign_out_controller.dart';

/// Signs out and leaves for the login screen — the one implementation, shared
/// by the Settings hub's button and the account screen's.
///
/// Navigation is `go`, not `push`: the authenticated stack must be replaced,
/// not covered. What actually keeps the protected screens shut afterwards is
/// the router's auth gate (`authGateProvider`, wired in `app_router.dart`) —
/// once the session providers are cleared, every protected location redirects
/// here, including a preserved bottom-nav branch stack and any deep link.
///
/// A failed sign-out leaves the session alone and says so. The message is the
/// app's own localized copy resolved from the problem code, never the raw
/// server string — see `FRONTEND-BACKEND-INTEGRATION.md` §2.
/// Confirms, then signs out — the one implementation of the whole gesture.
///
/// The Settings hub, the account screen and the Security screen all offer
/// sign-out, and all three must ask the same question and take the same
/// action. Each held a private copy of this dialog before; a security
/// confirmation that differs by entry point is how one of them quietly loses
/// its confirmation step.
Future<void> confirmAndSignOut(BuildContext context, WidgetRef ref) async {
  final platformSession = ref.read(authRoleProvider) == AuthRole.superAdmin;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(S.signOutConfirm),
          if (platformSession) ...[
            const SizedBox(height: AppSpacing.md),
            const Text(S.breakGlassSignOutWarning),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text(S.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text(S.signOut),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await signOutAndLeave(context, ref);
}

Future<void> signOutAndLeave(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await ref.read(signOutControllerProvider.notifier).signOut();
  // Null means a sign-out was already running and this call was dropped.
  if (result == null || !context.mounted) return;

  result.when(
    success: (_, {stale = false}) => context.go('/login'),
    failure: (message, code) {
      final parsed = ProblemCode.parse(code);
      final view = resolveProblem(
        Problem.of(parsed, rawCode: code, detail: message),
      );
      messenger.showSnackBar(
        SnackBar(
          // A code this build knows gets its own resolved copy; anything
          // else gets a sign-out-specific line rather than the generic
          // "something went wrong", which says nothing about what to do.
          content: Text(parsed == null ? S.profileSignOutFailed : view.message),
        ),
      );
    },
    // Sign-out is a request, not a local write: it cannot be queued for
    // later, because the session it revokes is the one being used offline.
    offline: (_) => messenger.showSnackBar(
      const SnackBar(content: Text(S.offlineTitle)),
    ),
  );
}
