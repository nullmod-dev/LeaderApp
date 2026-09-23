import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/saas_tenant_status.dart';
import '../../../core/result/result.dart';
import '../../../core/sync/uuid_v7.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/clock.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/reading_column.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../../auth/presentation/sign_out_action.dart';
import '../data/platform_main_admin_providers.dart';
import '../domain/platform_main_admin_models.dart';
import '../domain/platform_main_admin_repository.dart';
import 'platform_main_admin_copy.dart';
import 'saas_tenant_copy.dart';
import 'saas_tenant_routes.dart';
import 'widgets/platform_confirmation_dialog.dart';
import 'widgets/platform_page.dart';

/// `/platform/tenants/:tenantId/main-admin`.
///
/// The page only renders the Point 14A seat read model and delegates every
/// mutation to the single-flight controller. It never assigns a role or seat
/// locally and never touches tenant operational repositories.
class PlatformMainAdminPage extends ConsumerStatefulWidget {
  const PlatformMainAdminPage({super.key, required this.tenantId});

  final String tenantId;

  @override
  ConsumerState<PlatformMainAdminPage> createState() =>
      _PlatformMainAdminPageState();
}

class _PlatformMainAdminPageState extends ConsumerState<PlatformMainAdminPage> {
  String? _feedback;
  StatusKind _feedbackKind = StatusKind.warn;

  Future<void> _refresh() async {
    ref.invalidate(mainAdminAccountProvider(widget.tenantId));
    await ref.read(mainAdminAccountProvider(widget.tenantId).future);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(mainAdminAccountProvider(widget.tenantId));
    return PlatformPage(
      title: S.mainAdminTitle,
      onRefresh: _refresh,
      children: _content(async),
    );
  }

  List<Widget> _content(
    AsyncValue<Result<MainAdminAccountSnapshot>> async,
  ) {
    if (async.isLoading && !async.hasValue) {
      return const [_MainAdminSkeleton()];
    }
    if (async.hasError || !async.hasValue) {
      return [ErrorStateView(onRetry: _refresh)];
    }

    return async.requireValue.when(
      success: (snapshot, {stale = false}) {
        final view = ref.watch(mainAdminManagementProvider(widget.tenantId));
        if (view == null) return const [_MainAdminSkeleton()];
        return [
          if (_feedback != null) ...[
            _FeedbackBanner(kind: _feedbackKind, message: _feedback!),
            const SizedBox(height: AppSpacing.lg),
          ],
          _ManagementBody(
            view: view,
            now: ref.watch(clockProvider)(),
            busy: ref.watch(mainAdminActionControllerProvider),
            onAction: _confirmAndRun,
            onRefresh: _refresh,
          ),
        ];
      },
      failure: (_, code) => _failure(code),
      offline: (cached) {
        if (cached == null) {
          return [
            EmptyState(
              key: const Key('main-admin-offline-empty'),
              icon: Icons.cloud_off_rounded,
              title: S.offlineTitle,
              body: S.mainAdminOfflineNoData,
              actionLabel: S.retry,
              onAction: _refresh,
            ),
          ];
        }
        final view = ref.watch(mainAdminManagementProvider(widget.tenantId));
        if (view == null) return const [_MainAdminSkeleton()];
        return [
          if (_feedback != null) ...[
            _FeedbackBanner(kind: _feedbackKind, message: _feedback!),
            const SizedBox(height: AppSpacing.lg),
          ],
          _ManagementBody(
            view: view,
            now: ref.watch(clockProvider)(),
            busy: ref.watch(mainAdminActionControllerProvider),
            onAction: _confirmAndRun,
            onRefresh: _refresh,
          ),
        ];
      },
    );
  }

  List<Widget> _failure(String? wireCode) {
    final code = MainAdminProblemCode.parse(wireCode);
    if (code == MainAdminProblemCode.tenantAlreadyDeleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(SaasTenantRoutes.detail(widget.tenantId));
      });
      return const [SizedBox(key: Key('main-admin-deleted-redirect'))];
    }
    if (code == MainAdminProblemCode.tenantNotFound) {
      return [
        EmptyState(
          key: const Key('main-admin-tenant-not-found'),
          icon: Icons.search_off_rounded,
          title: S.platformTenantNotFoundTitle,
          body: S.platformTenantNotFoundBody,
          actionLabel: S.platformTenantBackToList,
          onAction: () => context.go(SaasTenantRoutes.list),
        ),
      ];
    }
    if (code == MainAdminProblemCode.notPermitted) {
      return const [
        EmptyState(
          key: Key('main-admin-not-permitted'),
          icon: Icons.lock_outline_rounded,
          title: S.mainAdminSummaryUnavailable,
          body: S.mainAdminNotPermitted,
        ),
      ];
    }
    return [
      ErrorStateView(
        key: const Key('main-admin-failure'),
        body: S.mainAdminFailure,
        onRetry: _refresh,
      ),
    ];
  }

  Future<void> _confirmAndRun(
    MainAdminAction action,
    MainAdminManagementView view,
  ) async {
    final snapshot = view.snapshot;
    Future<MainAdminActionOutcome>? pending;
    final controller = ref.read(mainAdminActionControllerProvider.notifier);

    switch (action) {
      case MainAdminAction.resendSetup ||
            MainAdminAction.resendReplacementSetup:
        // Name the recipient: with a replacement pending, the designate —
        // not the current holder — is the one whose invitation is resent.
        final recipient = action == MainAdminAction.resendSetup
            ? snapshot.current.loginEmail
            : snapshot.replacement?.designate.loginEmail;
        final confirmed = await showPlatformConfirmationSpec(
          context: context,
          title: S.mainAdminResendConfirmTitle,
          identity: recipient,
          identityLtr: true,
          change: S.mainAdminResendConfirmChange,
          unchanged: S.mainAdminResendConfirmUnchanged,
          confirmLabel: MainAdminCopy.action(action, view),
          dismissLabel: S.mainAdminDismiss,
        );
        if (!confirmed || !mounted) return;
        pending = controller.resendSetup(
          ResendMainAdminSetupCommand(
            tenantId: widget.tenantId,
            expectedRevision: snapshot.revision,
            idempotencyKey: _key(action),
            target: action == MainAdminAction.resendSetup
                ? MainAdminSetupTarget.current
                : MainAdminSetupTarget.replacement,
          ),
        );
      case MainAdminAction.suspend:
        final reason = await showDialog<String>(
          context: context,
          useRootNavigator: true,
          builder: (_) => _SuspendMainAdminDialog(account: snapshot.current),
        );
        if (reason == null || !mounted) return;
        pending = controller.suspend(
          SuspendMainAdminCommand(
            tenantId: widget.tenantId,
            expectedRevision: snapshot.revision,
            idempotencyKey: _key(action),
            reason: reason,
          ),
        );
      case MainAdminAction.reactivate:
        final confirmed = await showPlatformConfirmationSpec(
          context: context,
          title: S.mainAdminReactivateConfirmTitle,
          identity: snapshot.current.displayName,
          change: S.mainAdminReactivateConfirmChange,
          unchanged: S.mainAdminReactivateConfirmUnchanged,
          confirmLabel: S.mainAdminReactivate,
          dismissLabel: S.mainAdminDismiss,
        );
        if (!confirmed || !mounted) return;
        pending = controller.reactivate(
          ReactivateMainAdminCommand(
            tenantId: widget.tenantId,
            expectedRevision: snapshot.revision,
            idempotencyKey: _key(action),
          ),
        );
      case MainAdminAction.replace:
        context.push(SaasTenantRoutes.mainAdminReplace(widget.tenantId));
        return;
      case MainAdminAction.cancelReplacement:
        final replacement = snapshot.replacement;
        if (replacement == null) return;
        final confirmed = await showPlatformConfirmationSpec(
          context: context,
          title: S.mainAdminCancelConfirmTitle,
          change: MainAdminCopy.cancelChange(
            replacement.designate.displayName,
          ),
          unchanged: S.mainAdminCancelConfirmUnchanged,
          confirmLabel: S.mainAdminCancelReplacement,
          severity: PlatformConfirmationSeverity.warning,
          dismissLabel: S.mainAdminDismiss,
        );
        if (!confirmed || !mounted) return;
        pending = controller.cancelReplacement(
          CancelMainAdminReplacementCommand(
            tenantId: widget.tenantId,
            expectedRevision: snapshot.revision,
            idempotencyKey: _key(action),
            replacementId: replacement.id,
          ),
        );
    }

    final outcome = await pending;
    if (!mounted) return;
    await _showOutcome(outcome);
  }

  String _key(MainAdminAction action) =>
      mainAdminIdempotencyKey(action, uuidV7());

  Future<void> _showOutcome(MainAdminActionOutcome outcome) async {
    switch (outcome) {
      case MainAdminActionSucceeded(:final result):
        setState(() => _feedback = null);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(MainAdminCopy.success(result.effect))),
          );
      case MainAdminActionIgnored():
        return;
      case MainAdminActionOffline():
        _setFeedback(S.mainAdminOfflineAction);
      case MainAdminActionStale():
        _setFeedback(S.mainAdminStaleAction);
      case MainAdminActionRecentAuthRequired():
        await _showRecentAuth();
      case MainAdminActionNotPermitted():
        _setFeedback(S.mainAdminNotPermitted, kind: StatusKind.crit);
      case MainAdminActionTenantUnavailable(:final code):
        if (code == MainAdminProblemCode.tenantAlreadyDeleted) {
          context.go(SaasTenantRoutes.detail(widget.tenantId));
        } else {
          _setFeedback(MainAdminCopy.problem(code));
        }
      case MainAdminActionRejected(:final code):
        _setFeedback(
          MainAdminCopy.problem(code),
          kind: code == MainAdminProblemCode.idempotencyConflict
              ? StatusKind.crit
              : StatusKind.warn,
        );
      case MainAdminActionFailed():
        _setFeedback(S.mainAdminFailure, kind: StatusKind.crit);
    }
  }

  void _setFeedback(String message, {StatusKind kind = StatusKind.warn}) {
    setState(() {
      _feedback = message;
      _feedbackKind = kind;
    });
  }

  Future<void> _showRecentAuth() async {
    final signOut = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        key: const Key('main-admin-recent-auth'),
        title: const Text(S.mainAdminRecentAuthTitle),
        content: const Text(S.mainAdminRecentAuthBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(S.close),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(S.signOut),
          ),
        ],
      ),
    );
    if (signOut == true && mounted) await signOutAndLeave(context, ref);
  }
}

class _ManagementBody extends StatelessWidget {
  const _ManagementBody({
    required this.view,
    required this.now,
    required this.busy,
    required this.onAction,
    required this.onRefresh,
  });

  final MainAdminManagementView view;
  final DateTime now;
  final MainAdminActionState busy;
  final void Function(MainAdminAction, MainAdminManagementView) onAction;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final snapshot = view.snapshot;
    final lifecycle = snapshot.tenant.lifecycleStatus;
    final status = view.freshness;
    final freshness = switch (status) {
      MainAdminFreshness.confirmed => null,
      MainAdminFreshness.stale => const StatusChip(
          key: Key('main-admin-stale'),
          kind: StatusKind.muted,
          icon: Icons.history_rounded,
          label: S.staleData,
        ),
      MainAdminFreshness.offline => const StatusChip(
          key: Key('main-admin-offline-cached'),
          kind: StatusKind.warn,
          icon: Icons.cloud_off_rounded,
          label: S.offlineTitle,
        ),
    };

    // Each column is its own semantics group so a screen reader finishes the
    // seat before the actions even when the two sit side by side (≥900dp).
    final seat = Semantics(
      container: true,
      child: _SeatCard(snapshot: snapshot, now: now),
    );
    final side = Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (view.tenantBlocksAccessPaths) ...[
            _TenantBoundary(status: lifecycle),
            const SizedBox(height: AppSpacing.lg),
          ],
          _Actions(
            view: view,
            busy: busy,
            onAction: onAction,
            onRefresh: onRefresh,
          ),
          const SizedBox(height: AppSpacing.lg),
          const _Limitations(),
        ],
      ),
    );

    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            header: true,
            child: Text(snapshot.tenant.displayName,
                style: Theme.of(context).textTheme.titleLarge),
          ),
          const SizedBox(height: AppSpacing.sm),
          // The team's access state lives with the team name, apart from the
          // account chip inside the seat card: two labelled states, never one
          // colour standing in for both.
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              StatusChip(
                key: const Key('main-admin-tenant-access'),
                kind: MainAdminCopy.tenantAccessKind(lifecycle),
                icon: MainAdminCopy.tenantAccessIcon(lifecycle),
                label: MainAdminCopy.tenantAccess(lifecycle),
              ),
              if (freshness != null) freshness,
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          if (view.isUnsupported) ...[
            const _UnsupportedBanner(),
            const SizedBox(height: AppSpacing.lg),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = MediaQuery.sizeOf(context).width >= 900;
              if (!wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    seat,
                    const SizedBox(height: AppSpacing.xl),
                    side,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: seat),
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(flex: 5, child: side),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SeatCard extends StatelessWidget {
  const _SeatCard({required this.snapshot, required this.now});

  final MainAdminAccountSnapshot snapshot;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final current = snapshot.current;
    return Container(
      key: const Key('main-admin-seat-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            header: true,
            child: Text(S.mainAdminSeatTitle,
                style: Theme.of(context).textTheme.titleSmall),
          ),
          const SizedBox(height: AppSpacing.lg),
          _IdentityHeader(account: current),
          const SizedBox(height: AppSpacing.lg),
          _CurrentFacts(account: current, now: now),
          if (snapshot.replacement case final replacement?) ...[
            const SizedBox(height: AppSpacing.lg),
            Divider(color: c.line),
            const SizedBox(height: AppSpacing.lg),
            _ReplacementBlock(
              current: current,
              replacement: replacement,
              now: now,
            ),
          ],
        ],
      ),
    );
  }
}

class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({required this.account});

  final MainAdminAccount account;

  @override
  // One group: the name and the explicitly-labelled account status merge
  // into it (read once each); the selectable email stays its own node.
  Widget build(BuildContext context) => Semantics(
        container: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.c.primaryTint,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: ExcludeSemantics(
                child: Icon(Icons.admin_panel_settings_outlined,
                    color: context.c.primary),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(account.displayName,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  TechnicalText(
                    account.loginEmail,
                    key: const Key('main-admin-current-email'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Semantics(
                    label: '${S.mainAdminAccountStatus}: '
                        '${MainAdminCopy.status(account.status)}',
                    excludeSemantics: true,
                    child: StatusChip(
                      key: const Key('main-admin-account-status'),
                      kind: MainAdminCopy.statusKind(account.status),
                      icon: MainAdminCopy.statusIcon(account.status),
                      label: MainAdminCopy.status(account.status),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _CurrentFacts extends StatelessWidget {
  const _CurrentFacts({required this.account, required this.now});

  final MainAdminAccount account;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    switch (account.status) {
      case MainAdminAccountStatus.pendingSetup:
        return _SetupFacts(setup: account.setup!, now: now);
      case MainAdminAccountStatus.active:
        return _Fact(
          icon: Icons.event_available_outlined,
          label: S.mainAdminActivatedAt,
          value: MainAdminCopy.timestamp(account.activatedAt!),
        );
      case MainAdminAccountStatus.suspended:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Fact(
              icon: Icons.event_busy_outlined,
              label: S.mainAdminSuspendedAt,
              value: MainAdminCopy.timestamp(
                account.suspension!.suspendedAt,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(S.mainAdminPlatformReason,
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(account.suspension!.reason),
          ],
        );
      case MainAdminAccountStatus.revoked || MainAdminAccountStatus.unknown:
        return const SizedBox.shrink();
    }
  }
}

class _ReplacementBlock extends StatelessWidget {
  const _ReplacementBlock({
    required this.current,
    required this.replacement,
    required this.now,
  });

  final MainAdminAccount current;
  final MainAdminReplacement replacement;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final designate = replacement.designate;
    // The "not yet authorized" sentence is inside the block and merges into
    // this group; repeating it as a label read it twice.
    return Semantics(
      key: const Key('main-admin-replacement-pending'),
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.c.infoTint,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const StatusChip(
              kind: StatusKind.info,
              icon: Icons.hourglass_top_rounded,
              label: S.mainAdminReplacementPending,
            ),
            const SizedBox(height: AppSpacing.md),
            Semantics(
              container: true,
              header: true,
              child: Text(S.mainAdminDesignateTitle,
                  style: Theme.of(context).textTheme.labelMedium),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(designate.displayName,
                style: Theme.of(context).textTheme.titleSmall),
            TechnicalText(
              designate.loginEmail,
              key: const Key('main-admin-designate-email'),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(S.mainAdminDesignateNotAuthorized),
            const SizedBox(height: AppSpacing.md),
            _Fact(
              icon: Icons.schedule_outlined,
              label: S.mainAdminReplacementRequested,
              value: MainAdminCopy.timestamp(replacement.requestedAt),
            ),
            const SizedBox(height: AppSpacing.md),
            _SetupFacts(setup: designate.setup, now: now),
            const SizedBox(height: AppSpacing.md),
            Text(S.mainAdminPlatformReason,
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(replacement.reason),
            const SizedBox(height: AppSpacing.md),
            Text(
              MainAdminCopy.replacementKeepsCurrent(
                current.displayName,
                designate.displayName,
              ),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupFacts extends StatelessWidget {
  const _SetupFacts({required this.setup, required this.now});

  final MainAdminSetupState setup;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final expired =
        setup.effectiveStatusAt(now) == MainAdminSetupStatus.expired;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Fact(
          icon: Icons.outgoing_mail,
          label: S.mainAdminInvitationSent,
          value: MainAdminCopy.timestamp(setup.lastSentAt),
        ),
        if (expired) ...[
          const SizedBox(height: AppSpacing.sm),
          const StatusChip(
            key: Key('main-admin-invitation-expired'),
            kind: StatusKind.warn,
            icon: Icons.timer_off_outlined,
            label: S.mainAdminInvitationExpired,
          ),
        ] else if (setup.expiresAt != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _Fact(
            icon: Icons.timer_outlined,
            label: S.mainAdminInvitationExpires,
            value: MainAdminCopy.timestamp(setup.expiresAt!),
          ),
        ],
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: context.c.ink3),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text('$label: $value',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      );
}

class _TenantBoundary extends StatelessWidget {
  const _TenantBoundary({required this.status});

  final SaasTenantStatus status;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('main-admin-tenant-boundary'),
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.c.warnTint,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.domain_disabled_outlined,
                color: context.c.warn, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(MainAdminCopy.tenantBlocked(status))),
          ],
        ),
      );
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.view,
    required this.busy,
    required this.onAction,
    required this.onRefresh,
  });

  final MainAdminManagementView view;
  final MainAdminActionState busy;
  final void Function(MainAdminAction, MainAdminManagementView) onAction;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final ordered = [
      MainAdminAction.resendSetup,
      MainAdminAction.resendReplacementSetup,
      MainAdminAction.reactivate,
      MainAdminAction.replace,
      MainAdminAction.suspend,
      MainAdminAction.cancelReplacement,
    ].where(view.can).toList();

    return Semantics(
      container: true,
      child: Column(
        key: const Key('main-admin-actions'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            header: true,
            child: Text(S.mainAdminActionsTitle,
                style: Theme.of(context).textTheme.titleSmall),
          ),
          const SizedBox(height: AppSpacing.md),
          // A cached read is not "no actions for this state": say why the
          // page is read-only and offer the read that can lift it.
          if (view.isReadOnly && !view.isUnsupported)
            _ReadOnlyNotice(view: view, onRefresh: onRefresh)
          else if (ordered.isEmpty)
            const Text(S.mainAdminNoActions)
          else
            for (final action in ordered) ...[
              _ActionButton(
                action: action,
                view: view,
                submitting: busy.submitting,
                onPressed: () => onAction(action, view),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    required this.view,
    required this.submitting,
    required this.onPressed,
  });

  final MainAdminAction action;
  final MainAdminManagementView view;
  final MainAdminAction? submitting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final loading = submitting == action;
    final disabled = submitting != null;
    final icon = switch (action) {
      MainAdminAction.resendSetup ||
      MainAdminAction.resendReplacementSetup =>
        Icons.forward_to_inbox_outlined,
      MainAdminAction.reactivate => Icons.play_circle_outline_rounded,
      MainAdminAction.replace => Icons.swap_horiz_rounded,
      MainAdminAction.suspend => Icons.block_rounded,
      MainAdminAction.cancelReplacement => Icons.cancel_outlined,
    };
    // Only suspension ends someone's access. Cancelling a replacement leaves
    // the current holder untouched, so it stays a neutral action — one red
    // button per page at most.
    final destructive = action == MainAdminAction.suspend;
    final primary = action == MainAdminAction.resendSetup ||
        action == MainAdminAction.resendReplacementSetup ||
        action == MainAdminAction.reactivate;
    final child = loading
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(MainAdminCopy.action(action, view));
    final buttonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
      foregroundColor:
          destructive ? WidgetStatePropertyAll(context.c.crit) : null,
    );

    if (primary) {
      return FilledButton.icon(
        key: Key('main-admin-action-${action.wire}'),
        onPressed: disabled ? null : onPressed,
        icon: Icon(icon),
        label: child,
        style: buttonStyle,
      );
    }
    return OutlinedButton.icon(
      key: Key('main-admin-action-${action.wire}'),
      onPressed: disabled ? null : onPressed,
      icon: Icon(icon),
      label: child,
      style: buttonStyle,
    );
  }
}

class _Limitations extends StatelessWidget {
  const _Limitations();

  @override
  Widget build(BuildContext context) => Material(
        color: context.c.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: context.c.line),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        clipBehavior: Clip.antiAlias,
        child: const ExpansionTile(
          key: Key('main-admin-limitations'),
          title: Text(S.mainAdminLimitationsTitle),
          childrenPadding: EdgeInsetsDirectional.fromSTEB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          children: [Text(S.mainAdminLimitationsBody)],
        ),
      );
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice({required this.view, required this.onRefresh});

  final MainAdminManagementView view;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final offline = view.freshness == MainAdminFreshness.offline;
    return Container(
      key: const Key('main-admin-read-only'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.c.mutedTint,
        border: Border.all(color: context.c.line),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                offline ? Icons.cloud_off_rounded : Icons.history_rounded,
                size: 20,
                color: context.c.ink3,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  offline
                      ? S.mainAdminReadOnlyOffline
                      : S.mainAdminReadOnlyStale,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _Fact(
            icon: Icons.update_rounded,
            label: S.mainAdminLastRead,
            value: MainAdminCopy.timestamp(view.snapshot.readAt),
          ),
          const SizedBox(height: AppSpacing.md),
          // A read, never a write: it re-asks the backend and replays nothing.
          OutlinedButton.icon(
            key: const Key('main-admin-read-only-refresh'),
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(S.mainAdminRefresh),
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size.fromHeight(48)),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnsupportedBanner extends StatelessWidget {
  const _UnsupportedBanner();

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('main-admin-unsupported'),
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.c.warnTint,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.help_outline_rounded, color: context.c.warn, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.mainAdminUnsupportedTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(S.mainAdminUnsupportedBody),
                ],
              ),
            ),
          ],
        ),
      );
}

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.kind, required this.message});

  final StatusKind kind;
  final String message;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, icon) = switch (kind) {
      StatusKind.crit => (
          context.c.critTint,
          context.c.crit,
          Icons.error_outline_rounded
        ),
      StatusKind.info => (
          context.c.infoTint,
          context.c.info,
          Icons.info_outline_rounded
        ),
      StatusKind.ok => (
          context.c.okTint,
          context.c.ok,
          Icons.check_circle_outline_rounded
        ),
      StatusKind.warn || StatusKind.muted => (
          context.c.warnTint,
          context.c.warn,
          Icons.warning_amber_rounded
        ),
    };
    return Semantics(
      key: const Key('main-admin-feedback'),
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _SuspendMainAdminDialog extends StatefulWidget {
  const _SuspendMainAdminDialog({required this.account});

  final MainAdminAccount account;

  @override
  State<_SuspendMainAdminDialog> createState() =>
      _SuspendMainAdminDialogState();
}

class _SuspendMainAdminDialogState extends State<_SuspendMainAdminDialog> {
  final _controller = TextEditingController();
  var _touched = false;

  String get _reason => normalizeMainAdminReason(_controller.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = isValidMainAdminReason(_reason);
    return AlertDialog(
      key: const Key('main-admin-suspend-dialog'),
      scrollable: true,
      title: const Text(S.mainAdminSuspendConfirmTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kDialogMaxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Whose access ends: the one piece of context a reviewer must
            // see before typing the reason.
            Text(
              widget.account.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TechnicalText(
              widget.account.loginEmail,
              key: const Key('main-admin-suspend-email'),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(S.mainAdminSuspendConsequences),
            const SizedBox(height: AppSpacing.sm),
            const Text(S.mainAdminSuspendUnchanged),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              key: const Key('main-admin-suspend-reason'),
              controller: _controller,
              maxLength: kMainAdminReasonMaxLength,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              minLines: 3,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              onChanged: (_) => setState(() => _touched = true),
              decoration: InputDecoration(
                labelText: S.mainAdminReasonLabel,
                hintText: S.mainAdminReasonHint,
                helperText: S.mainAdminReasonHelp,
                helperMaxLines: 3,
                errorMaxLines: 3,
                errorText:
                    _touched && !valid ? S.mainAdminReasonRequired : null,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(S.mainAdminDismiss),
        ),
        FilledButton(
          key: const Key('main-admin-suspend-confirm'),
          onPressed: valid ? () => Navigator.pop(context, _reason) : null,
          style: FilledButton.styleFrom(
            backgroundColor: context.c.crit,
            foregroundColor: context.c.bg,
          ),
          child: const Text(S.mainAdminSuspend),
        ),
      ],
    );
  }
}

class _MainAdminSkeleton extends StatelessWidget {
  const _MainAdminSkeleton();

  @override
  Widget build(BuildContext context) => Column(
        key: const Key('main-admin-loading'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Skeleton(width: 180, height: 24),
          const SizedBox(height: AppSpacing.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: context.c.surface,
              border: Border.all(color: context.c.line),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: const Column(
              children: [
                SkeletonRow(),
                SizedBox(height: AppSpacing.md),
                SkeletonRow(),
                SizedBox(height: AppSpacing.md),
                SkeletonRow(),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Skeleton(width: double.infinity, height: 48),
          const SizedBox(height: AppSpacing.sm),
          const Skeleton(width: double.infinity, height: 48),
        ],
      );
}
