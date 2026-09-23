import '../../../core/format/app_date.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../l10n/strings.dart';
import '../domain/platform_break_glass_models.dart';
import '../domain/platform_break_glass_repository.dart';

abstract final class BreakGlassCopy {
  static String isolateLtr(String value) => '\u2066$value\u2069';

  static String timestamp(DateTime value) =>
      isolateLtr(AppDate.dayMonthTime(value.toLocal()));

  /// Stable, human-readable context calculated only when the surrounding
  /// state rebuilds. It never owns a timer and never becomes a countdown.
  static String remainingContext(DateTime expiresAt, DateTime now) {
    final remaining = expiresAt.toUtc().difference(now.toUtc());
    if (remaining <= Duration.zero) return S.breakGlassRemainingEnded;
    if (remaining.inSeconds < Duration.secondsPerMinute) {
      return S.breakGlassRemainingLessThanMinute;
    }

    final minutes = (remaining.inSeconds + 59) ~/ Duration.secondsPerMinute;
    if (minutes == 1) return S.breakGlassRemainingOneMinute;
    if (minutes == 2) return S.breakGlassRemainingTwoMinutes;
    if (minutes <= 10) {
      return S.breakGlassRemainingMinutes.replaceFirst(
        '%d',
        toArabicIndic('$minutes'),
      );
    }
    if (minutes < Duration.minutesPerHour) {
      return S.breakGlassRemainingLessThanHour;
    }

    final hours = (minutes + 59) ~/ Duration.minutesPerHour;
    if (hours == 1) return S.breakGlassRemainingOneHour;
    if (hours == 2) return S.breakGlassRemainingTwoHours;
    final template = hours <= 10
        ? S.breakGlassRemainingHours
        : S.breakGlassRemainingHoursMany;
    return template.replaceFirst('%d', toArabicIndic('$hours'));
  }

  static String operationSummary(BreakGlassAccessDecision decision) {
    final grant = decision.grant;
    if (!decision.isPossiblyLive || grant == null) {
      return S.breakGlassNoneTitle;
    }
    final verification = decision.state == BreakGlassAccessState.unverified
        ? ' · ${S.breakGlassUnverifiedShort}'
        : '';
    return '${grant.tenant.displayName} · ${S.breakGlassExpiresAt} '
        '${timestamp(grant.expiresAt)}$verification';
  }

  static String endedTitle(BreakGlassGrant grant) => switch (grant.endReason) {
        BreakGlassEndReason.revokedByPlatform => S.breakGlassRevokedTitle,
        BreakGlassEndReason.tenantUnavailable =>
          S.breakGlassTenantUnavailableTitle,
        _ => S.breakGlassEndedTitle,
      };

  static String endedBody(BreakGlassGrant grant) => switch (grant.endReason) {
        BreakGlassEndReason.endedByInitiator => S.breakGlassEndedByInitiator,
        BreakGlassEndReason.sessionEnded => S.breakGlassEndedWithSession,
        BreakGlassEndReason.tenantUnavailable =>
          S.breakGlassEndedTenantUnavailable,
        BreakGlassEndReason.revokedByPlatform => S.breakGlassEndedRevoked,
        BreakGlassEndReason.unknown || null => S.breakGlassEndedUnknown,
      };

  static String problem(BreakGlassProblemCode code) => switch (code) {
        BreakGlassProblemCode.tenantNotFound =>
          S.breakGlassProblemTenantNotFound,
        BreakGlassProblemCode.tenantNotEligible =>
          S.breakGlassProblemTenantNotEligible,
        BreakGlassProblemCode.tenantAlreadyDeleted =>
          S.breakGlassProblemTenantDeleted,
        BreakGlassProblemCode.invalidReason => S.breakGlassProblemInvalidReason,
        BreakGlassProblemCode.invalidScope => S.breakGlassProblemInvalidScope,
        BreakGlassProblemCode.grantAlreadyActive =>
          S.breakGlassProblemAlreadyActive,
        BreakGlassProblemCode.grantNotFound ||
        BreakGlassProblemCode.grantNotActive =>
          S.breakGlassProblemNotActive,
        BreakGlassProblemCode.staleTenant ||
        BreakGlassProblemCode.staleGrant =>
          S.breakGlassStaleAction,
        BreakGlassProblemCode.idempotencyConflict =>
          S.breakGlassProblemIdempotency,
        BreakGlassProblemCode.recentAuthenticationRequired =>
          S.breakGlassRecentAuthBody,
        BreakGlassProblemCode.notPermitted => S.breakGlassNotPermittedAction,
      };
}
