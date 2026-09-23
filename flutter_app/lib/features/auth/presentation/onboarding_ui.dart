/// Point 17B — shared copy and widgets for the production onboarding screens
/// (`/signup`, `/verify-email`, `/link-team`, `/account-setup`, and the
/// Google entry on `/login` and `/signup`).
///
/// One place for the error mapping and the two small widgets every screen
/// repeats, so a screen cannot drift from the rule in `HANDOFF.md` "POINT
/// 17A" §19: presentation never sees a wire code, only an
/// [OnboardingErrorKind].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings.dart';
import '../../about/domain/support_contacts.dart';
import '../data/auth_providers.dart';
import '../domain/auth_models.dart';
import '../domain/onboarding_repository.dart';
import 'sign_out_action.dart';

/// The role label shown on `/account-setup`'s tenant confirmation card.
/// `AuthRole.superAdmin` and `AuthRole.customerDemo` never reach onboarding —
/// kept exhaustive for the same reason `LinkedTenant.role`'s type is the
/// whole enum rather than a narrower one.
String onboardingRoleLabel(AuthRole role) => switch (role) {
      AuthRole.superAdmin => S.roleSuperAdmin,
      AuthRole.mainAdmin => S.roleMainAdmin,
      AuthRole.admin => S.roleSimpleAdmin,
      AuthRole.customerDemo => S.roleCustomerDemo,
    };

/// Awaits the re-read an `EntryReady` outcome triggers, before the caller
/// navigates to `/home`.
///
/// `OnboardingController._apply` invalidates `currentUserResultProvider` but
/// does not await it, so `authGateProvider` still reads the old `signedOut`
/// value for a moment. A `context.go('/home')` fired in that window is
/// redirected straight back to the auth screen it came from — the same race
/// `login_page.dart`'s password path has always guarded against.
Future<void> awaitFullSessionReady(WidgetRef ref) =>
    ref.read(currentUserResultProvider.future);

/// The one mapping from [OnboardingErrorKind] to Arabic copy.
String onboardingErrorMessage(OnboardingErrorKind kind) => switch (kind) {
      OnboardingErrorKind.invalidCredentials => S.onboardingInvalidCredentials,
      OnboardingErrorKind.passwordRejected => S.onboardingPasswordRejected,
      OnboardingErrorKind.invalidInput => S.onboardingInvalidInput,
      OnboardingErrorKind.verificationCodeInvalid => S.onboardingCodeInvalid,
      OnboardingErrorKind.verificationCodeExpired => S.onboardingCodeExpired,
      OnboardingErrorKind.verificationEnded => S.onboardingVerificationEnded,
      OnboardingErrorKind.resendThrottled => S.onboardingResendThrottled,
      OnboardingErrorKind.googleRetry => S.onboardingGoogleRetry,
      OnboardingErrorKind.googleUnavailable => S.onboardingGoogleUnavailable,
      OnboardingErrorKind.methodLinkRequired => S.onboardingMethodLinkRequired,
      OnboardingErrorKind.unsupportedMethod => S.onboardingUnsupportedMethod,
      OnboardingErrorKind.teamCodeMalformed => S.onboardingTeamCodeMalformed,
      OnboardingErrorKind.teamCodeRejected => S.onboardingTeamCodeRejected,
      OnboardingErrorKind.invitationExpired => S.onboardingInvitationExpired,
      OnboardingErrorKind.accountAlreadyLinked =>
        S.onboardingAccountAlreadyLinked,
      OnboardingErrorKind.tenantUnavailable => S.onboardingTenantUnavailable,
      OnboardingErrorKind.setupUnavailable => S.onboardingSetupUnavailable,
      OnboardingErrorKind.setupAlreadyCompleted =>
        S.onboardingSetupAlreadyCompleted,
      OnboardingErrorKind.accountUnavailable => S.onboardingAccountUnavailable,
      OnboardingErrorKind.sessionEnded => S.onboardingSessionEnded,
      OnboardingErrorKind.rateLimited => S.onboardingRateLimited,
      OnboardingErrorKind.offline => S.onboardingOfflineNotice,
      OnboardingErrorKind.temporaryFailure => S.onboardingTemporaryFailure,
      OnboardingErrorKind.unknown => S.onboardingUnknownError,
    };

/// `mm:ss`, always non-negative. Display only — the backend enforces the
/// real cooldown/throttle whatever this shows.
String onboardingCountdown(Duration remaining) {
  final clamped = remaining.isNegative ? Duration.zero : remaining;
  final minutes = clamped.inMinutes;
  final seconds = clamped.inSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

/// The one error banner shape every onboarding screen uses. A live region so
/// a screen reader announces a refusal the moment it appears, without the
/// person having to find it.
class OnboardingErrorBanner extends StatelessWidget {
  const OnboardingErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: c.critTint,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: c.crit),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, color: c.crit, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child:
                  Text(message, style: TextStyle(color: c.crit, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one line every trust-changing action shows instead of running while
/// offline. Never a spinner that spins forever.
class OnboardingOfflineNotice extends StatelessWidget {
  const OnboardingOfflineNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, color: c.ink3, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                S.onboardingOfflineNotice,
                style: TextStyle(color: c.ink2, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Point 18B — the "أو" rule between two independent ways to sign in, so the
/// Google surface reads as a separate method rather than part of the password
/// form. Decorative lines; the word is the only thing a reader announces.
class AuthMethodsDivider extends StatelessWidget {
  const AuthMethodsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        Expanded(child: Divider(color: c.line, height: 1)),
        Padding(
          padding:
              const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.md),
          child: Text(
            S.authMethodsDivider,
            style: TextStyle(
                color: c.ink3, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(child: Divider(color: c.line, height: 1)),
      ],
    );
  }
}

/// The sign-out / support row every onboarding screen with a live journey
/// (Team Link, Account Setup) offers as its way out — the same ordinary
/// sign-out the blocked-state screens use (`sign_out_action.dart`), so there
/// is exactly one exit from a pre-session journey.
class OnboardingExitRow extends ConsumerWidget {
  const OnboardingExitRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `Wrap`, not `Row`: two icon buttons with Arabic labels do not fit one
    // line at 320dp inside `AuthScaffold`'s padding — this wraps to a second
    // line there instead of overflowing.
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.sm,
      children: [
        TextButton.icon(
          onPressed: () => confirmAndSignOut(context, ref),
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text(S.signOut),
        ),
        TextButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              scrollable: true,
              title: const Text(S.aboutSupport),
              content: const Directionality(
                textDirection: TextDirection.ltr,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(supportEmail),
                    SizedBox(height: AppSpacing.sm),
                    SelectableText(supportTelegram),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(S.close),
                ),
              ],
            ),
          ),
          icon: const Icon(Icons.support_agent_rounded, size: 18),
          label: const Text(S.contactSupport),
        ),
      ],
    );
  }
}

/// A primary `FilledButton` that shows a spinner and disables while [busy].
class OnboardingPrimaryButton extends StatelessWidget {
  const OnboardingPrimaryButton({
    super.key,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: c.primaryInk),
            )
          : Text(label),
    );
  }
}
