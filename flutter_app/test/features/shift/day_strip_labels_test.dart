import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_guard.dart';
import 'package:mtm/core/format/app_date.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/detachment/presentation/tabs/detachment_shifts_tab.dart';

import '../render_fonts.dart';

/// The schedule's day strip: seven columns, seven different days.
///
/// The Phase 3C render review caught what a source read had not: both the
/// strip and the repeat picker abbreviated a weekday with
/// `AppDate.weekdayOf(d).substring(0, 2)`, and every Arabic weekday begins
/// «ال» — so all seven columns drew the same two characters. The row was a
/// decoration, not a label, and at 320 dp / 1.6× it was the only thing
/// distinguishing one column from another besides the date.
///
/// These hold the two halves of the fix: the initials are distinct, and the
/// column says its whole name to a screen reader, which one letter never
/// could.
void main() {
  const detachment = 'd_dam_central';

  // The real Arabic and icon faces: the tester's default font draws every
  // glyph as a fixed square, and a 1.6× assertion about whether seven
  // columns fit is only worth making against the metrics the app ships.
  setUpAll(loadRenderFonts);

  // A Saturday inside the seeded week, before any shift opens its attendance
  // window, so the strip renders the same way whenever the suite runs.
  DateTime now() => DateTime(2026, 9, 12, 9);

  Future<void> pump(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          capabilitiesProvider
              .overrideWithValue(const Capabilities(global: Cap.all)),
          clockProvider.overrideWithValue(now),
        ],
        child: MaterialApp(
          theme: AppTheme.light(PaletteId.medical),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: const Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: DetachmentShiftsTab(detachmentId: detachment),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  group('AppDate weekday initials', () {
    test('the seven are distinct — a two-letter prefix never was', () {
      final initials = [
        for (var weekday = 1; weekday <= 7; weekday++)
          AppDate.weekdayInitial(weekday),
      ];
      expect(initials.toSet(), hasLength(7));

      final prefixes = [
        for (var weekday = 1; weekday <= 7; weekday++)
          AppDate.weekdayName(weekday).substring(0, 2),
      ];
      expect(prefixes.toSet(), hasLength(1),
          reason: 'the old abbreviation collapsed all seven to «ال»');
    });

    test('each initial belongs to its own day name', () {
      for (var weekday = 1; weekday <= 7; weekday++) {
        expect(
          AppDate.weekdayName(weekday).contains(AppDate.weekdayInitial(weekday)),
          isTrue,
        );
      }
    });

    test('a date reads the same initial as its weekday number', () {
      final saturday = DateTime(2026, 9, 12);
      expect(saturday.weekday, DateTime.saturday);
      expect(AppDate.weekdayInitialOf(saturday), AppDate.weekdayInitial(6));
    });
  });

  group('the day strip', () {
    testWidgets('draws seven different weekday labels at 320 dp and 1.6×',
        (tester) async {
      await pump(tester, textScale: 1.6);

      final initials = {
        for (var weekday = 1; weekday <= 7; weekday++)
          AppDate.weekdayInitial(weekday),
      };
      for (final initial in initials) {
        expect(find.text(initial), findsOneWidget,
            reason: 'the column for «$initial» is missing');
      }
      expect(find.text('ال'), findsNothing);
    });

    testWidgets('each column is one node that says the whole day',
        (tester) async {
      await pump(tester);

      final week = startOfWeekFor(now());
      for (var offset = 0; offset < 7; offset++) {
        final day = DateTime(week.year, week.month, week.day + offset);
        final label = '${AppDate.weekdayOf(day)} ${AppDate.dayMonth(day)}';
        // At least one: the selected day is also named by the header above
        // the cards, and that is the point — the column and the header agree
        // on what the day is called.
        expect(
          find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}')),
          findsAtLeastNWidgets(1),
          reason: 'no day cell announces «$label»',
        );
      }
    });
  });
}

/// The Saturday on or before [d] — the same week boundary the schedule uses,
/// spelled here so the test does not depend on a private helper.
DateTime startOfWeekFor(DateTime d) {
  final date = DateTime(d.year, d.month, d.day);
  final back = (date.weekday - DateTime.saturday + 7) % 7;
  return DateTime(date.year, date.month, date.day - back);
}
