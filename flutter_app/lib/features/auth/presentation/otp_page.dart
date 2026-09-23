import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings.dart';
import '../data/auth_providers.dart';
import '_auth_scaffold.dart';
import '../../../core/theme/app_typography.dart';

class OtpPage extends ConsumerStatefulWidget {
  const OtpPage({super.key});
  @override
  ConsumerState<OtpPage> createState() => _S();
}

class _S extends ConsumerState<OtpPage> {
  static const _len = 6;
  final _controllers = List.generate(_len, (_) => TextEditingController());
  final _nodes = List.generate(_len, (_) => FocusNode());
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await ref
        .read(authRepositoryProvider)
        .verifyResetOtp('user@mtm.org', _code);
    if (!mounted) return;
    setState(() => _busy = false);
    r.when(
      success: (_, {stale = false}) => context.push('/new-password'),
      failure: (m, _) => setState(() => _error = m),
      offline: (_) => setState(() => _error = S.offlineTitle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AuthScaffold(
      title: S.otpTitle,
      subtitle: S.otpSub,
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (int i = 0; i < _len; i++)
                  SizedBox(
                    width: 46,
                    height: 56,
                    child: TextField(
                      controller: _controllers[i],
                      focusNode: _nodes[i],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(1),
                      ],
                      style: AppTypography.digits(c.ink, size: 22),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.zero,
                        counterText: '',
                      ),
                      onChanged: (v) {
                        if (v.isNotEmpty && i < _len - 1) {
                          _nodes[i + 1].requestFocus();
                        }
                        if (v.isEmpty && i > 0) _nodes[i - 1].requestFocus();
                        if (_code.length == _len) _submit();
                      },
                    ),
                  ),
              ],
            ),
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
                : const Text(S.confirm),
          ),
        ],
      ),
    );
  }
}
