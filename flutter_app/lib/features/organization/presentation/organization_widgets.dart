import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/problem/problem.dart';
import '../../../core/problem/problem_presentation.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/reading_column.dart';
import '../../../core/widgets/refresh_indicator.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../data/organization_providers.dart';
import '../domain/organization_models.dart';
import '../domain/organization_repository.dart';
import 'organization_copy.dart';

/// How current the snapshot on screen is.
enum OrganizationFreshness {
  fresh,

  /// A cached copy shown after a refresh failed.
  stale,

  /// A cached copy shown because the device is offline.
  offline,
}

/// The states both Point 15 screens share, resolved once.
///
/// Not `AsyncResultView`: that widget folds "offline with a cached copy" into
/// "stale", and these screens say which of the two it is — the viewer can do
/// something about being offline, and nothing about a server that failed.
class OrganizationReadView extends ConsumerWidget {
  const OrganizationReadView({super.key, required this.builder});

  final Widget Function(
    BuildContext context,
    OrganizationSnapshot snapshot,
    OrganizationFreshness freshness,
  ) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(organizationSnapshotProvider);
    void retry() => ref.invalidate(organizationSnapshotProvider);
    return AppRefreshIndicator(
      onRefresh: () => ref.refresh(organizationSnapshotProvider.future),
      child: value.when(
        loading: () => const SkeletonList(count: 4),
        error: (_, __) => ErrorStateView(onRetry: retry),
        data: (result) => result.when(
          success: (snapshot, {stale = false}) => builder(
            context,
            snapshot,
            stale ? OrganizationFreshness.stale : OrganizationFreshness.fresh,
          ),
          offline: (cached) => cached == null
              ? EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: S.offlineTitle,
                  body: S.orgOfflineNoCache,
                  actionLabel: S.retry,
                  onAction: retry,
                )
              : builder(context, cached, OrganizationFreshness.offline),
          failure: (message, code) {
            if (OrganizationProblemCode.parse(code) ==
                OrganizationProblemCode.contextUnavailable) {
              return const EmptyState(
                icon: Icons.apartment_rounded,
                title: S.orgUnavailableTitle,
                body: S.orgUnavailableBody,
              );
            }
            final view = resolveProblem(Problem.of(
              ProblemCode.parse(code),
              rawCode: code,
              detail: message,
            ));
            return ErrorStateView(
              title: view.title,
              body: view.message,
              onRetry: retry,
            );
          },
        ),
      ),
    );
  }
}

/// Says why the screen shows a cached copy, when it was read, and offers a
/// read — never a write, never a replay.
class OrganizationFreshnessNotice extends ConsumerWidget {
  const OrganizationFreshnessNotice({
    super.key,
    required this.freshness,
    required this.readAt,
  });

  final OrganizationFreshness freshness;
  final DateTime readAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (freshness == OrganizationFreshness.fresh) {
      return const SizedBox.shrink();
    }
    final c = context.c;
    final offline = freshness == OrganizationFreshness.offline;
    return Container(
      key: const Key('org-freshness-notice'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.mutedTint,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  offline ? Icons.cloud_off_rounded : Icons.history_rounded,
                  size: 20,
                  color: c.ink2,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    offline ? S.orgOfflineNotice : S.orgStaleNotice,
                    style: TextStyle(color: c.ink, fontSize: 13, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 28),
            child: Text(
              '${S.orgLastRead}: ${OrganizationCopy.readAt(readAt)}',
              style: TextStyle(color: c.ink3, fontSize: 12),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            key: const Key('org-refresh'),
            onPressed: () => ref.invalidate(organizationSnapshotProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(S.orgRefresh),
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size.fromHeight(48)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A section title on the organisation screens.
///
/// The heading semantics that used to be added here now live in the shared
/// [SectionHeader] that [SectionLabel] renders, so every section in the app
/// is announced the same way rather than only these two screens'.
class OrganizationSectionTitle extends StatelessWidget {
  const OrganizationSectionTitle(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => SectionLabel(label);
}

/// A status chip announced with what it is the status *of*, so "فترة سماح"
/// is never read out without "الاشتراك".
class OrganizationStatusChip extends StatelessWidget {
  const OrganizationStatusChip({
    super.key,
    required this.label,
    required this.kind,
    required this.icon,
    required this.announcement,
  });

  final String label;
  final StatusKind kind;
  final IconData icon;
  final String announcement;

  @override
  Widget build(BuildContext context) => Semantics(
        // Its own node: two chips side by side are two statuses, and without
        // a container they merge into one announcement on the parent.
        container: true,
        label: announcement,
        excludeSemantics: true,
        child: StatusChip(kind: kind, label: label, icon: icon),
      );
}

/// One label/value fact inside a [SettingsSection].
///
/// Side by side while the value has room; stacked, label above value, once
/// the text scale or a narrow phone would squeeze either to a sliver. The
/// leading icon lines the text up with the section's divider indent.
class OrganizationFact extends StatelessWidget {
  const OrganizationFact({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.help,
    this.trailing,
  });

  final IconData icon;
  final String label;

  /// Usually a [Text]; a technical value brings its own LTR isolation.
  final Widget value;
  final String? help;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final labelText =
        Text(label, style: TextStyle(color: c.ink3, fontSize: 13));
    final valueText = DefaultTextStyle.merge(
      style: TextStyle(color: c.ink, fontSize: 15, fontWeight: FontWeight.w500),
      child: value,
    );
    // Label and value are one announcement; a trailing action stays its own
    // focusable control rather than being merged into the fact.
    final fact = MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 20, color: c.ink3),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(builder: (context, constraints) {
                  final em = MediaQuery.textScalerOf(context).scale(14);
                  if (constraints.maxWidth < em * 20) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        labelText,
                        const SizedBox(height: 2),
                        valueText,
                      ],
                    );
                  }
                  // Both loose: a short label keeps one line and a short
                  // value sits at the row's end; only a long one wraps.
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(flex: 3, child: labelText),
                      const SizedBox(width: AppSpacing.md),
                      Flexible(flex: 2, child: valueText),
                    ],
                  );
                }),
                if (help != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    help!,
                    style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md,
        trailing == null ? AppSpacing.md : AppSpacing.xs,
        trailing == null ? AppSpacing.md : AppSpacing.xs,
        trailing == null ? AppSpacing.md : AppSpacing.xs,
      ),
      child: trailing == null
          ? fact
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    child: fact,
                  ),
                ),
                trailing!,
              ],
            ),
    );
  }
}

/// A calm explanatory note with an optional action. Not a banner and not a
/// card: a hairline-bounded paragraph on the page ground.
class OrganizationNote extends StatelessWidget {
  const OrganizationNote({
    super.key,
    required this.icon,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 20, color: c.ink3),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  body,
                  style: TextStyle(color: c.ink2, fontSize: 13, height: 1.6),
                ),
              ),
            ],
          ),
          if (action != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 28),
              child: action!,
            ),
        ],
      ),
    );
  }
}

/// Two columns once the content is wide enough to hold them without either
/// becoming a strip; one column below that. Reading order stays start column
/// first, then end column.
/// The page measure for the two organisation screens.
///
/// Narrow enough to read until the content has room for two columns, then
/// out of the way. A limit row puts its label at the start and its figures at
/// the end, so a single column stretched to 568 dp on a 600 dp tablet is a
/// label and a number with most of the row empty between them — the defect
/// the 2026-09-19 audit read off `09-plan-600-light.png`. Below 520 dp (every
/// phone) it does nothing at all.
///
/// Above [OrganizationColumns.breakpoint] the cap lifts, because at that
/// width the content stops being one column and reflows into two.
class OrganizationPageWidth extends StatelessWidget {
  const OrganizationPageWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth < OrganizationColumns.breakpoint
                ? ReadingColumn(child: child)
                : child,
      );
}

class OrganizationColumns extends StatelessWidget {
  const OrganizationColumns({
    super.key,
    required this.start,
    required this.end,
  });

  final List<Widget> start;
  final List<Widget> end;

  static const double breakpoint = 760;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < breakpoint) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [...start, ...end],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: start,
            ),
          ),
          const SizedBox(width: AppSpacing.xl),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: end,
            ),
          ),
        ],
      );
    });
  }
}
