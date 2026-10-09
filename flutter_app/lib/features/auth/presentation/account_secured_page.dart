import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/status_screen.dart';
import '../../../l10n/strings.dart';

/// `/account-secured` — after a trusted device answered "No" to a new one.
///
/// The server has already blocked that device and ended every session of the
/// account, this phone's included, so this page is reached signed out. An
/// account with a password goes on to the existing reset flow (`/forgot`):
/// the password is presumed known to someone else, and the server refuses it
/// until it is reset. A Google-only account has no password to reset; it
/// signs in again.
class AccountSecuredPage extends StatelessWidget {
  const AccountSecuredPage({super.key});

  static const location = '/account-secured';

  @override
  Widget build(BuildContext context) {
    final reset = GoRouterState.of(context).uri.queryParameters['reset'] != '0';
    return StatusScreen(
      icon: Icons.shield_outlined,
      tone: StatusTone.info,
      title: S.accountSecuredTitle,
      body: reset ? S.accountSecuredPasswordBody : S.accountSecuredGoogleBody,
      primaryAction: FilledButton(
        key: const Key('account-secured-next'),
        onPressed: () => context.go(reset ? '/forgot' : '/login'),
        child: Text(reset ? S.accountSecuredReset : S.login),
      ),
    );
  }
}
