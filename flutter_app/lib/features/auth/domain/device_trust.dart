/// Device trust, seen from the app (`docs/api/auth.md` → Device trust).
///
/// The server decides everything here: which device is trusted, which is
/// restricted and for how long, and what a restricted session may do. The
/// app lists the account's devices, lets a trusted device answer Yes or No
/// to a new one, and removes a device. Nothing in this file grants access.
library;

import 'package:flutter/foundation.dart';

import '../../../core/result/result.dart';

enum AccountDeviceStatus {
  trusted('trusted'),
  untrusted('untrusted'),

  /// A status this build does not know; shown without a verdict.
  other('');

  const AccountDeviceStatus(this.wire);

  final String wire;

  static AccountDeviceStatus parse(Object? raw) {
    for (final status in values) {
      if (status != other && status.wire == raw) return status;
    }
    return other;
  }
}

/// One row of `GET /auth/devices`.
@immutable
class AccountDevice {
  const AccountDevice({
    required this.id,
    required this.label,
    required this.status,
    required this.current,
    required this.restricted,
    required this.signedInAt,
    required this.lastSeenAt,
    this.restrictedUntil,
  });

  final String id;
  final String label;
  final AccountDeviceStatus status;

  /// The device this app is running on.
  final bool current;

  /// Its sessions are restricted now (a new device's window, or untrusted).
  final bool restricted;
  final DateTime? restrictedUntil;
  final DateTime signedInAt;
  final DateTime lastSeenAt;

  factory AccountDevice.fromJson(Map<String, dynamic> j) {
    final until = j['restrictedUntil'];
    return AccountDevice(
      id: j['id'] as String,
      label: (j['label'] as String?) ?? '',
      status: AccountDeviceStatus.parse(j['status']),
      current: j['current'] == true,
      restricted: j['restricted'] == true,
      restrictedUntil: until is String ? DateTime.parse(until).toUtc() : null,
      signedInAt: DateTime.parse(j['signedInAt'] as String).toUtc(),
      lastSeenAt: DateTime.parse(j['lastSeenAt'] as String).toUtc(),
    );
  }
}

/// `GET /auth/devices`: the trusted-device limit and the devices (trusted
/// first; blocked devices are never listed).
@immutable
class AccountDevices {
  const AccountDevices({required this.limit, required this.devices});

  final int limit;
  final List<AccountDevice> devices;

  int get trustedCount =>
      devices.where((d) => d.status == AccountDeviceStatus.trusted).length;

  factory AccountDevices.fromJson(Map<String, dynamic> j) => AccountDevices(
        limit: (j['limit'] as num).toInt(),
        devices: List.unmodifiable([
          for (final row in j['devices'] as List)
            AccountDevice.fromJson(row as Map<String, dynamic>),
        ]),
      );
}

/// What a "No" did: every session ended, and whether the account must reset
/// its password (an account without one — Google only — does not).
@immutable
class DenyDeviceOutcome {
  const DenyDeviceOutcome({required this.passwordReset});

  final bool passwordReset;
}

/// The device-trust seam. Online only: every answer comes from the server.
abstract class DeviceTrustRepository {
  Future<Result<AccountDevices>> listDevices();

  /// "Yes, this is my device": the new device's restriction lifts now.
  /// `trusted_device_limit` when an untrusted device cannot be trusted
  /// until another is removed.
  Future<Result<void>> approve(String deviceId);

  /// "No, this is not me": the device is blocked and EVERY session of the
  /// account ends, this one included.
  Future<Result<DenyDeviceOutcome>> deny(String deviceId);

  /// Removes a device (never the current one): its sessions end and it is a
  /// new device next time.
  Future<Result<void>> remove(String deviceId);
}

/// The wire code [DeviceTrustRepository.approve] answers when the limit is full.
const trustedDeviceLimitCode = 'trusted_device_limit';
