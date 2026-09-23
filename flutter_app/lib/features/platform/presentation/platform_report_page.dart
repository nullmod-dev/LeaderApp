import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings.dart';
import '../domain/platform_report_models.dart';
import 'platform_activity_report_page.dart';
import 'platform_feature_availability_report_page.dart';
import 'platform_operations_routes.dart';
import 'platform_subscriptions_report_page.dart';
import 'platform_usage_limits_report_page.dart';
import 'widgets/platform_page.dart';

/// `/platform/reports/:reportType` — dispatches to one of the closed
/// catalogue's four pages by wire value. Point 13A §K.1: an unknown type is
/// never redirected — a deep link to a report a newer backend added, or a
/// typo, renders a safe in-place state with a way back, never a loop.
class PlatformReportPage extends StatelessWidget {
  const PlatformReportPage({super.key, required this.reportType});

  final String reportType;

  @override
  Widget build(BuildContext context) {
    return switch (PlatformReportType.parse(reportType)) {
      PlatformReportType.subscriptions =>
        const PlatformSubscriptionsReportPage(),
      PlatformReportType.usageLimits => const PlatformUsageLimitsReportPage(),
      PlatformReportType.featureAvailability =>
        const PlatformFeatureAvailabilityReportPage(),
      PlatformReportType.platformActivity => const PlatformActivityReportPage(),
      PlatformReportType.unknown => const _UnsupportedReportPage(),
    };
  }
}

class _UnsupportedReportPage extends StatelessWidget {
  const _UnsupportedReportPage();

  @override
  Widget build(BuildContext context) {
    return PlatformPage(
      title: S.platformReportUnsupportedTitle,
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: Column(
              key: const Key('report-unsupported'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.help_outline_rounded,
                    size: 48, color: context.c.ink3),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  S.platformReportUnsupportedTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  S.platformReportUnsupportedBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.c.ink3),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  key: const Key('report-unsupported-back'),
                  onPressed: () => context.go(PlatformOperationsRoutes.reports),
                  child: const Text(S.platformReportBackToCatalogue),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
