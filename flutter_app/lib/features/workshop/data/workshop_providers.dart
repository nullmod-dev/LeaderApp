import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../demo/data/demo_workspace.dart';
import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../../team/data/team_providers.dart';
import '../domain/workshop_models.dart';
import '../domain/workshop_repository.dart';
import 'mock_workshop_repository.dart';

/// Resolves people through the same roster the Team screens read, so a
/// workshop can only reference members that exist in this workspace.
final workshopRepositoryProvider = Provider<WorkshopRepository>((ref) {
  return ref.watch(demoWorkspaceProvider)?.workshops ??
      MockWorkshopRepository(
        team: ref.watch(teamRepositoryProvider),
        clock: ref.watch(clockProvider),
      );
});

final workshopListProvider =
    FutureProvider<Result<List<Workshop>>>((ref) async {
  return ref.read(workshopRepositoryProvider).list();
});

final workshopByIdProvider =
    FutureProvider.family<Result<Workshop>, String>((ref, id) async {
  return ref.read(workshopRepositoryProvider).byId(id);
});

final workshopParticipantsProvider =
    FutureProvider.family<Result<List<WorkshopParticipant>>, String>(
        (ref, wsId) async {
  return ref.read(workshopRepositoryProvider).participants(wsId);
});

/// Re-reads everything that shows one workshop after a mutation: the list
/// card, the detail header and Team tab, the register, and — through them —
/// the statistics.
void refreshWorkshop(WidgetRef ref, String workshopId) {
  ref.invalidate(workshopListProvider);
  ref.invalidate(workshopByIdProvider(workshopId));
  ref.invalidate(workshopParticipantsProvider(workshopId));
}

/// Whether one workshop may be changed right now.
enum WorkshopMode {
  /// Not read yet, or unreadable. Denies writes rather than guessing.
  unknown,
  active,

  /// Archived — readable and exportable, closed to every change.
  archived,
}

/// Derived from the record itself, the way `detachmentModeProvider` is: a
/// cached copy read offline still answers, and only a workshop that could not
/// be read at all resolves to [WorkshopMode.unknown].
final workshopModeProvider =
    Provider.family<WorkshopMode, String>((ref, workshopId) {
  final workshop = ref.watch(workshopByIdProvider(workshopId)).whenOrNull(
        data: (r) => r.when(
          success: (Workshop w, {bool stale = false}) => w,
          failure: (_, __) => null,
          offline: (cached) => cached,
        ),
      );
  if (workshop == null) return WorkshopMode.unknown;
  return workshop.archived ? WorkshopMode.archived : WorkshopMode.active;
});

