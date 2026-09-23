/// The Customer Demo **control plane**: the global policy, and the record of
/// one trial session.
///
/// **Why this is not part of `CustomerDemoPolicy`.** That type
/// (`auth/domain/customer_demo.dart`) is the *answer to one question a login
/// screen asks*: may this device start a trial, and for how long. These are
/// the durable facts a Super Admin administers — whether the offer exists at
/// all, what the default window is, who last changed it, and which trials are
/// currently running. The login-side type is derived from [DemoPolicy]; it is
/// never the other way round.
///
/// **Server/control-plane authoritative.** Nothing here is a client decision.
/// A production build replaces the store behind it with the real endpoints
/// (`BACKEND-HANDOFF.md` §Customer Demo); the shapes are what those endpoints
/// must return. In particular [DemoSession.expiresAt] is *stamped once*, by
/// the backend, at session creation — the client never recomputes it from a
/// later policy revision, which is the whole reason [policyRevision] is on the
/// session record.
///
/// **No secrets.** A session record carries an id, an account id, a workspace
/// id and three timestamps. It never carries a token, a credential, a device
/// fingerprint or anything from inside the demo workspace, because the Super
/// Admin screen that lists these has no need of them and a list that held them
/// would be a list worth stealing.
library;

import 'package:flutter/foundation.dart';

/// The lifecycle of one trial. Three values, and deliberately no more.
///
/// "Paused", "extended" and "grace" are states a subscription has; a 24-hour
/// trial that can be neither renewed nor resumed has no use for them, and an
/// unused state is a state nothing keeps honest.
enum DemoSessionStatus {
  /// Inside its window and not ended by anybody.
  active('active'),

  /// Reached [DemoSession.expiresAt]. Reached by time, not by an actor.
  expired('expired'),

  /// Ended before its window closed, by a Super Admin.
  terminated('terminated');

  const DemoSessionStatus(this.wire);

  final String wire;

  /// The status [wire] names, or `null` for a value this build cannot
  /// interpret. Callers fail closed: an uninterpretable trial is not active.
  static DemoSessionStatus? tryParse(String wire) {
    for (final status in values) {
      if (status.wire == wire) return status;
    }
    return null;
  }
}

/// *How* a trial came to be [DemoSessionStatus.terminated].
///
/// **Metadata, not a fourth state.** "The user ended it" and "an operator ended
/// it" are the same fact about the session — it stopped before its window
/// closed — and differ only in who asked. Modelling that difference as a
/// status would make every reader that only cares whether the trial is over
/// handle one more case, and would put the answer to "may this session still
/// act?" in two places. So the state stays `terminated` and the *reason* rides
/// alongside it, for the operator's list and for Audit.
///
/// Absent on an [DemoSessionStatus.active] or [DemoSessionStatus.expired]
/// record: expiry is reached by time, not asked for by anybody.
enum DemoSessionTerminationReason {
  /// The holder pressed «إنهاء التجربة», or signed out of the trial.
  userEnded('user_ended'),

  /// A Super Admin ended this one session from the management list.
  superAdminTerminated('super_admin_terminated'),

  /// A Super Admin ended every running trial at once.
  terminateAll('terminate_all');

  const DemoSessionTerminationReason(this.wire);

  final String wire;

  /// The reason [wire] names, or `null` for a value this build cannot
  /// interpret. An unreadable reason is not an error: the *status* is what
  /// authorizes anything, and it is read separately.
  static DemoSessionTerminationReason? tryParse(String wire) {
    for (final reason in values) {
      if (reason.wire == wire) return reason;
    }
    return null;
  }
}

/// Who changed the policy. A display identity and nothing more.
@immutable
class DemoPolicyActor {
  const DemoPolicyActor({required this.accountId, required this.displayName})
      : assert(accountId != ''),
        assert(displayName != '');

  final String accountId;
  final String displayName;

  Map<String, dynamic> toJson() =>
      {'accountId': accountId, 'displayName': displayName};

  static DemoPolicyActor? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final id = json['accountId'];
    final name = json['displayName'];
    if (id is! String || name is! String || id.isEmpty || name.isEmpty) {
      return null;
    }
    return DemoPolicyActor(accountId: id, displayName: name);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DemoPolicyActor &&
          other.accountId == accountId &&
          other.displayName == displayName;

  @override
  int get hashCode => Object.hash(accountId, displayName);
}

/// The one global answer to "is the trial on offer, and for how long".
@immutable
class DemoPolicy {
  const DemoPolicy({
    required this.enabled,
    required this.defaultDuration,
    required this.revision,
    this.updatedBy,
    this.updatedAt,
  }) : assert(revision >= 1);

  /// **24 hours — the product default, and the only one this client ships.**
  ///
  /// It is a constant rather than a configurable seed because "how long is a
  /// Leader trial" is a product answer, not a deployment one. A Super Admin
  /// moves [defaultDuration] away from it; nothing else may.
  static const Duration defaultDemoDuration = Duration(hours: 24);

  /// The policy a control plane starts from before any administration.
  static const DemoPolicy initial = DemoPolicy(
    enabled: true,
    defaultDuration: defaultDemoDuration,
    revision: 1,
  );

  /// Whether a **new** trial may be started.
  ///
  /// Disabling it stops creation and nothing else — see the note on
  /// [DemoSession.policyRevision]. An administrator who wants the running
  /// trials gone asks for that explicitly.
  final bool enabled;

  /// The window a **new** trial is stamped with.
  final Duration defaultDuration;

  /// Bumped on every policy change. A session records the revision it was
  /// created under, so a later change is visibly *not* retroactive.
  final int revision;

  final DemoPolicyActor? updatedBy;
  final DateTime? updatedAt;

  DemoPolicy copyWith({
    bool? enabled,
    Duration? defaultDuration,
    int? revision,
    DemoPolicyActor? updatedBy,
    DateTime? updatedAt,
  }) =>
      DemoPolicy(
        enabled: enabled ?? this.enabled,
        defaultDuration: defaultDuration ?? this.defaultDuration,
        revision: revision ?? this.revision,
        updatedBy: updatedBy ?? this.updatedBy,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'defaultDurationMinutes': defaultDuration.inMinutes,
        'revision': revision,
        if (updatedBy != null) 'updatedBy': updatedBy!.toJson(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
      };

  /// Reads a policy payload, falling back to [initial]'s values field by field
  /// so a backend that implements half of this shape still produces a usable
  /// policy rather than an exception.
  factory DemoPolicy.fromJson(Map<String, dynamic> json) {
    final rawMinutes = json['defaultDurationMinutes'];
    final minutes = rawMinutes is int && rawMinutes > 0
        ? rawMinutes
        : defaultDemoDuration.inMinutes;
    final rawRevision = json['revision'];
    final rawUpdatedAt = json['updatedAt'];
    return DemoPolicy(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      defaultDuration: Duration(minutes: minutes),
      revision: rawRevision is int && rawRevision >= 1 ? rawRevision : 1,
      updatedBy: DemoPolicyActor.fromJson(
        json['updatedBy'] is Map<String, dynamic>
            ? json['updatedBy'] as Map<String, dynamic>
            : null,
      ),
      updatedAt:
          rawUpdatedAt is String ? DateTime.tryParse(rawUpdatedAt)?.toUtc() : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DemoPolicy &&
          other.enabled == enabled &&
          other.defaultDuration == defaultDuration &&
          other.revision == revision &&
          other.updatedBy == updatedBy &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      Object.hash(enabled, defaultDuration, revision, updatedBy, updatedAt);
}

/// One running (or finished) trial, as the control plane records it.
@immutable
class DemoSession {
  const DemoSession({
    required this.demoSessionId,
    required this.accountId,
    required this.demoWorkspaceId,
    required this.startedAt,
    required this.expiresAt,
    required this.status,
    required this.policyRevision,
    this.displayName,
    this.endedAt,
    this.terminationReason,
  });

  final String demoSessionId;

  /// The **real** identity that started the trial — the verified, unlinked
  /// account. It survives the trial; ending one never touches it.
  final String accountId;

  /// The isolated workspace this trial reads and writes. Discarded with the
  /// session; nothing in it reaches a tenant.
  final String demoWorkspaceId;

  final DateTime startedAt;

  /// Stamped once, at creation, from the policy in force *then*. A later
  /// policy change does not move it.
  final DateTime expiresAt;

  final DemoSessionStatus status;

  /// The [DemoPolicy.revision] in force when this session was created.
  final int policyRevision;

  /// A safe display identity for the operator's list, when the control plane
  /// supplies one. Never an email, never a token.
  final String? displayName;

  /// When it was ended early. Only ever set for
  /// [DemoSessionStatus.terminated].
  final DateTime? endedAt;

  /// Why it was ended early, when the control plane records that. Only ever
  /// set alongside [endedAt] — see [DemoSessionTerminationReason].
  final DemoSessionTerminationReason? terminationReason;

  /// The status **as of [now]**, which is the only status worth branching on.
  ///
  /// A stored [status] of [DemoSessionStatus.active] is a claim about the past:
  /// it was active when it was written. Time alone retires a trial, and no
  /// actor writes the transition, so every reader asks this rather than the
  /// field. A terminated session stays terminated whatever the clock says.
  DemoSessionStatus statusAt(DateTime now) {
    if (status != DemoSessionStatus.active) return status;
    return now.toUtc().isBefore(expiresAt.toUtc())
        ? DemoSessionStatus.active
        : DemoSessionStatus.expired;
  }

  bool isActiveAt(DateTime now) => statusAt(now) == DemoSessionStatus.active;

  /// What is left of the window, or [Duration.zero] once it has closed.
  Duration remainingAt(DateTime now) {
    if (!isActiveAt(now)) return Duration.zero;
    final left = expiresAt.toUtc().difference(now.toUtc());
    return left.isNegative ? Duration.zero : left;
  }

  DemoSession copyWith({
    DemoSessionStatus? status,
    DateTime? endedAt,
    DemoSessionTerminationReason? terminationReason,
  }) =>
      DemoSession(
        demoSessionId: demoSessionId,
        accountId: accountId,
        demoWorkspaceId: demoWorkspaceId,
        startedAt: startedAt,
        expiresAt: expiresAt,
        status: status ?? this.status,
        policyRevision: policyRevision,
        displayName: displayName,
        endedAt: endedAt ?? this.endedAt,
        terminationReason: terminationReason ?? this.terminationReason,
      );

  Map<String, dynamic> toJson() => {
        'demoSessionId': demoSessionId,
        'accountId': accountId,
        'demoWorkspaceId': demoWorkspaceId,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'status': status.wire,
        'policyRevision': policyRevision,
        if (displayName != null) 'displayName': displayName,
        if (endedAt != null) 'endedAt': endedAt!.toUtc().toIso8601String(),
        if (terminationReason != null)
          'terminationReason': terminationReason!.wire,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DemoSession &&
          other.demoSessionId == demoSessionId &&
          other.accountId == accountId &&
          other.demoWorkspaceId == demoWorkspaceId &&
          other.startedAt == startedAt &&
          other.expiresAt == expiresAt &&
          other.status == status &&
          other.policyRevision == policyRevision &&
          other.displayName == displayName &&
          other.endedAt == endedAt &&
          other.terminationReason == terminationReason;

  @override
  int get hashCode => Object.hash(
        demoSessionId,
        accountId,
        demoWorkspaceId,
        startedAt,
        expiresAt,
        status,
        policyRevision,
        displayName,
        endedAt,
        terminationReason,
      );
}

/// What the duration control may offer, and what it must leave to the backend.
///
/// **There is no maximum here on purpose.** A ceiling on a trial window is
/// deployment policy — it depends on what a Leader trial workspace costs to
/// hold open, which this client cannot know. The control offers an unbounded
/// increase and the backend rejects what it will not honour
/// (`BACKEND-HANDOFF.md`). The *floor* is different in kind: below an hour a
/// "24 hour trial" product has stopped being one, and a zero or negative
/// duration is not a window at all.
abstract final class DemoDurationPolicy {
  static const Duration minimum = Duration(hours: 1);

  /// Below a day, an hour is the unit an operator thinks in; at or above one,
  /// a day is. Stepping 24 → 25 → 26 hours would be a control that is precise
  /// where nobody needs precision.
  static Duration increment(Duration current) =>
      current < const Duration(hours: 24)
          ? current + const Duration(hours: 1)
          : current + const Duration(hours: 24);

  /// The inverse, clamped at [minimum]. Stepping down from 48h lands on 24h,
  /// then walks back in hours.
  static Duration decrement(Duration current) {
    final next = current > const Duration(hours: 24)
        ? current - const Duration(hours: 24)
        : current - const Duration(hours: 1);
    return next < minimum ? minimum : next;
  }

  static bool canDecrease(Duration current) => current > minimum;
}
