import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/conflict/domain/conflict_models.dart';
import 'package:mtm/features/conflict/presentation/conflict_resolution_page.dart';
import 'package:mtm/features/shift/domain/shift_models.dart';
import 'package:mtm/features/shift/presentation/shift_conflict_adapter.dart';
import 'package:mtm/features/team/domain/team_models.dart';
import 'package:mtm/l10n/strings.dart';

const _localManager = TeamMember(
  id: 'm_local',
  name: 'أحمد كنعان',
  initials: 'أك',
  role: TeamRole.shiftSupervisor,
  detachmentId: 'd1',
  attendance: AttendanceState.notCheckedIn,
);

const _currentManager = TeamMember(
  id: 'm_current',
  name: 'ريم الخطيب',
  initials: 'را',
  role: TeamRole.shiftSupervisor,
  detachmentId: 'd1',
  attendance: AttendanceState.notCheckedIn,
);

ConflictPresentation _shiftConflict() => presentShiftConflict(
      conflictId: 'conflict-1',
      localOperationId: 'operation-1',
      baseVersion: '7',
      currentVersion: '8',
      local: Shift(
        id: 'shift-1',
        detachmentId: 'd1',
        date: DateTime(2026, 9, 5),
        centerName: 'مركز داريا',
        startMinutes: 8 * 60,
        endMinutes: 14 * 60,
        needed: 4,
        attendees: const [_localManager],
      ),
      current: Shift(
        id: 'shift-1',
        detachmentId: 'd1',
        date: DateTime(2026, 9, 6),
        centerName: 'مركز داريا',
        startMinutes: 14 * 60,
        endMinutes: 20 * 60,
        needed: 6,
        attendees: const [_currentManager],
      ),
    );

Future<void> _pumpPage(
  WidgetTester tester, {
  ConflictPresentation? conflict,
  ConflictDecisionHandler? onDecision,
  Size size = const Size(450, 950),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      theme: AppTheme.light(PaletteId.medical),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: ConflictResolutionPage(
          conflict: conflict ?? _shiftConflict(),
          onDecision: onDecision ?? (_) async {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the Arabic conflict flow in RTL', (tester) async {
    await _pumpPage(tester);

    expect(find.text(S.conflictTitle), findsOneWidget);
    expect(find.text(S.conflictDescription), findsOneWidget);
    expect(find.text(S.conflictLocalVersion), findsOneWidget);
    expect(find.text(S.conflictCurrentVersion), findsOneWidget);
    expect(
      tester
          .widget<Directionality>(
            find
                .ancestor(
                  of: find.byType(ConflictResolutionPage),
                  matching: find.byType(Directionality),
                )
                .first,
          )
          .textDirection,
      TextDirection.rtl,
    );
  });

  testWidgets('local and current versions use distinct labelled treatments',
      (tester) async {
    await _pumpPage(tester);

    final localContainer = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(const Key('local-version-legend')),
            matching: find.byType(Container),
          )
          .first,
    );
    final currentContainer = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(const Key('current-version-legend')),
            matching: find.byType(Container),
          )
          .first,
    );
    final localDecoration = localContainer.decoration! as BoxDecoration;
    final currentDecoration = currentContainer.decoration! as BoxDecoration;

    expect(localDecoration.color, isNot(currentDecoration.color));
    expect(find.byIcon(Icons.edit_note_rounded), findsWidgets);
    expect(find.byIcon(Icons.groups_2_outlined), findsWidgets);
    expect(find.text(S.conflictLocalVersionSub), findsOneWidget);
    expect(find.text(S.conflictCurrentVersionSub), findsOneWidget);
  });

  testWidgets(
      'version legend and value cells announce their composed label once',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpPage(tester);

    // Each cell wraps its visible Text nodes in ExcludeSemantics behind a
    // single composed Semantics label, so a screen reader announces the
    // version once instead of the label followed by the same title/value
    // again from the descendant Text nodes.
    expect(
      find.bySemanticsLabel(
        '${S.conflictLocalVersion}، ${S.conflictLocalVersionSub}',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(S.conflictLocalVersion), findsNothing);
    expect(find.bySemanticsLabel(S.conflictLocalVersionSub), findsNothing);
    expect(find.bySemanticsLabel('أحمد كنعان'), findsNothing);

    handle.dispose();
  });

  testWidgets('presents only the differences supplied by the shift adapter',
      (tester) async {
    await _pumpPage(tester);

    expect(find.text(S.shiftManager), findsOneWidget);
    expect(find.text(S.conflictShiftDate), findsOneWidget);
    expect(find.text(S.conflictShiftTime), findsOneWidget);
    expect(find.text(S.shiftNeededLabel), findsOneWidget);
    expect(find.text('أحمد كنعان'), findsOneWidget);
    expect(find.text('ريم الخطيب'), findsOneWidget);
    // Same on both records, so the adapter does not add visual noise.
    expect(find.text(S.shiftCenter), findsNothing);
  });

  testWidgets('known shift fields use localized presentation labels',
      (tester) async {
    await _pumpPage(tester);

    expect(find.text(S.shiftManager), findsOneWidget);
    expect(find.text('shift_manager_id'), findsNothing);
    expect(find.text('start_minutes'), findsNothing);
    expect(find.text('needed'), findsNothing);
  });

  testWidgets('opaque identities, versions, and backend details are not shown',
      (tester) async {
    final safe = _shiftConflict();
    final conflict = ConflictPresentation(
      conflictId: 'Bearer secret-token',
      localOperationId: 'SQLSTATE 23505',
      entityType: 'shift_manager_id',
      entityId: '{"patient":"hidden"}',
      recordTitle: safe.recordTitle,
      recordSubtitle: safe.recordSubtitle,
      baseVersion: 'internal-base-version',
      currentVersion: 'internal-current-version',
      differences: safe.differences,
    );
    await _pumpPage(tester, conflict: conflict);

    for (final hidden in [
      'Bearer secret-token',
      'SQLSTATE 23505',
      'shift_manager_id',
      '{"patient":"hidden"}',
      'internal-base-version',
      'internal-current-version',
    ]) {
      expect(find.textContaining(hidden), findsNothing);
    }
  });

  testWidgets('keep-local emits the typed intent with stable operation data',
      (tester) async {
    ConflictResolutionDecision? emitted;
    await _pumpPage(tester, onDecision: (decision) async {
      emitted = decision;
    });

    await tester.tap(find.byKey(const Key('conflict-use-local')));
    await tester.pumpAndSettle();

    expect(emitted?.intent, ConflictResolutionIntent.useLocal);
    expect(emitted?.conflictId, 'conflict-1');
    expect(emitted?.localOperationId, 'operation-1');
    expect(emitted?.currentVersion, '8');
    expect(emitted?.resolvesConflict, isTrue);
  });

  testWidgets('use-current confirms first, then emits the typed intent',
      (tester) async {
    ConflictResolutionDecision? emitted;
    await _pumpPage(tester, onDecision: (decision) async {
      emitted = decision;
    });

    await tester.tap(find.byKey(const Key('conflict-use-current')));
    await tester.pumpAndSettle();

    // Nothing is decided by opening the confirmation.
    expect(find.text(S.conflictUseCurrentConfirmBody), findsOneWidget);
    expect(emitted, isNull);

    await tester.tap(find.byKey(const Key('conflict-use-current-confirm')));
    await tester.pumpAndSettle();

    expect(emitted?.intent, ConflictResolutionIntent.useCurrent);
    expect(emitted?.resolvesConflict, isTrue);
  });

  testWidgets('cancelling the confirmation discards nothing', (tester) async {
    ConflictResolutionDecision? emitted;
    await _pumpPage(tester, onDecision: (decision) async {
      emitted = decision;
    });

    await tester.tap(find.byKey(const Key('conflict-use-current')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conflict-use-current-cancel')));
    await tester.pumpAndSettle();

    expect(emitted, isNull);
    expect(find.byType(ConflictResolutionPage), findsOneWidget);
  });

  testWidgets('review later explicitly keeps the conflict unresolved',
      (tester) async {
    final unresolved = <String>{'conflict-1'};
    ConflictResolutionDecision? emitted;
    await _pumpPage(tester, onDecision: (decision) async {
      emitted = decision;
      if (decision.resolvesConflict) unresolved.remove(decision.conflictId);
    });

    await tester.tap(find.byKey(const Key('conflict-review-later')));
    await tester.pumpAndSettle();

    expect(emitted?.intent, ConflictResolutionIntent.reviewLater);
    expect(emitted?.resolvesConflict, isFalse);
    expect(unresolved, contains('conflict-1'));
  });

  testWidgets('system back persists review-later before leaving the screen',
      (tester) async {
    ConflictResolutionDecision? emitted;
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
                MaterialPageRoute<void>(
                  builder: (_) => ConflictResolutionPage(
                    conflict: _shiftConflict(),
                    onDecision: (decision) async {
                      emitted = decision;
                    },
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

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(emitted?.intent, ConflictResolutionIntent.reviewLater);
    expect(find.byType(ConflictResolutionPage), findsNothing);
    expect(find.byKey(const Key('open-conflict')), findsOneWidget);
  });

  testWidgets('a failed preservation callback keeps the conflict on screen',
      (tester) async {
    await _pumpPage(tester, onDecision: (_) async => throw StateError('fail'));

    await tester.tap(find.byKey(const Key('conflict-review-later')));
    await tester.pumpAndSettle();

    expect(find.byType(ConflictResolutionPage), findsOneWidget);
    expect(find.text(S.conflictDecisionFailed), findsOneWidget);
  });

  testWidgets('narrow phones keep the comparison readable without overflow',
      (tester) async {
    await _pumpPage(tester, size: const Size(320, 820));
    expect(tester.takeException(), isNull);
    expect(find.text(S.conflictUseLocal), findsOneWidget);
  });
}
