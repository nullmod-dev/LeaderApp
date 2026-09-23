import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/core/startup/startup_destination.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/session_access.dart';

/// Point 3 follow-up — **absent** versus **present-but-unsupported** on the
/// session envelope.
///
/// The behaviour being replaced: every unrecognised value read as the normal
/// one. That is right for an absent field (partial implementation is the
/// documented path) and wrong for a present one, because a server that sends
/// `accountStatus: "locked"` is *asserting a restriction* and an old client
/// reading it as `active` hands that account the whole application. This file
/// pins both halves so a future simplification cannot quietly merge them
/// again.
///
/// Pure `fromJson` + `resolveStartup` — no widget tree. The routing half (that
/// the refusal actually reaches a screen, and that neither `/home` nor
/// `/platform` is reachable underneath it) is in
/// `test/core/startup/startup_routing_test.dart`.

void main() {
  final now = DateTime.utc(2026, 9, 8, 12);

  StartupDestination resolve(SessionAccess access, {AuthUser? user}) =>
      resolveStartup(StartupInputs(
        gate: AuthGate.signedIn,
        now: now,
        user: user ?? _mainAdmin,
        access: access,
        hasTenantCapability: true,
      ));

  group('absent means the documented default', () {
    test('an empty envelope is exactly SessionAccess.normal', () {
      // The backend that has implemented none of this. It must keep working.
      final access = SessionAccess.fromJson(const {});
      expect(access, SessionAccess.normal);
      expect(access.hasUnsupportedState, isFalse);
      expect(resolve(access), StartupDestination.tenantSurface);
    });

    test('an explicit null is the same as an absent field', () {
      final access = SessionAccess.fromJson(const {
        'accountStatus': null,
        'tenantStatus': null,
        'demoMode': null,
        'mfaRequired': null,
        'sessionExpiresAt': null,
      });
      expect(access, SessionAccess.normal);
      expect(access.hasUnsupportedState, isFalse);
    });

    test('a property this build has never heard of is ignored, not refused',
        () {
      // The line the policy draws: an unknown *field* is additive metadata and
      // must not break a session. An unknown *value* in a field this client
      // already gates on is a different thing entirely — see below.
      final access = SessionAccess.fromJson(const {
        'accountStatus': 'active',
        'lastPasswordChangeAt': '2026-09-01T00:00:00Z',
        'someFutureFlag': true,
      });
      expect(access.hasUnsupportedState, isFalse);
      expect(resolve(access), StartupDestination.tenantSurface);
    });
  });

  group('known values keep their meaning', () {
    test('the normal ones resolve to the product surface', () {
      final access = SessionAccess.fromJson(const {
        'accountStatus': 'active',
        'tenantStatus': 'active',
        'demoMode': 'none',
        'mfaRequired': false,
      });
      expect(access, SessionAccess.normal);
      expect(resolve(access), StartupDestination.tenantSurface);
    });

    for (final (json, expected) in <(Map<String, dynamic>, StartupDestination)>[
      ({'accountStatus': 'suspended'}, StartupDestination.accountSuspended),
      ({'accountStatus': 'revoked'}, StartupDestination.accountRevoked),
      ({'accountStatus': 'pending_setup'}, StartupDestination.firstTimeSetup),
      ({'tenantStatus': 'suspended'}, StartupDestination.tenantSuspended),
      (
        {'tenantStatus': 'deletion_pending'},
        StartupDestination.tenantDeletionPending
      ),
      ({'tenantStatus': 'deleted'}, StartupDestination.tenantDeleted),
      ({'demoMode': 'active'}, StartupDestination.demoActive),
      ({'demoMode': 'expired'}, StartupDestination.demoExpired),
      ({'mfaRequired': true}, StartupDestination.mfaRequired),
    ]) {
      test('$json still resolves to ${expected.name}', () {
        final access = SessionAccess.fromJson(json);
        expect(access.hasUnsupportedState, isFalse, reason: '$json');
        final isCustomerDemo = json.containsKey('demoMode');
        expect(
          resolve(access, user: isCustomerDemo ? _customerDemo : _mainAdmin),
          expected,
        );
      });
    }
  });

  group('present but unsupported fails closed', () {
    /// One case per gating field, so the set that fails closed is the set the
    /// contract enumerates.
    final cases = <AccessLifecycleField, Map<String, dynamic>>{
      AccessLifecycleField.accountStatus: {'accountStatus': 'locked'},
      AccessLifecycleField.tenantStatus: {'tenantStatus': 'archived'},
      AccessLifecycleField.demoMode: {'demoMode': 'read_only'},
      AccessLifecycleField.mfaRequired: {'mfaRequired': 'pending'},
      AccessLifecycleField.sessionExpiresAt: {
        'sessionExpiresAt': 'not-a-timestamp'
      },
    };

    test('every gating field has a case here', () {
      // If a field is added to the envelope, this fails until it is decided
      // whether an unknown value in it is a refusal.
      expect(cases.keys.toSet(), AccessLifecycleField.values.toSet());
    });

    for (final entry in cases.entries) {
      test('an unknown ${entry.key.wire} refuses both surfaces', () {
        final access = SessionAccess.fromJson(entry.value);

        expect(access.hasUnsupportedState, isTrue);
        expect(access.unsupported.keys, [entry.key]);
        expect(
          resolve(access),
          StartupDestination.unsupportedAccessState,
          reason: 'a tenant session must not reach /home',
        );
        expect(
          resolve(access, user: _superAdmin),
          StartupDestination.unsupportedAccessState,
          reason: 'a platform session must not reach /platform either',
        );
      });
    }

    test('the field still reports its default, and nothing reads it', () {
      // The fallback exists so no caller ever holds a half-parsed object; it
      // is deliberately *not* what the decision is made on.
      final access = SessionAccess.fromJson(const {'accountStatus': 'locked'});
      expect(access.account, AccountStatus.active);
      expect(resolve(access), isNot(StartupDestination.tenantSurface));
    });

    test('an unsupported value outranks a known restrictive one', () {
      // Both are refusals, so which one wins matters only for the sentence the
      // person reads — and «this build cannot read your account state» is the
      // honest one when the envelope is partly unreadable.
      final access = SessionAccess.fromJson(const {
        'accountStatus': 'suspended',
        'demoMode': 'read_only',
      });
      expect(access.account, AccountStatus.suspended);
      expect(access.hasUnsupportedState, isTrue);
      expect(resolve(access), StartupDestination.unsupportedAccessState);
    });

    test('several unknown fields are all recorded', () {
      final access = SessionAccess.fromJson(const {
        'accountStatus': 'locked',
        'tenantStatus': 'archived',
      });
      expect(access.unsupported, {
        AccessLifecycleField.accountStatus: 'locked',
        AccessLifecycleField.tenantStatus: 'archived',
      });
    });

    test('a value of the wrong JSON type is unsupported, not a crash', () {
      // The parser used to `as String?` these, which throws on a number.
      final access = SessionAccess.fromJson(const {'accountStatus': 7});
      expect(access.hasUnsupportedState, isTrue);
      expect(access.unsupported[AccessLifecycleField.accountStatus], '7');
    });

    test('an unsupported state outranks nothing above authentication', () {
      // It must not tell a person whose session merely expired that their app
      // is out of date.
      expect(
        resolveStartup(StartupInputs(
          gate: AuthGate.expired,
          now: now,
          access: SessionAccess.unsupportedValue(
            AccessLifecycleField.accountStatus,
            'locked',
          ),
        )),
        StartupDestination.sessionExpired,
      );
      expect(
        resolveStartup(StartupInputs(
          gate: AuthGate.signedIn,
          now: now,
          user: _mainAdmin,
          upgradeBlocks: true,
          access: SessionAccess.unsupportedValue(
            AccessLifecycleField.demoMode,
            'read_only',
          ),
        )),
        StartupDestination.forcedUpgrade,
      );
    });
  });

  group('serialisation does not launder a refused state', () {
    test('an unsupported value round-trips as it arrived', () {
      const json = {
        'accountStatus': 'locked',
        'tenantStatus': 'active',
        'demoMode': 'none',
        'mfaRequired': false,
      };
      final access = SessionAccess.fromJson(json);

      // Not `active`: writing the fallback back out would turn a session this
      // build refused into one it accepts on the next read.
      expect(access.toJson(), json);
      expect(SessionAccess.fromJson(access.toJson()), access);
    });

    test('a normal envelope round-trips unchanged', () {
      final access = SessionAccess.fromJson(const {
        'accountStatus': 'suspended',
        'demoMode': 'active',
      });
      expect(SessionAccess.fromJson(access.toJson()), access);
    });

    test('a valid expiry parses to an absolute UTC instant and round-trips',
        () {
      final access = SessionAccess.fromJson(const {
        'sessionExpiresAt': '2026-09-08T14:30:00+02:00',
      });
      expect(access.hasUnsupportedState, isFalse);
      expect(access.sessionExpiresAt, DateTime.utc(2026, 9, 8, 12, 30));
      expect(access.isExpiredAt(DateTime.utc(2026, 9, 8, 12, 29)), isFalse);
      expect(access.isExpiredAt(DateTime.utc(2026, 9, 8, 12, 30)), isTrue);
      expect(
        access.toJson()['sessionExpiresAt'],
        '2026-09-08T12:30:00.000Z',
      );
      expect(SessionAccess.fromJson(access.toJson()), access);
    });

    test('an absent expiry stays absent and preserves 401-driven behaviour',
        () {
      final access = SessionAccess.fromJson(const {});
      expect(access.sessionExpiresAt, isNull);
      expect(access.toJson(), isNot(contains('sessionExpiresAt')));
      expect(resolve(access), StartupDestination.tenantSurface);
    });

    test('timezone-less and wrong-type expiries fail closed', () {
      for (final raw in <Object>['2026-09-08T14:30:00', 1234, true]) {
        final access = SessionAccess.fromJson({'sessionExpiresAt': raw});
        expect(access.hasUnsupportedState, isTrue, reason: '$raw');
        expect(
          access.unsupported[AccessLifecycleField.sessionExpiresAt],
          raw.toString(),
        );
        expect(resolve(access), StartupDestination.unsupportedAccessState);
      }
    });

    test('equality and hashing account for the unsupported map', () {
      final a = SessionAccess.fromJson(const {'accountStatus': 'locked'});
      final b = SessionAccess.fromJson(const {'accountStatus': 'locked'});
      final c = SessionAccess.fromJson(const {'accountStatus': 'frozen'});

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      // And an unsupported envelope is never equal to the normal one, which is
      // what makes `sessionAccessProvider` notify when one arrives.
      expect(a, isNot(SessionAccess.normal));
    });
  });

  group('the enums answer honestly on their own', () {
    test('tryParse returns null rather than a default', () {
      expect(AccountStatus.tryParse('active'), AccountStatus.active);
      expect(AccountStatus.tryParse('locked'), isNull);
      expect(SaasTenantStatus.tryParse('deleted'), SaasTenantStatus.deleted);
      expect(SaasTenantStatus.tryParse('archived'), isNull);
      expect(DemoMode.tryParse('expired'), DemoMode.expired);
      expect(DemoMode.tryParse('read_only'), isNull);
    });

    test('every wire string is distinct within its enum', () {
      for (final wires in [
        AccountStatus.values.map((v) => v.wire),
        SaasTenantStatus.values.map((v) => v.wire),
        DemoMode.values.map((v) => v.wire),
        AccessLifecycleField.values.map((v) => v.wire),
      ]) {
        expect(wires.toSet().length, wires.length);
      }
    });
  });
}

const _mainAdmin = AuthUser(
  id: 'u_tenant',
  name: 'مشرف',
  email: 'admin@mtm.org',
  role: AuthRole.mainAdmin,
  saasTenantId: 'saas_test',
  capabilities: Capabilities(global: Cap.all),
  orgName: 'MTM',
);

const _customerDemo = AuthUser(
  id: 'customer_demo',
  name: 'زائر النسخة التجريبية',
  email: 'customer-demo@local.invalid',
  role: AuthRole.customerDemo,
  saasTenantId: null,
  capabilities: Capabilities.none,
  orgName: 'مساحة MTM التجريبية',
);

const _superAdmin = AuthUser(
  id: 'u_platform',
  name: 'مدير منصة',
  email: 'nullmod.dev@gmail.com',
  role: AuthRole.superAdmin,
  saasTenantId: null,
  capabilities: Capabilities.none,
  orgName: 'MTM',
);
