import '../../../core/storage/local_store.dart';
import '../domain/demo_session_store.dart';
import 'demo_personas.dart';

/// The durable [DemoSessionStore] — the one that survives a real process
/// restart.
///
/// **What Point 2 left open, and this closes.** `InMemoryDemoSessionStore`
/// proved the seam and let a relaunch be *modelled* in a test (a second
/// container over the same object), but an actual app relaunch started from
/// nothing and fell back to the seed, so a developer who signed in as the
/// Simple Admin came back as the Main Admin and a developer who signed out
/// came back signed in. This writes the persona id to
/// [LocalStore] instead, so the selection survives process termination until
/// an explicit sign-out.
///
/// **Only the persona id.** The `AuthUser` — identity, capability grant,
/// tenant id — is rebuilt from that id by `DemoPersona.user` on the next
/// launch. Nothing about a grant is serialised, so a stored record can never
/// disagree with the fixture that defines it, and the value on disk
/// authenticates nothing on its own: it names a fixture that exists only in a
/// debug build.
///
/// **First run vs. signed out — the distinction the two keys exist for.**
/// A development device that has never been used should boot into a session
/// (the Main Admin), because that is what every screen, mock and existing test
/// is written against. A device that was signed out must stay signed out. One
/// key cannot say both: "no persona on file" is the state of *both*. So
/// [_seededKey] records that this device has been initialised at all, and it
/// is never cleared — [clear] removes the persona and leaves the marker, which
/// is exactly "someone signed out here" rather than "brand new device".
///
/// **Release safety is not this class's job and must not be.** It writes and
/// reads whatever it is asked to. Whether a demo persona may be *restored* is
/// decided above it, twice: `demoSessionStoreProvider` hands a release
/// configuration a store that touches no device storage at all, and
/// `MockAuthRepository` refuses the restore path outright when
/// `demoAccountsAllowed` is false. See `core/env/build_mode.dart`.
class PersistentDemoSessionStore implements DemoSessionStore {
  PersistentDemoSessionStore(
    this._store, {
    DemoPersona? seed = DemoPersona.mainAdmin,
  }) : _seed = seed;

  /// Namespaced so this record is unmistakable in a preference dump, and so a
  /// grep for `mtm.dev.` finds every development-only key at once.
  static const String personaKey = 'mtm.dev.demo_persona';

  /// Presence-only marker: this device has been through first-run seeding.
  static const String _seededKey = 'mtm.dev.demo_persona.seeded';
  static const String _seededValue = '1';

  final LocalStore _store;

  /// What a never-used development device boots as, or `null` to boot signed
  /// out. Applied exactly once per device, not once per launch.
  final DemoPersona? _seed;

  @override
  Future<String?> read() async {
    try {
      final stored = await _store.readString(personaKey);
      if (stored != null) return stored;
      if (await _store.readString(_seededKey) != null) {
        // Seeded before, and no persona on file: this device was signed out.
        return null;
      }
      await _store.writeString(_seededKey, _seededValue);
      final seed = _seed;
      if (seed == null) return null;
      await _store.writeString(personaKey, seed.wire);
      return seed.wire;
    } catch (_) {
      // A device that cannot be read is not a session. **Fail closed** — the
      // opposite of the forced-upgrade gate, where failing open only risks
      // letting an old build in; failing open here would invent an
      // authenticated user out of a storage error.
      //
      // Guarded here as well as in `SharedPreferencesLocalStore` on purpose:
      // this class is handed a `LocalStore` it does not control, and the one
      // rule it must not be able to break is that one.
      return null;
    }
  }

  @override
  Future<void> write(String personaId) async {
    await _store.writeString(_seededKey, _seededValue);
    await _store.writeString(personaKey, personaId);
  }

  @override
  Future<void> clear() async {
    // The persona record is removed, not blanked — a test asserting "the
    // durable key is gone after sign-out" is asserting the real thing. The
    // seeded marker stays, which is what stops the next launch re-seeding the
    // session the developer just left.
    await _store.remove(personaKey);
    await _store.writeString(_seededKey, _seededValue);
  }
}

/// A [DemoSessionStore] that holds nothing and remembers nothing.
///
/// What a **release configuration** gets. A stored persona left on a device by
/// a development build is then not merely ignored downstream — it is never
/// read, because nothing in a shipping configuration is wired to the storage
/// that holds it. The record is not deleted either: refusing to honour it is
/// the requirement; erasing a developer's device state from a production run
/// is not.
class NoDemoSessionStore implements DemoSessionStore {
  const NoDemoSessionStore();

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String personaId) async {}

  @override
  Future<void> clear() async {}
}
