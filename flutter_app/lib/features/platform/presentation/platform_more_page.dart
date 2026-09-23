import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_info.dart';
import '../../../core/display/frame_rate.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../l10n/strings.dart';
import '../../auth/data/auth_providers.dart';
import '../../auth/data/sign_out_controller.dart';
import '../../auth/presentation/sign_out_action.dart';
import '../../settings/data/frame_rate_provider.dart';
import '../../settings/data/motion_level_provider.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../domain/platform_area.dart';
import 'platform_destinations.dart';
import 'widgets/platform_page.dart';

/// `/platform/more` — the Super Admin's own account and application settings.
///
/// **An allowlist, and that is the whole design.** The tempting shortcut is to
/// render the tenant `SettingsPage` and hide the rows that do not apply. `§29`
/// forbids it and the reason is not tidiness: that screen reads the sync
/// outbox and the capability grant to build its row summaries, so rendering it
/// would initialise tenant machinery for the one session that must never touch
/// any (`§16`). Listing five safe destinations is both smaller and provably
/// correct.
///
/// **What is here, and why each one is safe.** Every row below reads only the
/// session (`currentUserProvider`), the app's own preferences (theme, motion,
/// frame rate) or a compile-time constant. None reads a detachment, a member,
/// a shift, an inventory item, a workshop or an organisation record.
///
///  - **حسابي** — the account screen, in its Super-Admin form: no organisation
///    row and no tenant capability rows. See `ProfilePage`.
///  - **السمات والأداء** — all application appearance preferences, including
///    the one Eye Protection control. They are properties of the device and
///    the person, not of a product.
///  - **الأمان** — sessions and MFA. `AuthRepository`, which is the platform
///    account's own authentication just as much as a tenant admin's.
///  - **حول التطبيق** — version and support addresses. Constants.
///
/// **What is deliberately absent.** The organisation record
/// (`/more/organization`) and plan (`/more/plan`), the
/// sync centre and Needs Review (a tenant outbox), notification preferences
/// (their four toggles are shifts, stock, workshops and join requests — tenant
/// events, `§28`), the tenant plan, detachment settings and tenant admin
/// management. Platform notifications are a later Point and will be their own
/// thing, never these.
class PlatformMorePage extends ConsumerWidget {
  const PlatformMorePage({super.key});

  /// The branch root. Every row below hangs off it, so there is one spelling
  /// of the platform settings prefix.
  static String get location => PlatformArea.more.route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final destination = destinationFor(PlatformArea.more);
    final signedInName = ref.watch(currentUserProvider).valueOrNull?.name;
    final signingOut =
        ref.watch(signOutControllerProvider) == SignOutPhase.inProgress;
    final theme = ref.watch(themeStateProvider);
    final motion = ref.watch(motionLevelProvider);
    final frameRate = ref.watch(frameRateProvider);

    // The same three-part summary the tenant hub shows, from the same
    // providers and the same label functions — this is one application
    // preference, and two descriptions of it would drift.
    final appearanceSummary = [
      themeChoiceLabel(theme.choice),
      if (motion.valueOrNull != null) motionLevelLabel(motion.valueOrNull!),
      frameRateLabel(frameRate.valueOrNull ?? FrameRatePreference.auto),
    ].join(' · ');

    return PlatformPage(
      title: destination.label,
      children: [
        const SectionLabel(S.sectionAccount),
        SettingsSection(children: [
          NavigationRow(
            key: const Key('platform-more-profile'),
            icon: Icons.person_outline_rounded,
            label: S.settingsProfile,
            subtitle: signedInName,
            onTap: () => context.push('$location/profile'),
          ),
        ]),
        const SectionLabel(S.sectionAppearance),
        SettingsSection(children: [
          NavigationRow(
            key: const Key('platform-more-themes'),
            icon: Icons.palette_outlined,
            label: S.sectionThemesPerformance,
            subtitle: appearanceSummary,
            onTap: () => context.push('$location/themes'),
          ),
        ]),
        const SectionLabel(S.sectionApp),
        SettingsSection(children: [
          NavigationRow(
            key: const Key('platform-more-security'),
            icon: Icons.shield_outlined,
            label: S.settingsSecurity,
            onTap: () => context.push('$location/security'),
          ),
          NavigationRow(
            key: const Key('platform-more-about'),
            icon: Icons.info_outline_rounded,
            label: S.aboutTitle,
            subtitle: AppInfo.version,
            onTap: () => context.push('$location/about'),
          ),
        ]),
        const Padding(
          padding: EdgeInsetsDirectional.only(
            start: AppSpacing.xs,
            end: AppSpacing.xs,
            top: AppSpacing.md,
          ),
          child: _ScopeNote(),
        ),
        const SizedBox(height: AppSpacing.xl),
        OutlinedButton.icon(
          // The one sign-out in the app, shared with every other surface.
          onPressed: signingOut ? null : () => confirmAndSignOut(context, ref),
          style: OutlinedButton.styleFrom(
            foregroundColor: c.crit,
            side: BorderSide(color: c.crit),
          ),
          icon: const Icon(Icons.logout_rounded),
          label: const Text(S.signOut),
        ),
      ],
    );
  }
}

/// One sentence saying what this screen is *not*, so the absence of an
/// organisation section reads as a boundary rather than as a missing feature.
class _ScopeNote extends StatelessWidget {
  const _ScopeNote();

  @override
  Widget build(BuildContext context) => Text(
        S.platformMoreScopeNote,
        style: TextStyle(
          color: context.c.ink3,
          fontSize: 12,
          height: 1.5,
        ),
      );
}
