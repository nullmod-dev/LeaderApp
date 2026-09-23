import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/main.dart';

void main() {
  test('immersive mode is Android-only and safely disabled elsewhere', () {
    expect(
      shouldUseImmersiveSystemUi(
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      isTrue,
    );
    expect(
      shouldUseImmersiveSystemUi(
        isWeb: true,
        platform: TargetPlatform.android,
      ),
      isFalse,
    );
    for (final platform in TargetPlatform.values) {
      if (platform == TargetPlatform.android) continue;
      expect(
        shouldUseImmersiveSystemUi(isWeb: false, platform: platform),
        isFalse,
      );
    }
  });
}
