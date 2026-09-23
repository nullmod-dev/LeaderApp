import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/app_date.dart';
import '../../../core/motion/motion_tokens.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/reading_column.dart';
import '../data/platform_tenant_store.dart';
import '../data/saas_tenant_providers.dart';
import '../domain/platform_audit_models.dart';
import 'platform_audit_copy.dart';
import 'saas_tenant_routes.dart';

Future<void> showPlatformAuditDetail(
  BuildContext context,
  PlatformAuditEvent event,
) async {
  final duration = MediaQuery.of(context).accessibleNavigation ||
          motionSpec(context).isInstant
      ? Duration.zero
      : effectiveDuration(context, MotionTokens.medium);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
    sheetAnimationStyle: AnimationStyle(
      duration: duration,
      reverseDuration: duration,
    ),
    builder: (_) => PlatformAuditDetail(event: event),
  );
}

bool _canOpen(PlatformTenantStore store, PlatformAuditTenantReference tenant) =>
    store.tombstoneById(tenant.id) != null ||
    (!tenant.isDeleted && store.byId(tenant.id) != null);

class PlatformAuditDetail extends ConsumerWidget {
  const PlatformAuditDetail({super.key, required this.event});

  final PlatformAuditEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = event.tenant;
    final store = ref.watch(platformTenantStoreProvider);
    final target = event.target;
    final actor = event.actor;
    final textTheme = Theme.of(context).textTheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                    child: Text('تفاصيل حدث التدقيق',
                        style: textTheme.titleLarge)),
                IconButton(
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ]),
              _Fact('الإجراء', AuditCopy.action(event.action)),
              _Fact('التصنيف', AuditCopy.category(event.category)),
              _Fact(
                'وقت الحدث حسب الجهاز',
                _timestamp(event.occurredAt.toLocal()),
              ),
              _Fact('معرّف الحدث', event.id, technical: true),
              const Divider(),
              _Fact('المنفّذ', AuditCopy.actor(actor)),
              if (actor is PlatformAuditAdministratorActor) ...[
                const _Fact('نوع المنفّذ', 'مسؤول المنصة'),
                _Fact('معرّف المنفّذ', actor.id, technical: true),
              ],
              const Divider(),
              _Fact('المورد المستهدف', AuditCopy.resource(target.type)),
              if (target.type != PlatformAuditTargetResource.unknown) ...[
                if (target.displayName case final String name
                    when name.trim().isNotEmpty)
                  _Fact('اسم المورد', name),
                if (target.id.isNotEmpty)
                  _Fact('معرّف المورد', target.id, technical: true),
              ],
              if (tenant != null) ...[
                _Fact('الفريق المرتبط', tenant.displayName),
                _Fact('معرّف الفريق', tenant.id, technical: true),
                if (_canOpen(store, tenant))
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () {
                        final current = ref.read(platformTenantStoreProvider);
                        if (!_canOpen(current, tenant)) {
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            const SnackBar(
                                content: Text('تفاصيل الفريق غير متاحة')),
                          );
                          return;
                        }
                        final router = GoRouter.of(context);
                        Navigator.of(context).pop();
                        router.go(SaasTenantRoutes.detail(tenant.id));
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: Text(store.tombstoneById(tenant.id) != null
                          ? 'عرض سجل الفريق المحذوف'
                          : 'فتح تفاصيل الفريق'),
                    ),
                  )
                else
                  Text(tenant.isDeleted
                      ? 'فريق محذوف؛ السجل المرجعي غير متاح'
                      : 'تفاصيل الفريق غير متاحة'),
              ],
              const Divider(),
              Text('التغييرات', style: textTheme.titleMedium),
              if (event.changes.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text('لا توجد تغييرات مسجلة لهذا الحدث'),
                )
              else ...[
                const Text(
                    '«غير محدد» تعني أن الحدث لم يتضمن قيمة لهذا الجانب.'),
                for (final change in event.changes)
                  Card(
                    margin: const EdgeInsets.only(top: AppSpacing.md),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(AuditCopy.changeField(change.field),
                              style: textTheme.titleSmall),
                          _Fact('قبل التغيير',
                              AuditCopy.value(change.field, change.before)),
                          _Fact('بعد التغيير',
                              AuditCopy.value(change.field, change.after)),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, {this.technical = false});
  final String label;
  final String value;
  final bool technical;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(value,
                textDirection: technical ? TextDirection.ltr : null,
                textAlign: technical ? TextAlign.right : null,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
}

/// «١٢ أيلول ٢٠٢٦ — ١٤:٣٠».
///
/// An em dash, not ` · `: the separator sat between «٢٠٢٦» and «١٤:٣٠» and is
/// the same mark as the Arabic-Indic zero on either side of it (UI audit
/// P1-11). This is a plain string handed to a label/value field, so the fix is
/// a mark that cannot be a digit rather than a layout.
String _timestamp(DateTime value) {
  return '${AppDate.dayMonthYear(value)} — ${AppDate.time(value)}';
}
