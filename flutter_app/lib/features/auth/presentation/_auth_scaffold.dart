import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings.dart';

/// Shared scaffold for auth screens: keeps them visually distinct from the
/// signed-in shell (no bottom nav, wider top spacing, single-column form).
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.showBack = false,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: showBack
          ? AppBar(
              leading: IconButton(
                tooltip: S.back,
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsetsDirectional.fromSTEB(
            AppSpacing.xl,
            AppSpacing.xxl,
            AppSpacing.xl,
            AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: c.primaryTint,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
                child: Icon(Icons.health_and_safety_rounded,
                    color: c.primary, size: 30),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(title, style: t.headlineMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(subtitle, style: t.bodyMedium?.copyWith(color: c.ink3)),
              const SizedBox(height: AppSpacing.xxl),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
