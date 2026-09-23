import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/widgets/offline_banner.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/auth_repository.dart';
import 'package:mtm/features/settings/presentation/security_page.dart';
import 'package:mtm/l10n/strings.dart';

/// What the Security screen must never say, and what it must never let happen
/// by accident.
///
/// Layout is inspected by hand; these cover the two things a screenshot does
/// not show — a status claimed without data behind it, and a destructive
/// control reachable without a confirmation.
void main() {
  testWidgets('two-step verification is reported as unknown, never as enabled',
      (tester) async {
    // `AuthUser` carries no MFA field and no endpoint answers the question.
    // The screen said "مفعّل" unconditionally before; that was a claim about
    // the account the app had no basis for.
    await _pump(tester, Success(_sessions));

    expect(find.byKey(const Key('security-mfa-row')), findsOneWidget);
    expect(find.text(S.securityMfa), findsOneWidget);
    expect(find.text(S.securityMfaUnknown), findsOneWidget);
    expect(find.text(S.securityMfaNote), findsOneWidget);
    // The word the old screen used for "enabled", wherever it came from.
    expect(find.text('مفعّل'), findsNothing);
  });

  testWidgets('the password action is the reset flow, not a pretend change',
      (tester) async {
    // The backend has `password-reset/request → verify → complete` and no
    // authenticated change-password endpoint. Offering one would be a button
    // that cannot work.
    await _pump(tester, Success(_sessions));

    expect(find.byKey(const Key('security-password-row')), findsOneWidget);
    expect(find.text(S.profilePasswordReset), findsOneWidget);
    expect(find.text(S.profilePasswordResetSub), findsOneWidget);
  });

  testWidgets('this session is named and cannot be ended from the list',
      (tester) async {
    await _pump(tester, Success(_sessions));

    expect(find.byKey(const Key('security-current-session')), findsOneWidget);
    expect(find.text(S.securityCurrentSession), findsOneWidget);
    // No revoke control on the current row — ending it is sign-out, and the
    // screen says where that is.
    expect(find.byKey(const Key('security-revoke-s_cur')), findsNothing);
    expect(find.text(S.securityCurrentSessionNote), findsOneWidget);
    // Which is on screen, once.
    expect(find.byKey(const Key('security-sign-out')), findsOneWidget);

    // The other device does get one.
    expect(find.byKey(const Key('security-revoke-s_2')), findsOneWidget);
  });

  testWidgets(
      'ending another session asks first, and a cancelled dialog '
      'sends nothing', (tester) async {
    final repo = _FakeAuthRepo();
    await _pump(tester, Success(_sessions), repo: repo);

    await tester.tap(find.byKey(const Key('security-revoke-s_2')));
    await tester.pumpAndSettle();
    expect(find.text(S.securityRevokeConfirm), findsOneWidget);
    expect(find.text(S.securityRevokeConfirmBody), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, S.cancel));
    await tester.pumpAndSettle();

    expect(repo.revokeCalls, isEmpty);
    expect(find.byKey(const Key('security-session-s_2')), findsOneWidget);
  });

  testWidgets('a session list that fails keeps the rest of the screen',
      (tester) async {
    // The account section and the way out do not depend on the network, so a
    // failed session read must not take them down with it.
    await _pump(tester, const Failure('boom', code: 'server'));

    expect(find.byKey(const Key('security-sessions-problem')), findsOneWidget);
    expect(find.byKey(const Key('security-mfa-row')), findsOneWidget);
    expect(find.byKey(const Key('security-password-row')), findsOneWidget);
    expect(find.byKey(const Key('security-sign-out')), findsOneWidget);
    // And nothing raw from the server.
    expect(find.text('boom'), findsNothing);
  });

  testWidgets(
      'offline with a cached list still shows the devices, marked '
      'stale', (tester) async {
    await _pump(tester, Offline(cached: _sessions));

    expect(find.byKey(const Key('security-session-s_cur')), findsOneWidget);
    expect(find.byType(StaleBadge), findsOneWidget);
  });

  testWidgets('offline with nothing cached is a state, not a blank',
      (tester) async {
    await _pump(tester, const Offline());

    expect(find.byKey(const Key('security-sessions-offline')), findsOneWidget);
    expect(find.byKey(const Key('security-sign-out')), findsOneWidget);
  });

  testWidgets('a revoke in flight disables its own row', (tester) async {
    final repo = _FakeAuthRepo(hold: true);
    await _pump(tester, Success(_sessions), repo: repo);

    await tester.tap(find.byKey(const Key('security-revoke-s_2')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, S.settingsRevoke));
    // Enough for the dialog to leave and the row to rebuild, not enough for
    // the held request to answer.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final button = tester.widget<TextButton>(
      find.byKey(const Key('security-revoke-s_2')),
    );
    expect(button.onPressed, isNull, reason: 'a second tap has nothing to hit');

    repo.release();
    await tester.pumpAndSettle();
  });
}

/// A fixed instant: these tests are about the rows, not about the clock.
final _startedAt = DateTime(2026, 9, 6, 8);

final _sessions = <Session>[
  Session(
    id: 's_cur',
    device: 'هاتف المشرف',
    ipMasked: '176.29.xx.xx',
    locationLabel: 'دمشق, سوريا',
    startedAt: _startedAt,
    current: true,
  ),
  Session(
    id: 's_2',
    device: 'حاسوب المكتب',
    ipMasked: '82.137.xx.xx',
    locationLabel: 'حمص, سوريا',
    startedAt: _startedAt,
    current: false,
  ),
];

Future<void> _pump(
  WidgetTester tester,
  Result<List<Session>> sessions, {
  _FakeAuthRepo? repo,
}) async {
  tester.view.physicalSize = const Size(1080, 3600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  // The same pre-existing `ListTile`-inside-a-decorated-card complaint the
  // Settings hub tests already tolerate.
  final inherited = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details
        .toString()
        .contains('ListTile background color or ink splashes')) {
      return;
    }
    inherited?.call(details);
  };
  addTearDown(() => FlutterError.onError = inherited);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo ?? _FakeAuthRepo()),
        sessionsProvider.overrideWith((ref) async => sessions),
      ],
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: SecurityPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeAuthRepo implements AuthRepository {
  _FakeAuthRepo({this.hold = false});

  /// Keeps a revoke in flight until [release], so the in-progress state can
  /// be observed.
  final bool hold;
  final _gate = Completer<void>();
  final List<String> revokeCalls = [];

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<Result<void>> revokeSession(String id) async {
    revokeCalls.add(id);
    if (hold) await _gate.future;
    return const Success(null);
  }

  @override
  Future<Result<List<Session>>> listSessions() async => Success(_sessions);

  @override
  Future<Result<void>> signOut() async => const Success(null);

  @override
  Future<Result<AuthUser?>> currentUser() async =>
      const Success<AuthUser?>(null);

  @override
  Future<Result<MfaSetupData>> beginMfaSetup() async => const Failure('unused');

  @override
  Future<Result<void>> verifyMfa(String code) async => const Success(null);

  @override
  Future<Result<void>> requestPasswordReset(String email) async =>
      const Success(null);

  @override
  Future<Result<void>> verifyResetOtp(String email, String code) async =>
      const Success(null);

  @override
  Future<Result<void>> setNewPassword(String password) async =>
      const Success(null);

  @override
  Future<Result<void>> confirmNewDevice({required bool itsMe}) async =>
      const Success(null);

  @override
  Future<Result<AuthUser>> signIn({
    required String emailOrUsername,
    required String password,
  }) async =>
      const Failure('unused');
}
