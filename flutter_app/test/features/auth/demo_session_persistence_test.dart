import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_guard.dart';
import 'package:mtm/core/storage/local_store.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/demo_personas.dart';
import 'package:mtm/features/auth/data/demo_sign_in_controller.dart';
import 'package:mtm/features/auth/data/persistent_demo_session_store.dart';
import 'package:mtm/features/auth/data/sign_out_controller.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/session_access.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Point 2 gap this point closes: **the selected development persona must
/// survive a real process restart.**
///
/// A relaunch is modelled the way `forced_upgrade_test.dart` established — a
/// second `ProviderContainer` built over the **same** durable store. That is
/// exactly what a new process does: new repository, new providers, same device
/// storage. The store under it is `InMemoryLocalStore` rather than the
/// `shared_preferences` one, because what has to be proved here is that the
/// *record* survives, not that a platform channel works.
void main() {
  /// A launch. Everything the app rebuilds on a cold start is rebuilt here;
  /// [store] is the device, and it is not.
  ProviderContainer launch(
    LocalStore store, {
    bool demoEnabled = true,
  }) {
    final container = ProviderContainer(overrides: [
      localStoreProvider.overrideWithValue(store),
      demoAccountsEnabledProvider.overrideWithValue(demoEnabled),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Future<AuthUser?> sessionOf(ProviderContainer container) =>
      container.read(currentUserProvider.future);

  group('a selection survives a relaunch', () {
    for (final persona in DemoPersona.values) {
      test('${persona.wire} is restored by the next launch', () async {
        final device = InMemoryLocalStore();

        final first = launch(device);
        final signedIn = await first
            .read(demoSignInControllerProvider.notifier)
            .signInAs(persona);
        expect(signedIn?.isSuccess, isTrue);
        expect((await sessionOf(first))?.id, persona.user.id);

        // Process termination. Nothing survives but the device.
        final second = launch(device);
        final restored = await sessionOf(second);

        expect(restored?.id, persona.user.id);
        expect(restored?.role, persona.user.role);
        expect(restored?.saasTenantId, persona.user.saasTenantId);
        expect(
          second.read(capabilitiesProvider),
          persona.user.capabilities,
          reason: 'the grant is rebuilt from the fixture, not deserialised',
        );
      });
    }

    test('only the persona id is written — no account, no grant', () async {
      final device = InMemoryLocalStore();
      final container = launch(device);
      await container
          .read(demoSignInControllerProvider.notifier)
          .signInAs(DemoPersona.simpleAdmin);

      expect(
        device.values[PersistentDemoSessionStore.personaKey],
        DemoPersona.simpleAdmin.wire,
      );
      // Nothing that could disagree with the fixture on the next launch.
      final dump = device.values.values.join('|');
      expect(dump, isNot(contains('@')), reason: 'no email was stored');
      expect(dump, isNot(contains(Cap.memberView)), reason: 'no grant stored');
      expect(dump, isNot(contains(kDemoSaasTenantId)));
    });

    test('each surface is restored, and none crosses into another', () async {
      final platform = InMemoryLocalStore();
      final tenant = InMemoryLocalStore();

      await launch(platform)
          .read(demoSignInControllerProvider.notifier)
          .signInAs(DemoPersona.superAdmin);
      await launch(tenant)
          .read(demoSignInControllerProvider.notifier)
          .signInAs(DemoPersona.mainAdmin);

      expect((await sessionOf(launch(platform)))?.role, AuthRole.superAdmin);
      expect((await sessionOf(launch(tenant)))?.role, AuthRole.mainAdmin);
    });
  });

  group('first run', () {
    test('a never-used device boots into the Main Admin persona', () async {
      final device = InMemoryLocalStore();
      expect(
          (await sessionOf(launch(device)))?.id, DemoPersona.mainAdmin.user.id);
    });

    test('and the seeding happens once, not once per launch', () async {
      final device = InMemoryLocalStore();
      await sessionOf(launch(device));

      // Sign out on a later launch, then relaunch: the device has been
      // through first-run seeding, so it must not be seeded again.
      final second = launch(device);
      await sessionOf(second);
      await second.read(signOutControllerProvider.notifier).signOut();

      expect(await sessionOf(launch(device)), isNull);
    });
  });

  group('sign-out', () {
    test('removes the durable record and the next launch stays signed out',
        () async {
      final device = InMemoryLocalStore();
      final first = launch(device);
      await first
          .read(demoSignInControllerProvider.notifier)
          .signInAs(DemoPersona.simpleAdmin);
      expect(device.values.containsKey(PersistentDemoSessionStore.personaKey),
          isTrue);

      final result =
          await first.read(signOutControllerProvider.notifier).signOut();
      expect(result?.isSuccess, isTrue);

      expect(
        device.values.containsKey(PersistentDemoSessionStore.personaKey),
        isFalse,
        reason: 'the durable key is gone, not blanked',
      );

      final second = launch(device);
      expect(await sessionOf(second), isNull);
      expect(second.read(capabilitiesProvider), Capabilities.none);
      expect(second.read(authGateProvider), AuthGate.signedOut);
    });

    test('it clears the forced session state too, not just the account',
        () async {
      // §7: sign-out clears *session* state. A lifecycle state forced by the
      // development inspector belongs to the session that was signed out, and
      // leaving it set would hand the next sign-in a suspension that belongs
      // to nobody.
      final container = launch(InMemoryLocalStore());
      await sessionOf(container);
      container.read(sessionAccessOverrideProvider.notifier).state =
          const SessionAccess(account: AccountStatus.revoked);
      expect(
          container.read(sessionAccessProvider).account, AccountStatus.revoked);

      await container.read(signOutControllerProvider.notifier).signOut();

      expect(container.read(sessionAccessProvider), SessionAccess.normal);
    });

    test('there is no separate developer logout', () async {
      // The ordinary `SignOutController` is what cleared the record above.
      // This asserts the other half: nothing else has to be called.
      final device = InMemoryLocalStore();
      final container = launch(device);
      await container
          .read(demoSignInControllerProvider.notifier)
          .signInAs(DemoPersona.mainAdmin);
      await container.read(signOutControllerProvider.notifier).signOut();
      expect(device.values[PersistentDemoSessionStore.personaKey], isNull);
    });
  });

  group('release safety', () {
    test('a stored persona is never read by a release configuration', () async {
      // A developer's device, handed to a shipping build.
      final device = InMemoryLocalStore({
        PersistentDemoSessionStore.personaKey: DemoPersona.mainAdmin.wire,
      });

      final release = launch(device, demoEnabled: false);
      expect(await sessionOf(release), isNull);
      expect(release.read(capabilitiesProvider), Capabilities.none);
    });

    test('and the record is not touched either — read or written', () async {
      final device = InMemoryLocalStore({
        PersistentDemoSessionStore.personaKey: DemoPersona.superAdmin.wire,
      });
      final before = Map.of(device.values);

      final release = launch(device, demoEnabled: false);
      await sessionOf(release);
      await release.read(signOutControllerProvider.notifier).signOut();

      expect(
        device.values,
        before,
        reason: 'refusing to honour a developer record is the requirement; '
            'deleting their device state from a production run is not',
      );
    });

    test('a release configuration is handed a store with no device behind it',
        () {
      final release = launch(InMemoryLocalStore(), demoEnabled: false);
      expect(release.read(demoSessionStoreProvider), isA<NoDemoSessionStore>());

      final development = launch(InMemoryLocalStore());
      expect(
        development.read(demoSessionStoreProvider),
        isA<PersistentDemoSessionStore>(),
      );
    });
  });

  group('the durable store itself', () {
    test('an unreadable device is not a session', () async {
      // A store that throws must fail closed — the opposite of the
      // forced-upgrade gate, because failing open here would invent a user.
      final store = PersistentDemoSessionStore(_BrokenStore());
      expect(await store.read(), isNull);
    });

    test('shared_preferences round-trips a persona id', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = PersistentDemoSessionStore(SharedPreferencesLocalStore());

      await store.write(DemoPersona.simpleAdmin.wire);
      // A second store object over the same platform storage: a relaunch.
      final next = PersistentDemoSessionStore(SharedPreferencesLocalStore());
      expect(await next.read(), DemoPersona.simpleAdmin.wire);

      await next.clear();
      expect(
        await PersistentDemoSessionStore(SharedPreferencesLocalStore()).read(),
        isNull,
      );
    });
  });
}

class _BrokenStore implements LocalStore {
  @override
  Future<String?> readString(String key) async => throw StateError('no device');

  @override
  Future<void> writeString(String key, String value) async {}

  @override
  Future<void> remove(String key) async {}
}
