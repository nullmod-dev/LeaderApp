import '../domain/saas_tenant_models.dart';
import '../domain/tenant_lifecycle_models.dart';
import 'widgets/platform_confirmation_dialog.dart';

/// Typed consequence copy for every lifecycle action. Widgets select an
/// action; they do not assemble or weaken its safety language ad hoc.
class TenantLifecycleConfirmation {
  const TenantLifecycleConfirmation({
    required this.action,
    required this.title,
    required this.identity,
    required this.change,
    required this.unchanged,
    required this.confirmLabel,
    required this.severity,
    this.effective,
    this.typedConfirmation,
    this.requiresIrreversibleAcknowledgement = false,
  });

  final TenantLifecycleAction action;
  final String title;
  final String identity;
  final String change;
  final String unchanged;
  final String confirmLabel;
  final PlatformConfirmationSeverity severity;
  final String? effective;
  final String? typedConfirmation;
  final bool requiresIrreversibleAcknowledgement;

  static TenantLifecycleConfirmation forTenant(
    SaasTenant tenant,
    TenantLifecycleAction action,
  ) =>
      switch (action) {
        TenantLifecycleAction.suspend => TenantLifecycleConfirmation(
            action: action,
            title: 'إيقاف وصول الفريق',
            identity: tenant.displayName,
            change:
                'سيُحظر الوصول التشغيلي لكل من المدير الرئيسي والمديرين البسطاء في هذا الفريق.',
            unchanged:
                'تبقى البيانات والاشتراك والخطة والحدود والميزات كما هي، ويمكن إعادة تفعيل الوصول لاحقاً.',
            confirmLabel: 'إيقاف الوصول',
            severity: PlatformConfirmationSeverity.warning,
          ),
        TenantLifecycleAction.reactivate => TenantLifecycleConfirmation(
            action: action,
            title: 'إعادة تفعيل وصول الفريق',
            identity: tenant.displayName,
            change: 'سيعود الوصول التشغيلي إلى الفريق.',
            unchanged:
                'تبقى البيانات كما هي، ولا تتغير حالة الاشتراك أو الميزات أو القدرات أو حدود الخطة.',
            confirmLabel: 'إعادة التفعيل',
            severity: PlatformConfirmationSeverity.normal,
          ),
        TenantLifecycleAction.beginDeletion => TenantLifecycleConfirmation(
            action: action,
            title: 'بدء طلب حذف الفريق',
            identity: tenant.displayName,
            change:
                'سيدخل الفريق حالة انتظار الحذف، وسيُحظر الوصول التشغيلي والتعديلات العادية.',
            unchanged:
                'لن تُحذف البيانات مادياً الآن. الحذف النهائي عملية خادم منفصلة وقد تصبح الاستعادة بعدها مستحيلة.',
            effective:
                'يمكن إلغاء الطلب قبل الموعد فقط، ويحدد الخادم الموعد وفق سياسة المنصة.',
            confirmLabel: 'بدء انتظار الحذف',
            severity: PlatformConfirmationSeverity.destructive,
          ),
        TenantLifecycleAction.cancelDeletion => TenantLifecycleConfirmation(
            action: action,
            title: 'إلغاء طلب الحذف',
            identity: tenant.displayName,
            change: tenant.lifecycle.deletion?.previousStatus ==
                    TenantDeletionRestoreStatus.suspended
                ? 'سيعود الفريق إلى حالة الإيقاف السابقة.'
                : 'سيعود الفريق إلى الحالة النشطة السابقة.',
            unchanged:
                'تبقى حالة الاشتراك والميزات والقدرات والحدود دون تغيير.',
            confirmLabel: 'إلغاء طلب الحذف',
            severity: PlatformConfirmationSeverity.normal,
          ),
        TenantLifecycleAction.finalizeDeletion => TenantLifecycleConfirmation(
            action: action,
            title: 'الحذف النهائي للفريق',
            identity: tenant.displayName,
            change:
                'سيُرسل طلب حذف نهائي إلى الخادم لمعالجة بيانات الفريق وفق سياسة الاحتفاظ. قد تصبح الاستعادة مستحيلة.',
            unchanged:
                'لا يمحو التطبيق التخزين أو النسخ الاحتياطية بنفسه؛ الخادم وحده يقرر وينفذ النتيجة النهائية.',
            effective:
                'سيبقى فقط سجل منصة مختصر محدود وفق سياسة التدقيق والاحتفاظ.',
            confirmLabel: 'طلب الحذف النهائي',
            severity: PlatformConfirmationSeverity.destructive,
            typedConfirmation: tenant.displayName,
            requiresIrreversibleAcknowledgement: true,
          ),
      };
}
