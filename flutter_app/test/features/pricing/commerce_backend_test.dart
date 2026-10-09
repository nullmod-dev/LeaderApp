import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/network/api_client.dart';
import 'package:mtm/core/network/token_vault.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/storage/secure_store.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/secure_auth_state_store.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/pricing/data/commerce_backend.dart';
import 'package:mtm/features/pricing/data/commerce_control_plane.dart';
import 'package:mtm/features/pricing/data/pricing_providers.dart';
import 'package:mtm/features/pricing/domain/billing_option.dart';
import 'package:mtm/features/pricing/domain/money.dart';
import 'package:mtm/features/pricing/domain/promotion.dart';

/// Commerce against the server: the HTTP adapter's wire, and the control
/// plane as a cache of what the server answered.
http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

const _offerJson = {
  'id': 'offer_1',
  'enabled': true,
  'live': true,
  'target': 'monthly',
  'discount': {
    'kind': 'fixed_final_price',
    'finalPrice': {'amount': 200, 'currency': 'USD'},
  },
  'title': 'جرّب أول شهر',
  'endsAt': null,
  'createdAt': '2026-10-01T00:00:00.000Z',
};

const _couponJson = {
  'id': 'coupon_1',
  'code': 'TEAM20',
  'enabled': false,
  'target': 'three_months',
  'discount': {'kind': 'percentage', 'percent': 20},
  'assignment': {'kind': 'account', 'accountId': 'acc_9'},
  'note': 'internal',
  'expiresAt': '2026-12-31T00:00:00.000Z',
  'createdAt': '2026-10-02T00:00:00.000Z',
};

const _superAdmin = AuthUser(
  id: 'sa_1',
  name: 'Super Admin',
  email: 'sa@leader.test',
  role: AuthRole.superAdmin,
  saasTenantId: null,
  capabilities: Capabilities.none,
  orgName: 'Leader',
);

const _mainAdmin = AuthUser(
  id: 'ma_1',
  name: 'مشرف',
  email: 'ma@leader.test',
  role: AuthRole.mainAdmin,
  saasTenantId: 't_1',
  capabilities: Capabilities(global: Cap.all),
  orgName: 'فريق',
);

const _actor = CommerceActor(accountId: 'sa_1', displayName: 'Super Admin');

void main() {
  late List<http.Request> sent;
  late http.Response Function(http.Request) server;

  HttpCommerceBackend backend() => HttpCommerceBackend(ApiClient(
        vault: TokenVault(SecureAuthStateStore(InMemorySecureStore())),
        origin: 'http://leader.test',
        client: MockClient((request) async {
          sent.add(request);
          return server(request);
        }),
      ));

  setUp(() {
    sent = [];
    server = (_) => _json(404, {
          'error': {'code': 'not_found'}
        });
  });

  group('the HTTP adapter', () {
    test('reads every offer and coupon for the control plane', () async {
      server = (r) => r.url.path.endsWith('/offers')
          ? _json(200, [_offerJson])
          : _json(200, [_couponJson]);
      final state = (await backend().loadPlatform() as Success).data
          as CommerceState;

      final offer = state.offers.single;
      expect(offer.target, BillingOptionId.monthly);
      expect(offer.discount, const FixedFinalPriceDiscount(Money.cents(200)));
      expect(offer.enabled, isTrue);
      final coupon = state.coupons.single;
      expect(coupon.code, 'TEAM20');
      expect(coupon.discount, const PercentageDiscount(20));
      expect((coupon.assignment as CouponAssignmentAccount).accountId, 'acc_9');
      expect(coupon.expiresAt, DateTime.utc(2026, 12, 31));
    });

    test('sends a new offer the way the server validates it', () async {
      server = (_) => _json(201, _offerJson);
      await backend().createOffer(
        target: BillingOptionId.monthly,
        discount: const FixedFinalPriceDiscount(Money.cents(200)),
        enabled: true,
        title: '  جرّب  ',
      );
      final request = sent.single;
      expect(request.method, 'POST');
      expect(request.url.path, endsWith('/platform/commerce/offers'));
      expect(request.headers['Idempotency-Key'], isNotEmpty);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['target'], 'monthly');
      expect(body['discount'], {
        'kind': 'fixed_final_price',
        'finalPrice': {'amount': 200, 'currency': 'USD'},
      });
      expect(body['title'], 'جرّب');
      expect(body['enabled'], isTrue);
    });

    test('an operator may type an email for a targeted coupon', () async {
      server = (_) => _json(201, _couponJson);
      await backend().createCoupon(
        code: 'TEAM20',
        target: BillingOptionId.threeMonths,
        discount: const PercentageDiscount(20),
        assignment: const CouponAssignmentAccount('ali@leader.test'),
        enabled: false,
      );
      final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
      expect(body['assignment'], {'kind': 'account', 'email': 'ali@leader.test'});
    });

    test('enable and disable are their own commands', () async {
      server = (_) => _json(200, _offerJson);
      await backend().setOfferEnabled('offer_1', false);
      expect(sent.single.url.path, endsWith('/offers/offer_1/disable'));
    });

    test('a coupon is judged by the server', () async {
      server = (_) => _json(200, {
            'valid': true,
            'coupon': {'code': 'TEAM20', 'target': 'three_months'},
            'quote': {
              'billingOptionId': 'three_months',
              'basePrice': {'amount': 1400, 'currency': 'USD'},
              'finalPrice': {'amount': 1120, 'currency': 'USD'},
            },
            'couponOutcome': 'applied',
            'appliesToSelected': true,
          });
      final resolution = (await backend()
              .validateCoupon(' team20 ', BillingOptionId.threeMonths) as Success)
          .data;
      final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
      expect(body, {'code': ' team20 ', 'billingOptionId': 'three_months'});
      expect(resolution.target, BillingOptionId.threeMonths);
      expect(resolution.basePrice, const Money.cents(1400));
      expect(resolution.finalPrice, const Money.cents(1120));
      expect(resolution.coupon.code, 'TEAM20');
    });

    test("a refused code keeps the server's reason", () async {
      server = (_) => _json(422, {
            'error': {'code': 'coupon_expired', 'message': 'expired'}
          });
      final result =
          await backend().validateCoupon('OLD', BillingOptionId.monthly);
      expect((result as Failure).code, 'coupon_expired');
    });
  });

  group('the control plane over a backend', () {
    ProviderContainer over(AuthUser user) {
      final c = ProviderContainer(overrides: [
        currentUserProvider.overrideWith((ref) async => user),
        commerceBackendProvider.overrideWith((ref) => backend()),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<void> settle(ProviderContainer c) async {
      await c.read(currentUserProvider.future);
      c.read(commerceControlPlaneProvider);
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('a Super Admin loads every offer and coupon from the server',
        () async {
      server = (r) => r.url.path.endsWith('/offers')
          ? _json(200, [_offerJson])
          : _json(200, [_couponJson]);
      final c = over(_superAdmin);
      expect(c.read(commerceControlPlaneProvider).phase,
          anyOf(CommercePhase.loading, CommercePhase.ready));
      await settle(c);
      final state = c.read(commerceControlPlaneProvider);
      expect(state.phase, CommercePhase.ready);
      expect(state.offers.single.id, 'offer_1');
      expect(state.coupons.single.id, 'coupon_1');
    });

    test('everyone else sees the live offers and no coupon list', () async {
      server = (r) {
        expect(r.url.path, endsWith('/pricing/offers/active'));
        return _json(200, [
          {
            'id': 'offer_1',
            'target': 'monthly',
            'discount': {'kind': 'percentage', 'percent': 10},
            'title': null,
            'endsAt': null,
          }
        ]);
      };
      final c = over(_mainAdmin);
      await settle(c);
      expect(c.read(liveGlobalOffersProvider).keys, [BillingOptionId.monthly]);
      expect(c.read(commerceControlPlaneProvider).coupons, isEmpty);
    });

    test('a change is made on the server and applied from its reply',
        () async {
      server = (r) => r.method == 'GET'
          ? _json(200, <Object>[])
          : _json(201, _offerJson);
      final c = over(_superAdmin);
      await settle(c);
      final plane = c.read(commerceControlPlaneProvider.notifier);
      final created = await plane.createOffer(
        target: BillingOptionId.monthly,
        discount: const FixedFinalPriceDiscount(Money.cents(200)),
        enabled: true,
        actor: _actor,
      );
      expect(created, isA<Success<GlobalOffer>>());
      expect(c.read(commerceControlPlaneProvider).offers.single.id, 'offer_1');

      server = (_) => _json(409, {
            'error': {'code': 'offer_conflict'}
          });
      final refused = await plane.setOfferEnabled('offer_1', true, actor: _actor);
      expect((refused as Failure).code, 'offer_conflict');
      expect(c.read(commerceControlPlaneProvider).offers, hasLength(1),
          reason: 'a refusal changes nothing here');

      server = (_) => http.Response('', 204);
      expect(await plane.removeOffer('offer_1', actor: _actor),
          isA<Success<GlobalOffer>>());
      expect(c.read(commerceControlPlaneProvider).offers, isEmpty);
    });

    test('no actor, no request', () async {
      server = (_) => _json(200, <Object>[]);
      final c = over(_superAdmin);
      await settle(c);
      sent.clear();
      final result = await c
          .read(commerceControlPlaneProvider.notifier)
          .createOffer(
            target: BillingOptionId.monthly,
            discount: const PercentageDiscount(10),
          );
      expect((result as Failure).code, CommerceCodes.notAuthorized);
      expect(sent, isEmpty);
    });

    test('a failed read says so and can be retried', () async {
      server = (_) => _json(503, {
            'error': {'code': 'server'}
          });
      final c = over(_superAdmin);
      await settle(c);
      expect(c.read(commerceControlPlaneProvider).phase, CommercePhase.failed);

      server = (r) => _json(200, <Object>[]);
      await c.read(commerceControlPlaneProvider.notifier).reload();
      expect(c.read(commerceControlPlaneProvider).phase, CommercePhase.ready);
    });

    test('the coupon field asks the server', () async {
      server = (r) => r.url.path.endsWith('/validate')
          ? _json(422, {
              'error': {'code': 'coupon_not_assigned'}
            })
          : _json(200, <Object>[]);
      final c = over(_mainAdmin);
      await settle(c);
      final entry = c.read(couponEntryProvider.notifier)..setInput('TEAM20');
      await entry.validate();
      final last = c.read(couponEntryProvider).last;
      expect((last as Failure).code, 'coupon_not_assigned');
      expect(sent.last.url.path, endsWith('/pricing/coupons/validate'));
    });
  });
}
