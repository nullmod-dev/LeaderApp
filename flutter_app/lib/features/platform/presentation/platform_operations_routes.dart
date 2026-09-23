import '../domain/platform_area.dart';
import '../domain/platform_report_models.dart' show PlatformReportType;

/// Canonical implemented destinations hosted by the Operations branch.
///
/// These remain siblings of `/platform/operations` because those public paths
/// were established before the screens landed. The router still places both
/// routes inside the Operations shell branch, so the fourth-area
/// information architecture does not change.
abstract final class PlatformOperationsRoutes {
  static const String health = '$kPlatformRoot/$kPlatformHealthSegment';
  static const String security = '$kPlatformRoot/$kPlatformAlertsSegment';
  static const String audit = '$kPlatformRoot/$kPlatformAuditSegment';
  static const String access = '$kPlatformRoot/access';
  static const String accessRequest = '$access/request';

  /// Customer Demo management. Unlike the siblings above it has no established
  /// public path to preserve, so it sits *under* the area it belongs to —
  /// which is also why `PlatformArea.operations` claims it with no new sibling
  /// segment to register.
  static const String demo = '$kPlatformRoot/operations/demo';
  static const String commerce = '$kPlatformRoot/operations/commerce';
  static const String commerceOffer = '$commerce/offer';
  static const String commerceCoupon = '$commerce/coupon';

  /// Point 13 — `/platform/reports`, the closed Platform Reports catalogue.
  static const String reports = '$kPlatformRoot/$kPlatformReportsSegment';

  /// `/platform/reports/:reportType` path parameter name.
  static const String reportTypeParam = 'reportType';

  /// `/platform/reports/<wire>` for one catalogue entry, e.g. `subscriptions`.
  static String report(PlatformReportType type) => '$reports/${type.wire}';

  static const List<String> all = [
    health,
    security,
    audit,
    access,
    reports,
    demo,
    commerce,
  ];
}
