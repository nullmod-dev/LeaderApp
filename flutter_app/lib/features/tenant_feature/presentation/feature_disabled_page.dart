import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/status_screen.dart';
import '../domain/tenant_feature_models.dart';

class FeatureDisabledPage extends StatelessWidget {
  const FeatureDisabledPage({super.key, required this.feature});

  final TenantFeatureKey? feature;

  static const String routePath = '/feature-disabled';

  static String location(TenantFeatureKey feature) =>
      '$routePath?feature=${feature.wire}';

  @override
  Widget build(BuildContext context) {
    final label =
        feature == null ? 'هذه الميزة' : definitionOf(feature!).arabicLabel;
    return StatusScreen(
      icon: Icons.extension_off_outlined,
      tone: StatusTone.info,
      title: 'هذه الميزة غير مفعلة لهذا الفريق',
      body:
          '$label غير متاحة حاليًا لأعضاء هذا الفريق. لم تُحذف البيانات، ويمكن أن تعود عند إعادة تفعيل الميزة وفق صلاحيات حسابك.',
      primaryAction: FilledButton(
        onPressed: () => context.go('/home'),
        child: const Text('العودة إلى الرئيسية'),
      ),
    );
  }
}
