import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/shift/data/mock_shift_repository.dart';
import 'package:mtm/features/shift/data/shift_providers.dart';
import 'package:mtm/features/shift/domain/shift_models.dart';
import 'package:mtm/features/shift/domain/shift_repository.dart';
import 'package:mtm/features/shift/presentation/shift_edit_sheet.dart';
import 'package:mtm/features/team/data/mock_team_repository.dart';
import 'package:mtm/l10n/strings.dart';

/// Functional counterpart to `shift_sheet_layout_test.dart`: that file proves
/// the Save control can be reached, this one proves pressing it does the work.
T _success<T>(Result<T> result) => result.when(
      success: (data, {stale = false}) => data,
      failure: (message, code) => fail('$message ($code)'),
      offline: (_) => fail('offline'),
    );

/// The real mock, with one deliberately broken write.
class _FailingCreateRepository extends MockShiftRepository {
  _FailingCreateRepository() : super(MockTeamRepository());

  @override
  Future<Result<Shift>> create({
    required String detachmentId,
    required DateTime date,
    required String centerName,
    required int startMinutes,
    required int endMinutes,
    required int needed,
    List<DateTime> repeatOn = const [],
  }) async =>
      const Failure('تعذّر حفظ الشفت.', code: 'server');
}

const _saveButton = Key('shift-save-button');
const _saveError = Key('shift-save-error');

Future<ProviderContainer> _openEditor(
  WidgetTester tester, {
  required DateTime day,
  required String center,
  ShiftRepository? repository,
}) async {
  final container = ProviderContainer(
    overrides: [
      if (repository != null)
        shiftRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.slate),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showShiftEditor(
                    context: context,
                    detachmentId: 'd_dam_central',
                    date: day,
                    defaultCenter: center,
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
  expect(find.byKey(_saveButton), findsOneWidget);
  return container;
}

Future<List<Shift>> _shiftsOn(
  WidgetTester tester,
  ProviderContainer container,
  DateTime day,
) async {
  final result = await tester.runAsync(
    () => container
        .read(shiftRepositoryProvider)
        .listForRange('d_dam_central', day, day),
  );
  return _success(result!);
}

void main() {
  testWidgets('Save writes the shift, closes the sheet, and the shift is there',
      (tester) async {
    final day = addDays(dateOnly(DateTime.now()), 40);
    final container = await _openEditor(
      tester,
      day: day,
      center: 'مركز الحفظ',
    );

    expect(await _shiftsOn(tester, container, day), isEmpty);

    await tester.tap(find.byKey(_saveButton));
    await tester.pump();

    // Loading state: the action reports itself busy and refuses a second press.
    expect(
      find.descendant(
        of: find.byKey(_saveButton),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byKey(_saveButton)).onPressed,
      isNull,
    );

    await tester.pumpAndSettle();

    // Success state: the sheet is gone and the confirmation is shown.
    expect(find.byKey(_saveButton), findsNothing);
    expect(find.text(S.shiftSaved), findsOneWidget);

    // Persistence: the repository — the running app's source of truth — now
    // holds the shift, and a fresh read after the sheet closed returns it.
    final saved = await _shiftsOn(tester, container, day);
    expect(saved, hasLength(1));
    expect(saved.single.centerName, 'مركز الحفظ');
    expect(saved.single.date, day);
    expect(saved.single.detachmentId, 'd_dam_central');

    // And it is in the week the schedule screen actually reads.
    final week = await tester.runAsync(
      () => container.read(
        weekShiftsProvider(
          WeekQuery(detachmentId: 'd_dam_central', weekStart: day),
        ).future,
      ),
    );
    expect(
      _success(week!).any((shift) => shift.centerName == 'مركز الحفظ'),
      isTrue,
    );
  });

  testWidgets('a double press creates one shift, not two', (tester) async {
    final day = addDays(dateOnly(DateTime.now()), 41);
    final container = await _openEditor(
      tester,
      day: day,
      center: 'مركز التكرار',
    );

    await tester.tap(find.byKey(_saveButton));
    await tester.pump();
    // The second press lands while the first is still in flight.
    await tester.tap(find.byKey(_saveButton), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(await _shiftsOn(tester, container, day), hasLength(1));
  });

  testWidgets('an empty centre is refused and nothing is written',
      (tester) async {
    final day = addDays(dateOnly(DateTime.now()), 42);
    final container = await _openEditor(
      tester,
      day: day,
      center: 'مركز مؤقت',
    );

    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_saveButton));
    await tester.pumpAndSettle();

    expect(find.text(S.required), findsOneWidget);
    // The sheet stays open on a validation failure.
    expect(find.byKey(_saveButton), findsOneWidget);
    expect(await _shiftsOn(tester, container, day), isEmpty);
  });

  testWidgets('a repository failure is shown and the sheet stays open',
      (tester) async {
    final day = dateOnly(DateTime.now()).add(const Duration(days: 43));
    await _openEditor(
      tester,
      day: day,
      center: 'مركز الفشل',
      repository: _FailingCreateRepository(),
    );

    await tester.tap(find.byKey(_saveButton));
    await tester.pumpAndSettle();

    expect(find.byKey(_saveError), findsOneWidget);
    expect(find.text('تعذّر حفظ الشفت.'), findsOneWidget);
    expect(find.byKey(_saveButton), findsOneWidget);
    // Recovered: the button is live again rather than stuck busy.
    expect(
      tester.widget<FilledButton>(find.byKey(_saveButton)).onPressed,
      isNotNull,
    );
  });
}
