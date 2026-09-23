import 'package:flutter/material.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/strings.dart';
import '../../../pricing/domain/money.dart';
import '../../../pricing/domain/promotion.dart';
import 'platform_meta.dart';

/// The parts the offer and the coupon editors share.
///
/// They are the same form with one extra section, and before Phase 2 they were
/// two copies of the same hand-built column — including the same
/// `SwitchListTile` whose title and subtitle both read «مفعّل», and the same
/// lone save button with no way back.

/// A row of form choices that wraps.
///
/// Not an `AppFilterBar`: these are *values* on a form, and the shared filter
/// control means "narrow the list below". Dressing a value as a filter is how
/// somebody changes what an offer applies to while believing they changed what
/// they are looking at.
class CommerceChoiceRow extends StatelessWidget {
  const CommerceChoiceRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: children,
      );
}

/// A quiet sentence under a control, for a rule the form enforces anyway.
class CommerceFormNote extends StatelessWidget {
  const CommerceFormNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: context.c.ink3, height: 1.5),
        ),
      );
}

/// What the customer would pay, computed from the form as it stands.
///
/// **Display only.** It calls the same `applyDiscount` the domain already
/// exposes; no pricing rule lives here. An operator typing «٢٠» into a
/// percentage field is deciding a price, and a control panel that makes them
/// do the arithmetic in their head is the reason fixed-price offers get typed
/// as percentages.
class CommercePricePreview extends StatelessWidget {
  const CommercePricePreview({
    super.key,
    required this.base,
    required this.discount,
  });

  final Money? base;
  final Discount? discount;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final value = base == null || discount == null
        ? null
        : applyDiscount(discount!, base!);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            S.platformCommercePreview,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          if (value == null)
            Text(
              S.platformCommerceInvalid,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: c.ink3),
            )
          else
            PlatformMeta(parts: [
              PlatformMetaText(
                '${S.platformCommerceBasePrice} ${formatUsd(base!)}',
              ),
              PlatformMetaText(
                '${S.platformCommerceFinalPrice} ${formatUsd(value)}',
                color: c.ink,
                emphasis: true,
              ),
            ]),
        ],
      ),
    );
  }
}

/// The availability switch, with its state said once in words underneath.
///
/// The editors used to title this switch «مفعّل» and subtitle it «مفعّل» or
/// «معطّل» — the same adjective twice, one of which was the label and one of
/// which was the state.
class CommerceAvailabilityCard extends StatelessWidget {
  const CommerceAvailabilityCard({
    super.key,
    required this.switchKey,
    required this.enabled,
    required this.onChanged,
  });

  final Key switchKey;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // A `Material`, not a decorated box: a `ListTile` paints its ink on the
    // nearest `Material` ancestor, and a `BoxDecoration` in between hides the
    // splash — the same reasoning `SettingsSection` carries.
    return Material(
      color: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: BorderSide(color: c.line),
      ),
      child: SwitchListTile.adaptive(
        key: switchKey,
        value: enabled,
        onChanged: onChanged,
        title: const Text(S.platformCommerceSectionAvailability),
        subtitle: Text(
          enabled
              ? S.platformCommerceAvailabilityOn
              : S.platformCommerceAvailabilityOff,
          style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
        ),
        contentPadding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.xs,
        ),
      ),
    );
  }
}

/// One primary action and one way back.
///
/// Side by side above 360 dp of form, stacked below it — and the cancel is a
/// `TextButton`, so the two never read as a pair of equal choices.
class CommerceFormActions extends StatelessWidget {
  const CommerceFormActions({
    super.key,
    required this.saveKey,
    required this.onSave,
    required this.onCancel,
  });

  final Key saveKey;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final save = FilledButton.icon(
      key: saveKey,
      onPressed: onSave,
      icon: const Icon(Icons.save_outlined),
      label: const Text(S.save),
    );
    final cancel = TextButton(
      onPressed: onCancel,
      child: const Text(S.cancel),
    );
    return LayoutBuilder(builder: (context, constraints) {
      // 320 dp of form, not 360: a 390 dp phone leaves this row 358 dp, which
      // is enough for a primary button and a one-word text button beside it.
      if (constraints.maxWidth < 320) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            save,
            const SizedBox(height: AppSpacing.sm),
            Align(alignment: AlignmentDirectional.center, child: cancel),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: save),
          const SizedBox(width: AppSpacing.sm),
          cancel,
        ],
      );
    });
  }
}
