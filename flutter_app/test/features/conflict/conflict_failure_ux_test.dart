import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/conflict/domain/conflict_models.dart';
import 'package:mtm/features/conflict/presentation/conflict_resolution_page.dart';
import 'package:mtm/l10n/strings.dart';

/// What the conflict screen does when the resolution does not go through
/// (roadmap §7, §10, §16, §17).
///
/// Two rules are being held here. A choice the user cannot complete must say
/// *why* in plain Arabic — never "تعذّر حفظ اختيارك" for a conflict somebody
/// else already resolved. And a conflict that no longer exists in the form
/// shown must close, while one that could still be resolved must stay open
/// with both choices intact.
ConflictPresentation _conflict() => ConflictPresentation(
      conflictId: 'conflict-1',
      localOperationId: 'operation-1',
      entityType: 'shift',
      entityId: 'shift-1',
      recordTitle: 'الشفت · مركز داريا',
      currentVersion: '8',
      differences: const [
        ConflictFieldComparison(
          fieldId: 'needed',
          label: 'العدد المطلوب',
          localValue: '٤',
          currentValue: '٦',
        ),
      ],
    );

/// Pushes the screen onto a host route, so "did it close?" is observable.
Future<void> _pushPage(
  WidgetTester tester, {
  required ConflictDecisionHandler onDecision,
}) async {
  tester.view.physicalSize = const Size(450, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(PaletteId.medical),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            key: const Key('open-conflict'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<Object?>(
                builder: (_) => ConflictResolutionPage(
                  conflict: _conflict(),
                  onDecision: onDecision,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.byKey(const Key('open-conflict')));
  await tester.pumpAndSettle();
}

ConflictDecisionHandler _throwing(ConflictResolutionFailure reason) =>
    (_) async => throw ConflictResolutionException(reason, 'test');

void main() {
  testWidgets('two taps in one frame make one decision', (tester) async {
    var calls = 0;
    await _pushPage(tester, onDecision: (_) async => calls++);

    // No frame is built between the taps, so the disabled state cannot be
    // what saves this — the guard has to.
    await tester.tap(find.byKey(const Key('conflict-use-local')));
    await tester.tap(find.byKey(const Key('conflict-use-local')));
    await tester.pumpAndSettle();

    expect(calls, 1);
  });

  testWidgets('a conflict resolved elsewhere says so and closes',
      (tester) async {
    await _pushPage(
      tester,
      onDecision: _throwing(ConflictResolutionFailure.alreadyResolved),
    );

    await tester.tap(find.byKey(const Key('conflict-use-local')));
    await tester.pumpAndSettle();

    expect(find.text(S.conflictAlreadyResolved), findsOneWidget);
    expect(find.text(S.conflictDecisionFailed), findsNothing);
    expect(find.byType(ConflictResolutionPage), findsNothing,
        reason: 'a choice that can never apply is not offered again');
    expect(find.byKey(const Key('open-conflict')), findsOneWidget);
  });

  testWidgets('a record that moved again asks to be reviewed afresh',
      (tester) async {
    await _pushPage(
      tester,
      onDecision: _throwing(ConflictResolutionFailure.recordChanged),
    );

    await tester.tap(find.byKey(const Key('conflict-use-local')));
    await tester.pumpAndSettle();

    expect(find.text(S.conflictRecordChanged), findsOneWidget);
    expect(find.byType(ConflictResolutionPage), findsNothing);
  });

  testWidgets('a deleted record is explained, and the screen stays open',
      (tester) async {
    await _pushPage(
      tester,
      onDecision: _throwing(ConflictResolutionFailure.recordDeleted),
    );

    await tester.tap(find.byKey(const Key('conflict-use-current')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conflict-use-current-confirm')));
    await tester.pumpAndSettle();

    expect(find.text(S.conflictRecordDeleted), findsOneWidget);
    expect(find.byType(ConflictResolutionPage), findsOneWidget);
    // Both choices are still there — nothing was consumed by the attempt.
    expect(find.byKey(const Key('conflict-use-local')), findsOneWidget);
  });

  testWidgets('a refused permission never reads as a lost change',
      (tester) async {
    await _pushPage(
      tester,
      onDecision: _throwing(ConflictResolutionFailure.notPermitted),
    );

    await tester.tap(find.byKey(const Key('conflict-use-local')));
    await tester.pumpAndSettle();

    expect(find.text(S.conflictNotPermitted), findsOneWidget);
    expect(find.byType(ConflictResolutionPage), findsOneWidget);
  });

  testWidgets('a resolution that needs the network says which, and waits',
      (tester) async {
    await _pushPage(
      tester,
      onDecision: _throwing(ConflictResolutionFailure.offline),
    );

    await tester.tap(find.byKey(const Key('conflict-use-current')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conflict-use-current-confirm')));
    await tester.pumpAndSettle();

    expect(find.text(S.conflictOfflineDecision), findsOneWidget);
    expect(find.byType(ConflictResolutionPage), findsOneWidget);
  });

  testWidgets('the buttons come back after a failure, so a retry is possible',
      (tester) async {
    var calls = 0;
    await _pushPage(tester, onDecision: (_) async {
      calls++;
      if (calls == 1) {
        throw ConflictResolutionException(
          ConflictResolutionFailure.couldNotApply,
          'test',
        );
      }
    });

    await tester.tap(find.byKey(const Key('conflict-use-local')));
    await tester.pumpAndSettle();
    expect(find.text(S.conflictDecisionFailed), findsOneWidget);

    await tester.tap(find.byKey(const Key('conflict-use-local')));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.byType(ConflictResolutionPage), findsNothing);
  });
}
