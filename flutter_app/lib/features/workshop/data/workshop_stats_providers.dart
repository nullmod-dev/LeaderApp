import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../domain/workshop_stats.dart';
import 'workshop_providers.dart';

/// The workshop's statistics, built once from the workshop record and its
/// participant list.
///
/// Composing the two reads here rather than in the widget is what lets the
/// dashboard, the detail tables and both export formats quote the same
/// object — a screen cannot disagree with the file it just produced. It also
/// keeps the failure modes honest: if either read fails or is offline, the
/// statistics say so instead of rendering half a picture as if it were whole.
final workshopStatsProvider = FutureProvider.autoDispose
    .family<Result<WorkshopStats>, String>((ref, workshopId) async {
  final workshop = await ref.watch(workshopByIdProvider(workshopId).future);
  final participants =
      await ref.watch(workshopParticipantsProvider(workshopId).future);

  return workshop.when(
    success: (w, {stale = false}) => participants.when(
      success: (list, {stale = false}) =>
          Success(WorkshopStats.of(w, list), stale: stale),
      failure: (message, code) => Failure(message, code: code),
      // A cached participant list is still a real answer; a missing one is
      // not, because a workshop with no people would read as a workshop
      // nobody came to.
      offline: (cached) => cached == null
          ? const Offline()
          : Offline(cached: WorkshopStats.of(w, cached)),
    ),
    failure: (message, code) => Failure(message, code: code),
    offline: (cachedWorkshop) => cachedWorkshop == null
        ? const Offline()
        : participants.when(
            success: (list, {stale = false}) =>
                Offline(cached: WorkshopStats.of(cachedWorkshop, list)),
            failure: (_, __) => const Offline(),
            offline: (cached) => Offline(
              cached: cached == null
                  ? null
                  : WorkshopStats.of(cachedWorkshop, cached),
            ),
          ),
  );
});
