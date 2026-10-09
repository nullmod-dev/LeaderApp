import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion_tokens.dart';
import '../../../core/platform/external_links.dart';
import '../../../core/text/bidi.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/forward_chevron.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../l10n/strings.dart';
import '../domain/support_contacts.dart';

/// The ways to reach support, and the step that hands the person over to one.
///
/// **Two surfaces, one flow.** `/more/about` lists the contacts inline; every
/// screen that has no About to link to — the sign-in screen, the blocked
/// session states, the onboarding exits — opens [showSupportSheet]. Both ask
/// the same question before a social app opens ([SupportHandoffPanel]), so
/// leaving Leader for WhatsApp or Telegram is always a choice the person made
/// on a screen that said where they were going.
///
/// **Mail is not asked about.** A `mailto:` opens a composer the person still
/// has to fill in and send; nothing has left the device yet, so a question in
/// front of it would only be a second tap.
enum SupportChannel {
  whatsApp,
  telegram,
  email;

  String get label => switch (this) {
        SupportChannel.whatsApp => S.aboutSupportWhatsAppLabel,
        SupportChannel.telegram => S.aboutSupportTelegramLabel,
        SupportChannel.email => S.aboutSupportEmailLabel,
      };

  /// The contact exactly as it is displayed and copied.
  String get value => switch (this) {
        SupportChannel.whatsApp => supportWhatsApp,
        SupportChannel.telegram => supportTelegram,
        SupportChannel.email => supportEmail,
      };

  IconData get icon => switch (this) {
        SupportChannel.whatsApp => Icons.chat_outlined,
        SupportChannel.telegram => Icons.telegram,
        SupportChannel.email => Icons.mail_outline_rounded,
      };

  /// Whether leaving for this channel is asked about first.
  bool get asksFirst => this != SupportChannel.email;

  /// The links tried in order: the app first, then the web fallback that a
  /// device without the app still handles.
  List<Uri> get attempts => switch (this) {
        SupportChannel.whatsApp => [
            supportWhatsAppAppUri(),
            supportWhatsAppWebUri(),
          ],
        SupportChannel.telegram => [telegramAppUri(), telegramWebUri()],
        SupportChannel.email => [emailUri()],
      };

  String get copiedMessage => switch (this) {
        SupportChannel.whatsApp => S.aboutWhatsAppCopied,
        SupportChannel.telegram => S.aboutTelegramCopied,
        SupportChannel.email => S.aboutEmailCopied,
      };

  /// Said when nothing on the device opens this channel.
  String get unsupportedMessage => switch (this) {
        SupportChannel.whatsApp => S.aboutWhatsAppUnsupported,
        SupportChannel.telegram => S.aboutTelegramUnsupported,
        SupportChannel.email => S.aboutEmailUnsupported,
      };

  String get handoffTitle => switch (this) {
        SupportChannel.whatsApp => S.supportHandoffWhatsAppTitle,
        _ => S.supportHandoffTelegramTitle,
      };

  String get handoffBody => switch (this) {
        SupportChannel.whatsApp => S.supportHandoffWhatsAppBody,
        _ => S.supportHandoffTelegramBody,
      };

  String get handoffConfirm => switch (this) {
        SupportChannel.whatsApp => S.supportHandoffWhatsAppConfirm,
        _ => S.supportHandoffTelegramConfirm,
      };

  /// The sentence for an outcome that did not open anything.
  String failureMessage(ExternalLinkOutcome outcome) =>
      outcome == ExternalLinkOutcome.unsupported
          ? unsupportedMessage
          : S.aboutLaunchFailed;
}

/// Hands [channel] to the platform: each of its links in turn until one opens.
///
/// A fallback is only tried after a miss, so a phone with WhatsApp installed
/// never sees the browser flash `wa.me` first.
Future<ExternalLinkOutcome> openSupportChannel(
  ExternalLinkLauncher launcher,
  SupportChannel channel,
) async {
  var outcome = ExternalLinkOutcome.unsupported;
  for (final uri in channel.attempts) {
    outcome = await launcher.open(uri);
    if (outcome == ExternalLinkOutcome.opened) break;
  }
  return outcome;
}

/// Asks before leaving for WhatsApp or Telegram, and does the hand-off on
/// «نعم». Completes with `true` once the other app opened; `false` when the
/// person stayed. A failed hand-off is said inside the sheet, which stays up
/// with the contact ready to copy.
Future<bool> confirmSupportHandoff(
  BuildContext context,
  SupportChannel channel,
) async {
  assert(channel.asksFirst, 'mail opens directly');
  final opened = await showAppSheet<bool>(
    context: context,
    title: S.contactSupport,
    child: Builder(
      builder: (sheet) => SupportHandoffPanel(
        channel: channel,
        cancelLabel: S.supportHandoffCancel,
        onCancel: () => Navigator.of(sheet).pop(false),
        onOpened: () => Navigator.of(sheet).pop(true),
      ),
    ),
  );
  return opened ?? false;
}

/// «تواصل مع الدعم» as a sheet: every channel, and the hand-off question
/// in place when a social one is chosen.
///
/// A sheet rather than a route on purpose: the screens that open it — the
/// sign-in form, a blocked session state — must not build the tenant shell
/// `/more/about` lives in, and a dismissal returns the person to exactly the
/// screen they left.
Future<void> showSupportSheet(BuildContext context) => showAppSheet<void>(
      context: context,
      title: S.contactSupport,
      child: const _SupportSheetBody(),
    );

class _SupportSheetBody extends StatefulWidget {
  const _SupportSheetBody();

  @override
  State<_SupportSheetBody> createState() => _SupportSheetBodyState();
}

class _SupportSheetBodyState extends State<_SupportSheetBody> {
  /// The social channel waiting on the hand-off question, or null while the
  /// list is showing.
  SupportChannel? _picked;

  @override
  Widget build(BuildContext context) {
    final picked = _picked;
    final Widget content = picked == null
        ? _ChannelList(
            key: const ValueKey('support-list'),
            onPicked: (channel) => setState(() => _picked = channel),
          )
        : SupportHandoffPanel(
            key: ValueKey('support-handoff-${picked.name}'),
            channel: picked,
            // Back to the list, not out of the sheet: the person may have
            // tapped the wrong row.
            cancelLabel: S.back,
            onCancel: () => setState(() => _picked = null),
            onOpened: () => Navigator.of(context).pop(),
          );
    return SingleChildScrollView(
      key: const Key('support-sheet'),
      child: AnimatedSize(
        alignment: Alignment.topCenter,
        duration: effectiveDuration(context, MotionTokens.medium),
        curve: effectiveCurve(context, MotionTokens.emphasized),
        child: AnimatedSwitcher(
          duration: effectiveDuration(context, MotionTokens.short),
          switchInCurve: effectiveCurve(context, MotionTokens.enter),
          switchOutCurve: effectiveCurve(context, MotionTokens.exit),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, if (current != null) current],
          ),
          child: content,
        ),
      ),
    );
  }
}

/// The three contacts as rows. WhatsApp and Telegram ask before leaving;
/// mail opens the composer straight away.
class _ChannelList extends ConsumerStatefulWidget {
  const _ChannelList({super.key, required this.onPicked});

  final ValueChanged<SupportChannel> onPicked;

  @override
  ConsumerState<_ChannelList> createState() => _ChannelListState();
}

class _ChannelListState extends ConsumerState<_ChannelList> {
  bool _busy = false;
  String? _error;

  Future<void> _tap(SupportChannel channel) async {
    if (channel.asksFirst) {
      widget.onPicked(channel);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await openSupportChannel(
        ref.read(externalLinkLauncherProvider), channel);
    if (!mounted) return;
    if (outcome == ExternalLinkOutcome.opened) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = channel.failureMessage(outcome);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            S.aboutSupportBody,
            style: TextStyle(color: c.ink2, fontSize: 13.5, height: 1.6),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final channel in SupportChannel.values) ...[
            _ChannelRow(
              channel: channel,
              enabled: !_busy,
              onTap: () => _tap(channel),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (_error case final error?)
            _InlineError(key: const Key('support-list-error'), message: error),
        ],
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.channel,
    required this.enabled,
    required this.onTap,
  });

  final SupportChannel channel;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('support-channel-${channel.name}'),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md, AppSpacing.md, AppSpacing.sm, AppSpacing.md),
          child: Row(
            children: [
              _ChannelBadge(channel: channel, size: 40),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.label,
                      style: TextStyle(
                        color: c.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // A number, a handle or an address: its own order, inside
                    // the Arabic row.
                    Text(
                      Bidi.ltr(channel.value),
                      style: TextStyle(color: c.ink3, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const ForwardChevron(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The question asked before WhatsApp or Telegram opens: where the person is
/// going, which account they will land on, and a plain yes / not now.
class SupportHandoffPanel extends ConsumerStatefulWidget {
  const SupportHandoffPanel({
    super.key,
    required this.channel,
    required this.cancelLabel,
    required this.onCancel,
    required this.onOpened,
  });

  final SupportChannel channel;

  /// «ليس الآن» in a sheet of its own; «رجوع» inside the support sheet.
  final String cancelLabel;
  final VoidCallback onCancel;

  /// The other app took the link.
  final VoidCallback onOpened;

  @override
  ConsumerState<SupportHandoffPanel> createState() =>
      _SupportHandoffPanelState();
}

class _SupportHandoffPanelState extends ConsumerState<SupportHandoffPanel> {
  /// Guards a second tap while the platform is still deciding: two taps on a
  /// slow hand-off would otherwise open the chat twice.
  bool _busy = false;
  String? _error;
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await openSupportChannel(
        ref.read(externalLinkLauncherProvider), widget.channel);
    if (!mounted) return;
    if (outcome == ExternalLinkOutcome.opened) {
      // Nothing is said on success: the person is already in the other app.
      widget.onOpened();
      return;
    }
    setState(() {
      _busy = false;
      _error = widget.channel.failureMessage(outcome);
    });
  }

  /// Copies the value exactly as displayed. Confirmed in place, not with a
  /// SnackBar: one would land on the screen under this sheet, behind it.
  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.channel.value));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    final channel = widget.channel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: _ChannelBadge(channel: channel, size: 56)),
          const SizedBox(height: AppSpacing.md),
          Semantics(
            header: true,
            child: Text(
              channel.handoffTitle,
              textAlign: TextAlign.center,
              style: t.titleMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            channel.handoffBody,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.ink2, fontSize: 13.5, height: 1.6),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.supportHandoffAccount,
                        style: TextStyle(color: c.ink3, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: SelectableText(
                            channel.value,
                            key: Key('support-handoff-value-${channel.name}'),
                            style: TextStyle(
                              color: c.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Semantics(
                  liveRegion: _copied,
                  child: IconButton(
                    key: Key('support-handoff-copy-${channel.name}'),
                    tooltip: _copied ? S.copied : S.copy,
                    onPressed: _copy,
                    icon: AnimatedSwitcher(
                      duration: effectiveDuration(context, MotionTokens.short),
                      child: Icon(
                        _copied ? Icons.check_rounded : Icons.copy_rounded,
                        key: ValueKey(_copied),
                        size: 20,
                        color: _copied ? c.ok : c.ink3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: AppSpacing.sm),
            _InlineError(
              key: const Key('support-handoff-error'),
              message: error,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            key: const Key('support-handoff-confirm'),
            onPressed: _busy ? null : _confirm,
            child: _busy
                ? SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.primaryInk,
                    ),
                  )
                : Text(channel.handoffConfirm),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            key: const Key('support-handoff-cancel'),
            onPressed: _busy ? null : widget.onCancel,
            child: Text(widget.cancelLabel),
          ),
        ],
      ),
    );
  }
}

/// The channel's glyph on a tinted disc. Decoration only: the row or the
/// question beside it always names the channel in words.
class _ChannelBadge extends StatelessWidget {
  const _ChannelBadge({required this.channel, required this.size});

  final SupportChannel channel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: c.primaryTint, shape: BoxShape.circle),
        child: Icon(channel.icon, color: c.primary, size: size * 0.5),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.error_outline_rounded, size: 16, color: c.crit),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: c.crit, fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
