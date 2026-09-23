import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_typography.dart';
import 'motion_tokens.dart';

/// Numeric value that eases from its previous value to the new one.
/// Rendered through [TabularDigits] so the number's width depends on how
/// many digits it has, never on which digits they are — otherwise the
/// count visibly nudges its neighbours on every frame of the tween.
class AnimatedCounter extends StatelessWidget {
  const AnimatedCounter({
    super.key,
    required this.value,
    this.style,
    this.duration = MotionTokens.long,
  });

  final int value;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // The cheap levels turn value tweens off outright: a counter re-lays
    // its text out on every frame it runs, and a dashboard can hold half a
    // dozen of them. Skipping the builder means the final figure — the one
    // the user opened the screen to read — is on screen immediately.
    if (!motionSpec(context).animatedValues) {
      return TabularDigits(
        _toArabicIndic(value),
        style: style ?? AppTypography.number(c, size: 26),
      );
    }
    return TweenAnimationBuilder<double>(
      // Under reduced motion, tween duration is zero so the widget renders
      // the target value on the first frame — no counter animation.
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: effectiveDuration(context, duration),
      curve: effectiveCurve(context, MotionTokens.standard),
      builder: (context, v, _) => TabularDigits(
        _toArabicIndic(v.round()),
        style: style ?? AppTypography.number(c, size: 26),
      ),
    );
  }
}

/// Lays every digit out in an equal-width cell — the layout-level
/// equivalent of tabular figures.
///
/// The bundled IBM Plex Sans Arabic ships no `tnum` feature and draws
/// Arabic-Indic digits proportionally, so `FontFeature.tabularFigures()`
/// cannot hold a column still on its own. Use this for any figure that
/// changes while it is on screen: animated counters, countdowns, live
/// quantities.
///
/// Digits and separators only. Never pass Arabic letters through here —
/// laying a word out one character at a time breaks the joining forms.
class TabularDigits extends StatelessWidget {
  const TabularDigits(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  /// Both numeral sets, so a column stays aligned even where the two mix.
  static const String _digits = '\u0660\u0661\u0662\u0663\u0664\u0665'
      '\u0666\u0667\u0668\u0669'
      '0123456789';

  /// Measuring ten glyphs on every frame of a counter tween would be
  /// wasteful, and the set of numeric styles in the app is tiny — key the
  /// result on the style plus its scaled size.
  static final Map<(TextStyle, double), double> _cellWidths = {};

  static double _cellWidth(TextStyle style, TextScaler scaler) {
    final key = (style, scaler.scale(style.fontSize ?? 14));
    return _cellWidths.putIfAbsent(key, () {
      var widest = 0.0;
      for (final d in _digits.split('')) {
        final painter = TextPainter(
          text: TextSpan(text: d, style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();
        widest = math.max(widest, painter.width);
      }
      return widest;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cell = _cellWidth(style, MediaQuery.textScalerOf(context));
    // Numerals run left-to-right even inside the app's RTL layout.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final ch in text.split(''))
            SizedBox(
              width: _digits.contains(ch) ? cell : null,
              child: Text(ch, style: style, textAlign: TextAlign.center),
            ),
        ],
      ),
    );
  }
}

/// Convert Western digits to Arabic-Indic — matches the existing dashboards.
String _toArabicIndic(int n) {
  const map = {
    '0': '٠',
    '1': '١',
    '2': '٢',
    '3': '٣',
    '4': '٤',
    '5': '٥',
    '6': '٦',
    '7': '٧',
    '8': '٨',
    '9': '٩',
  };
  final buf = StringBuffer();
  for (final ch in n.toString().split('')) {
    buf.write(map[ch] ?? ch);
  }
  return buf.toString();
}

String toArabicIndic(String s) {
  const map = {
    '0': '٠',
    '1': '١',
    '2': '٢',
    '3': '٣',
    '4': '٤',
    '5': '٥',
    '6': '٦',
    '7': '٧',
    '8': '٨',
    '9': '٩',
  };
  final buf = StringBuffer();
  for (final ch in s.split('')) {
    buf.write(map[ch] ?? ch);
  }
  return buf.toString();
}

/// The inverse: fold Arabic-Indic digits back to Western.
///
/// The UI reads and writes Arabic-Indic, but a number that will be stored,
/// compared, or sent to a backend has to be canonical first — otherwise
/// "١٠١" and "101" are two different member numbers.
String toWesternDigits(String s) {
  const map = {
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
  };
  final buf = StringBuffer();
  for (final ch in s.split('')) {
    buf.write(map[ch] ?? ch);
  }
  return buf.toString();
}
