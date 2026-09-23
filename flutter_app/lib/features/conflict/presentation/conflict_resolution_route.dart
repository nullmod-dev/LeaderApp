import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/skeleton.dart';
import '../data/conflict_outbox_resolver.dart';
import '../data/conflict_review_controller.dart';
import '../domain/conflict_models.dart';
import 'conflict_resolution_page.dart';

/// What `/conflicts/:conflictId` actually builds.
///
/// The conflict screen itself takes a typed [ConflictPresentation] and a
/// handler and knows nothing about routing or Riverpod — that is why it can
/// be opened from a feature flow with records the review store never saw.
/// This is the seam that feeds it when the route is entered without those
/// arguments: a restored deep link, or a return to a location the navigator
/// still holds after the `extra` payload is gone.
///
/// It resolves the conflict the same way the Needs Review list does — from
/// the join of the outbox and the stored review metadata — so a conflict
/// that has since been resolved, or one with no safe metadata to compare,
/// lands on [ConflictUnavailablePage] instead of a fabricated comparison.
/// There is no second source of conflicts anywhere in the app.
class ConflictResolutionRoute extends ConsumerWidget {
  const ConflictResolutionRoute({
    super.key,
    required this.conflictId,
    this.args,
  });

  final String? conflictId;

  /// The typed arguments the caller passed, when it passed any.
  final ConflictResolutionRouteArgs? args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passed = args;
    if (passed != null && passed.conflict.conflictId == conflictId) {
      return ConflictResolutionPage(
        conflict: passed.conflict,
        onDecision: passed.onDecision,
      );
    }

    final id = conflictId;
    if (id == null || id.isEmpty) return const ConflictUnavailablePage();

    final items = ref.watch(needsReviewItemsProvider);
    return items.when(
      loading: () => const Scaffold(body: SkeletonList(count: 3)),
      error: (_, __) => const ConflictUnavailablePage(),
      data: (rows) {
        final match = rows
            .where((item) => item.conflictId == id && item.isReviewable)
            .firstOrNull;
        final entry = match?.entry;
        if (entry == null) return const ConflictUnavailablePage();
        return ConflictResolutionPage(
          conflict: entry.toPresentation(),
          onDecision: ref.read(conflictDecisionHandlerProvider),
        );
      },
    );
  }
}
