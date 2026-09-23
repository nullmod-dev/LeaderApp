import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result/result.dart';
import '../../../core/startup/startup_destination.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/time/clock.dart';
import '../../../l10n/strings.dart';
import '../data/onboarding_controller.dart';
import '../domain/onboarding_models.dart';
import '../domain/onboarding_repository.dart';
import '_auth_scaffold.dart';
import 'onboarding_ui.dart';

/// `/verify-email` — Point 17B.
///
/// A **startup-only** destination (`app_router.dart`'s `startupStatusPages`):
/// it only renders while `authEntryStateProvider` actually holds an
/// [EntryVerificationPending] challenge, and a session that reaches any other
/// state is redirected off it by the router before this widget's build ever
/// runs. Nothing here composes a challenge on its own.
class EmailVerificationPage extends ConsumerStatefulWidget {
  const EmailVerificationPage({super.key});

  @override
  ConsumerState<EmailVerificationPage> createState() =>
      _EmailVerificationPageState();
}

class _EmailVerificationPageState extends ConsumerState<EmailVerificationPage> {
  final _code = TextEditingController();
  bool _busy = false;
  bool _resending = false;
  String? _error;
  bool _offline = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Only for the resend-cooldown countdown text; the backend enforces the
    // real throttle regardless of what this shows.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit(VerificationChallenge challenge) async {
    setState(() {
      _busy = true;
      _error = null;
      _offline = false;
    });
    final result = await ref
        .read(onboardingControllerProvider.notifier)
        .verifyEmail(_code.text);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case Success(:final data):
        switch (data) {
          case EntryReady():
            await awaitFullSessionReady(ref);
            if (!mounted) return;
            context.go('/home');
          case EntryVerificationRequired():
            // The mock never answers this way to its own `verifyEmail`; kept
            // exhaustive for a real backend that might re-challenge.
            break;
          case EntryContinueOnboarding(:final snapshot):
            context.go(onboardingDestination(snapshot).location!);
        }
      case Failure():
        final kind = onboardingErrorKindOf(result)!;
        setState(() {
          _error = onboardingErrorMessage(kind);
          _code.clear();
        });
      case Offline():
        setState(() => _offline = true);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
      _offline = false;
    });
    final result = await ref
        .read(onboardingControllerProvider.notifier)
        .resendVerification();
    if (!mounted) return;
    setState(() => _resending = false);
    result.when(
      success: (_, {stale = false}) {},
      failure: (_, __) {
        final kind = onboardingErrorKindOf(result)!;
        setState(() => _error = onboardingErrorMessage(kind));
      },
      offline: (_) => setState(() => _offline = true),
    );
  }

  Future<void> _useAnotherEmail() async {
    await ref.read(onboardingControllerProvider.notifier).abandon();
    if (!mounted) return;
    context.go('/signup');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final entry = ref.watch(authEntryStateProvider);
    if (entry is! EntryVerificationPending) {
      // The router is about to move the app off this route (or has not yet
      // on this frame). Hold a neutral surface rather than reaching into a
      // challenge that no longer exists.
      return const AuthScaffold(
        title: S.emailVerificationTitle,
        subtitle: '',
        child: SizedBox.shrink(),
      );
    }
    final challenge = entry.challenge;
    final now = ref.watch(clockProvider)();
    final cooldown = challenge.resendCooldownAt(now);
    final canResend = cooldown == Duration.zero;

    return AuthScaffold(
      title: S.emailVerificationTitle,
      subtitle: '\u2066${challenge.maskedEmail}\u2069',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              key: const Key('verification-code'),
              controller: _code,
              readOnly: _busy || _resending,
              autofocus: true,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: challenge.codeLength,
              inputFormatters: [
                LengthLimitingTextInputFormatter(challenge.codeLength),
              ],
              style: AppTypography.digits(c.ink, size: 26).copyWith(
                letterSpacing: 8,
              ),
              decoration: const InputDecoration(
                counterText: '',
                labelText: S.verificationCodeLabel,
              ),
            ),
          ),
          if (challenge.attemptsRemaining case final left?) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('${S.attemptsRemainingLabel}$left',
                style: TextStyle(color: c.ink3, fontSize: 12)),
          ],
          if (_offline) ...[
            const SizedBox(height: AppSpacing.md),
            const OnboardingOfflineNotice(),
          ] else if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            OnboardingErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppSpacing.xl),
          OnboardingPrimaryButton(
            label: S.verifyEmailAction,
            busy: _busy,
            onPressed: () => _submit(challenge),
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: canResend
                ? TextButton(
                    onPressed: _resending ? null : _resend,
                    child: Text(
                      _resending ? S.resendingCode : S.resendCode,
                      style: TextStyle(
                        color: c.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  )
                : Text(
                    '${S.resendCodeCountdown}${onboardingCountdown(cooldown)}',
                    style: TextStyle(color: c.ink3, fontSize: 13),
                  ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: TextButton(
              onPressed: _busy || _resending ? null : _useAnotherEmail,
              child: Text(
                S.useAnotherEmail,
                style: TextStyle(color: c.ink3, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
