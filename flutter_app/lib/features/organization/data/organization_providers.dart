import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/access/capability.dart';
import '../../../core/access/capability_guard.dart';
import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../../auth/data/auth_providers.dart';
import '../../platform/data/saas_tenant_providers.dart';
import '../domain/organization_models.dart';
import '../domain/organization_repository.dart';
import 'mock_organization_repository.dart';

class OrganizationMockConfig {
  const OrganizationMockConfig({
    this.mode = MockOrganizationMode.loaded,
    this.latency = const Duration(milliseconds: 260),
  });

  final MockOrganizationMode mode;
  final Duration latency;
}

final organizationMockConfigProvider = Provider<OrganizationMockConfig>(
  (ref) => const OrganizationMockConfig(),
);

/// One adapter per app, so its last-read cache survives leaving the screen.
final organizationRepositoryProvider = Provider<OrganizationRepository>((ref) {
  final config = ref.watch(organizationMockConfigProvider);
  return MockOrganizationRepository(
    store: ref.watch(platformTenantStoreProvider),
    clock: ref.watch(clockProvider),
    tenantId: () => ref.read(currentUserProvider).valueOrNull?.saasTenantId,
    // Organisation-wide figures are what `org.edit` already gates (the
    // organisation route before Point 15, the dashboard's organisation
    // section). Usage counts are exactly such figures.
    usageVisible: () => ref.read(capabilitiesProvider).can(Cap.orgEdit),
    mode: config.mode,
    latency: config.latency,
  );
});

/// The one read both Organization and Plan render. Plan is pushed on top of
/// Organization (or opened alone), so while either is on screen this is one
/// request, not two, and the two screens cannot show different snapshots.
///
/// No polling, no timer: it reads on open, on pull-to-refresh and on the
/// explicit refresh of a cached copy.
final organizationSnapshotProvider =
    FutureProvider.autoDispose<Result<OrganizationSnapshot>>((ref) async {
  // A changed grant changes what the read may include (usage figures).
  ref.watch(capabilitiesProvider);
  if (ref.watch(sessionAccessProvider).isDemo) return _contextUnavailable();
  final user = await ref.watch(currentUserProvider.future);
  if (user == null || !user.role.belongsToSaasTenant) {
    return _contextUnavailable();
  }
  return ref.read(organizationRepositoryProvider).readCurrent();
});

Failure<OrganizationSnapshot> _contextUnavailable() => Failure(
      'لا ترتبط هذه الجلسة بمؤسسة.',
      code: OrganizationProblemCode.contextUnavailable.wire,
    );
