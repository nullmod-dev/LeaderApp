import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/sync/uuid_v7.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/clock.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../l10n/strings.dart';
import '../data/platform_break_glass_providers.dart';
import '../data/saas_tenant_providers.dart';
import '../domain/platform_break_glass_models.dart';
import '../domain/platform_break_glass_repository.dart';
import '../domain/saas_tenant_models.dart';
import 'platform_break_glass_actions.dart';
import 'platform_operations_routes.dart';
import 'widgets/platform_confirmation_dialog.dart';
import 'widgets/platform_page.dart';

class PlatformBreakGlassRequestPage extends ConsumerStatefulWidget {
  const PlatformBreakGlassRequestPage({super.key});

  @override
  ConsumerState<PlatformBreakGlassRequestPage> createState() =>
      _PlatformBreakGlassRequestPageState();
}

class _PlatformBreakGlassRequestPageState
    extends ConsumerState<PlatformBreakGlassRequestPage> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _search = TextEditingController();
  String? _tenantId;
  String? _attemptKey;
  String? _attemptFingerprint;

  @override
  void dispose() {
    _reason.dispose();
    _search.dispose();
    super.dispose();
  }

  String? _reasonError(String? raw) {
    final normalized = normalizeBreakGlassReason(raw ?? '');
    if (normalized.isEmpty) return S.breakGlassReasonRequired;
    if (normalized.length > kBreakGlassReasonMaxLength) {
      return S.breakGlassReasonTooLong;
    }
    return null;
  }

  Future<void> _submit(SaasTenant tenant, {required bool online}) async {
    if (!_formKey.currentState!.validate()) return;
    if (!online) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(S.breakGlassOfflineAction)),
      );
      return;
    }

    // The picker may have been built from a stale page. Recheck the canonical
    // Platform lifecycle projection immediately before asking the backend;
    // the backend still repeats this check authoritatively.
    final currentStatus =
        ref.read(platformTenantStoreProvider).lifecycleStatusOf(tenant.id);
    if (tenant.tenantStatus != SaasTenantStatus.active ||
        currentStatus != SaasTenantStatus.active) {
      setState(() => _tenantId = null);
      ref.invalidate(breakGlassEligibleTenantsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(S.breakGlassTenantChanged)),
        );
      }
      return;
    }

    final reason = normalizeBreakGlassReason(_reason.text);
    final confirmed = await showPlatformConfirmationSpec(
      context: context,
      title: S.breakGlassActivateAction,
      identity: tenant.displayName,
      change: '${S.breakGlassActivationChange}\n'
          '${S.breakGlassReasonLabel}: $reason',
      unchanged: S.breakGlassActivationUnchanged,
      effective: S.breakGlassActivationEffective,
      confirmLabel: S.breakGlassActivateAction,
      severity: PlatformConfirmationSeverity.warning,
    );
    if (!confirmed || !mounted) return;

    final fingerprint = '${tenant.id}|${tenant.tenantVersion}|$reason';
    if (_attemptFingerprint != fingerprint || _attemptKey == null) {
      _attemptFingerprint = fingerprint;
      _attemptKey = breakGlassActivationIdempotencyKey(
        UuidV7(clock: ref.read(clockProvider)).generate(),
      );
    }

    final outcome = await ref
        .read(breakGlassActionControllerProvider.notifier)
        .activate(ActivateBreakGlassCommand(
          tenantId: tenant.id,
          expectedTenantVersion: tenant.tenantVersion,
          scopes: const {BreakGlassScope.tenantOperationalRead},
          reason: reason,
          idempotencyKey: _attemptKey!,
        ));
    if (!mounted) return;

    // Both land on the management page, which is always the route beneath
    // this one; popping keeps the Operations back stack a `go` would reset.
    final landed = switch (outcome) {
      BreakGlassActionSucceeded() => true,
      BreakGlassActionInvalid(
        code: BreakGlassProblemCode.grantAlreadyActive,
      ) =>
        true,
      _ => false,
    };
    if (landed) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(PlatformOperationsRoutes.access);
      }
      return;
    }
    if (outcome case BreakGlassActionStale()) {
      ref.invalidate(breakGlassEligibleTenantsProvider);
    }
    await showBreakGlassOutcome(context, ref, outcome);
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim();
    final tenants = ref.watch(breakGlassEligibleTenantsProvider(query));
    final action = ref.watch(breakGlassActionControllerProvider);

    return PlatformPage(
      title: S.breakGlassRequestTitle,
      children: [
        Text(
          S.breakGlassLead,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        const _ScopeSummary(),
        const SizedBox(height: AppSpacing.xl),
        Form(
          key: _formKey,
          child: tenants.when(
            loading: () => const Column(
              key: Key('break-glass-tenants-loading'),
              children: [Skeleton(height: 58), SizedBox(height: AppSpacing.lg)],
            ),
            error: (_, __) => const _TenantLoadProblem(),
            data: (result) => result.when(
              success: (items, {stale = false}) => _RequestFields(
                items: items,
                online: !stale,
                stale: stale,
                tenantId: _tenantId,
                search: _search,
                reason: _reason,
                reasonError: _reasonError,
                submitting: action.isSubmitting,
                onSearch: (_) => setState(() => _tenantId = null),
                onTenant: (value) => setState(() => _tenantId = value),
                onSubmit: (tenant) => _submit(tenant, online: !stale),
              ),
              failure: (_, __) => const _TenantLoadProblem(),
              offline: (items) => _RequestFields(
                items: items ?? const [],
                online: false,
                stale: false,
                tenantId: _tenantId,
                search: _search,
                reason: _reason,
                reasonError: _reasonError,
                submitting: action.isSubmitting,
                onSearch: (_) => setState(() => _tenantId = null),
                onTenant: (value) => setState(() => _tenantId = value),
                onSubmit: (tenant) => _submit(tenant, online: false),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScopeSummary extends StatelessWidget {
  const _ScopeSummary();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: context.c.warnTint,
          border: Border.all(color: context.c.warn),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.breakGlassReadOnlyScope),
            SizedBox(height: AppSpacing.sm),
            Text(S.breakGlassServerDuration),
          ],
        ),
      );
}

class _RequestFields extends StatelessWidget {
  const _RequestFields({
    required this.items,
    required this.online,
    required this.stale,
    required this.tenantId,
    required this.search,
    required this.reason,
    required this.reasonError,
    required this.submitting,
    required this.onSearch,
    required this.onTenant,
    required this.onSubmit,
  });

  final List<SaasTenant> items;
  final bool online;
  final bool stale;
  final String? tenantId;
  final TextEditingController search;
  final TextEditingController reason;
  final String? Function(String?) reasonError;
  final bool submitting;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onTenant;
  final ValueChanged<SaasTenant> onSubmit;

  @override
  Widget build(BuildContext context) {
    SaasTenant? selected;
    for (final tenant in items) {
      if (tenant.id == tenantId) selected = tenant;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!online)
          Padding(
            key: Key(stale
                ? 'break-glass-request-stale'
                : 'break-glass-request-offline'),
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
                stale ? S.breakGlassStaleAction : S.breakGlassOfflineAction),
          ),
        TextField(
          key: const Key('break-glass-tenant-search'),
          controller: search,
          onChanged: onSearch,
          decoration: const InputDecoration(
            labelText: S.breakGlassSearchTeam,
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (items.isEmpty)
          const Padding(
            key: Key('break-glass-no-eligible-tenants'),
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Text(S.breakGlassNoEligibleTeams),
          )
        else
          DropdownButtonFormField<String>(
            key: const Key('break-glass-tenant'),
            initialValue: selected?.id,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: S.breakGlassSelectTeam,
              prefixIcon: Icon(Icons.groups_2_outlined),
            ),
            items: [
              for (final tenant in items)
                DropdownMenuItem(
                  value: tenant.id,
                  child: Text(
                    '${tenant.displayName} · ${S.breakGlassTenantActive}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            validator: (value) => value == null ? S.breakGlassSelectTeam : null,
            onChanged: submitting ? null : onTenant,
          ),
        const SizedBox(height: AppSpacing.lg),
        TextFormField(
          key: const Key('break-glass-reason'),
          controller: reason,
          minLines: 3,
          maxLines: 5,
          maxLength: kBreakGlassReasonMaxLength,
          maxLengthEnforcement: MaxLengthEnforcement.none,
          validator: reasonError,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            labelText: S.breakGlassReasonLabel,
            hintText: S.breakGlassReasonHint,
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          key: const Key('break-glass-activate'),
          onPressed:
              selected == null || submitting ? null : () => onSubmit(selected!),
          icon: submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_open_rounded),
          label: const Text(S.breakGlassActivateAction),
        ),
      ],
    );
  }
}

class _TenantLoadProblem extends ConsumerWidget {
  const _TenantLoadProblem();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
        key: const Key('break-glass-tenant-failure'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(S.breakGlassTenantLoadFailure),
          TextButton.icon(
            onPressed: () => ref.invalidate(breakGlassEligibleTenantsProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(S.breakGlassRetry),
          ),
        ],
      );
}
