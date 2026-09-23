import 'package:flutter/foundation.dart';

/// A stable, machine-readable problem code — **the only thing frontend
/// behaviour is allowed to branch on.**
///
/// The wire strings match the codes already listed in `API_CONTRACT.md`
/// ("Errors"), so there is one vocabulary, not two. A value this build does
/// not know parses to `null` (see [ProblemCode.parse]) and the raw string is
/// kept on [Problem.rawCode] for diagnostics only — never for a branch, and
/// never shown to the user.
///
/// `upgrade_required` is the one code not yet in `API_CONTRACT.md`: it is
/// the concept the forced-upgrade gate consumes, pending the backend
/// contract decision on the `426` body — see
/// `FRONTEND-BACKEND-INTEGRATION.md` §1 and §2.
enum ProblemCode {
  /// `HTTP 426`. Routed to the forced-upgrade gate, not rendered inline.
  upgradeRequired('upgrade_required'),

  /// `HTTP 401`. The session must be re-established. App-wide.
  authenticationExpired('authentication_expired'),

  /// `HTTP 403`. Signed in, but not allowed to do this. App-wide.
  notPermitted('not_permitted'),

  /// The organisation does not have the product module this request belongs
  /// to (Point 8 — `API_CONTRACT.md` → Tenant product features, "Enforcement
  /// and retention"). Tenant-wide and cross-feature: any module read, write,
  /// export or search may return it. **Not a permission** — the same request
  /// from the Main Admin is refused the same way — so it never shares copy
  /// with [notPermitted].
  featureDisabled('feature_disabled'),

  /// A create or consuming mutation would exceed the organisation's effective
  /// plan limit (Point 7 — `API_CONTRACT.md` → "Limit enforcement
  /// semantics"). The backend is the authority; this client performs no local
  /// limit check. **Not a permission** and not a feature: the account may do
  /// this, the organisation has no room for more of it.
  planLimitReached('plan_limit_reached'),

  /// `HTTP 404`.
  notFound('not_found'),

  /// `HTTP 409`. Someone changed it first — a domain-shaped condition the
  /// owning feature resolves (a merge sheet, a reload).
  conflict('conflict'),

  /// `HTTP 409`. **Optimistic-concurrency stale write** — the record's
  /// server-held `version` no longer matches the `version` this write was
  /// made against. Distinct from [conflict]: [conflict] is an ordinary
  /// business-rule condition on a synchronous request/response call (e.g. a
  /// double-booked shift); `staleWrite` is specifically the version-mismatch
  /// verdict a versioned write gets back, chiefly on the local-first
  /// sync/outbox retry path (`sync_conflict_classifier.dart`, which
  /// recognises exactly this code and nothing else). The owning feature must
  /// read this code at its own call site and open
  /// `features/conflict/presentation/conflict_resolution_page.dart` with a
  /// typed adapter (see `presentShiftConflict`) — `resolveProblem()` only
  /// provides a safe, non-retryable fallback for a call site that has not
  /// done that yet. See `FRONTEND-BACKEND-INTEGRATION.md` §3/§4 (Task 3).
  staleWrite('stale_write'),

  /// `HTTP 422`. Field-level; the owning feature maps [Problem.fieldErrors]
  /// to its own inputs.
  validation('validation'),

  /// Client-synthesised from `Result.offline` — no connectivity at all.
  offline('offline'),

  /// Client-synthesised from a transport failure that is not a clean
  /// offline (DNS, TLS, socket reset).
  network('network'),

  /// Client-synthesised from `HTTP 5xx` — the server reached, and failed.
  server('server');

  const ProblemCode(this.wire);

  /// The exact string carried on the wire (RFC 9457 `code` extension member,
  /// or `error.code` in the interim envelope).
  final String wire;

  /// The matching code, or `null` when this build does not recognise
  /// [wire]. `null` is not an error — it is the case §11 of
  /// `FRONTEND-BACKEND-INTEGRATION.md` exists for: a newer backend adding a
  /// code an older app has never heard of.
  static ProblemCode? parse(String? wire) {
    if (wire == null || wire.isEmpty) return null;
    for (final c in values) {
      if (c.wire == wire) return c;
    }
    return null;
  }
}

/// A problem the frontend can consume, shaped so a future **RFC 9457**
/// (`application/problem+json`) response drops straight in.
///
/// Only [code] drives behaviour. The RFC 9457 members ([type], [title],
/// [detail], [status], [instance]) are carried for diagnostics and for a
/// last-resort fallback — they are **never** shown as product copy for a
/// known [code]; the localized string comes from `S` via
/// `resolveProblem`. See `FRONTEND-BACKEND-INTEGRATION.md` §2.
///
/// The model is deliberately typed and closed: no open `Map<String, dynamic>`
/// of arbitrary extension members. The two extensions MTM actually needs —
/// per-field messages and a safe support reference — are named fields
/// ([fieldErrors], [reference]). Anything the backend adds later that this
/// class does not name is dropped at the parse boundary rather than smuggled
/// through untyped.
@immutable
class Problem {
  const Problem({
    this.code,
    this.rawCode,
    this.title,
    this.detail,
    this.status,
    this.type,
    this.instance,
    this.fieldErrors = const {},
    this.reference,
  });

  /// Client-synthesised problem — from a legacy `Result.failure` code, from
  /// `Result.offline`, or from a caught transport error. No wire body.
  factory Problem.of(
    ProblemCode? code, {
    String? rawCode,
    String? detail,
    Map<String, String> fieldErrors = const {},
    String? reference,
  }) =>
      Problem(
        code: code,
        rawCode: rawCode ?? code?.wire,
        detail: detail,
        fieldErrors: fieldErrors,
        reference: reference,
      );

  /// Nothing recognisable at all — the safe fallback subject.
  const Problem.unknown([this.detail])
      : code = null,
        rawCode = null,
        title = null,
        status = null,
        type = null,
        instance = null,
        fieldErrors = const {},
        reference = null;

  /// Parses an RFC 9457 problem object. Tolerates the interim MTM envelope
  /// `{ "error": { "code", "message", "fields" } }` from `API_CONTRACT.md`
  /// so existing repositories can adopt it before the contract is finalised.
  ///
  /// Unknown members are ignored. Nothing here reads a header, a token, or
  /// any key not named below.
  factory Problem.fromJson(Map<String, dynamic> json, {int? httpStatus}) {
    final Map<String, dynamic> err = switch (json['error']) {
      final Map<String, dynamic> e => e,
      _ => const {},
    };

    String? str(String key) {
      final v = json[key] ?? err[key];
      return v is String && v.isNotEmpty ? v : null;
    }

    final rawCode = str('code');
    final rawFields = json['errors'] ?? json['fields'] ?? err['fields'];
    final fields = <String, String>{};
    if (rawFields is Map) {
      rawFields.forEach((k, v) {
        if (v != null) fields['$k'] = '$v';
      });
    }

    return Problem(
      code: ProblemCode.parse(rawCode),
      rawCode: rawCode,
      title: str('title'),
      // RFC 9457 `detail`, or the interim envelope's `message`.
      detail: str('detail') ?? str('message'),
      status: (json['status'] as num?)?.toInt() ?? httpStatus,
      type: str('type'),
      instance: str('instance'),
      fieldErrors: Map.unmodifiable(fields),
      // An explicit, safe support/correlation id if the backend sends one.
      // `instance` is a URI, not a support code, so it is NOT used here —
      // see FRONTEND-BACKEND-INTEGRATION §2, this is a backend contract item.
      reference: str('reference') ?? str('traceId') ?? str('requestId'),
    );
  }

  /// The recognised code, or `null` when this build does not know it.
  final ProblemCode? code;

  /// The raw wire code, kept even when [code] is `null`. Diagnostics and
  /// telemetry only — must not reach the UI or a branch.
  final String? rawCode;

  /// RFC 9457 `title`. Diagnostic / fallback only.
  final String? title;

  /// RFC 9457 `detail`. Diagnostic / fallback only — treated as untrusted,
  /// possibly-technical server text.
  final String? detail;

  /// HTTP status, when known.
  final int? status;

  /// RFC 9457 `type` URI. Not shown.
  final String? type;

  /// RFC 9457 `instance` URI. Not shown.
  final String? instance;

  /// Extension: field path → server message, for a `validation` problem.
  /// The owning feature maps these to its own inputs; the generic
  /// presentation never renders them.
  final Map<String, String> fieldErrors;

  /// Extension: a safe, non-identifying support reference, when the backend
  /// provides one. Shown only on substantial (modal / full-screen)
  /// unexpected-error surfaces — never on a field error.
  final String? reference;

  /// True when this build recognises the code and may branch on it.
  bool get isKnown => code != null;

  /// Whether re-issuing the same request could plausibly succeed. Unknown
  /// problems are **not** assumed retryable (§11).
  bool get isRetryable => switch (code) {
        ProblemCode.offline ||
        ProblemCode.network ||
        ProblemCode.server =>
          true,
        _ => false,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Problem &&
          other.code == code &&
          other.rawCode == rawCode &&
          other.title == title &&
          other.detail == detail &&
          other.status == status &&
          other.type == type &&
          other.instance == instance &&
          mapEquals(other.fieldErrors, fieldErrors) &&
          other.reference == reference;

  @override
  int get hashCode => Object.hash(
      code,
      rawCode,
      title,
      detail,
      status,
      type,
      instance,
      Object.hashAllUnordered(fieldErrors.entries.map((e) => e.key)),
      reference);

  @override
  String toString() =>
      'Problem(${code?.name ?? 'unknown'}${rawCode != null ? ':$rawCode' : ''}, '
      'status: $status)';
}
