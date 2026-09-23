import 'package:flutter/foundation.dart';

/// The smallest fact worth surviving a process restart: **this installed
/// build was already told it is unsupported.**
///
/// MTM is offline-first, so a build that has seen a `426` must not be able
/// to walk back in just by being relaunched with no network — the version
/// check may never answer. But the flag is only meaningful for the build it
/// was written about: shipping a fix — as a new version *or* just a new
/// build number — must not stay blocked on a verdict that belonged to the
/// old artefact. So the record is keyed by the **build identity**
/// (`major.minor.patch+build`, `AppInfo.buildIdentity`) it was captured
/// against ([blockedVersion]), and [appliesTo] is the only thing that reads
/// it back.
@immutable
class PersistedUpgradeGate {
  const PersistedUpgradeGate({
    required this.blockedVersion,
    this.minimumVersion,
  });

  /// `AppInfo.buildIdentity` (`major.minor.patch+build`) at the moment the
  /// `426` (or a support check with `supported == false`) was received.
  final String blockedVersion;

  /// The floor the backend named, if it named one — persisted only so the
  /// blocking screen can still show the version pair while offline. Not part
  /// of the identity check.
  final String? minimumVersion;

  /// True when this record was written about the build that is running now,
  /// and should therefore still block. A different string means the record
  /// is stale — a newer (or older) build is installed and this verdict is
  /// not about it.
  ///
  /// Exact string match on purpose: the client never parses or orders
  /// version strings. Pass `AppInfo.buildIdentity`. See
  /// `FRONTEND-BACKEND-INTEGRATION.md` §1 — the *server*-comparison identity
  /// is still a `Backend contract decision required`; this is only the local
  /// "is this verdict about the binary I am now?" check.
  bool appliesTo(String installedBuildIdentity) =>
      blockedVersion == installedBuildIdentity;

  factory PersistedUpgradeGate.fromJson(Map<String, dynamic> j) =>
      PersistedUpgradeGate(
        blockedVersion: j['blockedVersion'] as String,
        minimumVersion: j['minimumVersion'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'blockedVersion': blockedVersion,
        if (minimumVersion != null) 'minimumVersion': minimumVersion,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistedUpgradeGate &&
          other.blockedVersion == blockedVersion &&
          other.minimumVersion == minimumVersion;

  @override
  int get hashCode => Object.hash(blockedVersion, minimumVersion);

  @override
  String toString() =>
      'PersistedUpgradeGate($blockedVersion, min: $minimumVersion)';
}

/// Persists (and clears) the one [PersistedUpgradeGate] record.
///
/// THE SEAM. A real implementation writes to the same ordinary local
/// preference store `SettingsRepository` uses — this is non-sensitive UI
/// state, the bucket `DATA-NEEDS.md` §3.3 allows (alongside theme, motion
/// level, last active detachment). It is deliberately **not** on
/// `SettingsRepository`: that interface is user-chosen settings, and a
/// forced-upgrade verdict is a cached server answer, not a preference.
///
/// One record, three operations. Nothing here decides whether a build is
/// supported; it only remembers a decision already made.
abstract class AppVersionGateStore {
  /// The stored record, or null when this build has never been refused.
  Future<PersistedUpgradeGate?> read();

  /// Writes the record after a refusal.
  Future<void> write(PersistedUpgradeGate gate);

  /// Drops the record once a check says this build is supported again, or
  /// when the stored record turns out to belong to another build.
  Future<void> clear();
}
