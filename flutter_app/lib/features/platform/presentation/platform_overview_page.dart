import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion/animated_counter.dart';
import '../../../core/problem/problem.dart';
import '../../../core/problem/problem_presentation.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/time/clock.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/forward_chevron.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../data/platform_overview_providers.dart';
import '../domain/platform_area.dart';
import '../domain/platform_overview_models.dart';
import 'platform_destinations.dart';
import 'platform_operations_routes.dart';
import 'saas_tenant_copy.dart';
import 'saas_tenant_routes.dart';
import 'tenant_lifecycle_copy.dart';
import 'widgets/platform_meta.dart';
import 'widgets/platform_page.dart';

/// `/platform` — a decision-first SaaS control-plane overview.
///
/// This branch reads [platformOverviewProvider] only. It does not compose
/// tenant operational repositories, and each interactive item maps a typed
/// target to one of the Point 4 section landings that actually exists.
class PlatformOverviewPage extends ConsumerWidget {
  const PlatformOverviewPage({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(platformOverviewProvider);
    await ref.read(platformOverviewProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destination = destinationFor(PlatformArea.overview);
    final async = ref.watch(platformOverviewProvider);

    return PlatformPage(
      title: destination.label,
      // No app-bar refresh icon. The page had two affordances for one action
      // and the further of the two sat above the sentence that makes an
      // operator want it; the control now lives on the status strip, beside
      // «آخر تحديث قبل ٦ د» (UI audit P3). Pull-to-refresh is unchanged.
      onRefresh: () => _refresh(ref),
      children: [
        const PlatformPageIntro(lead: S.platformOverviewLead),
        const SizedBox(height: AppSpacing.lg),
        ..._content(ref, async),
      ],
    );
  }

  List<Widget> _content(
    WidgetRef ref,
    AsyncValue<Result<PlatformOverviewSnapshot>> async,
  ) {
    if (async.isLoading && !async.hasValue) {
      return const [_PlatformOverviewSkeleton()];
    }
    if (async.hasError || !async.hasValue) {
      return [
        ErrorStateView(onRetry: () => ref.invalidate(platformOverviewProvider)),
      ];
    }

    final result = async.requireValue;
    return result.when(
      success: (snapshot, {stale = false}) => [
        _OverviewBody(
          snapshot: snapshot,
          freshness:
              stale ? _OverviewFreshness.stale : _OverviewFreshness.fresh,
        ),
      ],
      failure: (message, code) {
        final view = resolveProblem(Problem.of(
          ProblemCode.parse(code),
          rawCode: code,
          detail: message,
        ));
        return [
          ErrorStateView(
            key: const Key('platform-overview-failure'),
            title: view.title,
            body: view.message,
            onRetry: () => ref.invalidate(platformOverviewProvider),
          ),
        ];
      },
      offline: (cached) => cached == null
          ? [
              EmptyState(
                key: const Key('platform-overview-offline-empty'),
                icon: Icons.cloud_off_rounded,
                title: S.offlineTitle,
                body: S.noCachedCopy,
                actionLabel: S.retry,
                onAction: () => ref.invalidate(platformOverviewProvider),
              ),
            ]
          : [
              _OverviewBody(
                snapshot: cached,
                freshness: _OverviewFreshness.offline,
              ),
            ],
    );
  }
}

enum _OverviewFreshness { fresh, stale, offline }

class _OverviewBody extends ConsumerWidget {
  const _OverviewBody({required this.snapshot, required this.freshness});

  final PlatformOverviewSnapshot snapshot;
  final _OverviewFreshness freshness;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    void refresh() => ref.invalidate(platformOverviewProvider);
    if (snapshot.isMinimal) {
      return Column(
        key: const Key('platform-overview-minimal'),
        children: [
          _StatusStrip(
            snapshot: snapshot,
            freshness: freshness,
            now: now,
            onRefresh: refresh,
          ),
          const SizedBox(height: AppSpacing.xxl),
          const EmptyState(
            icon: Icons.space_dashboard_outlined,
            title: S.platformOverviewMinimalTitle,
            body: S.platformOverviewMinimalBody,
          ),
        ],
      );
    }

    return Column(
      key: const Key('platform-overview-loaded'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusStrip(
          snapshot: snapshot,
          freshness: freshness,
          now: now,
          onRefresh: refresh,
        ),
        if (snapshot.attention.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxl),
          const SectionHeader(
            style: SectionHeaderStyle.heading,
            icon: Icons.priority_high_rounded,
            title: S.platformOverviewAttention,
          ),
          const SizedBox(height: AppSpacing.md),
          _AttentionList(items: snapshot.attention),
        ],
        const SizedBox(height: AppSpacing.xxl),
        const SectionHeader(
          style: SectionHeaderStyle.heading,
          icon: Icons.grid_view_rounded,
          title: S.platformOverviewSummary,
        ),
        const SizedBox(height: AppSpacing.md),
        _Metrics(snapshot: snapshot),
        const SizedBox(height: AppSpacing.xxl),
        _ResponsiveDetails(snapshot: snapshot, now: now),
      ],
    );
  }
}

/// The first thing on the page: is the platform healthy, how old is this
/// reading, and one control to take a newer one.
///
/// It replaced a 52 dp tile, a heading that repeated the app bar and a lead
/// paragraph — about 270 px before any data, which put «يحتاج إلى انتباه» at
/// the fold on a 390 × 844 phone (UI audit P1-6). The strip is the *answer*
/// the hero was decoration for.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.snapshot,
    required this.freshness,
    required this.now,
    required this.onRefresh,
  });

  final PlatformOverviewSnapshot snapshot;
  final _OverviewFreshness freshness;
  final DateTime now;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final offline = freshness == _OverviewFreshness.offline;
    final quiet = snapshot.attention.isEmpty && !snapshot.isMinimal;
    return Container(
      key: const Key('platform-overview-freshness'),
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: offline ? c.warnTint : c.surface,
        border: Border.all(color: offline ? c.warn : c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap, not Row: at a 1.6 text scale the refresh action drops under
          // the chips instead of pushing the health word off the edge.
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _HealthChip(status: snapshot.overallHealth),
              if (freshness == _OverviewFreshness.stale) const StaleBadge(),
              // The visible label is one word; the tooltip is the accessible
              // name and says which reading it refreshes.
              Tooltip(
                message: S.platformOverviewRefresh,
                child: TextButton.icon(
                  // Same key the app-bar icon carried, because this is the
                  // same action in a better place.
                  key: const Key('platform-overview-refresh'),
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
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
            child: PlatformMeta(
              parts: [
                PlatformMetaText(
                  offline
                      ? S.platformOverviewOfflineCached
                      : _updatedLabel(now, snapshot.generatedAt),
                ),
                // Said here rather than as an empty attention card: §7B keeps
                // the attention block for the case where there *is* something,
                // and the operator still deserves the negative answer.
                if (quiet)
                  const PlatformMetaText(S.platformOverviewAttentionClearTitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttentionList extends StatelessWidget {
  const _AttentionList({required this.items});

  final List<PlatformAttentionItem> items;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      key: const Key('platform-overview-attention'),
      color: c.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            _AttentionRow(item: items[index]),
            if (index != items.length - 1) Divider(color: c.line),
          ],
        ],
      ),
    );
  }
}

class _AttentionRow extends ConsumerWidget {
  const _AttentionRow({required this.item});

  final PlatformAttentionItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final (color, tint, icon) = switch (item.severity) {
      AttentionSeverity.info => (
          c.info,
          c.infoTint,
          Icons.info_outline_rounded
        ),
      AttentionSeverity.warning => (
          c.warn,
          c.warnTint,
          Icons.warning_amber_rounded
        ),
      AttentionSeverity.critical => (
          c.crit,
          c.critTint,
          Icons.gpp_maybe_outlined
        ),
    };

    final deadlineContext = item.scheduledFor == null
        ? null
        : tenantDeletionRemainingLabel(
            ref.watch(clockProvider)(),
            item.scheduledFor!,
          );
    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  item.description,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: c.ink3, height: 1.5),
                ),
                // The deadline is a reading, not a clause of the sentence
                // above it. Glued on with ` · ` it sat between a description
                // and a number and the separator read as an Arabic-Indic zero
                // (UI audit P1-11); on its own line it carries the severity
                // colour and can be scanned.
                if (deadlineContext != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    deadlineContext,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (item.target != null) ...[
            const SizedBox(width: AppSpacing.sm),
            const ForwardChevron(size: 20),
          ],
        ],
      ),
    );

    if (item.target == null) return content;
    return Semantics(
      button: true,
      label: '${item.title}، ${S.platformOverviewOpenSection}',
      child: InkWell(
        key: Key('platform-attention-${item.id}'),
        onTap: () => context.go(
          item.tenantId == null
              ? _routeFor(item.target!)
              : SaasTenantRoutes.detail(item.tenantId!),
        ),
        child: content,
      ),
    );
  }
}

/// The five figures, in three weights.
///
/// **What changed and why.** The page used to draw five identical tiles, each
/// with its number in `c.primary` — including «سماح أو إيقاف», a count of
/// customers in trouble, painted the same brand green as «الفرق المشتركة»
/// (UI audit P1-6). Equal weight on a control plane is a refusal to say what
/// matters.
///
/// Now: the two figures an operator can *act on* lead and carry severity, and
/// the three that describe the size of the business are one quiet card of
/// label↔value rows underneath. Every figure the page had is still here —
/// none was dropped to make the hierarchy, and none was invented to fill it.
class _Metrics extends StatelessWidget {
  const _Metrics({required this.snapshot});

  final PlatformOverviewSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final tenants = snapshot.tenants;
    final demos = snapshot.demos;

    // Severity from the *kind* of trouble, not from the total: a suspended or
    // deletion-pending team is a different conversation from one in its grace
    // window, and «٢» says neither on its own.
    final critical = tenants.suspended + tenants.deletionPending;
    final riskTone = critical > 0
        ? _MetricTone.critical
        : tenants.gracePeriod > 0
            ? _MetricTone.warning
            : _MetricTone.calm;

    final risk = _SignalTile(
      id: 'tenant-attention',
      icon: Icons.report_problem_outlined,
      label: S.platformOverviewRisk,
      value: tenants.requiringAttention,
      tone: riskTone,
      target: PlatformOverviewTarget.tenants,
      detail: tenants.requiringAttention == 0
          ? const [PlatformMetaText(S.platformOverviewRiskClear)]
          : [
              PlatformMetaText(
                '${_digits(tenants.gracePeriod)} ${S.platformOverviewGrace}',
              ),
              PlatformMetaText(
                '${_digits(tenants.suspended)} ${S.platformOverviewSuspended}',
              ),
              PlatformMetaText(
                '${_digits(tenants.deletionPending)} '
                '${S.platformOverviewDeletionPending}',
              ),
            ],
    );

    final trials = _SignalTile(
      id: 'demos',
      icon: Icons.science_outlined,
      label: S.platformOverviewDemos,
      value: demos.active,
      tone: demos.expiringSoon > 0 ? _MetricTone.notice : _MetricTone.calm,
      target: PlatformOverviewTarget.operations,
      detail: [
        PlatformMetaText(
          '${_digits(demos.simple)} ${S.platformOverviewSimpleDemo}',
        ),
        PlatformMetaText(
          '${_digits(demos.full)} ${S.platformOverviewFullDemo}',
        ),
        PlatformMetaText(
          '${_digits(demos.expiringSoon)} ${S.platformOverviewDemoExpiring}',
          emphasis: demos.expiringSoon > 0,
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          // Side by side once each tile still has room for its own breakdown
          // line; stacked below that, because a three-part meta line squeezed
          // into 160 dp wraps to three rows and stops being a line.
          if (constraints.maxWidth < 520) {
            return Column(
              children: [
                risk,
                const SizedBox(height: AppSpacing.sm),
                trials,
              ],
            );
          }
          // `IntrinsicHeight`, because `CrossAxisAlignment.stretch` inside a
          // `ListView` child asks for an infinite height. Two small cards is
          // exactly the size at which the extra pass is worth having them
          // agree on a height.
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: risk),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: trials),
              ],
            ),
          );
        }),
        const SizedBox(height: AppSpacing.sm),
        _ScaleCard(tenants: tenants),
      ],
    );
  }
}

/// How loudly a figure is allowed to speak.
enum _MetricTone { calm, notice, warning, critical }

/// One figure that can require an action, with its breakdown.
class _SignalTile extends StatelessWidget {
  const _SignalTile({
    required this.id,
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
    required this.target,
    required this.detail,
  });

  final String id;
  final IconData icon;
  final String label;
  final int value;
  final _MetricTone tone;
  final PlatformOverviewTarget target;
  final List<Widget> detail;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // The calm case is deliberately the quietest thing on the page: a zero
    // drawn in brand green is a number asking to be read for no reason.
    final (fg, tint, border) = switch (tone) {
      _MetricTone.calm => (c.ink2, c.surface2, c.line),
      _MetricTone.notice => (c.info, c.infoTint, c.line),
      _MetricTone.warning => (c.warn, c.warnTint, c.warn),
      _MetricTone.critical => (c.crit, c.critTint, c.crit),
    };
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: border),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('platform-metric-$id'),
        onTap: () => context.go(_routeFor(target)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tint,
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                      child: Icon(icon, size: 18, color: fg),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    _digits(value),
                    style: AppTypography.digits(fg, size: 24)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const ForwardChevron(size: 20),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              PlatformMeta(parts: detail),
            ],
          ),
        ),
      ),
    );
  }
}

/// How big the platform is — three facts that change slowly and need no
/// decision, as label↔value rows rather than three more cards.
class _ScaleCard extends StatelessWidget {
  const _ScaleCard({required this.tenants});

  final PlatformTenantSummary tenants;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rows = <(String, String, int)>[
      ('tenants', S.platformOverviewTenants, tenants.total),
      (
        'subscriptions',
        S.platformOverviewSubscriptions,
        tenants.activeSubscriptions
      ),
      ('trials', S.platformOverviewTrials, tenants.activeTrials),
    ];
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            _ScaleRow(
              id: rows[index].$1,
              label: rows[index].$2,
              value: rows[index].$3,
            ),
            if (index != rows.length - 1) Divider(height: 1, color: c.line),
          ],
        ],
      ),
    );
  }
}

class _ScaleRow extends StatelessWidget {
  const _ScaleRow({
    required this.id,
    required this.label,
    required this.value,
  });

  final String id;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      key: Key('platform-metric-$id'),
      onTap: () => context.go(_routeFor(PlatformOverviewTarget.tenants)),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              _digits(value),
              style: AppTypography.digits(c.ink, size: 17),
            ),
            const SizedBox(width: AppSpacing.sm),
            const ForwardChevron(size: 20),
          ],
        ),
      ),
    );
  }
}

class _ResponsiveDetails extends StatelessWidget {
  const _ResponsiveDetails({required this.snapshot, required this.now});

  final PlatformOverviewSnapshot snapshot;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final primary = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HealthSection(signals: snapshot.health),
          if (snapshot.usage case final usage?) ...[
            const SizedBox(height: AppSpacing.xxl),
            _UsageSection(usage: usage),
          ],
        ],
      );
      final activity = _ActivitySection(
        events: snapshot.recentActivity,
        now: now,
      );
      if (constraints.maxWidth < 620) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            primary,
            const SizedBox(height: AppSpacing.xxl),
            activity,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: primary),
          const SizedBox(width: AppSpacing.lg),
          Expanded(child: activity),
        ],
      );
    });
  }
}

class _HealthSection extends StatelessWidget {
  const _HealthSection({required this.signals});

  final List<PlatformHealthSignal> signals;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          style: SectionHeaderStyle.heading,
          icon: Icons.monitor_heart_outlined,
          title: S.platformOverviewHealth,
        ),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          button: true,
          label:
              '${S.platformOverviewHealth}، ${S.platformOperationsOpenModule}',
          child: Material(
            key: const Key('platform-overview-health'),
            color: c.surface,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: c.line),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const Key('platform-overview-health-open'),
              onTap: () => context.go(PlatformOperationsRoutes.health),
              child: Column(
                children: [
                  for (var index = 0; index < signals.length; index++) ...[
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  signals[index].label,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  signals[index].summary,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: c.ink3),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          _HealthChip(status: signals[index].status),
                        ],
                      ),
                    ),
                    if (index != signals.length - 1) Divider(color: c.line),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({required this.events, required this.now});

  final List<PlatformActivityEvent> events;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          style: SectionHeaderStyle.heading,
          icon: Icons.history_rounded,
          title: S.platformOverviewActivity,
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          key: const Key('platform-overview-activity'),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: events.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text(S.platformOverviewNoActivity),
                )
              : Column(
                  children: [
                    for (var index = 0; index < events.length; index++) ...[
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ActivityIcon(type: events[index].type),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    events[index].title,
                                    style:
                                        Theme.of(context).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    events[index].description,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: c.ink3, height: 1.4),
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    _ago(now, events[index].occurredAt),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: c.ink3, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (index != events.length - 1) Divider(color: c.line),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _ActivityIcon extends StatelessWidget {
  const _ActivityIcon({required this.type});

  final PlatformActivityType type;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final icon = switch (type) {
      PlatformActivityType.tenantCreated => Icons.domain_add_outlined,
      PlatformActivityType.subscriptionChanged => Icons.sync_alt_rounded,
      PlatformActivityType.demoStarted => Icons.play_circle_outline_rounded,
      PlatformActivityType.demoExpired => Icons.timer_off_outlined,
      PlatformActivityType.securityAlert => Icons.security_outlined,
      PlatformActivityType.platformHealthChanged =>
        Icons.monitor_heart_outlined,
    };
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Icon(icon, size: 18, color: c.ink2),
    );
  }
}

class _UsageSection extends StatelessWidget {
  const _UsageSection({required this.usage});

  final PlatformUsageSummary usage;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // `tenantBytesLabel`, not `~/ 1 GiB`: integer division rendered anything
    // under a gigabyte as «٠ غ.ب من ٢٠ غ.ب» (UI audit P3). The shared helper
    // falls back to megabytes.
    final used = tenantBytesLabel(usage.storageUsedBytes);
    final allowance = tenantBytesLabel(usage.storageAllowanceBytes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          style: SectionHeaderStyle.heading,
          icon: Icons.storage_outlined,
          title: S.platformOverviewUsage,
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          key: const Key('platform-overview-usage'),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                S.platformOverviewStorage,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '$used${S.platformOverviewStorageOf}$allowance',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: c.ink3),
              ),
              const SizedBox(height: AppSpacing.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.pill),
                child: LinearProgressIndicator(
                  value: usage.storageRatio,
                  minHeight: 7,
                  color: c.primary,
                  backgroundColor: c.surface3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HealthChip extends StatelessWidget {
  const _HealthChip({required this.status});

  final PlatformHealthStatus status;

  @override
  Widget build(BuildContext context) {
    final (kind, label) = switch (status) {
      PlatformHealthStatus.healthy => (
          StatusKind.ok,
          S.platformOverviewHealthHealthy
        ),
      PlatformHealthStatus.degraded => (
          StatusKind.warn,
          S.platformOverviewHealthDegraded
        ),
      PlatformHealthStatus.unavailable => (
          StatusKind.crit,
          S.platformOverviewHealthUnavailable
        ),
      PlatformHealthStatus.unknown => (
          StatusKind.muted,
          S.platformOverviewHealthUnknown
        ),
    };
    return StatusChip(kind: kind, label: label);
  }
}

class _PlatformOverviewSkeleton extends StatelessWidget {
  const _PlatformOverviewSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      key: const Key('platform-overview-loading'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Skeleton(width: 180, height: 38),
        const SizedBox(height: AppSpacing.xxl),
        const Skeleton(width: 140, height: 20),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: const Column(
            children: [
              SkeletonRow(),
              SizedBox(height: AppSpacing.sm),
              SkeletonRow(),
              SizedBox(height: AppSpacing.sm),
              SkeletonRow(),
            ],
          ),
        ),
      ],
    );
  }
}

String _routeFor(PlatformOverviewTarget target) => switch (target) {
      PlatformOverviewTarget.tenants => PlatformArea.tenants.route,
      PlatformOverviewTarget.operations => PlatformArea.operations.route,
      PlatformOverviewTarget.health => PlatformOperationsRoutes.health,
      PlatformOverviewTarget.security => PlatformOperationsRoutes.security,
    };

String _digits(int value) => toArabicIndic(value.toString());

String _updatedLabel(DateTime now, DateTime generatedAt) {
  final delta = now.toUtc().difference(generatedAt.toUtc());
  if (delta.isNegative || delta.inMinutes < 1) {
    return S.platformOverviewUpdatedNow;
  }
  if (delta.inHours < 1) {
    return '${S.platformOverviewUpdatedPrefix}${_digits(delta.inMinutes)}'
        '${S.platformOverviewMinute}';
  }
  if (delta.inDays < 1) {
    return '${S.platformOverviewUpdatedPrefix}${_digits(delta.inHours)}'
        '${S.platformOverviewHour}';
  }
  return '${S.platformOverviewUpdatedPrefix}${_digits(delta.inDays)}'
      '${S.platformOverviewDay}';
}

String _ago(DateTime now, DateTime occurredAt) {
  final delta = now.toUtc().difference(occurredAt.toUtc());
  if (delta.isNegative || delta.inMinutes < 1) return S.now;
  if (delta.inHours < 1) {
    return '${S.platformOverviewAgoPrefix}${_digits(delta.inMinutes)}'
        '${S.platformOverviewMinutesWord}';
  }
  if (delta.inDays < 1) {
    return '${S.platformOverviewAgoPrefix}${_digits(delta.inHours)}'
        '${S.platformOverviewHoursWord}';
  }
  return '${S.platformOverviewAgoPrefix}${_digits(delta.inDays)}'
      '${S.platformOverviewDaysWord}';
}
