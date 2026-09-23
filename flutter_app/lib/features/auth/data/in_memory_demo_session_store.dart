import '../domain/demo_session_store.dart';
import 'demo_personas.dart';

/// In-memory [DemoSessionStore].
///
/// **No longer what the app is wired to.** `demoSessionStoreProvider` hands a
/// development build `PersistentDemoSessionStore`, which survives a real
/// process restart — the gap Point 2 left open and Point 3 closed. This
/// remains as `MockAuthRepository`'s own fallback when it is constructed
/// without a store (a test that does not care about persistence), and as the
/// simplest way for a test to seed a session.
///
/// MOCK — same shape and same limitation as `MockSettingsRepository` and
/// `MockAppVersionGateStore`: it holds the record for the lifetime of this
/// object only. A second `ProviderContainer` built over the **same instance**
/// models an app relaunch, which is the idiom `forced_upgrade_test.dart`
/// established. It is not durable across an OS process restart; the durable
/// store is.
///
/// [seed] is what a development device looks like on first run, and it
/// defaults to the Main Admin persona for one reason: the mock has always
/// booted straight into a signed-in tenant session, and every screen, mock
/// repository and existing test is written against that. Moving that
/// assumption out of a hard-coded `_me` inside `MockAuthRepository` and into
/// the store is what makes sign-out stick across a relaunch — sign-out clears
/// the record, and a fresh repository over the cleared store reads `null` and
/// stays signed out.
class InMemoryDemoSessionStore implements DemoSessionStore {
  InMemoryDemoSessionStore({DemoPersona? seed = DemoPersona.mainAdmin})
      : _personaId = seed?.wire;

  String? _personaId;

  @override
  Future<String?> read() async => _personaId;

  @override
  Future<void> write(String personaId) async => _personaId = personaId;

  @override
  Future<void> clear() async => _personaId = null;
}
