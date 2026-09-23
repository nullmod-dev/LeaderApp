import '../domain/platform_audit_models.dart';
import '../../../core/motion/animated_counter.dart' show toArabicIndic;
import '../../../l10n/strings.dart';

/// Presentation-only vocabulary. Unknown wire values never become UI copy.
abstract final class AuditCopy {
  static String action(PlatformAuditAction value) => switch (value) {
        PlatformAuditAction.tenantRegistered => 'تسجيل فريق',
        PlatformAuditAction.subscriptionActivated => 'تفعيل الاشتراك',
        PlatformAuditAction.trialExtended => 'تمديد التجربة',
        PlatformAuditAction.trialEnded => 'إنهاء التجربة',
        PlatformAuditAction.subscriptionMovedToGrace =>
          'نقل الاشتراك إلى فترة السماح',
        PlatformAuditAction.planChanged => 'تغيير الخطة',
        PlatformAuditAction.limitOverrideChanged => 'تغيير استثناء الحد',
        PlatformAuditAction.featureFlagChanged => 'تغيير تفعيل الميزة',
        PlatformAuditAction.tenantSuspended => 'تعليق الفريق',
        PlatformAuditAction.tenantReactivated => 'إعادة تفعيل الفريق',
        PlatformAuditAction.deletionRequested => 'طلب حذف الفريق',
        PlatformAuditAction.deletionCancelled => 'إلغاء حذف الفريق',
        PlatformAuditAction.deletionFinalized => 'الحذف النهائي للفريق',
        PlatformAuditAction.breakGlassActivated => 'تفعيل الوصول الطارئ',
        PlatformAuditAction.breakGlassEnded => 'إنهاء الوصول الطارئ',
        PlatformAuditAction.breakGlassExpired => 'انتهاء مدة الوصول الطارئ',
        PlatformAuditAction.breakGlassRevoked => 'سحب الوصول الطارئ',
        PlatformAuditAction.mainAdminSetupResent =>
          'إعادة إرسال دعوة إعداد المدير الرئيسي',
        PlatformAuditAction.mainAdminSuspended => 'إيقاف حساب المدير الرئيسي',
        PlatformAuditAction.mainAdminReactivated =>
          'إعادة تفعيل حساب المدير الرئيسي',
        PlatformAuditAction.mainAdminReplacementStarted =>
          'بدء استبدال المدير الرئيسي',
        PlatformAuditAction.mainAdminReplacementCancelled =>
          'إلغاء استبدال المدير الرئيسي',
        PlatformAuditAction.mainAdminReplaced =>
          'اكتمال استبدال المدير الرئيسي',
        PlatformAuditAction.customerDemoPolicyChanged =>
          'تغيير سياسة التجربة',
        PlatformAuditAction.customerDemoSessionStarted =>
          'بدء جلسة تجريبية',
        PlatformAuditAction.customerDemoSessionTerminated =>
          'إنهاء جلسة تجريبية',
        PlatformAuditAction.customerDemoSessionExpired =>
          'انتهاء مدة جلسة تجريبية',
        PlatformAuditAction.unknown => 'إجراء غير معروف',
      };

  static String category(PlatformAuditCategory value) => switch (value) {
        PlatformAuditCategory.tenantManagement => 'إدارة الفرق',
        PlatformAuditCategory.subscription => 'الاشتراكات',
        PlatformAuditCategory.entitlement => 'الميزات والحدود',
        PlatformAuditCategory.lifecycle => 'دورة حياة الفريق',
        PlatformAuditCategory.emergencyAccess => 'الوصول الطارئ',
        PlatformAuditCategory.accountManagement => 'إدارة الحسابات',
        PlatformAuditCategory.customerDemo => 'الحسابات التجريبية',
        PlatformAuditCategory.unknown => 'تصنيف غير معروف',
      };

  static String actor(PlatformAuditActor value) => switch (value) {
        PlatformAuditAdministratorActor(:final displayName) => displayName,
        PlatformAuditSystemActor() => 'النظام',
        PlatformAuditUnknownActor() => 'منفّذ غير معروف',
      };

  static String resource(PlatformAuditTargetResource value) => switch (value) {
        PlatformAuditTargetResource.tenant => 'الفريق',
        PlatformAuditTargetResource.subscription => 'الاشتراك',
        PlatformAuditTargetResource.planAssignment => 'الخطة المعيّنة',
        PlatformAuditTargetResource.tenantFeature => 'ميزة الفريق',
        PlatformAuditTargetResource.tenantLimit => 'حد الفريق',
        PlatformAuditTargetResource.tenantLifecycle => 'دورة حياة الفريق',
        PlatformAuditTargetResource.breakGlassGrant => 'منحة الوصول الطارئ',
        PlatformAuditTargetResource.mainAdminAccount => 'حساب المدير الرئيسي',
        PlatformAuditTargetResource.customerDemoPolicy => 'سياسة التجربة',
        PlatformAuditTargetResource.customerDemoSession => 'الجلسة التجريبية',
        PlatformAuditTargetResource.unknown => 'مورد غير معروف',
      };

  static String changeField(PlatformAuditChangeField value) => switch (value) {
        PlatformAuditChangeField.lifecycleStatus => 'حالة الفريق',
        PlatformAuditChangeField.subscriptionStatus => 'حالة الاشتراك',
        PlatformAuditChangeField.planAssignment => 'الخطة المعيّنة',
        PlatformAuditChangeField.featureEnabled => 'تفعيل الميزة',
        PlatformAuditChangeField.limitOverride => 'استثناء الحد',
        PlatformAuditChangeField.accountStatus => 'حالة حساب المدير الرئيسي',
        PlatformAuditChangeField.loginIdentity => 'هوية تسجيل الدخول المحجوبة',
        PlatformAuditChangeField.demoAvailability => 'إتاحة التجربة',
        PlatformAuditChangeField.demoDefaultDuration =>
          'المدة الافتراضية للتجربة',
        PlatformAuditChangeField.unknown => 'حقل غير معروف',
      };

  static String value(PlatformAuditChangeField field, PlatformAuditValue? raw) {
    final safe = PlatformAuditSafetyPolicy.sanitizeValue(field, raw);
    return switch (safe) {
      null => 'غير محدد',
      PlatformAuditRedactedValue() => 'قيمة محجوبة',
      PlatformAuditBoolValue(:final value) => value ? 'مفعّل' : 'معطّل',
      // Arabic-Indic, like every other figure in the product. A limit
      // override used to read «استثناء الحد: 10 ← 20» under an Arabic-Indic
      // timestamp — two numeral systems in one row (UI audit P2).
      PlatformAuditIntegerValue(:final value) => toArabicIndic('$value'),
      PlatformAuditTextValue(:final value) => _text(field, value),
    };
  }

  static String _text(PlatformAuditChangeField field, String value) =>
      switch ((field, value)) {
        (PlatformAuditChangeField.lifecycleStatus, 'active') => 'نشط',
        (PlatformAuditChangeField.lifecycleStatus, 'suspended') => 'معلّق',
        (PlatformAuditChangeField.lifecycleStatus, 'deletion_pending') =>
          'بانتظار الحذف',
        (PlatformAuditChangeField.lifecycleStatus, 'deleted') => 'محذوف',
        (PlatformAuditChangeField.subscriptionStatus, 'trial') => 'تجريبي',
        (PlatformAuditChangeField.subscriptionStatus, 'active') => 'نشط',
        (PlatformAuditChangeField.subscriptionStatus, 'grace') => 'فترة السماح',
        (PlatformAuditChangeField.subscriptionStatus, 'inactive') => 'غير نشط',
        (PlatformAuditChangeField.accountStatus, 'pending_setup') =>
          'بانتظار الإعداد',
        (PlatformAuditChangeField.accountStatus, 'active') => 'نشط',
        (PlatformAuditChangeField.accountStatus, 'suspended') => 'موقوف',
        (PlatformAuditChangeField.accountStatus, 'revoked') => 'ملغى',
        // Names match the established platform plan catalogue.
        (PlatformAuditChangeField.planAssignment, 'mtm_core') =>
          '${S.productNameAr} الأساسية',
        (PlatformAuditChangeField.planAssignment, 'mtm_standard') =>
          '${S.productNameAr} القياسية',
        (PlatformAuditChangeField.planAssignment, 'mtm_advanced') =>
          '${S.productNameAr} المتقدمة',
        _ => 'قيمة غير معروفة',
      };
}
