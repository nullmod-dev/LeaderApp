import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/widgets/async_result.dart';
import 'package:mtm/l10n/strings.dart';

/// The one representative integration: `AsyncResultView` — the shared
/// four-state renderer used by ~25 screens — now routes a `Result.failure`
/// through the problem pipeline. Known codes get MTM's localized copy; an
/// unrecognised code gets the safe fallback; the raw `message` is never
/// shown for either.
void main() {
  Widget host(AsyncValue<Result<int>> value) => ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(PaletteId.medical),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: AsyncResultView<int>(
                value: value,
                onRetry: () {},
                builder: (_, data, __) => Text('data: $data'),
              ),
            ),
          ),
        ),
      );

  testWidgets('a known code shows MTM copy, not the wire message',
      (tester) async {
    await tester.pumpWidget(host(
      const AsyncValue.data(
        Failure<int>('لم يُعثر على المفرزة رقم d_9.', code: 'not_found'),
      ),
    ));

    expect(find.text(S.errNotFound), findsOneWidget);
    expect(find.text('لم يُعثر على المفرزة رقم d_9.'), findsNothing);
  });

  testWidgets('an unknown code shows the generic fallback, not the wire text',
      (tester) async {
    await tester.pumpWidget(host(
      const AsyncValue.data(
        Failure<int>('NullPointerException at Svc.load(Svc.kt:22)',
            code: 'kaboom_9000'),
      ),
    ));

    expect(find.text(S.problemUnexpectedBody), findsOneWidget);
    expect(find.textContaining('Svc.kt'), findsNothing);
  });

  testWidgets('not_permitted renders inline with its own copy', (tester) async {
    await tester.pumpWidget(host(
      const AsyncValue.data(
          Failure<int>('scope denied', code: 'not_permitted')),
    ));

    expect(find.text(S.errNotPermitted), findsOneWidget);
    expect(find.text('scope denied'), findsNothing);
  });

  testWidgets('offline with no cache still shows the offline empty state',
      (tester) async {
    await tester.pumpWidget(host(const AsyncValue.data(Offline<int>())));
    expect(find.text(S.offlineTitle), findsOneWidget);
  });

  testWidgets('success still renders the builder', (tester) async {
    await tester.pumpWidget(host(const AsyncValue.data(Success<int>(7))));
    expect(find.text('data: 7'), findsOneWidget);
  });
}
