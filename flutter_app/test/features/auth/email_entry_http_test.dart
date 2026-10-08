import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mtm/core/network/api_client.dart';
import 'package:mtm/core/network/token_vault.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/storage/secure_store.dart';
import 'package:mtm/features/auth/data/http_onboarding_repository.dart';
import 'package:mtm/features/auth/data/secure_auth_state_store.dart';
import 'package:mtm/features/auth/domain/onboarding_models.dart';
import 'package:mtm/features/auth/domain/onboarding_repository.dart';

http.Response _json(int status, Object body, [Map<String, String>? headers]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json', ...?headers});

/// `POST /auth/email-status` and `POST /auth/sign-in/code` on the wire, as
/// `emailEntryController.js` answers them.
void main() {
  late List<http.Request> requests;
  late http.Response Function(http.Request) reply;
  late SecureAuthStateStore authState;
  late HttpOnboardingRepository repo;

  setUp(() {
    requests = [];
    authState = SecureAuthStateStore(InMemorySecureStore());
    repo = HttpOnboardingRepository(
      ApiClient(
        vault: TokenVault(authState),
        origin: 'http://leader.test',
        client: MockClient((request) async {
          requests.add(request);
          return reply(request);
        }),
      ),
      authState,
      deviceId: () async => 'device-1',
    );
  });

  group('email-status', () {
    test('sends the address with this install\'s id and reads the status',
        () async {
      for (final (wire, status) in [
        ('registered', EmailEntryStatus.registered),
        ('invited', EmailEntryStatus.invited),
        ('new', EmailEntryStatus.fresh),
      ]) {
        reply = (_) => _json(200, {'status': wire});
        final r = await repo.checkEmailStatus('a@b.co');
        expect((r as Success).data, status);
      }
      final request = requests.last;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/auth/email-status');
      expect(jsonDecode(request.body), {'email': 'a@b.co'});
      expect(request.headers['X-Device-Id'], 'device-1');
      expect(request.headers.containsKey('Authorization'), isFalse);
    });

    test('a status this build does not know fails closed', () async {
      reply = (_) => _json(200, {'status': 'banned'});
      final r = await repo.checkEmailStatus('a@b.co');
      expect((r as Failure).code, 'server');
    });

    test('a 429 is rate_limited, with its retry instant', () async {
      reply = (_) => _json(429, {
            'error': {'code': 'rate_limited', 'retryAfterSeconds': 600},
          }, {
            'retry-after': '600'
          });
      final r = await repo.checkEmailStatus('a@b.co');
      expect(onboardingErrorKindOf(r), OnboardingErrorKind.rateLimited);
      expect((r as OnboardingFailure).retryAvailableAt, isNotNull);
    });
  });

  group('sign-in/code', () {
    test('a 202 challenge is held for a restart, worded for a sign-in',
        () async {
      reply = (_) => _json(202, {
            'challengeId': 'vc_1',
            'maskedEmail': 'a***@b.co',
            'codeLength': 6,
            'expiresAt': '2026-10-08T10:10:00.000Z',
            'resendAvailableAt': '2026-10-08T10:01:00.000Z',
            'attemptsRemaining': 5,
            'purpose': 'sign_in',
          });
      final r = await repo.requestSignInCode('a@b.co');
      final challenge = (r as Success<VerificationChallenge>).data;
      expect(challenge.purpose, VerificationPurpose.signIn);
      expect(challenge.maskedEmail, 'a***@b.co');

      final request = requests.single;
      expect(request.url.path, '/api/v1/auth/sign-in/code');
      expect(jsonDecode(request.body), {'email': 'a@b.co'});
      expect(request.headers['X-Device-Id'], 'device-1');
      expect(request.headers.containsKey('Idempotency-Key'), isFalse);

      final restored = await repo.restore();
      final held = ((restored as Success).data as EntryVerificationPending)
          .challenge;
      expect(held, challenge);
    });

    test('a malformed challenge is refused, and nothing is kept', () async {
      reply = (_) => _json(202, {'challengeId': 'vc_1'});
      final r = await repo.requestSignInCode('a@b.co');
      expect((r as Failure).code, 'server');
      expect(await authState.readOnboarding(), isNull);
    });
  });
}
