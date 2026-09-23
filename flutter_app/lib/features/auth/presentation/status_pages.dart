/// Every user-visible session state the startup classifier can reach.
///
/// **Why one file.** These are nine variations on one surface — icon, tone,
/// two sentences, one or two actions — built on the same `StatusScreen`. Split
/// across nine files they would be nine copies of the same eleven lines of
/// import and boilerplate, and the thing that actually matters about them —
/// that the *wording* differs and nothing else does — would be invisible.
/// Read top to bottom, the file is the copy deck for the whole state table.
///
/// **Each page is a leaf.** None reads a repository, none builds navigation,
/// none renders tenant data. What they may show is the account's own name, and
/// only where knowing it explains the screen. Everything else on them is
/// static copy plus the ordinary sign-out.
///
/// The route for each is declared on [StartupDestination], not here: the pure
/// decision layer owns the canonical spelling of every location so the router
/// and the classifier cannot disagree about one. See
/// `core/startup/startup_destination.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/startup/startup_destination.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_screen.dart';
import '../../../l10n/strings.dart';
import '../../about/domain/support_contacts.dart';
import '../data/auth_providers.dart';
import '../domain/auth_models.dart';
import '../data/sign_out_controller.dart';
import 'account_setup_page.dart';
import 'email_verification_page.dart';
import 'link_team_page.dart';
import 'sign_out_action.dart';

/// The sign-out button these screens share.
///
/// The **ordinary** sign-out — the same controller, the same confirmation and
/// the same clearing of the durable development record that the Settings hub
/// uses. There is no separate exit from a blocked state, because a second one
/// is how a session gets left half-cleared.
class _SignOutButton extends ConsumerWidget {
  const _SignOutButton({this.filled = false});

  final bool filled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final busy =
        ref.watch(signOutControllerProvider) == SignOutPhase.inProgress;
    final onPressed = busy ? null : () => confirmAndSignOut(context, ref);

    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.logout_rounded),
        label: const Text(S.signOut),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: c.crit,
        side: BorderSide(color: c.crit),
      ),
      icon: const Icon(Icons.logout_rounded),
      label: const Text(S.signOut),
    );
  }
}

/// Shows the app's real support addresses, in a dialog.
///
/// **Deliberately not a link to About.** `/more/about` lives inside the tenant
/// shell branch, so opening it would build `MainShell` — the bottom nav, and
/// the providers behind it — for exactly the sessions that must never
/// instantiate the tenant surface (`§32`). A dialog over the state screen
/// needs no route, no navigator branch and no repository, and it reads the
/// same two constants About does, so there is still one source for the
/// addresses.
class _SupportButton extends StatelessWidget {
  const _SupportButton();

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const _SupportDialog(),
        ),
        icon: const Icon(Icons.support_agent_rounded),
        label: const Text(S.contactSupport),
      );
}

class _SupportDialog extends StatelessWidget {
  const _SupportDialog();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AlertDialog(
      scrollable: true,
      title: const Text(S.aboutSupport),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(S.aboutSupportBody),
          SizedBox(height: AppSpacing.lg),
          // An address and a Telegram handle are Latin identifiers: forced LTR
          // so they read correctly inside the Arabic layout, the same
          // treatment About already gives them.
          _Contact(
            label: S.aboutSupportEmailLabel,
            value: supportEmail,
            copied: S.aboutEmailCopied,
          ),
          SizedBox(height: AppSpacing.md),
          _Contact(
            label: S.aboutSupportTelegramLabel,
            value: supportTelegram,
            copied: S.aboutTelegramCopied,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(S.close),
        ),
      ],
      backgroundColor: c.surface,
    );
  }
}

class _Contact extends StatelessWidget {
  const _Contact({
    required this.label,
    required this.value,
    required this.copied,
  });

  final String label;
  final String value;
  final String copied;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: c.ink3, fontSize: 12)),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: SelectableText(
                  value,
                  style: TextStyle(color: c.ink, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
      IconButton(
        tooltip: S.copy,
        onPressed: () async {
          final messenger = ScaffoldMessenger.maybeOf(context);
          await Clipboard.setData(ClipboardData(text: value));
          messenger?.showSnackBar(SnackBar(content: Text(copied)));
        },
        icon: const Icon(Icons.copy_rounded, size: 18),
      ),
    ]);
  }
}

/// The account card, when there is an account to name.
///
/// Name and account type, and deliberately nothing else — no email, no
/// organisation, no capability. A blocked or unassigned session must not be a
/// place to read details out of, and the reader only needs enough to answer
/// "is this the account I think it is".
class _Identity extends ConsumerWidget {
  const _Identity();

  static String _roleLabel(AuthRole role) => switch (role) {
        AuthRole.superAdmin => S.roleSuperAdmin,
        AuthRole.mainAdmin => S.roleMainAdmin,
        AuthRole.admin => S.roleSimpleAdmin,
        AuthRole.customerDemo => S.roleCustomerDemo,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user == null) return const SizedBox.shrink();
    return StatusIdentityCard(
      name: user.name,
      subtitle: _roleLabel(user.role),
    );
  }
}

// -----------------------------------------------------------------------------
// Authentication faults
// -----------------------------------------------------------------------------

/// An account payload this client refuses — role and tenant id disagree.
///
/// Fails closed, and says so plainly: no raw exception, no stack, and no
/// invitation to retry the same broken payload silently. The primary action is
/// the ordinary sign-out, which is what actually clears the refused session.
class SessionInvalidPage extends StatelessWidget {
  const SessionInvalidPage({super.key});

  @override
  Widget build(BuildContext context) => const StatusScreen(
        icon: Icons.report_problem_outlined,
        tone: StatusTone.critical,
        title: S.sessionInvalidTitle,
        body: S.sessionInvalidBody,
        detail: S.sessionInvalidDetail,
        // No identity card: the account was refused, so nothing about it is
        // trustworthy enough to render.
        primaryAction: _SignOutButton(filled: true),
        secondaryAction: _SupportButton(),
      );
}

/// A session envelope this build cannot interpret.
///
/// **Neither an account fault nor an authentication failure.** The account is
/// well-formed and the server answered; what arrived was a lifecycle value
/// this version of the app has never heard of, and there is no safe way to
/// guess whether it is more permissive or more restrictive than the states it
/// knows. So nothing opens — see `SessionAccess.unsupported` for why an
/// *absent* field is the opposite case and still means "normal".
///
/// The copy names the fix (update the app) rather than the cause (a wire
/// value), because the raw string is a diagnostic and not something a platform
/// administrator can act on. The identity card stays: the account itself is
/// trustworthy here, and knowing which one is held is what tells the reader
/// whether to update this device or ask about that account.
class AccessUnsupportedPage extends StatelessWidget {
  const AccessUnsupportedPage({super.key});

  @override
  Widget build(BuildContext context) => const StatusScreen(
        icon: Icons.system_update_alt_rounded,
        tone: StatusTone.warning,
        title: S.accessUnsupportedTitle,
        body: S.accessUnsupportedBody,
        detail: S.accessUnsupportedDetail,
        identity: _Identity(),
        primaryAction: _SignOutButton(filled: true),
        secondaryAction: _SupportButton(),
      );
}

// -----------------------------------------------------------------------------
// Authorization inside a valid tenant session
// -----------------------------------------------------------------------------

/// A valid, connected tenant account that holds no usable capability.
///
/// **Not an error screen**, and the copy is written to make that unmistakable:
/// nothing failed, nothing is broken, nobody has assigned this person anything
/// yet. It deliberately does not say "suspended" — that is a different state
/// with a different cause, and inferring one from an empty grant is the exact
/// mistake `§9` of the brief forbids.
class AccessNotAssignedPage extends StatelessWidget {
  const AccessNotAssignedPage({super.key});

  @override
  Widget build(BuildContext context) => const StatusScreen(
        icon: Icons.badge_outlined,
        tone: StatusTone.neutral,
        title: S.accessNotAssignedTitle,
        body: S.accessNotAssignedBody,
        detail: S.accessNotAssignedDetail,
        identity: _Identity(),
        primaryAction: _SignOutButton(filled: true),
      );
}

// -----------------------------------------------------------------------------
// Account lifecycle
// -----------------------------------------------------------------------------

/// Temporarily blocked. Reversible, and no reason is stated — the backend does
/// not supply one, and inventing one would be telling the user something the
/// app does not know.
class AccountSuspendedPage extends StatelessWidget {
  const AccountSuspendedPage({super.key});

  @override
  Widget build(BuildContext context) => const StatusScreen(
        icon: Icons.pause_circle_outline_rounded,
        tone: StatusTone.warning,
        title: S.accountSuspendedTitle,
        body: S.accountSuspendedBody,
        detail: S.accountSuspendedDetail,
        identity: _Identity(),
        primaryAction: _SignOutButton(filled: true),
        secondaryAction: _SupportButton(),
      );
}

/// Access withdrawn. Terminal, and phrased as terminal: no retry, and the copy
/// says outright that this is not a connection problem, because an offline-first
/// app trains its users to read a blocked screen as a network one.
class AccountRevokedPage extends StatelessWidget {
  const AccountRevokedPage({super.key});

  @override
  Widget build(BuildContext context) => const StatusScreen(
        icon: Icons.block_rounded,
        tone: StatusTone.critical,
        title: S.accountRevokedTitle,
        body: S.accountRevokedBody,
        detail: S.accountRevokedDetail,
        identity: _Identity(),
        primaryAction: _SignOutButton(filled: true),
        secondaryAction: _SupportButton(),
      );
}

// -----------------------------------------------------------------------------
// Customer (SaasTenant) lifecycle
// -----------------------------------------------------------------------------

/// The customer is suspended.
///
/// Full block is the Point 9 policy. Suspension preserves data, subscription,
/// features and limits, but neither Main nor Simple Admin may enter the tenant
/// shell while the state is known.
class TenantSuspendedPage extends StatelessWidget {
  const TenantSuspendedPage({super.key});

  @override
  Widget build(BuildContext context) => const StatusScreen(
        icon: Icons.pause_circle_outline_rounded,
        tone: StatusTone.warning,
        title: S.tenantSuspendedTitle,
        body: S.tenantSuspendedBody,
        detail: S.tenantSuspendedDetail,
        // No identity card and no organisation name: a suspended customer is
        // not a place to read its own details out of.
        primaryAction: _SignOutButton(filled: true),
        secondaryAction: _SupportButton(),
      );
}

/// Final deletion is scheduled but has not happened. Tenant operation is
/// blocked throughout the pending window; the platform remains able to cancel
/// the request before its effective instant.
class TenantDeletionPendingPage extends StatelessWidget {
  const TenantDeletionPendingPage({super.key});

  @override
  Widget build(BuildContext context) => const StatusScreen(
        icon: Icons.hourglass_top_rounded,
        tone: StatusTone.warning,
        title: S.tenantDeletionPendingTitle,
        body: S.tenantDeletionPendingBody,
        detail: S.tenantDeletionPendingDetail,
        primaryAction: _SignOutButton(filled: true),
        secondaryAction: _SupportButton(),
      );
}

/// The customer no longer exists.
///
/// Deliberately not a "not found" page: a deleted customer is a known,
/// terminal outcome, and rendering it as a missing resource would suggest a
/// wrong link. No cached tenant data is shown beneath it.
class TenantDeletedPage extends StatelessWidget {
  const TenantDeletedPage({super.key});

  @override
  Widget build(BuildContext context) => const StatusScreen(
        icon: Icons.folder_off_outlined,
        tone: StatusTone.critical,
        title: S.tenantDeletedTitle,
        body: S.tenantDeletedBody,
        detail: S.tenantDeletedDetail,
        primaryAction: _SignOutButton(filled: true),
        secondaryAction: _SupportButton(),
      );
}

// -----------------------------------------------------------------------------
// Onboarding — the production screens are Point 17B's:
// `account_setup_page.dart`, `email_verification_page.dart`,
// `link_team_page.dart`. This file keeps only the surrounding status screens.
// -----------------------------------------------------------------------------
// Customer demo — the future product feature, not the development personas
// -----------------------------------------------------------------------------

/// A customer demo whose window has ended. No mutation, no tenant route, and
/// no subscription flow — that conversion is a later point's.
class DemoExpiredPage extends StatelessWidget {
  const DemoExpiredPage({super.key});

  @override
  Widget build(BuildContext context) => const StatusScreen(
        icon: Icons.hourglass_disabled_outlined,
        tone: StatusTone.warning,
        title: S.demoExpiredTitle,
        body: S.demoExpiredBody,
        primaryAction: _SignOutButton(filled: true),
        secondaryAction: _SupportButton(),
      );
}

/// The pages, keyed by the location their [StartupDestination] declares.
///
/// One const map rather than ten hand-written `GoRoute`s, for the reason
/// `_publicPages` already gives in the router: the set the redirect must treat
/// as "a place the classifier legitimately sent someone" and the set of routes
/// that exist have to be the *same* list, or a state screen becomes a location
/// the redirect immediately bounces off — an infinite loop, not a bug you see
/// once.
const Map<String, Widget> startupStatusPages = {
  '/session-invalid': SessionInvalidPage(),
  '/session-unsupported': AccessUnsupportedPage(),
  '/access-not-assigned': AccessNotAssignedPage(),
  '/account-suspended': AccountSuspendedPage(),
  '/account-revoked': AccountRevokedPage(),
  '/tenant-suspended': TenantSuspendedPage(),
  '/tenant-deletion-pending': TenantDeletionPendingPage(),
  '/tenant-deleted': TenantDeletedPage(),
  '/verify-email': EmailVerificationPage(),
  '/link-team': LinkTeamPage(),
  '/account-setup': AccountSetupPage(),
  '/demo-expired': DemoExpiredPage(),
};
