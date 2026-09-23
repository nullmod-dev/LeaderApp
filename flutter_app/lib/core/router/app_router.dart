import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/demo/data/demo_workspace.dart';
import '../../features/about/presentation/about_page.dart';
import '../../features/admin_management/presentation/simple_admin_management_page.dart';
import '../../features/announcement/presentation/announcement_compose_page.dart';
import '../../features/announcement/presentation/announcements_page.dart';
import '../../features/app_version/presentation/upgrade_required_page.dart';
import '../../features/auth/data/auth_providers.dart';
import '../../features/auth/presentation/dev_session_states_page.dart';
import '../../features/auth/presentation/forgot_password_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/mfa_challenge_page.dart';
import '../../features/auth/presentation/mfa_setup_page.dart';
import '../../features/auth/presentation/new_device_page.dart';
import '../../features/auth/presentation/new_password_page.dart';
import '../../features/auth/presentation/otp_page.dart';
import '../../features/auth/presentation/session_expired_page.dart';
import '../../features/auth/presentation/signup_page.dart';
import '../../features/auth/presentation/startup_page.dart';
import '../../features/auth/presentation/status_pages.dart';
import '../../features/conflict/domain/conflict_models.dart';
import '../../features/conflict/presentation/conflict_resolution_page.dart';
import '../../features/conflict/presentation/conflict_resolution_route.dart';
import '../../features/conflict/presentation/needs_review_page.dart';
import '../../features/detachment/presentation/detachment_detail_shell.dart';
import '../../features/detachment/presentation/detachment_edit_page.dart';
import '../../features/detachment/presentation/detachment_list_page.dart';
import '../../features/detachment/presentation/detachment_member_edit_page.dart';
import '../../features/detachment/presentation/detachment_member_status_page.dart';
import '../../features/detachment/presentation/tabs/detachment_shifts_tab.dart';
import '../../features/detachment/presentation/tabs/detachment_stats_tab.dart';
import '../../features/detachment/presentation/tabs/detachment_storage_tab.dart';
import '../../features/detachment/presentation/tabs/detachment_team_tab.dart';
import '../../features/detachment/domain/report_models.dart';
import '../../features/detachment/presentation/report_export_page.dart';
import '../../features/detachment/presentation/report_preview_page.dart';
import '../../features/inventory/presentation/inventory_item_edit_page.dart';
import '../../features/notification/presentation/notifications_center_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/settings/presentation/notifications_page.dart';
import '../../features/organization/presentation/organization_page.dart';
import '../../features/organization/presentation/plan_page.dart';
import '../../features/pricing/presentation/pricing_page.dart';
import '../../features/settings/presentation/profile_page.dart';
import '../../features/settings/presentation/security_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/settings/presentation/sync_page.dart';
import '../../features/search/presentation/global_search_page.dart';
import '../../features/settings/presentation/themes_and_performance_page.dart';
import '../../features/platform/domain/platform_area.dart';
import '../../features/platform/domain/platform_audit_models.dart';
import '../../features/platform/presentation/platform_audit_page.dart';
import '../../features/platform/presentation/platform_break_glass_page.dart';
import '../../features/platform/presentation/platform_break_glass_request_page.dart';
import '../../features/platform/presentation/platform_commerce_page.dart';
import '../../features/platform/presentation/platform_offer_edit_page.dart';
import '../../features/platform/presentation/platform_coupon_edit_page.dart';
import '../../features/platform/presentation/platform_health_page.dart';
import '../../features/platform/presentation/platform_more_page.dart';
import '../../features/platform/presentation/platform_main_admin_page.dart';
import '../../features/platform/presentation/platform_main_admin_replace_page.dart';
import '../../features/platform/presentation/platform_demo_page.dart';
import '../../features/platform/presentation/platform_operations_page.dart';
import '../../features/platform/presentation/platform_operations_routes.dart';
import '../../features/platform/presentation/platform_overview_page.dart';
import '../../features/platform/presentation/platform_report_page.dart';
import '../../features/platform/presentation/platform_reports_catalogue_page.dart';
import '../../features/platform/presentation/platform_security_page.dart';
import '../../features/platform/presentation/platform_shell.dart';
import '../../features/platform/presentation/platform_tenants_page.dart';
import '../../features/platform/presentation/saas_tenant_create_page.dart';
import '../../features/platform/presentation/saas_tenant_detail_page.dart';
import '../../features/platform/presentation/saas_tenant_limits_page.dart';
import '../../features/platform/presentation/saas_tenant_features_page.dart';
import '../../features/platform/presentation/saas_tenant_routes.dart';
import '../../features/platform/presentation/saas_tenant_subscription_page.dart';
import '../../features/shell/main_shell.dart';
import '../../features/detachment_group/presentation/detachment_group_edit_page.dart';
import '../../features/detachment_group/presentation/detachment_group_list_page.dart';
import '../../features/workshop/presentation/tabs/workshop_members_tab.dart';
import '../../features/workshop/presentation/tabs/workshop_stats_tab.dart';
import '../../features/workshop/presentation/tabs/workshop_team_tab.dart';
import '../../features/workshop/presentation/workshop_detail_shell.dart';
import '../../features/workshop/presentation/workshop_edit_page.dart';
import '../../features/workshop/presentation/workshop_list_page.dart';
import '../../features/tenant_feature/data/tenant_feature_providers.dart';
import '../../features/tenant_feature/domain/tenant_feature_models.dart';
import '../../features/tenant_feature/presentation/feature_disabled_page.dart';
import '../access/capability.dart';
import '../access/capability_guard.dart';
import '../env/build_mode.dart';
import '../motion/transitions.dart';
import '../startup/startup_destination.dart';
import '../startup/startup_providers.dart';

// -----------------------------------------------------------------------------
// Navigator hierarchy
//
// The app runs three levels of Navigator. Every route below belongs to exactly
// one of them, and which one it belongs to is what decides whether a page
// covers the floating bottom nav or lives underneath it.
//
//   root           Auth screens, and every page that must COVER the bottom
//                  nav — the create and edit forms.
//   branch         One per bottom-nav tab. Keeps each tab's own back stack
//                  alive while the user switches tabs.
//   detail shell   One per detail surface (a detachment, a workshop). Keeps
//                  the title and the tab bar in place while the tab body swaps.
//
// The rule that keeps this file correct:
//
//   A route may set `parentNavigatorKey` as an immediate child of a plain
//   GoRoute, but never as an immediate child of a ShellRoute. go_router
//   asserts that a shell's direct children stay on that shell's own navigator,
//   and the assert runs while GoRouter is being constructed — so breaking it
//   does not misplace a single page, it throws before the app renders its
//   first frame.
//
//   Full-screen forms therefore sit BESIDE a detail shell, never inside it.
// -----------------------------------------------------------------------------

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

// One navigator per bottom-nav branch.
final _homeKey = GlobalKey<NavigatorState>(debugLabel: 'branch-home');
final _detachmentKey =
    GlobalKey<NavigatorState>(debugLabel: 'branch-detachment');
final _workshopKey = GlobalKey<NavigatorState>(debugLabel: 'branch-workshop');
final _moreKey = GlobalKey<NavigatorState>(debugLabel: 'branch-more');

// One navigator per platform branch. A separate set from the tenant branch
// keys above, and not a reuse of them: the two shells are never mounted at the
// same time, but a GlobalKey shared between two route trees is the kind of
// thing that works until the day a redirect briefly overlaps them.
final _platformOverviewKey =
    GlobalKey<NavigatorState>(debugLabel: 'platform-overview');
final _platformTenantsKey =
    GlobalKey<NavigatorState>(debugLabel: 'platform-tenants');
final _platformOperationsKey =
    GlobalKey<NavigatorState>(debugLabel: 'platform-operations');
final _platformMoreKey = GlobalKey<NavigatorState>(debugLabel: 'platform-more');

// One navigator per detail shell. Naming these is not cosmetic: a ShellRoute
// without an explicit key mints an anonymous one, and then the rule above
// cannot be checked by reading the code.
final _detachmentDetailKey =
    GlobalKey<NavigatorState>(debugLabel: 'detachment-detail');
final _workshopDetailKey =
    GlobalKey<NavigatorState>(debugLabel: 'workshop-detail');

/// Every page in the app enters with the same shared-axis transition, so the
/// app has one movement vocabulary rather than a per-route grab bag.
CustomTransitionPage<T> _sharedAxisPage<T>({
  required LocalKey key,
  required Widget child,
}) =>
    CustomTransitionPage<T>(
      key: key,
      child: child,
      transitionsBuilder: (context, animation, secondary, page) =>
          SharedAxisPageTransition(
        animation: animation,
        secondaryAnimation: secondary,
        child: page,
      ),
    );

// -----------------------------------------------------------------------------
// Route guards
//
// Hiding a navigation row is not authorization. A restricted destination has
// to refuse a deep link, a restored navigation stack and a `context.go` from
// anywhere else in the app too — so every route below that leads to a gated
// surface carries one of these, resolving through the same
// `Capabilities.canIn` its in-screen controls use. That is the single-resolver
// rule from `CAPABILITIES.md` §1: when the guard and the controls decide
// separately, they drift.
//
// TODO(security): still a UX gate. The backend rejects the request whatever
// the client renders — see the contract at the top of `core/access/
// capability.dart`.
// -----------------------------------------------------------------------------

/// Refuses the route unless one of [anyOf] is held inside the detachment the
/// path names, sending the user to [fallback] instead.
///
/// The detachment id is read from the `:id` path parameter, which every
/// detachment-owned route in this file carries — the same id the screen behind
/// the route will check its own controls against.
GoRouterRedirect _needsIn(
  Ref ref,
  Set<String> anyOf, {
  String fallback = '/home',
}) =>
    (context, state) => requireCapability(
          ref,
          anyOf: anyOf,
          detachmentId: state.pathParameters['id'],
          fallback: fallback,
        );

/// Refuses the route unless [key] is held **somewhere** — globally, or inside
/// at least one detachment.
///
/// For a surface that spans detachments rather than living inside one. Asking
/// `_needs` (i.e. `canIn(null, key)`) would be wrong for a per-detachment key:
/// it is the organisation-wide question, and it would bounce a scoped
/// administrator who holds the key in their own detachment.
///
/// TODO(security): still a client-side redirect, like every guard in this file.
GoRouterRedirect _needsAnywhere(
  Ref ref,
  String key, {
  String fallback = '/home',
}) =>
    (context, state) {
      // Same reasoning as `requireCapability`: while the session is unknown
      // this decides nothing, because every cold start and every offline
      // relaunch passes through that state.
      if (ref.read(authGateProvider).isUnresolved) return null;
      return ref.read(capabilitiesProvider).canAnywhere(key) ? null : fallback;
    };

/// The same, for the organisation-level keys, which take no detachment.
GoRouterRedirect _needs(
  Ref ref,
  Set<String> anyOf, {
  String fallback = '/home',
}) =>
    (context, state) =>
        requireCapability(ref, anyOf: anyOf, fallback: fallback);

/// Pre-session screens, and the whole of the app that a signed-out session is
/// allowed to reach.
///
/// One const map rather than eight hand-written routes, because the auth gate
/// in `redirect` needs exactly this set of locations and a second, separately
/// maintained copy of it is how a redirect loop gets shipped: forget `/otp`
/// here and a signed-out user reaching the OTP step is bounced back to
/// `/login` forever. The routes and the public set are now the same list.
///
/// They live on the root navigator, so none of them ever shows the bottom nav.
const _publicPages = <String, Widget>{
  '/login': LoginPage(),
  '/signup': SignupPage(),
  '/mfa-setup': MfaSetupPage(),
  '/mfa-challenge': MfaChallengePage(),
  '/forgot': ForgotPasswordPage(),
  '/otp': OtpPage(),
  '/new-password': NewPasswordPage(),
  '/session-expired': SessionExpiredPage(),
  '/new-device': NewDevicePage(),
};

List<RouteBase> get _authRoutes => [
      for (final entry in _publicPages.entries)
        GoRoute(
          path: entry.key,
          pageBuilder: (context, state) =>
              _sharedAxisPage(key: state.pageKey, child: entry.value),
        ),
    ];

/// Tab 1 — the operational summary.
StatefulShellBranch _homeBranch(Ref ref) => StatefulShellBranch(
      navigatorKey: _homeKey,
      routes: [
        GoRoute(
          path: '/home',
          pageBuilder: (context, state) =>
              _sharedAxisPage(key: state.pageKey, child: const HomePage()),
        ),
      ],
    );

/// Tab 2 — the container hierarchy: detachment groups, then the detachments
/// inside one, then a detachment's own tabbed detail.
///
/// The branch has two top-level routes rather than one. `/detachment-groups` is
/// where the tab opens; `/detachment/:id/...` is where a detachment's own
/// surfaces live. A detachment id is unique across detachment groups, so its
/// detail routes do not repeat the detachment group in the path — but nothing
/// detachment-*owned* gets a top-level route, which is the rule
/// `DETACHMENT-SCOPING.md` §3 actually sets: there is no `/inventory` and no
/// `/schedule`.
StatefulShellBranch _detachmentBranch(Ref ref) => StatefulShellBranch(
      navigatorKey: _detachmentKey,
      routes: [
        GoRoute(
          path: '/detachment-groups',
          // The container hierarchy — detachment groups, and creating
          // detachments into them — is organisation-level work, and
          // `detachment.create` is the capability that makes it actionable (it
          // is what both the detachment group list and the detachment group
          // form already gate their own controls on). A session without it is
          // not refused its detachments; it is sent straight to them, which is
          // the only part of this subtree that was ever its own. Route-level,
          // so a deep link lands the same way.
          redirect: _needs(
            ref,
            const {Cap.detachmentCreate},
            fallback: '/detachment',
          ),
          pageBuilder: (context, state) => _sharedAxisPage(
            key: state.pageKey,
            child: const DetachmentGroupListPage(),
          ),
          routes: [
            // Full-screen forms go on the root navigator so they cover the
            // bottom nav — see the navigator rule at the top of this file.
            // Restated on each child rather than inherited from the parent
            // route: which of a matched chain's redirects run is a go_router
            // implementation detail, and a guard that silently stopped
            // running would be invisible until someone deep-linked past it.
            GoRoute(
              path: 'new',
              parentNavigatorKey: _rootKey,
              redirect: _needs(
                ref,
                const {Cap.detachmentCreate},
                fallback: '/detachment',
              ),
              pageBuilder: (context, state) => _sharedAxisPage(
                key: state.pageKey,
                child: const DetachmentGroupEditPage(id: null),
              ),
            ),
            GoRoute(
              path: ':groupId/edit',
              parentNavigatorKey: _rootKey,
              redirect: _needs(
                ref,
                const {Cap.detachmentCreate},
                fallback: '/detachment',
              ),
              pageBuilder: (context, state) => _sharedAxisPage(
                key: state.pageKey,
                child: DetachmentGroupEditPage(
                    id: state.pathParameters['groupId']),
              ),
            ),
            // One detachment group's detachments.
            GoRoute(
              path: ':groupId',
              redirect: _needs(
                ref,
                const {Cap.detachmentCreate},
                fallback: '/detachment',
              ),
              pageBuilder: (context, state) => _sharedAxisPage(
                key: state.pageKey,
                child: DetachmentListPage(
                  detachmentGroupId: state.pathParameters['groupId'],
                ),
              ),
              routes: [
                // Creating a detachment happens *inside* a detachment group, so
                // the route carries the detachment group it is created into.
                GoRoute(
                  path: 'detachment/new',
                  parentNavigatorKey: _rootKey,
                  redirect: _needs(
                    ref,
                    const {Cap.detachmentCreate},
                    fallback: '/detachment',
                  ),
                  pageBuilder: (context, state) => _sharedAxisPage(
                    key: state.pageKey,
                    child: DetachmentEditPage(
                      id: null,
                      detachmentGroupId: state.pathParameters['groupId'],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/detachment',
          pageBuilder: (context, state) => _sharedAxisPage(
            key: state.pageKey,
            child: const DetachmentListPage(),
          ),
          routes: [
            GoRoute(
              path: ':id/edit',
              parentNavigatorKey: _rootKey,
              // The form saves with `detachment.edit` and archives with
              // `detachment.archive`; either one is a reason to open it.
              redirect: _needsIn(
                ref,
                const {Cap.detachmentEdit, Cap.detachmentArchive},
              ),
              pageBuilder: (context, state) => _sharedAxisPage(
                key: state.pageKey,
                child: DetachmentEditPage(id: state.pathParameters['id']),
              ),
            ),

            // The member form, for the same reason: it is a full-screen page
            // with its own app bar, so it covers the bottom nav and stays a
            // sibling of the detail shell rather than a child of it.
            GoRoute(
              path: ':id/member/new',
              parentNavigatorKey: _rootKey,
              redirect: _needsIn(ref, const {Cap.memberInvite}),
              pageBuilder: (context, state) => _sharedAxisPage(
                key: state.pageKey,
                child: DetachmentMemberEditPage(
                  detachmentId: state.pathParameters['id']!,
                  memberId: null,
                ),
              ),
            ),
            GoRoute(
              path: ':id/member/:memberId/edit',
              parentNavigatorKey: _rootKey,
              redirect: _needsIn(ref, const {Cap.memberEdit}),
              pageBuilder: (context, state) => _sharedAxisPage(
                key: state.pageKey,
                child: DetachmentMemberEditPage(
                  detachmentId: state.pathParameters['id']!,
                  memberId: state.pathParameters['memberId'],
                ),
              ),
            ),

            // The member's attendance history — opened from the roster card.
            // A full-screen page with its own app bar, so a sibling of the
            // detail shell rather than a child of it.
            GoRoute(
              path: ':id/member/:memberId/status',
              parentNavigatorKey: _rootKey,
              redirect: _needsIn(ref, const {Cap.memberView}),
              pageBuilder: (context, state) => _sharedAxisPage(
                key: state.pageKey,
                child: DetachmentMemberStatusPage(
                  detachmentId: state.pathParameters['id']!,
                  memberId: state.pathParameters['memberId']!,
                ),
              ),
            ),

            // Stock items are detachment-owned, so their form extends the
            // detachment path rather than taking one of its own.
            GoRoute(
              path: ':id/storage/new',
              parentNavigatorKey: _rootKey,
              redirect: _needsIn(ref, const {Cap.inventoryItemManage}),
              pageBuilder: (context, state) => _sharedAxisPage(
                key: state.pageKey,
                child: InventoryItemEditPage(
                  detachmentId: state.pathParameters['id']!,
                  itemId: null,
                ),
              ),
            ),
            GoRoute(
              path: ':id/storage/:itemId/edit',
              parentNavigatorKey: _rootKey,
              redirect: _needsIn(ref, const {Cap.inventoryItemManage}),
              pageBuilder: (context, state) => _sharedAxisPage(
                key: state.pageKey,
                child: InventoryItemEditPage(
                  detachmentId: state.pathParameters['id']!,
                  itemId: state.pathParameters['itemId'],
                ),
              ),
            ),

            // The report composer: pick what goes in the file, preview it,
            // export it.
            GoRoute(
              path: ':id/report',
              parentNavigatorKey: _rootKey,
              // A report is statistics in a file, so it rests on the same key
              // the statistics tab does. There is no separate export
              // capability in the domain yet — when one exists this is the
              // single line that gains it, and the preview/export controls
              // inside must gain it independently rather than inherit it.
              redirect: _needsIn(ref, const {Cap.statsView}),
              pageBuilder: (context, state) => _sharedAxisPage(
                key: state.pageKey,
                child: ReportExportPage(
                  detachmentId: state.pathParameters['id']!,
                ),
              ),
              routes: [
                // The spec travels in `extra` rather than the query string:
                // it is a set of eight flags plus two enums, and a URL that
                // encodes it is neither shareable nor readable.
                GoRoute(
                  path: 'preview',
                  parentNavigatorKey: _rootKey,
                  pageBuilder: (context, state) => _sharedAxisPage(
                    key: state.pageKey,
                    child: ReportPreviewPage(
                      detachmentId: state.pathParameters['id']!,
                      spec: state.extra as ReportSpec? ?? ReportSpec.initial,
                    ),
                  ),
                ),
              ],
            ),

            // One detachment, four tabs. The shell holds the title and the
            // tab bar; only `child` swaps as the tab changes.
            ShellRoute(
              navigatorKey: _detachmentDetailKey,
              pageBuilder: (context, state, child) => _sharedAxisPage(
                key: state.pageKey,
                child: DetachmentDetailShell(
                  detachmentId: state.pathParameters['id']!,
                  location: state.uri.toString(),
                  child: child,
                ),
              ),
              routes: [
                // `detachment.view` is the anchor of the scoping model and
                // any scoped grant implies it (`CAPABILITIES.md` §4/Q3), so
                // it is what decides whether this detachment's surfaces open
                // at all. The schedule and the store are gated on nothing
                // finer because visibility there follows membership —
                // `shift.view` and `inventory.view` were dropped for gating
                // nothing — while their controls inside are gated one at a
                // time. The roster wants `member.view`, and the statistics
                // tab keeps its own designed denied state rather than
                // bouncing the user out of one tab of a shell.
                GoRoute(
                  path: ':id/team',
                  redirect: _needsIn(ref, const {Cap.memberView}),
                  builder: (context, state) => DetachmentTeamTab(
                    detachmentId: state.pathParameters['id']!,
                  ),
                ),
                GoRoute(
                  path: ':id/shifts',
                  redirect: _needsIn(ref, const {Cap.detachmentView}),
                  builder: (context, state) => DetachmentShiftsTab(
                    detachmentId: state.pathParameters['id']!,
                  ),
                ),
                GoRoute(
                  path: ':id/storage',
                  redirect: _needsIn(ref, const {Cap.detachmentView}),
                  builder: (context, state) => DetachmentStorageTab(
                    detachmentId: state.pathParameters['id']!,
                  ),
                ),
                GoRoute(
                  path: ':id/stats',
                  redirect: _needsIn(ref, const {Cap.detachmentView}),
                  builder: (context, state) => DetachmentStatsTab(
                    detachmentId: state.pathParameters['id']!,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );

/// Tab 3 — workshops. Deliberately the same shape as the detachment branch;
/// the two detail surfaces must feel identical.
StatefulShellBranch _workshopBranch(Ref ref) => StatefulShellBranch(
      navigatorKey: _workshopKey,
      routes: [
        GoRoute(
          path: '/workshop',
          pageBuilder: (context, state) => _sharedAxisPage(
            key: state.pageKey,
            child: const WorkshopListPage(),
          ),
          routes: [
            GoRoute(
              path: 'new',
              parentNavigatorKey: _rootKey,
              redirect: _needs(ref, const {Cap.workshopCreate},
                  fallback: '/workshop'),
              pageBuilder: (context, state) => _sharedAxisPage(
                key: state.pageKey,
                child: const WorkshopEditPage(id: null),
              ),
            ),
            GoRoute(
              path: ':id/edit',
              parentNavigatorKey: _rootKey,
              redirect:
                  _needs(ref, const {Cap.workshopEdit}, fallback: '/workshop'),
              pageBuilder: (context, state) => _sharedAxisPage(
                key: state.pageKey,
                child: WorkshopEditPage(id: state.pathParameters['id']),
              ),
            ),
            ShellRoute(
              navigatorKey: _workshopDetailKey,
              pageBuilder: (context, state, child) => _sharedAxisPage(
                key: state.pageKey,
                child: WorkshopDetailShell(
                  workshopId: state.pathParameters['id']!,
                  location: state.uri.toString(),
                  child: child,
                ),
              ),
              routes: [
                GoRoute(
                  path: ':id/team',
                  builder: (context, state) => WorkshopTeamTab(
                    workshopId: state.pathParameters['id']!,
                  ),
                ),
                GoRoute(
                  path: ':id/members',
                  builder: (context, state) => WorkshopMembersTab(
                    workshopId: state.pathParameters['id']!,
                  ),
                ),
                GoRoute(
                  path: ':id/stats',
                  builder: (context, state) => WorkshopStatsTab(
                    workshopId: state.pathParameters['id']!,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );

/// Tab 4 — settings and the account pages behind it. These stay inside the
/// branch, so the bottom nav remains visible while the user drills in.
StatefulShellBranch _moreBranch(Ref ref) => StatefulShellBranch(
      navigatorKey: _moreKey,
      routes: [
        GoRoute(
          path: '/more',
          pageBuilder: (context, state) =>
              _sharedAxisPage(key: state.pageKey, child: const SettingsPage()),
          routes: [
            GoRoute(
              path: 'themes',
              pageBuilder: (context, state) => _sharedAxisPage(
                key: state.pageKey,
                child: const ThemesAndPerformancePage(),
              ),
            ),
            // Themes and performance are one screen now. The old path stays
            // as a redirect rather than a second page, so a deep link or a
            // restored navigation stack still lands somewhere real without
            // there being two screens that both claim these controls.
            GoRoute(
              path: 'performance',
              redirect: (context, state) => '/more/themes',
            ),
            GoRoute(
              path: 'eye-protect',
              redirect: (context, state) => '/more/themes',
            ),
            GoRoute(
              path: 'sync',
              pageBuilder: (context, state) => _sharedAxisPage(
                key: state.pageKey,
                child: const SyncPage(),
              ),
            ),
            GoRoute(
              path: 'profile',
              pageBuilder: (context, state) => _sharedAxisPage(
                key: state.pageKey,
                child: const ProfilePage(),
              ),
            ),
            GoRoute(
              path: 'security',
              pageBuilder: (context, state) => _sharedAxisPage(
                key: state.pageKey,
                child: const SecurityPage(),
              ),
            ),
            GoRoute(
              path: 'notifications',
              pageBuilder: (context, state) => _sharedAxisPage(
                key: state.pageKey,
                child: const NotificationsPage(),
              ),
            ),
            // About & support. Ungated on purpose, unlike the organisation
            // row below it: what the app is, which build is installed and how
            // to reach support are things every administrator needs, and a
            // session that could not read its own version number would be
            // unable to report a bug about it.
            GoRoute(
              path: 'about',
              pageBuilder: (context, state) => _sharedAxisPage(
                key: state.pageKey,
                child: const AboutPage(),
              ),
            ),
            // Point 15 — Organization and Plan. Read-only context about the
            // customer this account belongs to, open to both tenant roles:
            // neither screen carries an organisation-wide *figure* (what
            // `org.edit` gated here before), and the one place that does —
            // Plan's usage counts — is withheld by the read itself for a
            // session without that key. The Super Admin never reaches either:
            // the surface redirect turns every `/more` location around.
            GoRoute(
              path: 'organization',
              pageBuilder: (context, state) => _sharedAxisPage(
                key: state.pageKey,
                child: const OrganizationPage(),
              ),
            ),
            GoRoute(
              path: 'plan',
              pageBuilder: (context, state) => _sharedAxisPage(
                key: state.pageKey,
                child: const PlanPage(),
              ),
            ),
            GoRoute(
              path: 'pricing',
              pageBuilder: (context, state) => _sharedAxisPage(
                key: state.pageKey,
                child: const PricingPage(),
              ),
            ),
            GoRoute(
              path: 'simple-admins',
              redirect: _needs(ref, const {Cap.adminManage}),
              pageBuilder: (context, state) => _sharedAxisPage(
                key: state.pageKey,
                child: const SimpleAdminManagementPage(),
              ),
              routes: [
                GoRoute(
                  path: 'invite',
                  redirect: _needs(ref, const {Cap.adminManage}),
                  pageBuilder: (context, state) => _sharedAxisPage(
                    key: state.pageKey,
                    child: const SimpleAdminInvitePage(),
                  ),
                ),
                GoRoute(
                  path: ':accountId/capabilities',
                  redirect: _needs(ref, const {Cap.adminManage}),
                  pageBuilder: (context, state) => _sharedAxisPage(
                    key: state.pageKey,
                    child: SimpleAdminCapabilitiesPage(
                      accountId: state.pathParameters['accountId']!,
                    ),
                  ),
                ),
              ],
            ),
            // The pre-Point-15 organisation path. A redirect, not a second
            // screen, so an old deep link or a restored stack still lands on
            // the one Organization page.
            GoRoute(
              path: 'org',
              redirect: (context, state) => OrganizationPage.routePath,
            ),
          ],
        ),
      ],
    );

// -----------------------------------------------------------------------------
// The Super Admin platform surface (`/platform`)
//
// A second `StatefulShellRoute`, entirely beside the tenant one. The two never
// coexist: the startup classifier resolves a session to exactly one product
// surface, and the redirect below turns the other one around — so building the
// platform tree costs a tenant session nothing, and vice versa.
//
// Branch order is `PlatformArea`'s declaration order, which is also the order
// the navigation renders. That is the whole reason `PlatformArea.branchIndex`
// exists: the shell's selected index, the bar's selected row and the branch a
// `goBranch` moves to are the same number, read from one enum.
//
// Every nested page under `/platform/more` stays INSIDE its branch, exactly
// like the tenant `/more` sub-pages, so the platform navigation remains visible
// while the operator drills into their own settings and the branch's back stack
// survives a hop to another area and back.
// -----------------------------------------------------------------------------

/// One branch, given the area it serves and the pages it holds.
StatefulShellBranch _platformBranch(
  GlobalKey<NavigatorState> key,
  PlatformArea area,
  Widget root, {
  List<RouteBase> children = const [],
  List<RouteBase> additionalRoutes = const [],
}) =>
    StatefulShellBranch(
      navigatorKey: key,
      routes: [
        GoRoute(
          path: area.route,
          pageBuilder: (context, state) =>
              _sharedAxisPage(key: state.pageKey, child: root),
          routes: children,
        ),
        ...additionalRoutes,
      ],
    );

/// Operations modules keep their established public paths while living in the
/// Operations branch. They are sibling routes here, not aliases and not a
/// second top-level platform destination.
List<RouteBase> get _platformOperationsRoutes => [
      GoRoute(
        path: PlatformOperationsRoutes.audit,
        pageBuilder: (context, state) => _sharedAxisPage(
          key: state.pageKey,
          child: PlatformAuditPageWidget(
            initialQuery: state.extra is PlatformAuditQuery
                ? state.extra! as PlatformAuditQuery
                : null,
          ),
        ),
      ),
      GoRoute(
        path: PlatformOperationsRoutes.access,
        pageBuilder: (context, state) => _sharedAxisPage(
          key: state.pageKey,
          child: const PlatformBreakGlassPage(),
        ),
        routes: [
          GoRoute(
            path: 'request',
            pageBuilder: (context, state) => _sharedAxisPage(
              key: state.pageKey,
              child: const PlatformBreakGlassRequestPage(),
            ),
          ),
        ],
      ),
      GoRoute(
        path: PlatformOperationsRoutes.health,
        pageBuilder: (context, state) => _sharedAxisPage(
          key: state.pageKey,
          child: const PlatformHealthPage(),
        ),
      ),
      // Customer Demo management — the only Demo policy surface in the app.
      GoRoute(
        path: PlatformOperationsRoutes.demo,
        pageBuilder: (context, state) => _sharedAxisPage(
          key: state.pageKey,
          child: const PlatformDemoPage(),
        ),
      ),
      GoRoute(
        path: PlatformOperationsRoutes.commerce,
        pageBuilder: (context, state) => _sharedAxisPage(
          key: state.pageKey,
          child: const PlatformCommercePage(),
        ),
        routes: [
          GoRoute(
            path: 'offer',
            pageBuilder: (context, state) => _sharedAxisPage(
              key: state.pageKey,
              child: const PlatformOfferEditPage(),
            ),
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (context, state) => _sharedAxisPage(
                  key: state.pageKey,
                  child: PlatformOfferEditPage(
                    offerId: state.pathParameters['id'],
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'coupon',
            pageBuilder: (context, state) => _sharedAxisPage(
              key: state.pageKey,
              child: const PlatformCouponEditPage(),
            ),
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (context, state) => _sharedAxisPage(
                  key: state.pageKey,
                  child: PlatformCouponEditPage(
                    couponId: state.pathParameters['id'],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: PlatformOperationsRoutes.security,
        pageBuilder: (context, state) => _sharedAxisPage(
          key: state.pageKey,
          child: const PlatformSecurityPage(),
        ),
      ),
      // Point 13 — the closed report catalogue and its child report pages.
      // A child route, not a tab: filters differ per report and the back
      // gesture returns to the catalogue (§K.1).
      GoRoute(
        path: PlatformOperationsRoutes.reports,
        pageBuilder: (context, state) => _sharedAxisPage(
          key: state.pageKey,
          child: const PlatformReportsCataloguePage(),
        ),
        routes: [
          GoRoute(
            path: ':${PlatformOperationsRoutes.reportTypeParam}',
            pageBuilder: (context, state) => _sharedAxisPage(
              key: state.pageKey,
              child: PlatformReportPage(
                reportType: state.pathParameters[
                        PlatformOperationsRoutes.reportTypeParam] ??
                    '',
              ),
            ),
          ),
        ],
      ),
    ];

/// The Super Admin's own account and application settings.
///
/// An **allowlist** (`§26`, `§29`): five destinations, each one checked to read
/// nothing but the session, the app's preferences or a constant. The tenant
/// Settings hub is deliberately not rendered here with rows hidden — it builds
/// its summaries from the sync outbox and the capability grant, and rendering
/// it would initialise tenant machinery for the one session that must never
/// touch any.
///
/// `ProfilePage` is handed this branch's own Security location: its default
/// points at `/more/security`, which a platform session would be bounced off,
/// and a row that navigates nowhere is a dead control however good it looks.
List<RouteBase> get _platformMoreRoutes => [
      GoRoute(
        path: 'profile',
        pageBuilder: (context, state) => _sharedAxisPage(
          key: state.pageKey,
          child: ProfilePage(
            securityRoute: '${PlatformArea.more.route}/security',
          ),
        ),
      ),
      GoRoute(
        path: 'security',
        pageBuilder: (context, state) =>
            _sharedAxisPage(key: state.pageKey, child: const SecurityPage()),
      ),
      GoRoute(
        path: 'themes',
        pageBuilder: (context, state) => _sharedAxisPage(
          key: state.pageKey,
          child: const ThemesAndPerformancePage(),
        ),
      ),
      GoRoute(
        path: 'eye-protect',
        redirect: (context, state) => '${PlatformArea.more.route}/themes',
      ),
      GoRoute(
        path: 'about',
        pageBuilder: (context, state) =>
            _sharedAxisPage(key: state.pageKey, child: const AboutPage()),
      ),
    ];

/// The Point 6 subscriber pages, nested **inside** the Tenants branch.
///
/// Nested rather than root-level, exactly like `/platform/more/*`: the shell's
/// navigation stays visible while an operator drills into a customer, and the
/// branch's back stack survives a hop to another area and back. A root-level
/// route would have covered the bar and made "return to the list" a browser
/// gesture rather than a visible one.
///
/// `new` is registered **before** `:tenantId` so the literal segment is
/// matched as itself rather than resolved as a tenant whose id is "new" — the
/// ordering `_legacyDetachmentGroupPaths` already had to get right, restated
/// here because the failure is silent when it is wrong.
List<RouteBase> get _platformTenantRoutes => [
      GoRoute(
        path: SaasTenantRoutes.createSegment,
        pageBuilder: (context, state) => _sharedAxisPage(
          key: state.pageKey,
          child: const SaasTenantCreatePage(),
        ),
      ),
      GoRoute(
        path: SaasTenantRoutes.detailSegment,
        pageBuilder: (context, state) => _sharedAxisPage(
          key: state.pageKey,
          child: SaasTenantDetailPage(
            tenantId:
                state.pathParameters[SaasTenantRoutes.tenantIdParam] ?? '',
          ),
        ),
        routes: [
          GoRoute(
            path: SaasTenantRoutes.subscriptionSegment,
            pageBuilder: (context, state) => _sharedAxisPage(
              key: state.pageKey,
              child: SaasTenantSubscriptionPage(
                tenantId:
                    state.pathParameters[SaasTenantRoutes.tenantIdParam] ?? '',
              ),
            ),
          ),
          GoRoute(
            path: SaasTenantRoutes.limitsSegment,
            pageBuilder: (context, state) => _sharedAxisPage(
              key: state.pageKey,
              child: SaasTenantLimitsPage(
                tenantId:
                    state.pathParameters[SaasTenantRoutes.tenantIdParam] ?? '',
              ),
            ),
          ),
          GoRoute(
            path: SaasTenantRoutes.featuresSegment,
            pageBuilder: (context, state) => _sharedAxisPage(
              key: state.pageKey,
              child: SaasTenantFeaturesPage(
                tenantId:
                    state.pathParameters[SaasTenantRoutes.tenantIdParam] ?? '',
              ),
            ),
          ),
          GoRoute(
            path: SaasTenantRoutes.mainAdminSegment,
            pageBuilder: (context, state) => _sharedAxisPage(
              key: state.pageKey,
              child: PlatformMainAdminPage(
                tenantId:
                    state.pathParameters[SaasTenantRoutes.tenantIdParam] ?? '',
              ),
            ),
            routes: [
              GoRoute(
                path: SaasTenantRoutes.mainAdminReplaceSegment,
                pageBuilder: (context, state) => _sharedAxisPage(
                  key: state.pageKey,
                  child: PlatformMainAdminReplacePage(
                    tenantId:
                        state.pathParameters[SaasTenantRoutes.tenantIdParam] ??
                            '',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ];

RouteBase get _platformShellRoute => StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          PlatformShell(navigationShell: navigationShell),
      branches: [
        _platformBranch(
          _platformOverviewKey,
          PlatformArea.overview,
          const PlatformOverviewPage(),
        ),
        _platformBranch(
          _platformTenantsKey,
          PlatformArea.tenants,
          const PlatformTenantsPage(),
          children: _platformTenantRoutes,
        ),
        _platformBranch(
          _platformOperationsKey,
          PlatformArea.operations,
          const PlatformOperationsPage(),
          additionalRoutes: _platformOperationsRoutes,
        ),
        _platformBranch(
          _platformMoreKey,
          PlatformArea.more,
          const PlatformMorePage(),
          children: _platformMoreRoutes,
        ),
      ],
    );

/// The pre-rename `/tenant` locations, each rewritten onto its
/// `/detachment-groups` equivalent.
///
/// One list rather than five hand-written routes, for the same reason
/// `_publicPages` is one map: a redirect table that has to be read against
/// the canonical tree is easier to keep honest when it is literally a table.
/// Order is preserved, and `/tenant/new` precedes `/tenant/:groupId` so the
/// literal segment is matched before the parameter that would swallow it.
const _legacyDetachmentGroupPaths = <String, String>{
  '/tenant': '/detachment-groups',
  '/tenant/new': '/detachment-groups/new',
  '/tenant/:groupId': '/detachment-groups/:groupId',
  '/tenant/:groupId/edit': '/detachment-groups/:groupId/edit',
  '/tenant/:groupId/detachment/new':
      '/detachment-groups/:groupId/detachment/new',
};

List<RouteBase> get _legacyDetachmentGroupRedirects => [
      for (final entry in _legacyDetachmentGroupPaths.entries)
        GoRoute(
          path: entry.key,
          redirect: (context, state) => entry.value.replaceFirst(
            ':groupId',
            state.pathParameters['groupId'] ?? '',
          ),
        ),
    ];

/// Destinations whose locations exist **only** as a startup outcome.
///
/// Every one of them is a place the classifier sends a session that must not
/// be inside the tenant product. Nobody navigates there on purpose, and a
/// session the classifier did *not* send there is bounced out — which is what
/// stops a tenant admin sightseeing on `/platform`, or a healthy account
/// sitting on `/account-revoked` because a link said so.
///
/// Derived from [StartupDestination] rather than typed out, so a destination
/// added to the enum cannot be forgotten here. `tenantSurface` has no location
/// and drops out; `/login` and `/mfa-challenge` are excluded because they are
/// public auth pages that a signed-in session may also legitimately open (the
/// Security screen pushes `/mfa-setup` and `/forgot` beside them).
///
/// It holds the **destinations**, not their location strings, because
/// `platformSurface` now owns a whole subtree: `/platform/tenants` has to be
/// refused a tenant admin exactly as `/platform` is, and
/// `StartupDestination.claims` is the one place that question is answered.
final List<StartupDestination> _startupOnlyDestinations = [
  for (final destination in StartupDestination.values)
    if (destination.location case final location?)
      if (!_publicPages.containsKey(location)) destination,
];

/// Locations a Customer Demo session may not open.
///
/// The demo is the real application, so the refusals are listed once, here,
/// rather than as an `if (demo)` inside each screen. Two kinds of thing are on
/// the list and nothing else:
///
///  - **real account security** — the password, MFA and device/session
///    screens. A trial is not an account, and offering these would be
///    offering to change something that does not exist;
///  - **things that would have to reach production** — the organisation
///    record and its plan, Simple Admin management (also refused by the
///    missing `admin.manage` key), and everything that speaks to the sync
///    outbox. A demo must not touch the device's real sync queue, and it
///    would have nothing honest to show there.
///
/// Every operational module — home, detachments, team, shifts, inventory,
/// workshops, statistics, notifications, appearance — is deliberately absent
/// from this list: demonstrating those is the whole point.
const _demoBlockedLocations = <String>{
  '/more/security',
  '/more/sessions',
  '/more/sync',
  '/more/organization',
  '/more/plan',
  '/more/simple-admins',
  '/needs-review',
};

// `/more/pricing` is intentionally absent: a Customer Demo may explore the
// same read-only prices and coupon preview as a tenant session.

bool _isDemoBlocked(String here) => _demoBlockedLocations.any(
      (blocked) => here == blocked || here.startsWith('$blocked/'),
    );

/// Whether [here] belongs to some destination only the classifier may hand out.
bool _isStartupOnly(String here) =>
    _startupOnlyDestinations.any((destination) => destination.claims(here));

/// The auth pages a **signed-in** platform session may still open.
///
/// MFA enrolment and the reset-by-email flow, both reached from the Security
/// screen the platform surface shares. A tenant session already reaches them
/// (its destination has no location, so it goes wherever it asks); without
/// this the platform surface would show the same two rows and bounce off both,
/// which is the dead control `§34` forbids.
///
/// `/login` is deliberately not in the set: a signed-in account has no business
/// on the sign-in form, and the one route out of a session is the sign-out that
/// clears it. Nor is `/session-expired` or `/new-device` — those are outcomes,
/// not destinations.
const _signedInAuthPages = <String>{
  '/mfa-setup',
  '/forgot',
  '/otp',
  '/new-password',
};

final appRouterProvider = Provider<GoRouter>((ref) {
  // The startup decision, handed to GoRouter as a listenable rather than read
  // through `ref.watch`: watching would rebuild the whole GoRouter on every
  // change and throw away the navigation stack with it. This way the router is
  // built once and a change only re-runs `redirect`.
  //
  // **This one notifier replaced three.** Point 2's router held the upgrade
  // gate, the auth gate and the account's role separately and combined them
  // inside `redirect` with a chain of `if`s. All three are now inputs to
  // `startupDestinationProvider`, which is a pure function of them
  // (`core/startup/startup_destination.dart`) — so the router listens to the
  // *answer* instead of to the ingredients, and there is exactly one place
  // where a new session state changes where the app goes.
  final startup =
      ValueNotifier<StartupDestination>(ref.read(startupDestinationProvider));
  ref.listen<StartupDestination>(
    startupDestinationProvider,
    (_, next) => startup.value = next,
  );
  ref.onDispose(startup.dispose);

  // The capability gate, held the same way and for the third variant of the
  // same reason: a grant can narrow while the app is open — the server
  // re-issues the session, an admin revokes a key — and a screen the session
  // has stopped being allowed must not simply stay on screen because nothing
  // asked again. `Capabilities` has value equality, so a session rebuilt with
  // identical grants notifies nothing and no navigation is disturbed.
  //
  // The update is deferred by a microtask, unlike the two above. Those are
  // driven by an async read landing; this one is read by widgets during build
  // — `MainShell` asks it how many destinations to draw — so assigning it
  // synchronously would mark the Router dirty in the middle of the build that
  // just caused it, which Flutter refuses. A microtask runs the moment that
  // build returns.
  var disposed = false;
  final grants = ValueNotifier<Capabilities>(ref.read(capabilitiesProvider));
  ref.listen<Capabilities>(capabilitiesProvider, (_, next) {
    Future.microtask(() {
      if (!disposed) grants.value = next;
    });
  });
  ref.onDispose(() {
    disposed = true;
    grants.dispose();
  });

  // Feature availability changes independently from both session surface and
  // user grant. A platform toggle increments this token, which makes GoRouter
  // re-run the central module guard without rebuilding the router or losing
  // branch stacks.
  final features = ValueNotifier<int>(ref.read(tenantFeatureRevisionProvider));
  ref.listen<int>(tenantFeatureRevisionProvider, (_, next) {
    Future.microtask(() {
      if (!disposed) features.value = next;
    });
  });
  ref.onDispose(features.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    // The neutral loading surface, not `/home`.
    //
    // The session read is asynchronous, so with `/home` as the entry the app
    // built the tenant dashboard — app bar, bottom nav, repository reads —
    // for every cold start and then redirected whoever should not have seen
    // it. Starting on `StartupPage` means the first frame belongs to nobody:
    // the classifier answers `restoring` until the read lands, and the
    // redirect below moves the app the instant it does.
    initialLocation: StartupPage.location,
    debugLogDiagnostics: false,
    // The startup decision, and the capability grant. Two listenables because
    // they change for different reasons and at different times: the first is
    // "which surface does this session belong to", the second is "what may it
    // do inside the one it got", and the route guards read them separately.
    refreshListenable: Listenable.merge([startup, grants, features]),
    // The one place the app can be shut, and now the one place it is
    // *directed*. `redirect` runs on every navigation — a tab, a deep link, a
    // `context.go` from anywhere — so there is no alternate path into the app
    // that could skip what follows.
    //
    // It computes nothing. `startup.value` is the whole decision, in the
    // documented priority order of `resolveStartup`; everything below is the
    // mapping from that answer to a location, plus the two rules about which
    // *other* locations each answer tolerates.
    //
    // TODO(security): a UX gate, like every access decision in this client.
    // The backend rejects the request whatever the router chose to render.
    redirect: (context, state) {
      final destination = startup.value;
      final here = state.matchedLocation;
      final target = destination.location;

      if (target == null) {
        // The tenant application, or a session nothing can be concluded
        // about: go wherever it asked, and let the per-route capability
        // guards answer for themselves. The one thing refused is a
        // startup-only location — the whole `/platform` subtree, `/startup`,
        // and every blocked-state screen — which neither has any business on.
        if (_isStartupOnly(here)) return '/home';

        // A Customer Demo trial runs inside the tenant application, so it
        // passes through everything above — and is refused the short list of
        // locations that belong to a real account or would have to reach
        // production. Deep links included.
        if (ref.read(isCustomerDemoSessionProvider) && _isDemoBlocked(here)) {
          return '/more';
        }

        // Product availability precedes route/action capability once the
        // session is authenticated and tenant-scoped. One typed route-family
        // mapping protects navigation, restored stacks and direct deep links.
        for (final feature in tenantFeaturesForLocation(here)) {
          if (!ref.read(tenantFeatureAvailableProvider(feature))) {
            return FeatureDisabledPage.location(feature);
          }
        }
        return null;
      }

      // The destination's own territory. For every outcome but one that is a
      // single page; for the platform surface it is the four-branch shell and
      // everything nested inside it, so a Super Admin moving between
      // `/platform`, `/platform/tenants` and `/platform/more/security` is
      // never redirected mid-navigation.
      if (destination.claims(here)) return null;

      // A signed-in platform session may still finish an authentication
      // errand it started from its own Security screen. See
      // `_signedInAuthPages`.
      if (destination == StartupDestination.platformSurface &&
          _signedInAuthPages.contains(here)) {
        return null;
      }

      // Signed out is the one answer with a family of acceptable locations
      // rather than a single one: the login form, but also password reset,
      // OTP, the new-password step and the new-device confirmation. Bouncing
      // those back to `/login` would make the reset flow impossible to
      // complete — the failure `_publicPages` was extracted to prevent.
      if (destination == StartupDestination.signedOut &&
          _publicPages.containsKey(here)) {
        return null;
      }

      // Everything else has exactly one location, including the platform
      // surface: unlike a tenant session it is not allowed to wander onto the
      // public auth pages, because it has no link to any of them and letting
      // it would blur the one boundary this file exists to hold.
      return target;
    },
    routes: [
      // Root navigator, so it covers the bottom nav and every other surface.
      GoRoute(
        path: UpgradeRequiredPage.location,
        pageBuilder: (context, state) => _sharedAxisPage(
          key: state.pageKey,
          child: const UpgradeRequiredPage(),
        ),
      ),
      // The startup surface, and the app's `initialLocation`. Root navigator,
      // like every other pre-surface screen: it must not build the tenant
      // shell, which is the whole reason it exists.
      GoRoute(
        path: StartupPage.location,
        pageBuilder: (context, state) =>
            _sharedAxisPage(key: state.pageKey, child: const StartupPage()),
      ),
      GoRoute(
        path: FeatureDisabledPage.routePath,
        pageBuilder: (context, state) => _sharedAxisPage(
          key: state.pageKey,
          child: FeatureDisabledPage(
            feature: TenantFeatureKey.parse(
              state.uri.queryParameters['feature'],
            ),
          ),
        ),
      ),
      // Every session-state screen the classifier can reach, from the one
      // const map that defines them. Root navigator, for the same reason: a
      // session that landed on any of these must not have the tenant shell —
      // and therefore its providers — built underneath it (`§32`, `§33`).
      for (final entry in startupStatusPages.entries)
        GoRoute(
          path: entry.key,
          pageBuilder: (context, state) =>
              _sharedAxisPage(key: state.pageKey, child: entry.value),
        ),
      // DEVELOPMENT ONLY — the session-state inspector. Registered only when
      // `demoAccountsAllowed`, so in a shipping artefact the route does not
      // exist at all and the page behind it is tree-shaken; a deep link to it
      // there is an ordinary unknown route.
      if (demoAccountsAllowed)
        GoRoute(
          path: DevSessionStatesPage.location,
          pageBuilder: (context, state) => _sharedAxisPage(
            key: state.pageKey,
            child: const DevSessionStatesPage(),
          ),
        ),
      // The Super Admin platform surface. Its own shell, its own branches and
      // its own navigators — see `_platformShellRoute` above and
      // `features/platform/presentation/platform_shell.dart` for why it is not
      // the tenant shell with different tabs.
      _platformShellRoute,
      // A substantial decision surface that must cover the bottom nav. Auto
      // Sync must never push this route; Manual Sync, a future review list,
      // and direct feature flows may open it with typed route arguments.
      GoRoute(
        path: ConflictResolutionPage.routePath,
        pageBuilder: (context, state) {
          final args = state.extra;
          return _sharedAxisPage(
            key: state.pageKey,
            // Entered without its typed arguments — a restored deep link, a
            // relaunch — the route rebuilds the conflict from the stored
            // review metadata rather than dead-ending. See
            // `ConflictResolutionRoute`.
            child: ConflictResolutionRoute(
              conflictId: state.pathParameters['conflictId'],
              args: args is ConflictResolutionRouteArgs ? args : null,
            ),
          );
        },
      ),
      // The Notifications Center. A root route beside the Needs Review inbox
      // and for the same reason: a full surface the user opens deliberately,
      // which therefore covers the bottom nav. Reached from the bell in the
      // dashboard's app bar — the app's single entry point into it.
      GoRoute(
        path: NotificationsCenterPage.routePath,
        pageBuilder: (context, state) => _sharedAxisPage(
          key: state.pageKey,
          child: const NotificationsCenterPage(),
        ),
      ),
      // Announcements. Root routes beside the Notifications Center: the list
      // is a full surface the user opens deliberately, and the compose form is
      // a full-screen form — both cover the bottom nav.
      //
      // Guarded on the publish key held **anywhere**, not in one detachment:
      // neither route carries a detachment id, so `canIn(null, ...)` would
      // refuse a scoped administrator who genuinely holds the key in one of
      // theirs. `canAnywhere` is the same resolver asked the right question.
      // The compose form revalidates every target again at submit — a route
      // guard is a door, not a permission check.
      GoRoute(
        path: AnnouncementsPage.routePath,
        redirect: _needsAnywhere(ref, Cap.announcementPublish),
        pageBuilder: (context, state) => _sharedAxisPage(
          key: state.pageKey,
          child: const AnnouncementsPage(),
        ),
      ),
      GoRoute(
        path: AnnouncementComposePage.routePath,
        redirect: _needsAnywhere(ref, Cap.announcementPublish),
        pageBuilder: (context, state) => _sharedAxisPage(
          key: state.pageKey,
          child: const AnnouncementComposePage(),
        ),
      ),
      // Global Search. A root route beside the Notifications Center and for
      // the same reason: a full surface the user opens deliberately, so it
      // covers the bottom nav. Reached from the magnifier in the dashboard's
      // app bar — the app's single entry point into it.
      //
      // Deliberately unguarded, unlike every gated route above. There is no
      // one capability the screen rests on: what it may search is a *set*
      // derived per session by `AdminView.searchableCategories`, and a session
      // that may search nothing gets a designed restricted state rather than a
      // bounce to `/home`. Nothing is exposed by opening it — the corpus is
      // built from scope-narrowed sources, and every destination it can offer
      // is guarded by the route or the check behind it.
      GoRoute(
        path: GlobalSearchPage.routePath,
        pageBuilder: (context, state) => _sharedAxisPage(
          key: state.pageKey,
          child: const GlobalSearchPage(),
        ),
      ),
      // The Needs Review inbox. A root route for the same reason the screen
      // it leads to is one — a substantial decision surface that covers the
      // bottom nav — and reachable only from an explicit human action (the
      // Settings attention row). Auto Sync still cannot navigate anywhere.
      GoRoute(
        path: NeedsReviewPage.routePath,
        pageBuilder: (context, state) => _sharedAxisPage(
          key: state.pageKey,
          child: const NeedsReviewPage(),
        ),
      ),
      // -----------------------------------------------------------------
      // Legacy `/tenant` deep links.
      //
      // The local grouping concept was called "tenant" until Point 1 renamed
      // it to DetachmentGroup, because "tenant" is the word the platform
      // needs for the paying customer (`SaasTenant`) and one word cannot
      // carry both. A link handed out, bookmarked or written into a shipped
      // build before the rename still has to land somewhere sensible.
      //
      // Redirect-only, deliberately: there is no second implementation of
      // these screens and no second route tree to keep in step — each entry
      // rewrites the path and hands it back to the router, which then applies
      // the capability guard on the canonical route exactly as a fresh link
      // would. No loop is possible: every target is under
      // `/detachment-groups`, and nothing under that prefix redirects back.
      //
      // Flat rather than nested on purpose. Which redirect in a matched chain
      // runs is a go_router implementation detail, and a parent `/tenant`
      // redirect that fired first would drop the id out of the child paths.
      // Declared longest-first so `/tenant/new` is not eaten by `:groupId`.
      //
      // TEMPORARY. Remove once no build in the field still emits `/tenant`
      // links — see `HANDOFF.md`, Point 1.
      // -----------------------------------------------------------------
      ..._legacyDetachmentGroupRedirects,
      ..._authRoutes,
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          _homeBranch(ref),
          _detachmentBranch(ref),
          _workshopBranch(ref),
          _moreBranch(ref),
        ],
      ),
    ],
  );
});
