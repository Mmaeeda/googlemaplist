import 'dart:developer' as developer;

enum LogLevel {
  debug,
  info,
  warn,
  error,
}

/// Structured log entry emitted by SyncLogger.
class LogEntry {
  final String event;
  final LogLevel level;
  final DateTime timestamp;
  final String? syncJobId;
  final Map<String, dynamic> data;

  const LogEntry({
    required this.event,
    required this.level,
    required this.timestamp,
    this.syncJobId,
    this.data = const {},
  });

  @override
  String toString() => 'LogEntry($event, ${level.name}, $data)';
}

/// Callback type for external log consumers (e.g., tests, analytics).
typedef LogCallback = void Function(LogEntry entry);

class SyncLogger {
  final String? _syncJobId;
  final LogLevel _minLevel;
  final LogCallback? _onLog;

  /// Keys that must never appear in log output.
  static const _sensitiveKeys = {
    'access_token',
    'refresh_token',
    'api_key',
    'secret',
    'password',
    'authorization',
  };

  SyncLogger({
    String? syncJobId,
    LogLevel minLevel = LogLevel.debug,
    LogCallback? onLog,
  })  : _syncJobId = syncJobId,
        _minLevel = minLevel,
        _onLog = onLog;

  /// Create a child logger with a bound sync job ID.
  SyncLogger withJobId(String jobId) {
    return SyncLogger(syncJobId: jobId, minLevel: _minLevel, onLog: _onLog);
  }

  void debug(String event, [Map<String, dynamic>? data]) {
    _log(LogLevel.debug, event, data);
  }

  void info(String event, [Map<String, dynamic>? data]) {
    _log(LogLevel.info, event, data);
  }

  void warn(String event, [Map<String, dynamic>? data]) {
    _log(LogLevel.warn, event, data);
  }

  void error(String event, [Map<String, dynamic>? data]) {
    _log(LogLevel.error, event, data);
  }

  /// Start a stopwatch and return a function that logs the elapsed time.
  /// Usage:
  /// ```dart
  /// final done = logger.startTimer('zip_extract');
  /// await doWork();
  /// done({'fileCount': 42});
  /// ```
  void Function([Map<String, dynamic>? extraData]) startTimer(String event) {
    final sw = Stopwatch()..start();
    return ([Map<String, dynamic>? extraData]) {
      sw.stop();
      final data = <String, dynamic>{
        'duration_ms': sw.elapsedMilliseconds,
      };
      if (extraData != null) {
        data.addAll(extraData);
      }
      info(event, data);
    };
  }

  void _log(LogLevel level, String event, Map<String, dynamic>? data) {
    if (level.index < _minLevel.index) return;

    final now = DateTime.now();

    final safeData = <String, dynamic>{};
    if (data != null) {
      for (final entry in data.entries) {
        if (!_sensitiveKeys.contains(entry.key.toLowerCase())) {
          safeData[entry.key] = entry.value;
        }
      }
    }

    final entry = LogEntry(
      event: event,
      level: level,
      timestamp: now,
      syncJobId: _syncJobId,
      data: safeData,
    );

    // Notify external listener
    _onLog?.call(entry);

    // Emit to dart:developer log
    final payload = <String, dynamic>{
      'event': event,
      'level': level.name,
      'timestamp': now.toIso8601String(),
    };

    if (_syncJobId != null) {
      payload['sync_job_id'] = _syncJobId;
    }

    payload.addAll(safeData);

    developer.log(
      '$payload',
      name: 'MapsSaved',
      level: _levelToInt(level),
    );
  }

  int _levelToInt(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 500;
      case LogLevel.info:
        return 800;
      case LogLevel.warn:
        return 900;
      case LogLevel.error:
        return 1000;
    }
  }
}
