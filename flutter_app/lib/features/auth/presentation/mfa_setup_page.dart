import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/motion/animated_counter.dart';
import '../../../core/problem/problem.dart';
import '../../../core/problem/problem_presentation.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../l10n/strings.dart';
import '../data/auth_providers.dart';
import '../domain/auth_models.dart';
import '_auth_scaffold.dart';
import '../../../core/theme/app_typography.dart';

/// The setup payload, fetched once per entry to this screen.
///
/// Kept as the repository's own [Result] rather than being thrown into an
/// `AsyncError`: the old shape put the server's message on screen through
/// `e.toString()`, which is both a raw wire string dressed as product copy
/// and — on a setup call that carries a TOTP secret — the last place that
/// should be echoing whatever the server said. The failure is now resolved
/// through the shared problem pipeline like every other call in the app.
final _mfaSetupProvider = FutureProvider<Result<MfaSetupData>>((ref) async {
  return ref.read(authRepositoryProvider).beginMfaSetup();
});

class MfaSetupPage extends ConsumerWidget {
  const MfaSetupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_mfaSetupProvider);
    final c = context.c;
    return AuthScaffold(
      title: S.mfaSetupTitle,
      subtitle: S.mfaSetupSub,
      showBack: true,
      child: async.when(
        loading: () => Column(children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AppRadii.xl),
              border: Border.all(color: c.line),
            ),
            child: const SizedBox(
              height: 200,
              width: 200,
              child: Center(child: Skeleton(width: 200, height: 200)),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Skeleton(width: 200, height: 14),
        ]),
        // The provider returns a `Result` and no longer throws, so this is
        // only reached by an unexpected exception. Retry is offered anyway —
        // a dead end on the setup screen leaves no way forward at all.
        error: (_, __) => _SetupProblem(
          view: ProblemView.fallback,
          showRetry: true,
          onRetry: () => ref.invalidate(_mfaSetupProvider),
        ),
        data: (result) => result.when(
          success: (data, {stale = false}) => _Setup(data: data),
          failure: (message, code) => _SetupProblem(
            view: resolveProblem(Problem.of(
              ProblemCode.parse(code),
              rawCode: code,
              detail: message,
            )),
            onRetry: () => ref.invalidate(_mfaSetupProvider),
          ),
          // A setup secret is issued by the server; there is nothing to show
          // and nothing to cache, so offline is a plain "not now".
          offline: (_) => _SetupProblem(
            view: resolveProblem(Problem.of(ProblemCode.offline)),
            onRetry: () => ref.invalidate(_mfaSetupProvider),
          ),
        ),
      ),
    );
  }
}

class _Setup extends StatelessWidget {
  const _Setup({required this.data});
  final MfaSetupData data;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.xl),
            border: Border.all(color: c.line),
          ),
          child: Center(
            child: QrImageView(
              data: data.otpauthUrl,
              size: 220,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _Field(
          label: S.mfaManualSecret,
          value: data.manualSecret,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(S.mfaBackupCodesTitle, style: t.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(S.mfaBackupCodesSub, style: t.bodyMedium?.copyWith(color: c.ink3)),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 3.2,
                children: [
                  for (final code in data.backupCodes)
                    Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.surface2,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: Text(
                        toArabicIndic(code),
                        style: AppTypography.digits(c.ink, letterSpacing: 1),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: data.backupCodes.join('\n')));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text(S.copied)));
                  }
                },
                label: const Text(S.copy),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          // Where "continue" leads depends on how this screen was reached.
          // Pushed from the sign-in challenge, or from the Security screen of
          // an already-authenticated admin, the way on is back where they
          // came from; only a cold entry with nothing beneath it falls
          // through to the challenge. Going to `/mfa-challenge`
          // unconditionally used to drop an authenticated admin onto a
          // pre-session screen.
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/mfa-challenge'),
          child: const Text('متابعة'),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: c.line),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: c.ink3, fontSize: 11)),
              const SizedBox(height: 4),
              Text(value,
                  style:
                      AppTypography.digits(c.ink, size: 15, letterSpacing: 1)),
            ],
          ),
        ),
        IconButton(
          tooltip: S.copy,
          icon: const Icon(Icons.copy_rounded, size: 18),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text(S.copied)));
            }
          },
        ),
      ]),
    );
  }
}

/// A failed setup call, in the app's own words.
class _SetupProblem extends StatelessWidget {
  const _SetupProblem({
    required this.view,
    required this.onRetry,
    this.showRetry,
  });

  final ProblemView view;
  final VoidCallback onRetry;

  /// Defaults to the resolved problem's own verdict.
  final bool? showRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(view.title, style: t.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.xs),
        Text(
          view.message,
          style: t.bodyMedium?.copyWith(color: c.ink3),
          textAlign: TextAlign.center,
        ),
        if (showRetry ?? view.retryable) ...[
          const SizedBox(height: AppSpacing.xl),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(S.retry),
          ),
        ],
      ],
    );
  }
}
