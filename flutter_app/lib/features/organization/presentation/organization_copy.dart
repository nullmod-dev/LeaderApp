import 'package:flutter/material.dart';

import '../../../core/format/app_date.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../../platform/presentation/saas_subscription_copy.dart'
    show formatBytes;
import '../domain/organization_models.dart';

/// Every rendered word of Point 15 for a typed value, in one place. An
/// unknown value always has its own honest label; none falls through to a
/// neighbouring known one.
abstract final class OrganizationCopy {
  /// The organisation's support reference, from its tenant id.
  ///
  /// The tenant id is a control-plane slug — `saas_hilal`. Showing it to a
  /// **tenant administrator** labelled «معرّف المؤسسة» put an internal
  /// identifier on a customer screen (UI audit P1-12), and «saas_» is a
  /// business model, not something a customer has a use for.
  ///
  /// The underlying identifier is unchanged — nothing in the domain, the
  /// router or the wire sees this — and the distinctive part is preserved
  /// verbatim, so it is still the thing support searches for. What changes is
  /// that it now *reads* as a reference number: `saas_hilal` → `HILAL`,
  /// `saas_wadi_2` → `WADI-2`.
  static String supportReference(String tenantId) {
    var value = tenantId.trim();
    const prefix = 'saas_';
    if (value.toLowerCase().startsWith(prefix)) {
      value = value.substring(prefix.length);
    }
    // An id that was *only* the prefix has nothing distinctive left; showing
    // the raw value is better than showing an empty field.
    if (value.isEmpty) value = tenantId.trim();
    return value.replaceAll('_', '-').toUpperCase();
  }

  static String access(SaasTenantStatus? status) => switch (status) {
        SaasTenantStatus.active => S.orgAccessActive,
        SaasTenantStatus.suspended => S.orgAccessSuspended,
        SaasTenantStatus.deletionPending => S.orgAccessDeletionPending,
        SaasTenantStatus.deleted => S.orgAccessDeleted,
        null => S.orgAccessUnknown,
      };

  /// Never red: nothing on these screens is an error the viewer caused or
  /// can fix, and text carries the meaning either way.
  static StatusKind accessKind(SaasTenantStatus? status) => switch (status) {
        SaasTenantStatus.active => StatusKind.ok,
        SaasTenantStatus.suspended ||
        SaasTenantStatus.deletionPending =>
          StatusKind.warn,
        SaasTenantStatus.deleted || null => StatusKind.muted,
      };

  static IconData accessIcon(SaasTenantStatus? status) => switch (status) {
        SaasTenantStatus.active => Icons.verified_outlined,
        SaasTenantStatus.suspended => Icons.pause_circle_outline_rounded,
        SaasTenantStatus.deletionPending => Icons.schedule_rounded,
        SaasTenantStatus.deleted => Icons.block_rounded,
        null => Icons.help_outline_rounded,
      };

  static String subscription(SubscriptionStatus? status) => switch (status) {
        SubscriptionStatus.trial => S.orgSubscriptionTrial,
        SubscriptionStatus.active => S.orgSubscriptionActive,
        SubscriptionStatus.grace => S.orgSubscriptionGrace,
        SubscriptionStatus.inactive => S.orgSubscriptionInactive,
        null => S.orgSubscriptionUnknown,
      };

  static StatusKind subscriptionKind(SubscriptionStatus? status) =>
      switch (status) {
        SubscriptionStatus.active => StatusKind.ok,
        SubscriptionStatus.trial => StatusKind.info,
        SubscriptionStatus.grace => StatusKind.warn,
        SubscriptionStatus.inactive || null => StatusKind.muted,
      };

  static IconData subscriptionIcon(SubscriptionStatus? status) =>
      switch (status) {
        SubscriptionStatus.active => Icons.check_circle_outline_rounded,
        SubscriptionStatus.trial => Icons.hourglass_top_rounded,
        SubscriptionStatus.grace => Icons.timelapse_rounded,
        SubscriptionStatus.inactive => Icons.remove_circle_outline_rounded,
        null => Icons.help_outline_rounded,
      };

  /// The label of the one date [status] carries, or null.
  static String? subscriptionDateLabel(SubscriptionStatus? status) =>
      switch (status) {
        SubscriptionStatus.trial => S.planTrialEnds,
        SubscriptionStatus.active => S.planRenews,
        SubscriptionStatus.grace => S.planGraceEnds,
        SubscriptionStatus.inactive || null => null,
      };

  static String? subscriptionNote(SubscriptionStatus? status) =>
      switch (status) {
        SubscriptionStatus.grace => S.planGraceNote,
        SubscriptionStatus.inactive => S.planInactiveNote,
        null => S.planStatusUnknownNote,
        SubscriptionStatus.trial || SubscriptionStatus.active => null,
      };

  static String planTitle(OrganizationPlan plan) => switch (plan) {
        OrganizationPlanKnown(tier: PlanTier.basic) => S.planTitleBasic,
        OrganizationPlanKnown(tier: PlanTier.standard) => S.planTitleStandard,
        OrganizationPlanKnown(tier: PlanTier.advanced) => S.planTitleAdvanced,
        OrganizationPlanNone() => S.planTitleNone,
        OrganizationPlanUnsupported() => S.planTitleUnknown,
      };

  static String planDescription(OrganizationPlan plan) => switch (plan) {
        OrganizationPlanKnown(tier: PlanTier.basic) => S.planDescBasic,
        OrganizationPlanKnown(tier: PlanTier.standard) => S.planDescStandard,
        OrganizationPlanKnown(tier: PlanTier.advanced) => S.planDescAdvanced,
        OrganizationPlanNone() => S.planDescNone,
        OrganizationPlanUnsupported() => S.planDescUnknown,
      };

  static String limit(PlanLimitKey key) => switch (key) {
        PlanLimitKey.detachmentGroups => S.limitDetachmentGroups,
        PlanLimitKey.detachments => S.limitDetachments,
        PlanLimitKey.admins => S.limitAdmins,
        PlanLimitKey.members => S.limitMembers,
        PlanLimitKey.workshops => S.limitWorkshops,
        PlanLimitKey.storageBytes => S.limitStorage,
      };

  static IconData limitIcon(PlanLimitKey key) => switch (key) {
        PlanLimitKey.detachmentGroups => Icons.account_tree_outlined,
        PlanLimitKey.detachments => Icons.flag_outlined,
        PlanLimitKey.admins => Icons.admin_panel_settings_outlined,
        PlanLimitKey.members => Icons.groups_outlined,
        PlanLimitKey.workshops => Icons.school_outlined,
        PlanLimitKey.storageBytes => Icons.cloud_outlined,
      };

  /// Counts in Arabic-Indic digits; storage in MB/GB, formatted exactly as
  /// the Platform limits screen formats it.
  static String amount(PlanLimitKey key, int value) =>
      key.isBytes ? formatBytes(value) : toArabicIndic('$value');

  static String? standing(LimitStanding standing) => switch (standing) {
        LimitStanding.within => S.limitWithin,
        LimitStanding.atLimit => S.limitAt,
        LimitStanding.overLimit => S.limitOver,
        LimitStanding.unavailable => S.limitUnavailable,
        LimitStanding.limitOnly => null,
      };

  static String limitSemantics(OrganizationLimit line) {
    final label = limit(line.key);
    final effective = line.effective;
    if (effective == null) return '$label، ${S.limitUnavailable}';
    final max = amount(line.key, effective);
    final usage = line.usage;
    final base = usage == null
        ? S.limitMaxSemantics
            .replaceFirst('%label%', label)
            .replaceFirst('%limit%', max)
        : S.limitUsageSemantics
            .replaceFirst('%label%', label)
            .replaceFirst('%used%', amount(line.key, usage))
            .replaceFirst('%limit%', max);
    final state = standing(line.standing);
    return state == null ? base : '$base، $state';
  }

  static String date(DateTime value) => AppDate.dayMonthYear(value.toLocal());

  static String readAt(DateTime value) => AppDate.dayMonthTime(value.toLocal());
}
