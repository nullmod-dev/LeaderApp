import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/app_info.dart';
import 'package:mtm/features/about/domain/support_contacts.dart';
import 'package:mtm/l10n/strings.dart';

/// The values on the About screen, and the links behind them.
///
/// Pure and fast on purpose. The two things that can actually go wrong here
/// are a typo in an approved contact and a malformed URI, and neither is
/// visible by looking at the screen — a `mailto:` with an unescaped subject
/// still *renders* correctly and simply opens a broken composer.

void main() {
  group('the approved contacts', () {
    test('the support address is exactly the approved one', () {
      expect(supportEmail, 'medical.team.auth@gmail.com');
    });

    test('the Telegram username is exactly the approved one, with its @', () {
      expect(supportTelegram, '@jjkkkj');
    });

    test('subscription contacts are exact', () {
      expect(subscriptionEmail, 'nullmod.dev@gmail.com');
      expect(subscriptionWhatsApp, '07701322947');
    });
  });

  group('the email link', () {
    test('addresses the support mailbox over mailto', () {
      final uri = emailUri();
      expect(uri.scheme, 'mailto');
      expect(uri.path, supportEmail);
    });

    test('prefills a generic subject and nothing else', () {
      final uri = emailUri();
      expect(uri.queryParameters['subject'], '${S.productNameEn} Support');
      // One parameter: no body, and nothing about the signed-in user, their
      // detachment, or the device.
      expect(uri.queryParameters.keys, ['subject']);
    });

    test('the subject is escaped, so the link does not end at the space', () {
      // `Leader Support` is two words. A concatenated string would have
      // produced `?subject=Leader Support`, which a launcher truncates.
      expect(emailUri().toString(), isNot(contains(' ')));
      expect(emailUri().toString(), contains('subject=Leader'));
    });
  });

  group('the Telegram links', () {
    test('the handle drops the @, which a URL cannot carry', () {
      expect(telegramHandle(), 'jjkkkj');
    });

    test('the app link is Telegram\'s own tg:resolve scheme', () {
      final uri = telegramAppUri();
      expect(uri.scheme, 'tg');
      expect(uri.host, 'resolve');
      expect(uri.queryParameters['domain'], 'jjkkkj');
    });

    test('the fallback is an ordinary https t.me link', () {
      final uri = telegramWebUri();
      expect(uri.scheme, 'https');
      expect(uri.host, 't.me');
      expect(uri.path, '/jjkkkj');
      // Not an opaque deep link: a device with only a browser opens this.
      expect(uri.toString(), 'https://t.me/jjkkkj');
    });
  });

  group('the subscription links', () {
    test('normalizes the Iraqi WhatsApp number without keeping the trunk zero',
        () {
      expect(whatsAppDigits(), '9647701322947');
      expect(whatsAppAppUri().scheme, 'whatsapp');
      expect(whatsAppAppUri().queryParameters['phone'], '9647701322947');
      expect(whatsAppWebUri().toString(), 'https://wa.me/9647701322947');
    });

    test('builds the subscription mailbox and encoded subject', () {
      final uri = subscriptionEmailUri();
      expect(uri.scheme, 'mailto');
      expect(uri.path, subscriptionEmail);
      expect(uri.queryParameters['subject'], '${S.productNameEn} Subscription');
      expect(uri.toString(), isNot(contains(' ')));
    });
  });

  group('the version About shows', () {
    test('the build number is derived from the one build identity', () {
      // Not a second constant. If `pubspec.yaml` moves to `1.1.0+7`, About
      // follows the upgrade gate rather than drifting from it.
      expect(
          AppInfo.buildIdentity, '${AppInfo.version}+${AppInfo.buildNumber}');
    });

    test('the build number is the part after the plus', () {
      expect(AppInfo.buildNumber, '1');
    });
  });
}
