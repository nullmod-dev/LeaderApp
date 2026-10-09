/// The server side of commerce (Point 19): global offers and coupons kept on
/// the backend, and coupon validation done there.
///
/// `null` in every build without a backend — [CommerceControlPlane] then
/// keeps its development state in memory, as it always has. A backend build
/// overrides [commerceBackendProvider] with [HttpCommerceBackend], and the
/// control plane becomes a cache of what the server answered.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/billing_option.dart';
import '../domain/coupon_validation.dart';
import '../domain/money.dart';
import '../domain/promotion.dart';
import 'commerce_control_plane.dart';

abstract class CommerceBackend {
  /// Every offer and coupon (Super Admin): `/platform/commerce`.
  Future<Result<CommerceState>> loadPlatform();

  /// The offers live right now, as every customer sees them:
  /// `GET /pricing/offers/active`.
  Future<Result<List<GlobalOffer>>> loadActiveOffers();

  Future<Result<GlobalOffer>> createOffer({
    required BillingOptionId target,
    required Discount discount,
    required bool enabled,
    String? title,
    DateTime? endsAt,
  });

  Future<Result<GlobalOffer>> updateOffer(
    String id, {
    required BillingOptionId target,
    required Discount discount,
    required bool enabled,
    String? title,
    DateTime? endsAt,
  });

  Future<Result<GlobalOffer>> setOfferEnabled(String id, bool enabled);

  Future<Result<void>> removeOffer(String id);

  Future<Result<Coupon>> createCoupon({
    required String code,
    required BillingOptionId target,
    required Discount discount,
    required CouponAssignment assignment,
    required bool enabled,
    String? note,
    DateTime? expiresAt,
  });

  Future<Result<Coupon>> updateCoupon(
    String id, {
    required String code,
    required BillingOptionId target,
    required Discount discount,
    required CouponAssignment assignment,
    required bool enabled,
    String? note,
    DateTime? expiresAt,
  });

  Future<Result<Coupon>> setCouponEnabled(String id, bool enabled);

  Future<Result<void>> removeCoupon(String id);

  /// `POST /pricing/coupons/validate` — the signed-in account's code, judged
  /// by the server (assignment, expiry, uses, price sanity).
  Future<Result<CouponResolution>> validateCoupon(
    String code,
    BillingOptionId selected,
  );
}

/// Overridden by `backendOverrides`; `null` keeps commerce local.
final commerceBackendProvider = Provider<CommerceBackend?>((ref) => null);

class HttpCommerceBackend implements CommerceBackend {
  HttpCommerceBackend(this._api);

  final ApiClient _api;

  static const _offers = '/platform/commerce/offers';
  static const _coupons = '/platform/commerce/coupons';

  static String _one(String base, String id) =>
      '$base/${Uri.encodeComponent(id)}';

  // ---- wire ↔ model --------------------------------------------------------

  static Map<String, dynamic> _discountJson(Discount d) => switch (d) {
        PercentageDiscount(:final percent) => {
            'kind': 'percentage',
            'percent': percent,
          },
        FixedFinalPriceDiscount(:final finalPrice) => {
            'kind': 'fixed_final_price',
            'finalPrice': {'amount': finalPrice.cents, 'currency': 'USD'},
          },
      };

  static Discount _discount(Map<String, dynamic> j) => j['kind'] == 'percentage'
      ? PercentageDiscount((j['percent'] as num).toInt())
      : FixedFinalPriceDiscount(_money(j['finalPrice']));

  static Money _money(Object? raw) =>
      Money.cents(((raw as Map<String, dynamic>)['amount'] as num).toInt());

  static DateTime? _date(Object? raw) =>
      raw is String ? DateTime.parse(raw).toUtc() : null;

  static BillingOptionId _option(Object? raw) =>
      BillingOptionId.tryParse(raw as String? ?? '') ??
      (throw FormatException('unknown billing option', raw));

  static GlobalOffer _offer(Map<String, dynamic> j) => GlobalOffer(
        id: j['id'] as String,
        // An active-offer row carries no flag: being listed is being live.
        enabled: (j['enabled'] as bool?) ?? true,
        target: _option(j['target']),
        discount: _discount(j['discount'] as Map<String, dynamic>),
        createdAt: _date(j['createdAt']) ?? DateTime.utc(1970),
        title: j['title'] as String?,
        endsAt: _date(j['endsAt']),
      );

  static Coupon _coupon(Map<String, dynamic> j) {
    final assignment = (j['assignment'] as Map<String, dynamic>?) ?? const {};
    return Coupon(
      id: j['id'] as String,
      code: j['code'] as String,
      enabled: (j['enabled'] as bool?) ?? false,
      target: _option(j['target']),
      discount: _discount(j['discount'] as Map<String, dynamic>),
      assignment: assignment['kind'] == 'account'
          ? CouponAssignmentAccount(assignment['accountId'] as String? ?? '')
          : const CouponAssignmentPublic(),
      createdAt: _date(j['createdAt']) ?? DateTime.utc(1970),
      note: j['note'] as String?,
      expiresAt: _date(j['expiresAt']),
    );
  }

  /// An operator may type an email or an account id; the server resolves an
  /// email to the account and stores only the id.
  static Map<String, dynamic> _assignmentJson(CouponAssignment a) =>
      switch (a) {
        CouponAssignmentPublic() => {'kind': 'public'},
        CouponAssignmentAccount(:final accountId) => {
            'kind': 'account',
            if (accountId.contains('@'))
              'email': accountId
            else
              'accountId': accountId,
          },
      };

  static String? _clean(String? value) {
    final v = value?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  // ---- reads ---------------------------------------------------------------

  @override
  Future<Result<CommerceState>> loadPlatform() async {
    final offers = await _api.send(
      'GET',
      _offers,
      parse: (json) => [
        for (final row in json as List) _offer(row as Map<String, dynamic>),
      ],
    );
    if (offers is! Success<List<GlobalOffer>>) {
      return switch (offers) {
        Failure(:final message, :final code) => Failure(message, code: code),
        _ => const Offline(),
      };
    }
    final coupons = await _api.send(
      'GET',
      _coupons,
      parse: (json) => [
        for (final row in json as List) _coupon(row as Map<String, dynamic>),
      ],
    );
    return switch (coupons) {
      Success(:final data) => Success(CommerceState(
          offers: List.unmodifiable(offers.data),
          coupons: List.unmodifiable(data),
        )),
      Failure(:final message, :final code) => Failure(message, code: code),
      Offline() => const Offline(),
    };
  }

  @override
  Future<Result<List<GlobalOffer>>> loadActiveOffers() => _api.send(
        'GET',
        '/pricing/offers/active',
        authenticated: false,
        parse: (json) => List.unmodifiable([
          for (final row in json as List) _offer(row as Map<String, dynamic>),
        ]),
      );

  // ---- offers --------------------------------------------------------------

  Map<String, dynamic> _offerBody({
    required BillingOptionId target,
    required Discount discount,
    required bool enabled,
    String? title,
    DateTime? endsAt,
  }) =>
      {
        'target': target.wire,
        'discount': _discountJson(discount),
        'title': _clean(title),
        'endsAt': endsAt?.toUtc().toIso8601String(),
        'enabled': enabled,
      };

  @override
  Future<Result<GlobalOffer>> createOffer({
    required BillingOptionId target,
    required Discount discount,
    required bool enabled,
    String? title,
    DateTime? endsAt,
  }) =>
      _api.send(
        'POST',
        _offers,
        body: _offerBody(
            target: target,
            discount: discount,
            enabled: enabled,
            title: title,
            endsAt: endsAt),
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: (json) => _offer(json as Map<String, dynamic>),
      );

  @override
  Future<Result<GlobalOffer>> updateOffer(
    String id, {
    required BillingOptionId target,
    required Discount discount,
    required bool enabled,
    String? title,
    DateTime? endsAt,
  }) =>
      _api.send(
        'PATCH',
        _one(_offers, id),
        body: _offerBody(
            target: target,
            discount: discount,
            enabled: enabled,
            title: title,
            endsAt: endsAt),
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: (json) => _offer(json as Map<String, dynamic>),
      );

  @override
  Future<Result<GlobalOffer>> setOfferEnabled(String id, bool enabled) =>
      _api.send(
        'POST',
        '${_one(_offers, id)}/${enabled ? 'enable' : 'disable'}',
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: (json) => _offer(json as Map<String, dynamic>),
      );

  @override
  Future<Result<void>> removeOffer(String id) => _api.send(
        'DELETE',
        _one(_offers, id),
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: (_) {},
      );

  // ---- coupons -------------------------------------------------------------

  Map<String, dynamic> _couponBody({
    required String code,
    required BillingOptionId target,
    required Discount discount,
    required CouponAssignment assignment,
    required bool enabled,
    String? note,
    DateTime? expiresAt,
  }) =>
      {
        'code': code,
        'target': target.wire,
        'discount': _discountJson(discount),
        'assignment': _assignmentJson(assignment),
        'note': _clean(note),
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
        'enabled': enabled,
      };

  @override
  Future<Result<Coupon>> createCoupon({
    required String code,
    required BillingOptionId target,
    required Discount discount,
    required CouponAssignment assignment,
    required bool enabled,
    String? note,
    DateTime? expiresAt,
  }) =>
      _api.send(
        'POST',
        _coupons,
        body: _couponBody(
            code: code,
            target: target,
            discount: discount,
            assignment: assignment,
            enabled: enabled,
            note: note,
            expiresAt: expiresAt),
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: (json) => _coupon(json as Map<String, dynamic>),
      );

  @override
  Future<Result<Coupon>> updateCoupon(
    String id, {
    required String code,
    required BillingOptionId target,
    required Discount discount,
    required CouponAssignment assignment,
    required bool enabled,
    String? note,
    DateTime? expiresAt,
  }) =>
      _api.send(
        'PATCH',
        _one(_coupons, id),
        body: _couponBody(
            code: code,
            target: target,
            discount: discount,
            assignment: assignment,
            enabled: enabled,
            note: note,
            expiresAt: expiresAt),
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: (json) => _coupon(json as Map<String, dynamic>),
      );

  @override
  Future<Result<Coupon>> setCouponEnabled(String id, bool enabled) => _api.send(
        'POST',
        '${_one(_coupons, id)}/${enabled ? 'enable' : 'disable'}',
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: (json) => _coupon(json as Map<String, dynamic>),
      );

  @override
  Future<Result<void>> removeCoupon(String id) => _api.send(
        'DELETE',
        _one(_coupons, id),
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: (_) {},
      );

  // ---- customer ------------------------------------------------------------

  @override
  Future<Result<CouponResolution>> validateCoupon(
    String code,
    BillingOptionId selected,
  ) =>
      _api.send(
        'POST',
        '/pricing/coupons/validate',
        body: {'code': code, 'billingOptionId': selected.wire},
        parse: (json) {
          final j = json as Map<String, dynamic>;
          final coupon = j['coupon'] as Map<String, dynamic>;
          final quote = j['quote'] as Map<String, dynamic>;
          final target = _option(coupon['target']);
          final finalPrice = _money(quote['finalPrice']);
          // The server's quote already chose between the coupon and a live
          // offer (an exact tie stays with the offer). Its final price is the
          // coupon's price when the coupon applied, and the offer's when the
          // offer is better — which resolvePriceQuotes then reads the same
          // way, so the screen and the server agree.
          return CouponResolution(
            coupon: Coupon(
              id: coupon['code'] as String,
              code: coupon['code'] as String,
              enabled: true,
              target: target,
              discount: FixedFinalPriceDiscount(finalPrice),
              assignment: const CouponAssignmentPublic(),
              createdAt: DateTime.utc(1970),
            ),
            target: target,
            basePrice: _money(quote['basePrice']),
            finalPrice: finalPrice,
          );
        },
      );
}
