import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/problem/problem.dart';
import 'package:mtm/core/problem/problem_presentation.dart';
import 'package:mtm/l10n/strings.dart';

/// `resolveProblem` is the Core-owned half of the hybrid: it must classify
/// the app-wide problems, fall back safely for anything else, and it must
/// decide entirely from [ProblemCode] — never from server text.
void main() {
  group('known global codes → MTM-owned localized copy', () {
    test('authentication_expired is a full-screen re-auth state', () {
      final v = resolveProblem(Problem.of(ProblemCode.authenticationExpired));
      expect(v.surface, ProblemSurface.fullScreen);
      expect(v.title, S.sessionExpiredTitle);
      expect(v.message, S.sessionExpiredSub);
      expect(v.retryable, isFalse);
    });

    test('not_permitted is an inline state with no retry', () {
      final v = resolveProblem(Problem.of(ProblemCode.notPermitted));
      expect(v.surface, ProblemSurface.inline);
      expect(v.message, S.errNotPermitted);
      expect(v.retryable, isFalse, reason: 'retrying a 403 is a dead button');
    });

    test('offline / network / server are retryable inline states', () {
      for (final code in [
        ProblemCode.offline,
        ProblemCode.network,
        ProblemCode.server,
      ]) {
        final v = resolveProblem(Problem.of(code));
        expect(v.surface, ProblemSurface.inline, reason: code.name);
        expect(v.retryable, isTrue, reason: code.name);
      }
    });

    test('every message is an S.* string, never null or empty', () {
      for (final code in ProblemCode.values) {
        final v = resolveProblem(Problem.of(code));
        expect(v.message, isNotEmpty, reason: code.name);
        expect(v.title, isNotEmpty, reason: code.name);
      }
    });
  });

  group('unknown code → safe fallback (§11)', () {
    test('generic copy, not retryable, no crash', () {
      final v = resolveProblem(const Problem.unknown('raw server text'));
      expect(v.title, S.problemUnexpectedTitle);
      expect(v.message, S.problemUnexpectedBody);
      expect(v.retryable, isFalse);
    });

    test('a parsed-but-unrecognised code falls back the same way', () {
      final v = resolveProblem(Problem.fromJson(const {
        'code': 'brand_new_backend_code',
        'detail': 'something the backend team added last week',
      }));
      expect(v, ProblemView.fallback);
    });
  });

  group('branching is by code, not text', () {
    test('changing detail/title/type does not change the resolved view', () {
      final a = resolveProblem(Problem.fromJson(const {
        'code': 'not_permitted',
        'detail': 'overlap overlap overlap',
        'title': 'anything at all',
      }));
      final b = resolveProblem(Problem.fromJson(const {
        'code': 'not_permitted',
        'detail': 'completely different wording',
      }));
      expect(a, b);
      expect(a.message, S.errNotPermitted);
    });

    test('the resolved message never contains the server detail', () {
      const nasty =
          'SQLSTATE[42000] at Db.query (db.dart:88) token=Bearer abc.def';
      for (final code in ProblemCode.values) {
        final v = resolveProblem(Problem.of(code, detail: nasty));
        expect(v.message, isNot(contains('SQLSTATE')), reason: code.name);
        expect(v.message, isNot(contains('Bearer')), reason: code.name);
        expect(v.title, isNot(contains('db.dart')), reason: code.name);
      }
      final unknown =
          resolveProblem(Problem.of(null, rawCode: 'x', detail: nasty));
      expect(unknown.message, S.problemUnexpectedBody);
    });
  });

  group('feature-owned codes stay resolvable without leaking into Core', () {
    test('a domain code Core does not enumerate resolves to the fallback', () {
      // e.g. a future SHIFT_OVERLAP / EXPIRED_BATCH the shift/inventory
      // feature will own. Core neither knows nor needs to know it.
      final v =
          resolveProblem(Problem.fromJson(const {'code': 'shift_overlap'}));
      expect(v, ProblemView.fallback,
          reason: 'Core does not grow a case per feature error');
    });

    test('conflict and validation are generic defaults a feature overrides',
        () {
      expect(resolveProblem(Problem.of(ProblemCode.conflict)).surface,
          ProblemSurface.modal);
      expect(resolveProblem(Problem.of(ProblemCode.validation)).surface,
          ProblemSurface.field);
    });
  });

  group('support reference (§12)', () {
    test('shown only on modal / full-screen, and only when present', () {
      final conflictWithRef = resolveProblem(
        Problem.of(ProblemCode.conflict, reference: 'req_1'),
      );
      expect(conflictWithRef.reference, 'req_1',
          reason: 'conflict is a modal surface');

      final fieldWithRef = resolveProblem(
        Problem.of(ProblemCode.validation, reference: 'req_1'),
      );
      expect(fieldWithRef.reference, isNull,
          reason: 'a field error never shows a technical reference');

      final inlineWithRef = resolveProblem(
        Problem.of(ProblemCode.server, reference: 'req_1'),
      );
      expect(inlineWithRef.reference, isNull);
    });
  });
}
