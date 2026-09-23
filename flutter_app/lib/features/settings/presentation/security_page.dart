import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/app_time.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../core/problem/problem.dart';
import '../../../core/problem/problem_presentation.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../../core/widgets/refresh_indicator.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../../auth/data/auth_providers.dart';
import '../../auth/data/session_revoke_controller.dart';
import '../../auth/data/sign_out_controller.dart';
import '../../auth/presentation/sign_out_action.dart';
import '../../auth/domain/auth_models.dart';
import '../../shell/main_shell.dart';
import 'widgets/settings_widgets.dart';

/// Security & sessions (`/more/security`) — the app's one screen about
/// protecting the signed-in administrator's account.
///
/// **The split with Profile.** `/more/profile` is identity: who this account
/// is and what it is granted. This screen is protection: two-step
/// verification, the password action, which devices are signed in, and the
/// way out. Neither repeats the other; Profile links here rather than growing
/// a second session list.
///
/// **Nothing here is invented.** Every session field on screen is a field the
/// server sends (`API_CONTRACT.md` → `Session`); there is no device model, no
/// browser version and no unmasked address, because the contract carries
/// none. Two-step verification is reported as *unknown* rather than as
/// enabled: `AuthUser` has no MFA field and there is no endpoint that answers
/// the question, so a green "مفعّل" would be a claim the app cannot make. The
/// password row starts the reset-by-email flow the backend actually has and
/// is worded as that, not as an authenticated password change — there is no
/// such endpoint.
///
/// **Two sections, loaded separately.** The account section is derived from
/// what the app already knows and renders even when the session list cannot
/// be read; only the session list depends on the network. A failure in one
/// never blanks the other.
class SecurityPage extends ConsumerWidget {
  const SecurityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final sessions = ref.watch(sessionsProvider);
    final signingOut =
        ref.watch(signOutControllerProvider) == SignOutPhase.inProgress;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text(S.settingsSecurity)),
      body: AppRefreshIndicator(
        onRefresh: () => ref.refresh(sessionsProvider.future),
        child: FloatingNavPadding(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // ---- A. Account security -----------------------------------
              const SectionLabel(S.securityAccountSection),
              SettingsSection(children: [
                _StatusRow(
                  key: const Key('security-mfa-row'),
                  icon: Icons.verified_user_outlined,
                  label: S.securityMfa,
                  // Muted, not green and not red: this is an unread state,
                  // not a verdict about the account.
                  chip: const StatusChip(
                    kind: StatusKind.muted,
                    label: S.securityMfaUnknown,
                  ),
                  action: S.securityMfaManage,
                  // The setup flow owns the secret and the backup codes and
                  // keeps its existing safeguards; none of it is copied onto
                  // this screen.
                  onTap: () => context.push('/mfa-setup'),
                ),
                // The backend has `password-reset/request → verify → complete`
                // and nothing else, so this is a reset by email and says so.
                NavigationRow(
                  key: const Key('security-password-row'),
                  icon: Icons.password_rounded,
                  label: S.profilePasswordReset,
                  subtitle: S.profilePasswordResetSub,
                  onTap: () => context.push('/forgot'),
                ),
              ]),
              const _Caption(S.securityMfaNote),

              // ---- B. Sessions -------------------------------------------
              const SectionLabel(S.settingsSessions),
              ..._sessionsBlock(context, ref, sessions),

              // ---- C. The way out ----------------------------------------
              //
              // Sign-out is the *only* way to end the current session: the
              // server refuses to revoke it through the sessions endpoint,
              // and offering a second control that does the same thing under
              // a different name is how an admin ends the wrong one.
              const SizedBox(height: AppSpacing.xl),
              OutlinedButton.icon(
                key: const Key('security-sign-out'),
                onPressed:
                    signingOut ? null : () => confirmAndSignOut(context, ref),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.crit,
                  side: BorderSide(color: c.crit),
                ),
                icon: const Icon(Icons.logout_rounded),
                label: const Text(S.signOut),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The session section's own four states, as list children.
  ///
  /// Deliberately not `AsyncResultView`: that renders a whole-screen state,
  /// and a session list that cannot be read must not take the account
  /// section, the password action and sign-out down with it. The copy for a
  /// failure still comes from the shared problem pipeline — only the
  /// container is smaller.
  List<Widget> _sessionsBlock(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Result<List<Session>>> value,
  ) {
    return value.when(
      // Card-shaped placeholders, not `SkeletonList` — that is a `ListView`
      // of its own and cannot be nested inside this one.
      loading: () => const [
        Skeleton(height: 96, radius: AppRadii.lg),
        SizedBox(height: AppSpacing.sm),
        Skeleton(height: 96, radius: AppRadii.lg),
        SizedBox(height: AppSpacing.sm),
        Skeleton(height: 96, radius: AppRadii.lg),
      ],
      error: (_, __) => [
        _SectionProblem(
          view: ProblemView.fallback,
          // A thrown provider error says nothing about whether retrying
          // helps, and re-reading a session list is cheap and safe.
          showRetry: true,
          onRetry: () => ref.invalidate(sessionsProvider),
        ),
      ],
      data: (result) => result.when(
        success: (data, {stale = false}) =>
            _sessionList(context, ref, data, stale: stale),
        failure: (message, code) {
          final problem = Problem.of(ProblemCode.parse(code),
              rawCode: code, detail: message);
          return [
            _SectionProblem(
              view: resolveProblem(problem),
              onRetry: () => ref.invalidate(sessionsProvider),
            ),
          ];
        },
        // Offline with a cached copy still shows the devices, marked stale —
        // knowing which devices were signed in is useful without a network.
        // Offline with nothing cached says so, and offers the retry.
        offline: (cached) => cached == null
            ? [
                EmptyState(
                  key: const Key('security-sessions-offline'),
                  icon: Icons.cloud_off_rounded,
                  title: S.offlineTitle,
                  body: S.noCachedCopy,
                  actionLabel: S.retry,
                  onAction: () => ref.invalidate(sessionsProvider),
                ),
              ]
            : _sessionList(context, ref, cached, stale: true),
      ),
    );
  }

  List<Widget> _sessionList(
    BuildContext context,
    WidgetRef ref,
    List<Session> sessions, {
    required bool stale,
  }) {
    if (sessions.isEmpty) {
      return const [
        EmptyState(
          key: Key('security-sessions-empty'),
          icon: Icons.devices_other_outlined,
          title: S.emptySessions,
          body: S.emptySessionsSub,
        ),
      ];
    }

    // This session first, whatever order the server listed them in — it is
    // the row the admin has to be able to recognise at a glance.
    final ordered = [
      ...sessions.where((s) => s.current),
      ...sessions.where((s) => !s.current),
    ];
    final hasOthers = ordered.any((s) => !s.current);
    final inFlight = ref.watch(sessionRevokeControllerProvider);

    return [
      if (stale)
        const Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.sm),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: StaleBadge(),
          ),
        ),
      // A count, not a score: how many devices are signed in, and nothing
      // dressed up as a rating.
      _Caption(
        ordered.length == 1
            ? S.securitySessionsOne
            : S.securitySessionsMany
                .replaceFirst('%d', toArabicIndic('${ordered.length}')),
        top: 0,
      ),
      const SizedBox(height: AppSpacing.sm),
      for (final session in ordered) ...[
        _SessionCard(
          key: Key('security-session-${session.id}'),
          session: session,
          busy: inFlight.contains(session.id),
          onRevoke: session.current
              ? null
              : () => _confirmRevoke(context, ref, session),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      _Caption(
        hasOthers ? S.securityCurrentSessionNote : S.emptySessionsSub,
        top: 0,
      ),
    ];
  }

  /// Ends one *other* session, after asking.
  ///
  /// The request itself, the duplicate-tap guard and the rule about when the
  /// list may be re-read live in [SessionRevokeController]; this only asks the
  /// question and reports the answer in one line that says whether anything
  /// changed.
  Future<void> _confirmRevoke(
    BuildContext context,
    WidgetRef ref,
    Session session,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(S.securityRevokeConfirm),
        content: const Text(S.securityRevokeConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(S.settingsRevoke),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final outcome =
        await ref.read(sessionRevokeControllerProvider.notifier).revoke(
              session.id,
            );
    // Null means a request for this session was already in flight and this
    // call was dropped — there is nothing new to report.
    if (outcome == null) return;
    final message = _revokeMessage(outcome);
    // An expired session reports nothing here: the router's auth gate is
    // already taking the app out of the authenticated stack, and a snackbar
    // about a session list would land on the sign-in screen.
    if (message == null) return;
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

String? _revokeMessage(SessionRevokeOutcome outcome) => switch (outcome) {
      SessionRevokeOutcome.revoked => S.securityRevokeDone,
      SessionRevokeOutcome.alreadyGone => S.securityRevokeGone,
      SessionRevokeOutcome.notPermitted => S.securityRevokeNotPermitted,
      SessionRevokeOutcome.offline => S.securityRevokeOffline,
      SessionRevokeOutcome.failed => S.securityRevokeFailed,
      SessionRevokeOutcome.sessionExpired => null,
    };

/// A settings row that carries a state chip as well as a destination — the
/// shape [NavigationRow] does not have, used once, for two-step verification.
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    super.key,
    required this.icon,
    required this.label,
    required this.chip,
    required this.action,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Widget chip;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: c.ink2),
      title: Text(label),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Align(alignment: AlignmentDirectional.centerStart, child: chip),
      ),
      trailing: Text(
        action,
        style: TextStyle(
          color: c.primary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      minVerticalPadding: AppSpacing.md,
    );
  }
}

/// One signed-in device.
class _SessionCard extends StatelessWidget {
  const _SessionCard({
    super.key,
    required this.session,
    required this.busy,
    required this.onRevoke,
  });

  final Session session;
  final bool busy;

  /// Null for the current session — ending it is sign-out, and that is the
  /// button at the bottom of the screen.
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: session.current ? c.primary : c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: session.current ? c.okTint : c.mutedTint,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Icon(
                Icons.devices_rounded,
                color: session.current ? c.ok : c.ink2,
                size: 19,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                session.device,
                style: TextStyle(
                  color: c.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (session.current)
              const StatusChip(
                key: Key('security-current-session'),
                kind: StatusKind.ok,
                label: S.securityCurrentSession,
              )
            else
              TextButton(
                key: Key('security-revoke-${session.id}'),
                // Disabled while its own request is in flight. The controller
                // drops a duplicate anyway — this is so the row says so.
                onPressed: busy ? null : onRevoke,
                child: busy
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c.ink3,
                        ),
                      )
                    : const Text(S.settingsRevoke),
              ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            Expanded(
              child: Text(
                session.locationLabel,
                style: TextStyle(color: c.ink3, fontSize: 12),
              ),
            ),
            // Already masked on the wire — the contract guarantees it, and
            // nothing here unmasks or reconstructs it.
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                session.ipMasked,
                style: TextStyle(color: c.ink3, fontSize: 12),
              ),
            ),
          ]),
          const SizedBox(height: AppSpacing.xs),
          // One fact, one string: the day and the clock used to be two
          // `Text`s with a painted ` · ` between them — the dot immediately
          // before a time beginning «٠» (UI audit P1-11) — and a
          // `Directionality` override around the clock. `AppTime.dayTime`
          // owns both decisions: no mark, and the clock in an isolate rather
          // than a direction override that would also catch the Arabic.
          Row(children: [
            Text(S.startedAt, style: TextStyle(color: c.ink3, fontSize: 12)),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                AppTime.dayTime(session.startedAt),
                style: TextStyle(color: c.ink3, fontSize: 12),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

/// A section-sized failure: the app's own copy for the problem, and a retry
/// only when retrying could actually help.
class _SectionProblem extends StatelessWidget {
  const _SectionProblem({
    required this.view,
    required this.onRetry,
    this.showRetry,
  });

  final ProblemView view;
  final VoidCallback onRetry;

  /// Defaults to the resolved problem's own verdict: `not_permitted` and
  /// `validation` get no retry button, because retrying changes nothing.
  final bool? showRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      key: const Key('security-sessions-problem'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.error_outline_rounded, color: c.crit, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                view.title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ]),
          const SizedBox(height: AppSpacing.xs),
          Text(
            view.message,
            style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
          ),
          if (showRetry ?? view.retryable) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(S.retry),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text, {this.top = AppSpacing.sm});

  final String text;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: AppSpacing.xs,
        end: AppSpacing.xs,
        top: top,
      ),
      child: Text(
        text,
        style: TextStyle(color: context.c.ink3, fontSize: 12, height: 1.5),
      ),
    );
  }
}
