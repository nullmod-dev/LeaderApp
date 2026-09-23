import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/app_number.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../../pricing/data/commerce_control_plane.dart';
import '../../pricing/data/pricing_catalog.dart';
import '../../pricing/domain/billing_option.dart';
import '../../pricing/domain/money.dart';
import '../../pricing/domain/promotion.dart';
import '../../pricing/presentation/pricing_copy.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../data/platform_commerce_providers.dart';
import 'platform_operations_routes.dart';
import 'widgets/platform_confirmation_dialog.dart';
import 'widgets/platform_meta.dart';
import 'widgets/platform_page.dart';

/// `/platform/operations/commerce` — what a customer is shown when they come
/// to subscribe: the base prices, the global offers and the coupons.
///
/// **Phase 2 rebuilt the surface, not the domain.** The 2026-09-19 UI audit
/// (P1-7) found the only screen in the product that announced it was not
/// real, a popup menu that offered the *state adjective* as the command
/// («معطّل» where «تعطيل» belongs), a `StatusChip` in `ListTile.leading` so
/// the enabled/disabled word sat in the avatar slot and every title started
/// on a ragged edge, two competing full-width create buttons mid-scroll, a
/// confirmation whose "what does not change" line was the page's own
/// description paragraph, and a permanent removal confirmed as a *warning*.
///
/// Every price, promotion rule and refusal below is untouched: $6 / $14 / $24
/// / $40, full access on every duration, promotions on one and three months
/// only, no stacking, no redemption, no payment.
class PlatformCommercePage extends ConsumerWidget {
  const PlatformCommercePage({super.key});

  static const routePath = PlatformOperationsRoutes.commerce;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(commerceControlPlaneProvider);
    return PlatformPage(
      title: S.platformCommerceTitle,
      children: [
        const PlatformPageIntro(lead: S.platformCommerceLead),
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(title: S.platformCommerceBasePrices),
        const _BasePrices(),
        SectionHeader(
          title: S.platformCommerceOffers,
          action: S.platformCommerceCreateOffer,
          actionIcon: Icons.add_rounded,
          actionKey: const Key('platform-commerce-create-offer'),
          onAction: () => context.push(PlatformOperationsRoutes.commerceOffer),
        ),
        if (state.offers.isEmpty)
          const _Empty(
            text: S.platformCommerceNoOffers,
            hint: S.platformCommerceNoOffersHint,
          )
        else
          SettingsSection(children: [
            for (final offer in state.offers) _OfferRow(offer: offer),
          ]),
        SectionHeader(
          title: S.platformCommerceCoupons,
          action: S.platformCommerceCreateCoupon,
          actionIcon: Icons.add_rounded,
          actionKey: const Key('platform-commerce-create-coupon'),
          onAction: () => context.push(PlatformOperationsRoutes.commerceCoupon),
        ),
        if (state.coupons.isEmpty)
          const _Empty(
            text: S.platformCommerceNoCoupons,
            hint: S.platformCommerceNoCouponsHint,
          )
        else
          SettingsSection(children: [
            for (final coupon in state.coupons) _CouponRow(coupon: coupon),
          ]),
        // The build caveat, kept because it is true and removing it would
        // claim a payment path that does not exist — but at the foot, at the
        // weight of a note. It used to be a warning chip directly under the
        // page title, which made the whole commercial panel read as a test
        // build.
        const SizedBox(height: AppSpacing.xl),
        const PlatformNoteCard(
          key: Key('platform-commerce-build-note'),
          title: S.platformCommerceDevOnly,
          body: S.platformCommerceDevOnlyNote,
        ),
      ],
    );
  }
}

/// The four durations, read-only.
///
/// **An admin view of product data, not a pricing page.** Four large marketing
/// cards would dominate a screen whose subject is the promotions below them;
/// these are label↔value rows with the effective monthly price as the one
/// derived figure an operator actually compares durations by.
///
/// The monthly equivalent is shown only where it differs from the total — on
/// the one-month option it would be the same number twice.
class _BasePrices extends ConsumerWidget {
  const _BasePrices();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final catalog = ref.watch(pricingCatalogProvider);
    return SettingsSection(children: [
      for (final option in catalog)
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      PricingCopy.duration(option.id),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (option.months > 1) ...[
                      const SizedBox(height: 2),
                      PlatformMeta(parts: [
                        PlatformMetaText(
                          '${S.platformCommerceMonthlyEquivalent} '
                          // Isolated, not direction-overridden: the figure
                          // sits inside an Arabic phrase here rather than
                          // alone in its own cell.
                          '${formatUsd(effectiveMonthlyPrice(
                            option.basePrice,
                            option.months,
                          ))}',
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // The price alone in its own cell: a direction override, which
              // is what the rest of the app uses for a standalone money value.
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  formatUsd(option.basePrice, isolate: false),
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: c.ink),
                ),
              ),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Text(
          S.platformCommerceBasePricesNote,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: c.ink3, height: 1.5),
        ),
      ),
    ]);
  }
}

/// One global offer.
///
/// Title first — never the generated id — then the facts an operator compares
/// offers by on one metadata line, then the state as a trailing chip and the
/// actions behind one labelled menu.
class _OfferRow extends ConsumerWidget {
  const _OfferRow({required this.offer});

  final GlobalOffer offer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(pricingCatalogProvider);
    return _CommerceRow(
      rowKey: Key('platform-offer-${offer.id}'),
      title: Text(
        offer.title ?? S.pricingSpecialOffer,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      enabled: offer.enabled,
      meta: _promotionMeta(
        catalog: catalog,
        target: offer.target,
        discount: offer.discount,
      ),
      menuTooltip: S.platformCommerceRowActions,
      removeLabel: S.platformCommerceRemoveOffer,
      onEdit: () =>
          context.push('${PlatformOperationsRoutes.commerceOffer}/${offer.id}'),
      onToggle: () => _toggle(context, ref),
      onRemove: () => _remove(context, ref),
    );
  }

  String get _identity => offer.title ?? PricingCopy.duration(offer.target);

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final turningOn = !offer.enabled;
    final confirmed = await showPlatformConfirmationSpec(
      context: context,
      title: turningOn
          ? S.platformCommerceEnableTitle
          : S.platformCommerceDisableTitle,
      identity: _identity,
      change: turningOn
          ? S.platformCommerceEnableChange
          : S.platformCommerceDisableChange,
      unchanged: S.platformCommerceUnchanged,
      confirmLabel:
          turningOn ? S.platformCommerceEnable : S.platformCommerceDisable,
      severity: turningOn
          ? PlatformConfirmationSeverity.normal
          : PlatformConfirmationSeverity.warning,
    );
    if (!confirmed || !context.mounted) return;
    _report(
      context,
      ref.read(platformCommerceActionsProvider).setOfferEnabled(
            offer.id,
            turningOn,
          ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    // `destructive`, not `warning`: removing an offer cannot be undone from
    // this screen, and the audit found it confirmed at the same weight as
    // switching it off.
    final confirmed = await showPlatformConfirmationSpec(
      context: context,
      title: S.platformCommerceRemoveTitle,
      identity: _identity,
      change: S.platformCommerceRemoveChange,
      unchanged: S.platformCommerceUnchanged,
      confirmLabel: S.platformCommerceRemoveOffer,
      severity: PlatformConfirmationSeverity.destructive,
    );
    if (!confirmed || !context.mounted) return;
    _report(
      context,
      ref.read(platformCommerceActionsProvider).removeOffer(offer.id),
    );
  }
}

/// One coupon.
///
/// The code is the identity, so it leads — inside a left-to-right isolate, so
/// `SUMMER20` keeps its own order without dragging the Arabic around it out of
/// place. Whether it is public or bound to one account is a chip, because it
/// changes who can use it.
class _CouponRow extends ConsumerWidget {
  const _CouponRow({required this.coupon});

  final Coupon coupon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(pricingCatalogProvider);
    final targeted = coupon.assignment is CouponAssignmentAccount;
    return _CommerceRow(
      rowKey: Key('platform-coupon-${coupon.id}'),
      title: Text(
        '\u2066${coupon.code}\u2069',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      enabled: coupon.enabled,
      leadingChips: [
        StatusChip(
          kind: targeted ? StatusKind.info : StatusKind.muted,
          label: targeted
              ? S.platformCommerceTargetedShort
              : S.platformCommercePublicShort,
        ),
      ],
      meta: [
        ..._promotionMeta(
          catalog: catalog,
          target: coupon.target,
          discount: coupon.discount,
        ),
        // The account a targeted coupon belongs to is an identifier, so it is
        // labelled and isolated rather than printed as a bare slug.
        if (coupon.assignment case CouponAssignmentAccount(:final accountId))
          // Only the identifier is isolated. Isolating the whole phrase lays
          // «الحساب:» out left-to-right and prints the colon on the wrong side
          // of the Arabic word.
          PlatformMetaText(
            '${S.platformCommerceAccountShort}: \u2066$accountId\u2069',
          ),
      ],
      menuTooltip: S.platformCommerceRowActions,
      removeLabel: S.platformCommerceRemoveCoupon,
      onEdit: () => context
          .push('${PlatformOperationsRoutes.commerceCoupon}/${coupon.id}'),
      onToggle: () => _toggle(context, ref),
      onRemove: () => _remove(context, ref),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final turningOn = !coupon.enabled;
    final confirmed = await showPlatformConfirmationSpec(
      context: context,
      title: turningOn
          ? S.platformCommerceEnableTitle
          : S.platformCommerceDisableTitle,
      identity: coupon.code,
      identityLtr: true,
      change: turningOn
          ? S.platformCommerceEnableChange
          : S.platformCommerceDisableChange,
      unchanged: S.platformCommerceUnchanged,
      confirmLabel:
          turningOn ? S.platformCommerceEnable : S.platformCommerceDisable,
      severity: turningOn
          ? PlatformConfirmationSeverity.normal
          : PlatformConfirmationSeverity.warning,
    );
    if (!confirmed || !context.mounted) return;
    _report(
      context,
      ref.read(platformCommerceActionsProvider).setCouponEnabled(
            coupon.id,
            turningOn,
          ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showPlatformConfirmationSpec(
      context: context,
      title: S.platformCommerceRemoveTitle,
      identity: coupon.code,
      identityLtr: true,
      change: S.platformCommerceRemoveChange,
      unchanged: S.platformCommerceUnchanged,
      confirmLabel: S.platformCommerceRemoveCoupon,
      severity: PlatformConfirmationSeverity.destructive,
    );
    if (!confirmed || !context.mounted) return;
    _report(
      context,
      ref.read(platformCommerceActionsProvider).removeCoupon(coupon.id),
    );
  }
}

/// The shape both lists share: identity and state on the first line, the
/// comparable facts on the second, one labelled menu at the end.
class _CommerceRow extends StatelessWidget {
  const _CommerceRow({
    required this.rowKey,
    required this.title,
    required this.enabled,
    required this.meta,
    required this.menuTooltip,
    required this.removeLabel,
    required this.onEdit,
    required this.onToggle,
    required this.onRemove,
    this.leadingChips = const [],
  });

  final Key rowKey;
  final Widget title;
  final bool enabled;
  final List<Widget> meta;
  final List<Widget> leadingChips;
  final String menuTooltip;
  final String removeLabel;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: rowKey,
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Wrap, not Row: at a 1.6 text scale the state chip drops
                // under the title instead of crushing it.
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    title,
                    ...leadingChips,
                    StatusChip(
                      kind: enabled ? StatusKind.ok : StatusKind.muted,
                      label: enabled
                          ? S.platformCommerceEnabled
                          : S.platformCommerceDisabled,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                PlatformMeta(parts: meta),
              ],
            ),
          ),
          PopupMenuButton<_RowAction>(
            // The audit's fifth unlabelled control on this surface: a bare
            // `more_vert` with no accessible name.
            tooltip: menuTooltip,
            onSelected: (action) => switch (action) {
              _RowAction.edit => onEdit(),
              _RowAction.toggle => onToggle(),
              _RowAction.remove => onRemove(),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: _RowAction.edit, child: Text(S.edit)),
              PopupMenuItem(
                value: _RowAction.toggle,
                // A verb, because a menu item is a command. The adjective
                // belongs on the chip above, where it already is.
                child: Text(
                  enabled
                      ? S.platformCommerceDisable
                      : S.platformCommerceEnable,
                ),
              ),
              PopupMenuItem(
                value: _RowAction.remove,
                child: Text(
                  removeLabel,
                  style: TextStyle(color: context.c.crit),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _RowAction { edit, toggle, remove }

/// The comparable facts of a promotion: which duration it applies to, what it
/// takes off, and what the customer would pay.
List<Widget> _promotionMeta({
  required List<BillingOption> catalog,
  required BillingOptionId target,
  required Discount discount,
}) {
  final option = billingOptionById(catalog, target);
  return [
    PlatformMetaText(PricingCopy.duration(target)),
    PlatformMetaText(switch (discount) {
      PercentageDiscount(:final percent) =>
        '${S.platformCommerceDiscountLabel} ${AppNumber.percent(percent)}',
      FixedFinalPriceDiscount() => S.platformCommerceFixedPrice,
    }),
    if (option != null)
      PlatformMetaText(
        '${S.platformCommerceFinalPrice} '
        '${formatUsd(applyDiscount(discount, option.basePrice))}',
        emphasis: true,
      ),
  ];
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text, required this.hint});

  final String text;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            hint,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: c.ink3, height: 1.5),
          ),
        ],
      ),
    );
  }
}

void _report<T>(BuildContext context, Result<T> result) {
  final message = result.when(
    success: (_, {stale = false}) => S.platformCommerceSaved,
    failure: (_, code) => switch (code) {
      CommerceCodes.offerConflict => S.platformCommerceConflict,
      CommerceCodes.couponCodeTaken => S.platformCommerceCodeTaken,
      _ => S.platformCommerceInvalid,
    },
    offline: (_) => S.platformCommerceInvalid,
  );
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
