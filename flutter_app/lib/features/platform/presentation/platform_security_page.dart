import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/forward_chevron.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../data/platform_operations_providers.dart';
import '../data/saas_tenant_providers.dart';
import '../domain/platform_security_models.dart';
import 'saas_tenant_routes.dart';
import 'widgets/platform_meta.dart';
import 'widgets/platform_page.dart';

/// Read-only awareness of the latest available Platform Security snapshot.
///
/// Alerts may link to a validated platform tenant resource. They never open a
/// tenant operational shell and expose no acknowledgement, incident, audit,
/// or emergency-access controls.
class PlatformSecurityPage extends ConsumerWidget {
  const PlatformSecurityPage({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(platformSecurityProvider);
    await ref.read(platformSecurityProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(platformSecurityProvider);
    return PlatformPage(
      title: S.platformSecurityTitle,
      // One refresh affordance, on the snapshot card beside the age it
      // refreshes (UI audit P3).
      onRefresh: () => _refresh(ref),
      children: [
        const PlatformPageIntro(lead: S.platformSecurityLead),
        const SizedBox(height: AppSpacing.lg),
        ..._content(ref, async),
      ],
    );
  }

  List<Widget> _content(
    WidgetRef ref,
    AsyncValue<Result<PlatformSecuritySnapshot>> async,
  ) {
    if (async.isLoading && !async.hasValue) {
      return const [_SecurityLoading()];
    }
    if (async.hasError || !async.hasValue) {
      return [_failure(ref)];
    }

    return async.requireValue.when(
      success: (snapshot, {stale = false}) => [
        _SecurityBody(
          snapshot: snapshot,
          freshness:
              stale ? _SecurityFreshness.stale : _SecurityFreshness.fresh,
          onRefresh: () => ref.invalidate(platformSecurityProvider),
        ),
      ],
      failure: (_, __) => [_failure(ref)],
      offline: (cached) => cached == null
          ? [
              EmptyState(
                key: const Key('platform-security-offline-empty'),
                icon: Icons.cloud_off_rounded,
                title: S.platformSecurityOfflineTitle,
                body: S.platformSecurityOfflineBody,
                actionLabel: S.retry,
                onAction: () => ref.invalidate(platformSecurityProvider),
              ),
            ]
          : [
              _SecurityBody(
                snapshot: cached,
                freshness: _SecurityFreshness.offline,
                onRefresh: () => ref.invalidate(platformSecurityProvider),
              ),
            ],
    );
  }

  Widget _failure(WidgetRef ref) => ErrorStateView(
        key: const Key('platform-security-failure'),
        title: S.platformSecurityFailureTitle,
        body: S.platformSecurityFailureBody,
        onRetry: () => ref.invalidate(platformSecurityProvider),
      );
}

enum _SecurityFreshness { fresh, stale, offline }

class _SecurityBody extends StatelessWidget {
  const _SecurityBody({
    required this.snapshot,
    required this.freshness,
    required this.onRefresh,
  });

  final PlatformSecuritySnapshot snapshot;
  final _SecurityFreshness freshness;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('platform-security-loaded'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SnapshotCard(
          snapshot: snapshot,
          freshness: freshness,
          onRefresh: onRefresh,
        ),
        const SizedBox(height: AppSpacing.xxl),
        const SectionHeader(
          style: SectionHeaderStyle.heading,
          icon: Icons.notification_important_outlined,
          title: S.platformSecurityAlerts,
        ),
        const SizedBox(height: AppSpacing.md),
        if (snapshot.alerts.isEmpty)
          const EmptyState(
            key: Key('platform-security-no-alerts'),
            icon: Icons.shield_outlined,
            title: S.platformSecurityNoAlertsTitle,
            body: S.platformSecurityNoAlertsBody,
          )
        else
          _AlertList(alerts: snapshot.alerts),
      ],
    );
  }
}

/// The current security state, how old the reading is, and one control to
/// take a newer one.
///
/// The timestamp is the snapshot's **UTC** instant — unchanged, because two
/// operators comparing an incident need the same number — but written in the
/// product's own date shape and with the timezone named in Arabic instead of
/// «٢٠٢٦/٠٩/٠٨ · ١٥:٠٤ UTC», where the separator rendered as the Arabic-Indic
/// zero beside it (UI audit P2, P1-11).
class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard({
    required this.snapshot,
    required this.freshness,
    required this.onRefresh,
  });

  final PlatformSecuritySnapshot snapshot;
  final _SecurityFreshness freshness;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final summary = _summaryPresentation(snapshot.summaryState);
    final offline = freshness == _SecurityFreshness.offline;
    final freshnessLabel = switch (freshness) {
      _SecurityFreshness.fresh => S.platformSecuritySnapshot,
      _SecurityFreshness.stale => S.staleData,
      _SecurityFreshness.offline => S.platformSecurityOfflineCached,
    };

    return Semantics(
      key: const Key('platform-security-summary'),
      container: true,
      label: '${S.platformSecurityCurrentState}، ${summary.label}، '
          '${summary.description}، $freshnessLabel، '
          '${S.platformSecuritySnapshot} '
          '${PlatformTime.utcSpoken(snapshot.generatedAt)}',
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: offline ? c.warnTint : c.surface,
            border: Border.all(color: offline ? c.warn : c.line),
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      S.platformSecurityCurrentState,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  // The visible label is one word; the tooltip is the
                  // accessible name and says which reading it refreshes.
                  Tooltip(
                    message: S.platformSecurityRefresh,
                    child: TextButton.icon(
                      key: const Key('platform-security-refresh'),
                      onPressed: onRefresh,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        minimumSize: const Size(0, 36),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text(S.platformOverviewRefreshNow),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusChip(kind: summary.kind, label: summary.label),
                  if (freshness == _SecurityFreshness.stale) const StaleBadge(),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                summary.description,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: c.ink2, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.sm),
              PlatformMeta(parts: [
                if (offline)
                  const PlatformMetaText(S.platformSecurityOfflineCached),
                PlatformMetaText(
                  '${S.platformSecuritySnapshot} '
                  '${PlatformTime.utcDate(snapshot.generatedAt)}',
                ),
                PlatformMetaText(PlatformTime.utcTime(snapshot.generatedAt)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertList extends StatelessWidget {
  const _AlertList({required this.alerts});

  final List<PlatformSecurityAlert> alerts;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      key: const Key('platform-security-alerts'),
      color: c.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < alerts.length; index++) ...[
            _AlertRow(alert: alerts[index]),
            if (index != alerts.length - 1) Divider(color: c.line),
          ],
        ],
      ),
    );
  }
}

/// One alert.
///
/// **Five things, in three weights** (§30). The severity plate and the title
/// are the first line; the severity word, the category and the detection time
/// are one metadata line under it; the description is the body; the affected
/// tenant, when there is one, is a compact context strip.
///
/// The page used to stack a severity chip and a category chip — two different
/// chip shapes on one row, which at 320 dp fell onto two lines — above the
/// title, then the description, then «وقت الرصد · ٢٠٢٦/٠٩/٠٨ ١٥:٠٤ UTC», then
/// the tenant block: six stacked elements, none of them ranked.
///
/// Severity is never colour alone: it is a labelled chip, a glyph and a word,
/// so a monochrome rendering and a colour-vision difference both survive it.
class _AlertRow extends ConsumerWidget {
  const _AlertRow({required this.alert});

  final PlatformSecurityAlert alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final severity = _severityPresentation(alert.severity);
    final category = _categoryLabel(alert.category);
    final tenant = alert.affectedTenant;
    final tenantStore = ref.watch(platformTenantStoreProvider);
    final hasValidTenantTarget = tenant != null &&
        (tenantStore.byId(tenant.id) != null ||
            tenantStore.tombstoneById(tenant.id) != null);
    final tenantSemantics = tenant == null
        ? ''
        : '، ${S.platformSecurityAffectedTenant} ${tenant.displayName}، '
            '${tenant.id}'
            '${tenant.isDeleted ? '، ${S.platformSecurityDeletedTenant}' : ''}';
    final semanticsLabel = '${severity.label}، $category، ${alert.title}، '
        '${alert.description}، ${S.platformSecurityDetected} '
        '${PlatformTime.utcSpoken(alert.detectedAt)}'
        '$tenantSemantics'
        '${hasValidTenantTarget ? '، ${S.platformSecurityOpenTenant}' : ''}';

    final content = ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: severity.tint(c),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Icon(severity.icon, size: 20, color: severity.color(c)),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // One chip, not two. The severity keeps its chip because it
                  // is the ranking; the category is a plain word on the
                  // metadata line, which is what it is.
                  //
                  // The chip is stacked above that line rather than sharing a
                  // `Wrap` with it: at 320 dp and a 1.6 text scale the wrap
                  // slotted the chip into the middle of the metadata, between
                  // the date and the clock, which blurs the one thing on the
                  // row that ranks it.
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child:
                        StatusChip(kind: severity.kind, label: severity.label),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  PlatformMeta(parts: [
                    PlatformMetaText(category),
                    PlatformMetaText(PlatformTime.utcDate(alert.detectedAt)),
                    PlatformMetaText(PlatformTime.utcTime(alert.detectedAt)),
                  ]),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    alert.description,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: c.ink2, height: 1.55),
                  ),
                  if (tenant != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _TenantContext(tenant: tenant),
                  ],
                ],
              ),
            ),
            if (hasValidTenantTarget) ...[
              const SizedBox(width: AppSpacing.xs),
              const ForwardChevron(size: 20),
            ],
          ],
        ),
      ),
    );

    if (!hasValidTenantTarget) {
      return Semantics(
        key: Key('platform-security-alert-${alert.id}'),
        container: true,
        label: semanticsLabel,
        child: content,
      );
    }
    return Semantics(
      key: Key('platform-security-alert-${alert.id}'),
      button: true,
      label: semanticsLabel,
      child: InkWell(
        key: Key('platform-security-tenant-${alert.id}'),
        onTap: () => context.go(SaasTenantRoutes.detail(tenant.id)),
        child: content,
      ),
    );
  }
}

/// Which customer the alert is about.
///
/// The identifier stays and stays labelled: routing to a team by id is real
/// Super Admin work (§24), and an unlabelled `saas_…` under a team name reads
/// as something that leaked. It is one metadata line under the name rather
/// than a stacked label/value pair inside a stacked block.
class _TenantContext extends StatelessWidget {
  const _TenantContext({required this.tenant});

  final PlatformSecurityTenantReference tenant;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            tenant.isDeleted
                ? Icons.folder_off_outlined
                : Icons.apartment_rounded,
            size: 18,
            color: c.ink3,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      tenant.displayName,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (tenant.isDeleted)
                      const StatusChip(
                        kind: StatusKind.muted,
                        label: S.platformSecurityDeletedTenant,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                PlatformMeta(parts: [
                  const PlatformMetaText(S.platformSecurityAffectedTenant),
                  PlatformMetaText(
                    '${S.platformSecurityTenantId}: ${tenant.id}',
                    ltr: false,
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityLoading extends StatelessWidget {
  const _SecurityLoading();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      key: const Key('platform-security-loading'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skeleton(width: 150, height: 18),
              SizedBox(height: AppSpacing.md),
              Skeleton(width: 100, height: 24, radius: 12),
              SizedBox(height: AppSpacing.md),
              Skeleton(width: 220, height: 14),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        const Skeleton(width: 140, height: 20),
        const SizedBox(height: AppSpacing.md),
        const SkeletonRow(),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonRow(),
      ],
    );
  }
}

class _SummaryPresentation {
  const _SummaryPresentation(this.kind, this.label, this.description);

  final StatusKind kind;
  final String label;
  final String description;
}

_SummaryPresentation _summaryPresentation(PlatformSecuritySummaryState state) =>
    switch (state) {
      PlatformSecuritySummaryState.noAlerts => const _SummaryPresentation(
          StatusKind.ok,
          S.platformSecurityNoAlertsTitle,
          S.platformSecurityNoAlertsBody,
        ),
      PlatformSecuritySummaryState.informational => const _SummaryPresentation(
          StatusKind.info,
          S.platformSecuritySeverityInfo,
          S.platformSecuritySummaryInfo,
        ),
      PlatformSecuritySummaryState.warning => const _SummaryPresentation(
          StatusKind.warn,
          S.platformSecuritySeverityWarning,
          S.platformSecuritySummaryWarning,
        ),
      PlatformSecuritySummaryState.critical => const _SummaryPresentation(
          StatusKind.crit,
          S.platformSecuritySeverityCritical,
          S.platformSecuritySummaryCritical,
        ),
      PlatformSecuritySummaryState.unknown => const _SummaryPresentation(
          StatusKind.warn,
          S.platformSecuritySeverityUnknown,
          S.platformSecuritySummaryUnknown,
        ),
    };

class _SeverityPresentation {
  const _SeverityPresentation({
    required this.kind,
    required this.label,
    required this.icon,
    required this.color,
    required this.tint,
  });

  final StatusKind kind;
  final String label;
  final IconData icon;
  final Color Function(AppColors colors) color;
  final Color Function(AppColors colors) tint;
}

_SeverityPresentation _severityPresentation(
  PlatformSecurityAlertSeverity severity,
) =>
    switch (severity) {
      PlatformSecurityAlertSeverity.info => _SeverityPresentation(
          kind: StatusKind.info,
          label: S.platformSecuritySeverityInfo,
          icon: Icons.info_outline_rounded,
          color: (colors) => colors.info,
          tint: (colors) => colors.infoTint,
        ),
      PlatformSecurityAlertSeverity.warning => _SeverityPresentation(
          kind: StatusKind.warn,
          label: S.platformSecuritySeverityWarning,
          icon: Icons.warning_amber_rounded,
          color: (colors) => colors.warn,
          tint: (colors) => colors.warnTint,
        ),
      PlatformSecurityAlertSeverity.critical => _SeverityPresentation(
          kind: StatusKind.crit,
          label: S.platformSecuritySeverityCritical,
          icon: Icons.gpp_maybe_outlined,
          color: (colors) => colors.crit,
          tint: (colors) => colors.critTint,
        ),
      PlatformSecurityAlertSeverity.unknown => _SeverityPresentation(
          kind: StatusKind.warn,
          label: S.platformSecuritySeverityUnknown,
          icon: Icons.help_outline_rounded,
          color: (colors) => colors.warn,
          tint: (colors) => colors.warnTint,
        ),
    };

String _categoryLabel(PlatformSecurityAlertCategory category) =>
    switch (category) {
      PlatformSecurityAlertCategory.authentication =>
        S.platformSecurityCategoryAuthentication,
      PlatformSecurityAlertCategory.unknown =>
        S.platformSecurityCategoryUnknown,
    };
