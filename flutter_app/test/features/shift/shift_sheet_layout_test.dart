import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/shift/data/shift_providers.dart';
import 'package:mtm/features/shift/domain/shift_models.dart';
import 'package:mtm/features/shift/presentation/shift_edit_sheet.dart';

T _success<T>(Result<T> result) => result.when(
      success: (data, {stale = false}) => data,
      failure: (message, code) => fail('$message ($code)'),
      offline: (_) => fail('offline'),
    );

void main() {
  testWidgets(
      'small RTL screen keeps sticky save tappable above app and system navigation',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 48, top: 24);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48, top: 24);
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final day = dateOnly(DateTime.now()).add(const Duration(days: 10));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(PaletteId.slate),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.6),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: MotionScope(
                level: MotionLevel.reduced,
                child: child!,
              ),
            ),
          ),
          home: Scaffold(
            body: Stack(
              children: [
                Builder(
                  builder: (context) => Center(
                    child: FilledButton(
                      onPressed: () => showShiftEditor(
                        context: context,
                        detachmentId: 'd_dam_central',
                        date: day,
                        defaultCenter: 'Layout test center',
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                ),
                // A stand-in for MainShell's floating bottom navigation:
                // opaque and tappable, painted after the page body, exactly
                // like the bar that used to swallow the Save button.
                Align(
                  alignment: Alignment.bottomCenter,
                  child: GestureDetector(
                    onTap: () {},
                    child: Container(
                      key: const Key('application-bottom-navigation'),
                      height: 80,
                      width: double.infinity,
                      color: const Color(0xFF202020),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final save = find.byKey(const Key('shift-save-button'));
    expect(save, findsOneWidget);
    expect(save.hitTestable(), findsOneWidget);
    expect(find.byKey(const Key('shift-form-scroll')), findsOneWidget);

    // Above Android's system navigation: the action's bottom edge stays
    // inside the 48px the view reserves at the bottom.
    final saveBottom = tester.getBottomRight(save).dy;
    expect(saveBottom, lessThanOrEqualTo(640 - 48));

    // Above the application's own bottom navigation: the root-navigator sheet
    // and its barrier are painted over the bar, so the bar can no longer be
    // hit while the Save button can.
    expect(
      find.byKey(const Key('application-bottom-navigation')).hitTestable(),
      findsNothing,
    );

    // The form scrolls on its own; the action does not scroll away with it.
    final actionBefore = tester.getRect(find.byKey(const Key(
      'shift-sticky-action',
    )));
    await tester.drag(
        find.byKey(const Key('shift-form-scroll')), const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const Key('shift-sticky-action'))),
      actionBefore,
    );
    expect(save.hitTestable(), findsOneWidget);

    await tester.tap(save);
    await tester.pumpAndSettle();
    final persisted = await tester.runAsync(
      () => container
          .read(shiftRepositoryProvider)
          .listForRange('d_dam_central', day, day),
    );
    final after = _success(persisted!);
    expect(after, hasLength(1));
    expect(
        after.any((shift) => shift.centerName == 'Layout test center'), isTrue);
  });

  testWidgets('keyboard inset moves the sticky action into the reachable area',
      (tester) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 24, top: 24);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24, top: 24);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(PaletteId.slate),
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showShiftEditor(
                context: context,
                detachmentId: 'd_dam_central',
                date: dateOnly(DateTime.now()),
                defaultCenter: 'Keyboard center',
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    final save = find.byKey(const Key('shift-save-button'));
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(720 - 300));
  });

  testWidgets('a large tablet viewport keeps the action on screen',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 32, top: 40);
    tester.view.viewPadding = const FakeViewPadding(bottom: 32, top: 40);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(PaletteId.slate),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showShiftEditor(
                    context: context,
                    detachmentId: 'd_dam_central',
                    date: dateOnly(DateTime.now()),
                    defaultCenter: 'Tablet center',
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final save = find.byKey(const Key('shift-save-button'));
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(1600 - 32));
  });

  testWidgets('LTR layout keeps the same reachable sticky action',
      (tester) async {
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          theme: AppTheme.light(PaletteId.slate),
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showShiftEditor(
                context: context,
                detachmentId: 'd_dam_central',
                date: dateOnly(DateTime.now()),
                defaultCenter: 'LTR center',
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shift-save-button')).hitTestable(),
        findsOneWidget);
  });
}
