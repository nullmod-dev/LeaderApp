import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../l10n/strings.dart';
import '../app_info.dart';
import '../problem/problem.dart';
import '../problem/problem_presentation.dart';
import '../result/result.dart';
import '../sync/uuid_v7.dart';
import 'api_config.dart';
import 'token_vault.dart';

/// What one HTTP exchange produced, before it is mapped onto a [Result].
///
/// Most repositories never see this — they call [ApiClient.send]. It exists
/// for the few call sites that must read a typed extension next to the error
/// code (`attemptsRemaining`, `retryAvailableAt`, `currentVersion`), which
/// the shared `Problem` parser deliberately drops.
sealed class ApiOutcome {
  const ApiOutcome();
}

/// The server answered.
final class ApiReply extends ApiOutcome {
  const ApiReply(this.status, this.json, this.headers);

  final int status;

  /// The decoded body, or `null` for an empty (`204`) or non-JSON body.
  final Object? json;
  final Map<String, String> headers;

  bool get ok => status >= 200 && status < 300;

  /// The `error` object of the shared envelope, or an empty map.
  Map<String, dynamic> get error {
    final j = json;
    if (j is Map<String, dynamic> && j['error'] is Map<String, dynamic>) {
      return j['error'] as Map<String, dynamic>;
    }
    return const {};
  }

  /// The error `code` — the only key behaviour may branch on. Falls back to
  /// the global code the HTTP status implies when a body carries none (a
  /// proxy page, an empty 5xx).
  String? get code {
    final c = error['code'];
    if (c is String && c.isNotEmpty) return c;
    return switch (status) {
      401 => ProblemCode.authenticationExpired.wire,
      403 => ProblemCode.notPermitted.wire,
      404 => ProblemCode.notFound.wire,
      409 => ProblemCode.conflict.wire,
      422 => ProblemCode.validation.wire,
      426 => ProblemCode.upgradeRequired.wire,
      429 => 'rate_limited',
      >= 500 => ProblemCode.server.wire,
      _ => null,
    };
  }
}

/// The server could not be reached at all.
final class ApiUnreachable extends ApiOutcome {
  const ApiUnreachable({required this.offline});

  /// `true` for no connectivity / timeout (→ `Offline`); `false` for a
  /// transport fault that is not a clean offline, such as TLS (→ `network`).
  final bool offline;
}

/// The one place in the app that speaks HTTP (`FRONTEND-INTEGRATION-GUIDE.md`
/// §16.2): bearer, `X-Client-Version`, `Idempotency-Key`, timeouts, the
/// single-flight rotating refresh, and the mapping onto the app's [Result].
class ApiClient {
  ApiClient({
    required TokenVault vault,
    String? origin,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  })  : _vault = vault,
        _origin = origin ?? apiOrigin,
        _client = client ?? http.Client();

  final TokenVault _vault;
  final String _origin;
  final http.Client _client;
  final Duration timeout;

  /// Called on any `426 upgrade_required` — the forced-upgrade gate re-checks.
  void Function()? onUpgradeRequired;

  /// Called when a **full** session could not be refreshed: the credentials
  /// were cleared and the person has to sign in again.
  void Function()? onSessionEnded;

  /// This installation's id, sent as `X-Device-Id` on every request: every
  /// sign-in needs it (device trust), and a session that predates device
  /// trust registers its phone with it. `null` sends none.
  Future<String> Function()? deviceId;

  Future<bool>? _refreshing;

  TokenVault get vault => _vault;

  Uri uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse('$_origin$apiPathPrefix$path');
    return (query == null || query.isEmpty)
        ? base
        : base.replace(queryParameters: query);
  }

  static String newIdempotencyKey() => uuidV7();

  /// One request, with one transparent refresh-and-retry on
  /// `401 authentication_expired`.
  ///
  /// [bearer] replaces the stored access token for this call only (the
  /// password-reset token). [authenticated] `false` sends no bearer at all.
  /// [headers] are extra headers for this call only; the client's own win.
  /// [notifyUpgrade] `false` keeps a `426` from re-triggering the gate — the
  /// gate's own check must not call itself.
  Future<ApiOutcome> exchange(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    String? idempotencyKey,
    bool authenticated = true,
    String? bearer,
    bool notifyUpgrade = true,
    Map<String, String>? headers,
  }) async {
    final first = await _once(method, path,
        body: body,
        query: query,
        idempotencyKey: idempotencyKey,
        authenticated: authenticated,
        bearer: bearer,
        notifyUpgrade: notifyUpgrade,
        extraHeaders: headers);
    if (first is ApiReply &&
        first.status == 401 &&
        authenticated &&
        bearer == null &&
        first.code == ProblemCode.authenticationExpired.wire) {
      final tokens = await _vault.read();
      if (tokens == null) return first;
      final refreshed = await _refresh();
      if (refreshed == true) {
        return _once(method, path,
            body: body,
            query: query,
            idempotencyKey: idempotencyKey,
            authenticated: authenticated,
            notifyUpgrade: notifyUpgrade,
            extraHeaders: headers);
      }
    }
    return first;
  }

  /// [exchange], mapped onto the app's [Result]. [parse] turns the decoded
  /// body into `T`; a body it cannot read is a `server` failure, never an
  /// exception across the repository boundary.
  Future<Result<T>> send<T>(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    String? idempotencyKey,
    bool authenticated = true,
    String? bearer,
    bool notifyUpgrade = true,
    required T Function(Object? json) parse,
  }) async {
    final outcome = await exchange(method, path,
        body: body,
        query: query,
        idempotencyKey: idempotencyKey,
        authenticated: authenticated,
        bearer: bearer,
        notifyUpgrade: notifyUpgrade);
    return resultOf(outcome, parse);
  }

  /// The standard mapping. Exposed so a repository that read an extension
  /// from an [ApiReply] can still finish with the shared rules.
  static Result<T> resultOf<T>(
    ApiOutcome outcome,
    T Function(Object? json) parse,
  ) {
    switch (outcome) {
      case ApiUnreachable(:final offline):
        return offline
            ? Offline<T>()
            : Failure<T>(failureMessage(ProblemCode.network.wire),
                code: ProblemCode.network.wire);
      case ApiReply(:final ok, :final json):
        if (ok) {
          try {
            return Success<T>(parse(json));
          } catch (_) {
            return Failure<T>(failureMessage(ProblemCode.server.wire),
                code: ProblemCode.server.wire);
          }
        }
        final code = outcome.code;
        return Failure<T>(failureMessage(code), code: code);
    }
  }

  Future<ApiOutcome> _once(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    String? idempotencyKey,
    required bool authenticated,
    String? bearer,
    bool notifyUpgrade = true,
    Map<String, String>? extraHeaders,
  }) async {
    final installation = deviceId;
    final headers = <String, String>{
      ...?extraHeaders,
      'Accept': 'application/json',
      AppInfo.clientVersionHeader: AppInfo.version,
      if (installation != null) 'X-Device-Id': await installation(),
    };
    if (bearer != null) {
      headers['Authorization'] = 'Bearer $bearer';
    } else if (authenticated) {
      final tokens = await _vault.read();
      if (tokens != null) headers['Authorization'] = 'Bearer ${tokens.access}';
    }
    if (body != null) headers['Content-Type'] = 'application/json';
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;

    final request = http.Request(method, uri(path, query))
      ..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      ).timeout(timeout);
    } on SocketException {
      return const ApiUnreachable(offline: true);
    } on TimeoutException {
      return const ApiUnreachable(offline: true);
    } on HandshakeException {
      return const ApiUnreachable(offline: false);
    } on http.ClientException {
      return const ApiUnreachable(offline: true);
    } on IOException {
      return const ApiUnreachable(offline: false);
    }

    Object? decoded;
    if (response.bodyBytes.isNotEmpty) {
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        decoded = null;
      }
    }
    final reply = ApiReply(response.statusCode, decoded, response.headers);
    if (reply.status == 426 && notifyUpgrade) onUpgradeRequired?.call();
    return reply;
  }

  /// Rotating, single-use refresh. One in flight; concurrent 401s await the
  /// same future (`docs/api/auth.md` → "Refresh rotation & replay").
  Future<bool> _refresh() => _refreshing ??= _doRefresh().whenComplete(() {
        _refreshing = null;
      });

  Future<bool> _doRefresh() async {
    final tokens = await _vault.read();
    if (tokens == null) return false;
    final ApiOutcome outcome;
    try {
      outcome = await _once('POST', '/auth/refresh',
          body: {'refreshToken': tokens.refresh}, authenticated: false);
    } catch (_) {
      return false;
    }
    switch (outcome) {
      case ApiUnreachable():
        // Offline: keep the pair, sign nobody out.
        return false;
      case ApiReply(:final ok, :final json, :final status):
        if (ok && json is Map<String, dynamic>) {
          final access = json['accessToken'] ?? json['onboardingToken'];
          final refresh =
              json['refreshToken'] ?? json['onboardingRefreshToken'];
          if (access is String && refresh is String) {
            final sessionId = json['sessionId'];
            await _vault.rotate(access, refresh,
                sessionId: sessionId is String && sessionId.isNotEmpty
                    ? sessionId
                    : null);
            return true;
          }
          return false;
        }
        if (status == 401) {
          // Expired, revoked or replayed: the whole family is gone.
          if (tokens.grade == SessionGrade.full) {
            await _vault.clearFull();
            onSessionEnded?.call();
          } else {
            await _vault.clearOnboarding();
          }
        }
        return false;
    }
  }
}

/// Arabic copy for a failure code, so a server's diagnostic English text
/// never reaches a screen that prints `Failure.message`.
///
/// Global codes read the same copy `resolveProblem` shows; the handful of
/// feature codes a screen may print get the sentence their mock already
/// used. Anything else gets the generic unexpected-error sentence.
String failureMessage(String? code) {
  final own = _featureMessages[code];
  if (own != null) return own;
  if (code == 'rate_limited') return S.onboardingRateLimited;
  final known = ProblemCode.parse(code);
  if (known == null) return S.problemUnexpectedBody;
  return resolveProblem(Problem.of(known)).message;
}

/// The sentences the mock repositories answer these codes with, so a screen
/// reads the same whichever repository is behind it.
const Map<String, String> _featureMessages = {
  'already_organizer': 'أحد الأعضاء ضمن الفريق المنظِّم لهذه الورشة.',
  'already_participant': 'أحد الأعضاء مسجّل مشاركا في هذه الورشة.',
  'archived': 'الورشة مؤرشفة. استعدها أولا لتعديلها.',
  'duplicate': 'يوجد عضو بهذا الاسم في الورشة.',
  'insufficient_stock': 'الكمية المطلوبة أكبر من المخزون الحالي.',
  'invalid_credentials': 'تعذّر تسجيل الدخول.',
  'invalid_subscription_transition':
      'لا تسمح حالة الاشتراك الحالية بهذا الإجراء.',
  'invalid_trial_extension':
      'يجب أن يكون انتهاء التجربة الجديد بعد تاريخها الحالي.',
  'limit_invalid': 'الحد غير صالح.',
  'name_taken': 'يوجد عضو بهذا الاسم في المفرزة.',
  'number_taken': 'هذا الرقم مستخدم لعضو آخر في المفرزة.',
  'packaging_required':
      'حدّد عدد الوحدات في الشريط وعدد الشرائط في الكرتونة قبل اختيار هذه التعبئة.',
  'packaging_unavailable': 'هذا الصنف غير معرّف بهذه التعبئة.',
  'plan_not_found': 'الخطة غير موجودة.',
  'plan_unavailable': 'الخطة غير متاحة للاختيار.',
  'stale_feature_state': 'تغيّرت حالة الميزة. حدّث الصفحة ثم أعد المحاولة.',
  'stale_subscription': 'تغيّرت بيانات الاشتراك. حدّث الصفحة ثم أعد المحاولة.',
  'subscription_not_found': 'بيانات الاشتراك غير متاحة الآن.',
  'tenant_not_found': 'الفريق غير موجود.',
  'workshop_full': 'الورشة ممتلئة.',
};
