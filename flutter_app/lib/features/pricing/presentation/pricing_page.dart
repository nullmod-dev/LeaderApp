import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/reading_column.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../../shell/main_shell.dart';
import '../data/pricing_providers.dart';
import 'pricing_copy.dart';
import 'pricing_widgets.dart';
import 'subscription_contact.dart';

class PricingPage extends ConsumerWidget {
  const PricingPage({super.key});

  static const routePath = '/more/pricing';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final quotes = ref.watch(priceQuotesProvider);
    final selected = ref.watch(selectedBillingOptionProvider);
    final offers = ref.watch(liveGlobalOffersProvider);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text(S.pricingTitle)),
      // One column of label↔value rows: capped at the reading measure so a
      // tablet gains margins instead of a row whose label and value sit at
      // opposite ends of the window. Below 520 dp nothing changes.
      body: FloatingNavPadding(
        child: ReadingColumn(
            child: ListView(
          key: const Key('pricing-page'),
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const _PricingIntro(),
            if (offers.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              PricingOfferBanner(
                label: PricingCopy.promotion(
                  offers.values.first.discount,
                  title: offers.values.first.title,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            PricingColumns(
              primary: Column(children: [
                for (var index = 0; index < quotes.length; index++) ...[
                  PlanCard(
                    quote: quotes[index],
                    selected: selected == quotes[index].option.id,
                    onSelected: () => ref
                        .read(selectedBillingOptionProvider.notifier)
                        .state = quotes[index].option.id,
                  ),
                  if (index != quotes.length - 1)
                    const SizedBox(height: AppSpacing.sm),
                ],
              ]),
              secondary: Column(children: [
                const CouponSection(),
                const SizedBox(height: AppSpacing.lg),
                SubscriptionContactSection(selectedOption: selected),
              ]),
            ),
          ],
        )),
      ),
    );
  }
}

class _PricingIntro extends StatelessWidget {
  const _PricingIntro();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(S.pricingIntroTitle,
          style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: AppSpacing.sm),
      Text(S.pricingIntro, style: TextStyle(color: c.ink2, height: 1.6)),
      const SizedBox(height: AppSpacing.sm),
      const StatusChip(
        kind: StatusKind.info,
        label: S.pricingFullAccess,
        icon: Icons.check_circle_outline_rounded,
      ),
    ]);
  }
}
