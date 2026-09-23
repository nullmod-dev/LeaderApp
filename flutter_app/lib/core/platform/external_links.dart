/// The app's **only** door out to another application.
///
/// Every place that hands the user off — the support address on `/more/about`
/// today, an update destination or a map link later — goes through this one
/// object. The reason is not tidiness: `launchUrl` is a plugin call that
/// throws on some platforms, silently returns `false` on others, and cannot be
/// exercised in a widget test at all. Scattered through widgets it becomes a
/// behaviour nobody can test and everybody re-implements slightly differently.
/// Here it is one seam a test overrides with a fake, and the screens are
/// written against [ExternalLinkOutcome] rather than against a plugin.
///
/// It deliberately knows nothing about *what* is being opened. Building the
/// right `mailto:` or Telegram URI is a domain question and lives with the
/// contacts (`features/about/domain/support_contacts.dart`).
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// What an attempt to leave the app actually did.
///
/// Three values, and the distinction between the last two is the one that
/// matters to the user: "this device has nothing that opens a mail address"
/// is a permanent fact they can work around by copying, while "the handoff
/// failed" is worth trying again.
enum ExternalLinkOutcome {
  /// Another app took the link. The only outcome that may be reported as
  /// success.
  opened,

  /// Nothing on this device handles the scheme — no mail client configured,
  /// no Telegram installed and no browser. The screen offers the copy
  /// fallback instead.
  unsupported,

  /// The handoff was attempted and failed. Never surfaced as the platform's
  /// own exception text — see [ExternalLinkLauncher.open].
  failed,
}

/// Hands a [Uri] to the operating system.
class ExternalLinkLauncher {
  const ExternalLinkLauncher();

  /// Opens [uri] in whichever app claims it.
  ///
  /// Never throws and never leaks a platform message: a `PlatformException`
  /// carries a developer-facing string in a language the user does not read,
  /// and putting one in a SnackBar is the "no raw exception reaches the UI"
  /// rule broken in the one place it is most tempting. Everything that is not
  /// a clean launch collapses to [ExternalLinkOutcome.failed], and the screen
  /// says something true and Arabic instead.
  ///
  /// [LaunchMode.externalApplication] rather than the default: a `mailto:` or
  /// a Telegram link belongs in the user's mail or Telegram app, not in an
  /// in-app web view that cannot send mail.
  Future<ExternalLinkOutcome> open(Uri uri) async {
    try {
      if (!await canLaunchUrl(uri)) return ExternalLinkOutcome.unsupported;
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      return launched ? ExternalLinkOutcome.opened : ExternalLinkOutcome.failed;
    } on PlatformException {
      return ExternalLinkOutcome.failed;
    } on MissingPluginException {
      // A build (or a test host) with no platform implementation registered.
      // Honest, and exactly what the copy fallback exists for.
      return ExternalLinkOutcome.unsupported;
    } catch (_) {
      return ExternalLinkOutcome.failed;
    }
  }
}

/// The seam. Override in a test with a fake that records what was asked for.
final externalLinkLauncherProvider = Provider<ExternalLinkLauncher>((ref) {
  return const ExternalLinkLauncher();
});
