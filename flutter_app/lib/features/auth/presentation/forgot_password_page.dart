import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings.dart';
import '../data/auth_providers.dart';
import '_auth_scaffold.dart';

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});
  @override
  ConsumerState<ForgotPasswordPage> createState() => _S();
}

class _S extends ConsumerState<ForgotPasswordPage> {
  final _email = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final r = await ref
        .read(authRepositoryProvider)
        .requestPasswordReset(_email.text);
    if (!mounted) return;
    setState(() => _busy = false);
    r.when(
      success: (_, {stale = false}) => context.push('/otp'),
      // Never render backend text here: it can reveal whether the address
      // exists or which provider owns it. Only a generic service failure is
      // safe before authentication.
      failure: (_, __) => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(S.onboardingTemporaryFailure))),
      offline: (_) => ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(S.offlineTitle))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AuthScaffold(
      title: S.forgotTitle,
      subtitle: S.forgotSub,
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _email,
            readOnly: _busy,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: S.emailLabel),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: c.primaryInk),
                  )
                : const Text(S.next),
          ),
        ],
      ),
    );
  }
}
