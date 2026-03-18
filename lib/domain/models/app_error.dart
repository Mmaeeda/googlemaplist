enum AppErrorCode {
  authRequired,
  tokenExpired,
  archiveNotFound,
  downloadFailed,
  zipExtractFailed,
  csvNotFound,
  csvParseFailed,
  dbWriteFailed,
  classificationFailed,
}

class AppError implements Exception {
  final AppErrorCode code;
  final String message;
  final Object? cause;

  const AppError(this.code, this.message, [this.cause]);

  @override
  String toString() => 'AppError(${code.name}: $message)';
}
