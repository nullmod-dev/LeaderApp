import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/access/saas_tenant_status.dart';
import 'package:go_router/go_router.dart';

import '../../../core/env/build_mode.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings.dart';
import '../data/auth_providers.dart';
import '../domain/session_access.dart';

/// **DEVELOPMENT ONLY.** Forces a session lifecycle state so its screen can be
/// looked at.
///
/// The problem it answers (`§40` of the Point 3 brief): the classifier can
/// reach nine user-visible states, and *no backend or mock in this build
/// produces any of them*, so without a seam they would exist only inside
/// tests. Adding six more login personas was the alternative and it would have
/// been wrong — a persona is a development *identity*, and a suspension is a
/// server fact about an account, so folding them together would teach the app
/// a relationship the product does not have.
///
/// It writes `sessionAccessOverrideProvider` and pops. The router's
/// `refreshListenable` sees the change and re-runs the classifier, which sends
/// the app to whichever state screen the choice implies — through the real
/// decision path, not by navigating to the screen directly, so what is being
/// inspected is the routing as much as the layout.
///
/// **Unreachable in a shipping build.** [location] is only registered when
/// [demoAccountsAllowed] is true, and that constant is `const false` outside
/// debug — so the route does not exist, this widget is tree-shaken, and the
/// override it writes stays `null` forever.
class DevSessionStatesPage extends ConsumerWidget {
  const DevSessionStatesPage({super.key});

  static const String location = '/dev/session-states';

  /// Not `const`: the three forward-compatibility rows below are built by a
  /// factory constructor, and a list is only const when every element is.
  static final List<(String, SessionAccess?)> _choices = [
    (S.devStatesNormal, null),
    (
      S.devStatesAccountSuspended,
      const SessionAccess(account: AccountStatus.suspended)
    ),
    (
      S.devStatesAccountRevoked,
      const SessionAccess(account: AccountStatus.revoked)
    ),
    (
      S.devStatesPendingSetup,
      const SessionAccess(account: AccountStatus.pendingSetup)
    ),
    (
      S.devStatesTenantSuspended,
      const SessionAccess(tenant: SaasTenantStatus.suspended)
    ),
    (
      'الفريق بانتظار الحذف',
      const SessionAccess(tenant: SaasTenantStatus.deletionPending)
    ),
    (
      S.devStatesTenantDeleted,
      const SessionAccess(tenant: SaasTenantStatus.deleted)
    ),
    (S.devStatesDemoActive, const SessionAccess(demo: DemoMode.active)),
    (S.devStatesDemoExpired, const SessionAccess(demo: DemoMode.expired)),
    // The forward-compatibility states (Point 3 follow-up). Each one is what a
    // *future* backend sends to a build that predates it: a real value in a
    // real gating field, spelled in a way this version has never parsed. They
    // are here for the same reason the eight above are — nothing produces them
    // yet, and a state nobody can look at is a state nobody checks.
    (
      S.devStatesUnknownAccount,
      SessionAccess.unsupportedValue(
        AccessLifecycleField.accountStatus,
        'locked',
      )
    ),
    (
      S.devStatesUnknownTenant,
      SessionAccess.unsupportedValue(
        AccessLifecycleField.tenantStatus,
        'archived',
      )
    ),
    (
      S.devStatesUnknownDemo,
      SessionAccess.unsupportedValue(
        AccessLifecycleField.demoMode,
        'read_only',
      )
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    final current = ref.watch(sessionAccessOverrideProvider);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text(S.devStatesTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(
              S.devStatesBody,
              style: t.bodySmall?.copyWith(color: c.ink3, height: 1.6),
            ),
            const SizedBox(height: AppSpacing.xl),
            for (final (label, access) in _choices)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: OutlinedButton(
                  onPressed: () {
                    ref.read(sessionAccessOverrideProvider.notifier).state =
                        access;
                    // Leave the inspector; the classifier decides where to.
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/home');
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    alignment: AlignmentDirectional.centerStart,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    foregroundColor: current == access ? c.primary : c.ink,
                    side: BorderSide(
                      color: current == access ? c.primary : c.line,
                    ),
                  ),
                  child: Row(children: [
                    Expanded(child: Text(label)),
                    if (current == access)
                      Icon(Icons.check_rounded, size: 18, color: c.primary),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
