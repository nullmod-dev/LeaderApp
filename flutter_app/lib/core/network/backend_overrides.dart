import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/admin_management/data/http_simple_admin_repository.dart';
import '../../features/admin_management/data/simple_admin_providers.dart';
import '../../features/announcement/data/announcement_providers.dart';
import '../../features/announcement/data/http_announcement_repository.dart';
import '../../features/app_version/data/app_version_providers.dart';
import '../../features/app_version/data/http_app_version_repository.dart';
import '../../features/auth/data/auth_providers.dart';
import '../../features/auth/data/device_authenticator.dart';
import '../../features/auth/data/device_id_store.dart';
import '../../features/auth/data/device_trust_repository.dart';
import '../../features/auth/data/full_session_snapshot_store.dart';
import '../../features/auth/data/http_auth_repository.dart';
import '../../features/auth/data/http_onboarding_repository.dart';
import '../../features/auth/data/onboarding_controller.dart';
import '../../features/demo/data/demo_workspace.dart';
import '../../features/detachment/data/detachment_providers.dart';
import '../../features/detachment/data/http_detachment_repository.dart';
import '../../features/detachment_group/data/detachment_group_providers.dart';
import '../../features/detachment_group/data/http_detachment_group_repository.dart';
import '../../features/home/data/home_providers.dart';
import '../../features/home/data/http_home_repository.dart';
import '../../features/inventory/data/http_inventory_repository.dart';
import '../../features/inventory/data/inventory_providers.dart';
import '../../features/notification/data/http_notification_repository.dart';
import '../../features/notification/data/http_notification_state_store.dart';
import '../../features/notification/data/notification_providers.dart';
import '../../features/notification/domain/notification_history_store.dart';
import '../../features/notification/domain/notification_read_store.dart';
import '../../features/organization/data/http_organization_repository.dart';
import '../../features/organization/data/organization_providers.dart';
import '../../features/platform/data/http_platform_break_glass_repository.dart';
import '../../features/pricing/data/commerce_backend.dart';
import '../../features/platform/data/http_platform_insights_repositories.dart';
import '../../features/platform/data/http_platform_main_admin_repository.dart';
import '../../features/platform/data/http_platform_reports_repository.dart';
import '../../features/platform/data/http_saas_tenant_repository.dart';
import '../../features/platform/data/http_tenant_feature_repository.dart';
import '../../features/platform/data/http_tenant_lifecycle_repository.dart';
import '../../features/platform/data/http_tenant_subscription_repository.dart';
import '../../features/platform/data/platform_audit_providers.dart';
import '../../features/platform/data/platform_break_glass_providers.dart';
import '../../features/platform/data/platform_main_admin_providers.dart';
import '../../features/platform/data/platform_operations_providers.dart';
import '../../features/platform/data/platform_overview_providers.dart';
import '../../features/platform/data/platform_reports_providers.dart';
import '../../features/platform/data/saas_subscription_providers.dart';
import '../../features/platform/data/saas_tenant_providers.dart';
import '../../features/platform/data/tenant_lifecycle_providers.dart';
import '../../features/settings/data/http_settings_repository.dart';
import '../../features/settings/data/settings_providers.dart';
import '../../features/settings/domain/settings_repository.dart';
import '../../features/shift/data/http_shift_repository.dart';
import '../../features/shift/data/shift_providers.dart';
import '../../features/team/data/http_team_repository.dart';
import '../../features/team/data/team_providers.dart';
import '../../features/tenant_feature/data/tenant_feature_providers.dart';
import '../../features/workshop/data/http_workshop_repository.dart';
import '../../features/workshop/data/workshop_providers.dart';
import '../sync/http_sync_transport.dart';
import '../sync/outbox_controller.dart';
import '../sync/outbox_store.dart';
import '../sync/secure_sync_stores.dart';
import '../sync/sync_coordinator.dart';
import '../sync/sync_payload_store.dart';
import '../time/clock.dart';
import 'api_providers.dart';

/// Every repository seam pointed at the Leader API — the composition root's
/// half of the integration. `main()` installs this list only when the build
/// was given `--dart-define=LEADER_API_BASE_URL=…`; otherwise the app runs on
/// its mocks exactly as before.
///
/// Super Admin seams get only `/platform/**` repositories and tenant seams
/// only tenant-plane ones; the server's guards enforce the same split.
///
/// The Customer Demo stays local: each tenant seam still answers from the
/// in-memory `DemoWorkspace` while a demo session is active, exactly as the
/// mock wiring does.
///
/// [deviceSettings] is the local-store settings repository `main()` already
/// hydrated: appearance, motion and frame rate never leave the device.
List<Override> backendOverrides({required SettingsRepository deviceSettings}) =>
    [
      // ---- identity ---------------------------------------------------------
      authRepositoryProvider.overrideWith(
        (ref) => HttpAuthRepository(
          ref.watch(apiClientProvider),
          snapshots: FullSessionSnapshotStore(ref.watch(secureStoreProvider)),
          clock: ref.watch(clockProvider),
        ),
      ),
      onboardingRepositoryProvider.overrideWith(
        (ref) => HttpOnboardingRepository(
          ref.watch(apiClientProvider),
          ref.watch(authStateStoreProvider),
          deviceId: ref.watch(deviceIdStoreProvider).read,
        ),
      ),
      deviceTrustRepositoryProvider.overrideWith(
        (ref) => HttpDeviceTrustRepository(ref.watch(apiClientProvider)),
      ),
      appVersionRepositoryProvider.overrideWith(
        (ref) => HttpAppVersionRepository(ref.watch(apiClientProvider)),
      ),
      // The app lock: a signed-in account opens with the phone's screen lock.
      deviceAuthenticatorProvider.overrideWithValue(LocalDeviceAuthenticator()),

      // ---- tenant plane -----------------------------------------------------
      detachmentGroupRepositoryProvider.overrideWith(
        (ref) =>
            ref.watch(demoWorkspaceProvider)?.detachmentGroups ??
            HttpDetachmentGroupRepository(ref.watch(apiClientProvider)),
      ),
      detachmentRepositoryProvider.overrideWith(
        (ref) =>
            ref.watch(demoWorkspaceProvider)?.detachments ??
            HttpDetachmentRepository(ref.watch(apiClientProvider)),
      ),
      teamRepositoryProvider.overrideWith(
        (ref) =>
            ref.watch(demoWorkspaceProvider)?.team ??
            HttpTeamRepository(ref.watch(apiClientProvider)),
      ),
      shiftRepositoryProvider.overrideWith(
        (ref) =>
            ref.watch(demoWorkspaceProvider)?.shifts ??
            HttpShiftRepository(ref.watch(apiClientProvider)),
      ),
      inventoryRepositoryProvider.overrideWith(
        (ref) =>
            ref.watch(demoWorkspaceProvider)?.inventory ??
            HttpInventoryRepository(
              ref.watch(apiClientProvider),
              ref.watch(syncPayloadStoreProvider),
            ),
      ),
      workshopRepositoryProvider.overrideWith(
        (ref) =>
            ref.watch(demoWorkspaceProvider)?.workshops ??
            HttpWorkshopRepository(ref.watch(apiClientProvider)),
      ),
      homeRepositoryProvider.overrideWith(
        (ref) =>
            ref.watch(demoWorkspaceProvider)?.home ??
            HttpHomeRepository(ref.watch(apiClientProvider)),
      ),
      notificationRepositoryProvider.overrideWith(
        (ref) =>
            ref.watch(demoWorkspaceProvider)?.notifications ??
            HttpNotificationRepository(ref.watch(apiClientProvider)),
      ),
      // Read state and cleared history live on the server, per account. A
      // demo trial has no server account: it keeps them in memory, as before.
      // Rebuilt when the account changes, so the next one never sees the
      // previous one's set.
      httpNotificationStateStoreProvider.overrideWith((ref) {
        ref.watch(currentUserProvider.select((u) => u.valueOrNull?.id));
        return ref.watch(demoWorkspaceProvider) != null
            ? null
            : HttpNotificationStateStore(ref.watch(apiClientProvider));
      }),
      notificationReadStoreProvider.overrideWith((ref) =>
          ref.watch(httpNotificationStateStoreProvider) ??
          InMemoryNotificationReadStore()),
      notificationHistoryStoreProvider.overrideWith((ref) =>
          ref.watch(httpNotificationStateStoreProvider) ??
          InMemoryNotificationHistoryStore()),
      announcementRepositoryProvider.overrideWith(
        (ref) =>
            ref.watch(demoWorkspaceProvider)?.announcements ??
            HttpAnnouncementRepository(ref.watch(apiClientProvider)),
      ),
      settingsRepositoryProvider.overrideWith(
        (ref) => HttpSettingsRepository(
          ref.watch(apiClientProvider),
          device: deviceSettings,
        ),
      ),
      organizationRepositoryProvider.overrideWith(
        (ref) => HttpOrganizationRepository(ref.watch(apiClientProvider)),
      ),
      simpleAdminRepositoryProvider.overrideWith(
        (ref) => HttpSimpleAdminRepository(
          ref.watch(apiClientProvider),
          tenantId: () =>
              ref.read(currentUserProvider).valueOrNull?.saasTenantId,
        ),
      ),
      // The outbox and its payloads survive an app restart, in the secure
      // store, one queue per signed-in account (see `secure_sync_stores.dart`).
      // A demo trial and the moment before the account is known keep the
      // process-memory stores they always had.
      outboxStoreProvider.overrideWith((ref) {
        final accountId = _durableSyncAccount(ref);
        return accountId == null
            ? InMemoryOutboxStore()
            : SecureOutboxStore(ref.watch(secureStoreProvider),
                accountId: accountId);
      }),
      syncPayloadStoreProvider.overrideWith((ref) {
        final accountId = _durableSyncAccount(ref);
        return accountId == null
            ? InMemorySyncPayloadStore()
            : SecureSyncPayloadStore(ref.watch(secureStoreProvider),
                accountId: accountId);
      }),
      syncTransportProvider.overrideWith(
        (ref) => HttpSyncTransport(
          ref.watch(apiClientProvider),
          ref.watch(syncPayloadStoreProvider),
        ),
      ),

      // Commerce (Point 19): offers and coupons on the server, coupon codes
      // judged there. A demo trial keeps the local development plane.
      commerceBackendProvider.overrideWith((ref) =>
          ref.watch(demoWorkspaceProvider) != null
              ? null
              : HttpCommerceBackend(ref.watch(apiClientProvider))),

      // ---- control plane (Super Admin, /platform/**) ------------------------
      saasTenantRepositoryProvider.overrideWith(
        (ref) => HttpSaasTenantRepository(ref.watch(apiClientProvider)),
      ),
      tenantLifecycleRepositoryProvider.overrideWith(
        (ref) => HttpTenantLifecycleRepository(ref.watch(apiClientProvider)),
      ),
      tenantSubscriptionRepositoryProvider.overrideWith(
        (ref) => HttpTenantSubscriptionRepository(ref.watch(apiClientProvider)),
      ),
      tenantFeatureRepositoryProvider.overrideWith(
        (ref) => HttpTenantFeatureRepository(ref.watch(apiClientProvider)),
      ),
      platformMainAdminRepositoryProvider.overrideWith(
        (ref) => HttpPlatformMainAdminRepository(ref.watch(apiClientProvider)),
      ),
      platformOverviewRepositoryProvider.overrideWith(
        (ref) => HttpPlatformOverviewRepository(ref.watch(apiClientProvider)),
      ),
      platformHealthRepositoryProvider.overrideWith(
        (ref) => HttpPlatformHealthRepository(ref.watch(apiClientProvider)),
      ),
      platformSecurityRepositoryProvider.overrideWith(
        (ref) => HttpPlatformSecurityRepository(ref.watch(apiClientProvider)),
      ),
      platformAuditRepositoryProvider.overrideWith(
        (ref) => HttpPlatformAuditRepository(ref.watch(apiClientProvider)),
      ),
      platformReportsRepositoryProvider.overrideWith(
        (ref) => HttpPlatformReportsRepository(ref.watch(apiClientProvider)),
      ),
      platformBreakGlassRepositoryProvider.overrideWith(
        (ref) => HttpPlatformBreakGlassRepository(ref.watch(apiClientProvider)),
      ),
    ];

/// The account whose durable sync queue is in use, or `null` for the
/// process-memory one: a demo trial (no server account), or no account read
/// yet.
String? _durableSyncAccount(Ref ref) {
  if (ref.watch(demoWorkspaceProvider) != null) return null;
  return ref.watch(currentUserProvider.select((u) => u.valueOrNull?.id));
}
