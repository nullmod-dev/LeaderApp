import 'package:flutter/material.dart';

import '../../../core/access/saas_tenant_status.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../domain/platform_main_admin_models.dart';
import '../domain/platform_main_admin_repository.dart';
import '../domain/saas_tenant_validation.dart';
import 'widgets/platform_meta.dart';

/// Point 14B presentation vocabulary. Wire values never reach widgets.
abstract final class MainAdminCopy {
  /// «٨ أيلول ١١:٠٠».
  ///
  /// `PlatformTime.dayTime`, not `AppDate.dayMonthTime`: the shared helper
  /// joins the date and the clock with ` · ` and a platform clock very often
  /// begins with «٠», which is the same mark (UI audit P1-11).
  static String timestamp(DateTime value) => PlatformTime.dayTime(value);

  static String replacementKeepsCurrent(
    String current,
    String designate,
  ) =>
      S.mainAdminReplacementKeepsCurrent
          .replaceFirst('%current%', current)
          .replaceFirst('%designate%', designate);

  static String cancelChange(String name) =>
      S.mainAdminCancelConfirmChange.replaceFirst('%name%', name);

  static String replacementChange({
    required MainAdminReplacementMode mode,
    required String oldName,
    required String newName,
  }) {
    final template = mode == MainAdminReplacementMode.immediate
        ? S.mainAdminReplaceImmediateChange
        : S.mainAdminReplacePendingChange;
    return template
        .replaceFirst('%old%', oldName)
        .replaceFirst('%new%', newName);
  }

  static String replacementMode(MainAdminReplacementMode mode) =>
      mode == MainAdminReplacementMode.immediate
          ? S.mainAdminReplaceImmediateMode
          : S.mainAdminReplacePendingMode;

  static String status(MainAdminAccountStatus status) => switch (status) {
        MainAdminAccountStatus.active => S.mainAdminStatusActive,
        MainAdminAccountStatus.pendingSetup => S.mainAdminStatusPending,
        MainAdminAccountStatus.suspended => S.mainAdminStatusSuspended,
        MainAdminAccountStatus.revoked ||
        MainAdminAccountStatus.unknown =>
          S.mainAdminStatusUnsupported,
      };

  static StatusKind statusKind(MainAdminAccountStatus status) =>
      switch (status) {
        MainAdminAccountStatus.active => StatusKind.ok,
        MainAdminAccountStatus.pendingSetup => StatusKind.warn,
        MainAdminAccountStatus.suspended => StatusKind.crit,
        MainAdminAccountStatus.revoked ||
        MainAdminAccountStatus.unknown =>
          StatusKind.muted,
      };

  static IconData statusIcon(MainAdminAccountStatus status) => switch (status) {
        MainAdminAccountStatus.active => Icons.verified_user_outlined,
        MainAdminAccountStatus.pendingSetup => Icons.mark_email_unread_outlined,
        MainAdminAccountStatus.suspended => Icons.block_rounded,
        MainAdminAccountStatus.revoked ||
        MainAdminAccountStatus.unknown =>
          Icons.help_outline_rounded,
      };

  static String summary(MainAdminAccountSnapshot snapshot) {
    if (snapshot.hasUnsupportedState) return S.mainAdminSummaryUnavailable;
    if (snapshot.replacement != null) {
      return S.mainAdminSummaryReplacement;
    }
    return switch (snapshot.current.status) {
      MainAdminAccountStatus.pendingSetup => S.mainAdminSummaryPending,
      MainAdminAccountStatus.active => S.mainAdminSummaryActive,
      MainAdminAccountStatus.suspended => S.mainAdminSummarySuspended,
      MainAdminAccountStatus.revoked ||
      MainAdminAccountStatus.unknown =>
        S.mainAdminSummaryUnavailable,
    };
  }

  static String tenantBlocked(SaasTenantStatus status) => switch (status) {
        SaasTenantStatus.suspended => S.mainAdminTenantBlockedSuspended,
        SaasTenantStatus.deletionPending => S.mainAdminTenantBlockedDeletion,
        SaasTenantStatus.active || SaasTenantStatus.deleted => '',
      };

  /// The team's access state, worded as the team's so it never reads as the
  /// account status beside it. Never red: red belongs to the account.
  static String tenantAccess(SaasTenantStatus status) => switch (status) {
        SaasTenantStatus.active => S.mainAdminTenantAccessActive,
        SaasTenantStatus.suspended => S.mainAdminTenantAccessSuspended,
        SaasTenantStatus.deletionPending ||
        SaasTenantStatus.deleted =>
          S.mainAdminTenantAccessDeletion,
      };

  static StatusKind tenantAccessKind(SaasTenantStatus status) =>
      status == SaasTenantStatus.active ? StatusKind.muted : StatusKind.warn;

  static IconData tenantAccessIcon(SaasTenantStatus status) =>
      status == SaasTenantStatus.active
          ? Icons.domain_rounded
          : Icons.domain_disabled_outlined;

  static String action(MainAdminAction action, MainAdminManagementView view) =>
      switch (action) {
        MainAdminAction.resendSetup => S.mainAdminResend,
        MainAdminAction.resendReplacementSetup => S.mainAdminResendDesignate,
        MainAdminAction.suspend => S.mainAdminSuspend,
        MainAdminAction.reactivate => S.mainAdminReactivate,
        MainAdminAction.replace =>
          view.replacementMode == MainAdminReplacementMode.immediate
              ? S.mainAdminChangeInvitee
              : S.mainAdminReplace,
        MainAdminAction.cancelReplacement => S.mainAdminCancelReplacement,
      };

  static String success(MainAdminMutationEffect effect) => switch (effect) {
        MainAdminMutationEffect.setupResent => S.mainAdminSuccessResent,
        MainAdminMutationEffect.suspended => S.mainAdminSuccessSuspended,
        MainAdminMutationEffect.reactivated => S.mainAdminSuccessReactivated,
        MainAdminMutationEffect.replacementStarted =>
          S.mainAdminSuccessReplacementStarted,
        MainAdminMutationEffect.replaced => S.mainAdminSuccessReplaced,
        MainAdminMutationEffect.replacementCancelled =>
          S.mainAdminSuccessReplacementCancelled,
        MainAdminMutationEffect.setupCompleted => S.mainAdminSummaryActive,
      };

  static String problem(MainAdminProblemCode code) => switch (code) {
        MainAdminProblemCode.tenantNotFound ||
        MainAdminProblemCode.tenantAlreadyDeleted ||
        MainAdminProblemCode.tenantNotEligible =>
          S.mainAdminTenantUnavailable,
        MainAdminProblemCode.invalidTransition => S.mainAdminInvalidTransition,
        MainAdminProblemCode.invalidReason => S.mainAdminReasonRequired,
        MainAdminProblemCode.invalidIdentity => S.mainAdminEmailInvalid,
        MainAdminProblemCode.identityUnavailable => S.mainAdminEmailUnavailable,
        MainAdminProblemCode.replacementAlreadyPending =>
          S.mainAdminReplacementAlreadyPending,
        MainAdminProblemCode.setupResendThrottled => S.mainAdminResendThrottled,
        MainAdminProblemCode.staleMainAdmin => S.mainAdminStaleAction,
        MainAdminProblemCode.idempotencyConflict =>
          S.mainAdminIdempotencyConflict,
        MainAdminProblemCode.recentAuthenticationRequired =>
          S.mainAdminRecentAuthBody,
        MainAdminProblemCode.notPermitted => S.mainAdminNotPermitted,
      };

  static String? nameError(SaasTenantFieldError? error) => switch (error) {
        SaasTenantFieldError.required => S.mainAdminNameRequired,
        SaasTenantFieldError.tooLong => S.mainAdminNameTooLong,
        SaasTenantFieldError.invalidEmail ||
        SaasTenantFieldError.invalidTeamCode ||
        SaasTenantFieldError.duplicateTeamCode =>
          S.mainAdminNameRequired,
        null => null,
      };

  static String? emailError(SaasTenantFieldError? error) => switch (error) {
        SaasTenantFieldError.required => S.mainAdminEmailRequired,
        SaasTenantFieldError.tooLong => S.mainAdminEmailTooLong,
        SaasTenantFieldError.invalidEmail => S.mainAdminEmailInvalid,
        SaasTenantFieldError.invalidTeamCode ||
        SaasTenantFieldError.duplicateTeamCode =>
          S.mainAdminEmailInvalid,
        null => null,
      };
}
