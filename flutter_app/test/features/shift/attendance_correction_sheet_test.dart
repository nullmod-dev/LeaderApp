import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_guard.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/shift/data/shift_providers.dart';
import 'package:mtm/features/shift/domain/shift_models.dart';
import 'package:mtm/features/shift/presentation/shift_assign_sheet.dart';
import 'package:mtm/features/team/domain/team_models.dart';
import 'package:mtm/l10n/strings.dart';

/// The attendance sheet's three modes — ordinary (window open), read-only
/// (window closed, no override) and correction-only (window closed, override
/// held) — and the append-only correction it appends in the last one.
///
/// Every shift here is built directly (never through `MockShiftRepository`'s
/// seed, which is anchored to the real wall clock) so the one-hour window is
/// deterministically open or closed regardless of when the suite runs.

const _authorId = 'auth-user-raw-id-should-never-render';
const _testUser = AuthUser(
  id: _authorId,
  name: 'سامر المشرف',
  email: 'x@example.com',
  role: AuthRole.mainAdmin,
  saasTenantId: 'saas_test',
  capabilities: Capabilities.none,
  orgName: 'org',
);

T _ok<T>(Result<T> r) => r.when(
      success: (data, {stale = false}) => data,
      failure: (m, code) => fail('expected success, got failure: $m ($code)'),
      offline: (_) => fail('expected success, got offline'),
    );

// Every repository call is wrapped in `tester.runAsync` — the mock's
// `_latency()` is a real `Future.delayed`, which never resolves under
// `AutomatedTestWidgetsFlutterBinding`'s fake-async zone unless it runs in
// the real zone `runAsync` provides. Same convention as
// `shift_manage_sheet_test.dart`'s `_staffedShift`.
Future<(Shift, TeamMember)> _seedShift(
  WidgetTester tester,
  ProviderContainer container, {
  required DateTime date,
  required int startMinutes,
  required int endMinutes,
}) async {
  final repository = container.read(shiftRepositoryProvider);
  final assigned = await tester.runAsync(() async {
    final created = _ok(await repository.create(
      detachmentId: 'd_dam_central',
      date: date,
      centerName: 'مركز الاختبار',
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      needed: 1,
    ));
    final candidate = _ok(await repository.candidatesFor(created.id))
        .firstWhere((c) => !c.busy);
    return _ok(
        await repository.assignVolunteer(created.id, candidate.member.id));
  });
  return (assigned!, assigned.attendees.single);
}

/// Capability/user overrides only — the container is otherwise the same one
/// [_seedShift] writes into, so the shift the widget opens actually exists in
/// the repository it reads from.
ProviderContainer _container(Capabilities capabilities) => ProviderContainer(
      overrides: [
        capabilitiesProvider.overrideWithValue(capabilities),
        currentUserProvider.overrideWith((ref) async => _testUser),
      ],
    );

Future<void> _pumpAttendanceSheet(
  WidgetTester tester, {
  required ProviderContainer container,
  required Shift shift,
  required TeamMember member,
}) async {
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.slate),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showAttendanceSheet(
                    context: context,
                    ref: ref,
                    shift: shift,
                    member: member,
                    canUnassign: false,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  group('ordinary mode — window open', () {
    testWidgets('shows the ordinary controls, no correction action, no warning',
        (tester) async {
      final container = _container(const Capabilities(
        scoped: {
          'd_dam_central': {Cap.shiftAttendanceRecord},
        },
      ));
      addTearDown(container.dispose);
      final (shift, member) = await _seedShift(
        tester,
        container,
        // A full day ahead, 00:00-01:00 — so the shift has not even started
        // yet, let alone reached its one-hour-after-end window, regardless
        // of what time of day the suite happens to run.
        date: DateTime.now().add(const Duration(days: 1)),
        startMinutes: 0,
        endMinutes: 60,
      );

      await _pumpAttendanceSheet(
        tester,
        container: container,
        shift: shift,
        member: member,
      );

      expect(find.text(S.checkInDateTime), findsOneWidget);
      expect(find.text(S.checkedIn), findsOneWidget);
      expect(find.text(S.addCorrection), findsNothing);
      expect(find.text(S.attendanceWindowClosedOrdinary), findsNothing);
    });
  });

  group('read-only mode — window closed, no override', () {
    testWidgets(
        'an ordinary-expired session sees a read-only explanation and no '
        'mutation control', (tester) async {
      final container = _container(const Capabilities(
        scoped: {
          'd_dam_central': {Cap.shiftAttendanceRecord},
        },
      ));
      addTearDown(container.dispose);
      final (shift, member) = await _seedShift(
        tester,
        container,
        date: DateTime.now().subtract(const Duration(days: 3)),
        startMinutes: 8 * 60,
        endMinutes: 9 * 60,
      );

      await _pumpAttendanceSheet(
        tester,
        container: container,
        shift: shift,
        member: member,
      );

      expect(find.text(S.attendanceWindowClosedOrdinary), findsOneWidget);
      expect(find.text(S.addCorrection), findsNothing);
      expect(find.text(S.checkInDateTime), findsNothing);
      expect(find.text(S.editCheckIn), findsNothing);
    });
  });

  group('correction-only mode — window closed, override held', () {
    testWidgets(
        'shows the correction action, rejects a blank reason, appends a '
        'correction with the actor name and reason, never a raw id, and '
        'keeps prior corrections visible', (tester) async {
      final container = _container(const Capabilities(
        scoped: {
          'd_dam_central': {Cap.shiftAttendanceOverride},
        },
      ));
      addTearDown(container.dispose);
      final (shift, member) = await _seedShift(
        tester,
        container,
        date: DateTime.now().subtract(const Duration(days: 3)),
        startMinutes: 8 * 60,
        endMinutes: 9 * 60,
      );

      await _pumpAttendanceSheet(
        tester,
        container: container,
        shift: shift,
        member: member,
      );

      // Window closed + override held => the correction action, not the
      // ordinary controls, and no unnecessary read-only warning either.
      expect(find.text(S.addCorrection), findsOneWidget);
      expect(find.text(S.checkInDateTime), findsNothing);
      expect(find.text(S.attendanceWindowClosedOrdinary), findsNothing);

      await tester.tap(find.text(S.addCorrection));
      await tester.pumpAndSettle();

      // A blank reason is rejected before the repository is even asked.
      await tester.tap(find.text(S.saveCorrection));
      await tester.pumpAndSettle();
      expect(find.text(S.correctionReasonRequired), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('correction-reason-field')),
        '  نسي المشرف تسجيل الحضور خلال الشفت  ',
      );
      // Leave the default status (notCheckedIn) and switch it to checked-in.
      await tester.tap(find.text(S.checkedIn));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('save-correction-button')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // The form closed and the current-attendance line moved.
      expect(find.text(S.correctionReasonRequired), findsNothing);
      expect(find.text(S.checkedIn), findsWidgets);

      // The history shows who and why, in Arabic, and never the raw id.
      expect(find.text(S.correctionHistoryTitle), findsOneWidget);
      expect(find.textContaining(_testUser.name), findsOneWidget);
      expect(find.textContaining('نسي المشرف تسجيل الحضور خلال الشفت'),
          findsOneWidget);
      expect(find.textContaining(_authorId), findsNothing);
      expect(find.textContaining(_testUser.email), findsNothing);

      // A second correction appends alongside the first rather than
      // replacing it — both stay visible.
      await tester.tap(find.text(S.addCorrection));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('correction-reason-field')),
        'تصحيح ثانٍ لاحق لتأكيد الغياب',
      );
      await tester.tap(find.text(S.absent));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-correction-button')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.textContaining('نسي المشرف تسجيل الحضور خلال الشفت'),
          findsOneWidget);
      expect(
          find.textContaining('تصحيح ثانٍ لاحق لتأكيد الغياب'), findsOneWidget);
    });
  });
}
