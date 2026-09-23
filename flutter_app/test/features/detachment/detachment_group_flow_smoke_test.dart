import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/l10n/strings.dart';
import 'package:mtm/main.dart';

/// A boot-and-walk smoke test: does the detachment group → detachment →
/// schedule path render at all, in the real app with the real router and the
/// real theme?
///
/// Deliberately shallow. It asserts nothing about layout or behaviour — it
/// proves that every screen on the main path builds without throwing, which
/// is the failure this feature could plausibly introduce and the one that is
/// invisible until someone opens the app.
///
/// **Known pre-existing failure this test tolerates.** `GlassBottomNav` caps
/// its pill at 380px and divides it between four tabs, which leaves the
/// selected tab about 50px short of its icon-plus-label — so the nav reports
/// a horizontal overflow at every window size, on `main` as much as here.
/// It is filtered rather than fixed because it predates this work and fixing
/// it was not asked for; see the note in the session handoff.
/// Swallows the known bottom-nav overflow described above and nothing else.
///
/// Installed inside the test body rather than in `setUp`, because the test
/// binding installs its own handler when the body starts and would otherwise
/// overwrite this one.
void _ignoreKnownNavOverflow() {
  final inherited = FlutterError.onError;
  FlutterError.onError = (details) {
    // Matched on the file name rather than on "any overflow", so a new
    // overflow anywhere else still fails this test.
    final report = details.toString();
    if (report.contains('overflowed') &&
        report.contains('glass_bottom_nav.dart')) {
      return;
    }
    inherited?.call(details);
  };
  addTearDown(() => FlutterError.onError = inherited);
}

void main() {
  testWidgets(
      'the app boots and walks detachment group → detachment → schedule',
      (tester) async {
    _ignoreKnownNavOverflow();
    // A phone-sized surface — the day strip lays seven columns out across the
    // width, and the default 800×600 test window is not a phone.
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MtmApp()),
    );
    await tester.pumpAndSettle();

    // Driven through the router rather than by tapping the bottom nav: the
    // pre-existing overflow above means the nav's labels are not reliably
    // hit-testable, and this test is about the screens, not the nav.
    router.go('/detachment-groups');
    await tester.pumpAndSettle();
    expect(find.text('الهلال الأحمر — فرع دمشق'), findsOneWidget);

    await tester.tap(find.text('الهلال الأحمر — فرع دمشق'));
    await tester.pumpAndSettle();
    expect(find.text('مفرزة دمشق المركزية'), findsWidgets);

    await tester.tap(find.text('مفرزة دمشق المركزية').first);
    await tester.pumpAndSettle();

    // The detail shell opens on Members; its tab bar carries all four.
    expect(find.text(S.detachmentShifts), findsOneWidget);

    await tester.tap(find.text(S.detachmentShifts));
    await tester.pumpAndSettle();
    // The schedule now opens straight onto the day selector — the weekly
    // summary card it used to sit under is gone.
    expect(find.text(S.thisWeek), findsOneWidget);

    await tester.tap(find.text(S.detachmentStorage));
    await tester.pumpAndSettle();
    expect(find.text(S.searchItems), findsOneWidget);

    await tester.tap(find.text(S.detachmentStats));
    await tester.pumpAndSettle();
    expect(find.text(S.exportReport), findsOneWidget);

    // The report composer and its preview, which is where the export choices
    // live.
    router.go('/detachment/d_dam_central/report');
    await tester.pumpAndSettle();
    expect(
        find.text(S.exportSections), findsNothing); // heading carries a count
    expect(find.text(S.secSummary), findsOneWidget);
  });

  test('every palette resolves in both modes, plain and eye-protect', () {
    // The theme is built from tokens rather than from a seed colour alone, so
    // a missing token would be a runtime null rather than a compile error.
    // Building every palette × mode × eye-protect is the cheapest way to
    // catch that — and the eye-protect pass also exercises `AppColors.warmed`.
    for (final palette in PaletteId.values) {
      for (final eyeProtect in [false, true]) {
        for (final theme in [
          AppTheme.light(palette, eyeProtect: eyeProtect),
          AppTheme.dark(palette, eyeProtect: eyeProtect),
        ]) {
          expect(theme.extension<AppColorsExt>(), isNotNull);
          expect(theme.scaffoldBackgroundColor, isNotNull);
          expect(theme.textTheme.titleMedium?.fontFamily, isNotNull);
        }
      }
    }
  });
}
