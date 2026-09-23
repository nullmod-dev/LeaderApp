/// Persistence for the one development fact worth surviving a restart:
/// **which demo persona was selected.**
///
/// THE SEAM, and deliberately the smallest one that answers the requirement.
/// It stores a persona id and nothing else — no account, no capability set,
/// no token. The `AuthUser` is rebuilt from the id by `DemoPersona.user` on
/// the next launch, so a persisted grant can never disagree with the fixture
/// that defines it.
///
/// **Why this is not `SettingsRepository`.** That interface is user-chosen
/// preferences that a shipping build persists for every user; this is a
/// development artefact that a shipping build must actively refuse to read
/// (see `demoAccountsAllowed`). Putting it there would put a demo identity
/// inside the store production settings live in. It follows
/// `AppVersionGateStore` instead — one record, three operations, its own
/// interface — which is the pattern this repository already uses for "a
/// small fact that outlives the process but is not a preference".
///
/// A shipping build never reaches a real implementation of this:
/// `demoAccountsAllowed` is `const false` there, so `demoSessionStoreProvider`
/// hands it `NoDemoSessionStore` — which touches no device storage — and no
/// persona can be restored.
///
/// The durable implementation is `PersistentDemoSessionStore` (Point 3); it
/// writes through `core/storage/local_store.dart`, the app's one persistence
/// mechanism.
library;

abstract class DemoSessionStore {
  /// The stored persona id, or `null` when no development session is on
  /// file — which is also the state sign-out leaves behind.
  Future<String?> read();

  /// Records the selected persona.
  Future<void> write(String personaId);

  /// Drops the record. Called by ordinary sign-out, so a relaunch after
  /// signing out stays signed out rather than restoring the last persona.
  Future<void> clear();
}
