import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../../l10n/strings.dart';

class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    this.title = S.errTitle,
    this.body = S.errGeneric,
    required this.onRetry,
  });

  final String title;
  final String body;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: c.critTint,
                borderRadius: BorderRadius.circular(AppRadii.xl),
              ),
              child: Icon(Icons.error_outline_rounded, size: 30, color: c.crit),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: t.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xs),
            Text(
              body,
              style: t.bodyMedium?.copyWith(color: c.ink3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(S.retry),
            ),
          ],
        ),
      ),
    );
  }
}
