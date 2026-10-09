/// The commercial control plane: global offers and coupons.
///
/// **Two modes, one surface.** Without a backend (tests, the no-server build)
/// state lives only in process memory, exactly as before. With one
/// ([commerceBackendProvider]), this is a cache of what the server answered:
/// it loads on build — every offer and coupon for a Super Admin, the live
/// offers for everyone else — and every change is made on the server first
/// and applied here from its reply. Neither mode is payment authority, coupon
/// redemption or subscription activation.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../../auth/data/auth_providers.dart';
import '../../auth/domain/auth_models.dart';
import 'commerce_backend.dart';
import '../domain/billing_option.dart';
import '../domain/coupon_code.dart';
import '../domain/money.dart';
import '../domain/promotion.dart';
import 'pricing_catalog.dart';

final class CommerceActor {
  const CommerceActor({required this.accountId, required this.displayName});

  final String accountId;
  final String displayName;
}

/// Where the control plane's state came from.
enum CommercePhase {
  /// In-memory development state; always "ready".
  local,

  /// A backend read is in flight and nothing has arrived yet.
  loading,

  /// The backend answered.
  ready,

  /// The backend read failed; [CommerceControlPlane.reload] tries again.
  failed,
}

final class CommerceState {
  const CommerceState({
    required this.offers,
    required this.coupons,
    this.phase = CommercePhase.local,
  });

  final List<GlobalOffer> offers;
  final List<Coupon> coupons;
  final CommercePhase phase;

  GlobalOffer? offerById(String id) {
    for (final offer in offers) {
      if (offer.id == id) return offer;
    }
    return null;
  }

  GlobalOffer? liveOfferFor(BillingOptionId option, DateTime now) {
    for (final offer in offers) {
      if (offer.target == option && offer.isLiveAt(now)) return offer;
    }
    return null;
  }

  Coupon? couponById(String id) {
    for (final coupon in coupons) {
      if (coupon.id == id) return coupon;
    }
    return null;
  }

  Coupon? couponByCode(String normalizedCode) {
    for (final coupon in coupons) {
      if (coupon.code == normalizedCode) return coupon;
    }
    return null;
  }

  CommerceState copyWith({
    List<GlobalOffer>? offers,
    List<Coupon>? coupons,
    CommercePhase? phase,
  }) =>
      CommerceState(
        offers: offers ?? this.offers,
        coupons: coupons ?? this.coupons,
        phase: phase ?? this.phase,
      );
}

abstract final class CommerceCodes {
  static const notAuthorized = 'not_authorized';
  static const offerNotFound = 'offer_not_found';
  static const offerConflict = 'offer_conflict';
  static const couponNotFound = 'coupon_not_found';
  static const couponCodeTaken = 'coupon_code_taken';
  static const couponCodeInvalid = 'coupon_code_invalid';
  static const promotionInvalid = 'promotion_invalid';
}

final commerceControlPlaneSeedProvider = Provider<CommerceState>((ref) {
  final now = ref.watch(clockProvider)().toUtc();
  return CommerceState(
    offers: List.unmodifiable([
      GlobalOffer(
        id: 'offer_seed_try2',
        enabled: false,
        target: BillingOptionId.monthly,
        discount: const FixedFinalPriceDiscount(Money.cents(200)),
        createdAt: now.subtract(const Duration(days: 3)),
        title: 'جرّب أول شهر بـ \$2',
      ),
    ]),
    coupons: List.unmodifiable([
      Coupon(
        id: 'coupon_seed_public',
        code: 'LEADER10',
        enabled: false,
        target: BillingOptionId.threeMonths,
        discount: const PercentageDiscount(10),
        assignment: const CouponAssignmentPublic(),
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      Coupon(
        id: 'coupon_seed_targeted',
        code: 'TRY2',
        enabled: false,
        target: BillingOptionId.monthly,
        discount: const FixedFinalPriceDiscount(Money.cents(200)),
        assignment: const CouponAssignmentAccount('u_demo_main'),
        createdAt: now.subtract(const Duration(days: 1)),
      ),
    ]),
  );
});

class CommerceControlPlane extends Notifier<CommerceState> {
  int _sequence = 0;
  CommerceBackend? _backend;

  /// A Super Admin manages every offer and coupon; everyone else sees only
  /// the live offers (coupons are validated one code at a time).
  bool _platform = false;

  @override
  CommerceState build() {
    _backend = ref.watch(commerceBackendProvider);
    final backend = _backend;
    if (backend == null) {
      final seed = ref.watch(commerceControlPlaneSeedProvider);
      return CommerceState(
        offers: List.unmodifiable(seed.offers),
        coupons: List.unmodifiable(seed.coupons),
      );
    }
    final role =
        ref.watch(currentUserProvider.select((u) => u.valueOrNull?.role));
    _platform = role == AuthRole.superAdmin;
    Future.microtask(reload);
    return const CommerceState(
      offers: [],
      coupons: [],
      phase: CommercePhase.loading,
    );
  }

  /// Reads the server again. A no-op without a backend.
  Future<void> reload() async {
    final backend = _backend;
    if (backend == null) return;
    if (state.phase == CommercePhase.failed) {
      state = state.copyWith(phase: CommercePhase.loading);
    }
    if (_platform) {
      final result = await backend.loadPlatform();
      state = switch (result) {
        Success(:final data) => data.copyWith(phase: CommercePhase.ready),
        _ => state.copyWith(phase: CommercePhase.failed),
      };
    } else {
      final result = await backend.loadActiveOffers();
      state = switch (result) {
        Success(:final data) => CommerceState(
            offers: data,
            coupons: const [],
            phase: CommercePhase.ready,
          ),
        _ => state.copyWith(phase: CommercePhase.failed),
      };
    }
  }

  void _putOffer(GlobalOffer offer) {
    final known = state.offers.any((o) => o.id == offer.id);
    state = state.copyWith(
      offers: List.unmodifiable(known
          ? [for (final o in state.offers) o.id == offer.id ? offer : o]
          : [offer, ...state.offers]),
    );
  }

  void _putCoupon(Coupon coupon) {
    final known = state.coupons.any((c) => c.id == coupon.id);
    state = state.copyWith(
      coupons: List.unmodifiable(known
          ? [for (final c in state.coupons) c.id == coupon.id ? coupon : c]
          : [coupon, ...state.coupons]),
    );
  }

  /// The server's answer to a change, applied to the cache on success.
  Future<Result<T>> _remote<T>(
    Future<Result<T>> call,
    void Function(T value) apply,
  ) async {
    final result = await call;
    if (result case Success(:final data)) apply(data);
    return result;
  }

  DateTime get _now => ref.read(clockProvider)().toUtc();
  List<BillingOption> get _catalog => ref.read(pricingCatalogProvider);

  Future<Result<GlobalOffer>> createOffer({
    required BillingOptionId target,
    required Discount discount,
    bool enabled = false,
    String? title,
    DateTime? endsAt,
    CommerceActor? actor,
  }) async {
    final backend = _backend;
    if (backend == null) {
      return _localCreateOffer(
          target: target,
          discount: discount,
          enabled: enabled,
          title: title,
          endsAt: endsAt,
          actor: actor);
    }
    if (actor == null) return _unauthorized();
    return _remote(
        backend.createOffer(
            target: target,
            discount: discount,
            enabled: enabled,
            title: title,
            endsAt: endsAt),
        _putOffer);
  }

  Result<GlobalOffer> _localCreateOffer({
    required BillingOptionId target,
    required Discount discount,
    bool enabled = false,
    String? title,
    DateTime? endsAt,
    CommerceActor? actor,
  }) {
    if (actor == null) return _unauthorized();
    final invalid = _validatePromotion<GlobalOffer>(target, discount);
    if (invalid != null) return invalid;
    if (enabled && state.liveOfferFor(target, _now) != null) {
      return const Failure('', code: CommerceCodes.offerConflict);
    }
    final offer = GlobalOffer(
      id: 'offer_${_now.microsecondsSinceEpoch}_${_sequence++}',
      enabled: enabled,
      target: target,
      discount: discount,
      createdAt: _now,
      title: _cleanOptional(title),
      endsAt: endsAt?.toUtc(),
    );
    state = state.copyWith(offers: List.unmodifiable([offer, ...state.offers]));
    return Success(offer);
  }

  Future<Result<GlobalOffer>> updateOffer(
    String id, {
    required BillingOptionId target,
    required Discount discount,
    required bool enabled,
    String? title,
    DateTime? endsAt,
    CommerceActor? actor,
  }) async {
    final backend = _backend;
    if (backend == null) {
      return _localUpdateOffer(id,
          target: target,
          discount: discount,
          enabled: enabled,
          title: title,
          endsAt: endsAt,
          actor: actor);
    }
    if (actor == null) return _unauthorized();
    return _remote(
        backend.updateOffer(id,
            target: target,
            discount: discount,
            enabled: enabled,
            title: title,
            endsAt: endsAt),
        _putOffer);
  }

  Result<GlobalOffer> _localUpdateOffer(
    String id, {
    required BillingOptionId target,
    required Discount discount,
    required bool enabled,
    String? title,
    DateTime? endsAt,
    CommerceActor? actor,
  }) {
    if (actor == null) return _unauthorized();
    final existing = state.offerById(id);
    if (existing == null) {
      return const Failure('', code: CommerceCodes.offerNotFound);
    }
    final invalid = _validatePromotion<GlobalOffer>(target, discount);
    if (invalid != null) return invalid;
    if (enabled && _hasOtherLiveOffer(target, id)) {
      return const Failure('', code: CommerceCodes.offerConflict);
    }
    final updated = GlobalOffer(
      id: existing.id,
      enabled: enabled,
      target: target,
      discount: discount,
      createdAt: existing.createdAt,
      title: _cleanOptional(title),
      endsAt: endsAt?.toUtc(),
    );
    state = state.copyWith(
      offers: List.unmodifiable([
        for (final offer in state.offers)
          if (offer.id == id) updated else offer,
      ]),
    );
    return Success(updated);
  }

  Future<Result<GlobalOffer>> setOfferEnabled(
    String id,
    bool enabled, {
    CommerceActor? actor,
  }) async {
    final backend = _backend;
    if (backend == null) {
      return _localSetOfferEnabled(id, enabled, actor: actor);
    }
    if (actor == null) return _unauthorized();
    return _remote(backend.setOfferEnabled(id, enabled), _putOffer);
  }

  Result<GlobalOffer> _localSetOfferEnabled(
    String id,
    bool enabled, {
    CommerceActor? actor,
  }) {
    if (actor == null) return _unauthorized();
    final existing = state.offerById(id);
    if (existing == null) {
      return const Failure('', code: CommerceCodes.offerNotFound);
    }
    if (enabled && _hasOtherLiveOffer(existing.target, id)) {
      return const Failure('', code: CommerceCodes.offerConflict);
    }
    return _localUpdateOffer(
      id,
      target: existing.target,
      discount: existing.discount,
      enabled: enabled,
      title: existing.title,
      endsAt: existing.endsAt,
      actor: actor,
    );
  }

  Future<Result<GlobalOffer>> removeOffer(String id,
      {CommerceActor? actor}) async {
    final backend = _backend;
    if (backend == null) return _localRemoveOffer(id, actor: actor);
    if (actor == null) return _unauthorized();
    final existing = state.offerById(id);
    if (existing == null) {
      return const Failure('', code: CommerceCodes.offerNotFound);
    }
    final result = await backend.removeOffer(id);
    return switch (result) {
      Success() => () {
          state = state.copyWith(
            offers: List.unmodifiable(state.offers.where((e) => e.id != id)),
          );
          return Success(existing);
        }(),
      Failure(:final message, :final code) => Failure(message, code: code),
      Offline() => const Offline(),
    };
  }

  Result<GlobalOffer> _localRemoveOffer(String id, {CommerceActor? actor}) {
    if (actor == null) return _unauthorized();
    final existing = state.offerById(id);
    if (existing == null) {
      return const Failure('', code: CommerceCodes.offerNotFound);
    }
    state = state.copyWith(
      offers: List.unmodifiable(state.offers.where((offer) => offer.id != id)),
    );
    return Success(existing);
  }

  Future<Result<Coupon>> createCoupon({
    required String code,
    required BillingOptionId target,
    required Discount discount,
    required CouponAssignment assignment,
    bool enabled = false,
    String? note,
    DateTime? expiresAt,
    CommerceActor? actor,
  }) async {
    final backend = _backend;
    if (backend == null) {
      return _localCreateCoupon(
          code: code,
          target: target,
          discount: discount,
          assignment: assignment,
          enabled: enabled,
          note: note,
          expiresAt: expiresAt,
          actor: actor);
    }
    if (actor == null) return _unauthorized();
    return _remote(
        backend.createCoupon(
            code: code,
            target: target,
            discount: discount,
            assignment: assignment,
            enabled: enabled,
            note: note,
            expiresAt: expiresAt),
        _putCoupon);
  }

  Result<Coupon> _localCreateCoupon({
    required String code,
    required BillingOptionId target,
    required Discount discount,
    required CouponAssignment assignment,
    bool enabled = false,
    String? note,
    DateTime? expiresAt,
    CommerceActor? actor,
  }) {
    if (actor == null) return _unauthorized();
    final normalized = normalizeCouponCode(code);
    if (normalized == null) {
      return const Failure('', code: CommerceCodes.couponCodeInvalid);
    }
    if (state.couponByCode(normalized) != null) {
      return const Failure('', code: CommerceCodes.couponCodeTaken);
    }
    final invalid = _validatePromotion<Coupon>(target, discount);
    if (invalid != null) return invalid;
    if (assignment is CouponAssignmentAccount &&
        assignment.accountId.trim().isEmpty) {
      return const Failure('', code: CommerceCodes.promotionInvalid);
    }
    final coupon = Coupon(
      id: 'coupon_${_now.microsecondsSinceEpoch}_${_sequence++}',
      code: normalized,
      enabled: enabled,
      target: target,
      discount: discount,
      assignment: assignment,
      createdAt: _now,
      note: _cleanOptional(note),
      expiresAt: expiresAt?.toUtc(),
    );
    state =
        state.copyWith(coupons: List.unmodifiable([coupon, ...state.coupons]));
    return Success(coupon);
  }

  Future<Result<Coupon>> updateCoupon(
    String id, {
    required String code,
    required BillingOptionId target,
    required Discount discount,
    required CouponAssignment assignment,
    required bool enabled,
    String? note,
    DateTime? expiresAt,
    CommerceActor? actor,
  }) async {
    final backend = _backend;
    if (backend == null) {
      return _localUpdateCoupon(id,
          code: code,
          target: target,
          discount: discount,
          assignment: assignment,
          enabled: enabled,
          note: note,
          expiresAt: expiresAt,
          actor: actor);
    }
    if (actor == null) return _unauthorized();
    return _remote(
        backend.updateCoupon(id,
            code: code,
            target: target,
            discount: discount,
            assignment: assignment,
            enabled: enabled,
            note: note,
            expiresAt: expiresAt),
        _putCoupon);
  }

  Result<Coupon> _localUpdateCoupon(
    String id, {
    required String code,
    required BillingOptionId target,
    required Discount discount,
    required CouponAssignment assignment,
    required bool enabled,
    String? note,
    DateTime? expiresAt,
    CommerceActor? actor,
  }) {
    if (actor == null) return _unauthorized();
    final existing = state.couponById(id);
    if (existing == null) {
      return const Failure('', code: CommerceCodes.couponNotFound);
    }
    final normalized = normalizeCouponCode(code);
    if (normalized == null) {
      return const Failure('', code: CommerceCodes.couponCodeInvalid);
    }
    final sameCode = state.couponByCode(normalized);
    if (sameCode != null && sameCode.id != id) {
      return const Failure('', code: CommerceCodes.couponCodeTaken);
    }
    final invalid = _validatePromotion<Coupon>(target, discount);
    if (invalid != null) return invalid;
    if (assignment is CouponAssignmentAccount &&
        assignment.accountId.trim().isEmpty) {
      return const Failure('', code: CommerceCodes.promotionInvalid);
    }
    final updated = Coupon(
      id: existing.id,
      code: normalized,
      enabled: enabled,
      target: target,
      discount: discount,
      assignment: assignment,
      createdAt: existing.createdAt,
      note: _cleanOptional(note),
      expiresAt: expiresAt?.toUtc(),
    );
    state = state.copyWith(
      coupons: List.unmodifiable([
        for (final coupon in state.coupons)
          if (coupon.id == id) updated else coupon,
      ]),
    );
    return Success(updated);
  }

  Future<Result<Coupon>> setCouponEnabled(
    String id,
    bool enabled, {
    CommerceActor? actor,
  }) async {
    final backend = _backend;
    if (backend == null) {
      return _localSetCouponEnabled(id, enabled, actor: actor);
    }
    if (actor == null) return _unauthorized();
    return _remote(backend.setCouponEnabled(id, enabled), _putCoupon);
  }

  Result<Coupon> _localSetCouponEnabled(
    String id,
    bool enabled, {
    CommerceActor? actor,
  }) {
    if (actor == null) return _unauthorized();
    final existing = state.couponById(id);
    if (existing == null) {
      return const Failure('', code: CommerceCodes.couponNotFound);
    }
    return _localUpdateCoupon(
      id,
      code: existing.code,
      target: existing.target,
      discount: existing.discount,
      assignment: existing.assignment,
      enabled: enabled,
      note: existing.note,
      expiresAt: existing.expiresAt,
      actor: actor,
    );
  }

  Future<Result<Coupon>> removeCoupon(String id, {CommerceActor? actor}) async {
    final backend = _backend;
    if (backend == null) return _localRemoveCoupon(id, actor: actor);
    if (actor == null) return _unauthorized();
    final existing = state.couponById(id);
    if (existing == null) {
      return const Failure('', code: CommerceCodes.couponNotFound);
    }
    final result = await backend.removeCoupon(id);
    return switch (result) {
      Success() => () {
          state = state.copyWith(
            coupons: List.unmodifiable(state.coupons.where((e) => e.id != id)),
          );
          return Success(existing);
        }(),
      Failure(:final message, :final code) => Failure(message, code: code),
      Offline() => const Offline(),
    };
  }

  Result<Coupon> _localRemoveCoupon(String id, {CommerceActor? actor}) {
    if (actor == null) return _unauthorized();
    final existing = state.couponById(id);
    if (existing == null) {
      return const Failure('', code: CommerceCodes.couponNotFound);
    }
    state = state.copyWith(
      coupons:
          List.unmodifiable(state.coupons.where((coupon) => coupon.id != id)),
    );
    return Success(existing);
  }

  bool _hasOtherLiveOffer(BillingOptionId target, String id) =>
      state.offers.any((offer) =>
          offer.id != id && offer.target == target && offer.isLiveAt(_now));

  Failure<T>? _validatePromotion<T>(
    BillingOptionId target,
    Discount discount,
  ) {
    final option = billingOptionById(_catalog, target);
    if (!target.promotionEligible ||
        option == null ||
        !isSaneFor(discount, option.basePrice)) {
      return const Failure('', code: CommerceCodes.promotionInvalid);
    }
    return null;
  }

  Failure<T> _unauthorized<T>() =>
      const Failure('', code: CommerceCodes.notAuthorized);

  String? _cleanOptional(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }
}

final commerceControlPlaneProvider =
    NotifierProvider<CommerceControlPlane, CommerceState>(
  CommerceControlPlane.new,
);
