import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result/result.dart';
import '../../../core/sync/uuid_v7.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../l10n/strings.dart';
import '../../auth/presentation/sign_out_action.dart';
import '../data/platform_main_admin_providers.dart';
import '../domain/platform_main_admin_models.dart';
import '../domain/platform_main_admin_repository.dart';
import '../domain/saas_tenant_validation.dart';
import 'platform_main_admin_copy.dart';
import 'saas_tenant_copy.dart';
import 'saas_tenant_routes.dart';
import 'widgets/platform_confirmation_dialog.dart';
import 'widgets/platform_page.dart';

/// Full-page replacement draft. The backend alone decides and applies the
/// seat transition after the operator confirms exactly once.
class PlatformMainAdminReplacePage extends ConsumerStatefulWidget {
  const PlatformMainAdminReplacePage({
    super.key,
    required this.tenantId,
  });

  final String tenantId;

  @override
  ConsumerState<PlatformMainAdminReplacePage> createState() =>
      _PlatformMainAdminReplacePageState();
}

class _PlatformMainAdminReplacePageState
    extends ConsumerState<PlatformMainAdminReplacePage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _reason = TextEditingController();
  var _validated = false;
  String? _emailServerError;
  String? _reasonServerError;
  String? _feedback;
  String? _attemptKey;
  String? _attemptFingerprint;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(mainAdminAccountProvider(widget.tenantId));
    await ref.read(mainAdminAccountProvider(widget.tenantId).future);
  }

  void _changed() {
    setState(() {
      _emailServerError = null;
      _reasonServerError = null;
      _feedback = null;
      _attemptKey = null;
      _attemptFingerprint = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(mainAdminAccountProvider(widget.tenantId));
    return PlatformPage(
      title: S.mainAdminReplaceTitle,
      onRefresh: _refresh,
      children: _content(async),
    );
  }

  List<Widget> _content(
    AsyncValue<Result<MainAdminAccountSnapshot>> async,
  ) {
    if (async.isLoading && !async.hasValue) {
      return const [_ReplaceSkeleton()];
    }
    if (async.hasError || !async.hasValue) {
      return [ErrorStateView(onRetry: _refresh)];
    }
    return async.requireValue.when(
      success: (snapshot, {stale = false}) {
        final view = ref.watch(mainAdminManagementProvider(widget.tenantId));
        if (view == null) return const [_ReplaceSkeleton()];
        if (!view.can(MainAdminAction.replace)) {
          return [
            EmptyState(
              key: const Key('main-admin-replace-unavailable'),
              icon: view.isUnsupported
                  ? Icons.help_outline_rounded
                  : Icons.lock_clock_outlined,
              title: view.isUnsupported
                  ? S.mainAdminUnsupportedTitle
                  : S.mainAdminReplaceTitle,
              body: view.isUnsupported
                  ? S.mainAdminUnsupportedBody
                  : S.mainAdminInvalidTransition,
              actionLabel: S.close,
              onAction: () => context.pop(),
            ),
          ];
        }
        return [
          _ReplaceForm(
            view: view,
            name: _name,
            email: _email,
            reason: _reason,
            validated: _validated,
            emailServerError: _emailServerError,
            reasonServerError: _reasonServerError,
            feedback: _feedback,
            submitting:
                ref.watch(mainAdminActionControllerProvider).isSubmitting,
            onChanged: _changed,
            onSubmit: () => _submit(view),
          ),
        ];
      },
      failure: (_, code) {
        final parsed = MainAdminProblemCode.parse(code);
        if (parsed == MainAdminProblemCode.tenantAlreadyDeleted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.go(SaasTenantRoutes.detail(widget.tenantId));
          });
          return const [SizedBox(key: Key('main-admin-replace-deleted'))];
        }
        if (parsed == MainAdminProblemCode.notPermitted) {
          return const [
            EmptyState(
              key: Key('main-admin-replace-not-permitted'),
              icon: Icons.lock_outline_rounded,
              title: S.mainAdminSummaryUnavailable,
              body: S.mainAdminNotPermitted,
            ),
          ];
        }
        return [
          ErrorStateView(
            key: const Key('main-admin-replace-failure'),
            body: S.mainAdminFailure,
            onRetry: _refresh,
          ),
        ];
      },
      offline: (_) => [
        EmptyState(
          key: const Key('main-admin-replace-offline'),
          icon: Icons.cloud_off_rounded,
          title: S.offlineTitle,
          body: S.mainAdminOfflineAction,
          actionLabel: S.retry,
          onAction: _refresh,
        ),
      ],
    );
  }

  Future<void> _submit(MainAdminManagementView view) async {
    setState(() {
      _validated = true;
      _emailServerError = null;
      _reasonServerError = null;
      _feedback = null;
    });

    final normalizedEmail = normalizeMainAdminEmail(_email.text);
    final nameError = validateMainAdminName(_name.text);
    final emailError = validateMainAdminEmail(_email.text);
    final reason = normalizeMainAdminReason(_reason.text);
    final same = normalizedEmail == view.snapshot.current.loginEmail;
    if (nameError != null ||
        emailError != null ||
        same ||
        !isValidMainAdminReason(reason)) {
      setState(() {
        if (same) _emailServerError = S.mainAdminEmailSame;
      });
      return;
    }

    final normalizedName = normalizeMainAdminName(_name.text);
    final confirmed = await showPlatformConfirmationSpec(
      context: context,
      title: S.mainAdminVerifyEmail,
      identity: normalizedEmail,
      identityLtr: true,
      change: MainAdminCopy.replacementChange(
        mode: view.replacementMode,
        oldName: view.snapshot.current.displayName,
        newName: normalizedName,
      ),
      unchanged: S.mainAdminReplaceUnchanged,
      confirmLabel: S.mainAdminReplace,
      severity: PlatformConfirmationSeverity.warning,
      dismissLabel: S.mainAdminDismiss,
    );
    if (!confirmed || !mounted) return;

    final fingerprint = [
      view.snapshot.revision,
      normalizedName,
      normalizedEmail,
      reason,
    ].join('|');
    if (_attemptFingerprint != fingerprint || _attemptKey == null) {
      _attemptFingerprint = fingerprint;
      _attemptKey = mainAdminIdempotencyKey(
        MainAdminAction.replace,
        uuidV7(),
      );
    }

    final outcome =
        await ref.read(mainAdminActionControllerProvider.notifier).replace(
              ReplaceMainAdminCommand(
                tenantId: widget.tenantId,
                expectedRevision: view.snapshot.revision,
                idempotencyKey: _attemptKey!,
                designate: MainAdminDesignateIdentity(
                  displayName: normalizedName,
                  loginEmail: normalizedEmail,
                ),
                reason: reason,
              ),
            );
    if (!mounted) return;
    await _showOutcome(outcome);
  }

  Future<void> _showOutcome(MainAdminActionOutcome outcome) async {
    switch (outcome) {
      case MainAdminActionSucceeded():
        context.pop();
      case MainAdminActionIgnored():
        return;
      case MainAdminActionOffline():
        setState(() => _feedback = S.mainAdminOfflineAction);
      case MainAdminActionStale():
        setState(() => _feedback = S.mainAdminStaleAction);
      case MainAdminActionRecentAuthRequired():
        await _showRecentAuth();
      case MainAdminActionNotPermitted():
        setState(() => _feedback = S.mainAdminNotPermitted);
      case MainAdminActionTenantUnavailable(:final code):
        if (code == MainAdminProblemCode.tenantAlreadyDeleted) {
          context.go(SaasTenantRoutes.detail(widget.tenantId));
        } else {
          setState(() => _feedback = MainAdminCopy.problem(code));
        }
      case MainAdminActionRejected(:final code):
        switch (code) {
          case MainAdminProblemCode.invalidIdentity ||
                MainAdminProblemCode.identityUnavailable:
            setState(() => _emailServerError = MainAdminCopy.problem(code));
          case MainAdminProblemCode.invalidReason:
            setState(() => _reasonServerError = MainAdminCopy.problem(code));
          case MainAdminProblemCode.replacementAlreadyPending:
            context.pop();
          case MainAdminProblemCode.idempotencyConflict ||
                MainAdminProblemCode.invalidTransition ||
                MainAdminProblemCode.setupResendThrottled ||
                MainAdminProblemCode.staleMainAdmin ||
                MainAdminProblemCode.tenantNotFound ||
                MainAdminProblemCode.tenantNotEligible ||
                MainAdminProblemCode.tenantAlreadyDeleted ||
                MainAdminProblemCode.recentAuthenticationRequired ||
                MainAdminProblemCode.notPermitted:
            setState(() => _feedback = MainAdminCopy.problem(code));
        }
      case MainAdminActionFailed():
        setState(() => _feedback = S.mainAdminFailure);
    }
  }

  Future<void> _showRecentAuth() async {
    final signOut = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        key: const Key('main-admin-replace-recent-auth'),
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

class _ReplaceForm extends StatelessWidget {
  const _ReplaceForm({
    required this.view,
    required this.name,
    required this.email,
    required this.reason,
    required this.validated,
    required this.emailServerError,
    required this.reasonServerError,
    required this.feedback,
    required this.submitting,
    required this.onChanged,
    required this.onSubmit,
  });

  final MainAdminManagementView view;
  final TextEditingController name;
  final TextEditingController email;
  final TextEditingController reason;
  final bool validated;
  final String? emailServerError;
  final String? reasonServerError;
  final String? feedback;
  final bool submitting;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final nameError = validated
        ? MainAdminCopy.nameError(validateMainAdminName(name.text))
        : null;
    final emailError = emailServerError ??
        (validated
            ? MainAdminCopy.emailError(validateMainAdminEmail(email.text))
            : null);
    final reasonError = reasonServerError ??
        (validated &&
                !isValidMainAdminReason(normalizeMainAdminReason(reason.text))
            ? S.mainAdminReasonRequired
            : null);

    final current = view.snapshot.current;
    final t = Theme.of(context).textTheme;

    return Column(
      key: const Key('main-admin-replace-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Who is being replaced, before anything is typed. Read-only
        // context, not a field.
        Semantics(
          container: true,
          child: Column(
            key: const Key('main-admin-replace-current'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.mainAdminSeatTitle, style: t.labelMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(current.displayName, style: t.titleMedium),
              TechnicalText(current.loginEmail),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: context.c.infoTint,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: context.c.info, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child:
                    Text(MainAdminCopy.replacementMode(view.replacementMode)),
              ),
            ],
          ),
        ),
        if (feedback != null) ...[
          const SizedBox(height: AppSpacing.md),
          Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: context.c.warnTint,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: context.c.warn, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      feedback!,
                      key: const Key('main-admin-replace-feedback'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        TextField(
          key: const Key('main-admin-replace-name'),
          controller: name,
          maxLength: kMainAdminNameMaxLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          textInputAction: TextInputAction.next,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            labelText: S.mainAdminNewName,
            errorText: nameError,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // Only the typed address runs LTR; its Arabic label, helper and
        // error stay in the page's RTL flow so their punctuation lands on
        // the correct side.
        TextField(
          key: const Key('main-admin-replace-email'),
          controller: email,
          textDirection: TextDirection.ltr,
          maxLength: kMainAdminEmailMaxLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            labelText: S.mainAdminNewEmail,
            helperText: S.mainAdminEmailImmutableHelp,
            helperMaxLines: 3,
            errorText: emailError,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const Key('main-admin-replace-reason'),
          controller: reason,
          maxLength: kMainAdminReasonMaxLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          minLines: 3,
          maxLines: 5,
          textInputAction: TextInputAction.newline,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            labelText: S.mainAdminReasonLabel,
            hintText: S.mainAdminReasonHint,
            helperText: S.mainAdminReasonHelp,
            helperMaxLines: 3,
            errorText: reasonError,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          key: const Key('main-admin-replace-submit'),
          onPressed: submitting ? null : onSubmit,
          icon: submitting
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.fact_check_outlined),
          label: const Text(S.mainAdminReplaceSubmit),
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size.fromHeight(48)),
          ),
        ),
      ],
    );
  }
}

class _ReplaceSkeleton extends StatelessWidget {
  const _ReplaceSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
        key: Key('main-admin-replace-loading'),
        children: [
          SkeletonRow(),
          SizedBox(height: AppSpacing.lg),
          Skeleton(width: double.infinity, height: 56),
          SizedBox(height: AppSpacing.md),
          Skeleton(width: double.infinity, height: 56),
          SizedBox(height: AppSpacing.md),
          Skeleton(width: double.infinity, height: 120),
        ],
      );
}
