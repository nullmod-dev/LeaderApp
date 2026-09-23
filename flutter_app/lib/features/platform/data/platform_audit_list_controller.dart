import 'package:flutter/foundation.dart';

import '../../../core/result/result.dart';
import '../domain/platform_audit_models.dart';
import '../domain/platform_audit_repository.dart';

/// Owns one query revision. Requests from older revisions can never publish.
class PlatformAuditListController extends ChangeNotifier {
  PlatformAuditListController(this.repository);
  final PlatformAuditRepository repository;
  PlatformAuditQuery query = PlatformAuditQuery(limit: 8);
  List<PlatformAuditEvent> items = const [];
  String? nextCursor;
  bool loading = false;
  bool paging = false;
  bool offline = false;
  bool stale = false;
  bool failed = false;
  bool cursorFailed = false;
  int _revision = 0;
  bool _disposed = false;
  final Set<String> _cursors = {};

  Future<void> setQuery(PlatformAuditQuery value) async {
    query = value.firstPage;
    items = const [];
    nextCursor = null;
    offline = false;
    stale = false;
    await refresh();
  }

  Future<void> refresh() => _load(append: false);
  Future<void> loadMore() async {
    if (loading || paging || nextCursor == null || cursorFailed) return;
    await _load(append: true);
  }

  Future<void> _load({required bool append}) async {
    final revision = append ? _revision : ++_revision;
    final cursor = append ? nextCursor : null;
    if (!append) {
      loading = true;
      paging = false;
      cursorFailed = false;
    } else {
      paging = true;
    }
    failed = false;
    notifyListeners();
    final q = query;
    final request = PlatformAuditQuery(
      from: q.from,
      before: q.before,
      actorKind: q.actorKind,
      actorId: q.actorId,
      action: q.action,
      category: q.category,
      tenantId: q.tenantId,
      targetType: q.targetType,
      search: q.search,
      cursor: cursor,
      limit: q.limit,
    );
    Result<PlatformAuditPage> result;
    try {
      result = await repository.listAuditEvents(request);
    } catch (_) {
      result = const Failure('audit_unavailable');
    }
    if (_disposed || revision != _revision) return;
    loading = false;
    paging = false;
    offline = result is Offline<PlatformAuditPage>;
    stale = switch (result) {
      Success<PlatformAuditPage>() => result.stale || (append && stale),
      Offline<PlatformAuditPage>() => items.isNotEmpty || result.cached != null,
      Failure<PlatformAuditPage>() => stale,
    };
    final page = switch (result) {
      Success<PlatformAuditPage>(:final data) => data,
      Offline<PlatformAuditPage>(:final cached) => cached,
      _ => null,
    };
    if (page == null) {
      failed = !offline;
      // A rejected cursor is retried through a fresh first page, never a loop.
      cursorFailed = append &&
          result is Failure<PlatformAuditPage> &&
          (result.code == 'validation' ||
              (result.code?.contains('cursor') ?? false));
    } else {
      if (!append) _cursors.clear();
      if (cursor != null) _cursors.add(cursor);
      final seen = <String>{};
      items = List.unmodifiable([
        for (final item in [
          ...(append ? items : <PlatformAuditEvent>[]),
          ...page.items
        ])
          if (seen.add(item.id)) item,
      ]);
      final next = page.nextCursor;
      cursorFailed =
          next != null && (next.trim().isEmpty || _cursors.contains(next));
      nextCursor = cursorFailed ? null : next;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_revision;
    super.dispose();
  }
}
