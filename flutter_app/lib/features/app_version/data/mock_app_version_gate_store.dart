import '../domain/app_version_gate_store.dart';

/// In-memory stand-in for [AppVersionGateStore].
///
/// MOCK — same shape and same limitation as `MockSettingsRepository`: it
/// holds the record for the lifetime of this object only, so it proves the
/// seam and lets the offline-restart behaviour be tested (a second
/// [ProviderContainer] built over the *same instance* is a relaunch), but it
/// is not durable across an OS process restart. A concrete implementation
/// writes `PersistedUpgradeGate.toJson()` to local preferences; see
/// `FRONTEND-BACKEND-INTEGRATION.md` §1.
class MockAppVersionGateStore implements AppVersionGateStore {
  MockAppVersionGateStore({PersistedUpgradeGate? seed}) : _record = seed;

  PersistedUpgradeGate? _record;

  @override
  Future<PersistedUpgradeGate?> read() async => _record;

  @override
  Future<void> write(PersistedUpgradeGate gate) async => _record = gate;

  @override
  Future<void> clear() async => _record = null;
}
