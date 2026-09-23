import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// Wraps a scrollable with a themed pull-to-refresh.
class AppRefreshIndicator extends StatelessWidget {
  const AppRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
  });
  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: c.primary,
      backgroundColor: c.surface,
      strokeWidth: 2.4,
      displacement: 32,
      child: child,
    );
  }
}
