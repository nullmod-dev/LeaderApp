import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/device_trust.dart';
import 'auth_providers.dart';
import 'http_auth_repository.dart';

/// `GET/DELETE /auth/devices`, approve and deny (`docs/api/auth.md`).
class HttpDeviceTrustRepository implements DeviceTrustRepository {
  HttpDeviceTrustRepository(this._api);

  final ApiClient _api;

  String _path(String id) => '/auth/devices/${Uri.encodeComponent(id)}';

  @override
  Future<Result<AccountDevices>> listDevices() => _api.send(
        'GET',
        '/auth/devices',
        parse: (json) => AccountDevices.fromJson(json as Map<String, dynamic>),
      );

  @override
  Future<Result<void>> approve(String deviceId) =>
      _api.send('POST', '${_path(deviceId)}/approve', parse: (_) {});

  @override
  Future<Result<DenyDeviceOutcome>> deny(String deviceId) => _api.send(
        'POST',
        '${_path(deviceId)}/deny',
        parse: (json) => DenyDeviceOutcome(
          passwordReset:
              (json as Map<String, dynamic>)['passwordReset'] == true,
        ),
      );

  @override
  Future<Result<void>> remove(String deviceId) =>
      _api.send('DELETE', _path(deviceId), parse: (_) {});
}

/// The development and test stand-in: this phone, trusted, and nothing else.
/// A mock session is never restricted, so there is nothing to approve.
class MockDeviceTrustRepository implements DeviceTrustRepository {
  MockDeviceTrustRepository({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  @override
  Future<Result<AccountDevices>> listDevices() async {
    final now = _clock().toUtc();
    return Success(AccountDevices(limit: 3, devices: [
      AccountDevice(
        id: 'dv_this',
        label: 'Leader app',
        status: AccountDeviceStatus.trusted,
        current: true,
        restricted: false,
        signedInAt: now,
        lastSeenAt: now,
      ),
    ]));
  }

  @override
  Future<Result<void>> approve(String deviceId) async =>
      const Failure('', code: 'not_found');

  @override
  Future<Result<DenyDeviceOutcome>> deny(String deviceId) async =>
      const Failure('', code: 'not_found');

  @override
  Future<Result<void>> remove(String deviceId) async =>
      const Failure('', code: 'not_found');
}

/// Overridden with [HttpDeviceTrustRepository] in `backend_overrides.dart`.
final deviceTrustRepositoryProvider = Provider<DeviceTrustRepository>((ref) {
  return MockDeviceTrustRepository();
});

/// The account's devices, read when a screen asks and dropped when it leaves.
final accountDevicesProvider =
    FutureProvider.autoDispose<Result<AccountDevices>>((ref) {
  return ref.watch(deviceTrustRepositoryProvider).listDevices();
});

/// Yes / No / remove, with the follow-ups each one owes: re-reading the
/// session (the restriction or the notice changed) and, after a No, leaving
/// this phone signed out — the server already ended every session.
class DeviceTrustController {
  DeviceTrustController(this._ref);

  final Ref _ref;

  DeviceTrustRepository get _repo => _ref.read(deviceTrustRepositoryProvider);

  Future<Result<void>> approve(String deviceId) async {
    final result = await _repo.approve(deviceId);
    if (result is Success) {
      _ref.invalidate(currentUserResultProvider);
      _ref.invalidate(accountDevicesProvider);
    }
    return result;
  }

  Future<Result<DenyDeviceOutcome>> deny(String deviceId) async {
    final result = await _repo.deny(deviceId);
    if (result is Success) {
      final auth = _ref.read(authRepositoryProvider);
      if (auth is HttpAuthRepository) {
        await auth.forgetLocalSession();
      } else {
        await auth.signOut();
      }
      _ref.invalidate(currentUserResultProvider);
      await _ref.read(currentUserResultProvider.future);
    }
    return result;
  }

  Future<Result<void>> remove(String deviceId) async {
    final result = await _repo.remove(deviceId);
    if (result is Success) _ref.invalidate(accountDevicesProvider);
    return result;
  }
}

final deviceTrustControllerProvider = Provider<DeviceTrustController>(
  DeviceTrustController.new,
);
