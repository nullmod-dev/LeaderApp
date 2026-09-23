import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/problem/problem.dart';
import 'package:mtm/core/problem/problem_result.dart';
import 'package:mtm/core/result/result.dart';

/// The frontend [Problem] model: it must parse a future RFC 9457 body, keep
/// only what it is given (no untyped extension bag), and stay safe when the
/// backend sends a code this build has never heard of.
void main() {
  group('ProblemCode.parse', () {
    test('maps the wire strings already in API_CONTRACT.md', () {
      expect(ProblemCode.parse('not_found'), ProblemCode.notFound);
      expect(ProblemCode.parse('not_permitted'), ProblemCode.notPermitted);
      expect(ProblemCode.parse('conflict'), ProblemCode.conflict);
      expect(ProblemCode.parse('validation'), ProblemCode.validation);
      expect(ProblemCode.parse('authentication_expired'),
          ProblemCode.authenticationExpired);
      expect(
          ProblemCode.parse('upgrade_required'), ProblemCode.upgradeRequired);
    });

    test('an unknown, empty or null code is null, not a throw', () {
      expect(ProblemCode.parse('teleported_to_mars'), isNull);
      expect(ProblemCode.parse(''), isNull);
      expect(ProblemCode.parse(null), isNull);
    });

    test('every code round-trips through its wire string', () {
      for (final c in ProblemCode.values) {
        expect(ProblemCode.parse(c.wire), c, reason: c.name);
      }
    });
  });

  group('Problem.fromJson — RFC 9457 shape', () {
    test('reads type/title/status/detail/instance and the code extension', () {
      final p = Problem.fromJson(const {
        'type': 'https://mtm.app/problems/not-permitted',
        'title': 'Forbidden',
        'status': 403,
        'detail': 'user 4213 lacks scope shift.assign on d_9',
        'instance': '/api/v1/shifts/sh_1/assignments',
        'code': 'not_permitted',
      });

      expect(p.code, ProblemCode.notPermitted);
      expect(p.rawCode, 'not_permitted');
      expect(p.status, 403);
      expect(p.type, 'https://mtm.app/problems/not-permitted');
      expect(p.title, 'Forbidden');
      expect(p.detail, 'user 4213 lacks scope shift.assign on d_9');
      expect(p.instance, '/api/v1/shifts/sh_1/assignments');
      expect(p.isKnown, isTrue);
    });

    test('an unknown code keeps rawCode for diagnostics but does not branch',
        () {
      final p = Problem.fromJson(const {
        'status': 418,
        'detail': 'short and stout',
        'code': 'teapot',
      });
      expect(p.code, isNull);
      expect(p.isKnown, isFalse);
      expect(p.rawCode, 'teapot');
      expect(p.status, 418);
    });

    test('parses field errors from `errors` or `fields`', () {
      final a = Problem.fromJson(const {
        'code': 'validation',
        'errors': {'capacity': 'must be > 0', 'name': 'required'},
      });
      expect(a.fieldErrors, {'capacity': 'must be > 0', 'name': 'required'});

      final b = Problem.fromJson(const {
        'code': 'validation',
        'fields': {'capacity': 'must be > 0'},
      });
      expect(b.fieldErrors, {'capacity': 'must be > 0'});
    });

    test('tolerates the interim {error:{code,message,fields}} envelope', () {
      final p = Problem.fromJson(const {
        'error': {
          'code': 'conflict',
          'message': 'row version 7 != 8',
          'fields': {'startHour': 'overlaps sh_3'},
        },
      });
      expect(p.code, ProblemCode.conflict);
      expect(p.detail, 'row version 7 != 8');
      expect(p.fieldErrors, {'startHour': 'overlaps sh_3'});
    });

    test('reads an explicit support reference, never the instance URI', () {
      final withRef = Problem.fromJson(const {
        'code': 'server',
        'instance': '/api/v1/reports/rp_9',
        'reference': 'req_01HXYZ',
      });
      expect(withRef.reference, 'req_01HXYZ');

      final withoutRef = Problem.fromJson(const {
        'code': 'server',
        'instance': '/api/v1/reports/rp_9',
      });
      expect(withoutRef.reference, isNull,
          reason: 'instance is a URI, not a support code');
    });

    test('drops unnamed extension members rather than smuggling them', () {
      final p = Problem.fromJson(const {
        'code': 'server',
        'debugStackTrace': 'at Foo.bar (Foo.java:42)',
        'dbHost': 'pg-prod-3.internal',
      });
      // The model has nowhere to hold these, and that is the point.
      expect(p.toString(), isNot(contains('pg-prod-3')));
      expect(p.toString(), isNot(contains('Foo.java')));
    });

    test('field error map is unmodifiable', () {
      final p = Problem.fromJson(const {
        'code': 'validation',
        'fields': {'a': 'b'},
      });
      expect(() => p.fieldErrors['x'] = 'y', throwsUnsupportedError);
    });
  });

  group('Problem.isRetryable', () {
    test('true only for connectivity / server, never for an unknown code', () {
      expect(Problem.of(ProblemCode.offline).isRetryable, isTrue);
      expect(Problem.of(ProblemCode.network).isRetryable, isTrue);
      expect(Problem.of(ProblemCode.server).isRetryable, isTrue);
      expect(Problem.of(ProblemCode.notPermitted).isRetryable, isFalse);
      expect(Problem.of(ProblemCode.validation).isRetryable, isFalse);
      expect(const Problem.unknown('boom').isRetryable, isFalse);
    });
  });

  group('Result → Problem bridge', () {
    test('a coded failure becomes a typed problem, message kept as detail', () {
      const r = Failure<int>('لم يُعثر على المفرزة.', code: 'not_found');
      final p = r.problemOrNull!;
      expect(p.code, ProblemCode.notFound);
      expect(p.detail, 'لم يُعثر على المفرزة.');
      expect(p.rawCode, 'not_found');
    });

    test('a failure with no code is an unknown problem, not a crash', () {
      const r = Failure<int>('boom');
      final p = r.problemOrNull!;
      expect(p.code, isNull);
      expect(p.detail, 'boom');
    });

    test('offline becomes the offline problem', () {
      const r = Offline<int>();
      expect(r.problemOrNull!.code, ProblemCode.offline);
    });

    test('success has no problem', () {
      const r = Success<int>(1);
      expect(r.problemOrNull, isNull);
    });
  });
}
