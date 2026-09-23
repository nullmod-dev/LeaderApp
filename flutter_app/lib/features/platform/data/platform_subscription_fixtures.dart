import '../domain/saas_subscription_models.dart';
import '../../../l10n/strings.dart';

const int _gib = 1024 * 1024 * 1024;

/// Small deterministic catalogue. Prices are intentionally absent: this mock
/// proves administrative plan selection, not payment or billing.
final List<SaasPlan> canonicalSaasPlans = List.unmodifiable([
  SaasPlan(
    id: 'mtm_core',
    name: '${S.productNameAr} الأساسية',
    description: 'للفرق الصغيرة ذات التشغيل المحدود.',
    defaultLimits: PlanLimits(const {
      PlanLimitKey.detachmentGroups: 2,
      PlanLimitKey.detachments: 5,
      PlanLimitKey.admins: 3,
      PlanLimitKey.members: 75,
      PlanLimitKey.workshops: 12,
      PlanLimitKey.storageBytes: 5 * _gib,
    }),
  ),
  SaasPlan(
    id: 'mtm_standard',
    name: '${S.productNameAr} القياسية',
    description: 'للفرق النشطة متعددة المفارز.',
    recommended: true,
    defaultLimits: PlanLimits(const {
      PlanLimitKey.detachmentGroups: 5,
      PlanLimitKey.detachments: 15,
      PlanLimitKey.admins: 8,
      PlanLimitKey.members: 300,
      PlanLimitKey.workshops: 40,
      PlanLimitKey.storageBytes: 20 * _gib,
    }),
  ),
  SaasPlan(
    id: 'mtm_advanced',
    name: '${S.productNameAr} المتقدمة',
    description: 'للجهات الكبيرة ذات النطاق التشغيلي الواسع.',
    defaultLimits: PlanLimits(const {
      PlanLimitKey.detachmentGroups: 12,
      PlanLimitKey.detachments: 40,
      PlanLimitKey.admins: 20,
      PlanLimitKey.members: 1000,
      PlanLimitKey.workshops: 120,
      PlanLimitKey.storageBytes: 100 * _gib,
    }),
  ),
]);

SaasPlan? canonicalPlanById(String? id) {
  if (id == null) return null;
  for (final plan in canonicalSaasPlans) {
    if (plan.id == id) return plan;
  }
  return null;
}
