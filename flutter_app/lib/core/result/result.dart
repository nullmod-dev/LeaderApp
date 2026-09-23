/// Sealed result type — every repository method returns this.
/// No raw exceptions cross the repository boundary.
sealed class Result<T> {
  const Result();

  R when<R>({
    required R Function(T data, {bool stale}) success,
    required R Function(String message, String? code) failure,
    required R Function(T? cached) offline,
  });

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;
  bool get isOffline => this is Offline<T>;
}

class Success<T> extends Result<T> {
  const Success(this.data, {this.stale = false});
  final T data;

  /// True if this data came from cache after a background refresh failed —
  /// screens should show a subtle "cached" indicator.
  final bool stale;

  @override
  R when<R>({
    required R Function(T data, {bool stale}) success,
    required R Function(String message, String? code) failure,
    required R Function(T? cached) offline,
  }) =>
      success(data, stale: stale);
}

class Failure<T> extends Result<T> {
  const Failure(this.message, {this.code});
  final String message;
  final String? code;

  @override
  R when<R>({
    required R Function(T data, {bool stale}) success,
    required R Function(String message, String? code) failure,
    required R Function(T? cached) offline,
  }) =>
      failure(message, code);
}

class Offline<T> extends Result<T> {
  const Offline({this.cached});
  final T? cached;

  @override
  R when<R>({
    required R Function(T data, {bool stale}) success,
    required R Function(String message, String? code) failure,
    required R Function(T? cached) offline,
  }) =>
      offline(cached);
}
