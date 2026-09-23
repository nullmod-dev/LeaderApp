import 'package:flutter/material.dart';

import '../app_info.dart';

/// The Leader mark — `06 · Clean Layer` — wherever the app draws it.
///
/// **There is exactly one mark, and it is not a preference.** The product
/// shipped a period where three variants of the lockup could be picked in
/// Settings; that selector is gone. A brand mark is the one thing in an
/// application that must be the same object every time it appears — on the
/// home screen, on the launch intro, on the forced-upgrade screen and in
/// About — and offering three of them made the product's own identity a
/// setting. The home-screen icon was always fixed (Android can only swap a
/// launcher icon by toggling activity-aliases, which drops the user's placed
/// shortcut); now the in-app mark matches it.
///
/// **One asset path, spelled once.** [AppInfo.logoAsset] is the single place
/// `assets/brand/...` appears in `lib/`, and this widget is the single place
/// it is turned into pixels — so the decode settings the mark needs are not
/// re-decided at four call sites.
///
/// **Decoration, never a label.** The mark carries no semantics: every screen
/// that draws it also *says* what it is, and announcing the picture as well
/// would read the product name twice.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, required this.size, this.glow});

  /// The height the artwork is drawn at. The lockup is very slightly wider
  /// than it is tall, and `BoxFit.contain` inside a square of this side keeps
  /// its proportions at every scale.
  final double size;

  /// An optional coloured bloom beneath the mark. The artwork is already a
  /// rounded glass tile, so it sits bare with only light under it — no plate,
  /// no ring, no tile inside a tile.
  final Color? glow;

  /// The handle tests and the render harnesses reach the mark by.
  static const Key widgetKey = Key('brand-mark');

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      AppInfo.logoAsset,
      key: widgetKey,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      gaplessPlayback: true,
      excludeFromSemantics: true,
    );
    final bloom = glow;
    if (bloom == null) return image;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.24),
        boxShadow: [
          BoxShadow(
            color: bloom,
            blurRadius: size * 0.46,
            spreadRadius: -size * 0.12,
            offset: Offset(0, size * 0.14),
          ),
        ],
      ),
      child: image,
    );
  }
}
