import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../../about/presentation/about_page.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../../shell/main_shell.dart';
import '../../tenant_feature/data/tenant_feature_providers.dart';
import '../../tenant_feature/domain/tenant_feature_models.dart';
import '../domain/organization_models.dart';
import 'organization_copy.dart';
import 'organization_widgets.dart';

/// Plan & subscription (`/more/plan`) — what the organisation is on, what it
/// may hold, and which modules it has. Point 15.
///
/// Four questions, four independent sources, never merged:
///
///  - **plan** and **subscription** — the commercial state (Point 7);
///  - **limits** — `override ?? plan default`, computed where Point 7
///    computes it, with usage beside it when the session may see
///    organisation-wide figures;
///  - **modules** — the tenant's Feature Flags, read from the same
///    `currentTenantFeatureAccessProvider` navigation obeys, so this screen
///    cannot claim a module the app then hides;
///  - **permissions** — not shown at all, and explicitly said to be separate:
///    an enabled module grants no capability, and a missing tool may be a
///    permission rather than the plan.
///
/// **Not a billing screen.** No price, currency, invoice, payment method,
/// upgrade, downgrade, cancel or renewal charge exists, and nothing here
/// suggests one. Plan changes are the platform's; the screen says so and
/// points at support.
class PlanPage extends StatelessWidget {
  const PlanPage({super.key});

  static const routePath = '/more/plan';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.c.bg,
      appBar: AppBar(title: const Text(S.settingsPlan)),
      body: FloatingNavPadding(
        child: OrganizationPageWidth(
          child: OrganizationReadView(
            builder: (context, snapshot, freshness) =>
                _PlanContent(snapshot: snapshot, freshness: freshness),
          ),
        ),
      ),
    );
  }
}

class _PlanContent extends StatelessWidget {
  const _PlanContent({required this.snapshot, required this.freshness});

  final OrganizationSnapshot snapshot;
  final OrganizationFreshness freshness;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('plan-page'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        OrganizationFreshnessNotice(
          freshness: freshness,
          readAt: snapshot.readAt,
        ),
        _PlanHeader(snapshot: snapshot),
        OrganizationColumns(
          start: [
            const OrganizationSectionTitle(S.planLimitsSection),
            _LimitsSection(snapshot: snapshot),
          ],
          end: [
            const OrganizationSectionTitle(S.planFeaturesSection),
            const _FeaturesSection(),
            const OrganizationSectionTitle(S.planExplainSection),
            OrganizationNote(
              key: const Key('plan-explain'),
              icon: Icons.info_outline_rounded,
              body: S.planExplainBody,
              action: TextButton.icon(
                key: const Key('plan-contact-support'),
                onPressed: () => context.push(AboutPage.routePath),
                icon: const Icon(Icons.support_agent_rounded, size: 18),
                label: const Text(S.contactSupport),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The plan as a heading, the organisation it belongs to, what the plan is
/// for, and the subscription's one relevant date.
class _PlanHeader extends StatelessWidget {
  const _PlanHeader({required this.snapshot});

  final OrganizationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final subscription = snapshot.subscription;
    final status = subscription.status;
    final title = OrganizationCopy.planTitle(subscription.plan);
    final statusLabel = OrganizationCopy.subscription(status);
    final dateLabel = OrganizationCopy.subscriptionDateLabel(status);
    final date = subscription.relevantDate;
    final note = OrganizationCopy.subscriptionNote(status);
    return Column(
      key: const Key('plan-header'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          header: true,
          label: S.planCurrentAnnouncement.replaceFirst('%s', title),
          excludeSemantics: true,
          child: Text(
            title,
            key: const Key('plan-title'),
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700, height: 1.3),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          snapshot.displayName,
          style: TextStyle(color: c.ink3, fontSize: 13),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          OrganizationCopy.planDescription(subscription.plan),
          key: const Key('plan-description'),
          style: TextStyle(color: c.ink2, fontSize: 14, height: 1.6),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              S.planSubscriptionLabel,
              style: TextStyle(color: c.ink3, fontSize: 13),
            ),
            OrganizationStatusChip(
              key: const Key('plan-subscription-chip'),
              label: statusLabel,
              kind: OrganizationCopy.subscriptionKind(status),
              icon: OrganizationCopy.subscriptionIcon(status),
              announcement:
                  S.orgSubscriptionAnnouncement.replaceFirst('%s', statusLabel),
            ),
          ],
        ),
        if (dateLabel != null && date != null) ...[
          const SizedBox(height: AppSpacing.md),
          SettingsSection(children: [
            OrganizationFact(
              key: const Key('plan-subscription-date'),
              icon: Icons.event_outlined,
              label: dateLabel,
              value: Text(OrganizationCopy.date(date)),
            ),
          ]),
        ],
        if (note != null) ...[
          const SizedBox(height: AppSpacing.md),
          OrganizationNote(
            key: const Key('plan-subscription-note'),
            icon: status == null
                ? Icons.help_outline_rounded
                : Icons.info_outline_rounded,
            body: note,
          ),
        ],
      ],
    );
  }
}

class _LimitsSection extends StatelessWidget {
  const _LimitsSection({required this.snapshot});

  final OrganizationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final limits = snapshot.limits;
    // No plan → no plan limits to show. Said plainly, never drawn as
    // "unlimited": that would be a claim nobody made.
    if (snapshot.subscription.plan is OrganizationPlanNone) {
      return const OrganizationNote(
        key: Key('plan-no-plan-limits'),
        icon: Icons.info_outline_rounded,
        body: S.planNoPlanLimits,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!limits.usageIncluded) ...[
          const OrganizationNote(
            key: Key('plan-usage-hidden'),
            icon: Icons.visibility_off_outlined,
            body: S.planUsageHiddenNote,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        SettingsSection(children: [
          for (final line in limits.items) _LimitRow(line: line),
        ]),
        if (limits.unsupportedCount > 0)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: AppSpacing.xs,
              top: AppSpacing.sm,
            ),
            child: Text(
              S.planLimitsUnsupported,
              key: const Key('plan-limits-unsupported'),
              style: TextStyle(color: c.ink3, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

/// One limit: its name, the figures, a quiet track, and — only where it is
/// true — "at limit" or "over limit" in words, never in colour alone.
class _LimitRow extends StatelessWidget {
  const _LimitRow({required this.line});

  final OrganizationLimit line;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final standing = line.standing;
    final flagged = standing == LimitStanding.atLimit ||
        standing == LimitStanding.overLimit;
    final ratio = line.ratio;
    final planDefault = line.planDefault;
    return Semantics(
      key: Key('plan-limit-${line.key.wire}'),
      container: true,
      excludeSemantics: true,
      label: OrganizationCopy.limitSemantics(line),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                OrganizationCopy.limitIcon(line.key),
                size: 20,
                color: c.ink3,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // A Wrap, so at 320 dp and a large text scale the figures
                  // take their own line instead of crushing the name.
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.xs,
                    children: [
                      Text(
                        OrganizationCopy.limit(line.key),
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      _Figures(line: line),
                    ],
                  ),
                  if (ratio != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 6,
                        color: flagged ? c.warn : c.primary,
                        backgroundColor: c.surface3,
                      ),
                    ),
                  ],
                  if (line.effective != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (flagged)
                          Row(
                            key: Key('plan-limit-flag-${line.key.wire}'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                standing == LimitStanding.overLimit
                                    ? Icons.error_outline_rounded
                                    : Icons.block_rounded,
                                size: 16,
                                color: c.warn,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  OrganizationCopy.standing(standing)!,
                                  style: TextStyle(
                                    color: c.warn,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        Text(
                          line.overridden && planDefault != null
                              ? S.limitCustom.replaceFirst(
                                  '%s',
                                  OrganizationCopy.amount(
                                      line.key, planDefault),
                                )
                              : S.limitPlanDefault,
                          style: TextStyle(color: c.ink3, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                  if (flagged) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      standing == LimitStanding.overLimit
                          ? S.limitOverNote
                          : S.limitAtNote,
                      style:
                          TextStyle(color: c.ink2, fontSize: 12, height: 1.5),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "used / limit" when usage is part of the read, "الحد الأقصى limit" when
/// it is not, and an honest "unavailable" when no limit was reported.
class _Figures extends StatelessWidget {
  const _Figures({required this.line});

  final OrganizationLimit line;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final effective = line.effective;
    if (effective == null) {
      return Text(
        S.limitUnavailable,
        style: TextStyle(color: c.ink3, fontSize: 13),
      );
    }
    final max = OrganizationCopy.amount(line.key, effective);
    final usage = line.usage;
    if (usage == null) {
      return Text.rich(
        TextSpan(children: [
          TextSpan(
            text: '${S.limitMax} ',
            style: TextStyle(color: c.ink3, fontSize: 13),
          ),
          TextSpan(text: max, style: AppTypography.digits(c.ink, size: 15)),
        ]),
      );
    }
    // One run in the Arabic paragraph: Arabic-Indic figures and the slash
    // resolve right-to-left under the bidi rules, so usage reads first, from
    // the right — «٢٣ / ٤٠» is twenty-three of forty, the same order as the
    // attendance count on Home. Storage keeps its unit beside each figure.
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: OrganizationCopy.amount(line.key, usage),
          style: AppTypography.digits(c.ink, size: 15),
        ),
        TextSpan(
          text: ' / $max',
          style: AppTypography.digits(c.ink3, size: 15),
        ),
      ]),
    );
  }
}

/// The four Feature Flag modules, from the runtime entitlement.
class _FeaturesSection extends ConsumerWidget {
  const _FeaturesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(currentTenantFeatureAccessProvider);
    // No readable entitlement → say so. Four "disabled" rows would be a
    // claim about the organisation the app cannot make.
    if (access.kind != TenantFeatureContextKind.tenant) {
      return const OrganizationNote(
        key: Key('plan-features-unavailable'),
        icon: Icons.help_outline_rounded,
        body: S.planFeaturesUnavailable,
      );
    }
    return SettingsSection(children: [
      for (final definition in tenantFeatureCatalog)
        _FeatureRow(
          definition: definition,
          enabled: access.isAvailable(definition.key),
        ),
    ]);
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.definition, required this.enabled});

  final TenantFeatureDefinition definition;
  final bool enabled;

  static IconData _icon(TenantFeatureKey key) => switch (key) {
        TenantFeatureKey.inventory => Icons.inventory_2_outlined,
        TenantFeatureKey.statisticsReports => Icons.insights_outlined,
        TenantFeatureKey.workshops => Icons.school_outlined,
        TenantFeatureKey.announcements => Icons.campaign_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final state = enabled ? S.featureEnabled : S.featureDisabled;
    return Semantics(
      key: Key('plan-feature-${definition.key.wire}'),
      container: true,
      excludeSemantics: true,
      label: S.featureStateAnnouncement
          .replaceFirst('%feature%', definition.arabicLabel)
          .replaceFirst('%state%', state),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                _icon(definition.key),
                size: 20,
                color: enabled ? c.ink2 : c.ink3,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                // Stretch, so the state chip lines up at the row's end on
                // every row instead of trailing each label.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.xs,
                    children: [
                      Text(
                        definition.arabicLabel,
                        style: TextStyle(
                          color: enabled ? c.ink : c.ink2,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      StatusChip(
                        key: Key('plan-feature-state-${definition.key.wire}'),
                        kind: enabled ? StatusKind.ok : StatusKind.muted,
                        label: state,
                        icon: enabled
                            ? Icons.check_rounded
                            : Icons.remove_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    definition.description,
                    style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
