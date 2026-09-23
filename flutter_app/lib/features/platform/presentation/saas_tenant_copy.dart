import 'package:flutter/material.dart';

import '../../../core/format/app_date.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../domain/saas_tenant_models.dart';
import '../domain/saas_subscription_models.dart';
import '../domain/saas_tenant_validation.dart';

/// The Arabic surface of the `SaasTenant` domain, in one place.
///
/// Every enum in `saas_tenant_models.dart` is a wire value; nothing there
/// carries a label. This file is where each one becomes a word, so a status
/// reads the same on the list row, the filter chip, the detail header and the
/// history line — the drift that a per-screen `switch` produces is what it
/// exists to prevent.

/// «٨ فرق», «فريق واحد», «فريقان» — the Arabic plural, not a count glued to
/// a fixed singular.
///
/// Arabic counts its first two separately and then splits few (3–10) from
/// many (11+); `' فريق'` after every number produced «٨ فريق», which is
/// wrong. The same product already does this correctly for days, hours and
/// minutes in `PlatformDemoCopy`, so the rule is stated the same way here.
String tenantResultCount(int n) => switch (n) {
      0 => 'لا فرق',
      1 => 'فريق واحد',
      2 => 'فريقان',
      <= 10 => '${toArabicIndic('$n')} فرق',
      _ => '${toArabicIndic('$n')} فريقا',
    };

String tenantStatusLabel(SaasTenantListStatus status) => switch (status) {
      SaasTenantListStatus.trial => S.platformTenantStatusTrial,
      SaasTenantListStatus.active => S.platformTenantStatusActive,
      SaasTenantListStatus.grace => S.platformTenantStatusGrace,
      SaasTenantListStatus.inactive => 'اشتراك غير فعّال',
      SaasTenantListStatus.suspended => S.platformTenantStatusSuspended,
      SaasTenantListStatus.deletionPending => 'الحذف معلّق',
      SaasTenantListStatus.deleted => 'محذوف',
    };

/// The status chip's kind.
///
/// Grace is a warning and suspension is critical because those are the two an
/// operator has to act on; a trial is informational and an active subscription
/// is the healthy case. The chip carries a *word* as well as a colour, so none
/// of this is colour-only state.
StatusKind tenantStatusKind(SaasTenantListStatus status) => switch (status) {
      SaasTenantListStatus.trial => StatusKind.info,
      SaasTenantListStatus.active => StatusKind.ok,
      SaasTenantListStatus.grace => StatusKind.warn,
      SaasTenantListStatus.inactive => StatusKind.muted,
      SaasTenantListStatus.suspended => StatusKind.crit,
      SaasTenantListStatus.deletionPending => StatusKind.warn,
      SaasTenantListStatus.deleted => StatusKind.crit,
    };

/// The short filter word. Deliberately shorter than [tenantStatusLabel]; the
/// horizontally scrolling chip row remains usable as lifecycle filters grow.
String tenantStatusFilterLabel(SaasTenantListStatus status) => switch (status) {
      SaasTenantListStatus.trial => S.platformTenantsFilterTrial,
      SaasTenantListStatus.active => S.platformTenantsFilterActive,
      SaasTenantListStatus.grace => S.platformTenantsFilterGrace,
      SaasTenantListStatus.inactive => 'غير فعّال',
      SaasTenantListStatus.suspended => S.platformTenantsFilterSuspended,
      SaasTenantListStatus.deletionPending => 'حذف معلّق',
      SaasTenantListStatus.deleted => 'محذوف',
    };

/// The one subscription date that matters in the tenant's current state,
/// already labelled — or `null` when the state has none, which is a real case
/// (a suspended tenant renews nothing).
String? tenantSubscriptionLine(SaasTenant tenant) {
  final date = tenant.subscription.relevantDate;
  if (date == null) return null;
  final prefix = switch (tenant.subscription.status) {
    SubscriptionStatus.trial => S.platformTenantTrialEnds,
    SubscriptionStatus.active => S.platformTenantRenews,
    SubscriptionStatus.grace => S.platformTenantGraceEnds,
    SubscriptionStatus.inactive => '',
  };
  return '$prefix${AppDate.dayMonth(date.toLocal())}';
}

String tenantProvisioningLabel(MainAdminProvisioning provisioning) =>
    switch (provisioning) {
      MainAdminProvisioning.pendingSetup => S.platformTenantAdminPending,
      MainAdminProvisioning.active => S.platformTenantAdminActive,
    };

String tenantEventLabel(SaasTenantEventType type) => switch (type) {
      SaasTenantEventType.tenantCreated => S.platformTenantEventCreated,
      SaasTenantEventType.trialStarted => S.platformTenantEventTrialStarted,
      SaasTenantEventType.trialEnded => S.platformTenantEventTrialEnded,
      SaasTenantEventType.trialExtended => 'تمديد الفترة التجريبية',
      SaasTenantEventType.subscriptionActivated =>
        S.platformTenantEventActivated,
      SaasTenantEventType.movedToGrace => S.platformTenantEventGrace,
      SaasTenantEventType.planChanged => 'تغيير الخطة',
      SaasTenantEventType.limitOverrideChanged => 'تعديل حد مخصص',
      SaasTenantEventType.tenantSuspended => S.platformTenantEventSuspended,
      SaasTenantEventType.tenantReactivated => 'إعادة تفعيل وصول الفريق',
      SaasTenantEventType.deletionRequested => 'طلب الحذف النهائي',
      SaasTenantEventType.deletionCancelled => 'إلغاء طلب الحذف',
      SaasTenantEventType.tenantDeleted => 'اكتمال الحذف النهائي',
    };

String tenantFieldErrorLabel(SaasTenantFieldError error) => switch (error) {
      SaasTenantFieldError.required => S.platformTenantFieldRequired,
      SaasTenantFieldError.tooLong => S.platformTenantFieldTooLong,
      SaasTenantFieldError.invalidEmail => S.platformTenantFieldEmail,
      SaasTenantFieldError.invalidTeamCode => S.platformTenantFieldCode,
      SaasTenantFieldError.duplicateTeamCode => S.platformTenantCodeTaken,
    };

/// `٧ غ.ب` / `٨٨٠ م.ب` — whole units, Arabic-Indic digits.
///
/// Rounded to a whole unit on purpose: a control plane wants the order of
/// magnitude, and a decimal place here is precision the figure does not have.
String tenantBytesLabel(int bytes) {
  const gib = 1024 * 1024 * 1024;
  const mib = 1024 * 1024;
  if (bytes >= gib) {
    return '${toArabicIndic((bytes ~/ gib).toString())}'
        '${S.platformOverviewGigabyte}';
  }
  return '${toArabicIndic((bytes ~/ mib).toString())}'
      '${S.platformTenantMegabyte}';
}

/// A technical value — an email, a Team Code, an id — inside the RTL UI.
///
/// **Two things at once, and both are needed.** The `Directionality` override
/// makes the string lay out left-to-right, so `salma@hilal-medical.org` does
/// not have its `.org` pushed to the wrong end by the surrounding Arabic. The
/// `SelectableText` makes it copyable, because the operational use of these
/// values is to paste them into a support ticket or a mail client — a value an
/// operator has to retype by eye is a value that gets retyped wrong.
class TechnicalText extends StatelessWidget {
  const TechnicalText(
    this.value, {
    super.key,
    this.style,
    this.tabular = false,
  });

  final String value;
  final TextStyle? style;

  /// Equal-width digit cells. On for a Team Code, off for an email.
  final bool tabular;

  @override
  Widget build(BuildContext context) {
    final base = style ??
        Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.c.ink);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SelectableText(
        value,
        textAlign: TextAlign.start,
        style: tabular
            ? (base ?? const TextStyle())
                .copyWith(fontFeatures: AppTypography.tabular)
            : base,
      ),
    );
  }
}
