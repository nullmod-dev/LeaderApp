import '../domain/platform_area.dart';

/// The three Point 6 locations, spelled once.
///
/// The router registers the segments; every `push` in the feature builds its
/// location from here. That is the same reason `kPlatformRoot` exists — a
/// route string typed in two files is a route string that eventually differs
/// in one of them.
abstract final class SaasTenantRoutes {
  /// `/platform/tenants` — the branch root, owned by `PlatformArea.tenants`.
  static String get list => PlatformArea.tenants.route;

  /// `/platform/tenants/new`.
  static String get create => '$list/$createSegment';

  /// `/platform/tenants/:tenantId`.
  static String detail(String tenantId) => '$list/$tenantId';

  static String subscription(String tenantId) =>
      '${detail(tenantId)}/$subscriptionSegment';

  static String limits(String tenantId) => '${detail(tenantId)}/$limitsSegment';

  static String features(String tenantId) =>
      '${detail(tenantId)}/$featuresSegment';

  static String mainAdmin(String tenantId) =>
      '${detail(tenantId)}/$mainAdminSegment';

  static String mainAdminReplace(String tenantId) =>
      '${mainAdmin(tenantId)}/$mainAdminReplaceSegment';

  /// The literal segment. Registered **before** [detailSegment] so `new` is
  /// matched as itself rather than swallowed as a tenant id.
  static const String createSegment = 'new';

  static const String detailSegment = ':$tenantIdParam';
  static const String subscriptionSegment = 'subscription';
  static const String limitsSegment = 'limits';
  static const String featuresSegment = 'features';
  static const String mainAdminSegment = 'main-admin';
  static const String mainAdminReplaceSegment = 'replace';

  /// The path parameter name, shared by the route and the page that reads it.
  static const String tenantIdParam = 'tenantId';
}
