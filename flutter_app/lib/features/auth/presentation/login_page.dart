import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion/motion_tokens.dart';
import '../../../core/result/result.dart';
import '../../../core/startup/startup_destination.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/made_in_iraq.dart';
import '../../../core/widgets/reading_column.dart';
import '../../../l10n/strings.dart';
import '../data/auth_providers.dart';
import '../data/google_identity_gateway.dart';
import '../data/onboarding_controller.dart';
import '../domain/onboarding_models.dart';
import '../domain/onboarding_repository.dart';
import 'entry_glass.dart';
import 'google_sign_in_button.dart';
import 'onboarding_ui.dart';

/// The product's front door.
///
/// **It shares the launch screen's ground.** Every colour on it comes from
/// [EntryGlass], the same teal-and-glass surface the Leader intro is painted
/// on, so arriving here from a cold start reads as the mark dissolving into a
/// form rather than as a second screen. This file spells no colour.
///
/// **The brand is said once, by the title.** The screen used to open with the
/// mark, then «ليدر» under it, then «مرحباً بك في ليدر» under *that* — three
/// statements of the same fact in the first 140 dp, before anything the
/// person came here to do. The launcher icon and the intro have already shown
/// the mark by the time this screen exists; the heading carries the name, and
/// the space that bought goes to the form.
///
/// **Two zones, not one.** Who you are and what this is sit on the ground:
/// the heading and one supporting line. What you *do* sits on the glass: two
/// fields, the forgot link, the primary action, the rule and Google. A panel
/// that opened with a paragraph made the reader work out where the form
/// started; this way the panel *is* the form.
///
/// **Nothing about entry changed.** Same controller, same password call, same
/// Google gateway, same three outcomes handed to [_enter]. This screen is a
/// surface: it collects two fields and reports what came back. It carries no
/// demo entry, no persona shortcut, no credential hint and no MFA bypass —
/// Team/Demo is a post-verification decision for an unlinked identity, and
/// this screen is before that.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  /// Below this the screen padding and the panel padding both step down, so
  /// the fields keep their width rather than the layout keeping its margins.
  static const double compactWidth = 360;

  /// The form never gets wider than a phone's worth of line length, however
  /// wide the window is.
  ///
  /// This measure was the one value on this screen with obvious value
  /// everywhere else — a column of inputs has the same right width in a
  /// sign-up flow, a settings form or an edit sheet — so Phase 1 of the UI
  /// quality programme promoted it to [kFormMaxWidth] rather than leaving it
  /// spelled here. The screen's own *rhythm* (its 27 sp title, its −0.5
  /// tracking, its 13 and 18 px gaps) stays local: that is composition for one
  /// panel, not a token.
  static const double maxFormWidth = kFormMaxWidth;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _busy = false;

  /// A Google assertion is being exchanged. Kept apart from [_busy] so only
  /// the Google surface shows progress; both lock the whole form.
  bool _googleBusy = false;
  String? _error;
  bool _offline = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    // The two fields draw their own focus ring, fill and accent border, so
    // the screen has to rebuild when focus moves between them.
    _emailFocus.addListener(_onFocusChanged);
    _passwordFocus.addListener(_onFocusChanged);
    // The CTA is disabled until both fields have something in them, which
    // means it has to follow what is typed.
    _email.addListener(_onTyped);
    _password.addListener(_onTyped);
  }

  void _onFocusChanged() => setState(() {});

  void _onTyped() => setState(() {});

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// The one place a successful entry outcome is turned into navigation, for
  /// both the password path and Google.
  Future<void> _enter(Result<AuthEntryOutcome> result) async {
    switch (result) {
      case Success(:final data):
        switch (data) {
          case EntryReady():
            // The session providers are the app's authenticated state; the
            // controller only changed the repository. Awaited, not merely
            // invalidated: the gate is still `signedOut` until the re-read
            // lands, and a `context.go` fired before then is redirected
            // straight back here.
            await awaitFullSessionReady(ref);
            ref.invalidate(sessionsProvider);
            if (!mounted) return;
            context.go('/home');
          case EntryVerificationRequired():
            context.go('/verify-email');
          case EntryContinueOnboarding(:final snapshot):
            context.go(onboardingDestination(snapshot).location!);
        }
      case Failure():
        setState(() =>
            _error = onboardingErrorMessage(onboardingErrorKindOf(result)!));
      case Offline():
        setState(() => _offline = true);
    }
  }

  bool get _locked => _busy || _googleBusy;

  /// Whether the CTA can be pressed. Empty fields are the only thing this
  /// screen refuses on its own — everything else is the repository's answer
  /// to give, and a button that submits nothing is not a question worth
  /// asking a server.
  bool get _submittable =>
      !_locked && _email.text.trim().isNotEmpty && _password.text.isNotEmpty;

  Future<void> _submit() async {
    if (!_submittable) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _offline = false;
    });
    final result = await ref
        .read(onboardingControllerProvider.notifier)
        .signInWithPassword(email: _email.text, password: _password.text);
    if (!mounted) return;
    setState(() => _busy = false);
    await _enter(result);
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
          _googleBusy = true;
          _error = null;
          _offline = false;
        });
        final result = await ref
            .read(onboardingControllerProvider.notifier)
            .signInWithGoogle(assertion);
        if (!mounted) return;
        setState(() => _googleBusy = false);
        await _enter(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = ref.watch(themeStateProvider);
    final brightness = switch (theme.mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => media.platformBrightness,
    };
    final glass = EntryGlass.resolve(brightness, eyeProtect: theme.eyeProtect);

    final compact = media.size.width < LoginPage.compactWidth;
    final pad = compact ? 16.0 : 20.0;
    final panelPad = compact ? 16.0 : 19.0;

    final notice = switch (ref.watch(authEntryStateProvider)) {
      EntryNone(notice: EntryNotice.verificationEnded) =>
        S.onboardingVerificationEnded,
      EntryNone(notice: EntryNotice.sessionEnded) => S.onboardingSessionEnded,
      EntryNone(notice: EntryNotice.setupCompletedElsewhere) =>
        S.onboardingSetupAlreadyCompleted,
      _ => null,
    };

    return Scaffold(
      // The ground is the gradient below, not a flat colour; the scaffold's
      // own fill would only show for one frame behind it.
      backgroundColor: glass.baseMid,
      body: EntryBackdrop(
        glass: glass,
        // The wave rises through the heading and out past the panel, which is
        // where the intro's last wave was heading when this screen took over.
        pulseCenter: const Alignment(0, -0.22),
        // The idle screen keeps its breathing pulse. While either field is
        // active the painter holds its current frame, avoiding a full-screen
        // background repaint under the glass blur on every keyboard frame.
        pausePulse: _emailFocus.hasFocus || _passwordFocus.hasFocus,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              // The form is centred and capped through the scroll view's own
              // padding rather than an inner `Center`: a centring box would
              // hand the column loose height constraints and the `Spacer`
              // that holds the footer down would collapse to nothing.
              final side = math.max(
                pad,
                (box.maxWidth - LoginPage.maxFormWidth) / 2,
              );
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.symmetric(horizontal: side),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  // The footer sits at the bottom of the screen when the
                  // content is shorter than it, and directly under the
                  // content when large text or an open keyboard makes the
                  // content taller than the viewport.
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // A flexible opening gap rather than a fixed one: on
                        // a tall phone the form sits optically centred, and
                        // at 320 dp with 1.6× text it collapses to nothing
                        // instead of pushing the CTA off the screen.
                        const Spacer(flex: 2),
                        _Masthead(glass: glass),
                        const SizedBox(height: 22),
                        EntryGlassPanel(
                          glass: glass,
                          padding: EdgeInsets.all(panelPad),
                          child: _form(glass, notice),
                        ),
                        const SizedBox(height: 16),
                        _signupRow(glass),
                        const Spacer(flex: 3),
                        MadeInIraqFooter(
                          color: glass.faint,
                          padding: const EdgeInsets.only(top: 14, bottom: 22),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _form(EntryGlass glass, String? notice) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice != null) ...[
          _Notice(
            glass: glass,
            icon: Icons.info_outline_rounded,
            message: notice,
            tone: _NoticeTone.quiet,
          ),
          const SizedBox(height: 16),
        ],
        LoginField(
          key: const Key('login-email'), // the labelled group
          glass: glass,
          label: S.emailLabel,
          controller: _email,
          focusNode: _emailFocus,
          icon: Icons.mail_outline_rounded,
          enabled: !_locked,
          // The address is Latin whatever the interface language is, but it
          // still starts at the field's leading edge.
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.end,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username, AutofillHints.email],
          onSubmitted: (_) => _passwordFocus.requestFocus(),
        ),
        const SizedBox(height: 13),
        LoginField(
          key: const Key('login-password'),
          glass: glass,
          label: S.passwordLabel,
          controller: _password,
          focusNode: _passwordFocus,
          icon: Icons.lock_outline_rounded,
          enabled: !_locked,
          obscure: _obscure,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _submit(),
          trailing: _PasswordToggle(
            glass: glass,
            obscured: _obscure,
            onChanged: () => setState(() => _obscure = !_obscure),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: _locked ? null : () => context.push('/forgot'),
            style: TextButton.styleFrom(
              foregroundColor: glass.muted,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(48, 44),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            child: const Text(
              S.forgotPassword,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (_offline) ...[
          const SizedBox(height: 4),
          _Notice(
            glass: glass,
            icon: Icons.wifi_off_rounded,
            message: S.onboardingOfflineNotice,
            tone: _NoticeTone.quiet,
          ),
        ] else if (_error != null) ...[
          const SizedBox(height: 4),
          _Notice(
            glass: glass,
            icon: Icons.error_outline_rounded,
            message: _error!,
            tone: _NoticeTone.danger,
          ),
        ],
        const SizedBox(height: 14),
        _PrimaryCta(
          glass: glass,
          busy: _busy,
          onPressed: _submittable ? _submit : null,
        ),
        const SizedBox(height: 18),
        _Divider(glass: glass),
        const SizedBox(height: 18),
        GoogleSignInButton(
          busy: _busy,
          loading: _googleBusy,
          onAttempt: _onGoogleAttempt,
          skin: GoogleButtonSkin(
            fill: glass.fieldFill,
            border: glass.fieldBorder,
            label: glass.fg,
            labelDisabled: glass.faint,
            progress: glass.accent,
            // Google's mark keeps its own four colours, so it gets a solid
            // tile rather than sitting straight on translucent glass.
            plate: const Color(0xFFFFFFFF),
          ),
        ),
      ],
    );
  }

  Widget _signupRow(EntryGlass glass) => Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            S.noAccount,
            style: TextStyle(color: glass.muted, fontSize: 13.5),
          ),
          TextButton(
            onPressed: _locked ? null : () => context.push('/signup'),
            style: TextButton.styleFrom(
              // `accentInk`, not `accent`: this is prose on the ground and
              // has to clear 4.5:1 there. See [EntryGlass.accentInk].
              foregroundColor: glass.accentInk,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(48, 44),
            ),
            child: const Text(
              S.createAccount,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
}

/// «مرحباً بك في ليدر» and the one line under it.
///
/// The whole brand block on this screen. There is no mark and no separate
/// wordmark: the launcher icon and the launch intro have both already shown
/// the mark, and the heading carries the name. What replaces the lost visual
/// weight is a short accent rule — the one piece of brand colour above the
/// glass, and the thing that stops a bare heading from floating.
class _Masthead extends StatelessWidget {
  const _Masthead({required this.glass});

  final EntryGlass glass;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            key: const Key('login-brand-rule'),
            width: 44,
            height: 3,
            decoration: BoxDecoration(
              color: glass.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            S.loginTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: glass.fg,
              fontSize: 27,
              height: 1.32,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            S.loginSub,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: glass.muted,
              fontSize: 14.5,
              height: 1.55,
            ),
          ),
        ],
      );
}

/// One field: a persistent label, then a 54dp translucent well holding a
/// leading glyph, the input and an optional trailing control.
///
/// **Flat, not blurred.** It sits inside the panel's blur already; a second
/// `BackdropFilter` here is what makes a glass UI look muddy.
///
/// **The label is real.** It is above the field rather than floating inside
/// it — Arabic labels at 13.5sp do not survive being shrunk into a border —
/// and it is merged into the field's semantics node so a screen reader
/// announces the two as one control.
///
/// **Focus moves three things.** The border takes the accent, a 4dp ring
/// appears, and the well itself brightens ([EntryGlass.fieldFocusFill]).
/// Colour alone is never the signal, and on a frosted panel a border change
/// alone is close to invisible.
class LoginField extends StatelessWidget {
  const LoginField({
    super.key,
    required this.glass,
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.icon,
    this.enabled = true,
    this.obscure = false,
    this.textDirection,
    this.textAlign = TextAlign.start,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
    this.trailing,
  });

  final EntryGlass glass;
  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final IconData icon;
  final bool enabled;
  final bool obscure;
  final TextDirection? textDirection;

  /// The Latin address is written left to right but still sits against the
  /// field's leading edge, which in an Arabic layout is the right one.
  final TextAlign textAlign;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

  /// The handle a test or an automation tool reaches the input by.
  ///
  /// Login's labels sit *above* the field rather than in its
  /// `InputDecoration`, so the label-based finder the `AuthScaffold` screens
  /// use has nothing to match on here. Derived from the same `S` constant
  /// both sides read, so the two cannot drift.
  static Key keyFor(String label) => Key('login-field-$label');

  @override
  Widget build(BuildContext context) {
    final focused = focusNode.hasFocus;
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: TextStyle(
              color: glass.fg,
              fontSize: 13.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          AnimatedContainer(
            duration: effectiveDuration(context, MotionTokens.short),
            curve: effectiveCurve(context, MotionTokens.standard),
            constraints: const BoxConstraints(minHeight: 54),
            padding: EdgeInsetsDirectional.only(
              start: 15,
              end: trailing == null ? 15 : 5,
            ),
            decoration: BoxDecoration(
              color: focused ? glass.fieldFocusFill : glass.fieldFill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: focused ? glass.accent : glass.fieldBorder,
                width: 1.5,
              ),
              boxShadow: focused ? glass.focusRing : const [],
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: focused ? glass.accent : glass.muted,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: TextField(
                    key: keyFor(label),
                    controller: controller,
                    focusNode: focusNode,
                    enabled: enabled,
                    obscureText: obscure,
                    textDirection: textDirection,
                    textAlign: textAlign,
                    keyboardType: keyboardType,
                    textInputAction: textInputAction,
                    autofillHints: autofillHints,
                    onSubmitted: onSubmitted,
                    cursorColor: glass.accent,
                    style: TextStyle(
                      color: glass.fg,
                      fontSize: 15.5,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The hide/show control. A 48dp target, and it says which way it goes —
/// the eye alone is ambiguous in every language.
class _PasswordToggle extends StatelessWidget {
  const _PasswordToggle({
    required this.glass,
    required this.obscured,
    required this.onChanged,
  });

  final EntryGlass glass;
  final bool obscured;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => IconButton(
        key: const Key('login-password-toggle'),
        onPressed: onChanged,
        iconSize: 20,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        padding: EdgeInsets.zero,
        color: glass.muted,
        tooltip: obscured ? S.showPassword : S.hidePassword,
        icon: Icon(
          obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          semanticLabel: obscured ? S.showPassword : S.hidePassword,
        ),
      );
}

/// «تسجيل الدخول». A `FilledButton` so it keeps the app's button semantics,
/// with the glass palette painted over the theme's.
///
/// **It is the one lit object on the screen.** Everything else here is
/// translucent or is ink; the primary action is solid accent with its own
/// accent-tinted shadow under it. That is what makes it read as sitting *on*
/// the glass rather than being another panel of it — and it is the difference
/// between a screen that has a primary action and one that has six controls.
/// The shadow is dropped while the button is disabled: an inert control that
/// still casts light is the exact mixed signal a disabled state exists to
/// avoid.
class _PrimaryCta extends StatelessWidget {
  const _PrimaryCta({
    required this.glass,
    required this.busy,
    required this.onPressed,
  });

  final EntryGlass glass;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final live = !busy && onPressed != null;
    return AnimatedContainer(
      duration: effectiveDuration(context, MotionTokens.short),
      curve: effectiveCurve(context, MotionTokens.standard),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: live
            ? [
                BoxShadow(
                  color: glass.ctaShadow,
                  blurRadius: 22,
                  spreadRadius: -6,
                  offset: const Offset(0, 9),
                ),
              ]
            : const [],
      ),
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: glass.accent,
          foregroundColor: glass.onAccent,
          // Disabled is a pair of real colours, not the accent at an alpha —
          // and it is carried by the fill, by the shadow going out, and by
          // the button reporting itself disabled, never by colour alone.
          disabledBackgroundColor: glass.ctaDisabled,
          disabledForegroundColor: glass.onCtaDisabled,
          minimumSize: const Size.fromHeight(54),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          // Size and weight only — the family comes from the button theme's
          // own label style. Spelling a bare `TextStyle` here would drop
          // `fontFamily` and render Arabic in the platform fallback.
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: 16.5,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
        ),
        child: busy
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: glass.onAccent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(S.signIn),
                ],
              )
            : const Text(S.signIn),
      ),
    );
  }
}

/// «أو» between the two independent ways in.
class _Divider extends StatelessWidget {
  const _Divider({required this.glass});

  final EntryGlass glass;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Container(height: 1, color: glass.hairline)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              S.authMethodsDivider,
              style: TextStyle(
                color: glass.faint,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: glass.hairline)),
        ],
      );
}

enum _NoticeTone { danger, quiet }

/// A refusal, an offline hold or a notice carried over from a previous
/// session, said inside the panel.
///
/// Tinted rather than given a surface of its own: inside glass, a second
/// opaque card is one card too many, and the wash plus the glyph carry the
/// state without relying on colour alone. A live region, so a screen reader
/// announces it the moment it appears.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.glass,
    required this.icon,
    required this.message,
    required this.tone,
  });

  final EntryGlass glass;
  final IconData icon;
  final String message;
  final _NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final danger = tone == _NoticeTone.danger;
    final ink = danger ? glass.danger : glass.muted;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: danger ? glass.dangerWash : glass.fieldFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: danger
                ? glass.danger.withValues(alpha: 0.45)
                : glass.fieldBorder,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, color: ink, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: ink, fontSize: 13, height: 1.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
