/// The approved support contacts, and the URIs that reach them.
///
/// Pure Dart: no Flutter, no plugin, no provider. Building a `mailto:` or a
/// Telegram link is string work with two traps in it — percent-encoding the
/// subject, and the fact that `@handle` is not a URL — and both are worth a
/// test that runs in milliseconds rather than a screen somebody has to tap.
///
/// **These values are the product's, not a placeholder.** They are approved
/// support contacts and are displayed verbatim; a test pins them, so a typo
/// cannot ship quietly.
///
/// Support in V1 is a mail address and a Telegram username. There is no ticket
/// system, no support form, no submission endpoint and no ticket number — a
/// screen that claimed to have "sent" anything would be describing software
/// that does not exist.
library;

import '../../../l10n/strings.dart';

/// The support mailbox. Displayed exactly as written.
const String supportEmail = 'medical.team.auth@gmail.com';

/// The support Telegram username, in the form people recognise — with the `@`.
/// [telegramUri] strips it, because a URL path may not carry one.
const String supportTelegram = '@jjkkkj';

/// Subscription/sales contact. Separate from product support by design.
const String subscriptionEmail = 'nullmod.dev@gmail.com';

/// Displayed in its familiar Iraqi domestic form.
const String subscriptionWhatsApp = '07701322947';

/// The subject a support mail opens with.
///
/// Deliberately generic. Prefilling the signed-in administrator's name, their
/// detachment, the app's state or a device identifier would put data the user
/// did not choose to share into a message they have not read yet; they can
/// type whatever the problem actually is.
const String supportEmailSubject = '${S.productNameEn} Support';

/// `mailto:` for the support address, with the subject prefilled.
///
/// Built through [Uri]'s own query encoding rather than string concatenation,
/// so a subject containing a space or an Arabic word is escaped correctly
/// instead of truncating the link at the first space.
Uri emailUri() => Uri(
      scheme: 'mailto',
      path: supportEmail,
      query: Uri(queryParameters: {'subject': supportEmailSubject}).query,
    );

/// The Telegram username without its leading `@` — what a URL path carries.
String telegramHandle() => supportTelegram.startsWith('@')
    ? supportTelegram.substring(1)
    : supportTelegram;

/// The deep link that opens the Telegram app directly.
///
/// `tg://resolve?domain=…` is Telegram's own documented scheme. It is tried
/// first because it lands in the app the user already has signed in; a device
/// without Telegram installed has nothing registered for `tg:` and the attempt
/// fails cleanly rather than opening something wrong.
Uri telegramAppUri() => Uri(scheme: 'tg', host: 'resolve', queryParameters: {
      'domain': telegramHandle(),
    });

/// The web fallback, for a device with no Telegram app.
///
/// `https://t.me/<handle>` opens in the browser and offers the app if it is
/// installed after all. Ordinary `https`, so it is handled by every device
/// that has a browser at all — which is what makes it a fallback rather than a
/// second guess.
Uri telegramWebUri() => Uri.parse('https://t.me/${telegramHandle()}');

/// WhatsApp destination in E.164 digits: drop the domestic trunk `0` first.
String whatsAppDigits() =>
    '964${subscriptionWhatsApp.replaceFirst(RegExp(r'^0'), '')}';

Uri whatsAppAppUri() => Uri.parse('whatsapp://send?phone=${whatsAppDigits()}');

Uri whatsAppWebUri() => Uri.parse('https://wa.me/${whatsAppDigits()}');

Uri subscriptionEmailUri() => Uri(
      scheme: 'mailto',
      path: subscriptionEmail,
      query: Uri(
        queryParameters: {'subject': '${S.productNameEn} Subscription'},
      ).query,
    );
