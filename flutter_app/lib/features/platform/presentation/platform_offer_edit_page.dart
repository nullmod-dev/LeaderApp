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

/// Create or edit one global offer.
///
/// **The hierarchy, not the rules.** The eligible durations, the two discount
/// shapes and the 1–90 % bound are exactly what they were; what the form gained
/// is section headings, a form measure instead of the page's 720 dp working
/// column, a live reading of what the customer would pay, and one primary
/// action beside a secondary «إلغاء» instead of a lone save button.
///
/// The choice controls stay [ChoicePill]s. They are form *values* — which
/// duration this offer is for — not a filter over a list, and Phase 1 drew
/// that line deliberately when it retired the app's nine filter pills.
class PlatformOfferEditPage extends ConsumerStatefulWidget {
  const PlatformOfferEditPage({super.key, this.offerId});

  final String? offerId;

  @override
  ConsumerState<PlatformOfferEditPage> createState() =>
      _PlatformOfferEditPageState();
}

class _PlatformOfferEditPageState extends ConsumerState<PlatformOfferEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _value;
  late final TextEditingController _title;
  var _target = BillingOptionId.monthly;
  var _percentage = true;
  var _enabled = false;
  var _initialized = false;

  @override
  void initState() {
    super.initState();
    _value = TextEditingController();
    _title = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final id = widget.offerId;
    final offer = id == null
        ? null
        : ref.read(commerceControlPlaneProvider).offerById(id);
    if (offer != null) {
      _target = offer.target;
      _percentage = offer.discount is PercentageDiscount;
      _enabled = offer.enabled;
      _value.text = PlatformCommerceCopy.discountValue(offer.discount);
      _title.text = offer.title ?? '';
    }
  }

  @override
  void dispose() {
    _value.dispose();
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(pricingCatalogProvider);
    return PlatformPage(
      title: widget.offerId == null
          ? S.platformCommerceCreateOffer
          : S.platformCommerceEditOffer,
      children: [
        const PlatformPageIntro(lead: S.platformCommerceOfferLead),
        const SizedBox(height: AppSpacing.lg),
        ReadingColumn(
          maxWidth: kFormMaxWidth,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  key: const Key('platform-offer-value'),
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
                  switchKey: const Key('platform-offer-enabled'),
                  enabled: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  key: const Key('platform-offer-title'),
                  controller: _title,
                  decoration: const InputDecoration(
                    labelText: S.platformCommerceOfferTitle,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                CommerceFormActions(
                  saveKey: const Key('platform-offer-save'),
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
    final discount = _discount()!;
    final actions = ref.read(platformCommerceActionsProvider);
    final Result<GlobalOffer> result;
    if (widget.offerId == null) {
      result = actions.createOffer(
        target: _target,
        discount: discount,
        enabled: _enabled,
        title: _title.text,
      );
    } else {
      result = actions.updateOffer(
        widget.offerId!,
        target: _target,
        discount: discount,
        enabled: _enabled,
        title: _title.text,
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
          content: Text(code == CommerceCodes.offerConflict
              ? S.platformCommerceConflict
              : S.platformCommerceInvalid),
        ),
      ),
      offline: (_) {},
    );
  }
}
