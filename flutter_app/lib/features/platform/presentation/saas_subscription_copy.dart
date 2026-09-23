import '../../../core/motion/animated_counter.dart';
import '../../../core/widgets/status_chip.dart';
import '../domain/saas_subscription_models.dart';

String subscriptionStatusLabel(SubscriptionStatus status) => switch (status) {
      SubscriptionStatus.trial => 'فترة تجريبية',
      SubscriptionStatus.active => 'اشتراك فعّال',
      SubscriptionStatus.grace => 'فترة سماح',
      SubscriptionStatus.inactive => 'غير فعّال',
    };

StatusKind subscriptionStatusKind(SubscriptionStatus status) =>
    switch (status) {
      SubscriptionStatus.trial => StatusKind.info,
      SubscriptionStatus.active => StatusKind.ok,
      SubscriptionStatus.grace => StatusKind.warn,
      SubscriptionStatus.inactive => StatusKind.muted,
    };

String planLimitLabel(PlanLimitKey key) => switch (key) {
      PlanLimitKey.detachmentGroups => 'مجموعات المفارز',
      PlanLimitKey.detachments => 'المفارز',
      PlanLimitKey.admins => 'المشرفون',
      PlanLimitKey.members => 'الأعضاء',
      PlanLimitKey.workshops => 'ورش العمل',
      PlanLimitKey.storageBytes => 'التخزين',
    };

String formatLimitValue(PlanLimitKey key, int value) =>
    key.isBytes ? formatBytes(value) : toArabicIndic(value.toString());

String formatBytes(int bytes) {
  const gib = 1024 * 1024 * 1024;
  const mib = 1024 * 1024;
  if (bytes >= gib) {
    final value = bytes / gib;
    final text = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
    return '${toArabicIndic(text)} غ.ب';
  }
  return '${toArabicIndic((bytes / mib).round().toString())} م.ب';
}
