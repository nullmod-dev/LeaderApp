import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/features/auth/presentation/entry_glass.dart';

/// The entry surface's colours, held to WCAG AA by arithmetic rather than by
/// eye — the same treatment `test/core/theme/palette_contrast_test.dart`
/// gives the six product palettes.
///
/// It matters more here than anywhere else in the app: this is the one screen
/// every person sees, it is the one surface that does **not** come from
/// `AppColors`, and the redesign deliberately deepened the light ground and
/// brightened the accent to make the screen less washed out. Both of those
/// moves spend contrast, so both are bounded here.
///
/// Every ink is checked against the ground it is actually drawn on — the
/// gradient's darkest and lightest stop for anything on the ground, and the
/// composited panel for anything inside it.
double _relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// What the eye sees where a translucent fill sits over a ground.
Color _over(Color fill, Color ground) => Color.alphaBlend(fill, ground);

void main() {
  const appearances = <(String, Brightness, bool)>[
    ('light', Brightness.light, false),
    ('dark', Brightness.dark, false),
    ('light + eye protection', Brightness.light, true),
    ('dark + eye protection', Brightness.dark, true),
  ];

  for (final (name, brightness, eyeProtect) in appearances) {
    group(name, () {
      final g = EntryGlass.resolve(brightness, eyeProtect: eyeProtect);
      final grounds = <String, Color>{
        'baseTop': g.baseTop,
        'baseMid': g.baseMid,
        'baseBottom': g.baseBottom,
      };
      final panel = _over(g.glassTop, g.baseMid);
      final panelFoot = _over(g.glassBottom, g.baseMid);
      final well = _over(g.fieldFill, panel);
      final wellFocused = _over(g.fieldFocusFill, panel);

      test('text on the ground clears AA everywhere on the gradient', () {
        // The heading, the supporting line, the sign-up link and the footer
        // all sit on the ground rather than on the panel.
        final onGround = <String, Color>{
          'fg (heading)': g.fg,
          'muted (supporting copy, «ليس لديك حساب؟»)': g.muted,
          'faint (the footer line)': g.faint,
          'accentInk («إنشاء حساب»)': g.accentInk,
        };
        for (final ink in onGround.entries) {
          for (final ground in grounds.entries) {
            expect(
              _contrast(ink.value, ground.value),
              greaterThanOrEqualTo(4.5),
              reason: '${ink.key} on ${ground.key}',
            );
          }
        }
      });

      test('text inside the panel clears AA on what it is drawn on', () {
        // Each ink against the surfaces it actually lands on, not against
        // every surface in the panel: «أو» is never inside a field well, and
        // a check that pretended otherwise would be tuning a colour to a
        // pairing the screen cannot produce.
        final panelSurfaces = {'panel top': panel, 'panel bottom': panelFoot};
        final wellSurfaces = {
          'a field well': well,
          'a focused field well': wellFocused,
        };
        final placements = <String, (Color, Map<String, Color>)>{
          'fg (a field label)': (g.fg, panelSurfaces),
          'fg (what is typed)': (g.fg, wellSurfaces),
          'muted (the forgot link)': (g.muted, panelSurfaces),
          // A notice's text sits on the resting field fill. It is never on a
          // focused well — the only muted thing there is the password eye,
          // which is a control and is checked at 3:1 below.
          'muted (a notice)': (g.muted, {'a field well': well}),
          'faint («أو»)': (g.faint, panelSurfaces),
          'danger (a refusal)': (
            g.danger,
            {'the danger wash': _over(g.dangerWash, panel)},
          ),
        };
        for (final placement in placements.entries) {
          final (ink, surfaces) = placement.value;
          for (final surface in surfaces.entries) {
            expect(
              _contrast(ink, surface.value),
              greaterThanOrEqualTo(4.5),
              reason: '${placement.key} on ${surface.key}',
            );
          }
        }
      });

      test('the primary action reads at AA, enabled and disabled', () {
        expect(_contrast(g.onAccent, g.accent), greaterThanOrEqualTo(4.5),
            reason: '«تسجيل الدخول» on the filled button');
        // The empty form is the first thing everyone sees, so the disabled
        // CTA is the most-viewed state on the most-viewed screen. It is held
        // to the same floor as the live one.
        expect(_contrast(g.onCtaDisabled, g.ctaDisabled),
            greaterThanOrEqualTo(4.5),
            reason: 'the disabled label');
        // And it must not be mistakable for the live button.
        expect(_contrast(g.ctaDisabled, g.accent), greaterThanOrEqualTo(1.8),
            reason: 'disabled is a different fill, not a faded one');
      });

      test('the accent is a usable UI colour against what it borders', () {
        // 1.4.11: a non-text control boundary needs 3:1. The accent is the
        // focused field's border and the brand rule above the heading.
        for (final surface in <String, Color>{
          'a focused field well': wellFocused,
          'the panel': panel,
          'baseTop': g.baseTop,
          'baseMid': g.baseMid,
        }.entries) {
          expect(
            _contrast(g.accent, surface.value),
            greaterThanOrEqualTo(3),
            reason: 'the accent against ${surface.key}',
          );
        }
        // The muted glyphs — the leading mail/lock icon and the password eye
        // — are controls on a well, resting or focused.
        for (final surface in <String, Color>{
          'a field well': well,
          'a focused field well': wellFocused,
        }.entries) {
          expect(
            _contrast(g.muted, surface.value),
            greaterThanOrEqualTo(3),
            reason: 'a field glyph on ${surface.key}',
          );
        }
      });

      test('the pulse adds light rather than staining the ground', () {
        // A wave darker than the ground it crosses reads as a smudge. In both
        // appearances the pulse is the lighter of the two.
        expect(
          _relativeLuminance(g.pulse),
          greaterThan(_relativeLuminance(g.baseMid)),
        );
        // And it stays ambient. The bound is not on the alpha — the light
        // ground needs roughly twice the dark ground's for the same
        // perceived lift — but on how far the brightest frame ever gets from
        // the ground it crosses. Past about 2:1 a wave stops reading as
        // light and starts reading as an object with an edge.
        final brightest = _over(
          g.pulse.withValues(alpha: g.pulsePeak),
          g.baseMid,
        );
        expect(_contrast(brightest, g.baseMid), lessThan(2.2));
      });

      test('the focused well is brighter than the resting one', () {
        expect(
          _relativeLuminance(wellFocused),
          greaterThan(_relativeLuminance(well)),
          reason: 'focus is carried by the surface, not by the border alone',
        );
      });
    });
  }

  group('eye protection moves the ground and nothing else', () {
    for (final brightness in Brightness.values) {
      test('in ${brightness.name}', () {
        final plain = EntryGlass.resolve(brightness);
        final warm = EntryGlass.resolve(brightness, eyeProtect: true);

        // Every foreground is untouched — warming ink is what costs contrast
        // where text is read.
        expect(warm.fg, plain.fg);
        expect(warm.muted, plain.muted);
        expect(warm.faint, plain.faint);
        expect(warm.accent, plain.accent);
        expect(warm.accentInk, plain.accentInk);
        expect(warm.onAccent, plain.onAccent);
        expect(warm.danger, plain.danger);

        // The ground did move.
        expect(warm.baseMid, isNot(plain.baseMid));
        expect(warm.horizon, isNot(plain.horizon));
      });
    }

    test('and costs at most a third of the heading contrast', () {
      for (final brightness in Brightness.values) {
        final plain = EntryGlass.resolve(brightness);
        final warm = EntryGlass.resolve(brightness, eyeProtect: true);
        final before = _contrast(plain.fg, plain.baseMid);
        final after = _contrast(warm.fg, warm.baseMid);
        expect(after, greaterThan(before * 0.67), reason: brightness.name);
      }
    });
  });

  group('the pulse painter', () {
    final glass = EntryGlass.resolve(Brightness.dark);

    test('repaints for a new frame and for nothing else', () {
      const a = EntryPulsePainter(
          glass: kGlassFixture, center: Alignment.center, phase: 0.1);
      const b = EntryPulsePainter(
          glass: kGlassFixture, center: Alignment.center, phase: 0.2);
      expect(b.shouldRepaint(a), isTrue);
      expect(a.shouldRepaint(a), isFalse);
    });

    test('paints without throwing at every phase, including degenerate sizes',
        () {
      for (final size in const [
        Size.zero,
        Size(1, 1),
        Size(390, 844),
        Size(320, 2000),
      ]) {
        for (var i = 0; i <= 20; i++) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          EntryPulsePainter(
            glass: glass,
            center: const Alignment(0, -0.2),
            phase: i / 20,
          ).paint(canvas, size);
          recorder.endRecording().dispose();
        }
      }
    });
  });

  testWidgets('the pulse runs a controller only when ambience is allowed',
      (tester) async {
    Future<void> pump(
      MotionLevel level, {
      bool disableAnimations = false,
      bool paused = false,
    }) =>
        tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: MotionScope(
              level: level,
              child: EntryPulse(
                glass: EntryGlass.resolve(Brightness.dark),
                paused: paused,
              ),
            ),
          ),
        ));

    await pump(MotionLevel.balanced);
    expect(tester.hasRunningAnimations, isTrue);

    await pump(MotionLevel.low);
    expect(tester.hasRunningAnimations, isFalse);

    await pump(MotionLevel.high, disableAnimations: true);
    expect(tester.hasRunningAnimations, isFalse,
        reason: 'the accessibility flag outranks the quality level');

    await pump(MotionLevel.high);
    expect(tester.hasRunningAnimations, isTrue,
        reason: 'and the reduced form is a response, not the only thing it '
            'can do');

    await pump(MotionLevel.high, paused: true);
    expect(tester.hasRunningAnimations, isFalse,
        reason: 'field interaction holds the visible frame without repainting');

    await pump(MotionLevel.high);
    expect(tester.hasRunningAnimations, isTrue,
        reason: 'the breathing loop resumes when editing ends');
  });
}

/// A const [EntryGlass] for the painter-equality test, which needs two
/// painters that differ only in their phase.
const EntryGlass kGlassFixture = EntryGlass(
  baseTop: Color(0xFF08272B),
  baseMid: Color(0xFF03181A),
  baseBottom: Color(0xFF010D0F),
  horizon: Color(0x593E9C8C),
  wash1: Color(0x6B3FA48E),
  wash2: Color(0x7A1D6675),
  pulse: Color(0xFF6FE3C4),
  pulsePeak: 0.19,
  fg: Color(0xFFEFF9F7),
  muted: Color(0xFFAFC6C3),
  faint: Color(0xFF8DA5A3),
  accent: Color(0xFF5FDCBB),
  accentInk: Color(0xFF6FE3C4),
  onAccent: Color(0xFF00201E),
  ctaDisabled: Color(0xFF26544C),
  onCtaDisabled: Color(0xFF9CC6BB),
  danger: Color(0xFFFF8A80),
  dangerWash: Color(0x1FE04A44),
  glassTop: Color(0x1FFFFFFF),
  glassMid: Color(0x0DFFFFFF),
  glassBottom: Color(0x14FFFFFF),
  glassBorder: Color(0x2EFFFFFF),
  sheen: Color(0x70FFFFFF),
  fieldFill: Color(0x14FFFFFF),
  fieldFocusFill: Color(0x26FFFFFF),
  fieldBorder: Color(0x29FFFFFF),
  hairline: Color(0x24FFFFFF),
  panelShadow: Color(0xE0000709),
  ctaShadow: Color(0x665FDCBB),
  markGlow: Color(0x7A46AF95),
);
