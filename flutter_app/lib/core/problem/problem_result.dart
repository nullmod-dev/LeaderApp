import '../result/result.dart';
import 'problem.dart';

/// Bridges the app's existing [Result] type to [Problem] without changing
/// [Result] itself.
///
/// `Result` already carries everything the bridge needs: `Failure.code` is
/// the wire string, `Failure.message` is the (untrusted, diagnostic) server
/// text, and `Offline` is a connectivity problem by definition. A repository
/// that later parses a real RFC 9457 body can attach a richer [Problem] of
/// its own; until then this is the single conversion point, so presentation
/// code never has to know a `Result` was involved.
extension ResultProblem<T> on Result<T> {
  /// The [Problem] this result represents, or `null` when it is a success.
  Problem? get problemOrNull => when(
        success: (_, {stale = false}) => null,
        failure: (message, code) => Problem.of(
          ProblemCode.parse(code),
          rawCode: code,
          detail: message,
        ),
        offline: (_) => Problem.of(ProblemCode.offline),
      );
}
