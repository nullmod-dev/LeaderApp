import 'package:flutter/foundation.dart';

import '../../l10n/strings.dart';
import 'problem.dart';

/// Where a resolved [Problem] belongs on screen. The MTM error taxonomy,
/// one value — see `FRONTEND-BACKEND-INTEGRATION.md` §2.
enum ProblemSurface {
  /// A correctable form field. Shown at the field, never as a snackbar.
  field,

  /// Part of a screen failed, the rest is usable. `ErrorStateView` / a
  /// section retry.
  inline,

  /// Low-impact, nothing lost, no decision needed. A snackbar. Never for a
  /// blocking, destructive, security or conflict condition.
  transient,

  /// The current action cannot proceed and the user must choose what to do
  /// next, but the app as a whole is fine. A dialog or bottom sheet.
  modal,

  /// App-wide, or a substantial workflow. A full-screen state.
  fullScreen,
}

/// The frontend's decision about how to present a [Problem]: **its own
/// localized copy**, the surface it belongs on, whether retry is meaningful,
/// and a support reference when there is a substantial surface to show it
/// on.
///
/// Never carries backend text for a known code. `message` is always an `S`
/// string.
@immutable
class ProblemView {
  const ProblemView({
    required this.title,
    required this.message,
    required this.surface,
    required this.retryable,
    this.reference,
  });

  final String title;
  final String message;
  final ProblemSurface surface;

  /// Show a retry affordance only when this is true (§11). A retry on a
  /// `not_permitted` or a `validation` is a dead button.
  final bool retryable;

  /// A safe support/correlation id, present only when the [Problem] carried
  /// one *and* [surface] is substantial enough to show it ([modal] /
  /// [fullScreen]). `null` everywhere else — a field error never shows a
  /// technical reference (§12).
  final String? reference;

  /// The safe fallback for a code this build does not recognise (§11): a
  /// generic message, no assumption that retry helps.
  static const ProblemView fallback = ProblemView(
    title: S.problemUnexpectedTitle,
    message: S.problemUnexpectedBody,
    surface: ProblemSurface.inline,
    retryable: false,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProblemView &&
          other.title == title &&
          other.message == message &&
          other.surface == surface &&
          other.retryable == retryable &&
          other.reference == reference;

  @override
  int get hashCode =>
      Object.hash(title, message, surface, retryable, reference);
}

/// Core-owned resolution for **global / transport** problems, plus the safe
/// fallback for everything this build does not recognise.
///
/// This is the whole of Core's problem knowledge, and it is bounded: the
/// app-wide conditions every feature shares (upgrade, auth, permission, the
/// tenant-wide feature and plan-limit refusals, connectivity, server) and
/// nothing else. It is a plain `switch`, not a registry, because the set does
/// not grow with the product — a new detachment, inventory or workshop error
/// is **not** added here.
///
/// Domain problems stay with their feature: a feature reads `problem.code`
/// at its own `Result`/`Problem` call site, maps its own codes (including
/// codes unknown to [ProblemCode]) to its own copy and surface, and only
/// falls back to this function for the shared conditions. `conflict` and
/// `validation` are resolved here to sensible generic defaults a feature is
/// expected to override with something specific (a merge sheet, per-field
/// messages).
ProblemView resolveProblem(Problem problem) {
  switch (problem.code) {
    case ProblemCode.upgradeRequired:
      // The forced-upgrade gate owns the actual screen; this is only for a
      // caller that resolves the problem without routing.
      return _view(
          problem, S.upgradeTitle, S.upgradeBody, ProblemSurface.fullScreen,
          retryable: false);

    case ProblemCode.authenticationExpired:
      return _view(problem, S.sessionExpiredTitle, S.sessionExpiredSub,
          ProblemSurface.fullScreen,
          retryable: false);

    case ProblemCode.notPermitted:
      return _view(problem, S.errNotPermittedTitle, S.errNotPermitted,
          ProblemSurface.inline,
          retryable: false);

    // The two tenant-wide refusals that are *not* this account's permission.
    // Each has its own sentence so an administrator is never told "you lack
    // permission" for something no grant could fix (Point 16). Neither is
    // retryable: re-sending the same request meets the same answer.
    case ProblemCode.featureDisabled:
      return _view(problem, S.errFeatureDisabledTitle, S.errFeatureDisabled,
          ProblemSurface.inline,
          retryable: false);

    case ProblemCode.planLimitReached:
      return _view(
          problem, S.errPlanLimitTitle, S.errPlanLimit, ProblemSurface.inline,
          retryable: false);

    case ProblemCode.notFound:
      return _view(problem, S.errTitle, S.errNotFound, ProblemSurface.inline,
          retryable: false);

    case ProblemCode.offline:
    case ProblemCode.network:
      return _view(problem, S.offlineTitle, S.errNetwork, ProblemSurface.inline,
          retryable: true);

    case ProblemCode.server:
      return _view(problem, S.errTitle, S.errServer, ProblemSurface.inline,
          retryable: true);

    case ProblemCode.conflict:
      // Generic default. A feature that can show the conflicting record
      // overrides this with a modal that does.
      return _view(
          problem, S.errConflictTitle, S.errConflict, ProblemSurface.modal,
          retryable: true);

    case ProblemCode.staleWrite:
      // Generic default only. A mutation call site that can build a
      // ConflictPresentation must read this code before it ever reaches
      // here and open ConflictResolutionPage instead (§4). Unlike
      // `conflict` above, retry is never offered here: resubmitting the
      // exact same write against the same (now-stale) version is
      // guaranteed to fail the same way again, not just likely to.
      return _view(
          problem, S.errStaleWriteTitle, S.errStaleWrite, ProblemSurface.modal,
          retryable: false);

    case ProblemCode.validation:
      // Generic default. A feature with the form on screen maps
      // `problem.fieldErrors` to its inputs instead.
      return _view(problem, S.errTitle, S.errValidation, ProblemSurface.field,
          retryable: false);

    case null:
      return _view(problem, S.problemUnexpectedTitle, S.problemUnexpectedBody,
          ProblemSurface.inline,
          retryable: false);
  }
}

ProblemView _view(
  Problem problem,
  String title,
  String message,
  ProblemSurface surface, {
  required bool retryable,
}) {
  final showReference =
      surface == ProblemSurface.modal || surface == ProblemSurface.fullScreen;
  return ProblemView(
    title: title,
    message: message,
    surface: surface,
    retryable: retryable,
    reference: showReference ? problem.reference : null,
  );
}
