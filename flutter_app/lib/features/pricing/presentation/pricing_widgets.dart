import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../data/pricing_providers.dart';
import '../domain/billing_option.dart';
import '../domain/coupon_validation.dart';
import '../domain/money.dart';
import '../domain/price_quote.dart';
import 'pricing_copy.dart';

class PricingNote extends StatelessWidget {
  const PricingNote({
    super.key,
    required this.text,
    this.kind = StatusKind.info,
    this.icon = Icons.info_outline_rounded,
  });

  final String text;
  final StatusKind kind;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (background, foreground) = switch (kind) {
      StatusKind.ok => (c.okTint, c.ok),
      StatusKind.warn => (c.warnTint, c.warn),
      StatusKind.crit => (c.critTint, c.crit),
      StatusKind.info => (c.infoTint, c.info),
      StatusKind.muted => (c.mutedTint, c.ink2),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: foreground),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: foreground, size: 20),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: c.ink, height: 1.5),
          ),
        ),
      ]),
    );
  }
}

class PricingColumns extends StatelessWidget {
  const PricingColumns({
    super.key,
    required this.primary,
    required this.secondary,
  });

  final Widget primary;
  final Widget secondary;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 900) {
            return Column(children: [
              primary,
              const SizedBox(height: AppSpacing.xl),
              secondary,
            ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: primary),
            const SizedBox(width: AppSpacing.xl),
            Expanded(flex: 2, child: secondary),
          ]);
        },
      );
}

class PricingOfferBanner extends StatelessWidget {
  const PricingOfferBanner({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => PricingNote(
        key: const Key('pricing-offer-banner'),
        text: '${S.pricingActiveOffer} — $label',
        kind: StatusKind.ok,
        icon: Icons.local_offer_outlined,
      );
}

class PlanCard extends StatelessWidget {
  const PlanCard({
    super.key,
    required this.quote,
    required this.selected,
    required this.onSelected,
  });

  final PriceQuote quote;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final promoted = quote.promotion != null;
    final duration = PricingCopy.duration(quote.option.id);
    return Semantics(
      button: true,
      checked: selected,
      inMutuallyExclusiveGroup: true,
      label: '$duration ${formatUsd(quote.finalPrice, isolate: false)}',
      child: Material(
        color: selected ? c.primaryTint : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.xl),
          side: BorderSide(
            color: selected ? c.primary : c.line,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('pricing-plan-${quote.option.id.wire}'),
          onTap: onSelected,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      duration,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (quote.option.id == BillingOptionId.twelveMonths)
                      const StatusChip(
                        kind: StatusKind.ok,
                        label: S.pricingBestValue,
                        icon: Icons.star_outline_rounded,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (promoted)
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      formatUsd(quote.basePrice, isolate: false),
                      style: TextStyle(
                        color: c.ink3,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    formatUsd(quote.finalPrice, isolate: false),
                    style: AppTypography.digits(c.ink, size: 28),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        formatUsd(
                          quote.effectiveMonthly,
                          isolate: false,
                          forceFractionalDigits: true,
                        ),
                        style: AppTypography.digits(c.ink2, size: 13),
                      ),
                    ),
                    Text(S.pricingPerMonth, style: TextStyle(color: c.ink2)),
                  ],
                ),
                if (quote.durationSavings.cents > 0) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(S.pricingSave, style: TextStyle(color: c.ok)),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          formatUsd(quote.durationSavings, isolate: false),
                          style: AppTypography.digits(c.ok, size: 13),
                        ),
                      ),
                    ],
                  ),
                ],
                if (quote.promotion case final promotion?) ...[
                  const SizedBox(height: AppSpacing.sm),
                  StatusChip(
                    kind: StatusKind.info,
                    label: promotion.displayLabel == 'global_offer'
                        ? S.pricingSpecialOffer
                        : promotion.displayLabel,
                    icon: Icons.sell_outlined,
                  ),
                ],
                if (selected) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const StatusChip(
                    kind: StatusKind.ok,
                    label: S.pricingSelected,
                    icon: Icons.check_rounded,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CouponSection extends ConsumerWidget {
  const CouponSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final entry = ref.watch(couponEntryProvider);
    final selected = ref.watch(selectedBillingOptionProvider);
    final resolution = ref.watch(pricingResolutionProvider);
    final busy = entry.phase == CouponPhase.validating;
    return Container(
      key: const Key('pricing-coupon-section'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.xl),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(S.pricingCouponTitle,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const Key('pricing-coupon-input'),
          enabled: !busy,
          textCapitalization: TextCapitalization.characters,
          textDirection: TextDirection.ltr,
          onChanged: ref.read(couponEntryProvider.notifier).setInput,
          decoration: const InputDecoration(
            labelText: S.pricingCouponHint,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton(
          key: const Key('pricing-coupon-validate'),
          onPressed: entry.input.trim().isEmpty || busy
              ? null
              : ref.read(couponEntryProvider.notifier).validate,
          child: busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(S.pricingCouponValidate),
        ),
        if (entry.phase == CouponPhase.done && entry.last != null) ...[
          const SizedBox(height: AppSpacing.md),
          _CouponResult(
            result: entry.last!,
            selected: selected,
            priceOutcome: resolution.couponOutcome,
          ),
        ],
      ]),
    );
  }
}

class _CouponResult extends StatelessWidget {
  const _CouponResult({
    required this.result,
    required this.selected,
    required this.priceOutcome,
  });

  final Result<CouponResolution> result;
  final BillingOptionId selected;
  final CouponPriceOutcome priceOutcome;

  @override
  Widget build(BuildContext context) {
    if (result is! Success<CouponResolution>) {
      return const PricingNote(
        key: Key('pricing-coupon-invalid'),
        text: S.pricingCouponInvalid,
        kind: StatusKind.warn,
        icon: Icons.info_outline_rounded,
      );
    }
    final resolution = (result as Success<CouponResolution>).data;
    if (resolution.target != selected) {
      return PricingNote(
        key: const Key('pricing-coupon-wrong-duration'),
        text:
            '${S.pricingCouponWrongDuration} ${PricingCopy.duration(resolution.target)}',
        kind: StatusKind.info,
      );
    }
    if (priceOutcome == CouponPriceOutcome.globalOfferIsBetter) {
      return const PricingNote(
        key: Key('pricing-coupon-offer-better'),
        text: S.pricingCouponOfferBetter,
        kind: StatusKind.ok,
        icon: Icons.check_circle_outline_rounded,
      );
    }
    return PricingNote(
      key: const Key('pricing-coupon-valid'),
      text:
          '${S.pricingCouponValid} ${resolution.coupon.code} — ${formatUsd(resolution.finalPrice)}',
      kind: StatusKind.ok,
      icon: Icons.check_circle_outline_rounded,
    );
  }
}
