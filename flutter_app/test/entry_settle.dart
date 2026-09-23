import 'package:flutter_test/flutter_test.dart';

/// `pumpAndSettle`, for a tree that contains the app's entry surface.
///
/// **Why it has to exist.** `/startup` and `/login` are painted on the entry
/// surface (`features/auth/presentation/entry_glass.dart`), whose ambient
/// pulse is a *looping* controller: it runs for as long as the screen is up,
/// by design, because the product's front door is meant to look alive rather
/// than frozen. A looping controller schedules a frame forever, and
/// `pumpAndSettle` waits for frames to stop being scheduled — so on those two
/// screens it does not return, it times out.
///
/// This is the same bounded-pump shape several suites already wrote for the
/// mock repositories' simulated latency; it is shared so the reason is
/// written down once. [frames] × [step] is the wall-clock the tree is given,
/// which by default comfortably covers a route transition plus a mock
/// repository's ~800 ms answer.
///
/// Use `pumpAndSettle` everywhere else. A test that never renders the entry
/// surface has no reason for a bounded pump, and swapping one in would hide a
/// genuine never-settling animation somewhere else in the app.
Future<void> settleEntry(
  WidgetTester tester, {
  int frames = 8,
  Duration step = const Duration(milliseconds: 400),
}) async {
  await tester.pump();
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}
