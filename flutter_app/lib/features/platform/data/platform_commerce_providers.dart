/// Platform authorization boundary for local commerce controls.
///
/// A visible role label is never authority. Only an authenticated Super Admin
/// can produce a [CommerceActor], and every control-plane mutation still
/// refuses a null actor.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../auth/data/auth_providers.dart';
import '../../auth/domain/auth_models.dart';
import '../../pricing/data/commerce_control_plane.dart';
import '../../pricing/domain/billing_option.dart';
import '../../pricing/domain/promotion.dart';

final platformCommerceActorProvider = Provider<CommerceActor?>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null || user.role != AuthRole.superAdmin) return null;
  return CommerceActor(accountId: user.id, displayName: user.name);
});

class PlatformCommerceActions {
  const PlatformCommerceActions(this._ref);

  final Ref _ref;

  CommerceControlPlane get _plane =>
      _ref.read(commerceControlPlaneProvider.notifier);
  CommerceActor? get _actor => _ref.read(platformCommerceActorProvider);

  Result<GlobalOffer> createOffer({
    required BillingOptionId target,
    required Discount discount,
    required bool enabled,
    String? title,
  }) =>
      _plane.createOffer(
        target: target,
        discount: discount,
        enabled: enabled,
        title: title,
        actor: _actor,
      );

  Result<GlobalOffer> updateOffer(
    String id, {
    required BillingOptionId target,
    required Discount discount,
    required bool enabled,
    String? title,
  }) =>
      _plane.updateOffer(
        id,
        target: target,
        discount: discount,
        enabled: enabled,
        title: title,
        actor: _actor,
      );

  Result<GlobalOffer> setOfferEnabled(String id, bool enabled) =>
      _plane.setOfferEnabled(id, enabled, actor: _actor);

  Result<GlobalOffer> removeOffer(String id) =>
      _plane.removeOffer(id, actor: _actor);

  Result<Coupon> createCoupon({
    required String code,
    required BillingOptionId target,
    required Discount discount,
    required CouponAssignment assignment,
    required bool enabled,
    String? note,
  }) =>
      _plane.createCoupon(
        code: code,
        target: target,
        discount: discount,
        assignment: assignment,
        enabled: enabled,
        note: note,
        actor: _actor,
      );

  Result<Coupon> updateCoupon(
    String id, {
    required String code,
    required BillingOptionId target,
    required Discount discount,
    required CouponAssignment assignment,
    required bool enabled,
    String? note,
  }) =>
      _plane.updateCoupon(
        id,
        code: code,
        target: target,
        discount: discount,
        assignment: assignment,
        enabled: enabled,
        note: note,
        actor: _actor,
      );

  Result<Coupon> setCouponEnabled(String id, bool enabled) =>
      _plane.setCouponEnabled(id, enabled, actor: _actor);

  Result<Coupon> removeCoupon(String id) =>
      _plane.removeCoupon(id, actor: _actor);
}

final platformCommerceActionsProvider =
    Provider<PlatformCommerceActions>(PlatformCommerceActions.new);
