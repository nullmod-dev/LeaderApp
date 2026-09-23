import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/clock.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../data/platform_break_glass_providers.dart';
import '../domain/platform_audit_models.dart';
import '../domain/platform_break_glass_models.dart';
import '../domain/platform_break_glass_repository.dart';
import 'platform_break_glass_actions.dart';
import 'platform_break_glass_copy.dart';
import 'platform_operations_routes.dart';
import 'widgets/platform_page.dart';

class PlatformBreakGlassPage extends ConsumerWidget {
  const PlatformBreakGlassPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(breakGlassCurrentProvider);
    return PlatformPage(
      title: S.breakGlassTitle,
      onRefresh: () async {
        ref.invalidate(breakGlassCurrentProvider);
        await ref.read(breakGlassCurrentProvider.future);
      },
      children: [
        const _BreakGlassIntro(),
        const SizedBox(height: AppSpacing.lg),
        const _SectionTitle(S.breakGlassCurrentState),
        current.when(
          loading: () => const _LoadingState(),
          error: (_, __) => _UnavailableState(
            key: const Key('break-glass-failure'),
            icon: Icons.cloud_off_outlined,
            title: S.breakGlassFailureTitle,
            body: S.breakGlassLoadRetryBody,
            onRetry: () => ref.invalidate(breakGlassCurrentProvider),
          ),
          data: (result) => _result(context, ref, result),
        ),
      ],
    );
  }

  Widget _result(
    BuildContext context,
    WidgetRef ref,
    Result<BreakGlassSnapshot> result,
  ) {
    return result.when(
      success: (snapshot, {stale = false}) {
        final decision = ref.watch(breakGlassAccessProvider);
        if (snapshot.grant == null) {
          return stale
              ? const _UnavailableState(
                  key: Key('break-glass-stale'),
                  icon: Icons.cloud_sync_outlined,
                  title: S.breakGlassStaleTitle,
                  body: S.breakGlassStaleNoGrantBody,
                )
              : const _NoGrantState();
        }
        return _DecisionState(decision: decision);
      },
      failure: (_, code) {
        final parsed = BreakGlassProblemCode.parse(code);
        if (parsed == BreakGlassProblemCode.notPermitted) {
          return const _UnavailableState(
            key: Key('break-glass-not-permitted'),
            icon: Icons.lock_outline_rounded,
            title: S.breakGlassNotPermittedTitle,
            body: S.breakGlassNotPermittedAction,
          );
        }
        return _UnavailableState(
          key: const Key('break-glass-failure'),
          icon: Icons.cloud_off_outlined,
          title: S.breakGlassFailureTitle,
          body: S.breakGlassLoadRefreshBody,
          onRetry: () => ref.invalidate(breakGlassCurrentProvider),
        );
      },
      offline: (cached) {
        if (cached?.grant != null) {
          return _DecisionState(decision: ref.watch(breakGlassAccessProvider));
        }
        return _UnavailableState(
          key: const Key('break-glass-offline'),
          icon: Icons.cloud_off_outlined,
          title: S.breakGlassOfflineTitle,
          body: S.breakGlassOfflineAction,
          onRetry: () => ref.invalidate(breakGlassCurrentProvider),
        );
      },
    );
  }
}

class _BreakGlassIntro extends StatelessWidget {
  const _BreakGlassIntro();

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.admin_panel_settings_outlined,
            size: 24,
            color: context.c.ink3,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              S.breakGlassLead,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.c.ink3,
                    height: 1.6,
                  ),
            ),
          ),
        ],
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
          child: Text(text, style: Theme.of(context).textTheme.titleSmall),
        ),
      );
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('break-glass-loading'),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Skeleton(height: 96),
            SizedBox(height: AppSpacing.md),
            Skeleton(width: 180),
          ],
        ),
      );
}

class _NoGrantState extends StatelessWidget {
  const _NoGrantState();

  @override
  Widget build(BuildContext context) => Column(
        key: const Key('break-glass-none'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StateCard(
            icon: Icons.lock_clock_outlined,
            title: S.breakGlassNoneTitle,
            body: S.breakGlassNoneBody,
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            key: const Key('break-glass-request'),
            onPressed: () =>
                context.push(PlatformOperationsRoutes.accessRequest),
            icon: const Icon(Icons.lock_open_rounded),
            label: const Text(S.breakGlassRequestAction),
          ),
          const SizedBox(height: AppSpacing.xl),
          const _SectionTitle(S.breakGlassFactsTitle),
          const _FactList(),
          const SizedBox(height: AppSpacing.md),
          TextButton.icon(
            key: const Key('break-glass-audit'),
            onPressed: () => context.push(
              PlatformOperationsRoutes.audit,
              extra: PlatformAuditQuery(
                category: PlatformAuditCategory.emergencyAccess,
              ),
            ),
            icon: const Icon(Icons.history_rounded),
            label: const Text(S.breakGlassAuditAction),
          ),
        ],
      );
}

class _FactList extends StatelessWidget {
  const _FactList();

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
      child: const Column(
        children: [
          _Fact(Icons.visibility_outlined, S.breakGlassFactReadOnly),
          _Fact(Icons.groups_2_outlined, S.breakGlassFactOneTenant),
          _Fact(Icons.schedule_rounded, S.breakGlassFactExpiry),
          _Fact(Icons.tune_rounded, S.breakGlassFactEntitlements),
          _Fact(Icons.verified_user_outlined, S.breakGlassFactAudit),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: context.c.ink3),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _DecisionState extends ConsumerWidget {
  const _DecisionState({required this.decision});
  final BreakGlassAccessDecision decision;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grant = decision.grant!;
    return switch (decision.state) {
      BreakGlassAccessState.usable => _ActiveGrant(
          key: const Key('break-glass-active'),
          decision: decision,
          now: ref.watch(clockProvider)(),
          onEnd: () => confirmAndEndBreakGlass(context, ref, grant),
        ),
      BreakGlassAccessState.unverified => _ActiveGrant(
          key: const Key('break-glass-unverified'),
          decision: decision,
          now: ref.watch(clockProvider)(),
          onEnd: null,
        ),
      BreakGlassAccessState.expired => _TerminalGrant(
          key: const Key('break-glass-expired'),
          icon: Icons.timer_off_outlined,
          title: S.breakGlassExpiredTitle,
          body: S.breakGlassExpiredBody.replaceFirst(
            '%s',
            BreakGlassCopy.timestamp(grant.expiresAt),
          ),
        ),
      BreakGlassAccessState.ended => _TerminalGrant(
          key: const Key('break-glass-ended'),
          icon: grant.endReason == BreakGlassEndReason.revokedByPlatform
              ? Icons.gpp_bad_outlined
              : Icons.lock_outline_rounded,
          title: BreakGlassCopy.endedTitle(grant),
          body: BreakGlassCopy.endedBody(grant),
        ),
      BreakGlassAccessState.tenantUnavailable => const _UnavailableState(
          key: Key('break-glass-tenant-unavailable'),
          icon: Icons.domain_disabled_outlined,
          title: S.breakGlassTenantUnavailableTitle,
          body: S.breakGlassTenantUnavailableBody,
        ),
      BreakGlassAccessState.unsupported => const _UnavailableState(
          key: Key('break-glass-unsupported'),
          icon: Icons.help_outline_rounded,
          title: S.breakGlassUnsupportedTitle,
          body: S.breakGlassUnsupportedBody,
        ),
      BreakGlassAccessState.none => const _NoGrantState(),
    };
  }
}

class _ActiveGrant extends StatelessWidget {
  const _ActiveGrant({
    super.key,
    required this.decision,
    required this.now,
    required this.onEnd,
  });

  final BreakGlassAccessDecision decision;
  final DateTime now;
  final VoidCallback? onEnd;

  @override
  Widget build(BuildContext context) {
    final grant = decision.grant!;
    final verified = decision.state == BreakGlassAccessState.usable;
    return _StateCard(
      icon: verified ? Icons.lock_open_rounded : Icons.cloud_off_outlined,
      title: S.breakGlassActiveTitle,
      body: verified ? S.breakGlassActiveBody : S.breakGlassUnverifiedBody,
      warning: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              const StatusChip(
                kind: StatusKind.warn,
                label: S.breakGlassReadOnlyScope,
              ),
              StatusChip(
                kind: verified ? StatusKind.ok : StatusKind.warn,
                label: verified ? S.breakGlassVerified : S.breakGlassUnverified,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _Detail(S.breakGlassTargetTeam, grant.tenant.displayName),
          _Detail(
            S.breakGlassIssuedAt,
            BreakGlassCopy.timestamp(grant.issuedAt),
          ),
          _Detail(
            S.breakGlassExpiresAt,
            BreakGlassCopy.timestamp(grant.expiresAt),
          ),
          _Detail(
            S.breakGlassRemainingTime,
            BreakGlassCopy.remainingContext(grant.expiresAt, now),
          ),
          _Detail(
            S.breakGlassGrantId,
            BreakGlassCopy.isolateLtr(grant.id),
            ltr: true,
          ),
          _Detail(S.breakGlassReasonLabel, grant.reason),
          if (onEnd != null) ...[
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              key: const Key('break-glass-end'),
              onPressed: onEnd,
              icon: const Icon(Icons.lock_outline_rounded),
              label: const Text(S.breakGlassEndFullAction),
            ),
          ],
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value, {this.ltr = false});
  final String label;
  final String value;
  final bool ltr;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            if (ltr)
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(value),
              )
            else
              Text(value),
          ],
        ),
      );
}

class _TerminalGrant extends StatelessWidget {
  const _TerminalGrant({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StateCard(icon: icon, title: title, body: body),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            key: const Key('break-glass-request-new'),
            onPressed: () =>
                context.push(PlatformOperationsRoutes.accessRequest),
            icon: const Icon(Icons.lock_open_rounded),
            label: const Text(S.breakGlassRequestAction),
          ),
        ],
      );
}

class _UnavailableState extends StatelessWidget {
  const _UnavailableState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.onRetry,
  });
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => _StateCard(
        icon: icon,
        title: title,
        body: body,
        child: onRetry == null
            ? null
            : Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text(S.breakGlassRetry),
                ),
              ),
      );
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.body,
    this.warning = false,
    this.child,
  });
  final IconData icon;
  final String title;
  final String body;
  final bool warning;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: warning ? c.warnTint : c.surface,
        border: Border.all(color: warning ? c.warn : c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            label: '$title. $body',
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: warning ? c.warn : c.ink3),
                  const SizedBox(height: AppSpacing.md),
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(body, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ),
          if (child != null) ...[
            const SizedBox(height: AppSpacing.lg),
            child!,
          ],
        ],
      ),
    );
  }
}
