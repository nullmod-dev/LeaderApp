import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings.dart';
import '../data/auth_providers.dart';
import '_auth_scaffold.dart';

class NewDevicePage extends ConsumerWidget {
  const NewDevicePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return AuthScaffold(
      title: S.newDeviceTitle,
      subtitle: S.newDeviceSub,
      showBack: true,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: c.line),
          ),
          child: Column(children: [
            _row(context, Icons.smartphone_rounded, 'iPhone 15 · Safari',
                'دمشق, سوريا'),
            const Divider(height: 20),
            _row(context, Icons.access_time_rounded, 'منذ ٤ دقائق',
                '176.29.xx.xx'),
          ]),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          onPressed: () async {
            await ref
                .read(authRepositoryProvider)
                .confirmNewDevice(itsMe: true);
            if (context.mounted) context.go('/home');
          },
          child: const Text(S.yesItsMe),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          onPressed: () async {
            await ref
                .read(authRepositoryProvider)
                .confirmNewDevice(itsMe: false);
            if (context.mounted) context.go('/login');
          },
          child: const Text(S.notMe),
        ),
      ]),
    );
  }

  Widget _row(BuildContext context, IconData icon, String a, String b) {
    final c = context.c;
    return Row(children: [
      Icon(icon, color: c.ink2, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(a, style: TextStyle(color: c.ink))),
      Text(b, style: TextStyle(color: c.ink3, fontSize: 12)),
    ]);
  }
}
