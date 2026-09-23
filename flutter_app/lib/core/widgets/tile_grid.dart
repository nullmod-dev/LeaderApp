import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Equal columns of equal-height tiles, with the column count decided by the
/// room the grid actually has.
///
/// **Why not a `Wrap`.** Three surfaces reached for `Wrap` and all three got
/// the same result: rows of different lengths, a last row one tile wide, and
/// tiles of different widths sitting beside each other because each sized
/// itself to its own label. The 2026-09-19 audit called Home's version "four
/// ragged quick-action chips"; the statistics tab's attendance totals had the
/// same shape. A grid is the same information with a stable one.
///
/// **Why not a breakpoint.** The column count comes from [minTileWidth]
/// against the width this block is given *and* the text scale, not from the
/// window. At 1.6× a four-up row of metric tiles drew «أدوية منخفضة» as
/// «أدوية…» on a 320 dp phone — the figure survived and its meaning did not —
/// and that happens at a width the window never knows about, because the
/// grid sits inside a capped reading column.
///
/// Trailing slots in a short last row stay empty rather than letting one tile
/// stretch across the width, which would read as a primary action.
class TileGrid extends StatelessWidget {
  const TileGrid({
    super.key,
    required this.tiles,
    required this.minTileWidth,
    this.columnChoices = const [1, 2, 3, 4],
    this.spacing = AppSpacing.sm,
  });

  final List<Widget> tiles;

  /// The narrowest a tile may be drawn before its label stops being readable,
  /// in logical pixels at a text scale of 1. Scaled by the text scaler.
  final double minTileWidth;

  /// The column counts this grid is allowed to take, ascending. It is a list
  /// rather than a maximum because the counts that read well are a property
  /// of *how many tiles there are*: four comparable figures belong in two
  /// columns or four, never three, which would leave a row of three and a row
  /// of one and invite the eye to compare the wrong pairs. The largest choice
  /// that fits wins; the smallest is the floor.
  final List<int> columnChoices;

  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final scaled =
          MediaQuery.textScalerOf(context).scale(minTileWidth);
      final fits = ((constraints.maxWidth + spacing) / (scaled + spacing))
          .floor();
      var columns = columnChoices.first;
      for (final choice in columnChoices) {
        if (choice <= fits) columns = choice;
      }
      final rows = <Widget>[];
      for (var i = 0; i < tiles.length; i += columns) {
        final slice = tiles.sublist(i, (i + columns).clamp(0, tiles.length));
        rows.add(IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < columns; j++) ...[
                if (j > 0) SizedBox(width: spacing),
                Expanded(
                  child: j < slice.length ? slice[j] : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ));
        if (i + columns < tiles.length) rows.add(SizedBox(height: spacing));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
    });
  }
}
