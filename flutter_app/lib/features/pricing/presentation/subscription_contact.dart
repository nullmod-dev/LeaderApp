import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/external_links.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings.dart';
import '../../about/domain/support_contacts.dart';
import '../domain/billing_option.dart';
import 'pricing_copy.dart';

enum _SubscriptionContactKind { telegram, whatsApp, email }

class SubscriptionContactSection extends ConsumerWidget {
  const SubscriptionContactSection({
    super.key,
    required this.selectedOption,
  });

  final BillingOptionId selectedOption;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Container(
      key: const Key('pricing-contact-section'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.xl),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(S.pricingContactTitle,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(S.pricingContactBody,
            style: TextStyle(color: c.ink2, height: 1.5)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${S.pricingSelected}: ${PricingCopy.duration(selectedOption)}',
          style: TextStyle(color: c.ink2, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.md),
        const _ContactRow(
          kind: _SubscriptionContactKind.telegram,
          icon: Icons.send_rounded,
          label: S.pricingTelegram,
          value: supportTelegram,
        ),
        const SizedBox(height: AppSpacing.sm),
        const _ContactRow(
          kind: _SubscriptionContactKind.whatsApp,
          icon: Icons.chat_outlined,
          label: S.pricingWhatsApp,
          value: subscriptionWhatsApp,
        ),
        const SizedBox(height: AppSpacing.sm),
        const _ContactRow(
          kind: _SubscriptionContactKind.email,
          icon: Icons.mail_outline_rounded,
          label: S.pricingEmail,
          value: subscriptionEmail,
        ),
      ]),
    );
  }
}

class _ContactRow extends ConsumerStatefulWidget {
  const _ContactRow({
    required this.kind,
    required this.icon,
    required this.label,
    required this.value,
  });

  final _SubscriptionContactKind kind;
  final IconData icon;
  final String label;
  final String value;

  @override
  ConsumerState<_ContactRow> createState() => _ContactRowState();
}

class _ContactRowState extends ConsumerState<_ContactRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(widget.icon, size: 18, color: c.ink3),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(widget.label, style: TextStyle(color: c.ink3))),
        ]),
        const SizedBox(height: AppSpacing.xs),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SelectableText(widget.value),
          ),
        ),
        Wrap(spacing: AppSpacing.sm, children: [
          TextButton.icon(
            key: Key('pricing-open-${widget.kind.name}'),
            onPressed: _busy ? null : _open,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text(S.pricingOpen),
          ),
          TextButton.icon(
            key: Key('pricing-copy-${widget.kind.name}'),
            onPressed: _copy,
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text(S.copy),
          ),
        ]),
      ]),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(S.pricingContactCopied)),
    );
  }

  Future<void> _open() async {
    setState(() => _busy = true);
    final launcher = ref.read(externalLinkLauncherProvider);
    ExternalLinkOutcome outcome;
    switch (widget.kind) {
      case _SubscriptionContactKind.telegram:
        outcome = await launcher.open(telegramAppUri());
        if (outcome != ExternalLinkOutcome.opened) {
          outcome = await launcher.open(telegramWebUri());
        }
      case _SubscriptionContactKind.whatsApp:
        outcome = await launcher.open(whatsAppAppUri());
        if (outcome != ExternalLinkOutcome.opened) {
          outcome = await launcher.open(whatsAppWebUri());
        }
      case _SubscriptionContactKind.email:
        outcome = await launcher.open(subscriptionEmailUri());
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (outcome != ExternalLinkOutcome.opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(S.pricingContactUnsupported)),
      );
    }
  }
}
