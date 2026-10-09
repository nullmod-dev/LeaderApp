import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mtm/core/network/api_client.dart';
import 'package:mtm/core/network/token_vault.dart';
import 'package:mtm/core/problem/problem.dart';
import 'package:mtm/core/problem/problem_presentation.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/storage/secure_store.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/onboarding_controller.dart';
import 'package:mtm/features/auth/data/secure_auth_state_store.dart';
import 'package:mtm/features/auth/domain/onboarding_models.dart';
import 'package:mtm/features/auth/domain/onboarding_repository.dart';
import 'package:mtm/features/auth/domain/session_access.dart';
import 'package:mtm/features/auth/presentation/device_trust_bar.dart';
import 'package:mtm/features/auth/presentation/device_trust_copy.dart';
import 'package:mtm/features/auth/presentation/email_verification_page.dart';
import 'package:mtm/features/auth/presentation/onboarding_ui.dart';
import 'package:mtm/l10n/strings.dart';

/// Device trust, D3: what the app reads from the server and says about it.
void main() {
  group('SessionAccess device fields', () {
    Map<String, dynamic> base() => {
          'accountStatus': 'active',
          'tenantStatus': 'active',
          'demoMode': 'none',
          'mfaRequired': false,
        };

    test('absent → no restriction, nothing pending, still normal', () {
      final access = SessionAccess.fromJson(base());
      expect(access.deviceRestriction, isNull);
      expect(access.pendingDeviceApprovals, isEmpty);
      expect(access, SessionAccess.normal);
    });

    test('a new device: reason and the instant it lifts', () {
      final access = SessionAccess.fromJson({
        ...base(),
        'deviceRestriction': const {
          'reason': 'new_device',
          'until': '2026-10-08T22:00:00.000Z',
        },
      });
      expect(access.deviceRestriction!.reason, DeviceRestrictionReason.newDevice);
      expect(access.deviceRestriction!.until, DateTime.utc(2026, 10, 8, 22));
      expect(access.hasUnsupportedState, isFalse);
      expect(SessionAccess.fromJson(access.toJson()), access);
    });

    test('the device limit has no end; an unknown reason is still restricted',
        () {
      final limit = SessionAccess.fromJson({
        ...base(),
        'deviceRestriction': const {'reason': 'device_limit'},
      });
      expect(limit.deviceRestriction!.reason, DeviceRestrictionReason.deviceLimit);
      expect(limit.deviceRestriction!.until, isNull);
      final unknown = SessionAccess.fromJson({
        ...base(),
        'deviceRestriction': const {'reason': 'something_new'},
      });
      expect(unknown.deviceRestriction!.reason, DeviceRestrictionReason.other);
    });

    test('pending approvals: well-formed rows kept, the rest dropped', () {
      final access = SessionAccess.fromJson({
        ...base(),
        'pendingDeviceApprovals': const [
          {
            'id': 'dv_1',
            'label': 'Android',
            'signedInAt': '2026-10-08T16:00:00.000Z'
          },
          {'id': '', 'signedInAt': '2026-10-08T16:00:00.000Z'},
          {'id': 'dv_2', 'signedInAt': '2026-10-08 16:00'},
          'nonsense',
        ],
      });
      expect(access.pendingDeviceApprovals.map((p) => p.id), ['dv_1']);
      expect(SessionAccess.fromJson(access.toJson()), access);
    });
  });

  group('codes and wording', () {
    test('a new-device challenge round-trips its purpose', () {
      final challenge = VerificationChallenge.fromJson(const {
        'challengeId': 'vc_1',
        'maskedEmail': 's***@hilal.org',
        'codeLength': 6,
        'purpose': 'new_device',
      });
      expect(challenge.purpose, VerificationPurpose.newDevice);
      expect(challenge.toJson()['purpose'], 'new_device');
    });

    test('session_restricted is its own inline, non-retryable sentence', () {
      final view = resolveProblem(Problem.of(ProblemCode.sessionRestricted));
      expect(view.message, S.errSessionRestricted);
      expect(view.title, S.errSessionRestrictedTitle);
      expect(view.retryable, isFalse);
      expect(failureMessage('session_restricted'), S.errSessionRestricted);
      expect(view.message, isNot(S.errNotPermitted));
    });

    test('device-trust sign-in refusals each have their sentence', () {
      String say(String code) => onboardingErrorMessage(
          onboardingErrorKindOf(Failure<void>('', code: code))!);
      expect(say('device_blocked'), S.onboardingDeviceBlocked);
      expect(say('password_reset_required'), S.onboardingPasswordResetRequired);
      expect(say('device_id_required'), S.onboardingAppUpdateRequired);
    });

    test('days left, in Arabic', () {
      expect(DeviceTrustCopy.days(const Duration(hours: 5)), S.daysLessThanOne);
      expect(DeviceTrustCopy.days(const Duration(days: 1, hours: 3)), S.daysOne);
      expect(DeviceTrustCopy.days(const Duration(days: 2)), S.daysTwo);
      expect(DeviceTrustCopy.days(const Duration(days: 6, hours: 23)), '٦ أيام');
    });
  });

  test('every request carries X-Device-Id once the client is given one',
      () async {
    final seen = <String?>[];
    final api = ApiClient(
      vault: TokenVault(SecureAuthStateStore(InMemorySecureStore())),
      origin: 'http://leader.test',
      client: MockClient((request) async {
        seen.add(request.headers['X-Device-Id']);
        return http.Response(jsonEncode({}), 200,
            headers: {'content-type': 'application/json'});
      }),
    );
    await api.exchange('GET', '/health', authenticated: false);
    api.deviceId = () async => '0f6d2c9e-4b1a-4c3d-9e8f-1a2b3c4d5e6f';
    await api.exchange('POST', '/auth/sign-in', body: {}, authenticated: false);
    await api.exchange('GET', '/auth/me');
    expect(seen, [
      null,
      '0f6d2c9e-4b1a-4c3d-9e8f-1a2b3c4d5e6f',
      '0f6d2c9e-4b1a-4c3d-9e8f-1a2b3c4d5e6f',
    ]);
  });

  group('the code screen for a new device', () {
    Future<void> pump(WidgetTester tester, VerificationPurpose purpose) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authEntryStateProvider.overrideWithValue(EntryVerificationPending(
            VerificationChallenge(
              handle: 'vc_1',
              maskedEmail: 's***@hilal.org',
              purpose: purpose,
            ),
          )),
        ],
        child: MaterialApp(
          theme: AppTheme.light(PaletteId.medical),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: EmailVerificationPage(),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('says why a code is asked, and offers another account',
        (tester) async {
      await pump(tester, VerificationPurpose.newDevice);
      expect(find.text(S.newDeviceVerificationTitle), findsOneWidget);
      expect(find.textContaining(S.newDeviceCodeSentTo), findsOneWidget);
      expect(find.text(S.useAnotherAccount), findsOneWidget);
    });
  });

  group('DeviceTrustBar', () {
    Future<void> pump(WidgetTester tester, SessionAccess access,
        {ThemeData? theme, double width = 390, double scale = 1}) async {
      tester.view.physicalSize = Size(width * 3, 2400);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
            body: Column(children: [
              DeviceTrustBar(),
              Expanded(child: SizedBox.expand()),
            ]),
          ),
        ),
        GoRoute(
          path: '/new-device',
          builder: (_, __) => const Scaffold(body: Text('approval')),
        ),
      ]);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionAccessOverrideProvider.overrideWith((ref) => access),
        ],
        child: MaterialApp.router(
          theme: theme ?? AppTheme.light(PaletteId.medical),
          routerConfig: router,
          builder: (context, child) =>
              Directionality(textDirection: TextDirection.rtl, child: child!),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('nothing for an ordinary session', (tester) async {
      await pump(tester, SessionAccess.normal);
      expect(find.byKey(const Key('device-restricted-bar')), findsNothing);
      expect(find.byKey(const Key('device-pending-bar')), findsNothing);
    });

    testWidgets('a new device says until when', (tester) async {
      final until = DateTime.now().toUtc().add(const Duration(hours: 5));
      await pump(
        tester,
        SessionAccess(
          deviceRestriction: DeviceRestriction(
              reason: DeviceRestrictionReason.newDevice, until: until),
        ),
      );
      expect(find.byKey(const Key('device-restricted-bar')), findsOneWidget);
      expect(
          find.text(
              '${S.deviceRestrictedBanner}${DeviceTrustCopy.moment(until)}'),
          findsOneWidget);
    });

    testWidgets('an untrusted device has its own sentence (dark, 320dp, 1.6×)',
        (tester) async {
      await pump(
        tester,
        const SessionAccess(
          deviceRestriction:
              DeviceRestriction(reason: DeviceRestrictionReason.deviceLimit),
        ),
        theme: AppTheme.dark(PaletteId.medical),
        width: 320,
        scale: 1.6,
      );
      expect(find.text(S.deviceLimitBanner), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a trusted device is asked, and the review opens the prompt',
        (tester) async {
      await pump(
        tester,
        SessionAccess(pendingDeviceApprovals: [
          PendingDeviceApproval(
            id: 'dv_1',
            label: 'Android',
            signedInAt: DateTime.utc(2026, 10, 8, 16),
          ),
        ]),
        width: 320,
        scale: 1.6,
      );
      expect(find.text(S.pendingDeviceBanner), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('device-pending-review')));
      await tester.pumpAndSettle();
      expect(find.text('approval'), findsOneWidget);
    });
  });
}
