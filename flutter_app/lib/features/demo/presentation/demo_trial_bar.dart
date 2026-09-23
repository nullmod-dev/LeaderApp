import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings.dart';
import '../../auth/data/sign_out_controller.dart';
import '../../auth/presentation/sign_out_action.dart';
import '../../pricing/presentation/pricing_page.dart';
import '../data/demo_workspace.dart';

/// The one thing on screen that says this is a trial.
///
/// It sits above every page of the shell rather than on a demo-only landing
/// screen: the demo *is* the application, so the fact that the data is a
/// sample has to travel with the user instead of being stated once and then
/// forgotten three screens later. It also carries the exit, so ending the
/// trial is always one tap away from wherever the user got to.
class DemoTrialBar extends ConsumerWidget {
  const DemoTrialBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isCustomerDemoSessionProvider)) {
      return const SizedBox.shrink();
    }
    final c = context.c;
    final leaving =
        ref.watch(signOutControllerProvider) == SignOutPhase.inProgress;
    // At large text sizes a sentence and a button do not share a line
    // honestly; the button goes underneath rather than squeezing the notice.
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 16 ||
        MediaQuery.sizeOf(context).width < 360;

    final notice = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.science_outlined, size: 18, color: c.info),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            S.demoTrialNotice,
            style: TextStyle(color: c.ink2, fontSize: 12, height: 1.4),
          ),
        ),
      ],
    );
    final exit = TextButton(
      key: const Key('demo-exit'),
      onPressed: leaving ? null : () => endDemoTrial(context, ref),
      style: TextButton.styleFrom(
        foregroundColor: c.info,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      ),
      child: const Text(S.customerDemoExit),
    );
    final plans = TextButton(
      key: const Key('demo-see-plans'),
      // The bar sits above every branch navigator, so this is a branch switch
      // rather than a page pushed onto whichever tab happened to be active.
      onPressed: () => context.go(PricingPage.routePath),
      style: TextButton.styleFrom(
        foregroundColor: c.info,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      ),
      child: const Text(S.demoSeePlans),
    );
    final actions = Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [plans, exit],
    );

    return Material(
      color: c.infoTint,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.lg, AppSpacing.xs, AppSpacing.sm, AppSpacing.xs),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    notice,
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: actions,
                    ),
                  ],
                )
              : Row(children: [
                  Expanded(child: notice),
                  Flexible(child: actions),
                ]),
        ),
      ),
    );
  }
}

/// Ends the trial: confirms in the demo's own words, then clears the session.
///
/// It is the ordinary sign-out underneath — the demo session is a session, and
/// the one mechanism that ends a session must stay the one mechanism. What
/// differs is the sentence: nothing is being logged out of, and what is lost
/// is the sample work done inside the trial. The real identity that started
/// the demo is untouched and can sign in again and choose Team or Demo, which
/// is why this does not say "your account".
Future<void> endDemoTrial(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text(S.customerDemoExit),
      content: const Text(S.demoExitConfirm),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text(S.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text(S.customerDemoExit),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await signOutAndLeave(context, ref);
}
