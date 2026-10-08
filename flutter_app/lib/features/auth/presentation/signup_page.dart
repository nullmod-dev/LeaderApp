import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result/result.dart';
import '../../../core/startup/startup_destination.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings.dart';
import '../data/auth_entry_email_provider.dart';
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
///
/// **The address is checked first** (`/auth/email-status`). A registered one
/// is not signed up again: the screen says so and offers its sign-in code,
/// and the typed password is never sent. The check is advice only — when it
/// cannot be answered, sign-up goes ahead and the backend still decides.
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

  /// The address the backend called registered. The notice offering its
  /// sign-in code shows only while the field still holds it.
  String? _registeredEmail;

  /// The sign-in code is being asked for (the notice's own progress).
  bool _sendingCode = false;

  @override
  void initState() {
    super.initState();
    // The address typed on `/login`, so it is never typed twice. Taken once:
    // cleared after this frame, since a provider cannot change mid-build.
    final handed = ref.read(authEntryEmailProvider);
    if (handed != null) {
      _email.text = handed;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(authEntryEmailProvider.notifier).state = null;
      });
    }
  }

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
      _registeredEmail = null;
    });
    final controller = ref.read(onboardingControllerProvider.notifier);
    final status = await controller.checkEmailStatus(_email.text);
    if (!mounted) return;
    switch (status) {
      case Success(data: EmailEntryStatus.registered):
        setState(() {
          _busy = false;
          _registeredEmail = normalizeLoginEmail(_email.text);
        });
        return;
      case Offline():
        setState(() {
          _busy = false;
          _offline = true;
        });
        return;
      // Invited, new — or a check that could not be answered: sign-up runs,
      // and the backend's own answer is the one that counts.
      case Success() || Failure():
        break;
    }
    final result = await controller.signUpWithPassword(
        email: _email.text, password: _password.text);
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

  /// A registered address signs in with a mailed code instead.
  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _sendingCode = true;
      _error = null;
      _offline = false;
    });
    final result = await ref
        .read(onboardingControllerProvider.notifier)
        .beginEmailCodeSignIn(_email.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _sendingCode = false;
    });
    result.when(
      success: (_, {stale = false}) => context.go('/verify-email'),
      failure: (_, __) => setState(() =>
          _error = onboardingErrorMessage(onboardingErrorKindOf(result)!)),
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
      case GoogleSignInRateLimited(:final retryAfter):
        setState(() => _error =
            '${S.googleSignInRateLimited}${onboardingCountdown(retryAfter)}');
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
    final registered = _registeredEmail != null &&
        _registeredEmail == normalizeLoginEmail(_email.text);
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
            // Rebuilds while an error or the registered notice is about the
            // address being edited, so neither outlives what it was about.
            onChanged: _emailError == null && _registeredEmail == null
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
          if (registered) ...[
            const SizedBox(height: AppSpacing.md),
            _RegisteredNotice(
              sending: _sendingCode,
              onSendCode: _busy ? null : _sendCode,
            ),
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

/// «هذا البريد مسجَّل بالفعل» and the one step that fits it: a sign-in code.
///
/// Guidance, not a refusal — the offline notice's quiet surface, not the
/// error banner's — with its action inside it, so the way forward sits under
/// the sentence that explains it. A live region, so a screen reader hears it
/// as the answer to the tap it made.
class _RegisteredNotice extends StatelessWidget {
  const _RegisteredNotice({required this.sending, required this.onSendCode});

  final bool sending;
  final VoidCallback? onSendCode;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('signup-registered'),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.mark_email_read_outlined, color: c.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    S.emailAlreadyRegistered,
                    style: TextStyle(color: c.ink2, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              key: const Key('signup-send-code'),
              onPressed: sending ? null : onSendCode,
              icon: sending
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: c.primary),
                    )
                  : const Icon(Icons.mail_outline_rounded, size: 18),
              label: const Text(S.sendSignInCode),
            ),
          ],
        ),
      ),
    );
  }
}
