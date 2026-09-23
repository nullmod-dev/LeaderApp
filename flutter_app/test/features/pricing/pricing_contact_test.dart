import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/features/about/domain/support_contacts.dart';

void main() {
  test('approved subscription contacts and URI normalization are exact', () {
    expect(supportTelegram, '@jjkkkj');
    expect(subscriptionWhatsApp, '07701322947');
    expect(subscriptionEmail, 'nullmod.dev@gmail.com');
    expect(whatsAppDigits(), '9647701322947');
    expect(whatsAppAppUri().toString(), 'whatsapp://send?phone=9647701322947');
    expect(whatsAppWebUri().toString(), 'https://wa.me/9647701322947');
    expect(subscriptionEmailUri().scheme, 'mailto');
    expect(telegramWebUri().toString(), 'https://t.me/jjkkkj');
  });
}
