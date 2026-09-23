import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/session_access.dart';
import 'package:mtm/features/platform/domain/platform_main_admin_models.dart';

void main() {
  final now = DateTime.utc(2026, 9, 11, 9);

  MainAdminTenantReference tenant([
    SaasTenantStatus status = SaasTenantStatus.active,
  ]) =>
      MainAdminTenantReference(
        tenantId: 'saas_hilal',
        displayName: 'فرق الهلال الطبية',
        lifecycleStatus: status,
        lifecycleVersion: 4,
      );

  MainAdminSetupState setup({DateTime? sentAt}) => MainAdminSetupState(
        status: MainAdminSetupStatus.outstanding,
        lastSentAt: sentAt ?? now.subtract(const Duration(days: 1)),
        expiresAt: (sentAt ?? now.subtract(const Duration(days: 1)))
            .add(kProvisionalMainAdminSetupValidity),
      );

  MainAdminAccount account(MainAdminAccountStatus status) => MainAdminAccount(
        accountId: 'ma_hilal',
        displayName: 'سلمى الحارثي',
        loginEmail: 'Salma@Hilal-Medical.org ',
        status: status,
        createdAt: now.subtract(const Duration(days: 300)),
        activatedAt: status == MainAdminAccountStatus.pendingSetup
            ? null
            : now.subtract(const Duration(days: 299)),
        setup: status == MainAdminAccountStatus.pendingSetup ? setup() : null,
        suspension: status == MainAdminAccountStatus.suspended
            ? MainAdminSuspension(
                suspendedAt: now.subtract(const Duration(days: 2)),
                reason: 'سبب إداري',
              )
            : null,
      );

  MainAdminReplacement replacement() => MainAdminReplacement(
        id: 'mar_1',
        status: MainAdminReplacementStatus.pending,
        designate: MainAdminDesignate(
          accountId: 'ma_new_1',
          displayName: 'ريم القحطاني',
          loginEmail: 'reem@example.org',
          setup: setup(),
        ),
        requestedAt: now.subtract(const Duration(days: 1)),
        reason: 'تغيير المدير الرئيسي',
      );

  MainAdminAccountSnapshot seat(
    MainAdminAccountStatus status, {
    SaasTenantStatus tenantStatus = SaasTenantStatus.active,
    bool pendingReplacement = false,
  }) =>
      MainAdminAccountSnapshot(
        tenant: tenant(tenantStatus),
        revision: 5,
        current: account(status),
        replacement: pendingReplacement ? replacement() : null,
        readAt: now,
      );

  const identity = MainAdminDesignateIdentity(
    displayName: '  ريم   القحطاني ',
    loginEmail: ' Reem@Example.org',
  );

  MainAdminAccountSnapshot allowed(MainAdminTransitionDecision decision) =>
      (decision as MainAdminTransitionAllowed).snapshot;

  MainAdminTransitionProblem refused(MainAdminTransitionDecision decision) =>
      (decision as MainAdminTransitionRefused).problem;

  group('states and invariants', () {
    test('account status wire values are the session AccountStatus values', () {
      for (final status in AccountStatus.values) {
        expect(MainAdminAccountStatus.parse(status.wire).wire, status.wire);
      }
      expect(MainAdminAccountStatus.parse('locked'),
          MainAdminAccountStatus.unknown);
      expect(MainAdminAccountStatus.parse('unknown'),
          MainAdminAccountStatus.unknown);
      expect(MainAdminSetupStatus.parse('delivered'),
          MainAdminSetupStatus.unknown);
      expect(MainAdminReplacementStatus.parse('approved'),
          MainAdminReplacementStatus.unknown);
    });

    test('login email and name are normalized; malformed email is refused', () {
      final a = account(MainAdminAccountStatus.active);
      expect(a.loginEmail, 'salma@hilal-medical.org');
      expect(normalizeMainAdminName('  ريم   القحطاني '), 'ريم القحطاني');
      expect(
        () => MainAdminAccount(
          accountId: 'ma_x',
          displayName: 'x',
          loginEmail: 'not-an-email',
          status: MainAdminAccountStatus.active,
          createdAt: now,
          activatedAt: now,
        ),
        throwsArgumentError,
      );
    });

    test('each seat state carries exactly its own metadata', () {
      MainAdminAccount build(
        MainAdminAccountStatus status, {
        bool withSetup = false,
        bool withActivation = false,
        bool withSuspension = false,
      }) =>
          MainAdminAccount(
            accountId: 'ma_x',
            displayName: 'x',
            loginEmail: 'x@example.org',
            status: status,
            createdAt: now,
            activatedAt: withActivation ? now : null,
            setup: withSetup ? setup() : null,
            suspension: withSuspension
                ? MainAdminSuspension(suspendedAt: now, reason: 'سبب')
                : null,
          );
      expect(() => build(MainAdminAccountStatus.pendingSetup),
          throwsArgumentError);
      expect(
        () => build(MainAdminAccountStatus.pendingSetup,
            withSetup: true, withActivation: true),
        throwsArgumentError,
      );
      expect(() => build(MainAdminAccountStatus.active), throwsArgumentError);
      expect(
        () => build(MainAdminAccountStatus.active,
            withActivation: true, withSuspension: true),
        throwsArgumentError,
      );
      expect(
          () => build(MainAdminAccountStatus.suspended, withActivation: true),
          throwsArgumentError);
      expect(
        build(MainAdminAccountStatus.suspended,
                withActivation: true, withSuspension: true)
            .status,
        MainAdminAccountStatus.suspended,
      );
    });

    test('the seat holder is never revoked and a deleted tenant has no seat',
        () {
      expect(
        () => MainAdminAccountSnapshot(
          tenant: tenant(),
          revision: 1,
          current: MainAdminAccount(
            accountId: 'ma_x',
            displayName: 'x',
            loginEmail: 'x@example.org',
            status: MainAdminAccountStatus.revoked,
            createdAt: now,
          ),
          readAt: now,
        ),
        throwsArgumentError,
      );
      expect(
        () => seat(MainAdminAccountStatus.active,
            tenantStatus: SaasTenantStatus.deleted),
        throwsArgumentError,
      );
      expect(MainAdminAccountStatus.revoked.holdsSeat, isFalse);
      expect(MainAdminAccountStatus.unknown.holdsSeat, isFalse);
    });

    test('a designate is always a different identity and account', () {
      expect(
        () => MainAdminAccountSnapshot(
          tenant: tenant(),
          revision: 1,
          current: account(MainAdminAccountStatus.active),
          replacement: MainAdminReplacement(
            id: 'mar_1',
            status: MainAdminReplacementStatus.pending,
            designate: MainAdminDesignate(
              accountId: 'ma_new',
              displayName: 'x',
              loginEmail: 'SALMA@hilal-medical.org',
              setup: setup(),
            ),
            requestedAt: now,
            reason: 'سبب',
          ),
          readAt: now,
        ),
        throwsArgumentError,
      );
    });

    test('JSON round-trips; malformed payloads are unreadable, not repaired',
        () {
      final original =
          seat(MainAdminAccountStatus.active, pendingReplacement: true);
      final parsed = MainAdminAccountSnapshot.fromJson(original.toJson());
      expect(parsed.toJson(), original.toJson());

      final revoked = original.toJson()
        ..['current'] = {
          ...(original.toJson()['current'] as Map<String, dynamic>),
          'status': 'revoked',
        };
      expect(() => MainAdminAccountSnapshot.fromJson(revoked),
          throwsFormatException);

      final noSuspension = seat(MainAdminAccountStatus.active).toJson()
        ..['current'] = {
          ...(seat(MainAdminAccountStatus.active).toJson()['current']
              as Map<String, dynamic>),
          'status': 'suspended',
        };
      expect(() => MainAdminAccountSnapshot.fromJson(noSuspension),
          throwsFormatException);

      final unknownLifecycle = original.toJson()
        ..['tenant'] = {
          ...(original.toJson()['tenant'] as Map<String, dynamic>),
          'lifecycleStatus': 'frozen',
        };
      expect(() => MainAdminAccountSnapshot.fromJson(unknownLifecycle),
          throwsFormatException);
    });

    test('unknown values are readable, flagged, and never actionable', () {
      final json = seat(MainAdminAccountStatus.active).toJson()
        ..['current'] = {
          ...(seat(MainAdminAccountStatus.active).toJson()['current']
              as Map<String, dynamic>),
          'status': 'locked_by_policy',
        };
      final parsed = MainAdminAccountSnapshot.fromJson(json);
      expect(parsed.current.status, MainAdminAccountStatus.unknown);
      expect(parsed.hasUnsupportedState, isTrue);
      expect(MainAdminPolicy.availableActions(parsed, now), isEmpty);
      expect(
        MainAdminManagementPolicy.evaluate(
          sessionRole: AuthRole.superAdmin,
          snapshot: parsed,
          freshness: MainAdminFreshness.confirmed,
          now: now,
        ).actions,
        isEmpty,
      );

      final unknownReplacement =
          seat(MainAdminAccountStatus.active, pendingReplacement: true)
              .toJson();
      (unknownReplacement['replacement'] as Map<String, dynamic>)['status'] =
          'approved';
      final withUnknown = MainAdminAccountSnapshot.fromJson(unknownReplacement);
      expect(withUnknown.hasUnsupportedState, isTrue);
      expect(MainAdminPolicy.availableActions(withUnknown, now), isEmpty);
    });

    test('setup expiry fails toward expired exactly at expiresAt', () {
      final s = setup(sentAt: now);
      final at = now.add(kProvisionalMainAdminSetupValidity);
      expect(s.effectiveStatusAt(at.subtract(const Duration(seconds: 1))),
          MainAdminSetupStatus.outstanding);
      expect(s.effectiveStatusAt(at), MainAdminSetupStatus.expired);
      expect(
        () => MainAdminSetupState(
          status: MainAdminSetupStatus.outstanding,
          lastSentAt: now,
          expiresAt: now,
        ),
        throwsArgumentError,
      );
    });

    test('reasons reuse the Point 9 normalization and 280 limit', () {
      expect(normalizeMainAdminReason('  سبب \n  إداري  '), 'سبب إداري');
      expect(isValidMainAdminReason(''), isFalse);
      expect(isValidMainAdminReason('x' * 280), isTrue);
      expect(isValidMainAdminReason('x' * 281), isFalse);
      expect(kMainAdminReasonMaxLength, 280);
    });
  });

  group('the closed action catalogue', () {
    test('six actions; none is a credential, MFA, session or bare revoke', () {
      expect(MainAdminAction.values.map((a) => a.wire), [
        'resend_setup',
        'suspend',
        'reactivate',
        'replace',
        'resend_replacement_setup',
        'cancel_replacement',
      ]);
      final forbidden = RegExp(
        r'password|mfa|otp|session|token|impersonat|email_edit|^revoke$',
      );
      for (final action in MainAdminAction.values) {
        expect(forbidden.hasMatch(action.wire), isFalse, reason: action.wire);
      }
      expect(
        MainAdminAction.values.where((a) => a.requiresReason).toSet(),
        {MainAdminAction.suspend, MainAdminAction.replace},
      );
    });

    test('only suspend, replace and cancel end sessions', () {
      expect(
        MainAdminMutationEffect.values.where((e) => e.endsSessions).toSet(),
        {
          MainAdminMutationEffect.suspended,
          MainAdminMutationEffect.replaced,
          MainAdminMutationEffect.replacementCancelled,
        },
      );
    });
  });

  group('seat state machine', () {
    test('actions available per account state on an active tenant', () {
      expect(
        MainAdminPolicy.availableActions(
            seat(MainAdminAccountStatus.pendingSetup), now),
        {MainAdminAction.resendSetup, MainAdminAction.replace},
      );
      expect(
        MainAdminPolicy.availableActions(
            seat(MainAdminAccountStatus.active), now),
        {MainAdminAction.suspend, MainAdminAction.replace},
      );
      expect(
        MainAdminPolicy.availableActions(
            seat(MainAdminAccountStatus.suspended), now),
        {MainAdminAction.reactivate, MainAdminAction.replace},
      );
      expect(
        MainAdminPolicy.availableActions(
          seat(MainAdminAccountStatus.active, pendingReplacement: true),
          now,
        ),
        {
          MainAdminAction.suspend,
          MainAdminAction.resendReplacementSetup,
          MainAdminAction.cancelReplacement,
        },
      );
    });

    test('suspend and reactivate are a reversible pair; each bumps revision',
        () {
      final active = seat(MainAdminAccountStatus.active);
      final suspended = allowed(MainAdminPolicy.suspend(
        snapshot: active,
        reason: '  اشتباه   في مشاركة الدخول ',
        now: now,
      ));
      expect(suspended.current.status, MainAdminAccountStatus.suspended);
      expect(suspended.current.suspension!.reason, 'اشتباه في مشاركة الدخول');
      expect(suspended.current.activatedAt, active.current.activatedAt);
      expect(suspended.revision, 6);

      final back =
          allowed(MainAdminPolicy.reactivate(snapshot: suspended, now: now));
      expect(back.current.status, MainAdminAccountStatus.active);
      expect(back.current.suspension, isNull);
      expect(back.revision, 7);

      expect(
        refused(
            MainAdminPolicy.suspend(snapshot: active, reason: ' ', now: now)),
        MainAdminTransitionProblem.invalidReason,
      );
      expect(
        refused(MainAdminPolicy.reactivate(snapshot: active, now: now)),
        MainAdminTransitionProblem.invalidTransition,
      );
      expect(
        refused(MainAdminPolicy.suspend(
          snapshot: seat(MainAdminAccountStatus.pendingSetup),
          reason: 'سبب',
          now: now,
        )),
        MainAdminTransitionProblem.invalidTransition,
      );
    });

    test('replacing a never-activated account takes effect immediately', () {
      final pending = seat(MainAdminAccountStatus.pendingSetup);
      expect(MainAdminPolicy.replacementMode(pending.current),
          MainAdminReplacementMode.immediate);
      final decision = MainAdminPolicy.replace(
        snapshot: pending,
        designate: identity,
        reason: 'البريد المسجّل خاطئ',
        designateAccountId: 'ma_new_1',
        replacementId: 'mar_new_1',
        now: now,
      ) as MainAdminTransitionAllowed;
      expect(decision.effect, MainAdminMutationEffect.replaced);
      expect(decision.revokedAccountId, 'ma_hilal');
      final next = decision.snapshot;
      expect(next.current.accountId, 'ma_new_1');
      expect(next.current.displayName, 'ريم القحطاني');
      expect(next.current.loginEmail, 'reem@example.org');
      expect(next.current.status, MainAdminAccountStatus.pendingSetup);
      expect(next.current.setup!.lastSentAt, now);
      expect(next.replacement, isNull);
    });

    test(
        'replacing an active account waits for the designate; never two '
        'usable Main Admins', () {
      final active = seat(MainAdminAccountStatus.active);
      final started = MainAdminPolicy.replace(
        snapshot: active,
        designate: identity,
        reason: 'تغيير المدير',
        designateAccountId: 'ma_new_1',
        replacementId: 'mar_new_1',
        now: now,
      ) as MainAdminTransitionAllowed;
      expect(started.effect, MainAdminMutationEffect.replacementStarted);
      final pending = started.snapshot;
      expect(pending.current.accountId, 'ma_hilal');
      expect(pending.current.status, MainAdminAccountStatus.active);
      expect(pending.replacement!.designate.setup.status,
          MainAdminSetupStatus.outstanding);

      final completed = MainAdminPolicy.completeReplacement(
        snapshot: pending,
        now: now.add(const Duration(hours: 2)),
      ) as MainAdminTransitionAllowed;
      expect(completed.effect, MainAdminMutationEffect.replaced);
      expect(completed.revokedAccountId, 'ma_hilal');
      expect(completed.snapshot.current.accountId, 'ma_new_1');
      expect(completed.snapshot.current.status, MainAdminAccountStatus.active);
      expect(completed.snapshot.replacement, isNull);

      expect(
        refused(MainAdminPolicy.replace(
          snapshot: pending,
          designate: const MainAdminDesignateIdentity(
            displayName: 'آخر',
            loginEmail: 'other@example.org',
          ),
          reason: 'سبب',
          designateAccountId: 'ma_new_2',
          replacementId: 'mar_new_2',
          now: now,
        )),
        MainAdminTransitionProblem.replacementAlreadyPending,
      );
    });

    test('replacement of a suspended account completes over the suspension',
        () {
      final suspended = seat(MainAdminAccountStatus.suspended);
      expect(MainAdminPolicy.replacementMode(suspended.current),
          MainAdminReplacementMode.onDesignateSetupCompletion);
      final pending = allowed(MainAdminPolicy.replace(
        snapshot: suspended,
        designate: identity,
        reason: 'سبب',
        designateAccountId: 'ma_new_1',
        replacementId: 'mar_new_1',
        now: now,
      ));
      final done = allowed(
          MainAdminPolicy.completeReplacement(snapshot: pending, now: now));
      expect(done.current.status, MainAdminAccountStatus.active);
      expect(done.current.suspension, isNull);
    });

    test('the designate must be well formed and a different login', () {
      final active = seat(MainAdminAccountStatus.active);
      for (final bad in const [
        MainAdminDesignateIdentity(displayName: '', loginEmail: 'a@b.org'),
        MainAdminDesignateIdentity(displayName: 'x', loginEmail: 'nope'),
        MainAdminDesignateIdentity(
            displayName: 'x', loginEmail: ' SALMA@hilal-medical.org'),
      ]) {
        expect(
          refused(MainAdminPolicy.replace(
            snapshot: active,
            designate: bad,
            reason: 'سبب',
            designateAccountId: 'ma_new_1',
            replacementId: 'mar_new_1',
            now: now,
          )),
          MainAdminTransitionProblem.invalidIdentity,
        );
      }
    });

    test('cancel discards the designate; resend refreshes the invitation', () {
      final pending =
          seat(MainAdminAccountStatus.active, pendingReplacement: true);
      final cancelled = allowed(
          MainAdminPolicy.cancelReplacement(snapshot: pending, now: now));
      expect(cancelled.replacement, isNull);
      expect(cancelled.current.toJson(), pending.current.toJson());

      final later = now.add(const Duration(days: 10));
      expect(pending.replacement!.designate.setup.effectiveStatusAt(later),
          MainAdminSetupStatus.expired);
      expect(
        refused(
            MainAdminPolicy.completeReplacement(snapshot: pending, now: later)),
        MainAdminTransitionProblem.invalidTransition,
      );
      final resent = allowed(MainAdminPolicy.resendReplacementSetup(
          snapshot: pending, now: later));
      expect(resent.replacement!.designate.setup.lastSentAt, later);
      expect(resent.replacement!.designate.setup.effectiveStatusAt(later),
          MainAdminSetupStatus.outstanding);
      expect(resent.replacement!.id, pending.replacement!.id);

      final setupPending = seat(MainAdminAccountStatus.pendingSetup);
      final resentCurrent = allowed(
          MainAdminPolicy.resendSetup(snapshot: setupPending, now: later));
      expect(resentCurrent.current.setup!.lastSentAt, later);
      expect(resentCurrent.revision, setupPending.revision + 1);
    });

    test('setup completion is a backend event gated by an outstanding invite',
        () {
      final pending = seat(MainAdminAccountStatus.pendingSetup);
      final done = MainAdminPolicy.completeSetup(snapshot: pending, now: now)
          as MainAdminTransitionAllowed;
      expect(done.effect, MainAdminMutationEffect.setupCompleted);
      expect(done.snapshot.current.status, MainAdminAccountStatus.active);
      expect(done.snapshot.current.activatedAt, now);
      expect(
        refused(MainAdminPolicy.completeSetup(
          snapshot: pending,
          now: now.add(const Duration(days: 30)),
        )),
        MainAdminTransitionProblem.invalidTransition,
      );
    });
  });

  group('tenant lifecycle interaction', () {
    test('matrix: deleted nothing; blocked tenants reducing actions only', () {
      for (final action in MainAdminAction.values) {
        expect(MainAdminPolicy.tenantGate(action, SaasTenantStatus.active),
            isNull);
        expect(MainAdminPolicy.tenantGate(action, SaasTenantStatus.deleted),
            MainAdminTransitionProblem.tenantDeleted);
        for (final blocked in const [
          SaasTenantStatus.suspended,
          SaasTenantStatus.deletionPending,
        ]) {
          expect(
            MainAdminPolicy.tenantGate(action, blocked),
            action.opensAccessPath
                ? MainAdminTransitionProblem.tenantNotEligible
                : null,
            reason: '${action.wire} on ${blocked.wire}',
          );
        }
      }
      expect(
        MainAdminAction.values.where((a) => !a.opensAccessPath).toSet(),
        {MainAdminAction.suspend, MainAdminAction.cancelReplacement},
      );
    });

    test('reactivation never bypasses a tenant suspension', () {
      final suspendedTenant = seat(MainAdminAccountStatus.suspended,
          tenantStatus: SaasTenantStatus.suspended);
      expect(
        refused(
            MainAdminPolicy.reactivate(snapshot: suspendedTenant, now: now)),
        MainAdminTransitionProblem.tenantNotEligible,
      );
      expect(
        MainAdminPolicy.availableActions(suspendedTenant, now),
        isEmpty,
      );
      final activeOnSuspendedTenant = seat(MainAdminAccountStatus.active,
          tenantStatus: SaasTenantStatus.suspended, pendingReplacement: true);
      expect(
        MainAdminPolicy.availableActions(activeOnSuspendedTenant, now),
        {MainAdminAction.suspend, MainAdminAction.cancelReplacement},
      );
    });

    test('no seat can complete a handover while the tenant is blocked', () {
      for (final blocked in const [
        SaasTenantStatus.suspended,
        SaasTenantStatus.deletionPending,
      ]) {
        expect(
          refused(MainAdminPolicy.completeReplacement(
            snapshot: seat(MainAdminAccountStatus.active,
                tenantStatus: blocked, pendingReplacement: true),
            now: now,
          )),
          MainAdminTransitionProblem.tenantNotEligible,
        );
        expect(
          refused(MainAdminPolicy.completeSetup(
            snapshot: seat(MainAdminAccountStatus.pendingSetup,
                tenantStatus: blocked),
            now: now,
          )),
          MainAdminTransitionProblem.tenantNotEligible,
        );
      }
    });

    test('account transitions never touch the tenant reference', () {
      final active = seat(MainAdminAccountStatus.active);
      final suspended = allowed(
          MainAdminPolicy.suspend(snapshot: active, reason: 'سبب', now: now));
      expect(suspended.tenant.toJson(), active.tenant.toJson());
    });
  });

  group('management view', () {
    test('super admin + confirmed read is the only actionable combination', () {
      final s = seat(MainAdminAccountStatus.active);
      for (final role in AuthRole.values) {
        for (final freshness in MainAdminFreshness.values) {
          final view = MainAdminManagementPolicy.evaluate(
            sessionRole: role,
            snapshot: s,
            freshness: freshness,
            now: now,
          );
          final expected = role == AuthRole.superAdmin &&
              freshness == MainAdminFreshness.confirmed;
          expect(view.actions.isNotEmpty, expected,
              reason: '${role.wire} ${freshness.name}');
          expect(view.isReadOnly, freshness != MainAdminFreshness.confirmed);
        }
      }
      expect(
        MainAdminManagementPolicy.evaluate(
          sessionRole: null,
          snapshot: s,
          freshness: MainAdminFreshness.confirmed,
          now: now,
        ).actions,
        isEmpty,
      );
    });

    test('says when the tenant, not the account, withholds actions', () {
      final view = MainAdminManagementPolicy.evaluate(
        sessionRole: AuthRole.superAdmin,
        snapshot: seat(MainAdminAccountStatus.suspended,
            tenantStatus: SaasTenantStatus.deletionPending),
        freshness: MainAdminFreshness.confirmed,
        now: now,
      );
      expect(view.tenantBlocksAccessPaths, isTrue);
      expect(view.can(MainAdminAction.reactivate), isFalse);
      expect(view.replacementMode,
          MainAdminReplacementMode.onDesignateSetupCompletion);
    });
  });
}
