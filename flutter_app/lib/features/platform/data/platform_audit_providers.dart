import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../domain/platform_audit_models.dart';
import '../domain/platform_audit_repository.dart';
import 'mock_platform_audit_repository.dart';
import 'platform_audit_fixtures.dart';

final platformAuditFixturesProvider = Provider<PlatformAuditFixtures>((ref) {
  return PlatformAuditFixtures(clock: ref.watch(clockProvider));
});

final platformAuditRepositoryProvider =
    Provider<PlatformAuditRepository>((ref) {
  return MockPlatformAuditRepository(
    fixtures: ref.watch(platformAuditFixturesProvider),
  );
});

final platformAuditEventsProvider =
    FutureProvider.family<Result<PlatformAuditPage>, PlatformAuditQuery>(
        (ref, query) {
  return ref.watch(platformAuditRepositoryProvider).listAuditEvents(query);
});
