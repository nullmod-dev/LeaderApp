import '../../../core/access/saas_tenant_status.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../core/widgets/status_chip.dart';
import '../domain/tenant_lifecycle_models.dart';
import '../domain/tenant_lifecycle_repository.dart';

String tenantLifecycleStatusLabel(SaasTenantStatus status) => switch (status) {
      SaasTenantStatus.active => 'نشط تشغيلياً',
      SaasTenantStatus.suspended => 'الوصول موقوف',
      SaasTenantStatus.deletionPending => 'الحذف قيد الانتظار',
      SaasTenantStatus.deleted => 'محذوف نهائياً',
    };

String tenantLifecycleStatusSummary(SaasTenantStatus status) =>
    switch (status) {
      SaasTenantStatus.active =>
        'يمكن لمستخدمي الفريق فتح التطبيق التشغيلي وفق ميزاته وصلاحياته وحدوده الحالية.',
      SaasTenantStatus.suspended =>
        'الوصول التشغيلي محظور مؤقتاً، مع بقاء بيانات الفريق واشتراكه وإعداداته كما هي.',
      SaasTenantStatus.deletionPending =>
        'الوصول التشغيلي محظور أثناء انتظار الحذف، ولم تُحذف بيانات الفريق نهائياً بعد.',
      SaasTenantStatus.deleted =>
        'انتهى المورد التشغيلي ولا يوجد مسار عادي لإعادة تفعيله.',
    };

StatusKind tenantLifecycleStatusKind(SaasTenantStatus status) =>
    switch (status) {
      SaasTenantStatus.active => StatusKind.ok,
      SaasTenantStatus.suspended => StatusKind.crit,
      SaasTenantStatus.deletionPending => StatusKind.warn,
      SaasTenantStatus.deleted => StatusKind.crit,
    };

String tenantDeletionRestoreLabel(TenantDeletionRestoreStatus status) =>
    switch (status) {
      TenantDeletionRestoreStatus.active => 'الحالة النشطة السابقة',
      TenantDeletionRestoreStatus.suspended => 'حالة الإيقاف السابقة',
    };

/// Stable day-level context. It intentionally has no timer or background
/// polling; a refresh or an existing provider rebuild reads the injected clock
/// again and recalculates the legal action.
String tenantDeletionRemainingLabel(DateTime now, DateTime scheduledFor) {
  final remaining = scheduledFor.toUtc().difference(now.toUtc());
  if (remaining <= Duration.zero) return 'بلغ موعد الحذف النهائي';
  if (remaining < const Duration(days: 1)) return 'متبقٍ أقل من يوم';

  final days = (remaining.inMinutes / Duration.minutesPerDay).ceil();
  final number = toArabicIndic(days.toString());
  return switch (days) {
    1 => 'متبقٍ يوم واحد',
    2 => 'متبقي يومان',
    >= 3 && <= 10 => 'متبقي $number أيام',
    _ => 'متبقي $number يوماً',
  };
}

String tenantLifecycleSuccessMessage(TenantLifecycleAction action) =>
    switch (action) {
      TenantLifecycleAction.suspend => 'تم إيقاف وصول الفريق.',
      TenantLifecycleAction.reactivate => 'تمت إعادة تفعيل وصول الفريق.',
      TenantLifecycleAction.beginDeletion => 'تمت جدولة حذف الفريق.',
      TenantLifecycleAction.cancelDeletion => 'تم إلغاء طلب الحذف.',
      TenantLifecycleAction.finalizeDeletion =>
        'اكتمل طلب الحذف النهائي، وحُفظ سجل المنصة المختصر.',
    };

/// Safe localized recovery copy. Repository/server messages never reach this
/// surface because they may contain technical or policy-only detail.
String tenantLifecycleProblemMessage(TenantLifecycleProblemCode code) =>
    switch (code) {
      TenantLifecycleProblemCode.tenantNotFound =>
        'لم يعد سجل الفريق متاحاً. حدّث البيانات ثم راجع الحالة الحالية.',
      TenantLifecycleProblemCode.invalidTransition =>
        'لم يعد هذا الإجراء متاحاً في حالة الفريق الحالية. حدّث البيانات وحاول مجدداً.',
      TenantLifecycleProblemCode.invalidReason =>
        'أدخل سبباً إدارياً واضحاً من ١ إلى ٢٨٠ محرفاً.',
      TenantLifecycleProblemCode.staleTenant =>
        'تغيّرت حالة الفريق في مكان آخر. تم تحديث البيانات؛ راجعها قبل أي محاولة جديدة.',
      TenantLifecycleProblemCode.deletionWindowExpired =>
        'انتهت نافذة إلغاء الحذف. تم تحديث الحالة، ويمكن متابعة الحذف النهائي عند توفره.',
      TenantLifecycleProblemCode.deletionNotEffective =>
        'لم يحن موعد الحذف النهائي بعد. راجع الموعد المقرر وحاول بعد بلوغه.',
      TenantLifecycleProblemCode.tenantAlreadyDeleted =>
        'اكتمل حذف الفريق بالفعل، ولا توجد له إجراءات دورة حياة عادية.',
      TenantLifecycleProblemCode.idempotencyConflict =>
        'تعذّر تأكيد العملية لأن حالتها تغيرت. حدّث البيانات وحاول مرة أخرى.',
      TenantLifecycleProblemCode.notPermitted =>
        'لا تسمح جلسة المنصة الحالية بتنفيذ هذا الإجراء.',
    };
