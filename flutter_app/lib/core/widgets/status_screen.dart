import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme.dart';

/// How serious a [StatusScreen] is, and therefore which semantic colour it
/// draws its mark in.
///
/// Four tones rather than a colour parameter: every one of these screens is a
/// *state of the session*, and the reader should be able to tell a terminal
/// outcome from a temporary one before reading a word. A caller that could
/// pass any colour would eventually paint a revocation in the same tint as a
/// waiting state.
enum StatusTone {
  /// Nothing is wrong. Waiting, or an account that simply has nothing
  /// assigned yet.
  neutral,

  /// Informational, and the person is expected to do something next.
  info,

  /// Blocked, but reversibly — a suspension, an expired session.
  warning,

  /// Terminal — access withdrawn, the customer deleted.
  critical,
}

/// The one layout every session-state screen in this app uses.
///
/// **Why one component and not twelve screens.** Point 3 introduced nine
/// user-visible session states — no access assigned, suspended, revoked,
/// tenant suspended, tenant deleted, setup incomplete, invalid session, demo,
/// demo expired — and they say different sentences about the same situation:
/// *you are authenticated, and here is why this is as far as you go.* Twelve
/// hand-built layouts would drift in spacing, in where the sign-out sits, and
/// in which of them remembered text scaling. One component means fixing any of
/// that once.
///
/// **What it deliberately is not.** Not `ErrorStateView` — that lives *inside*
/// a screen that failed to load and offers a retry. This replaces the screen:
/// it is a full `Scaffold` with no app bar, no navigation and no bottom nav,
/// because every state that reaches it is one the tenant shell must not be
/// built for.
///
/// **Accessibility and layout.** The whole body scrolls, so a 320 dp phone at
/// text scale 1.6 cannot overflow it; the actions are stretched buttons in a
/// column rather than a row, for the same reason. Everything is directional
/// (`AlignmentDirectional`, `EdgeInsetsDirectional`), so the Arabic layout is
/// the layout rather than a mirrored afterthought.
///
/// **Motion.** None. These screens are the end of a decision, not a
/// transition, and the router's own shared-axis page transition is the only
/// movement involved — which `MotionScope`/`MediaQuery.disableAnimations`
/// already govern. Nothing here animates on a loop or delays what the reader
/// came to find out.
class StatusScreen extends StatelessWidget {
  const StatusScreen({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.tone = StatusTone.neutral,
    this.detail,
    this.identity,
    this.primaryAction,
    this.secondaryAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final StatusTone tone;

  /// A second paragraph, for a state that needs to say what happens next
  /// without burying it in the first.
  final String? detail;

  /// The account card — name and a role/status line — for the states where
  /// knowing *which* account is held explains the screen. Omitted wherever
  /// showing it would leak something the session should not still see.
  final Widget? identity;

  /// The filled button. Every screen here has exactly one obvious next
  /// action, and a screen with none would be a dead end.
  final Widget? primaryAction;

  /// An outlined button under it — support, or a way back to the login form.
  final Widget? secondaryAction;

  ({Color fg, Color bg}) _colors(AppColors c) => switch (tone) {
        StatusTone.neutral => (fg: c.ink3, bg: c.surface2),
        StatusTone.info => (fg: c.info, bg: c.infoTint),
        StatusTone.warning => (fg: c.warn, bg: c.warnTint),
        StatusTone.critical => (fg: c.crit, bg: c.critTint),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    final tint = _colors(c);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.xxl,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Semantics(
                container: true,
                label: title,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tint.bg,
                          borderRadius: BorderRadius.circular(AppRadii.lg),
                        ),
                        child: ExcludeSemantics(
                          child: Icon(icon, color: tint.fg, size: 28),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(title, style: t.headlineSmall),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      body,
                      style: t.bodyMedium?.copyWith(color: c.ink3, height: 1.6),
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        detail!,
                        style:
                            t.bodySmall?.copyWith(color: c.ink3, height: 1.6),
                      ),
                    ],
                    if (identity != null) ...[
                      const SizedBox(height: AppSpacing.xl),
                      identity!,
                    ],
                    if (primaryAction != null) ...[
                      const SizedBox(height: AppSpacing.xxl),
                      primaryAction!,
                    ],
                    if (secondaryAction != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      secondaryAction!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The account card shown on the states where identity clarifies the screen.
///
/// Name and one supporting line — never an email, never a tenant name, never
/// a capability. A blocked or unassigned session must not be a place to read
/// customer information out of.
class StatusIdentityCard extends StatelessWidget {
  const StatusIdentityCard({
    super.key,
    required this.name,
    required this.subtitle,
  });

  final String name;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(children: [
        Icon(Icons.person_outline_rounded, size: 20, color: c.ink3),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  color: c.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(color: c.ink3, fontSize: 12)),
            ],
          ),
        ),
      ]),
    );
  }
}
