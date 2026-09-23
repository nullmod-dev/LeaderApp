import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../demo/data/demo_workspace.dart';
import '../../../core/result/result.dart';
import '../../detachment/data/detachment_providers.dart';
import '../domain/detachment_group_models.dart';
import '../domain/detachment_group_repository.dart';
import 'mock_detachment_group_repository.dart';

final detachmentGroupRepositoryProvider =
    Provider<DetachmentGroupRepository>((ref) {
  // Counts on a detachment group card are read from the detachment repository,
  // never stored twice — see `MockDetachmentGroupRepository`.
  return ref.watch(demoWorkspaceProvider)?.detachmentGroups ??
      MockDetachmentGroupRepository(ref.watch(detachmentRepositoryProvider));
});

/// The detachment group list, optionally filtered by a search string.
final detachmentGroupListProvider = FutureProvider.autoDispose
    .family<Result<List<DetachmentGroup>>, String>((ref, query) async {
  return ref.read(detachmentGroupRepositoryProvider).list(query: query);
});

final detachmentGroupByIdProvider = FutureProvider.autoDispose
    .family<Result<DetachmentGroup>, String>((ref, id) async {
  return ref.read(detachmentGroupRepositoryProvider).byId(id);
});
