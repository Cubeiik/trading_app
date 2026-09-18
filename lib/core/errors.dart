import 'dart:developer' as developer;

class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'AppException: $message'
      : 'AppException: $message ($cause)';
}

// TODO: wire up a crash reporter (Crashlytics/Sentry) here.
void logError(Object error, [StackTrace? stackTrace, String? context]) {
  developer.log(
    context ?? 'Error',
    name: 'trading_app',
    error: error,
    stackTrace: stackTrace,
    level: 1000,
  );
}
