import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result/result.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/reading_column.dart';
import '../../../core/widgets/section_header.dart';
import '../../../l10n/strings.dart';
import '../../pricing/data/commerce_control_plane.dart';
import '../../pricing/data/pricing_catalog.dart';
import '../../pricing/domain/billing_option.dart';
import '../../pricing/domain/promotion.dart';
import '../../pricing/presentation/pricing_copy.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../data/platform_commerce_providers.dart';
import 'platform_commerce_copy.dart';
import 'widgets/commerce_form.dart';
import 'widgets/platform_page.dart';

/// Create or edit one coupon.
///
/// Same shape as the offer editor plus the section that makes a coupon a
/// coupon — its code, and whether anybody holding it may use it or only one
/// named account. The code field stays left-to-right and upper-cased, because
/// a coupon code is a technical value inside an Arabic form.
class PlatformCouponEditPage extends ConsumerStatefulWidget {
  const PlatformCouponEditPage({super.key, this.couponId});

  final String? couponId;

  @override
  ConsumerState<PlatformCouponEditPage> createState() =>
      _PlatformCouponEditPageState();
}

class _PlatformCouponEditPageState
    extends ConsumerState<PlatformCouponEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _value;
  late final TextEditingController _account;
  late final TextEditingController _note;
  var _target = BillingOptionId.monthly;
  var _percentage = true;
  var _public = true;
  var _enabled = false;
  var _initialized = false;

  @override
  void initState() {
    super.initState();
    _code = TextEditingController();
    _value = TextEditingController();
    _account = TextEditingController();
    _note = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final id = widget.couponId;
    final coupon = id == null
        ? null
        : ref.read(commerceControlPlaneProvider).couponById(id);
    if (coupon != null) {
      _code.text = coupon.code;
      _target = coupon.target;
      _percentage = coupon.discount is PercentageDiscount;
      _value.text = PlatformCommerceCopy.discountValue(coupon.discount);
      _public = coupon.assignment is CouponAssignmentPublic;
      if (coupon.assignment case CouponAssignmentAccount(:final accountId)) {
        _account.text = accountId;
      }
      _note.text = coupon.note ?? '';
      _enabled = coupon.enabled;
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _value.dispose();
    _account.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(pricingCatalogProvider);
    return PlatformPage(
      title: widget.couponId == null
          ? S.platformCommerceCreateCoupon
          : S.platformCommerceEditCoupon,
      children: [
        const PlatformPageIntro(lead: S.platformCommerceCouponLead),
        const SizedBox(height: AppSpacing.lg),
        ReadingColumn(
          maxWidth: kFormMaxWidth,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: S.platformCommerceSectionIdentity),
                TextFormField(
                  key: const Key('platform-coupon-code'),
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: S.platformCommerceCouponCode,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? S.platformCommerceInvalid
                      : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  S.platformCommerceAssignment,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                CommerceChoiceRow(
                  children: [
                    ChoicePill(
                      label: S.platformCommercePublic,
                      selected: _public,
                      onTap: () => setState(() => _public = true),
                    ),
                    ChoicePill(
                      label: S.platformCommerceTargeted,
                      selected: !_public,
                      onTap: () => setState(() => _public = false),
                    ),
                  ],
                ),
                if (!_public) ...[
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: const Key('platform-coupon-account'),
                    controller: _account,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: S.platformCommerceAccountId,
                    ),
                    validator: (value) =>
                        !_public && (value == null || value.trim().isEmpty)
                            ? S.platformCommerceInvalid
                            : null,
                  ),
                ],
                const SectionHeader(title: S.platformCommerceTarget),
                CommerceChoiceRow(
                  children: [
                    for (final target in kPromotionEligibleOptions)
                      ChoicePill(
                        label: PricingCopy.duration(target),
                        selected: _target == target,
                        onTap: () => setState(() => _target = target),
                      ),
                  ],
                ),
                const CommerceFormNote(S.platformCommerceEligibleNote),
                const SectionHeader(title: S.platformCommerceSectionDiscount),
                CommerceChoiceRow(
                  children: [
                    ChoicePill(
                      label: S.platformCommercePercentage,
                      selected: _percentage,
                      onTap: () => setState(() => _percentage = true),
                    ),
                    ChoicePill(
                      label: S.platformCommerceFixedPrice,
                      selected: !_percentage,
                      onTap: () => setState(() => _percentage = false),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const Key('platform-coupon-value'),
                  controller: _value,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textDirection: TextDirection.ltr,
                  onChanged: (_) => setState(() {}),
                  decoration:
                      const InputDecoration(labelText: S.platformCommerceValue),
                  validator: (_) =>
                      _discount() == null ? S.platformCommerceInvalid : null,
                ),
                const SizedBox(height: AppSpacing.md),
                CommercePricePreview(
                  base: billingOptionById(catalog, _target)?.basePrice,
                  discount: _discount(),
                ),
                const SectionHeader(
                  title: S.platformCommerceSectionAvailability,
                ),
                CommerceAvailabilityCard(
                  switchKey: const Key('platform-coupon-enabled'),
                  enabled: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  key: const Key('platform-coupon-note'),
                  controller: _note,
                  decoration: const InputDecoration(
                    labelText: S.platformCommerceInternalNote,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                CommerceFormActions(
                  saveKey: const Key('platform-coupon-save'),
                  onSave: _save,
                  onCancel: () => context.pop(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Discount? _discount() {
    if (_percentage) {
      final percent = int.tryParse(_value.text.trim());
      if (percent == null || percent < 1 || percent > 90) return null;
      return PercentageDiscount(percent);
    }
    final price = PlatformCommerceCopy.fixedPrice(_value.text);
    return price == null ? null : FixedFinalPriceDiscount(price);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final assignment = _public
        ? const CouponAssignmentPublic()
        : CouponAssignmentAccount(_account.text.trim());
    final actions = ref.read(platformCommerceActionsProvider);
    final Result<Coupon> result;
    if (widget.couponId == null) {
      result = actions.createCoupon(
        code: _code.text,
        target: _target,
        discount: _discount()!,
        assignment: assignment,
        enabled: _enabled,
        note: _note.text,
      );
    } else {
      result = actions.updateCoupon(
        widget.couponId!,
        code: _code.text,
        target: _target,
        discount: _discount()!,
        assignment: assignment,
        enabled: _enabled,
        note: _note.text,
      );
    }
    result.when(
      success: (_, {stale = false}) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(S.platformCommerceSaved)),
        );
        context.pop();
      },
      failure: (_, code) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(code == CommerceCodes.couponCodeTaken
              ? S.platformCommerceCodeTaken
              : S.platformCommerceInvalid),
        ),
      ),
      offline: (_) {},
    );
  }
}
