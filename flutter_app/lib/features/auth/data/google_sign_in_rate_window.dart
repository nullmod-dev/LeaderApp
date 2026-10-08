/// The device's own record of failed Google sign-ins — for the message and
/// the countdown only.
///
/// The backend is the authority: `POST /auth/google` refuses a device after
/// [GoogleSignInRateWindow.maxFailures] failed attempts in an hour
/// (`429 rate_limited` + `Retry-After`). This mirrors that budget so a device
/// that has spent it is told so, with the time left, before the account
/// picker opens rather than after another round-trip. It never decides
/// anything the server would allow for long: clearing the app's data starts
/// it empty, and the server still answers.
///
/// What counts mirrors the server: a refusal the backend actually returned.
/// A success, a dismissed picker, an offline attempt or a transport fault
/// never spends the budget. Stored in [LocalStore] as instants only — no
/// address, no token.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/problem/problem.dart';
import '../../../core/result/result.dart';
import '../../../core/storage/local_store.dart';
import '../domain/onboarding_repository.dart';
import 'auth_providers.dart' show localStoreProvider;

class GoogleSignInRateWindow {
  GoogleSignInRateWindow(this._store, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  static const storageKey = 'mtm.auth.google_sign_in_attempts';
  static const maxFailures = 6;
  static const window = Duration(hours: 1);

  /// Clock drift tolerated before a stored instant is treated as bogus. A
  /// record from "the future" (a clock moved back) is dropped, never obeyed:
  /// this store fails open, because the server is the one that refuses.
  static const _skew = Duration(minutes: 5);

  /// Upper bound on what is kept, whatever the clock does.
  static const _maxKept = 32;

  final LocalStore _store;
  final DateTime Function() _now;

  /// How long until another attempt is worth making, or `null` when one is.
  Future<Duration?> blockedFor() async {
    final now = _now().toUtc();
    final record = await _read(now);
    var until = record.blockedUntil;
    final failures = record.failures;
    if (failures.length >= maxFailures) {
      // The attempt that has to age out before fewer than six remain.
      final freed = failures[failures.length - maxFailures].add(window);
      if (until == null || freed.isAfter(until)) until = freed;
    }
    if (until == null || !until.isAfter(now)) return null;
    return until.difference(now);
  }

  /// Applies one `POST /auth/google` answer.
  Future<void> record(Result<Object?> result) async {
    final String? code;
    switch (result) {
      case Success() || Offline():
        return;
      case Failure(code: final c):
        code = c;
    }
    // Not delivered, so not counted by the server either.
    if (ProblemCode.parse(code) == ProblemCode.network) return;

    final now = _now().toUtc();
    final record = await _read(now);
    var failures = record.failures;
    var blockedUntil = record.blockedUntil;
    if (code == OnboardingProblemCode.rateLimited.wire) {
      // The server's own verdict: wait until it said, never longer than a
      // window (a missing or absurd Retry-After).
      final ceiling = now.add(window);
      final said = result is OnboardingFailure<Object?>
          ? result.retryAvailableAt?.toUtc()
          : null;
      final at = (said == null || said.isAfter(ceiling)) ? ceiling : said;
      if (blockedUntil == null || at.isAfter(blockedUntil)) blockedUntil = at;
    } else {
      failures = [...failures, now];
      if (failures.length > _maxKept) {
        failures = failures.sublist(failures.length - _maxKept);
      }
    }
    await _write(failures, blockedUntil);
  }

  Future<({List<DateTime> failures, DateTime? blockedUntil})> _read(
    DateTime now,
  ) async {
    final raw = await _store.readString(storageKey);
    final empty = (failures: <DateTime>[], blockedUntil: null);
    if (raw == null) return empty;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return empty;
      final earliest = now.subtract(window);
      final latest = now.add(_skew);
      DateTime? instant(Object? value) => value is int
          ? DateTime.fromMillisecondsSinceEpoch(value, isUtc: true)
          : null;
      final failures = <DateTime>[
        for (final value in (json['failures'] as List? ?? const []))
          if (instant(value) case final at?
              when at.isAfter(earliest) && !at.isAfter(latest))
            at,
      ]..sort();
      var blockedUntil = instant(json['blockedUntil']);
      if (blockedUntil != null &&
          (!blockedUntil.isAfter(now) ||
              blockedUntil.isAfter(latest.add(window)))) {
        blockedUntil = null;
      }
      return (failures: failures, blockedUntil: blockedUntil);
    } catch (_) {
      // Corrupt or foreign data reads as "nothing on file".
      return empty;
    }
  }

  Future<void> _write(List<DateTime> failures, DateTime? blockedUntil) {
    if (failures.isEmpty && blockedUntil == null) {
      return _store.remove(storageKey);
    }
    return _store.writeString(
      storageKey,
      jsonEncode({
        'failures': [for (final at in failures) at.millisecondsSinceEpoch],
        'blockedUntil': blockedUntil?.millisecondsSinceEpoch,
      }),
    );
  }
}

final googleSignInRateWindowProvider = Provider<GoogleSignInRateWindow>((ref) {
  return GoogleSignInRateWindow(ref.watch(localStoreProvider));
});
