import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../domain/platform_report_models.dart';
import 'platform_operations_routes.dart';
import 'platform_reports_copy.dart';
import 'widgets/platform_page.dart';

/// `/platform/reports` — Point 13A §K.2: two `SectionLabel` groups, current
/// state and period, one `NavigationRow`-shaped entry each, no numbers on the
/// landing (the Overview stays the one place for that) and no report data —
/// this page states what each report is, never what it currently says.
class PlatformReportsCataloguePage extends StatelessWidget {
  const PlatformReportsCataloguePage({super.key});

  static const _current = [
    PlatformReportType.subscriptions,
    PlatformReportType.usageLimits,
    PlatformReportType.featureAvailability,
  ];
  static const _period = [PlatformReportType.platformActivity];

  @override
  Widget build(BuildContext context) {
    return PlatformPage(
      title: S.platformOpsReports,
      children: [
        const PlatformPageIntro(lead: S.platformReportsLead),
        const SizedBox(height: AppSpacing.lg),
        const SectionLabel(S.platformReportsSectionCurrent),
        SettingsSection(
          children: [
            for (final type in _current) _ReportCatalogueRow(type: type),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        const SectionLabel(S.platformReportsSectionPeriod),
        SettingsSection(
          children: [
            for (final type in _period) _ReportCatalogueRow(type: type),
          ],
        ),
      ],
    );
  }
}

/// One catalogue entry.
///
/// `NavigationRow`, not a hand-built `ListTile`. The page used to re-implement
/// the shared row with the same padding and a two-line subtitle — and pick the
/// wrong chevron while doing it (UI audit P2). The report's *kind* — a current
/// state or a period — moves from a third line of small bold text to the row's
/// badge, which is what a one-word state belongs in.
class _ReportCatalogueRow extends StatelessWidget {
  const _ReportCatalogueRow({required this.type});

  final PlatformReportType type;

  @override
  Widget build(BuildContext context) {
    final definition = PlatformReportCatalogue.of(type)!;
    return NavigationRow(
      key: Key('platform-report-${type.wire}'),
      icon: _iconFor(type),
      label: PlatformReportsCopy.title(type),
      subtitle: PlatformReportsCopy.question(type),
      badge: StatusChip(
        kind: StatusKind.muted,
        label: PlatformReportsCopy.kindLabel(definition.dataKind),
      ),
      onTap: () => context.push(PlatformOperationsRoutes.report(type)),
    );
  }

  static IconData _iconFor(PlatformReportType type) => switch (type) {
        PlatformReportType.subscriptions => Icons.workspace_premium_outlined,
        PlatformReportType.usageLimits => Icons.speed_outlined,
        PlatformReportType.featureAvailability => Icons.toggle_on_outlined,
        PlatformReportType.platformActivity => Icons.timeline_outlined,
        PlatformReportType.unknown => Icons.help_outline_rounded,
      };
}
