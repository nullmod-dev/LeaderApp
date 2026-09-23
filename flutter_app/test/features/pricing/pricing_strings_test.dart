import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/features/about/domain/support_contacts.dart';
import 'package:mtm/l10n/strings.dart';

void main() {
  test('approved pricing and conversion copy stays exact in logical order', () {
    expect(S.pricingTitle, 'الاشتراك والأسعار');
    expect(
      S.pricingFullAccess,
      'جميع مدد الاشتراك تتضمن كامل ميزات ليدر.',
    );
    expect(S.pricingBestValue, 'أفضل قيمة');
    expect(S.pricingOneMonth, 'شهر واحد');
    expect(S.pricingThreeMonths, '٣ أشهر');
    expect(S.pricingSixMonths, '٦ أشهر');
    expect(S.pricingTwelveMonths, '١٢ شهرا');
    expect(S.pricingCouponTitle, 'لديك كوبون؟');
    expect(S.pricingCouponValidate, 'تحقق من الكوبون');
    expect(S.pricingContactTitle, 'للاشتراك تواصل معنا');
    expect(S.demoPricingPrompt, 'أعجبتك ليدر؟ شاهد الخطط');

    expect(supportTelegram, '@jjkkkj');
    expect(subscriptionWhatsApp, '07701322947');
    expect(subscriptionEmail, 'nullmod.dev@gmail.com');
  });
}
