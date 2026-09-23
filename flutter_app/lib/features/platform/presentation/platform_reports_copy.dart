import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../../tenant_feature/domain/tenant_feature_models.dart';
import '../domain/platform_report_datasets.dart';
import '../domain/platform_report_models.dart';
import '../domain/saas_subscription_models.dart';

/// Point 13B — presentation vocabulary for the closed report catalogue.
///
/// Kept separate from the Point 13A domain (`platform_report_datasets.dart`)
/// for the same reason `AuditCopy` is separate from the Audit domain: a wire
/// value is never rendered directly, and every switch here is exhaustive so a
/// catalogue change that this file has not caught up with fails to compile
/// rather than falling through to a made-up label.
abstract final class PlatformReportsCopy {
  static String title(PlatformReportType type) => switch (type) {
        PlatformReportType.subscriptions => S.platformReportSubscriptionsTitle,
        PlatformReportType.usageLimits => S.platformReportUsageLimitsTitle,
        PlatformReportType.featureAvailability =>
          S.platformReportFeatureAvailabilityTitle,
        PlatformReportType.platformActivity => S.platformReportActivityTitle,
        PlatformReportType.unknown => S.platformReportUnsupportedTitle,
      };

  /// The one-line question the landing row states under the title.
  static String question(PlatformReportType type) => switch (type) {
        PlatformReportType.subscriptions =>
          S.platformReportSubscriptionsQuestion,
        PlatformReportType.usageLimits => S.platformReportUsageLimitsQuestion,
        PlatformReportType.featureAvailability =>
          S.platformReportFeatureAvailabilityQuestion,
        PlatformReportType.platformActivity => S.platformReportActivityQuestion,
        PlatformReportType.unknown => '',
      };

  static String kindLabel(PlatformReportDataKind kind) => switch (kind) {
        PlatformReportDataKind.currentSnapshot => S.platformReportKindSnapshot,
        PlatformReportDataKind.periodSummary => S.platformReportKindPeriod,
      };

  static String bandLabel(UsageLimitBand band) => switch (band) {
        UsageLimitBand.withinLimit => S.platformUsageBandWithin,
        UsageLimitBand.atLimit => S.platformUsageBandAt,
        UsageLimitBand.overLimit => S.platformUsageBandOver,
        UsageLimitBand.noLimit => S.platformUsageBandNoLimit,
      };

  static StatusKind bandKind(UsageLimitBand band) => switch (band) {
        UsageLimitBand.overLimit => StatusKind.crit,
        UsageLimitBand.atLimit => StatusKind.warn,
        UsageLimitBand.withinLimit => StatusKind.ok,
        UsageLimitBand.noLimit => StatusKind.muted,
      };

  static String featureAvailabilityLabel(TenantFeatureAvailability state) =>
      switch (state) {
        TenantFeatureAvailability.enabled => S.platformFeatureEnabled,
        TenantFeatureAvailability.disabled => S.platformFeatureDisabled,
      };

  static StatusKind featureAvailabilityKind(TenantFeatureAvailability state) =>
      switch (state) {
        TenantFeatureAvailability.enabled => StatusKind.ok,
        TenantFeatureAvailability.disabled => StatusKind.muted,
      };

  static String featureKeyLabel(TenantFeatureKey key) =>
      definitionOf(key).arabicLabel;

  /// The label in front of a subscription row's `relevantDate`, chosen by the
  /// row's own status — `null` (inactive, or the date is missing) shows no
  /// date fragment at all, never a guessed one.
  static String? subscriptionRelevantDateLabel(SubscriptionStatus? status) =>
      switch (status) {
        SubscriptionStatus.trial => 'تنتهي التجربة',
        SubscriptionStatus.active => 'يتجدد',
        SubscriptionStatus.grace => 'تنتهي المهلة',
        SubscriptionStatus.inactive || null => null,
      };

  /// A value this build does not recognise — the report's own honest word for
  /// it, never a guess at what a newer backend meant.
  static const unsupportedValueLabel = S.platformReportUnsupportedValuesNote;
}
