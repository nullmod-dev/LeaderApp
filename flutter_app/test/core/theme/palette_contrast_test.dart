import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/theme/app_palette.dart';

/// Legibility guard for every palette, plain and under eye-protect.
///
/// The palettes are hand-authored hex, so nothing but a test can tell you
/// that a new one puts white text on a colour it cannot carry. That is
/// exactly what happened when `medical` and `teal` were first written: their
/// dark-mode filled-button label sat at 2.67:1 and 2.80:1.
///
/// Two standards are enforced, and they are deliberately different:
///
///  * **[_houseFloor]** applies to all six. It is set just under the worst
///    ratio the original `slate` / `copper` / `clay` tokens actually achieve —
///    those mirror `tokens.css` and are not ours to re-tune, so the floor
///    documents the shipped design system rather than WCAG.
///  * **[_authoredPalettes]** — the three added later — must additionally
///    clear WCAG AA on the filled-button label, the one piece of text that is
///    always read on a saturated ground.
void main() {
  group('palette contrast', () {
    test('every palette clears the house floor, plain and eye-protected', () {
      for (final id in PaletteId.values) {
        for (final brightness in Brightness.values) {
          final plain = AppColors.resolve(id, brightness);
          for (final (colors, wash) in [
            (plain, 'plain'),
            (plain.warmed(), 'eye-protect'),
          ]) {
            for (final pair in _pairs) {
              final got = _ratio(pair.fg(colors), pair.bg(colors));
              expect(
                got,
                greaterThanOrEqualTo(pair.floor),
                reason: '${id.name} ${brightness.name} [$wash]: '
                    '${pair.name} is ${got.toStringAsFixed(2)}:1, '
                    'below the ${pair.floor} house floor',
              );
            }
          }
        }
      }
    });

    test('the later palettes carry an AA filled-button label', () {
      for (final id in _authoredPalettes) {
        for (final brightness in Brightness.values) {
          final c = AppColors.resolve(id, brightness);
          expect(
            _ratio(c.primaryInk, c.primary),
            greaterThanOrEqualTo(4.5),
            reason: '${id.name} ${brightness.name}: a filled button label must '
                'clear WCAG AA against its own primary',
          );
        }
      }
    });

    // The floors above are the real guarantee. This is the sanity bound that
    // stops someone "making eye-protect stronger" until the whole app is a
    // wash of amber: the floors alone would allow a pull of 0.9, which keeps
    // every ratio legal and still looks broken.
    test('eye-protect costs no pair more than 10% of its contrast', () {
      for (final id in PaletteId.values) {
        for (final brightness in Brightness.values) {
          final plain = AppColors.resolve(id, brightness);
          final warm = plain.warmed();
          for (final pair in _pairs) {
            final before = _ratio(pair.fg(plain), pair.bg(plain));
            final after = _ratio(pair.fg(warm), pair.bg(warm));
            expect(
              (before - after) / before,
              lessThanOrEqualTo(0.10),
              reason: '${id.name} ${brightness.name}: ${pair.name} falls from '
                  '${before.toStringAsFixed(2)} to ${after.toStringAsFixed(2)} '
                  'under eye-protect',
            );
          }
        }
      }
    });

    // The other half of that bound: a wash nobody can see is not a feature.
    // `surface` is the token the eye actually lands on, so it has to move far
    // enough to be perceptible rather than read as a rendering artefact.
    //
    // The promise is **blue removal**, not an absolute warm hue. Some dark
    // palettes (`slate`, `copper`) sit on a deliberately blue-black surface,
    // and pulling those all the way past neutral into amber would mean
    // lightening the wash until `clay` broke its own contrast floors. So a
    // blue-black lands neutral and a neutral one lands warm — in both cases
    // measurably less blue than it started, which is what the feature claims.
    test('eye-protect takes blue out of the surface, visibly', () {
      for (final id in PaletteId.values) {
        for (final brightness in Brightness.values) {
          final plain = AppColors.resolve(id, brightness);
          final warm = plain.warmed();

          expect(
            warm.surface.b,
            lessThan(plain.surface.b),
            reason: '${id.name} ${brightness.name}: surface kept its blue',
          );

          // Red-minus-blue is the direction-independent measure of "warmer":
          // it rises whether the wash lightens a light surface or darkens a
          // dark one.
          //
          // Travel by palette, for anyone retuning the pull: light modes move
          // +0.078 to +0.094 (white becomes a warm ivory), dark modes +0.024
          // to +0.059. `clayDark` sets the floor at +0.024 precisely because
          // its surface is already warm and has the least distance to cover.
          final plainSpread = plain.surface.r - plain.surface.b;
          final warmSpread = warm.surface.r - warm.surface.b;
          expect(
            warmSpread - plainSpread,
            greaterThan(0.02),
            reason: '${id.name} ${brightness.name}: surface barely warmed '
                '(red-minus-blue moved from '
                '${plainSpread.toStringAsFixed(3)} to '
                '${warmSpread.toStringAsFixed(3)})',
          );
        }
      }
    });

    test('eye-protect moves the ground and nothing else', () {
      for (final id in PaletteId.values) {
        for (final brightness in Brightness.values) {
          final plain = AppColors.resolve(id, brightness);
          final warm = plain.warmed();
          final where = '${id.name} ${brightness.name}';

          // Foregrounds are the whole point: they must come back untouched,
          // or the filter is eating the contrast it is supposed to preserve.
          expect(warm.ink, plain.ink, reason: '$where ink');
          expect(warm.ink2, plain.ink2, reason: '$where ink2');
          expect(warm.ink3, plain.ink3, reason: '$where ink3');
          expect(warm.primary, plain.primary, reason: '$where primary');
          expect(warm.primaryInk, plain.primaryInk,
              reason: '$where primaryInk');
          expect(warm.primaryPressed, plain.primaryPressed,
              reason: '$where primaryPressed');
          expect(warm.focus, plain.focus, reason: '$where focus');
          // A warning has to still read as a warning through the wash.
          expect(warm.ok, plain.ok, reason: '$where ok');
          expect(warm.warn, plain.warn, reason: '$where warn');
          expect(warm.crit, plain.crit, reason: '$where crit');
          expect(warm.info, plain.info, reason: '$where info');
          expect(warm.muted, plain.muted, reason: '$where muted');

          // ...and the ground must actually have moved, or the toggle is a
          // no-op the user can see nothing from.
          expect(warm.bg, isNot(plain.bg), reason: '$where bg did not warm');
          expect(warm.surface, isNot(plain.surface),
              reason: '$where surface did not warm');
        }
      }
    });

    test('warming is memoised per palette instance', () {
      final c = AppColors.resolve(PaletteId.medical, Brightness.light);
      expect(identical(c.warmed(), c.warmed()), isTrue);
    });
  });
}

/// The palettes added after the original `tokens.css` set — the ones this
/// repository authored itself and can therefore hold to a higher bar.
const _authoredPalettes = [PaletteId.medical, PaletteId.indigo, PaletteId.teal];

typedef _Pick = Color Function(AppColors c);

class _Pair {
  const _Pair(this.name, this.fg, this.bg, this.floor);

  final String name;
  final _Pick fg;
  final _Pick bg;

  /// Minimum acceptable ratio. Set just under what `slate`/`copper`/`clay`
  /// already achieve, so this catches a regression without demanding the
  /// shipped tokens be redesigned.
  final double floor;
}

const _pairs = <_Pair>[
  _Pair('body text on card', _ink, _surface, 12.0),
  _Pair('body text on page', _ink, _bg, 12.0),
  _Pair('secondary text on card', _ink2, _surface, 7.0),
  _Pair('hint text on card', _ink3, _surface, 3.4),
  _Pair('hint text on page', _ink3, _bg, 3.2),
  _Pair('filled button label', _primaryInk, _primary, 3.6),
  _Pair('primary chip text', _primary, _primaryTint, 3.5),
  _Pair('ok chip text', _ok, _okTint, 3.4),
  _Pair('warn chip text', _warn, _warnTint, 2.2),
  _Pair('crit chip text', _crit, _critTint, 3.3),
  _Pair('info chip text', _info, _infoTint, 4.1),
  _Pair('muted chip text', _ink2, _mutedTint, 5.9),
  _Pair('primary accent on card', _primary, _surface, 3.9),
];

Color _ink(AppColors c) => c.ink;
Color _ink2(AppColors c) => c.ink2;
Color _ink3(AppColors c) => c.ink3;
Color _bg(AppColors c) => c.bg;
Color _surface(AppColors c) => c.surface;
Color _primary(AppColors c) => c.primary;
Color _primaryInk(AppColors c) => c.primaryInk;
Color _primaryTint(AppColors c) => c.primaryTint;
Color _ok(AppColors c) => c.ok;
Color _okTint(AppColors c) => c.okTint;
Color _warn(AppColors c) => c.warn;
Color _warnTint(AppColors c) => c.warnTint;
Color _crit(AppColors c) => c.crit;
Color _critTint(AppColors c) => c.critTint;
Color _info(AppColors c) => c.info;
Color _infoTint(AppColors c) => c.infoTint;
Color _mutedTint(AppColors c) => c.mutedTint;

/// WCAG 2.1 contrast ratio. `computeLuminance` is already the WCAG relative
/// luminance, so this is the published formula verbatim.
double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
