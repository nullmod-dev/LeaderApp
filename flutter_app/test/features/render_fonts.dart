import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the real fonts a render harness needs.
///
/// Without this a golden renders every glyph as a filled box: the widget
/// tester ships no font, and the Material icon font lives in the Flutter
/// tool's artifact cache rather than in the package.
///
/// Extracted from the harnesses that each spelled it out so a new one does
/// not have to (the Phase 1 tenant harness is the first caller; the existing
/// platform, onboarding and organisation harnesses still carry their own
/// copies and can adopt this whenever they are next touched).
Future<void> loadRenderFonts() async {
  final arabic = FontLoader('IBMPlexSansArabic');
  for (final weight in ['Regular', 'Medium', 'SemiBold']) {
    arabic.addFont(
      File('assets/fonts/IBMPlexSansArabic-$weight.ttf')
          .readAsBytes()
          .then(ByteData.sublistView),
    );
  }
  await arabic.load();

  // Walk up from the Dart executable to the tool's `cache` directory, which
  // is where `material_fonts` is unpacked.
  var cache = File(Platform.resolvedExecutable).parent;
  while (!cache.path.endsWith('/cache') && cache.parent.path != cache.path) {
    cache = cache.parent;
  }
  await (FontLoader('MaterialIcons')
        ..addFont(
          File(
            '${cache.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
      .load();
}
