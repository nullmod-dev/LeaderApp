import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../../pricing/data/commerce_control_plane.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../data/platform_break_glass_providers.dart';
import '../data/platform_demo_providers.dart';
import '../domain/platform_area.dart';
import 'platform_break_glass_copy.dart';
import 'platform_demo_copy.dart';
import 'platform_destinations.dart';
import 'platform_operations_routes.dart';
import 'widgets/platform_page.dart';

/// `/platform/operations` — the area that keeps the bottom bar at four rows.
///
/// **Five groups, not one list of seven.** The 2026-09-19 UI audit found this
/// page reading as a documentation index: seven identical `NavigationRow`s,
/// each carrying a two-line explanation, no counts, no state and no grouping —
/// so «الوصول الطارئ», the most consequential capability on the surface, had
/// exactly the weight of «تقارير المنصة».
///
/// The routes are unchanged and no destination was invented. What changed is
/// that the rows are sorted by *what they are for*, that the ones with live
/// local state say what it is, and that the emergency-access row sits **last
/// and alone**, under a heading that says what opening it means — the danger
/// zone at the bottom of the page rather than the fourth of seven identical
/// rows.
class PlatformOperationsPage extends ConsumerWidget {
  const PlatformOperationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destination = destinationFor(PlatformArea.operations);
    final c = context.c;
    final access = ref.watch(breakGlassAccessProvider);
    // Both of these are synchronous local control planes — reading them adds
    // no loading state to this page. Health and Security are network-shaped
    // and are deliberately *not* read here: a navigation index that spins
    // before it can be navigated is worse than one that describes itself.
    final demos = ref.watch(demoSessionCountsProvider);
    final commerce = ref.watch(commerceControlPlaneProvider);
    final liveOffers = commerce.offers.where((offer) => offer.enabled).length +
        commerce.coupons.where((coupon) => coupon.enabled).length;

    return PlatformPage(
      title: destination.label,
      children: [
        const PlatformPageIntro(lead: S.platformOperationsLead),
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(title: S.platformOperationsGroupMonitor),
        SettingsSection(
          children: [
            NavigationRow(
              key: const Key('platform-operations-health'),
              icon: Icons.monitor_heart_outlined,
              label: S.platformOpsHealth,
              subtitle: S.platformOperationsRowHealth,
              onTap: () => context.push(PlatformOperationsRoutes.health),
            ),
            NavigationRow(
              key: const Key('platform-operations-security'),
              icon: Icons.security_outlined,
              label: S.platformSecurityTitle,
              subtitle: S.platformOperationsRowSecurity,
              onTap: () => context.push(PlatformOperationsRoutes.security),
            ),
          ],
        ),
        const SectionHeader(title: S.platformOperationsGroupCustomers),
        SettingsSection(
          children: [
            // The one Demo control in the product. Everything a Demo needs
            // administering — availability, window, running sessions — is
            // behind this row and nowhere else.
            NavigationRow(
              key: const Key('platform-operations-demo'),
              icon: Icons.science_outlined,
              label: S.platformOpsDemo,
              subtitle: S.platformOperationsRowDemo,
              badge: demos.active == 0
                  ? null
                  : _CountBadge(
                      kind: StatusKind.info,
                      count: demos.active,
                      spoken: PlatformDemoCopy.activeSessions(demos.active),
                    ),
              onTap: () => context.push(PlatformOperationsRoutes.demo),
            ),
          ],
        ),
        const SectionHeader(title: S.platformOperationsGroupCommerce),
        SettingsSection(
          children: [
            NavigationRow(
              key: const Key('platform-operations-commerce'),
              icon: Icons.sell_outlined,
              label: S.platformOpsCommerce,
              subtitle: S.platformOperationsRowCommerce,
              badge: liveOffers == 0
                  ? null
                  : _CountBadge(
                      kind: StatusKind.ok,
                      count: liveOffers,
                      spoken: PlatformDemoCopy.livePromotions(liveOffers),
                    ),
              onTap: () => context.push(PlatformOperationsRoutes.commerce),
            ),
          ],
        ),
        const SectionHeader(title: S.platformOperationsGroupReview),
        SettingsSection(
          children: [
            NavigationRow(
              key: const Key('platform-operations-audit'),
              icon: Icons.history_outlined,
              label: S.platformOpsAudit,
              subtitle: S.platformOperationsRowAudit,
              onTap: () => context.push(PlatformOperationsRoutes.audit),
            ),
            NavigationRow(
              key: const Key('platform-operations-reports'),
              icon: Icons.insert_chart_outlined_rounded,
              label: S.platformOpsReports,
              subtitle: S.platformOperationsRowReports,
              onTap: () => context.push(PlatformOperationsRoutes.reports),
            ),
          ],
        ),
        const SectionHeader(title: S.platformOperationsGroupCritical),
        SettingsSection(
          children: [
            // Alone, under its own heading, with a critical-toned glyph and a
            // chip when a grant is live. Not flashy — no tinted card, no
            // warning banner — because the point is that it reads as a
            // *different kind of thing* from the rows above it, and hierarchy
            // does that more honestly than decoration. Authorization is
            // unchanged: the screen behind this row still refuses on its own.
            NavigationRow(
              key: const Key('platform-operations-break-glass'),
              icon: Icons.admin_panel_settings_outlined,
              iconColor: c.crit,
              label: S.platformOpsBreakGlass,
              subtitle: BreakGlassCopy.operationSummary(access),
              badge: access.isPossiblyLive
                  ? const StatusChip(
                      kind: StatusKind.crit,
                      label: S.platformOperationsBreakGlassActive,
                    )
                  : null,
              onTap: () => context.push(PlatformOperationsRoutes.access),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: AppSpacing.sm),
          child: _CriticalNote(),
        ),
      ],
    );
  }
}

/// A count on a navigation row.
///
/// Drawn as the numeral alone, because the badge shares a row with a title, a
/// subtitle and a chevron and has to survive a 320 dp phone at a 1.6 text
/// scale. Announced as a sentence, because «١» on its own tells a screen
/// reader nothing.
class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.kind,
    required this.count,
    required this.spoken,
  });

  final StatusKind kind;
  final int count;
  final String spoken;

  @override
  Widget build(BuildContext context) => Semantics(
        label: spoken,
        child: ExcludeSemantics(
          child: StatusChip(
            kind: kind,
            label: PlatformDemoCopy.count('%d', count),
          ),
        ),
      );
}

class _CriticalNote extends StatelessWidget {
  const _CriticalNote();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 16, color: c.ink3),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            S.platformOperationsCriticalNote,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: c.ink3, height: 1.5),
          ),
        ),
      ],
    );
  }
}
