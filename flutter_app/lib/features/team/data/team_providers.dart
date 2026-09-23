import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../demo/data/demo_workspace.dart';
import '../../../core/result/result.dart';
import '../domain/team_models.dart';
import '../domain/team_repository.dart';
import 'mock_team_repository.dart';

final teamRepositoryProvider = Provider<TeamRepository>((ref) {
  return ref.watch(demoWorkspaceProvider)?.team ?? MockTeamRepository();
});

final teamListProvider =
    FutureProvider.family<Result<List<TeamMember>>, String>((ref, detId) async {
  return ref.read(teamRepositoryProvider).listForDetachment(detId);
});

/// One member, for the edit form. Family key is the member id.
final memberByIdProvider =
    FutureProvider.family<Result<TeamMember>, String>((ref, memberId) async {
  return ref.read(teamRepositoryProvider).byId(memberId);
});
