import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/time/clock.dart';
import '../../../l10n/strings.dart';
import '../../demo/data/demo_control_plane.dart';
import '../../demo/domain/demo_policy.dart';
import '../../../core/widgets/status_chip.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../data/platform_demo_providers.dart';
import 'platform_demo_copy.dart';
import 'platform_operations_routes.dart';
import 'widgets/platform_confirmation_dialog.dart';
import 'widgets/platform_meta.dart';
import 'widgets/platform_page.dart';

/// `/platform/operations/demo` — **إدارة الحسابات التجريبية**.
///
/// The one screen in the product where Customer Demo *policy* is administered,
/// and the only place any Demo control exists outside the trial itself. A Main
/// Admin and a Simple Admin have no Demo surface at all: the trial is a
/// platform offer, not a tenant feature, and a tenant-side switch would be a
/// second answer to a question that has one.
///
/// **Operational, not explanatory.** The Demo is described where somebody is
/// deciding whether to start one — the onboarding chooser — and once, in the
/// in-trial banner. Repeating that copy here would push the two things an
/// operator opens this screen for, the availability switch and the session
/// list, below the fold on a phone. So: a policy card, a three-number summary,
/// the running trials, and the two operations that act on all of them.
///
/// **Authorization is asked for, never assumed.** Nothing here branches on the
/// signed-in role. Every action goes to [PlatformDemoActions], which is
/// refused with `not_authorized` unless the session can build a
/// [DemoPolicyActor] — the same refusal a backend would send, so the screen
/// behaves identically whether the guard is the router's or the control
/// plane's.
class PlatformDemoPage extends ConsumerWidget {
  const PlatformDemoPage({super.key});

  static const routePath = PlatformOperationsRoutes.demo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(activeDemoSessionsProvider);
    return PlatformPage(
      title: S.platformDemoTitle,
      children: [
        const PlatformPageIntro(lead: S.platformDemoLead),
        const SizedBox(height: AppSpacing.lg),
        const SectionLabel(S.platformDemoPolicySection),
        const _PolicyCard(),
        const SectionLabel(S.platformDemoSummarySection),
        const _SessionSummary(),
        const SectionLabel(S.platformDemoActiveSection),
        if (sessions.isEmpty)
          const _EmptyActive()
        else
          SettingsSection(
            children: [
              for (final session in sessions) _SessionRow(session: session),
            ],
          ),
        const SectionLabel(S.platformDemoMaintenanceSection),
        const _Maintenance(),
      ],
    );
  }
}

/// Availability and the default window — the two facts a policy is.
class _PolicyCard extends ConsumerWidget {
  const _PolicyCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final policy = ref.watch(demoPolicyProvider);
    return SettingsSection(
      children: [
        // A switch, and its state also said in words underneath. The colour of
        // a thumb is not a state a screen may communicate on its own.
        SwitchListTile.adaptive(
          key: const Key('platform-demo-enabled'),
          value: policy.enabled,
          onChanged: (next) => _setEnabled(context, ref, next),
          title: const Text(S.platformDemoAvailability),
          subtitle: Text(
            policy.enabled
                ? S.platformDemoAvailabilityOn
                : S.platformDemoAvailabilityOff,
            style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
          ),
          contentPadding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.xs,
          ),
        ),
        Divider(height: 1, color: c.line),
        const _DurationRow(),
        Divider(height: 1, color: c.line),
        _PolicyProvenance(policy: policy),
      ],
    );
  }

  /// Enabling is immediate; disabling is confirmed, because the sentence that
  /// matters is the one about what *does not* happen — the running trials are
  /// not thrown out. An operator who expected them to be would otherwise find
  /// that out from a support message.
  Future<void> _setEnabled(
    BuildContext context, WidgetRef ref, bool next) async {
    if (!next) {
      final confirmed = await showPlatformConfirmation(
        context: context,
        title: S.platformDemoDisableConfirmTitle,
        change: S.platformDemoDisableConfirmChange,
        unchanged: S.platformDemoDisableConfirmUnchanged,
        confirmLabel: S.platformDemoDisableConfirmAction,
        warning: true,
      );
      if (!confirmed || !context.mounted) return;
    }
    final result = ref.read(platformDemoActionsProvider).setEnabled(next);
    if (!context.mounted) return;
    _report(
      context,
      result,
      done: next ? S.platformDemoEnabledDone : S.platformDemoDisabledDone,
    );
  }
}

/// The default window, as a stepper in hours and days.
///
/// Raw minutes are never shown and never entered: an operator sets "a day" or
/// "48 hours", and a text field inviting `1440` would be inviting a typo whose
/// blast radius is every trial started afterwards.
class _DurationRow extends ConsumerWidget {
  const _DurationRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final duration = ref.watch(demoPolicyProvider).defaultDuration;
    final canDecrease = DemoDurationPolicy.canDecrease(duration);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The label owns its line and the stepper owns the next one. Putting
          // them side by side costs «المدة الافتراضية» its ending on a 320dp
          // phone at a 1.6 text scale — and the two step buttons may not
          // shrink below 48dp to make room for it.
          const Text(S.platformDemoDuration),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _StepButton(
                id: 'decrease',
                icon: Icons.remove_rounded,
                tooltip: S.platformDemoDurationDecrease,
                onPressed: canDecrease
                    ? () => _set(
                        context, ref, DemoDurationPolicy.decrement(duration))
                    : null,
              ),
              // Expanded, so the value takes whatever the two fixed targets
              // leave and «١٢ يوما» wraps rather than pushing a button off the
              // edge.
              Expanded(
                child: Text(
                  PlatformDemoCopy.duration(duration),
                  key: const Key('platform-demo-duration-value'),
                  textAlign: TextAlign.center,
                  style: AppTypography.digits(c.ink, size: 15),
                ),
              ),
              _StepButton(
                id: 'increase',
                icon: Icons.add_rounded,
                tooltip: S.platformDemoDurationIncrease,
                onPressed: () => _set(
                    context, ref, DemoDurationPolicy.increment(duration)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            canDecrease
                ? S.platformDemoDurationNote
                : '${S.platformDemoDurationNote} ${S.platformDemoDurationAtMinimum}.',
            style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  void _set(BuildContext context, WidgetRef ref, Duration next) {
    final result = ref.read(platformDemoActionsProvider).setDefaultDuration(next);
    _report(context, result, done: S.platformDemoDurationDone);
  }
}

/// A 48dp target whatever the icon's own size, so the stepper stays usable
/// with a thumb and reachable by a switch-access sweep.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.id,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final String id;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        key: Key('platform-demo-duration-$id'),
        onPressed: onPressed,
        icon: Icon(icon),
        tooltip: tooltip,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      );
}

/// Who last changed the policy, and which revision is in force.
///
/// The revision is not decoration: a session records the revision it started
/// under, so this number is what makes "the change applies to new sessions"
/// checkable rather than merely stated.
class _PolicyProvenance extends StatelessWidget {
  const _PolicyProvenance({required this.policy});

  final DemoPolicy policy;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final updatedAt = policy.updatedAt;
    final by = policy.updatedBy;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            S.platformDemoPolicyUpdatedBy,
            style: TextStyle(color: c.ink3, fontSize: 12),
          ),
          const SizedBox(height: 2),
          if (by == null || updatedAt == null)
            const Text(
              S.platformDemoPolicyNeverUpdated,
              key: Key('platform-demo-policy-updated'),
            )
          else
            PlatformMeta(
              key: const Key('platform-demo-policy-updated'),
              parts: [
                PlatformMetaText(by.displayName, color: c.ink2),
                PlatformMetaText(
                  PlatformTime.dayTime(updatedAt),
                  color: c.ink2,
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.sm),
          PlatformMeta(parts: [
            const PlatformMetaText(S.platformDemoRevision),
            PlatformMetaText(
              PlatformDemoCopy.count('%d', policy.revision),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Three numbers, one line. Not three cards: these are a scale reading, and a
/// card each would make the list below them start off-screen.
class _SessionSummary extends ConsumerWidget {
  const _SessionSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(demoSessionCountsProvider);
    return SettingsSection(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.md,
            children: [
              _Count(
                id: 'active',
                label: S.platformDemoCountActive,
                value: counts.active,
                tone: _CountTone.active,
              ),
              _Count(
                id: 'expired',
                label: S.platformDemoCountExpired,
                value: counts.expired,
                tone: _CountTone.neutral,
              ),
              _Count(
                id: 'terminated',
                label: S.platformDemoCountTerminated,
                value: counts.terminated,
                tone: _CountTone.neutral,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _CountTone { active, neutral }

class _Count extends StatelessWidget {
  const _Count({
    required this.id,
    required this.label,
    required this.value,
    required this.tone,
  });

  final String id;
  final String label;
  final int value;
  final _CountTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          PlatformDemoCopy.count('%d', value),
          key: Key('platform-demo-count-$id'),
          style: AppTypography.digits(
            tone == _CountTone.active ? c.ink : c.ink2,
            size: 22,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
        Text(label, style: TextStyle(color: c.ink3, fontSize: 12)),
      ],
    );
  }
}

class _EmptyActive extends StatelessWidget {
  const _EmptyActive();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SettingsSection(children: [
      Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          S.platformDemoNoActive,
          key: const Key('platform-demo-empty'),
          style: TextStyle(color: c.ink3, fontSize: 13, height: 1.6),
        ),
      ),
    ]);
  }
}

/// One running trial: who holds it, what state it is in, how much of its
/// window is left, and the one action available on it.
///
/// **Two lines and a chip, not five stacked facts.** The row used to be a
/// name and three label/value lines of equal weight, with no status at all —
/// `PlatformDemoCopy.sessionStatus` existed and was never called (UI audit,
/// Demo Management). The remaining time leads the metadata line because it is
/// the figure the list is read for; the start time is last because it never
/// changes what an operator would do.
///
/// **Nothing secret is on this row.** A display name (or the account id, which
/// is an opaque identifier, when the control plane supplies no name), the
/// window and a status. No token, no email, no device.
class _SessionRow extends ConsumerWidget {
  const _SessionRow({required this.session});

  final DemoSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final now = ref.watch(clockProvider)();
    final remaining = session.remainingAt(now);
    // Under an hour is the point at which "when does this end" stops being a
    // detail, so the status word changes too — not only its colour.
    final endingSoon = remaining < const Duration(hours: 1);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline_rounded, size: 18, color: c.ink3),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  session.displayName ?? session.accountId,
                  style: TextStyle(color: c.ink, fontSize: 14),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusChip(
                kind: endingSoon ? StatusKind.warn : StatusKind.ok,
                label: endingSoon
                    ? S.platformDemoSessionEndsSoon
                    : PlatformDemoCopy.sessionStatus(
                        DemoSessionStatus.active,
                      ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          PlatformMeta(parts: [
            _SessionFact(
              label: S.platformDemoSessionRemaining,
              value: PlatformDemoCopy.remaining(remaining),
              tone: endingSoon ? c.warn : c.ink,
              emphasis: true,
            ),
            _SessionFact(
              label: S.platformDemoSessionExpires,
              value: PlatformTime.dayTime(session.expiresAt),
            ),
            _SessionFact(
              label: S.platformDemoSessionStarted,
              value: PlatformTime.dayTime(session.startedAt),
            ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: Key('platform-demo-terminate-${session.demoSessionId}'),
              onPressed: () => _terminate(context, ref),
              style: TextButton.styleFrom(
                foregroundColor: c.crit,
                minimumSize: const Size(48, 48),
              ),
              icon: const Icon(Icons.block_rounded, size: 18),
              label: const Text(S.platformDemoTerminate),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _terminate(BuildContext context, WidgetRef ref) async {
    final confirmed = await showPlatformConfirmationSpec(
      context: context,
      title: S.platformDemoTerminateConfirmTitle,
      change: S.platformDemoTerminateConfirmChange,
      unchanged: S.platformDemoTerminateConfirmUnchanged,
      identity: session.displayName ?? session.accountId,
      confirmLabel: S.platformDemoTerminate,
      severity: PlatformConfirmationSeverity.destructive,
    );
    if (!confirmed || !context.mounted) return;
    final result =
        ref.read(platformDemoActionsProvider).terminate(session.demoSessionId);
    if (!context.mounted) return;
    _report(context, result, done: S.platformDemoTerminatedDone);
  }
}

/// A labelled figure on a session's metadata line.
///
/// The label stays its own `Text` rather than being glued into the value: the
/// two are different weights, and a screen reader that hears «المتبقي» before
/// a duration is hearing the right sentence.
class _SessionFact extends StatelessWidget {
  const _SessionFact({
    required this.label,
    required this.value,
    this.tone,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final Color? tone;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: c.ink3, fontSize: 12)),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            value,
            style: AppTypography.digits(
              tone ?? c.ink2,
              size: 13,
              weight: emphasis ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// The two operations that act on the whole list.
///
/// Both are destructive in their own way, so neither is a row that looks like
/// navigation: they are buttons, the harmful one is critical-coloured, and
/// each states its own non-consequence — the real accounts are untouched, the
/// terminated records are kept.
class _Maintenance extends ConsumerWidget {
  const _Maintenance();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Operation(
          id: 'terminate-all',
          label: S.platformDemoTerminateAll,
          body: S.platformDemoTerminateAllSub,
          tone: c.crit,
          onPressed: () => _terminateAll(context, ref),
        ),
        const SizedBox(height: AppSpacing.sm),
        _Operation(
          id: 'clean-expired',
          label: S.platformDemoCleanExpired,
          body: S.platformDemoCleanExpiredSub,
          tone: c.ink2,
          onPressed: () => _clean(context, ref),
        ),
      ],
    );
  }

  Future<void> _terminateAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showPlatformConfirmationSpec(
      context: context,
      title: S.platformDemoTerminateAllConfirmTitle,
      change: S.platformDemoTerminateAllConfirmChange,
      unchanged: S.platformDemoTerminateAllConfirmUnchanged,
      confirmLabel: S.platformDemoTerminateAll,
      severity: PlatformConfirmationSeverity.destructive,
    );
    if (!confirmed || !context.mounted) return;
    final result = ref.read(platformDemoActionsProvider).terminateAllActive();
    if (!context.mounted) return;
    _reportCount(
      context,
      result,
      done: S.platformDemoTerminatedAllDone,
      none: S.platformDemoNothingToTerminate,
    );
  }

  Future<void> _clean(BuildContext context, WidgetRef ref) async {
    final confirmed = await showPlatformConfirmation(
      context: context,
      title: S.platformDemoCleanConfirmTitle,
      change: S.platformDemoCleanConfirmChange,
      unchanged: S.platformDemoCleanConfirmUnchanged,
      confirmLabel: S.platformDemoCleanExpired,
      warning: true,
    );
    if (!confirmed || !context.mounted) return;
    final result = ref.read(platformDemoActionsProvider).cleanExpired();
    if (!context.mounted) return;
    _reportCount(
      context,
      result,
      done: S.platformDemoCleanedDone,
      none: S.platformDemoNothingToClean,
    );
  }
}

class _Operation extends StatelessWidget {
  const _Operation({
    required this.id,
    required this.label,
    required this.body,
    required this.tone,
    required this.onPressed,
  });

  final String id;
  final String label;
  final String body;
  final Color tone;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            body,
            style: TextStyle(color: c.ink3, fontSize: 12, height: 1.6),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton(
              key: Key('platform-demo-$id'),
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: tone,
                side: BorderSide(color: tone),
                minimumSize: const Size(48, 48),
              ),
              child: Text(label),
            ),
          ),
        ],
      ),
    );
  }
}

/// Says what happened, including when nothing did.
///
/// A refusal is reported in the operator's words rather than the wire code:
/// `not_authorized` means this session may not administer the policy, and
/// `demo_session_not_active` means somebody else — or the clock — got there
/// first, which is information, not an error to swallow.
void _report<T>(BuildContext context, Result<T> result, {required String done}) {
  final message = result.when(
    success: (_, {stale = false}) => done,
    failure: (_, code) => _refusal(code),
    offline: (_) => S.platformDemoNotAuthorized,
  );
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

/// The same, for the two actions whose success is a count. Zero is reported as
/// "there was nothing to do" rather than as a success with an Arabic zero in
/// it, because those read very differently to somebody who just tapped.
void _reportCount(
  BuildContext context,
  Result<int> result, {
  required String done,
  required String none,
}) {
  final message = result.when(
    success: (count, {stale = false}) =>
        count == 0 ? none : PlatformDemoCopy.count(done, count),
    failure: (_, code) => _refusal(code),
    offline: (_) => S.platformDemoNotAuthorized,
  );
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

String _refusal(String? code) => switch (code) {
      DemoControlPlaneCodes.sessionNotFound ||
      DemoControlPlaneCodes.sessionNotActive =>
        S.platformDemoSessionGone,
      _ => S.platformDemoNotAuthorized,
    };
