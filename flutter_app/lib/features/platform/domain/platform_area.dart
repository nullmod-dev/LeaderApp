/// The Super Admin platform's top-level information architecture.
///
/// **Pure Dart, and that is the point.** This file is the one statement of
/// what areas the SaaS control plane has, what each one is called on the wire
/// (its route), what order they appear in, and whether its module has landed
/// yet. It holds no icon, no label, no widget and no navigation behaviour —
/// those are presentation, and they live in
/// `presentation/platform_destinations.dart`.
///
/// Keeping the split is what `§18` of the Point 4 brief asks for: the later
/// Super Admin **web** dashboard will have a sidebar, not a bottom bar, and a
/// different icon set, but it has to agree with this app about which areas
/// exist and what `/platform/tenants` means. A domain model carrying a
/// `NavigationBar` assumption could not be shared; this one can.
///
/// It is also what the *router* and the *startup classifier* read
/// ([kPlatformRoot]), so there is exactly one spelling of `/platform` in the
/// app — the failure mode the classifier's own header warns about.
library;

/// The platform surface's root route.
///
/// A top-level constant rather than `PlatformArea.overview.route` because
/// `StartupDestination.platformSurface` needs it in a **const** enum argument,
/// and an enum getter is not a constant expression.
const String kPlatformRoot = '/platform';

/// Established sibling segments for the Point 10 Operations modules.
///
/// Their full public locations are exposed by `PlatformOperationsRoutes` in
/// presentation, while the pure area registry keeps just enough route shape
/// to classify both locations as part of [PlatformArea.operations].
const String kPlatformHealthSegment = 'health';
const String kPlatformAlertsSegment = 'alerts';
const String kPlatformAuditSegment = 'audit';

/// Point 13 — Platform Reports. Unlike the Point 10 siblings above, this
/// segment owns a child route (`/platform/reports/:reportType`), so
/// [PlatformArea.contains] matches it and everything under it, not only the
/// exact segment.
const String kPlatformReportsSegment = 'reports';

/// Whether an area's module exists yet.
///
/// Point 4 builds the shell, not the modules. Rather than leaving that fact in
/// a comment, it is typed: the navigation renders every area, and each area's
/// landing surface reads its own readiness to decide whether it presents
/// content or a deliberate section state. When Point 6 lands the tenant list,
/// exactly one value here changes and one page body is replaced — no route
/// moves, no destination appears or disappears under a user who had learned
/// where things were.
enum PlatformAreaReadiness {
  /// The area's content in this build is real and complete for what it claims.
  available,

  /// The route, the destination and a designed section surface exist; the
  /// module that fills them belongs to a later Point.
  ///
  /// **Not "disabled" and not "coming soon".** A reserved area is reachable,
  /// says truthfully what it will manage, and offers no control that does
  /// nothing — see `PlatformSectionHeader` / `PlatformNoteCard`.
  reserved,
}

/// One top-level area of the platform control plane.
///
/// Four, deliberately, and they are *areas* rather than actions: a control
/// plane grows modules constantly, and a navigation model that gave each
/// module a row would be re-learned every release. Points 5–13 add pages
/// *inside* these four; none of them adds a fifth.
enum PlatformArea {
  /// **المنصة** — the control-plane home. Point 5 owns the real dashboard
  /// (status, subscriptions, activity, security attention); Point 4 ships the
  /// authenticated landing surface it will replace.
  overview(
    segment: null,
    readiness: PlatformAreaReadiness.available,
  ),

  /// **الفرق** — the paying customers, one `SaasTenant` each.
  ///
  /// MTM's own word for a customer is a team, so that is the word used here
  /// rather than importing a commercial one («العملاء») the product does not
  /// otherwise speak. There is no collision risk with the tenant app's
  /// «الفريق»: a Super Admin never sees the tenant application.
  ///
  /// Point 6 owns list/detail/provisioning. Point 9 hosts lifecycle actions
  /// inside tenant detail rather than adding a separate primary destination.
  tenants(
    segment: 'tenants',
    readiness: PlatformAreaReadiness.available,
  ),

  /// **العمليات** — every platform-management module that must not consume a
  /// primary destination of its own: customer demos, health, alerts, audit,
  /// break-glass access, cross-tenant subscription operations, reports.
  ///
  /// Points 7–13. Its existence as one area is the decision that keeps the
  /// bottom bar at four rows however many modules arrive.
  operations(
    segment: 'operations',
    readiness: PlatformAreaReadiness.available,
    siblingSegments: {
      kPlatformHealthSegment,
      kPlatformAlertsSegment,
      kPlatformAuditSegment,
      kPlatformReportsSegment,
    },
  ),

  /// **المزيد** — the Super Admin's own account and application settings.
  ///
  /// An allowlist, never the tenant Settings hub with rows hidden: the
  /// organisation record, the tenant plan, detachment settings and tenant
  /// admin management are not this account's, and a screen that read them
  /// would initialise repositories this surface must never touch.
  more(
    segment: 'more',
    readiness: PlatformAreaReadiness.available,
  );

  const PlatformArea({
    required this.segment,
    required this.readiness,
    this.siblingSegments = const {},
  });

  /// The path segment under [kPlatformRoot], or `null` for the area that *is*
  /// the root.
  ///
  /// [overview] has no segment on purpose: `/platform` is where a Super Admin
  /// lands, and `/platform/overview` redirecting to it — or not — would be one
  /// more thing to keep in step for no gain.
  final String? segment;

  final PlatformAreaReadiness readiness;

  /// Canonical routes that belong to this branch without sitting below the
  /// area's root path. Point 10 retains the already documented
  /// `/platform/health` and `/platform/alerts` locations while hosting both
  /// inside the Operations branch.
  final Set<String> siblingSegments;

  /// The canonical route of this area's root page.
  String get route =>
      segment == null ? kPlatformRoot : '$kPlatformRoot/$segment';

  /// Whether [location] is this area's root or a page inside it.
  ///
  /// [overview] claims only its exact route, because every other area's route
  /// starts with it — an "is it under `/platform`" test would match all four.
  bool contains(String location) {
    if (location == route) return true;
    // Prefix-aware: a sibling segment may itself own child routes (Point 13
    // `/platform/reports/:reportType`), so it claims its own subtree exactly
    // like the area's own [route] does below, not only its bare segment.
    if (siblingSegments.any(
      (segment) =>
          location == '$kPlatformRoot/$segment' ||
          location.startsWith('$kPlatformRoot/$segment/'),
    )) {
      return true;
    }
    if (segment == null) return false;
    return location.startsWith('$route/');
  }

  /// The area [location] belongs to, or `null` when it is outside the platform
  /// surface entirely.
  ///
  /// Longest match wins by construction: [overview] is exact-only, so a
  /// `/platform/tenants/t_1` cannot be mistaken for the root.
  static PlatformArea? forLocation(String location) {
    for (final area in values) {
      if (area != PlatformArea.overview && area.contains(location)) return area;
    }
    return PlatformArea.overview.contains(location)
        ? PlatformArea.overview
        : null;
  }

  /// The area a shell branch index selects. Branch order **is** declaration
  /// order, and both the compact bar and the rail derive from this list, so
  /// there is no second ordering to keep in step.
  static PlatformArea ofBranch(int index) => values[index];

  /// This area's branch index in the platform shell.
  int get branchIndex => index;
}
