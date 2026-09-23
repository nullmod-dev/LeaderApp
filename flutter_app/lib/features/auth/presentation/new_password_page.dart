import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings.dart';
import '../data/auth_providers.dart';
import '_auth_scaffold.dart';

class NewPasswordPage extends ConsumerStatefulWidget {
  const NewPasswordPage({super.key});
  @override
  ConsumerState<NewPasswordPage> createState() => _S();
}

class _S extends ConsumerState<NewPasswordPage> {
  final _p = TextEditingController();
  final _p2 = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _p.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_p.text != _p2.text) {
      setState(() => _error = 'كلمة المرور غير متطابقة.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await ref.read(authRepositoryProvider).setNewPassword(_p.text);
    if (!mounted) return;
    setState(() => _busy = false);
    r.when(
      success: (_, {stale = false}) => context.go('/login'),
      failure: (m, _) => setState(() => _error = m),
      offline: (_) => setState(() => _error = S.offlineTitle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AuthScaffold(
      title: S.newPasswordTitle,
      subtitle: S.newPasswordSub,
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _p,
            obscureText: true,
            decoration: const InputDecoration(labelText: S.passwordLabel),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _p2,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(_error!, style: TextStyle(color: c.crit, fontSize: 13)),
          ],
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
                : const Text(S.save),
          ),
        ],
      ),
    );
  }
}
