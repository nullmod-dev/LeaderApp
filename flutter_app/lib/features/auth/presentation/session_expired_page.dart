import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/strings.dart';
import '_auth_scaffold.dart';

class SessionExpiredPage extends StatelessWidget {
  const SessionExpiredPage({super.key});
  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: S.sessionExpiredTitle,
      subtitle: S.sessionExpiredSub,
      child: Column(children: [
        FilledButton(
          onPressed: () => context.go('/login'),
          child: const Text(S.signIn),
        ),
      ]),
    );
  }
}
