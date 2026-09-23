import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/core/storage/secure_store.dart';
import 'package:mtm/features/auth/data/secure_auth_state_store.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/onboarding_models.dart';
import 'package:mtm/features/auth/domain/session_access.dart';

void main() {
  final challenge = VerificationChallenge(
    handle: 'opaque-challenge-handle',
    maskedEmail: 'a***@example.org',
    expiresAt: DateTime.utc(2026, 9, 13, 12),
    resendAvailableAt: DateTime.utc(2026, 9, 13, 11, 1),
    attemptsRemaining: 4,
  );
  final snapshot = OnboardingSnapshot(
    accountId: 'account_1',
    email: 'admin@example.org',
    methods: const {AuthMethod.password},
    account: AccountStatus.pendingSetup,
    link: TenantLinkStatus.linked,
    tenant: const LinkedTenant(
      displayName: 'فريق الاختبار',
      role: AuthRole.admin,
      status: SaasTenantStatus.active,
    ),
    setup: AccountSetupStatus.required,
  );

  test('verification handle round-trips only in secure storage', () async {
    final device = InMemorySecureStore();
    final store = SecureAuthStateStore(device);
    await store.writeVerification(challenge);

    final restored = await store.readOnboarding();
    expect(restored, isA<StoredVerificationState>());
    expect((restored as StoredVerificationState).challenge, challenge);
    expect(device.values, contains(SecureAuthStateStore.onboardingKey));
  });

  test('restricted snapshot is cache only and token toString is redacted',
      () async {
    final store = SecureAuthStateStore(InMemorySecureStore());
    await store.writeRestricted(
      token: 'restricted-secret-token',
      cachedSnapshot: snapshot,
    );
    final restored = await store.readOnboarding();
    expect(restored, isA<StoredRestrictedSession>());
    expect((restored as StoredRestrictedSession).cachedSnapshot, snapshot);
    expect(restored.toString(), isNot(contains('restricted-secret-token')));
  });

  test('full and restricted credentials are mutually exclusive', () async {
    final device = InMemorySecureStore();
    final store = SecureAuthStateStore(device);
    await store.writeRestricted(token: 'restricted', cachedSnapshot: snapshot);
    await store.writeFullSessionToken('full');
    expect(await store.readOnboarding(), isNull);
    expect(await store.readFullSessionToken(), 'full');

    await store.writeVerification(challenge);
    expect(await store.readFullSessionToken(), isNull);
    expect(await store.readOnboarding(), isA<StoredVerificationState>());
  });

  test('corrupted and unknown-version records are removed, never trusted',
      () async {
    for (final raw in ['not-json', '{"version":99,"kind":"restricted"}']) {
      final device = InMemorySecureStore({
        SecureAuthStateStore.onboardingKey: raw,
      });
      final store = SecureAuthStateStore(device);
      expect(await store.readOnboarding(), isNull);
      expect(
          device.values, isNot(contains(SecureAuthStateStore.onboardingKey)));
    }
  });

  test('password, OTP, Team Code and Google token are never serialized',
      () async {
    final device = InMemorySecureStore();
    final store = SecureAuthStateStore(device);
    await store.writeRestricted(
      token: 'allowed-restricted-session-token',
      cachedSnapshot: snapshot,
    );
    final dump = device.values.values.join('|');
    for (final forbidden in [
      'super-secret-password',
      '246810',
      'MTM-5JQX-2TWD',
      'google-provider-token',
      'invitation-secret',
      'reset-secret',
      'mfa-secret',
    ]) {
      expect(dump, isNot(contains(forbidden)));
    }
  });

  test('platform adapter uses flutter_secure_storage, not preferences',
      () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final first = PlatformSecureStore();
    await first.writeString('secure-key', 'secure-value');
    expect(
        await PlatformSecureStore().readString('secure-key'), 'secure-value');
    await first.remove('secure-key');
    expect(await PlatformSecureStore().readString('secure-key'), isNull);
  });
}
