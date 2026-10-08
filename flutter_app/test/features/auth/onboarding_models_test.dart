import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/onboarding_models.dart';
import 'package:mtm/features/auth/domain/onboarding_repository.dart';
import 'package:mtm/features/auth/domain/session_access.dart';
import 'package:mtm/features/platform/domain/platform_main_admin_models.dart';
import 'package:mtm/features/platform/domain/team_code.dart';

/// Point 17A — the typed onboarding models: normalization, fail-closed
/// parsing, and the rule that no secret survives into a string.
void main() {
  final now = DateTime.utc(2026, 9, 12, 9);

  group('login email', () {
    test('normalizes exactly like the Platform-provisioned address', () {
      // The invitation match compares these two; they must never drift.
      for (final raw in [
        '  Huda@Nabd-Team.org ',
        'REEM@najd-response.sa',
        'a.b+tag@x.io',
      ]) {
        expect(normalizeLoginEmail(raw), normalizeMainAdminEmail(raw));
      }
      expect(normalizeLoginEmail(' Huda@Nabd-Team.ORG '), 'huda@nabd-team.org');
    });

    test('shape only — permissive, and refuses what is certainly not one', () {
      expect(validateLoginEmail('a.b+tag@x.io'), isNull);
      expect(validateLoginEmail(''), LoginEmailError.empty);
      expect(validateLoginEmail('no-at-sign'), LoginEmailError.malformed);
      expect(validateLoginEmail('a b@x.io'), LoginEmailError.malformed);
      expect(validateLoginEmail('${'a' * 250}@x.io'), LoginEmailError.tooLong);
    });
  });

  test('password input: a courtesy floor, never trimmed', () {
    expect(checkPasswordInput(''), PasswordInputError.empty);
    expect(
        checkPasswordInput('short'), PasswordInputError.belowAdvisoryMinimum);
    expect(checkPasswordInput('        '), isNull,
        reason: 'spaces are password characters');
    expect(checkPasswordInput('long enough'), isNull);
  });

  group('verification code', () {
    test('folds Arabic-Indic and Persian digits, strips spaces and hyphens',
        () {
      expect(normalizeVerificationCode('٢٤٦ ٨١٠'), '246810');
      expect(normalizeVerificationCode('۲۴۶-۸۱۰'), '246810');
      expect(validateVerificationCode('٢٤٦٨١٠'), isNull);
    });

    test('numeric and exactly the challenge length', () {
      expect(validateVerificationCode(''), VerificationCodeError.empty);
      expect(
          validateVerificationCode('12345'), VerificationCodeError.malformed);
      expect(
          validateVerificationCode('12345a'), VerificationCodeError.malformed);
      expect(validateVerificationCode('12345678', length: 8), isNull);
    });
  });

  group('Team Code input', () {
    test('canonicalizes what a person types, including Arabic digits', () {
      for (final raw in [
        'MTM-5JQX-2TWD',
        'mtm 5jqx 2twd',
        'mtm5jqx2twd',
        '5JQX2TWD',
        '5jqx-2twd',
      ]) {
        expect(normalizeTeamCodeInput(raw), 'MTM-5JQX-2TWD', reason: raw);
      }
      expect(normalizeTeamCodeInput('MTM-٥JQX-٢TWD'), 'MTM-5JQX-2TWD');
      expect(validateTeamCodeInput('mtm ٥jqx ٢twd'), isNull);
    });

    test('format only: empty and malformed are refused locally', () {
      expect(validateTeamCodeInput('  '), TeamCodeError.empty);
      expect(validateTeamCodeInput('MTM-5JQX'), TeamCodeError.malformed);
      // `0`, `O`, `1`, `I` are outside the alphabet.
      expect(validateTeamCodeInput('MTM-0OI1-2TWD'), TeamCodeError.malformed);
      expect(validateTeamCodeInput('ABC-5JQX-2TWD'), TeamCodeError.malformed);
    });
  });

  test('display name: collapsed, 1–80, not identity', () {
    expect(normalizeDisplayName('  هدى   الشمري '), 'هدى الشمري');
    expect(validateDisplayName('   '), DisplayNameError.empty);
    expect(validateDisplayName('ا' * 81), DisplayNameError.tooLong);
    expect(validateDisplayName('ا' * 80), isNull);
  });

  group('VerificationChallenge', () {
    Map<String, dynamic> wire() => {
          'challengeId': 'vc_secret_handle',
          'maskedEmail': 'h***@nabd-team.org',
          'codeLength': 6,
          'expiresAt': '2026-09-12T09:10:00Z',
          'resendAvailableAt': '2026-09-12T12:01:00+03:00',
          'attemptsRemaining': 5,
        };

    test('parses, normalizes instants to UTC, and round-trips', () {
      final c = VerificationChallenge.fromJson(wire());
      expect(c.resendAvailableAt, DateTime.utc(2026, 9, 12, 9, 1));
      expect(VerificationChallenge.fromJson(c.toJson()), c);
    });

    test('cooldown and expiry are server instants read with a clock', () {
      final c = VerificationChallenge.fromJson(wire());
      expect(c.resendCooldownAt(now), const Duration(minutes: 1));
      expect(c.canResendAt(now), isFalse);
      expect(c.canResendAt(now.add(const Duration(minutes: 1))), isTrue);
      expect(c.isExpiredAt(DateTime.utc(2026, 9, 12, 9, 10)), isTrue,
          reason: 'expired at the instant itself');
      expect(c.isExpiredAt(now), isFalse);
    });

    test('fails closed on a missing handle, a local timestamp, a bad length',
        () {
      for (final broken in [
        {...wire()}..remove('challengeId'),
        {...wire(), 'maskedEmail': ''},
        {...wire(), 'expiresAt': '2026-09-12T09:10:00'},
        {...wire(), 'codeLength': 2},
        {...wire(), 'attemptsRemaining': -1},
      ]) {
        expect(
            () => VerificationChallenge.fromJson(broken), throwsFormatException,
            reason: '$broken');
      }
    });

    test('never prints its handle', () {
      final c = VerificationChallenge.fromJson(wire());
      expect(c.toString(), isNot(contains('vc_secret_handle')));
      expect(EntryVerificationPending(c).toString(),
          isNot(contains('vc_secret_handle')));
    });

    test('purpose: sign_in is a returning sign-in; absent or unknown is email',
        () {
      final signIn =
          VerificationChallenge.fromJson({...wire(), 'purpose': 'sign_in'});
      expect(signIn.purpose, VerificationPurpose.signIn);
      expect(VerificationChallenge.fromJson(signIn.toJson()), signIn,
          reason: 'the secure-storage record keeps the purpose');
      expect(signIn.copyWith(attemptsRemaining: 1).purpose,
          VerificationPurpose.signIn);

      final email = VerificationChallenge.fromJson(wire());
      expect(email.purpose, VerificationPurpose.emailOwnership);
      expect(email.toJson().containsKey('purpose'), isFalse);
      expect(
          VerificationChallenge.fromJson({...wire(), 'purpose': 'later'})
              .purpose,
          VerificationPurpose.emailOwnership);
      expect(signIn == email, isFalse);
    });
  });

  test('a Google assertion never prints its token', () {
    const a = GoogleIdentityAssertion('eyJhbGciOi.secret.token');
    expect(a.toString(), isNot(contains('secret')));
  });

  group('OnboardingSnapshot', () {
    Map<String, dynamic> linked() => {
          'accountId': 'ma_nabd',
          'email': 'Huda@Nabd-Team.org',
          'methods': ['password', 'apple'],
          'accountStatus': 'pending_setup',
          'linkStatus': 'linked',
          'setupStatus': 'required',
          'tenant': {
            'displayName': 'فريق نبض التطوعي',
            'role': 'main_admin',
            'tenantStatus': 'active',
          },
          'displayNameSuggestion': '  هدى  الشمري ',
          'authorizationExpiresAt': '2026-09-15T09:00:00Z',
        };

    test('parses a linked Main Admin designate', () {
      final s = OnboardingSnapshot.fromJson(linked());
      expect(s.email, 'huda@nabd-team.org');
      expect(s.methods, {AuthMethod.password},
          reason: 'an unknown method is metadata and is dropped, not fatal');
      expect(s.account, AccountStatus.pendingSetup);
      expect(s.link, TenantLinkStatus.linked);
      expect(s.tenant!.role, AuthRole.mainAdmin);
      expect(s.tenant!.status, SaasTenantStatus.active);
      expect(s.displayNameSuggestion, 'هدى الشمري');
      expect(s.hasUnsupportedState, isFalse);
      expect(s.isComplete, isFalse);
      expect(OnboardingSnapshot.fromJson(s.toJson()), s);
    });

    test('an unknown value in a gating field fails closed, and round-trips raw',
        () {
      for (final (key, raw, field) in [
        ('accountStatus', 'locked', OnboardingField.accountStatus),
        ('linkStatus', 'pending_review', OnboardingField.linkStatus),
        ('setupStatus', 'partial', OnboardingField.setupStatus),
      ]) {
        final s = OnboardingSnapshot.fromJson({...linked(), key: raw});
        expect(s.hasUnsupportedState, isTrue, reason: key);
        expect(s.unsupported[field], raw);
        expect(s.toJson()[key], raw, reason: 'never laundered to a default');
      }
      final role = OnboardingSnapshot.fromJson({
        ...linked(),
        'tenant': const {
          'displayName': 'x',
          'role': 'owner',
          'tenantStatus': 'active',
        },
      });
      expect(role.unsupported[OnboardingField.role], 'owner');
      final tenantStatus = OnboardingSnapshot.fromJson({
        ...linked(),
        'tenant': const {
          'displayName': 'x',
          'role': 'admin',
          'tenantStatus': 'frozen',
        },
      });
      expect(tenantStatus.unsupported[OnboardingField.tenantStatus], 'frozen');
    });

    test('a structural contradiction is invalid, not unfamiliar', () {
      for (final broken in [
        {...linked()}..remove('accountId'),
        {...linked()}..remove('linkStatus'),
        {...linked()}..remove('tenant'),
        {...linked(), 'linkStatus': 'unlinked'},
        {
          ...linked(),
          'linkStatus': 'unlinked',
          'setupStatus': 'completed',
        }..remove('tenant'),
        {
          ...linked(),
          'tenant': {
            'displayName': 'x',
            'role': 'super_admin',
            'tenantStatus': 'active',
          },
        },
      ]) {
        expect(() => OnboardingSnapshot.fromJson(broken), throwsFormatException,
            reason: '$broken');
      }
    });

    test('reads a pending Main Admin seat on an unlinked snapshot', () {
      final unlinked = {
        ...linked(),
        'linkStatus': 'unlinked',
        'tenant': null,
        'pendingInvitation': {
          'role': 'main_admin',
          'tenantDisplayName': 'فريق نبض التطوعي',
        },
      };
      final s = OnboardingSnapshot.fromJson(unlinked);
      expect(
          s.pendingInvitation,
          const PendingInvitation(
              tenantDisplayName: 'فريق نبض التطوعي',
              role: AuthRole.mainAdmin));
      expect(OnboardingSnapshot.fromJson(s.toJson()), s,
          reason: 'it survives the secure-storage round trip');
      expect(s.hasUnsupportedState, isFalse);
    });

    test('a pending invitation it cannot read is dropped, never fatal', () {
      for (final raw in <Object?>[
        'main_admin',
        {'role': 'main_admin'},
        {'role': 'super_admin', 'tenantDisplayName': 'x'},
        {'role': 7, 'tenantDisplayName': 'x'},
        {'role': 'owner', 'tenantDisplayName': 'x'},
        {'role': 'main_admin', 'tenantDisplayName': '  '},
      ]) {
        final s = OnboardingSnapshot.fromJson({
          ...linked(),
          'linkStatus': 'unlinked',
          'tenant': null,
          'pendingInvitation': raw,
        });
        expect(s.pendingInvitation, isNull, reason: '$raw');
        expect(s.hasUnsupportedState, isFalse, reason: '$raw');
      }
    });

    test('carries no tenant id, Team Code or operational datum', () {
      final json = OnboardingSnapshot.fromJson(linked()).toJson();
      final text = json.toString();
      expect(text, isNot(contains('saas_')));
      expect(text, isNot(contains('MTM-')));
      expect((json['tenant'] as Map).keys,
          unorderedEquals(['displayName', 'role', 'tenantStatus']));
    });
  });

  group('error taxonomy', () {
    test('every onboarding code maps to a category; unknown is generic', () {
      for (final code in OnboardingProblemCode.values) {
        final kind = onboardingErrorKindOf(OnboardingFailure<void>(code));
        expect(kind, isNotNull, reason: code.wire);
      }
      expect(onboardingErrorKindOf(const Failure<void>('', code: 'brand_new')),
          OnboardingErrorKind.unknown);
      expect(onboardingErrorKindOf(const Offline<void>()),
          OnboardingErrorKind.offline);
      expect(onboardingErrorKindOf(const Success<void>(null)), isNull);
    });

    test('the wire code reaches every existing Result consumer', () {
      const r = OnboardingFailure<void>(OnboardingProblemCode.teamLinkRefused);
      expect(
          r.when(
            success: (_, {stale = false}) => null,
            failure: (_, code) => code,
            offline: (_) => null,
          ),
          'team_link_refused');
    });

    test('there is no "account exists" code for a client to render', () {
      expect(
        OnboardingProblemCode.values.map((c) => c.wire),
        isNot(anyElement(anyOf(contains('exists'), contains('taken')))),
      );
    });
  });
}
