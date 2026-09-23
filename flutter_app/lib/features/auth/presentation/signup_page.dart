import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result/result.dart';
import '../../../core/startup/startup_destination.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings.dart';
import '../data/google_identity_gateway.dart';
import '../data/onboarding_controller.dart';
import '../domain/onboarding_models.dart';
import '../domain/onboarding_repository.dart';
import '_auth_scaffold.dart';
import 'google_sign_in_button.dart';
import 'onboarding_ui.dart';

/// `/signup` — Point 17B.
///
/// Email and password only: never a tenant, role, capability, Team Code or
/// plan field (`HANDOFF.md` "POINT 17A" §N.2 and CLAUDE.md's project rules).
/// Success always lands on `/verify-email`, whether or not the address was
/// already registered — the enumeration-safe answer sign-up must give.
class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  String? _emailError;
  bool _offline = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // The same courtesy check the controller applies, surfaced on the field
    // it is about instead of a generic banner. No request is sent.
    if (validateLoginEmail(_email.text) != null) {
      setState(() {
        _emailError = S.mainAdminEmailInvalid;
        _error = null;
        _offline = false;
      });
      return;
    }
    setState(() {
      _emailError = null;
      _busy = true;
      _error = null;
      _offline = false;
    });
    final result = await ref
        .read(onboardingControllerProvider.notifier)
        .signUpWithPassword(email: _email.text, password: _password.text);
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      success: (_, {stale = false}) => context.go('/verify-email'),
      failure: (_, __) {
        final kind = onboardingErrorKindOf(result)!;
        setState(() => _error = onboardingErrorMessage(kind));
      },
      offline: (_) => setState(() => _offline = true),
    );
  }

  Future<void> _onGoogleAttempt(GoogleSignInAttempt attempt) async {
    switch (attempt) {
      case GoogleSignInCancelled():
        return;
      case GoogleSignInUnavailable():
        setState(() => _error =
            onboardingErrorMessage(OnboardingErrorKind.googleUnavailable));
        return;
      case GoogleSignInNetworkFailure():
        setState(() => _offline = true);
        return;
      case GoogleSignInFailed():
        setState(() =>
            _error = onboardingErrorMessage(OnboardingErrorKind.googleRetry));
        return;
      case GoogleSignInObtained(:final assertion):
        setState(() {
          _busy = true;
          _error = null;
          _offline = false;
        });
        final result = await ref
            .read(onboardingControllerProvider.notifier)
            .signInWithGoogle(assertion);
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
                context.go('/verify-email');
              case EntryContinueOnboarding(:final snapshot):
                context.go(onboardingDestination(snapshot).location!);
            }
          case Failure():
            setState(() => _error =
                onboardingErrorMessage(onboardingErrorKindOf(result)!));
          case Offline():
            setState(() => _offline = true);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AuthScaffold(
      title: S.signupTitle,
      subtitle: S.signupSub,
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('signup-email'),
            controller: _email,
            readOnly: _busy,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: S.signupEmailLabel,
              errorText: _emailError,
            ),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            onChanged: _emailError == null
                ? null
                : (_) => setState(() => _emailError = null),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('signup-password'),
            controller: _password,
            readOnly: _busy,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: S.passwordLabel,
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
                tooltip: _obscure ? S.showPassword : S.hidePassword,
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(S.passwordAdvisoryHint,
              style: TextStyle(color: c.ink3, fontSize: 12)),
          if (_offline) ...[
            const SizedBox(height: AppSpacing.md),
            const OnboardingOfflineNotice(),
          ] else if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            OnboardingErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppSpacing.xl),
          OnboardingPrimaryButton(
            label: S.signUpAction,
            busy: _busy,
            onPressed: _submit,
          ),
          const SizedBox(height: AppSpacing.md),
          GoogleSignInButton(busy: _busy, onAttempt: _onGoogleAttempt),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: TextButton(
              onPressed: _busy ? null : () => context.go('/login'),
              child: Text(
                S.haveAccountAlready,
                style: TextStyle(
                  color: c.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
