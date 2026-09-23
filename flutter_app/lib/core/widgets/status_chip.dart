import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';

enum StatusKind { ok, warn, crit, info, muted }

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.kind,
    required this.label,
    this.icon,
  });
  final StatusKind kind;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (bg, fg) = switch (kind) {
      StatusKind.ok => (c.okTint, c.ok),
      StatusKind.warn => (c.warnTint, c.warn),
      StatusKind.crit => (c.critTint, c.crit),
      StatusKind.info => (c.infoTint, c.info),
      StatusKind.muted => (c.mutedTint, c.ink2),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: fg),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            ExcludeSemantics(child: Icon(icon, color: fg, size: 15)),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              // The chip's own type token, not whatever `DefaultTextStyle` it
              // lands in. A `StatusChip` is placed in `ListTile` slots and
              // inside `Wrap`s all over the app, and inheriting a family is
              // how a chip full of Arabic-Indic digits ends up on a font that
              // has none.
              style: AppTypography.chip(c).copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
