import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/core/network/api_client.dart';
import 'package:mtm/core/network/token_vault.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/storage/secure_store.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/secure_auth_state_store.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/platform/data/http_platform_break_glass_repository.dart';
import 'package:mtm/features/platform/data/http_saas_tenant_repository.dart';
import 'package:mtm/features/platform/data/platform_break_glass_providers.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/platform/domain/platform_break_glass_models.dart';

/// Two Super Admin reads that used to consult the local fixture catalogue in
/// a backend build: the break-glass target team's status, and a finally
/// deleted team's tombstone.
http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

const _superAdmin = AuthUser(
  id: 'sa_1',
  name: 'Super Admin',
  email: 'sa@leader.test',
  role: AuthRole.superAdmin,
  saasTenantId: null,
  capabilities: Capabilities.none,
  orgName: 'Leader',
);

void main() {
  final now = DateTime.utc(2026, 10, 9, 9);
  late http.Response Function(http.Request) server;

  ApiClient api() => ApiClient(
        vault: TokenVault(SecureAuthStateStore(InMemorySecureStore())),
        origin: 'http://leader.test',
        client: MockClient((request) async => server(request)),
      );

  Map<String, dynamic> grant(String status) => {
        'id': 'bg_1',
        'revision': 1,
        // A real team: unknown to the local fixture catalogue.
        'tenant': {'tenantId': 'saas_01REAL', 'displayName': 'alwalla'},
        'scopes': ['tenant_operational_read'],
        'reason': 'تحقيق في بلاغ',
        'initiator': {'accountId': 'sa_1', 'displayName': 'Super Admin'},
        'issuedAt': now.subtract(const Duration(minutes: 5)).toIso8601String(),
        'expiresAt': now.add(const Duration(minutes: 25)).toIso8601String(),
        'status': status,
        'endedAt': status == 'ended' ? now.toIso8601String() : null,
        'endReason': status == 'ended' ? 'tenant_unavailable' : null,
      };

  group('break-glass', () {
    test('an active grant from the server vouches for its team', () async {
      server = (_) => _json(200, {
            'grant': grant('active'),
            'readAt': now.toIso8601String(),
          });
      final snapshot =
          (await HttpPlatformBreakGlassRepository(api()).loadCurrent()
                  as Success)
              .data;
      expect(snapshot.targetTenantStatus, SaasTenantStatus.active);
    });

    test('an ended grant vouches for nothing', () async {
      server = (_) => _json(200, {
            'grant': grant('ended'),
            'readAt': now.toIso8601String(),
          });
      final snapshot =
          (await HttpPlatformBreakGlassRepository(api()).loadCurrent()
                  as Success)
              .data;
      expect(snapshot.targetTenantStatus, isNull);
    });

    test("a live grant on a real team is usable, not 'team unavailable'",
        () async {
      server = (_) => _json(200, {
            'grant': grant('active'),
            'readAt': now.toIso8601String(),
          });
      final c = ProviderContainer(overrides: [
        currentUserProvider.overrideWith((ref) async => _superAdmin),
        clockProvider.overrideWithValue(() => now),
        platformBreakGlassRepositoryProvider
            .overrideWith((ref) => HttpPlatformBreakGlassRepository(api())),
      ]);
      addTearDown(c.dispose);
      await c.read(currentUserProvider.future);
      await c.read(breakGlassCurrentProvider.future);

      expect(c.read(breakGlassAccessProvider).state,
          BreakGlassAccessState.usable);
    });
  });

  group('a finally deleted team', () {
    test('keeps its tombstone instead of reading as not found', () async {
      server = (_) => _json(200, {
            'tenantId': 'saas_gone',
            'displayNameSnapshot': 'فريق قديم',
            'status': 'deleted',
            'deletedAt': '2026-10-01T10:00:00.000Z',
            'lifecycleVersion': 7,
            'historyReference': 'hist_1',
          });
      final c = ProviderContainer(overrides: [
        saasTenantRepositoryProvider
            .overrideWith((ref) => HttpSaasTenantRepository(api())),
      ]);
      addTearDown(c.dispose);
      final sub = c.listen(deletedTenantTombstoneProvider('saas_gone'), (_, __) {});
      addTearDown(sub.close);
      expect(sub.read(), isNull, reason: 'nothing known before the read');

      final read = await c.read(saasTenantDetailProvider('saas_gone').future);
      expect((read as Failure).code, 'not_found');

      final tombstone = c.read(deletedTenantTombstoneProvider('saas_gone'));
      expect(tombstone?.displayNameSnapshot, 'فريق قديم');
      expect(tombstone?.lifecycleVersion, 7);
      expect(tombstone?.deletedAt, DateTime.utc(2026, 10, 1, 10));
    });

    test('an ordinary not found stays not found', () async {
      server = (_) => _json(404, {
            'error': {'code': 'not_found'}
          });
      final c = ProviderContainer(overrides: [
        saasTenantRepositoryProvider
            .overrideWith((ref) => HttpSaasTenantRepository(api())),
      ]);
      addTearDown(c.dispose);
      await c.read(saasTenantDetailProvider('saas_x').future);
      expect(c.read(deletedTenantTombstoneProvider('saas_x')), isNull);
    });
  });
}
