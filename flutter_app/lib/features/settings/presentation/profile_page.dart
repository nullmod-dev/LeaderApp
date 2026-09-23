import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../demo/data/demo_workspace.dart';
import '../../demo/presentation/demo_trial_bar.dart';
import '../../../core/access/admin_experience.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_result.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../../core/widgets/refresh_indicator.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../../auth/data/auth_providers.dart';
import '../../auth/data/sign_out_controller.dart';
import '../../auth/presentation/sign_out_action.dart';
import '../../auth/domain/admin_account.dart';
import '../../auth/domain/auth_models.dart';
import '../../shell/main_shell.dart';
import 'widgets/settings_widgets.dart';

/// The signed-in administrator's own account (`/more/profile`) — the app's
/// one account screen, reached from the Account section of the Settings hub.
///
/// **What this screen is not.** MTM is administered by a handful of admin
/// accounts; no volunteer ever signs in. So there is no member profile here —
/// no shifts, no attendance, no specialty, no personal history. A person's
/// operational record lives in the Members module, which is about *other*
/// people, and the two are never crossed: the authenticated account is not a
/// `TeamMember` and nothing on this screen infers one.
///
/// **Everything shown is on `AuthUser`.** Name, email, organisation name,
/// avatar initials, the account's role, and the capability grant — that is
/// the whole of the account payload in `API_CONTRACT.md`, and this screen
/// shows no field the server does not send. There is no phone, no username
/// and no account status; inventing a row for any of them would be inventing
/// data. Nothing token-shaped is rendered anywhere, and `saasTenantId` is not
/// rendered either: it is an isolation boundary, not a fact a person reads
/// off their own account.
///
/// **Role and access level are two different rows on purpose.** «نوع الحساب»
/// is `AuthUser.role` — the product surface the server asserted, reported
/// verbatim. «مستوى الوصول» is `AdminAccountSummary`, derived from the grant.
/// A Main Admin whose keys were narrowed is still a Main Admin *and* honestly
/// shown as narrowed; collapsing the two would let one of them lie.
///
/// **It is read-only, deliberately.** `AuthRepository` has no self-update
/// method and the contract has no endpoint behind one, so there is no edit
/// affordance to offer — writing changes into a local object and calling it
/// an account edit would be a lie the next cold start exposes. The screen
/// says so once, quietly, instead of hiding the absence.
///
/// **One screen, two surfaces.** A Super Admin reaches it at
/// `/platform/more/profile` and a tenant admin at `/more/profile`. Two things
/// differ between them, and both are stated here rather than in a second copy
/// of the file: [securityRoute], because Security lives inside whichever
/// shell asked; and the access section, because the thirty keys in `Cap` are
/// tenant-operational and a platform account holds none of them — reporting
/// «غير ممنوح» five times would describe the platform owner as the narrowest
/// admin in the system, which is precisely the claim the product model denies
/// (`§27`).
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key, this.securityRoute = '/more/security'});

  /// Where the Security row goes. The tenant shell's by default; the platform
  /// shell passes its own, so the row cannot push a tenant location that the
  /// router would immediately bounce — a dead control that happens to look
  /// like a working one.
  final String securityRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text(S.settingsProfile)),
      body: AppRefreshIndicator(
        onRefresh: () => ref.refresh(currentUserResultProvider.future),
        // The un-collapsed session: this screen is the one place that has to
        // tell "no session" from "the read failed" from "offline with
        // nothing cached", and `currentUserProvider` flattens all three to
        // null. Loading, failure, stale and offline-without-cache are the
        // shared view's four states; the fifth — signed out — is the null
        // below, which is a successful answer, not an error.
        child: AsyncResultView<AuthUser?>(
          value: ref.watch(currentUserResultProvider),
          onRetry: () => ref.invalidate(currentUserResultProvider),
          loading: const SkeletonList(count: 4),
          builder: (context, user, stale) => user == null
              ? EmptyState(
                  icon: Icons.person_off_outlined,
                  title: S.profileNoSession,
                  body: S.profileNoSessionSub,
                  actionLabel: S.signIn,
                  onAction: () => context.go('/login'),
                )
              : _AccountContent(
                  user: user,
                  stale: stale,
                  securityRoute: securityRoute,
                ),
        ),
      ),
    );
  }
}

class _AccountContent extends ConsumerWidget {
  const _AccountContent({
    required this.user,
    required this.stale,
    required this.securityRoute,
  });

  final AuthUser user;
  final bool stale;
  final String securityRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The platform owner is not classified by the tenant grant at all — see
    // the class note. Everything derived from `Capabilities` below is built
    // only for the surface it describes.
    final isPlatform = user.role == AuthRole.superAdmin;
    final demo = ref.watch(isCustomerDemoSessionProvider);
    final summary = AdminAccountSummary.of(user.capabilities);
    final signingOut =
        ref.watch(signOutControllerProvider) == SignOutPhase.inProgress;

    return FloatingNavPadding(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (stale)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.md),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: StaleBadge(),
              ),
            ),
          _IdentityHeader(
            user: user,
            view: AdminView.of(user.capabilities),
          ),
          const SectionLabel(S.profileAccountSection),
          SettingsSection(children: [
            _InfoRow(
              icon: Icons.alternate_email_rounded,
              label: S.profileEmail,
              // An address is Latin script inside an Arabic column: pinned
              // LTR so it is not reordered around its @ and dots.
              value: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(user.email),
              ),
            ),
            // The organisation, for an account that is *in* one. A Super Admin
            // is not: `saasTenantId` is null by invariant, and `orgName` on
            // that account names the platform rather than a customer — a row
            // labelled «المؤسسة» over it would read as a tenant identity this
            // account does not have.
            if (!isPlatform)
              _InfoRow(
                icon: Icons.apartment_rounded,
                label: S.profileOrg,
                value: Text(user.orgName),
              ),
          ]),
          const _Caption(S.profileReadOnlyNote),
          const SectionLabel(S.profileAccessSection),
          SettingsSection(children: [
            _InfoRow(
              icon: Icons.workspace_premium_outlined,
              label: S.profileRole,
              value: Text(roleLabel(user.role)),
            ),
            // Access level, scope and the two administration keys are readings
            // of a *tenant* grant. On the platform surface they would all say
            // "none", which is true of `Cap` and false about the account, so
            // the section stops after the role and says why.
            if (!isPlatform) ...[
              _InfoRow(
                icon: Icons.verified_user_outlined,
                label: S.profileAccessLevel,
                value: Text(_levelLabel(summary.level)),
              ),
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: S.profileScope,
                value: Text(_scopeLabel(summary)),
              ),
              // The two administration keys, and only those two. The grant has
              // thirty; listing them all would be an internal permission
              // matrix, not an account summary. These two are here because they
              // are the ones a person actually asks about — "may I manage the
              // other admins, may I edit the organisation" — not because they
              // stand in for a rank. The rank is the row above, read off
              // `AuthUser.role`.
              _GrantRow(
                icon: Icons.admin_panel_settings_outlined,
                label: S.profileManagesAdmins,
                granted: summary.managesAdmins,
              ),
              _GrantRow(
                icon: Icons.edit_note_rounded,
                label: S.profileEditsOrg,
                granted: summary.editsOrganisation,
              ),
            ],
          ]),
          _Caption(
            isPlatform ? S.platformProfileAccessNote : S.profileAccessNote,
          ),
          // A Customer Demo trial is not an account: there is no password to
          // reset and no device list to review, so the whole section is
          // absent rather than offered and refused.
          if (!demo) ...[
            const SectionLabel(S.profileSecuritySection),
            SettingsSection(children: [
              // Sessions and MFA already have a screen; this routes to it
              // rather than growing a second copy of the session list.
              NavigationRow(
                icon: Icons.shield_outlined,
                label: S.settingsSecurity,
                subtitle: S.profileSecurityRow,
                onTap: () => context.push(securityRoute),
              ),
              // The only password change the backend supports is the
              // reset-by-email flow (`requestPasswordReset` → OTP → set new).
              // There is no authenticated change-password endpoint, so the row
              // is worded as the flow it actually starts.
              NavigationRow(
                icon: Icons.password_rounded,
                label: S.profilePasswordReset,
                subtitle: S.profilePasswordResetSub,
                onTap: () => context.push('/forgot'),
              ),
            ]),
          ],
          const SizedBox(height: AppSpacing.xl),
          OutlinedButton.icon(
            // Disabled for the duration of the request, and the controller
            // drops a second call anyway — a double tap must not fire two
            // sign-outs, from here or from the Settings hub's button.
            onPressed: signingOut
                ? null
                : () => demo
                    ? endDemoTrial(context, ref)
                    : confirmAndSignOut(context, ref),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.c.crit,
              side: BorderSide(color: context.c.crit),
            ),
            icon: const Icon(Icons.logout_rounded),
            label: Text(demo ? S.customerDemoExit : S.signOut),
          ),
        ],
      ),
    );
  }
}

/// The human-readable name of an account level.
///
/// **Identity, never authority.** Nothing opens because of what this returns;
/// every action still resolves through `Capabilities.canIn`. It exists so the
/// account screen can say what the server said instead of guessing a rank
/// from capability breadth — a Main Admin must not be presented as a Simple
/// Admin, and neither may be presented as the platform owner.
String roleLabel(AuthRole role) => switch (role) {
      AuthRole.superAdmin => S.roleSuperAdmin,
      AuthRole.mainAdmin => S.roleMainAdmin,
      AuthRole.admin => S.roleSimpleAdmin,
      AuthRole.customerDemo => S.roleCustomerDemo,
    };

String _levelLabel(AdminAccessLevel level) => switch (level) {
      AdminAccessLevel.full => S.profileAccessFull,
      AdminAccessLevel.organisation => S.profileAccessOrg,
      AdminAccessLevel.detachmentScoped => S.profileAccessScoped,
      AdminAccessLevel.none => S.profileAccessNone,
    };

String _scopeLabel(AdminAccountSummary summary) {
  if (summary.level == AdminAccessLevel.full ||
      summary.level == AdminAccessLevel.organisation) {
    return S.profileScopeOrgWide;
  }
  return switch (summary.detachmentCount) {
    0 => S.profileAccessNone,
    1 => S.profileScopeOneDetachment,
    final n =>
      S.profileScopeManyDetachments.replaceFirst('%d', toArabicIndic('$n')),
  };
}

/// Name, address and the one-line statement of what this account is.
///
/// A compact header, not a hero: this is an administrative account page, so
/// it opens with identity and gets out of the way.
class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({required this.user, required this.view});

  final AuthUser user;

  /// Which of the two experiences this account is shown. A **presentation
  /// label derived from capability breadth**, not an account property: the
  /// server sends no role and the domain has no Main Admin field, so the chip
  /// says how broad the grant is and the rows below say exactly what it
  /// contains. `admin_experience.dart` states the mapping once.
  final AdminView view;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final initials = user.avatarInitials;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.primaryTint,
              shape: BoxShape.circle,
              border: Border.all(color: c.primary),
            ),
            // `avatarInitials` is optional on the wire. When it is absent the
            // avatar is a person glyph — filling it with the app's name, or
            // with anything else invented here, would put made-up identity on
            // an identity screen.
            child: initials == null
                ? Icon(Icons.person_outline_rounded, color: c.primary)
                : Text(
                    initials,
                    style: TextStyle(
                      color: c.primary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A long Arabic name wraps rather than being clipped.
                Text(
                  user.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  // The account's own role, not a computed label. A Super
                  // Admin never reaches this screen — the router holds it
                  // outside the tenant application — but if it ever did, the
                  // chip below would call it what it is rather than grading
                  // it as a narrow in-tenant admin, which is what the
                  // capability-derived experience chip would have to say.
                  child: user.role == AuthRole.superAdmin
                      ? StatusChip(
                          kind: StatusKind.info,
                          label: roleLabel(user.role),
                        )
                      : StatusChip(
                          kind:
                              view.isFull ? StatusKind.info : StatusKind.muted,
                          label: view.isFull
                              ? S.adminExperienceFull
                              : S.adminExperienceScoped,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c.ink3, size: 20),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: c.ink3, fontSize: 12)),
                const SizedBox(height: AppSpacing.xs),
                // `merge`, not a replacement: a bare `TextStyle` names no
                // family, and setting it as *the* default text style drops the
                // theme's — so the email and the account type were the only
                // rows on this screen rendered in the platform's font instead
                // of the app's. Merging keeps the family and overrides only
                // what is named here.
                DefaultTextStyle.merge(
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  child: value,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One capability, said plainly: held or not held.
class _GrantRow extends StatelessWidget {
  const _GrantRow({
    required this.icon,
    required this.label,
    required this.granted,
  });

  final IconData icon;
  final String label;
  final bool granted;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(children: [
        Icon(icon, color: c.ink3, size: 20),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: c.ink,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        StatusChip(
          kind: granted ? StatusKind.ok : StatusKind.muted,
          label: granted ? S.profileGranted : S.profileNotGranted,
        ),
      ]),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AppSpacing.xs,
        end: AppSpacing.xs,
        top: AppSpacing.sm,
      ),
      child: Text(
        text,
        style: TextStyle(color: context.c.ink3, fontSize: 12, height: 1.5),
      ),
    );
  }
}
