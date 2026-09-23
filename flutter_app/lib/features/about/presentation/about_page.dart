import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info.dart';
import '../../../core/platform/external_links.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/made_in_iraq.dart';
import '../../../l10n/strings.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../../shell/main_shell.dart';
import '../domain/support_contacts.dart';

/// About & support (`/more/about`) — one screen, three blocks.
///
/// **One page, not three.** About, Support and Contact Us are the same
/// question asked by the same person at the same moment: *what is this, which
/// build am I on, and how do I reach somebody*. Splitting them would put two
/// taps between a confused administrator and a mail address.
///
/// **Nothing here is fetched and nothing here is claimed.** The identity is
/// static, the version comes from [AppInfo] — the same constants the
/// forced-upgrade screen renders, held to `pubspec.yaml` by a drift test — and
/// the capability list names only features this build actually ships. There is
/// no uptime figure, no security claim and no "your data is safe": this client
/// has no backend behind it, so any such sentence would be a promise nobody
/// made.
///
/// **Support is a mail address and a Telegram username.** There is no ticket
/// system, no form and no submission endpoint (see `support_contacts.dart`).
/// Each contact offers two actions — open, and copy — and the copy is not a
/// consolation prize: it is the action that always works, on a device with no
/// mail client, in a screenshot, or when the handoff fails.
///
/// **Privacy Policy and Terms of Use are deliberately absent.** They are
/// deferred until the backend's real data handling is known; a placeholder row
/// leading nowhere, or invented legal text, would be worse than their absence.
/// `DATA-NEEDS.md` records the requirement.
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  static const routePath = '/more/about';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text(S.aboutTitle)),
      body: FloatingNavPadding(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: const [
            _Identity(),
            SectionLabel(S.aboutCapabilities),
            _Capabilities(),
            SectionLabel(S.aboutAppInfo),
            _BuildInfo(),
            SectionLabel(S.aboutSupport),
            _Support(),
            // Last, after everything the screen was opened to find. The
            // product signs itself off here; nothing follows it.
            MadeInIraqFooter(),
          ],
        ),
      ),
    );
  }
}

/// The mark, the name, and one sentence saying what Leader is.
///
/// A modest header, not a hero: this screen is opened to find a version number
/// or an address, and a full-bleed splash would push both below the fold on a
/// small phone.
class _Identity extends StatelessWidget {
  const _Identity();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      children: [
        // The existing mark — reused, never re-invented.
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.xxl),
          child: Image.asset(
            AppInfo.logoAsset,
            width: 72,
            height: 72,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // The Arabic product name follows the screen's ambient RTL direction.
        const Text(
          S.aboutAppName,
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        // The English product name keeps its natural Latin direction.
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            S.aboutAppFullName,
            style: TextStyle(color: c.ink2, fontSize: 13),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          S.aboutDescription,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.ink2, fontSize: 14, height: 1.7),
        ),
      ],
    );
  }
}

/// What the app does, as ten short phrases.
///
/// Every one names a module that exists in this build — including «صلاحيات
/// محدّدة حسب الدور», which is a design property the capability system really
/// enforces rather than a security assurance nobody here could back. A `Wrap`,
/// so the phrases reflow rather than clip at 320dp or at a large text scale.
class _Capabilities extends StatelessWidget {
  const _Capabilities();

  static const _items = <String>[
    S.aboutCapabilityDetachments,
    S.aboutCapabilityShifts,
    S.aboutCapabilityTeam,
    S.aboutCapabilityWorkshops,
    S.aboutCapabilityAttendance,
    S.aboutCapabilityStorage,
    S.aboutCapabilityStats,
    S.aboutCapabilitySync,
    S.aboutCapabilityRoles,
    S.aboutCapabilityArabic,
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final item in _items)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              item,
              style: TextStyle(color: c.ink2, fontSize: 13),
            ),
          ),
      ],
    );
  }
}

/// The installed version and build number, from [AppInfo] and nowhere else.
class _BuildInfo extends StatelessWidget {
  const _BuildInfo();

  @override
  Widget build(BuildContext context) => const SettingsSection(children: [
        _InfoRow(
          key: Key('about-version'),
          label: S.appVersion,
          value: AppInfo.version,
        ),
        _InfoRow(
          key: Key('about-build'),
          label: S.aboutBuildNumber,
          // Derived from `AppInfo.buildIdentity`, so there is one version
          // source in the app and About cannot drift from the upgrade gate.
          value: null,
        ),
      ]);
}

/// One label/value line. A technical value is Latin-digit and forced LTR,
/// exactly as the forced-upgrade screen already renders a version.
class _InfoRow extends StatelessWidget {
  const _InfoRow({super.key, required this.label, required this.value});

  final String label;

  /// Null means "read `AppInfo.buildNumber`" — a getter cannot be a `const`
  /// argument, and this row is built inside a `const` list.
  final String? value;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: c.ink3, fontSize: 13)),
          ),
          const SizedBox(width: AppSpacing.md),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              value ?? AppInfo.buildNumber,
              style: AppTypography.digits(c.ink, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// The two approved ways to reach support.
class _Support extends StatelessWidget {
  const _Support();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.aboutSupportBody,
          style: TextStyle(color: c.ink3, fontSize: 13, height: 1.6),
        ),
        const SizedBox(height: AppSpacing.sm),
        const _ContactCard(
          key: Key('about-email'),
          icon: Icons.mail_outline_rounded,
          label: S.aboutSupportEmailLabel,
          value: supportEmail,
          openLabel: S.aboutSupportEmailAction,
          kind: _ContactKind.email,
        ),
        const SizedBox(height: AppSpacing.sm),
        const _ContactCard(
          key: Key('about-telegram'),
          icon: Icons.send_rounded,
          label: S.aboutSupportTelegramLabel,
          value: supportTelegram,
          openLabel: S.aboutSupportTelegramAction,
          kind: _ContactKind.telegram,
        ),
      ],
    );
  }
}

enum _ContactKind { email, telegram }

/// One contact: what it is, the address itself, and two actions.
///
/// Stateful for one reason — [_busy]. `launchUrl` is asynchronous, and a
/// double tap on a slow handoff would ask the platform to open two mail
/// composers. The flag is the guard; the disabled button is only what the
/// user sees.
class _ContactCard extends ConsumerStatefulWidget {
  const _ContactCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.openLabel,
    required this.kind,
  });

  final IconData icon;
  final String label;
  final String value;
  final String openLabel;
  final _ContactKind kind;

  @override
  ConsumerState<_ContactCard> createState() => _ContactCardState();
}

class _ContactCardState extends ConsumerState<_ContactCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(widget.icon, size: 18, color: c.ink3),
              const SizedBox(width: AppSpacing.sm),
              // Flexible, not fixed: «البريد الإلكتروني» at a 1.5× text scale
              // on a 320dp phone is wider than the card, and a clipped label
              // is how a caption stops naming the value beneath it.
              Flexible(
                child: Text(
                  widget.label,
                  style: TextStyle(color: c.ink3, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // An address and a Telegram handle are Latin identifiers. Forced
          // LTR and selectable: the value is the thing the user came for, and
          // on a device where nothing launches, reading it off the screen is
          // the fallback behind the fallback.
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: SelectableText(
                widget.value,
                style: TextStyle(color: c.ink, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // A Wrap, not a Row: «مراسلة عبر البريد» beside «نسخ» does not fit a
          // 320dp phone at a large text scale, and two buttons on two lines
          // beat one clipped off the edge.
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              FilledButton.tonal(
                key: Key('about-open-${widget.kind.name}'),
                onPressed: _busy ? null : _open,
                child: Text(widget.openLabel),
              ),
              TextButton.icon(
                key: Key('about-copy-${widget.kind.name}'),
                onPressed: _copy,
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text(S.copy),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Copies the value exactly as it is displayed — `@jjkkkj` with its `@`,
  /// the address with no subject appended. What is copied is what is on
  /// screen; anything else would be a surprise in someone's paste buffer.
  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.kind == _ContactKind.email
              ? S.aboutEmailCopied
              : S.aboutTelegramCopied,
        ),
      ),
    );
  }

  Future<void> _open() async {
    setState(() => _busy = true);
    final launcher = ref.read(externalLinkLauncherProvider);

    ExternalLinkOutcome outcome;
    if (widget.kind == _ContactKind.email) {
      outcome = await launcher.open(emailUri());
    } else {
      // The app first, then the browser. A device without Telegram installed
      // has nothing registered for `tg:`, and `https://t.me/…` is handled by
      // anything with a browser — so the fallback is a real second chance,
      // not a second guess at the same door.
      outcome = await launcher.open(telegramAppUri());
      if (outcome != ExternalLinkOutcome.opened) {
        outcome = await launcher.open(telegramWebUri());
      }
    }

    if (!mounted) return;
    setState(() => _busy = false);

    // Nothing is said on success: the user is already looking at another app.
    // Claiming «تم الإرسال» would be the lie this screen exists to avoid.
    if (outcome == ExternalLinkOutcome.opened) return;

    final message = switch (outcome) {
      ExternalLinkOutcome.unsupported => widget.kind == _ContactKind.email
          ? S.aboutEmailUnsupported
          : S.aboutTelegramUnsupported,
      _ => S.aboutLaunchFailed,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
