import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/shift/data/shift_providers.dart';
import 'package:mtm/features/shift/domain/shift_models.dart';
import 'package:mtm/features/shift/presentation/shift_manage_sheet.dart';
import 'package:mtm/l10n/strings.dart';

/// The per-shift management sheet: it opens with a summary, lists every
/// assigned member as a readable row (full name, not a 12px pill), and shows
/// exactly the actions the caller's capabilities allow.

T _ok<T>(Result<T> r) => r.when(
      success: (data, {stale = false}) => data,
      failure: (m, c) => fail('$m ($c)'),
      offline: (_) => fail('offline'),
    );

Future<Shift> _staffedShift(WidgetTester tester, ProviderContainer c) async {
  final repo = c.read(shiftRepositoryProvider);
  final week = await tester.runAsync(
      () => repo.listForWeek('d_dam_central', startOfWeek(DateTime.now())));
  return _ok(week!).firstWhere((s) => s.attendees.isNotEmpty);
}

Future<void> _open(
  WidgetTester tester,
  ProviderContainer container,
  Shift shift, {
  bool canAssign = true,
  bool canRecord = true,
  bool canOverride = true,
  bool canManage = true,
  bool canDelete = true,
}) async {
  tester.view.physicalSize = const Size(450, 900);
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
                  onPressed: () => showShiftManageSheet(
                    context: context,
                    ref: ref,
                    shift: shift,
                    detachmentId: 'd_dam_central',
                    canAssign: canAssign,
                    canRecord: canRecord,
                    canOverride: canOverride,
                    canManage: canManage,
                    canDelete: canDelete,
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
  testWidgets('shows a readable row per assigned member and all actions',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final shift = await _staffedShift(tester, container);

    await _open(tester, container, shift);

    // Every attendee's full name is on screen — the sheet shows the full list.
    for (final a in shift.attendees) {
      expect(find.text(a.name), findsOneWidget);
    }

    // The capability-gated actions are all present.
    expect(
        find.widgetWithText(FilledButton, S.assignVolunteer), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, S.editShift), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, S.deleteShift), findsOneWidget);
  });

  testWidgets('without manage/assign/delete caps only attendance remains',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final shift = await _staffedShift(tester, container);

    await _open(tester, container, shift,
        canAssign: false, canManage: false, canDelete: false);

    expect(find.widgetWithText(FilledButton, S.assignVolunteer), findsNothing);
    expect(find.widgetWithText(OutlinedButton, S.editShift), findsNothing);
    expect(find.widgetWithText(OutlinedButton, S.deleteShift), findsNothing);
    // The attendee rows are still there for attendance recording.
    expect(find.text(shift.attendees.first.name), findsOneWidget);
  });

  testWidgets('tapping an attendee row opens the attendance sheet',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final shift = await _staffedShift(tester, container);

    await _open(tester, container, shift);

    await tester.tap(find.text(shift.attendees.first.name));
    await tester.pumpAndSettle();

    expect(find.textContaining(S.attendanceSheetTitle), findsOneWidget);
    // Same latency-timer drain other repository-backed sheets in this suite
    // already need at teardown (see `member_assignment_sheet_test.dart`).
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });
}
