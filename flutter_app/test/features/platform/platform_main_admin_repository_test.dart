import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/platform/data/mock_platform_main_admin_repository.dart';
import 'package:mtm/features/platform/data/mock_tenant_lifecycle_repository.dart';
import 'package:mtm/features/platform/data/platform_main_admin_fixtures.dart';
import 'package:mtm/features/platform/data/platform_tenant_store.dart';
import 'package:mtm/features/platform/domain/platform_main_admin_models.dart';
import 'package:mtm/features/platform/domain/platform_main_admin_repository.dart';
import 'package:mtm/features/platform/domain/saas_tenant_models.dart';
import 'package:mtm/features/platform/domain/tenant_lifecycle_models.dart';

void main() {
  var now = DateTime.utc(2026, 9, 11, 9);

  setUp(() => now = DateTime.utc(2026, 9, 11, 9));

  PlatformTenantStore store() => PlatformTenantStore(clock: () => now);

  MockPlatformMainAdminRepository repo(
    PlatformTenantStore store, {
    MockMainAdminMode mode = MockMainAdminMode.loaded,
    bool permitted = true,
  }) =>
      MockPlatformMainAdminRepository(
        store: store,
        clock: () => now,
        permitted: () => permitted,
        mode: mode,
        latency: Duration.zero,
      );

  T unwrap<T>(Result<T> result) => result.when(
        success: (data, {stale = false}) => data,
        failure: (message, code) => throw TestFailure('$code: $message'),
        offline: (_) => throw TestFailure('offline'),
      );

  String? code<T>(Result<T> result) => result.when(
        success: (_, {stale = false}) => null,
        failure: (_, code) => code,
        offline: (_) => 'offline',
      );

  Future<MainAdminAccountSnapshot> load(
    MockPlatformMainAdminRepository r,
    String tenantId,
  ) async =>
      unwrap(await r.load(tenantId));

  SuspendMainAdminCommand suspend(
    MainAdminAccountSnapshot s, {
    String key = 'attempt-suspend',
    String reason = 'اشتباه في مشاركة بيانات الدخول',
    int? revision,
  }) =>
      SuspendMainAdminCommand(
        tenantId: s.tenant.tenantId,
        expectedRevision: revision ?? s.revision,
        idempotencyKey: mainAdminIdempotencyKey(MainAdminAction.suspend, key),
        reason: reason,
      );

  ReplaceMainAdminCommand replace(
    MainAdminAccountSnapshot s, {
    String key = 'attempt-replace',
    String email = 'new.admin@example.org',
    String name = 'مدير جديد',
  }) =>
      ReplaceMainAdminCommand(
        tenantId: s.tenant.tenantId,
        expectedRevision: s.revision,
        idempotencyKey: mainAdminIdempotencyKey(MainAdminAction.replace, key),
        designate: MainAdminDesignateIdentity(
          displayName: name,
          loginEmail: email,
        ),
        reason: 'طلبت الجهة تغيير المدير الرئيسي',
      );

  /// Everything a Main Admin account action must never change.
  Map<String, Object?> untouched(PlatformTenantStore s, String tenantId) {
    final tenant = s.byId(tenantId)!;
    return {
      'lifecycle': tenant.lifecycle.toJson(),
      'subscription': tenant.subscription.toJson(),
      'teamCode': tenant.teamCode,
      'counts': tenant.counts.toJson(),
      'history': [for (final e in s.historyOf(tenant)) e.toJson()],
      'features': s.featuresOf(tenantId)?.toString(),
    };
  }

  group('reads', () {
    test('fixtures cover every seat scenario, positioned by the clock',
        () async {
      final r = repo(store());
      final hilal = await load(r, 'saas_hilal');
      expect(hilal.current.status, MainAdminAccountStatus.active);
      expect(hilal.readAt, now);
      expect(hilal.current.loginEmail, 'salma@hilal-medical.org');

      final nabd = await load(r, MainAdminFixtures.pendingSetupTenantId);
      expect(nabd.current.status, MainAdminAccountStatus.pendingSetup);
      expect(nabd.current.setup!.effectiveStatusAt(now),
          MainAdminSetupStatus.outstanding);

      final najd = await load(r, MainAdminFixtures.replacementTenantId);
      expect(najd.replacement!.status, MainAdminReplacementStatus.pending);
      expect(najd.replacement!.designate.loginEmail,
          MainAdminFixtures.designateEmail);

      final sahel = await load(r, MainAdminFixtures.suspendedAccountTenantId);
      expect(sahel.current.status, MainAdminAccountStatus.suspended);
      expect(sahel.tenant.lifecycleStatus, SaasTenantStatus.active);

      final rukn = await load(r, MainAdminFixtures.suspendedTenantId);
      expect(rukn.tenant.lifecycleStatus, SaasTenantStatus.suspended);
      expect(rukn.current.status, MainAdminAccountStatus.active);
    });

    test('the seat describes the same person as the tenant contact', () async {
      final s = store();
      final r = repo(s);
      for (final tenant in s.tenants) {
        final seat = await load(r, tenant.id);
        expect(seat.current.loginEmail,
            normalizeMainAdminEmail(tenant.mainAdmin.email));
        expect(seat.current.status == MainAdminAccountStatus.pendingSetup,
            tenant.mainAdmin.setupPending);
      }
    });

    test('a newly registered tenant starts with a pending, invited seat',
        () async {
      final s = store();
      final created = s.create(const SaasTenantDraft(
        displayName: 'فريق جديد',
        mainAdminName: 'مدير الفريق',
        mainAdminEmail: 'lead@new-team.org',
        teamCode: 'MTM-7KXP-3RQV',
      ));
      final seat = await load(repo(s), created.id);
      expect(seat.current.status, MainAdminAccountStatus.pendingSetup);
      expect(seat.current.setup!.lastSentAt, created.createdAt);
    });

    test('missing and deleted tenants never yield a seat', () async {
      final s = store();
      final r = repo(s);
      expect(code(await r.load('saas_nope')), 'tenant_not_found');

      final lifecycle = MockTenantLifecycleRepository(
        store: s,
        clock: () => now,
        latency: Duration.zero,
      );
      final hilal = s.byId('saas_hilal')!;
      await lifecycle.beginDeletion(BeginTenantDeletionCommand(
        tenantId: hilal.id,
        expectedVersion: hilal.tenantVersion,
        idempotencyKey: 'begin',
        reason: 'طلب الجهة',
      ));
      now = now.add(const Duration(days: 31));
      final pending = s.byId('saas_hilal')!;
      await lifecycle.finalizeDeletion(FinalizeTenantDeletionCommand(
        tenantId: pending.id,
        expectedVersion: pending.tenantVersion,
        idempotencyKey: 'final',
      ));
      expect(code(await r.load('saas_hilal')), 'tenant_already_deleted');
      expect(s.byId('saas_hilal'), isNull);
    });

    test('offline serves only the last authoritative read; stale is flagged',
        () async {
      final s = store();
      final offline = repo(s, mode: MockMainAdminMode.offline);
      final none = await offline.load('saas_hilal');
      expect(none, isA<Offline<MainAdminAccountSnapshot>>());
      expect((none as Offline<MainAdminAccountSnapshot>).cached, isNull);

      final stale =
          await repo(s, mode: MockMainAdminMode.stale).load('saas_hilal');
      expect((stale as Success<MainAdminAccountSnapshot>).stale, isTrue);

      final unsupported = await load(
          repo(s, mode: MockMainAdminMode.unsupportedState), 'saas_hilal');
      expect(unsupported.hasUnsupportedState, isTrue);
    });

    test('a non-super-admin session is refused every read and write', () async {
      final r = repo(store(), permitted: false);
      expect(code(await r.load('saas_hilal')), 'not_permitted');
      final s = await load(repo(store()), 'saas_hilal');
      expect(code(await r.suspend(suspend(s))), 'not_permitted');
    });
  });

  group('commands', () {
    test('suspend succeeds once; the same attempt replays with no new effect',
        () async {
      final s = store();
      final r = repo(s);
      final before = await load(r, 'saas_hilal');
      final first = unwrap(await r.suspend(suspend(before)));
      expect(first.changed, isTrue);
      expect(first.effect, MainAdminMutationEffect.suspended);
      expect(first.effect.endsSessions, isTrue);
      expect(first.snapshot.revision, before.revision + 1);

      final replay = unwrap(await r.suspend(suspend(before)));
      expect(replay.idempotentReplay, isTrue);
      expect(replay.changed, isFalse);
      expect((await load(r, 'saas_hilal')).revision, before.revision + 1);
    });

    test('a reused key for a different command is a conflict', () async {
      final r = repo(store());
      final before = await load(r, 'saas_hilal');
      unwrap(await r.suspend(suspend(before)));
      expect(
        code(await r.suspend(suspend(before, reason: 'سبب مختلف'))),
        'idempotency_conflict',
      );
    });

    test('a stale revision is refused without overwrite', () async {
      final r = repo(store());
      final before = await load(r, 'saas_hilal');
      expect(
        code(await r.suspend(suspend(before, revision: before.revision + 3))),
        'stale_main_admin',
      );
      expect((await load(r, 'saas_hilal')).current.status,
          MainAdminAccountStatus.active);
    });

    test('offline, failure and recent-auth refuse without any effect',
        () async {
      final s = store();
      final live = repo(s);
      final before = await load(live, 'saas_hilal');
      final contact = s.byId('saas_hilal')!.mainAdmin.toJson();
      expect(
        await repo(s, mode: MockMainAdminMode.offline).suspend(suspend(before)),
        isA<Offline<MainAdminMutationResult>>(),
      );
      expect(
        code(await repo(s, mode: MockMainAdminMode.failure)
            .suspend(suspend(before))),
        'server',
      );
      expect(
        code(await repo(s, mode: MockMainAdminMode.recentAuthRequired)
            .replace(replace(before))),
        'recent_authentication_required',
      );
      expect(s.byId('saas_hilal')!.mainAdmin.toJson(), contact);
      expect((await load(live, 'saas_hilal')).revision, before.revision);
    });

    test('invalid transitions, reasons and malformed commands are typed',
        () async {
      final r = repo(store());
      final hilal = await load(r, 'saas_hilal');
      expect(
        code(await r.reactivate(ReactivateMainAdminCommand(
          tenantId: hilal.tenant.tenantId,
          expectedRevision: hilal.revision,
          idempotencyKey: 'k1',
        ))),
        'invalid_main_admin_transition',
      );
      expect(code(await r.suspend(suspend(hilal, reason: '   '))),
          'invalid_main_admin_reason');
      expect(
        code(await r.suspend(SuspendMainAdminCommand(
          tenantId: 'saas_hilal',
          expectedRevision: hilal.revision,
          idempotencyKey: ' ',
          reason: 'سبب',
        ))),
        'validation',
      );
      expect(
        code(await r.resendSetup(ResendMainAdminSetupCommand(
          tenantId: 'saas_hilal',
          expectedRevision: hilal.revision,
          idempotencyKey: 'k2',
          target: MainAdminSetupTarget.current,
        ))),
        'invalid_main_admin_transition',
      );
    });

    test('suspended account reactivates on an active tenant', () async {
      final r = repo(store());
      final sahel = await load(r, MainAdminFixtures.suspendedAccountTenantId);
      final result = unwrap(await r.reactivate(ReactivateMainAdminCommand(
        tenantId: sahel.tenant.tenantId,
        expectedRevision: sahel.revision,
        idempotencyKey: 'k',
      )));
      expect(result.snapshot.current.status, MainAdminAccountStatus.active);
      expect(result.effect.endsSessions, isFalse);
    });
  });

  group('tenant lifecycle interaction', () {
    test('suspended tenant: suspend allowed, access-opening actions refused',
        () async {
      final s = store();
      final r = repo(s);
      final rukn = await load(r, MainAdminFixtures.suspendedTenantId);
      expect(code(await r.replace(replace(rukn))), 'tenant_not_eligible');
      final suspended = unwrap(await r.suspend(suspend(rukn)));
      expect(
          suspended.snapshot.current.status, MainAdminAccountStatus.suspended);
      expect(
        code(await r.reactivate(ReactivateMainAdminCommand(
          tenantId: rukn.tenant.tenantId,
          expectedRevision: suspended.snapshot.revision,
          idempotencyKey: 'react',
        ))),
        'tenant_not_eligible',
      );
      expect(s.byId(MainAdminFixtures.suspendedTenantId)!.tenantStatus,
          SaasTenantStatus.suspended);
    });

    test('deletion pending: cancel/suspend allowed, resend/replace refused',
        () async {
      final s = store();
      final r = repo(s);
      final lifecycle = MockTenantLifecycleRepository(
        store: s,
        clock: () => now,
        latency: Duration.zero,
      );
      final najdTenant = s.byId(MainAdminFixtures.replacementTenantId)!;
      await lifecycle.beginDeletion(BeginTenantDeletionCommand(
        tenantId: najdTenant.id,
        expectedVersion: najdTenant.tenantVersion,
        idempotencyKey: 'begin',
        reason: 'طلب الجهة',
      ));
      final najd = await load(r, najdTenant.id);
      expect(najd.tenant.lifecycleStatus, SaasTenantStatus.deletionPending);
      expect(
        code(await r.resendSetup(ResendMainAdminSetupCommand(
          tenantId: najd.tenant.tenantId,
          expectedRevision: najd.revision,
          idempotencyKey: 'resend',
          target: MainAdminSetupTarget.replacement,
        ))),
        'tenant_not_eligible',
      );
      expect(
        r.simulateReplacementSetupCompleted(najd.tenant.tenantId),
        isA<MainAdminTransitionRefused>(),
      );
      final cancelled = unwrap(await r.cancelReplacement(
        CancelMainAdminReplacementCommand(
          tenantId: najd.tenant.tenantId,
          expectedRevision: najd.revision,
          idempotencyKey: 'cancel',
          replacementId: najd.replacement!.id,
        ),
      ));
      expect(cancelled.snapshot.replacement, isNull);
      expect(s.byId(najdTenant.id)!.tenantStatus,
          SaasTenantStatus.deletionPending);
    });

    test('no account action writes tenant lifecycle, commerce or history',
        () async {
      final s = store();
      final r = repo(s);
      final hilalBefore = untouched(s, 'saas_hilal');
      final hilal = await load(r, 'saas_hilal');
      final suspended = unwrap(await r.suspend(suspend(hilal))).snapshot;
      unwrap(await r.reactivate(ReactivateMainAdminCommand(
        tenantId: 'saas_hilal',
        expectedRevision: suspended.revision,
        idempotencyKey: 'react',
      )));
      final pending = unwrap(await r.replace(replace(
        await load(r, 'saas_hilal'),
      )))
          .snapshot;
      unwrap(await r.cancelReplacement(CancelMainAdminReplacementCommand(
        tenantId: 'saas_hilal',
        expectedRevision: pending.revision,
        idempotencyKey: 'cancel',
        replacementId: pending.replacement!.id,
      )));
      expect(untouched(s, 'saas_hilal'), hilalBefore);
    });
  });

  group('replacement', () {
    test('never-activated account: replaced immediately, contact follows',
        () async {
      final s = store();
      final r = repo(s);
      final before = untouched(s, MainAdminFixtures.pendingSetupTenantId);
      final nabd = await load(r, MainAdminFixtures.pendingSetupTenantId);
      final result = unwrap(await r.replace(replace(nabd)));
      expect(result.effect, MainAdminMutationEffect.replaced);
      expect(result.snapshot.current.loginEmail, 'new.admin@example.org');
      expect(
          result.snapshot.current.status, MainAdminAccountStatus.pendingSetup);
      expect(result.snapshot.current.accountId, isNot(nabd.current.accountId));
      expect(result.snapshot.replacement, isNull);

      final contact = s.byId(MainAdminFixtures.pendingSetupTenantId)!.mainAdmin;
      expect(contact.email, 'new.admin@example.org');
      expect(contact.provisioning, MainAdminProvisioning.pendingSetup);
      expect(untouched(s, MainAdminFixtures.pendingSetupTenantId), before);
    });

    test('active account: authority moves only when the designate completes',
        () async {
      final s = store();
      final r = repo(s);
      final hilal = await load(r, 'saas_hilal');
      final started = unwrap(await r.replace(replace(hilal)));
      expect(started.effect, MainAdminMutationEffect.replacementStarted);
      expect(started.snapshot.current.accountId, hilal.current.accountId);
      expect(s.byId('saas_hilal')!.mainAdmin.email, hilal.current.loginEmail);

      final done = r.simulateReplacementSetupCompleted('saas_hilal')
          as MainAdminTransitionAllowed;
      expect(done.revokedAccountId, hilal.current.accountId);
      final after = await load(r, 'saas_hilal');
      expect(after.current.loginEmail, 'new.admin@example.org');
      expect(after.current.status, MainAdminAccountStatus.active);
      expect(after.replacement, isNull);
      expect(s.byId('saas_hilal')!.mainAdmin.email, 'new.admin@example.org');
      expect(s.byId('saas_hilal')!.mainAdmin.provisioning,
          MainAdminProvisioning.active);
    });

    test('one replacement at a time; cancel needs the reviewed replacement',
        () async {
      final r = repo(store());
      final najd = await load(r, MainAdminFixtures.replacementTenantId);
      expect(code(await r.replace(replace(najd))),
          'main_admin_replacement_already_pending');
      expect(
        code(await r.cancelReplacement(CancelMainAdminReplacementCommand(
          tenantId: najd.tenant.tenantId,
          expectedRevision: najd.revision,
          idempotencyKey: 'cancel',
          replacementId: 'mar_other',
        ))),
        'invalid_main_admin_transition',
      );
    });

    test('identity: same login is invalid, another account is unavailable',
        () async {
      final r = repo(store());
      final hilal = await load(r, 'saas_hilal');
      expect(
        code(
            await r.replace(replace(hilal, email: ' SALMA@hilal-medical.org'))),
        'invalid_main_admin_identity',
      );
      expect(
        code(await r.replace(
            replace(hilal, key: 'k2', email: 'badr@najd-response.sa'))),
        'main_admin_identity_unavailable',
      );
      expect(
        code(await r.replace(replace(hilal,
            key: 'k3', email: MainAdminFixtures.designateEmail))),
        'main_admin_identity_unavailable',
      );
    });

    test('an expired invitation cannot complete; a resend revives it',
        () async {
      final r = repo(store());
      // Seed the clock-positioned fixtures first, then let time pass.
      await load(r, MainAdminFixtures.pendingSetupTenantId);
      now = now.add(const Duration(days: 30));
      final nabd = await load(r, MainAdminFixtures.pendingSetupTenantId);
      expect(nabd.current.setup!.effectiveStatusAt(now),
          MainAdminSetupStatus.expired);
      expect(r.simulateSetupCompleted(nabd.tenant.tenantId),
          isA<MainAdminTransitionRefused>());
      final resent = unwrap(await r.resendSetup(ResendMainAdminSetupCommand(
        tenantId: nabd.tenant.tenantId,
        expectedRevision: nabd.revision,
        idempotencyKey: 'resend',
        target: MainAdminSetupTarget.current,
      )));
      expect(resent.effect, MainAdminMutationEffect.setupResent);
      expect(resent.snapshot.current.setup!.lastSentAt, now);
      expect(r.simulateSetupCompleted(nabd.tenant.tenantId),
          isA<MainAdminTransitionAllowed>());
    });
  });

  /// Source without comments: the docs rightly *name* what is excluded
  /// ("no impersonation", "no `Cap`"); only code must not contain it.
  String sourceOf(String path) => File(path)
      .readAsLinesSync()
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  group('separation', () {
    const files = [
      'lib/features/platform/domain/platform_main_admin_models.dart',
      'lib/features/platform/domain/platform_main_admin_repository.dart',
      'lib/features/platform/data/platform_main_admin_fixtures.dart',
      'lib/features/platform/data/mock_platform_main_admin_repository.dart',
      'lib/features/platform/data/platform_main_admin_providers.dart',
    ];

    test(
        'imports no tenant operational, auth, audit, lifecycle-repository, '
        'break-glass, capability or outbox seam', () {
      const forbidden = [
        'features/detachment',
        'features/team',
        'features/shift',
        'features/inventory',
        'features/workshop',
        'features/home',
        'features/notification',
        'features/announcement',
        'features/settings',
        'auth_repository',
        'mock_auth_repository',
        'tenant_lifecycle_repository',
        'mock_tenant_lifecycle_repository',
        'saas_tenant_repository',
        'platform_audit',
        'platform_break_glass',
        'platform_security',
        'core/access/capability',
        'core/storage',
        'sync/',
        'outbox',
      ];
      for (final path in files) {
        final imports = File(path)
            .readAsLinesSync()
            .where((line) => line.startsWith('import '));
        for (final line in imports) {
          for (final token in forbidden) {
            expect(line.contains(token), isFalse, reason: '$path → $line');
          }
        }
      }
    });

    test('no field can hold a credential, secret, token, session or device',
        () {
      final field = RegExp(r'^\s*final\s+[\w<>?, ]+\s+(\w+);', multiLine: true);
      final forbidden = RegExp(
        r'password|hash|otp|secret|token|backup|mfa|session|device|'
        r'credential|teamcode|^ip$|ipaddress',
        caseSensitive: false,
      );
      for (final path in files) {
        for (final match in field.allMatches(File(path).readAsStringSync())) {
          final name = match.group(1)!;
          expect(forbidden.hasMatch(name), isFalse,
              reason: '$path declares $name');
        }
      }
    });

    test('no tenant Cap authorizes the Platform surface', () {
      final cap = RegExp(r'\bCap\.|\bCapabilities\b|capability_guard');
      for (final path in files) {
        expect(cap.hasMatch(sourceOf(path)), isFalse, reason: path);
      }
    });

    test('the seam carries no Point 17 onboarding or credential operation', () {
      final source = sourceOf(files[1]);
      final methods = RegExp(r'Future<Result<\w+>>\s+(\w+)\(')
          .allMatches(source)
          .map((m) => m.group(1))
          .toSet();
      expect(methods, {
        'load',
        'resendSetup',
        'suspend',
        'reactivate',
        'replace',
        'cancelReplacement',
      });
      final onboarding = RegExp(
        r'signUp|signIn|verifyOtp|linkTeamCode|setPassword|changePassword|'
        r'resetPassword|requestPasswordReset|impersonat|disableMfa|resetMfa|'
        r'listSessions|revokeSession|updateAccount|updateEmail',
      );
      for (final path in files) {
        expect(onboarding.hasMatch(sourceOf(path)), isFalse, reason: path);
      }
    });
  });
}
