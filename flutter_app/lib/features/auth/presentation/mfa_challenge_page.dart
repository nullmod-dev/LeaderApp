import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/problem/problem.dart';
import '../../../core/problem/problem_presentation.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings.dart';
import '../data/auth_providers.dart';
import '_auth_scaffold.dart';
import '../../../core/theme/app_typography.dart';

class MfaChallengePage extends ConsumerStatefulWidget {
  const MfaChallengePage({super.key});

  @override
  ConsumerState<MfaChallengePage> createState() => _MfaChallengePageState();
}

class _MfaChallengePageState extends ConsumerState<MfaChallengePage> {
  static const int _len = 6;
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _nodes;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_len, (_) => TextEditingController());
    _nodes = List.generate(_len, (_) => FocusNode());
  }

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
    // The last digit typed submits automatically, so a correction made while
    // the first request is still in flight would fire a second verify. The
    // disabled button alone does not cover that path.
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await ref.read(authRepositoryProvider).verifyMfa(_code);
    if (!mounted) return;
    r.when(
      success: (_, {stale = false}) {
        setState(() => _busy = false);
        context.go('/home');
      },
      failure: (m, code) {
        final parsed = ProblemCode.parse(code);
        setState(() {
          _busy = false;
          // Never the server's own text. A rejected code is a `validation`
          // in the contract's vocabulary, and the useful thing to say about
          // it is that the code was wrong — not the generic field message.
          // Everything else gets the app's resolved copy for that code.
          _error = switch (parsed) {
            null || ProblemCode.validation => S.mfaCodeRejected,
            _ => resolveProblem(
                Problem.of(parsed, rawCode: code, detail: m),
              ).message,
          };
        });
      },
      offline: (_) => setState(() {
        _busy = false;
        _error = S.offlineTitle;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AuthScaffold(
      title: S.mfaChallengeTitle,
      subtitle: S.mfaChallengeSub,
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
                      decoration: InputDecoration(
                        contentPadding: EdgeInsets.zero,
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          borderSide: BorderSide(color: c.line2),
                        ),
                      ),
                      onChanged: (v) {
                        if (v.isNotEmpty && i < _len - 1) {
                          _nodes[i + 1].requestFocus();
                        }
                        if (v.isEmpty && i > 0) {
                          _nodes[i - 1].requestFocus();
                        }
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
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onPressed: () => context.push('/mfa-setup'),
            child: const Text('لم أُعدَّه بعد — تفعيل التحقق بخطوتين'),
          ),
        ],
      ),
    );
  }
}
