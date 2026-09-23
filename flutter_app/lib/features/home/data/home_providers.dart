import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../demo/data/demo_workspace.dart';
import '../../../core/result/result.dart';
import '../../detachment/data/detachment_providers.dart';
import '../../detachment/domain/detachment_models.dart';
import '../../inventory/data/inventory_providers.dart';
import '../../shift/data/shift_providers.dart';
import '../../team/data/team_providers.dart';
import '../domain/home_models.dart';
import '../domain/home_repository.dart';
import 'mock_home_repository.dart';
import '../../tenant_feature/data/tenant_feature_providers.dart';
import '../../tenant_feature/domain/tenant_feature_models.dart';

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  final inventoryEnabled = ref.watch(
    tenantFeatureAvailableProvider(TenantFeatureKey.inventory),
  );
  // Composed from the same repositories the rest of the app reads, so the
  // dashboard can never show a figure that exists nowhere else.
  final demo = ref.watch(demoWorkspaceProvider);
  if (demo != null) return demo.home;
  return MockHomeRepository(
    detachments: ref.watch(detachmentRepositoryProvider),
    shifts: ref.watch(shiftRepositoryProvider),
    inventory: inventoryEnabled ? ref.watch(inventoryRepositoryProvider) : null,
    team: ref.watch(teamRepositoryProvider),
  );
});

/// The detachments the dashboard may open on: the active ones, in name order.
///
/// `autoDispose` and keyed like every other detachment-scoped read
/// (`DETACHMENT-SCOPING.md` §2 rule 2).
final dashboardDetachmentsProvider =
    FutureProvider.autoDispose<Result<List<Detachment>>>((ref) async {
  final result = await ref.watch(
    detachmentListProvider(
      const DetachmentListQuery(filter: DetachmentStatus.active),
    ).future,
  );
  return result.when(
    success: (data, {stale = false}) => Success(_byName(data), stale: stale),
    failure: (message, code) => Failure(message, code: code),
    offline: (cached) =>
        Offline(cached: cached == null ? null : _byName(cached)),
  );
});

List<Detachment> _byName(List<Detachment> input) =>
    List<Detachment>.of(input)..sort((a, b) => a.name.compareTo(b.name));

/// The detachment the user explicitly switched the dashboard to, or null while
/// they have not chosen one.
///
/// Session-scoped on purpose. `DETACHMENT-SCOPING.md` §4.3 asks for this to be
/// persisted locally as a UI preference; there is no durable local store in
/// this build yet (the theme preference has the same gap — see `HANDOFF.md`),
/// so the choice deterministically re-seeds on relaunch through
/// [resolveActiveDetachment] instead of being remembered incorrectly.
class ActiveDetachmentController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String detachmentId) => state = detachmentId;
}

final activeDetachmentSelectionProvider =
    NotifierProvider<ActiveDetachmentController, String?>(
  ActiveDetachmentController.new,
);

/// Which detachment the dashboard opens on, given what the session can see.
///
/// Deterministic, per `DETACHMENT-SCOPING.md` §4.4 — never a "best guess" that
/// reorders itself between launches:
///
/// 1. the explicit choice, if it is still in the list;
/// 2. the only detachment, when there is exactly one;
/// 3. otherwise the first by name.
///
/// Null only when the session can see none, which is a designed dashboard
/// state rather than an error.
Detachment? resolveActiveDetachment(
  List<Detachment> available,
  String? selectedId,
) {
  if (available.isEmpty) return null;
  if (selectedId != null) {
    for (final detachment in available) {
      if (detachment.id == selectedId) return detachment;
    }
  }
  return available.first;
}

/// The resolved active detachment, or null when there is none to show.
final activeDetachmentProvider =
    Provider.autoDispose<AsyncValue<Result<Detachment?>>>((ref) {
  final selection = ref.watch(activeDetachmentSelectionProvider);
  return ref.watch(dashboardDetachmentsProvider).whenData(
        (result) => result.when(
          success: (data, {stale = false}) =>
              Success(resolveActiveDetachment(data, selection), stale: stale),
          failure: (message, code) => Failure(message, code: code),
          offline: (cached) => cached == null
              ? const Offline()
              : Offline(cached: resolveActiveDetachment(cached, selection)),
        ),
      );
});

/// Today's operational snapshot for one detachment.
final homeSummaryProvider = FutureProvider.autoDispose
    .family<Result<HomeSummary>, String>((ref, detachmentId) async {
  return ref.read(homeRepositoryProvider).summary(detachmentId);
});
