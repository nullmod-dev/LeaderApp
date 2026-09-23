import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/shift/data/shift_providers.dart';
import 'package:mtm/features/shift/domain/shift_models.dart';
import 'package:mtm/features/shift/presentation/shift_assign_sheet.dart';
import 'package:mtm/features/team/data/team_providers.dart';
import 'package:mtm/l10n/strings.dart';

T _success<T>(Result<T> result) => result.when(
      success: (data, {stale = false}) => data,
      failure: (message, code) => fail('$message ($code)'),
      offline: (_) => fail('offline'),
    );

void main() {
  testWidgets(
      'assignment offers normalized search, duplicate selection, tap, drag, and genuine creation',
      (tester) async {
    tester.view.physicalSize = const Size(450, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final repository = container.read(shiftRepositoryProvider);
    final shiftResult = await tester.runAsync(
      () => repository.listForWeek(
        'd_dam_central',
        startOfWeek(DateTime.now()),
      ),
    );
    final shift = _success(shiftResult!).first;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(PaletteId.slate),
          home: Consumer(
            builder: (context, ref, _) => FilledButton(
              onPressed: () => showAssignSheet(
                context: context,
                ref: ref,
                shift: shift,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('member-search-field')), findsOneWidget);
    expect(find.byKey(const Key('selected-member-drop-zone')), findsOneWidget);
    expect(find.byType(LongPressDraggable<ShiftCandidate>), findsWidgets);

    final candidatesResult = await tester.runAsync(
      () => repository.candidatesFor(shift.id),
    );
    final existing = _success(candidatesResult!).firstWhere((x) => !x.busy);
    await tester.enterText(
      find.byKey(const Key('manual-member-name')),
      '  ${existing.member.name.replaceAll(' ', '   ')}  ',
    );
    await tester.tap(find.byKey(const Key('manual-member-add')));
    await tester.pumpAndSettle();
    expect(find.text(S.duplicateMemberName), findsOneWidget);
    expect(find.text(existing.member.name), findsWidgets);

    await tester.tap(find.text(existing.member.name).last);
    await tester.pumpAndSettle();
    expect(find.text(S.memberAssigned), findsOneWidget);

    const newName = 'New Manual Member';
    await tester.enterText(
      find.byKey(const Key('manual-member-name')),
      '  New   Manual   Member  ',
    );
    await tester.tap(find.byKey(const Key('manual-member-add')));
    await tester.pumpAndSettle();
    expect(find.text(S.memberCreatedAndAssigned), findsOneWidget);
    expect(find.text(newName), findsWidgets);

    final rosterResult = await tester.runAsync(
      () => container
          .read(teamRepositoryProvider)
          .listForDetachment(shift.detachmentId),
    );
    final roster = _success(rosterResult!);
    final created = roster.singleWhere((member) => member.name == newName);
    final savedShiftResult =
        await tester.runAsync(() => repository.byId(shift.id));
    final savedShift = _success(savedShiftResult!);
    expect(
        savedShift.attendees.any((member) => member.id == created.id), isTrue);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'search narrows the list, a drag assigns, and a repeated name '
      'never creates a second record', (tester) async {
    tester.view.physicalSize = const Size(450, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final repository = container.read(shiftRepositoryProvider);
    final shift = _success(
      (await tester.runAsync(
        () => repository.listForWeek(
          'd_dam_central',
          startOfWeek(DateTime.now()),
        ),
      ))!,
    ).first;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(PaletteId.slate),
          home: Consumer(
            builder: (context, ref, _) => FilledButton(
              onPressed: () =>
                  showAssignSheet(context: context, ref: ref, shift: shift),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final free = _success(
      (await tester.runAsync(() => repository.candidatesFor(shift.id)))!,
    ).where((candidate) => !candidate.busy).toList();
    expect(free.length, greaterThanOrEqualTo(2));

    // Search: a name typed with sloppy spacing and the wrong case still finds
    // its member, and nothing else.
    final target = free.first.member;
    await tester.enterText(
      find.byKey(const Key('member-search-field')),
      '  ${target.name.toUpperCase().replaceAll(' ', '    ')} ',
    );
    await tester.pumpAndSettle();
    expect(find.byType(LongPressDraggable<ShiftCandidate>), findsOneWidget);
    expect(find.text(target.name), findsOneWidget);

    // A nonsense query says so rather than showing an empty box.
    await tester.enterText(
      find.byKey(const Key('member-search-field')),
      'zzzz no such member',
    );
    await tester.pumpAndSettle();
    expect(find.text(S.noMatchingMembers), findsOneWidget);

    // Drag: long-press the row and drop it on the selected-members zone.
    await tester.enterText(find.byKey(const Key('member-search-field')), '');
    await tester.pumpAndSettle();
    final row = find.byType(LongPressDraggable<ShiftCandidate>).first;
    final dragged =
        tester.widget<LongPressDraggable<ShiftCandidate>>(row).data!.member;
    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(
      tester.getCenter(find.byKey(const Key('selected-member-drop-zone'))),
    );
    await tester.pump();
    // The row is really being dragged — its childWhenDragging placeholder is
    // on screen — so the assignment below cannot be a mistaken tap.
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Opacity && widget.opacity == .35,
      ),
      findsOneWidget,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text(S.memberAssigned), findsOneWidget);
    final afterDrag =
        _success((await tester.runAsync(() => repository.byId(shift.id)))!);
    expect(
      afterDrag.attendees.any((member) => member.id == dragged.id),
      isTrue,
      reason: 'the dropped member is on the shift',
    );

    // Creating the same manual name twice points at the first record instead
    // of quietly adding a second one.
    const name = 'Duplicate Candidate';
    await tester.enterText(
        find.byKey(const Key('manual-member-name')), '  $name  ');
    await tester.tap(find.byKey(const Key('manual-member-add')));
    await tester.pumpAndSettle();
    expect(find.text(S.memberCreatedAndAssigned), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('manual-member-name')), 'duplicate   CANDIDATE');
    await tester.tap(find.byKey(const Key('manual-member-add')));
    await tester.pumpAndSettle();
    expect(find.text(S.duplicateMemberName), findsOneWidget);

    final roster = _success(
      (await tester.runAsync(
        () => container
            .read(teamRepositoryProvider)
            .listForDetachment(shift.detachmentId),
      ))!,
    );
    expect(
      roster.where((member) => member.name == name),
      hasLength(1),
      reason: 'one person, one roster record',
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });
}
