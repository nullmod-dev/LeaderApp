import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_guard.dart';
import 'package:mtm/core/chart/series_card.dart';
import 'package:mtm/core/chart/series_scale.dart';
import 'package:mtm/core/format/app_number.dart';
import 'package:mtm/core/motion/animated_counter.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/core/widgets/reading_column.dart';
import 'package:mtm/features/detachment/data/detachment_providers.dart';
import 'package:mtm/features/detachment/domain/detachment_models.dart';
import 'package:mtm/features/detachment/presentation/tabs/detachment_stats_tab.dart';
import 'package:mtm/features/inventory/data/inventory_providers.dart';
import 'package:mtm/features/inventory/domain/inventory_models.dart';
import 'package:mtm/features/shift/data/shift_providers.dart';
import 'package:mtm/features/shift/domain/shift_models.dart';
import 'package:mtm/features/team/data/team_providers.dart';
import 'package:mtm/features/team/domain/team_models.dart';
import 'package:mtm/l10n/strings.dart';

/// Statistics, after Phase 3A.
///
/// UI audit P1-10 ("the charts cannot be read") and P1-11 (the ` · ` that is
/// «٠» beside Arabic-Indic numerals). These tests hold the two claims the
/// screen now makes: that a bar's height is a reading against a *stated*
/// scale, and that everything the picture says is also said in words.

const _det = 'd1';
final _now = DateTime(2026, 9, 12, 9);

const _stats = DetachmentStats(
  attendanceSeries: [72, 78, 81, 88, 84, 92, 90],
  coverageSeries: [70, 74, 78, 82, 86, 90, 92],
  stockSeries: [12, 18, 9, 22, 15, 30, 24],
);

Shift _shift(String id, int day, {int needed = 2, int assigned = 2}) => Shift(
      id: id,
      detachmentId: _det,
      date: DateTime(2026, 9, day),
      centerName: 'مركز الشعلان',
      startMinutes: 8 * 60,
      endMinutes: 14 * 60,
      needed: needed,
      attendees: [
        for (var i = 0; i < assigned; i++)
          TeamMember(
            id: '$id-m$i',
            name: 'عضو $i',
            initials: 'ع',
            role: TeamRole.member,
            detachmentId: _det,
            attendance: AttendanceState.checkedOut,
            checkInAt: DateTime(2026, 9, day, 8),
            checkOutAt: DateTime(2026, 9, day, 14),
          ),
      ],
    );

Future<void> _pump(
  WidgetTester tester, {
  DetachmentStats stats = _stats,
  List<Shift> week = const [],
  double width = 390,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width * 2, 4200 * textScale);
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(() => _now),
        capabilitiesProvider
            .overrideWithValue(const Capabilities(scoped: {_det: Cap.scoped})),
        detachmentStatsProvider.overrideWith((ref, id) async => Success(stats)),
        teamListProvider.overrideWith(
          (ref, id) async => const Success<List<TeamMember>>([]),
        ),
        weekShiftsProvider.overrideWith((ref, q) async => Success(week)),
        inventoryListProvider.overrideWith(
          (ref, id) async => const Success<List<InventoryItem>>([]),
        ),
        attendanceStatisticsProvider.overrideWith(
          (ref, q) async => const Success(AttendanceStatistics(members: [])),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: DetachmentStatsTab(detachmentId: _det)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// `TabularDigits` lays every numeral out in its own equal-width cell, so a
/// figure it paints is not one `Text` a finder can match. This addresses the
/// widget instead.
Finder _digits(String value) => find.byWidgetPredicate(
      (w) => w is TabularDigits && w.text == value,
      description: 'TabularDigits("$value")',
    );

void main() {
  group('a series states the scale it is drawn against', () {
    testWidgets('a percentage card says 0–100, whatever its own peak is',
        (tester) async {
      await _pump(tester);

      expect(
        find.text('${S.statsScale} ${AppNumber.range(0, 100)}'
            '${S.percentSign}'),
        findsOneWidget,
      );
      // The coverage card is drawn against 100 even though its peak is 92.
      final coverage = tester
          .widgetList<SeriesCard>(find.byType(SeriesCard))
          .firstWhere((card) => card.title == S.statsCoverage);
      expect(coverage.plot.unit, SeriesUnit.percent);
      expect(coverage.plot.domainMax, 100);
    });

    testWidgets('a count card says the round ceiling it chose', (tester) async {
      await _pump(tester);

      expect(find.text('${S.statsScale} ${AppNumber.range(0, 50)}'),
          findsOneWidget);
      final stock = tester
          .widgetList<SeriesCard>(find.byType(SeriesCard))
          .firstWhere((card) => card.title == S.statsStock);
      expect(stock.plot.unit, SeriesUnit.count);
      expect(stock.plot.domainMax, 50);
    });

    testWidgets('the two units are never put on one scale', (tester) async {
      await _pump(tester);
      final cards = tester.widgetList<SeriesCard>(find.byType(SeriesCard));
      expect(cards.map((c) => c.plot.domainMax).toSet().length, 2);
    });
  });

  group('the period and the days are on the card, not inferred', () {
    testWidgets('the range is printed and the last day is today',
        (tester) async {
      await _pump(tester);
      // Seven readings ending on the pinned day: ٦ أيلول – ١٢ أيلول.
      expect(find.text('٦ أيلول – ١٢ أيلول'), findsNWidgets(2));
      // A day number under every bar, both cards.
      expect(_digits('١٢'), findsNWidgets(2));
      expect(_digits('٦'), findsNWidgets(2));
    });

    testWidgets('the section heading no longer carries a joined period',
        (tester) async {
      await _pump(tester);
      expect(find.text(S.statsCoverage), findsOneWidget);
      expect(find.textContaining('·'), findsNothing);
    });
  });

  group('everything the picture says is also said in words', () {
    testWidgets('the latest reading, the high, the average and the change',
        (tester) async {
      await _pump(tester);

      expect(find.text('${S.statsLatest} ${AppNumber.percent(92)}'),
          findsOneWidget);
      expect(find.text('${S.statsLatest} ${AppNumber.count(24)}'),
          findsOneWidget);
      // Change is a word plus a bare figure — never an arrow, never a colour,
      // and never «٢٪» for two points on a 0–100 scale.
      expect(
        find.text(S.statsChangeUp.replaceFirst('%s', AppNumber.count(2))),
        findsOneWidget,
      );
      expect(
        find.text(S.statsChangeDown.replaceFirst('%s', AppNumber.count(6))),
        findsOneWidget,
      );
    });

    testWidgets('a reader who gets no chart still gets the metric',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      final spoken =
          tester.getSemantics(find.byKey(const Key('series-coverage'))).label;
      for (final fragment in [
        S.statsCoverage,
        '٦ أيلول – ١٢ أيلول',
        AppNumber.percent(92),
        AppNumber.percent(82),
        S.statsScale,
      ]) {
        expect(spoken.contains(fragment), isTrue,
            reason: 'the spoken card must carry «$fragment»: $spoken');
      }
      handle.dispose();
    });

    testWidgets('a series that cannot be drawn honestly is not drawn',
        (tester) async {
      await _pump(
        tester,
        stats: const DetachmentStats(
          attendanceSeries: [0, 0, 0, 0, 0, 0, 0],
          coverageSeries: [0, 0, 0, 0, 0, 0, 0],
          stockSeries: [0, 0, 0, 0, 0, 0, 0],
        ),
      );

      expect(find.text(S.statsSeriesAllZero), findsNWidgets(2));
      expect(find.text('${S.statsLatest} ${AppNumber.percent(0)}'),
          findsNothing);
    });
  });

  group('one percentage path', () {
    testWidgets('no screen appends a bare sign, and the Latin % is gone',
        (tester) async {
      await _pump(tester, week: [_shift('a', 7), _shift('b', 8)]);

      expect(find.textContaining('%'), findsNothing);
      // The coverage tile reads through `AppNumber.percent`.
      expect(_digits(AppNumber.percent(100)), findsOneWidget);
    });

    testWidgets(
        'a week with no shifts reports no coverage rather than a perfect '
        'one', (tester) async {
      // `WeekSummary.coveragePercent` answers 100 when nothing is needed —
      // true as a fraction, false as a statement on a screen.
      await _pump(tester);
      expect(_digits(AppNumber.percent(100)), findsNothing);
      expect(_digits('—'), findsOneWidget);
    });
  });

  group('the measure policy', () {
    testWidgets('Statistics is a working column and does not stretch at 900 dp',
        (tester) async {
      await _pump(tester, width: 900);

      expect(tester.takeException(), isNull);
      final card = tester.getSize(find.byType(SeriesCard).first);
      expect(card.width, lessThanOrEqualTo(kContentMaxWidth));
      expect(card.width, greaterThan(kContentMaxWidth - 2 * AppSpacing.lg - 1));
    });

    testWidgets('320 dp at 1.6x keeps every tile label readable',
        (tester) async {
      await _pump(tester, width: 320, textScale: 1.6);

      expect(tester.takeException(), isNull);
      // The four glance tiles reflow to two columns rather than truncating
      // «أدوية منخفضة» into «أدوية…».
      final low = tester.getSize(find.text(S.stockLow));
      const tileRowWidth = 320 - 2 * AppSpacing.lg;
      expect(low.width, lessThan(tileRowWidth / 2));
      for (final label in [S.statsMembers, S.statsShifts, S.weekCoverage]) {
        expect(find.text(label), findsOneWidget);
      }
    });
  });
}
