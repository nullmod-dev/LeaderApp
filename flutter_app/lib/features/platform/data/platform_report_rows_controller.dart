import 'package:flutter/foundation.dart';

import '../../../core/result/result.dart';
import '../domain/platform_report_models.dart';

/// Point 13B — the report-agnostic application layer around Point 13A's
/// pure [PlatformReportRowsState].
///
/// The first page of every report is a Riverpod family read
/// (`platform_reports_providers.dart`) keyed by the typed query, exactly as
/// Point 13A specifies — a query change is a new family key, so page one and
/// its summary always come from `ref.watch`. This controller owns exactly
/// the part Point 13A left to 13B: turning a "show more" tap into a
/// repository call for the next opaque cursor, and folding the result into
/// [PlatformReportRowsState] so rows never mix across two snapshots.
///
/// One instance per report screen, built with that report's own typed
/// `loadPage`/`pageOf`/`withCursor`/`keyOf`. Not a `ChangeNotifier` per report
/// type — the shape is identical across every paginated report, so it is
/// written once and configured four ways (three, in practice: activity has no
/// rows).
class PlatformReportRowsController<Q, Res, R> extends ChangeNotifier {
  PlatformReportRowsController({
    required Future<Result<Res>> Function(Q query) loadPage,
    required PlatformReportPage<R> Function(Res result) pageOf,
    required String Function(Res result) snapshotIdOf,
    required Q Function(Q query, String cursor) withCursor,
    required String Function(R row) keyOf,
  })  : _loadPage = loadPage,
        _pageOf = pageOf,
        _snapshotIdOf = snapshotIdOf,
        _withCursor = withCursor,
        _keyOf = keyOf;

  final Future<Result<Res>> Function(Q query) _loadPage;
  final PlatformReportPage<R> Function(Res result) _pageOf;
  final String Function(Res result) _snapshotIdOf;
  final Q Function(Q query, String cursor) _withCursor;
  final String Function(R row) _keyOf;

  Q? _query;
  PlatformReportRowsState<R>? state;

  /// A next-page request is in flight.
  bool paging = false;

  /// The last next-page attempt found the app offline; paging stays refused
  /// until a fresh page one arrives, never queued.
  bool offlinePaging = false;

  bool _disposed = false;

  /// Folds in a first page that a report screen already has in hand — from
  /// its `ref.watch` of the Point 13A family provider, which owns page one
  /// entirely; this controller only ever *appends*.
  ///
  /// **Deliberately silent.** The caller always reads this at the top of its
  /// own `build()`, in the same frame the new data arrived through
  /// `ref.watch`, so the screen already reflects it — a `notifyListeners()`
  /// here would call `setState` while Flutter is still building this widget.
  /// [loadMore] below runs after an `await`, outside any build, and does
  /// notify.
  void syncFirstPage(
    Q query,
    PlatformReportMeta meta,
    PlatformReportPage<R> page,
  ) {
    _query = query;
    paging = false;
    offlinePaging = false;
    state = PlatformReportRowsState<R>.firstPage(
      snapshotId: meta.snapshotId,
      page: page,
    );
  }

  /// Whether [syncFirstPage] needs to run for this [snapshotId] — a report
  /// page calls this at the top of `build()` before reading [state].
  bool needsSync(String snapshotId) =>
      state == null || state!.snapshotId != snapshotId;

  Future<void> loadMore() async {
    final current = state;
    final query = _query;
    if (current == null || query == null) return;
    if (paging || !current.canLoadMore) return;
    final cursor = current.nextCursor;
    if (cursor == null) return;

    paging = true;
    offlinePaging = false;
    notifyListeners();

    Result<Res> result;
    try {
      result = await _loadPage(_withCursor(query, cursor));
    } catch (_) {
      result = const Failure('server');
    }
    if (_disposed) return;
    // The state object was replaced (a new first page landed) while this
    // request was in flight: that page no longer belongs to what is shown.
    if (!identical(state, current)) return;

    paging = false;
    switch (result) {
      case Success<Res>(:final data):
        state = current.appendPage(
          cursor: cursor,
          snapshotId: _snapshotIdOf(data),
          page: _pageOf(data),
          keyOf: _keyOf,
        );
      case Offline<Res>():
        offlinePaging = true;
      case Failure<Res>(:final code):
        state = current.pageFailure(code: code);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
