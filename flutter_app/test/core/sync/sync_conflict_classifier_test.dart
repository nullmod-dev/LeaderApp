import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/sync/sync_conflict_classifier.dart';

/// Task 3 — the agreed stale-write wire code. `defaultSyncConflictClassifier`
/// must recognise exactly `stale_write` and nothing else: not `null`, not the
/// unrelated generic `conflict` code (`ProblemCode.conflict`, a different
/// concept per `sync_conflict_classifier.dart`'s doc comment), and not a
/// future in-progress / invalid-reuse code that is still `Backend contract
/// decision required` (`FRONTEND-BACKEND-INTEGRATION.md` §3).
void main() {
  group('defaultSyncConflictClassifier', () {
    test('recognises the agreed stale-write code', () {
      expect(defaultSyncConflictClassifier('stale_write'), isTrue);
    });

    test('does not recognise null', () {
      expect(defaultSyncConflictClassifier(null), isFalse);
    });

    test('does not recognise the unrelated generic conflict code', () {
      expect(defaultSyncConflictClassifier('conflict'), isFalse);
    });

    test('does not recognise an unrelated or future/undecided code', () {
      for (final code in [
        'offline',
        'network',
        'server',
        'validation',
        'in_progress', // still Backend contract decision required
        'invalid_reuse', // still Backend contract decision required
        'some_future_code',
      ]) {
        expect(defaultSyncConflictClassifier(code), isFalse, reason: code);
      }
    });
  });
}
