import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../data/platform_operations_providers.dart';
import '../domain/platform_health_models.dart';
import 'widgets/platform_meta.dart';
import 'widgets/platform_page.dart';

/// The latest available, backend-neutral Platform Health snapshot.
class PlatformHealthPage extends ConsumerWidget {
  const PlatformHealthPage({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(platformHealthProvider);
    await ref.read(platformHealthProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(platformHealthProvider);
    return PlatformPage(
      title: S.platformHealthTitle,
      // One refresh affordance, not two. The app-bar icon and pull-to-refresh
      // did the same thing; the control now sits on the snapshot card, beside
      // the age it refreshes (UI audit P3, §39).
      onRefresh: () => _refresh(ref),
      children: [
        const PlatformPageIntro(lead: S.platformHealthLead),
        const SizedBox(height: AppSpacing.lg),
        ..._content(ref, async),
      ],
    );
  }

  List<Widget> _content(
    WidgetRef ref,
    AsyncValue<Result<PlatformHealthSnapshot>> async,
  ) {
    if (async.isLoading && !async.hasValue) {
      return const [_HealthLoading()];
    }
    if (async.hasError || !async.hasValue) {
      return [_failure(ref)];
    }

    return async.requireValue.when(
      success: (snapshot, {stale = false}) => [
        _HealthBody(
          snapshot: snapshot,
          freshness: stale ? _HealthFreshness.stale : _HealthFreshness.fresh,
          onRefresh: () => ref.invalidate(platformHealthProvider),
        ),
      ],
      failure: (_, __) => [_failure(ref)],
      offline: (cached) => cached == null
          ? [
              EmptyState(
                key: const Key('platform-health-offline-empty'),
                icon: Icons.cloud_off_rounded,
                title: S.platformHealthOfflineTitle,
                body: S.platformHealthOfflineBody,
                actionLabel: S.retry,
                onAction: () => ref.invalidate(platformHealthProvider),
              ),
            ]
          : [
              _HealthBody(
                snapshot: cached,
                freshness: _HealthFreshness.offline,
                onRefresh: () => ref.invalidate(platformHealthProvider),
              ),
            ],
    );
  }

  Widget _failure(WidgetRef ref) => ErrorStateView(
        key: const Key('platform-health-failure'),
        title: S.platformHealthFailureTitle,
        body: S.platformHealthFailureBody,
        onRetry: () => ref.invalidate(platformHealthProvider),
      );
}

enum _HealthFreshness { fresh, stale, offline }

class _HealthBody extends StatelessWidget {
  const _HealthBody({
    required this.snapshot,
    required this.freshness,
    required this.onRefresh,
  });

  final PlatformHealthSnapshot snapshot;
  final _HealthFreshness freshness;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('platform-health-loaded'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SnapshotCard(
          snapshot: snapshot,
          freshness: freshness,
          onRefresh: onRefresh,
        ),
        if (snapshot.isPartial) ...[
          const SizedBox(height: AppSpacing.md),
          const _PartialNotice(),
        ],
        const SizedBox(height: AppSpacing.xxl),
        const SectionHeader(
          style: SectionHeaderStyle.heading,
          icon: Icons.monitor_heart_outlined,
          title: S.platformHealthSignals,
        ),
        const SizedBox(height: AppSpacing.md),
        if (snapshot.signals.isEmpty)
          const EmptyState(
            key: Key('platform-health-no-signals'),
            icon: Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
            title: S.platformHealthNoSignalsTitle,
            body: S.platformHealthNoSignalsBody,
          )
        else
          _SignalList(signals: snapshot.signals),
      ],
    );
  }
}

class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard({
    required this.snapshot,
    required this.freshness,
    required this.onRefresh,
  });

  final PlatformHealthSnapshot snapshot;
  final _HealthFreshness freshness;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final status = _statusPresentation(snapshot.overallStatus);
    final freshnessLabel = switch (freshness) {
      _HealthFreshness.fresh => S.platformHealthFresh,
      _HealthFreshness.stale => S.platformHealthStale,
      _HealthFreshness.offline => S.platformHealthOfflineCached,
    };
    return Semantics(
      key: const Key('platform-health-overall'),
      container: true,
      label: '${S.platformHealthOverall}، ${status.label}، '
          '$freshnessLabel، ${S.platformHealthUpdated} '
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
            color:
                freshness == _HealthFreshness.offline ? c.warnTint : c.surface,
            border: Border.all(
              color: freshness == _HealthFreshness.offline ? c.warn : c.line,
            ),
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The refresh sits here, beside the age it refreshes — one
              // affordance where the page used to carry an app-bar icon and
              // pull-to-refresh for the same action (§39).
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      S.platformHealthOverall,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  // The visible label is one word; the tooltip is the
                  // accessible name and says which reading it refreshes.
                  Tooltip(
                    message: S.platformHealthRefresh,
                    child: TextButton.icon(
                      key: const Key('platform-health-refresh'),
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
                  StatusChip(kind: status.kind, label: status.label),
                  if (freshness == _HealthFreshness.stale) const StaleBadge(),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                freshnessLabel,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: c.ink2, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.sm),
              PlatformMeta(parts: [
                PlatformMetaText(
                  '${S.platformHealthUpdated} '
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

class _PartialNotice extends StatelessWidget {
  const _PartialNotice();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      key: const Key('platform-health-partial'),
      container: true,
      label: '${S.platformHealthPartialTitle}، ${S.platformHealthPartialBody}',
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: c.warnTint,
            border: Border.all(color: c.warn),
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: c.warn, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.platformHealthPartialTitle,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      S.platformHealthPartialBody,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: c.ink2, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignalList extends StatelessWidget {
  const _SignalList({required this.signals});

  final List<PlatformHealthSignal> signals;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      key: const Key('platform-health-signals'),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < signals.length; index++) ...[
            _SignalRow(signal: signals[index]),
            if (index != signals.length - 1) Divider(color: c.line),
          ],
        ],
      ),
    );
  }
}

class _SignalRow extends StatelessWidget {
  const _SignalRow({required this.signal});

  final PlatformHealthSignal signal;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final status = _statusPresentation(signal.status);
    final requiresAttention = signal.status != PlatformHealthStatus.healthy;
    return Semantics(
      key: Key('platform-health-signal-${signal.id}'),
      container: true,
      label: '${signal.label}، ${status.label}، ${signal.summary}، '
          '${S.platformHealthObserved} '
          '${PlatformTime.utcSpoken(signal.observedAt)}'
          '${requiresAttention ? '، ${S.platformHealthAttention}' : ''}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    signal.label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  StatusChip(kind: status.kind, label: status.label),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                signal.summary,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: c.ink2, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.sm),
              PlatformMeta(parts: [
                PlatformMetaText(
                  '${S.platformHealthObserved} '
                  '${PlatformTime.utcDate(signal.observedAt)}',
                ),
                PlatformMetaText(PlatformTime.utcTime(signal.observedAt)),
              ]),
              if (requiresAttention) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 17,
                      color: status.color(c),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        S.platformHealthAttention,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: status.color(c),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HealthLoading extends StatelessWidget {
  const _HealthLoading();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      key: const Key('platform-health-loading'),
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
              Skeleton(width: 120, height: 18),
              SizedBox(height: AppSpacing.md),
              Skeleton(width: 92, height: 24, radius: 12),
              SizedBox(height: AppSpacing.md),
              Skeleton(width: 210, height: 14),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        const Skeleton(width: 140, height: 20),
        const SizedBox(height: AppSpacing.md),
        const SkeletonRow(),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonRow(),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonRow(),
      ],
    );
  }
}

class _StatusPresentation {
  const _StatusPresentation(this.kind, this.label, this.color);

  final StatusKind kind;
  final String label;
  final Color Function(AppColors colors) color;
}

_StatusPresentation _statusPresentation(PlatformHealthStatus status) =>
    switch (status) {
      PlatformHealthStatus.healthy => _StatusPresentation(
          StatusKind.ok,
          S.platformHealthStatusHealthy,
          (colors) => colors.ok,
        ),
      PlatformHealthStatus.degraded => _StatusPresentation(
          StatusKind.warn,
          S.platformHealthStatusDegraded,
          (colors) => colors.warn,
        ),
      PlatformHealthStatus.unavailable => _StatusPresentation(
          StatusKind.crit,
          S.platformHealthStatusUnavailable,
          (colors) => colors.crit,
        ),
      PlatformHealthStatus.unknown => _StatusPresentation(
          StatusKind.muted,
          S.platformHealthStatusUnknown,
          (colors) => colors.ink2,
        ),
    };
