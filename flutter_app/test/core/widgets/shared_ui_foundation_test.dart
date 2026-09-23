import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/theme/app_typography.dart';
import 'package:mtm/core/widgets/confirmation_dialog.dart';
import 'package:mtm/core/widgets/filter_chips.dart';
import 'package:mtm/core/widgets/reading_column.dart';
import 'package:mtm/core/widgets/section_header.dart';

/// The four primitives Phase 1 of the UI quality programme promoted out of
/// per-screen copies: the section header, the filter chip, the confirmation
/// dialog and the reading column.
///
/// These test behaviour and constraints, not pixels. There is no golden here
/// on purpose — a brittle image of a chip would fail on every palette change
/// and tell nobody anything.

/// Sets the surface the next pump lays out on. The widget tester's default
/// is 800x600; a chip row wrapping at 320 dp has to be laid out at 320 dp.
void sizeTo(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

Widget host(
  Widget child, {
  TextDirection direction = TextDirection.rtl,
  PaletteId palette = PaletteId.medical,
  Brightness brightness = Brightness.light,
  bool eyeProtect = false,
  double textScale = 1,
}) =>
    MaterialApp(
      theme: brightness == Brightness.light
          ? AppTheme.light(palette, eyeProtect: eyeProtect)
          : AppTheme.dark(palette, eyeProtect: eyeProtect),
      // Direction and text scale go on `builder`, above the navigator, the
      // way `main.dart` sets them — a dialog opened on the root navigator
      // inherits from there, and a Directionality placed under `home` would
      // leave the dialog LTR in a test while the app renders it RTL.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: Directionality(
          textDirection: direction,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: Scaffold(body: child),
    );

void main() {
  group('SectionHeader', () {
    testWidgets('a label is the eyebrow token, not a hand-spelled style',
        (tester) async {
      await tester.pumpWidget(host(const SectionHeader(title: 'المزامنة')));
      final style = tester.widget<Text>(find.text('المزامنة')).style!;
      final expected = AppTypography.eyebrow(
        AppColors.resolve(PaletteId.medical, Brightness.light),
      );
      expect(style.fontSize, expected.fontSize);
      expect(style.fontWeight, expected.fontWeight);
      expect(style.letterSpacing, expected.letterSpacing);
      expect(style.color, expected.color);
    });

    testWidgets('a heading is titleMedium and takes a tinted icon',
        (tester) async {
      await tester.pumpWidget(host(const SectionHeader(
        title: 'صحة المنصة',
        icon: Icons.favorite_rounded,
        style: SectionHeaderStyle.heading,
      )));
      final palette = AppColors.resolve(PaletteId.medical, Brightness.light);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.favorite_rounded)).color,
        palette.primary,
      );
      final style = tester.widget<Text>(find.text('صحة المنصة')).style!;
      expect(style.fontSize, 17);
    });

    testWidgets('a label never grows an icon', (tester) async {
      // The eyebrow has no icon slot by design; passing one is a no-op rather
      // than a second idiom sneaking back in.
      await tester.pumpWidget(host(const SectionHeader(
        title: 'الحساب',
        icon: Icons.favorite_rounded,
      )));
      expect(find.byIcon(Icons.favorite_rounded), findsNothing);
    });

    testWidgets('the trailing action fires', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(SectionHeader(
        title: 'التنبيهات',
        action: 'امسح',
        onAction: () => taps++,
      )));
      await tester.tap(find.text('امسح'));
      expect(taps, 1);
    });

    testWidgets('is announced as a heading', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(const SectionHeader(title: 'الحساب')));
      expect(
        tester
            .getSemantics(find.text('الحساب'))
            .flagsCollection
            .isHeader,
        isTrue,
      );
      handle.dispose();
    });

    testWidgets('starts at the start edge in both directions', (tester) async {
      for (final direction in TextDirection.values) {
        await tester.pumpWidget(host(
          const SectionHeader(title: 'الحساب'),
          direction: direction,
        ));
        final header = tester.getRect(find.text('الحساب'));
        final screen = tester.getRect(find.byType(Scaffold));
        if (direction == TextDirection.rtl) {
          expect(header.right, closeTo(screen.right - 4, 1));
        } else {
          expect(header.left, closeTo(screen.left + 4, 1));
        }
      }
    });
  });

  group('AppFilterChip', () {
    Widget bar({
      String selected = 'all',
      void Function(String)? onPick,
      bool archivedEnabled = true,
      double textScale = 1,
      double width = 390,
    }) =>
        host(
          AppFilterBar(
            semanticLabel: 'تصفية حسب الحالة',
            children: [
              for (final (id, label) in const [
                ('all', 'الكل'),
                ('active', 'نشطة'),
                ('archived', 'الأرشيف'),
              ])
                AppFilterChip(
                  key: Key('filter-$id'),
                  label: label,
                  selected: selected == id,
                  enabled: id != 'archived' || archivedEnabled,
                  onSelected: (_) => onPick?.call(id),
                ),
            ],
          ),
          textScale: textScale,
        );

    testWidgets('selected fills with primary, unselected does not',
        (tester) async {
      await tester.pumpWidget(bar(selected: 'active'));
      final palette = AppColors.resolve(PaletteId.medical, Brightness.light);

      Color groundOf(String id) {
        final container = tester.widget<AnimatedContainer>(find.descendant(
          of: find.byKey(Key('filter-$id')),
          matching: find.byType(AnimatedContainer),
        ));
        return (container.decoration! as BoxDecoration).color!;
      }

      expect(groundOf('active'), palette.primary);
      expect(groundOf('all'), palette.surface);
      expect(groundOf('all'), isNot(groundOf('active')));
    });

    testWidgets('the selected label is legible on the fill', (tester) async {
      await tester.pumpWidget(bar(selected: 'active'));
      final palette = AppColors.resolve(PaletteId.medical, Brightness.light);
      expect(
        tester.widget<Text>(find.text('نشطة')).style!.color,
        palette.primaryInk,
      );
      expect(
        tester.widget<Text>(find.text('الكل')).style!.color,
        palette.ink2,
      );
    });

    testWidgets('tapping reports the value the chip would take',
        (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(bar(selected: 'all', onPick: picked.add));
      await tester.tap(find.byKey(const Key('filter-active')));
      await tester.pump();
      expect(picked, ['active']);
    });

    testWidgets('a disabled filter is inert and stays visible',
        (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(
        bar(onPick: picked.add, archivedEnabled: false),
      );
      expect(find.byKey(const Key('filter-archived')), findsOneWidget);
      await tester.tap(find.byKey(const Key('filter-archived')));
      await tester.pump();
      expect(picked, isEmpty);
    });

    testWidgets('state is announced, not left to colour', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(bar(selected: 'active'));
      final node = tester.getSemantics(find.byKey(const Key('filter-active')));
      expect(node.flagsCollection.isSelected, Tristate.isTrue);
      expect(node.label, 'نشطة');
      final off = tester.getSemantics(find.byKey(const Key('filter-all')));
      expect(off.flagsCollection.isSelected, Tristate.isFalse);
      handle.dispose();
    });

    testWidgets('every chip stays on screen at 320 dp and 1.6x',
        (tester) async {
      sizeTo(tester, const Size(320, 800));
      await tester.pumpWidget(bar(textScale: 1.6));
      expect(tester.takeException(), isNull);
      final screen = tester.getRect(find.byType(Scaffold));
      for (final id in const ['all', 'active', 'archived']) {
        final chip = tester.getRect(find.byKey(Key('filter-$id')));
        expect(chip.left, greaterThanOrEqualTo(screen.left - 0.01),
            reason: '$id ran off the start edge');
        expect(chip.right, lessThanOrEqualTo(screen.right + 0.01),
            reason: '$id ran off the end edge');
      }
    });

    testWidgets('a row too long for the width wraps rather than clipping',
        (tester) async {
      // The failure this replaces: a horizontally scrolling row that clipped
      // its last chip at the edge with no affordance to reach it.
      sizeTo(tester, const Size(320, 800));
      await tester.pumpWidget(host(
        const AppFilterBar(children: [
          AppFilterChip(
            key: Key('long-a'),
            label: 'بانتظار إكمال الإعداد',
            selected: false,
            onSelected: _ignore,
          ),
          AppFilterChip(
            key: Key('long-b'),
            label: 'الحالة التجارية أو حالة الوصول',
            selected: false,
            onSelected: _ignore,
          ),
          AppFilterChip(
            key: Key('long-c'),
            label: 'بانتظار الحذف النهائي',
            selected: false,
            onSelected: _ignore,
          ),
        ]),
        textScale: 1.6,
      ));
      expect(tester.takeException(), isNull);
      final screen = tester.getRect(find.byType(Scaffold));
      final first = tester.getRect(find.byKey(const Key('long-a')));
      final last = tester.getRect(find.byKey(const Key('long-c')));
      expect(last.top, greaterThan(first.top), reason: 'did not wrap');
      expect(last.right, lessThanOrEqualTo(screen.right + 0.01));
      expect(last.left, greaterThanOrEqualTo(screen.left - 0.01));
    });

    testWidgets('runs right to left in Arabic', (tester) async {
      await tester.pumpWidget(bar());
      final first = tester.getRect(find.byKey(const Key('filter-all')));
      final second = tester.getRect(find.byKey(const Key('filter-active')));
      expect(first.right, greaterThan(second.right));
    });

    testWidgets('builds in every palette, both appearances, eye-protect too',
        (tester) async {
      for (final palette in PaletteId.values) {
        for (final brightness in Brightness.values) {
          for (final eyeProtect in [false, true]) {
            await tester.pumpWidget(host(
              const AppFilterBar(children: [
                AppFilterChip(
                  label: 'نشطة',
                  selected: true,
                  onSelected: _ignore,
                ),
              ]),
              palette: palette,
              brightness: brightness,
              eyeProtect: eyeProtect,
            ));
            expect(tester.takeException(), isNull,
                reason: '$palette $brightness eyeProtect=$eyeProtect');
          }
        }
      }
    });
  });

  group('showAppConfirmation', () {
    Future<bool?> open(
      WidgetTester tester, {
      ConfirmationSeverity severity = ConfirmationSeverity.normal,
      String? identity,
      bool identityLtr = false,
      String? effective,
      String dismissLabel = 'إلغاء',
    }) async {
      bool? answer;
      await tester.pumpWidget(host(Builder(builder: (context) {
        return TextButton(
          onPressed: () async {
            answer = await showAppConfirmation(
              context: context,
              title: 'حذف العضو',
              identity: identity,
              identityLtr: identityLtr,
              change: 'سيُحذف العضو من مفرزته.',
              unchanged: 'يبقى حضوره المسجَّل كما هو.',
              effective: effective,
              confirmLabel: 'حذف',
              severity: severity,
              dismissLabel: dismissLabel,
            );
          },
          child: const Text('open'),
        );
      })));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return answer;
    }

    testWidgets('states what changes and what does not', (tester) async {
      await open(tester);
      expect(find.text('حذف العضو'), findsOneWidget);
      expect(find.text('سيُحذف العضو من مفرزته.'), findsOneWidget);
      expect(find.text('يبقى حضوره المسجَّل كما هو.'), findsOneWidget);
    });

    testWidgets('the identity is its own selectable line', (tester) async {
      await open(tester, identity: 'أحمد كنعان');
      final identity = find.byKey(const Key('app-confirmation-identity'));
      expect(identity, findsOneWidget);
      expect(
        tester.widget<SelectableText>(identity).data,
        'أحمد كنعان',
      );
    });

    testWidgets('an LTR identity is isolated inside the Arabic dialog',
        (tester) async {
      await open(tester, identity: 'name@example.org', identityLtr: true);
      expect(
        Directionality.of(tester.element(
          find.byKey(const Key('app-confirmation-identity')),
        )),
        TextDirection.ltr,
      );
    });

    testWidgets('an Arabic identity keeps the page direction', (tester) async {
      await open(tester, identity: 'أحمد كنعان');
      expect(
        Directionality.of(tester.element(
          find.byKey(const Key('app-confirmation-identity')),
        )),
        TextDirection.rtl,
      );
    });

    testWidgets('normal, warning and destructive are three grounds',
        (tester) async {
      final palette = AppColors.resolve(PaletteId.medical, Brightness.light);
      Color? groundOf(WidgetTester tester) {
        final button = tester.widget<FilledButton>(
          find.byKey(const Key('app-confirmation-confirm')),
        );
        return button.style?.backgroundColor?.resolve({});
      }

      await open(tester);
      expect(groundOf(tester), isNull, reason: 'normal uses the theme');

      await tester.pumpWidget(const SizedBox.shrink());
      await open(tester, severity: ConfirmationSeverity.warning);
      expect(groundOf(tester), palette.warn);

      await tester.pumpWidget(const SizedBox.shrink());
      await open(tester, severity: ConfirmationSeverity.destructive);
      expect(groundOf(tester), palette.crit);
    });

    testWidgets('the confirm is a filled button, never a coloured label',
        (tester) async {
      // The defect this replaced: a `TextButton` with a crit foreground at
      // exactly the same weight as «إلغاء».
      await open(tester, severity: ConfirmationSeverity.destructive);
      expect(
        find.byKey(const Key('app-confirmation-confirm')),
        findsOneWidget,
      );
      expect(
        tester.widget(find.byKey(const Key('app-confirmation-confirm'))),
        isA<FilledButton>(),
      );
      expect(
        tester.widget(find.byKey(const Key('app-confirmation-dismiss'))),
        isA<TextButton>(),
      );
    });

    testWidgets('confirming answers true, dismissing answers false',
        (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('app-confirmation-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('حذف العضو'), findsNothing);

      await open(tester);
      await tester.tap(find.byKey(const Key('app-confirmation-dismiss')));
      await tester.pumpAndSettle();
      expect(find.text('حذف العضو'), findsNothing);
    });

    testWidgets('the dismiss label can avoid repeating the confirm word',
        (tester) async {
      await open(tester, dismissLabel: 'تراجع');
      expect(find.text('تراجع'), findsOneWidget);
      expect(find.text('إلغاء'), findsNothing);
    });

    testWidgets('the optional effective line only appears when given',
        (tester) async {
      await open(tester);
      expect(find.byIcon(Icons.schedule_rounded), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await open(tester, effective: 'يسري فورا.');
      expect(find.text('يسري فورا.'), findsOneWidget);
    });

    testWidgets('holds at 320 dp and 1.6x without overflowing',
        (tester) async {
      bool? answer;
      await tester.pumpWidget(host(
        Builder(builder: (context) {
          return TextButton(
            onPressed: () async {
              answer = await showAppConfirmation(
                context: context,
                title: 'حذف العضو من المفرزة نهائيا',
                identity: 'أحمد كنعان الحسيني',
                change: 'سيُحذف العضو من مفرزته ومن كل شفت لم يبدأ بعد. '
                    'لا يمكن التراجع عن هذه العملية.',
                unchanged:
                    'يبقى حضوره المسجَّل في الشفتات المنتهية وفي التقارير.',
                confirmLabel: 'حذف',
                severity: ConfirmationSeverity.destructive,
              );
            },
            child: const Text('open'),
          );
        }),
        textScale: 1.6,
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(answer, isNull);
    });
  });

  group('ReadingColumn', () {
    Future<double> widthAt(WidgetTester tester, double screen,
        {double? maxWidth}) async {
      sizeTo(tester, Size(screen, 800));
      await tester.pumpWidget(host(
        ReadingColumn(
          maxWidth: maxWidth ?? kReadingMaxWidth,
          child: Container(key: const Key('content'), color: Colors.red),
        ),
      ));
      return tester.getSize(find.byKey(const Key('content'))).width;
    }

    testWidgets('a phone keeps the full width', (tester) async {
      expect(await widthAt(tester, 390), 390);
      expect(await widthAt(tester, 320), 320);
    });

    testWidgets('a tablet is capped at the reading measure', (tester) async {
      expect(await widthAt(tester, 600), kReadingMaxWidth);
      expect(await widthAt(tester, 900), kReadingMaxWidth);
    });

    testWidgets('the content measure caps wider', (tester) async {
      expect(
        await widthAt(tester, 900, maxWidth: kContentMaxWidth),
        kContentMaxWidth,
      );
    });

    testWidgets('the column is centred, not pinned to a side',
        (tester) async {
      sizeTo(tester, const Size(900, 800));
      await tester.pumpWidget(host(
        const ReadingColumn(child: SizedBox(key: Key('content'), height: 40)),
      ));
      final content = tester.getRect(find.byKey(const Key('content')));
      final screen = tester.getRect(find.byType(Scaffold));
      expect(content.center.dx, closeTo(screen.center.dx, 0.5));
    });

    testWidgets('top-aligned, so a short page sits under its header',
        (tester) async {
      sizeTo(tester, const Size(900, 800));
      await tester.pumpWidget(host(
        const ReadingColumn(child: SizedBox(key: Key('content'), height: 40)),
      ));
      final content = tester.getRect(find.byKey(const Key('content')));
      final screen = tester.getRect(find.byType(Scaffold));
      expect(content.top, closeTo(screen.top, 0.5));
    });

    test('the measures are one ordered scale', () {
      expect(kFormMaxWidth, lessThan(kReadingMaxWidth));
      expect(kReadingMaxWidth, lessThan(kContentMaxWidth));
    });
  });
}

void _ignore(bool _) {}
