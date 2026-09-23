import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/reading_column.dart';
import '../../demo/data/demo_workspace.dart';
import '../../demo/presentation/demo_trial_bar.dart';
import '../../../core/access/capability.dart';
import '../../../core/access/capability_guard.dart';
import '../../../core/app_info.dart';
import '../../../core/display/frame_rate.dart';
import '../../../core/env/build_mode.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../core/sync/outbox_controller.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/made_in_iraq.dart';
import '../../../l10n/strings.dart';
import '../../about/presentation/about_page.dart';
import '../../admin_management/presentation/simple_admin_management_page.dart';
import '../../auth/data/auth_providers.dart';
import '../../auth/data/sign_out_controller.dart';
import '../../auth/presentation/dev_session_states_page.dart';
import '../../auth/presentation/sign_out_action.dart';
import '../../organization/presentation/organization_page.dart';
import '../../pricing/presentation/pricing_page.dart';
import '../../shell/main_shell.dart';
import '../data/frame_rate_provider.dart';
import '../data/motion_level_provider.dart';
import 'widgets/settings_widgets.dart';

/// The Settings hub (`/more`): navigation only.
///
/// Every control it once held directly now lives on its own nested screen
/// (`/more/themes`, `/more/sync`, …), reading and writing the exact same
/// providers it always did. This page only routes to them and shows a short,
/// plain-language summary of the active choice on each row. Eye Protection
/// has one user-facing control, inside Themes & Appearance.
///
/// The order is the order a user looks for things — account, then how the
/// app looks, then its data, then the rest — and every row leads somewhere
/// that exists. There is no Language row (the app is Arabic-only). About &
/// support is one row leading to one screen (`/more/about`) — not a row each
/// for About, Support and Contact us, which would be three names for one
/// destination. There is deliberately no Privacy or Terms row: those are
/// deferred until the backend's real data handling is known, and a row that
/// opened nothing would be worse than an absent one.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Only for the Account row's subtitle: which account is signed in. The
    // collapsed view is the right one here — a hub row has nothing useful to
    // say about *why* there is no session, and the account screen it leads to
    // explains that properly.
    final signedInName = ref.watch(currentUserProvider).valueOrNull?.name;
    // A Customer Demo trial runs on these same screens. What it is not
    // offered is listed in the router's `_demoBlockedLocations`; the rows
    // below are hidden for the same reasons, so no row opens a page the
    // router would bounce.
    final demo = ref.watch(isCustomerDemoSessionProvider);
    final canManageAdmins =
        ref.watch(capabilitiesProvider).can(Cap.adminManage);
    // Personal settings — profile, appearance, sync,
    // notifications, security, sign-out — need no grant and are the same hub
    // for every administrator; gating a person's own device preferences
    // behind a capability would be wrong (`CAPABILITIES.md` §2). Since Point
    // 15 the organisation rows are ungated too: Organization and Plan are
    // read-only context both tenant roles need, and the organisation-wide
    // usage figures `org.edit` gates are withheld inside the Plan read
    // itself rather than by hiding the row.
    final signingOut =
        ref.watch(signOutControllerProvider) == SignOutPhase.inProgress;
    final theme = ref.watch(themeStateProvider);
    final motion = ref.watch(motionLevelProvider);
    final frameRate = ref.watch(frameRateProvider);
    final pending = ref.watch(pendingOperationsCountProvider);
    final needingReview = ref.watch(conflictOperationsCountProvider);
    final syncStatus = ref.watch(syncCoordinatorProvider);

    // One row now leads to one screen, so its summary carries all three of
    // that screen's choices: theme, performance level, frame rate. The
    // stored motion level may still be loading; the theme and the frame
    // rate always have a usable value.
    final themesSubtitle = [
      themeChoiceLabel(theme.choice),
      themeModeLabel(theme.mode),
      if (motion.valueOrNull != null) motionLevelLabel(motion.valueOrNull!),
      frameRateLabel(frameRate.valueOrNull ?? FrameRatePreference.auto),
    ].join(' — ');

    final String syncSubtitle;
    Color? syncSubtitleColor;
    if (syncStatus.isSyncing) {
      syncSubtitle = S.syncInProgress;
    } else if (needingReview > 0) {
      syncSubtitle = needingReview == 1
          ? S.syncReviewOne
          : S.syncReviewMany
              .replaceFirst('%d', toArabicIndic('$needingReview'));
      syncSubtitleColor = c.warn;
    } else if (pending == 0) {
      syncSubtitle = S.syncAllSynced;
    } else if (pending == 1) {
      syncSubtitle = S.syncPendingOne;
    } else {
      syncSubtitle = S.syncPendingMany
          .replaceFirst('%d', toArabicIndic(pending.toString()));
    }

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text(S.settingsTitle)),
      // One column of label↔value rows: capped at the reading measure so a
      // tablet gains margins instead of a row whose label and value sit at
      // opposite ends of the window. Below 520 dp nothing changes.
      body: FloatingNavPadding(
        child: ReadingColumn(
            child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // Personal choices belong together: the signed-in account and
            // how this device presents the app. Eye Protection still has its
            // one control on the canonical appearance page.
            const SectionLabel(S.sectionAccount),
            SettingsSection(children: [
              NavigationRow(
                icon: Icons.person_outline_rounded,
                label: S.settingsProfile,
                subtitle: signedInName,
                onTap: () => context.push('/more/profile'),
              ),
              NavigationRow(
                icon: Icons.palette_outlined,
                label: S.sectionThemesPerformance,
                subtitle: themesSubtitle,
                onTap: () => context.push('/more/themes'),
              ),
            ]),
            // App services share one group. A Customer Demo writes nothing
            // to the device's queue and has no real account, so Sync and
            // Security remain absent there exactly as before.
            const SectionLabel(S.sectionApp),
            SettingsSection(children: [
              if (!demo)
                NavigationRow(
                  icon: needingReview == 0 &&
                          pending == 0 &&
                          !syncStatus.isSyncing
                      ? Icons.cloud_done_outlined
                      : Icons.sync_rounded,
                  label: S.sectionSync,
                  subtitle: syncSubtitle,
                  subtitleColor: syncSubtitleColor,
                  onTap: () => context.push('/more/sync'),
                ),
              NavigationRow(
                icon: Icons.notifications_none_rounded,
                label: S.settingsNotifications,
                onTap: () => context.push('/more/notifications'),
              ),
              // A trial has no real account, so it is not offered the
              // password, the second factor or the device list.
              if (!demo)
                NavigationRow(
                  icon: Icons.shield_outlined,
                  label: S.settingsSecurity,
                  onTap: () => context.push('/more/security'),
                ),
              // The one canonical About & Support destination. No separate
              // "Support" or "Contact us" row: the address lives on the page
              // this row opens, and two rows into one screen is two names for
              // one thing.
              NavigationRow(
                key: const Key('settings-about-row'),
                icon: Icons.info_outline_rounded,
                label: S.aboutTitle,
                subtitle: AppInfo.version,
                onTap: () => context.push(AboutPage.routePath),
              ),
            ]),
            // DEVELOPMENT ONLY. The one entry point into the session-state
            // inspector, placed here because the states it forces are things
            // that happen to a signed-in account. `demoAccountsAllowed` is
            // `const false` in any shipping artefact, so this `if` is dead
            // code there and the row, its route and the page behind it are
            // tree-shaken out. The Login screen exposes no development
            // selector in any build. See `core/env/build_mode.dart`.
            if (demoAccountsAllowed) ...[
              const SectionLabel(S.devStatesTitle),
              SettingsSection(children: [
                NavigationRow(
                  key: const Key('settings-dev-states-row'),
                  icon: Icons.bug_report_outlined,
                  label: S.devStatesOpen,
                  onTap: () => context.push(DevSessionStatesPage.location),
                ),
              ]),
            ],
            // Product pricing is public commercial information for both a
            // tenant administrator and a Customer Demo. It therefore lives in
            // its own unconditional section rather than inside Organization.
            const SectionLabel(S.sectionSubscription),
            SettingsSection(children: [
              NavigationRow(
                key: const Key('settings-pricing-row'),
                icon: Icons.sell_outlined,
                label: S.pricingTitle,
                subtitle: S.pricingRowSub,
                onTap: () => context.push(PricingPage.routePath),
              ),
            ]),
            // The organisation row is the context door; its existing Plan
            // row opens the current subscription and limits. Keeping a
            // second Plan door here beside Pricing made one concept appear
            // twice. A demo belongs to no organisation.
            if (!demo) ...[
              const SectionLabel(S.sectionOrgManagement),
              SettingsSection(children: [
                NavigationRow(
                  key: const Key('settings-org-row'),
                  icon: Icons.apartment_rounded,
                  label: S.settingsOrg,
                  onTap: () => context.push(OrganizationPage.routePath),
                ),
                if (canManageAdmins)
                  NavigationRow(
                    key: const Key('settings-simple-admins-row'),
                    icon: Icons.manage_accounts_outlined,
                    label: S.simpleAdminsTitle,
                    subtitle: S.simpleAdminsRowSub,
                    onTap: () =>
                        context.push(SimpleAdminManagementPage.routePath),
                  ),
              ]),
            ],
            // Sign-out last: it leaves the app, so it sits below every
            // destination rather than between two of them.
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton.icon(
              onPressed: signingOut
                  ? null
                  : (demo ? () => endDemoTrial(context, ref) : _confirmSignOut),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.crit,
                side: BorderSide(color: c.crit),
              ),
              icon: const Icon(Icons.logout_rounded),
              // A trial is ended, not signed out of.
              label: Text(demo ? S.customerDemoExit : S.signOut),
            ),
            // The very bottom of the scrollable content — below sign-out,
            // which is itself below every destination. Reached by scrolling,
            // never pinned, and not a settings row: it is the product signing
            // itself off, not something to do.
            const MadeInIraqFooter(),
          ],
        )),
      ),
    );
  }

  // The confirmation, the request, the duplicate-tap guard, the clearing of
  // the session providers and the departure all live in `confirmAndSignOut`,
  // shared with the account and Security screens.
  Future<void> _confirmSignOut() => confirmAndSignOut(context, ref);
}
