import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../problem/problem.dart';
import '../problem/problem_presentation.dart';
import '../result/result.dart';
import '../../l10n/strings.dart';
import 'empty_state.dart';
import 'error_state.dart';
import 'skeleton.dart';

/// Renders the four states every screen in this app has to handle: the
/// provider still loading, and then the three cases of [Result] — success
/// (possibly stale), failure, and offline (possibly with a cached copy).
///
/// The pattern was already written out by hand on every built screen; this
/// only names it, so a new screen cannot quietly forget one of the four.
class AsyncResultView<T> extends StatelessWidget {
  const AsyncResultView({
    super.key,
    required this.value,
    required this.onRetry,
    required this.builder,
    this.loading,
  });

  final AsyncValue<Result<T>> value;
  final VoidCallback onRetry;

  /// `stale` is true when the data is a cached copy shown after a refresh
  /// failed — the screen should mark it rather than pass it off as fresh.
  final Widget Function(BuildContext context, T data, bool stale) builder;

  /// Defaults to the shared list skeleton.
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => loading ?? const SkeletonList(),
      error: (_, __) => ErrorStateView(onRetry: onRetry),
      data: (result) => result.when(
        success: (data, {stale = false}) => builder(context, data, stale),
        // A section failure is resolved through the shared problem pipeline:
        // known codes get MTM's own localized copy, an unrecognised code
        // gets the safe generic fallback — never a raw wire string dressed
        // up as product copy. See FRONTEND-BACKEND-INTEGRATION.md §2.
        failure: (message, code) => _failure(message, code),
        offline: (cached) => cached == null
            ? EmptyState(
                icon: Icons.cloud_off_rounded,
                title: S.offlineTitle,
                body: S.noCachedCopy,
                actionLabel: S.retry,
                onAction: onRetry,
              )
            : builder(context, cached, true),
      ),
    );
  }

  Widget _failure(String message, String? code) {
    final problem = Problem.of(
      ProblemCode.parse(code),
      rawCode: code,
      detail: message,
    );
    if (!problem.isKnown && kDebugMode) {
      // Keep the dropped information for a developer without ever showing
      // it: the user sees the generic fallback, the console keeps the code
      // and the server text.
      debugPrint('AsyncResultView: unhandled problem '
          '${problem.rawCode ?? '(no code)'} — "${problem.detail ?? ''}"');
    }
    final view = resolveProblem(problem);
    return ErrorStateView(
      title: view.title,
      body: view.message,
      onRetry: onRetry,
    );
  }
}
