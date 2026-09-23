import 'dart:convert';

import '../../../core/problem/problem.dart';
import '../../../core/result/result.dart';
import '../../../core/text/search_key.dart';
import '../domain/platform_audit_models.dart';
import '../domain/platform_audit_repository.dart';
import 'platform_audit_fixtures.dart';

enum MockPlatformAuditMode {
  loaded,
  empty,
  stale,
  offlineWithCache,
  offlineWithoutCache,
  failure,
}

class MockPlatformAuditRepository implements PlatformAuditRepository {
  MockPlatformAuditRepository({
    required this.fixtures,
    this.mode = MockPlatformAuditMode.loaded,
    this.latency = const Duration(milliseconds: 420),
  });

  final PlatformAuditFixtures fixtures;
  final MockPlatformAuditMode mode;
  final Duration latency;

  @override
  Future<Result<PlatformAuditPage>> listAuditEvents(
    PlatformAuditQuery query,
  ) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);

    if (mode == MockPlatformAuditMode.failure) {
      return const Failure(
        'تعذّر تحميل سجل المنصة.',
        code: 'server',
      );
    }
    if (mode == MockPlatformAuditMode.offlineWithoutCache) {
      return const Offline();
    }

    final pageResult = _page(
      query,
      mode == MockPlatformAuditMode.empty ? const [] : fixtures.events,
    );
    if (pageResult is Failure<PlatformAuditPage>) return pageResult;
    final page = (pageResult as Success<PlatformAuditPage>).data;

    return switch (mode) {
      MockPlatformAuditMode.loaded ||
      MockPlatformAuditMode.empty =>
        Success(page),
      MockPlatformAuditMode.stale => Success(page, stale: true),
      MockPlatformAuditMode.offlineWithCache => Offline(cached: page),
      MockPlatformAuditMode.offlineWithoutCache ||
      MockPlatformAuditMode.failure =>
        throw StateError('handled before paging'),
    };
  }

  Result<PlatformAuditPage> _page(
    PlatformAuditQuery query,
    List<PlatformAuditEvent> source,
  ) {
    final needle = searchKey(query.search);
    final matched = [
      for (final event in source)
        if (_matches(event, query, needle)) event,
    ]..sort(_compareEvents);

    var start = 0;
    if (query.cursor != null) {
      final anchor = _decodeCursor(query.cursor!);
      if (anchor == null) return _invalidCursor();
      final anchorIndex = matched.indexWhere(
        (event) =>
            event.id == anchor.id &&
            event.occurredAt.microsecondsSinceEpoch == anchor.occurredAtMicros,
      );
      if (anchorIndex < 0) return _invalidCursor();
      start = anchorIndex + 1;
    }

    final end = (start + query.limit).clamp(0, matched.length);
    final items = matched.sublist(start, end);
    return Success(
      PlatformAuditPage(
        items: items,
        nextCursor: end < matched.length && items.isNotEmpty
            ? _encodeCursor(items.last)
            : null,
      ),
    );
  }

  static bool _matches(
    PlatformAuditEvent event,
    PlatformAuditQuery query,
    String needle,
  ) {
    if (query.from != null && event.occurredAt.isBefore(query.from!)) {
      return false;
    }
    if (query.before != null && !event.occurredAt.isBefore(query.before!)) {
      return false;
    }
    if (query.actorKind != null && event.actor.kind != query.actorKind) {
      return false;
    }
    if (query.actorId != null) {
      final actor = event.actor;
      if (actor is! PlatformAuditAdministratorActor ||
          actor.id != query.actorId) {
        return false;
      }
    }
    if (query.action != null && event.action != query.action) return false;
    if (query.category != null && event.category != query.category) {
      return false;
    }
    if (query.tenantId != null && event.tenant?.id != query.tenantId) {
      return false;
    }
    if (query.targetType != null && event.target.type != query.targetType) {
      return false;
    }
    if (needle.isEmpty) return true;

    final searchable = <String>[
      event.id,
      if (event.actor case PlatformAuditAdministratorActor(:final displayName))
        displayName,
      event.target.id,
      if (event.target.displayName case final displayName?) displayName,
      if (event.tenant case final tenant?) ...[
        tenant.id,
        tenant.displayName,
      ],
    ];
    return searchable.any((value) => searchKey(value).contains(needle));
  }

  static int _compareEvents(
    PlatformAuditEvent left,
    PlatformAuditEvent right,
  ) {
    final time = right.occurredAt.compareTo(left.occurredAt);
    return time != 0 ? time : right.id.compareTo(left.id);
  }

  static String _encodeCursor(PlatformAuditEvent event) {
    final payload = jsonEncode({
      'v': 1,
      'at': event.occurredAt.microsecondsSinceEpoch,
      'id': event.id,
    });
    return base64Url.encode(utf8.encode(payload)).replaceAll('=', '');
  }

  static _CursorAnchor? _decodeCursor(String cursor) {
    try {
      if (cursor.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(cursor)) {
        return null;
      }
      final normalized = cursor.padRight((cursor.length + 3) ~/ 4 * 4, '=');
      final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      if (decoded is! Map<String, dynamic> ||
          decoded['v'] != 1 ||
          decoded['at'] is! int ||
          decoded['id'] is! String ||
          (decoded['id'] as String).isEmpty) {
        return null;
      }
      return _CursorAnchor(
        decoded['at'] as int,
        decoded['id'] as String,
      );
    } on FormatException {
      return null;
    }
  }

  static Failure<PlatformAuditPage> _invalidCursor() => Failure(
        'مؤشر صفحة سجل المنصة غير صالح.',
        code: ProblemCode.validation.wire,
      );
}

class _CursorAnchor {
  const _CursorAnchor(this.occurredAtMicros, this.id);

  final int occurredAtMicros;
  final String id;
}
