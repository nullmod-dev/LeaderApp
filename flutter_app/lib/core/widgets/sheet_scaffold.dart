import 'package:flutter/material.dart';

import '../motion/motion_tokens.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';

/// Modal bottom sheet content wrapper: drag handle + title + body.
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    required this.title,
    required this.child,
    this.action,
    this.expanded = false,
  });
  final String title;
  final Widget child;
  final Widget? action;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final media = MediaQuery.of(context);
    final availableHeight =
        media.size.height - media.viewInsets.bottom - media.padding.top;
    final sheet = Container(
      constraints: BoxConstraints(
        maxHeight: availableHeight.clamp(240.0, media.size.height) * .96,
      ),
      height: expanded
          ? availableHeight.clamp(240.0, media.size.height) * .96
          : null,
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppRadii.xxl),
          topRight: Radius.circular(AppRadii.xxl),
        ),
      ),
      child: Column(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: c.line2,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: 6),
            child: Row(children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (action != null) action!,
            ]),
          ),
          Divider(color: c.line, height: 1),
          if (expanded) Expanded(child: child) else Flexible(child: child),
        ],
      ),
    );
    return AnimatedPadding(
      duration: effectiveDuration(context, MotionTokens.short),
      curve: effectiveCurve(context, MotionTokens.enter),
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        maintainBottomViewPadding: true,
        child: sheet,
      ),
    );
  }
}

/// Show a modal bottom sheet using [SheetScaffold]. Spring curve.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required String title,
  required Widget child,
  Widget? action,
  bool expanded = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (context) => SheetScaffold(
      title: title,
      action: action,
      expanded: expanded,
      child: child,
    ),
  );
}
