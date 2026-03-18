import 'package:flutter_test/flutter_test.dart';

import 'package:maps_saved_app/infrastructure/logging/sync_logger.dart';

void main() {
  group('SyncLogger', () {
    group('LogCallback', () {
      test('onLog callback receives all log entries', () {
        final entries = <LogEntry>[];
        final logger = SyncLogger(onLog: entries.add);

        logger.info('test_event', {'key': 'value'});

        expect(entries, hasLength(1));
        expect(entries.first.event, 'test_event');
        expect(entries.first.level, LogLevel.info);
        expect(entries.first.data['key'], 'value');
      });

      test('callback receives correct log levels', () {
        final entries = <LogEntry>[];
        final logger = SyncLogger(onLog: entries.add);

        logger.debug('debug_event');
        logger.info('info_event');
        logger.warn('warn_event');
        logger.error('error_event');

        expect(entries, hasLength(4));
        expect(entries[0].level, LogLevel.debug);
        expect(entries[1].level, LogLevel.info);
        expect(entries[2].level, LogLevel.warn);
        expect(entries[3].level, LogLevel.error);
      });

      test('minLevel filters logs below threshold', () {
        final entries = <LogEntry>[];
        final logger = SyncLogger(
          minLevel: LogLevel.warn,
          onLog: entries.add,
        );

        logger.debug('should_skip');
        logger.info('should_skip');
        logger.warn('should_appear');
        logger.error('should_appear');

        expect(entries, hasLength(2));
        expect(entries[0].event, 'should_appear');
        expect(entries[1].event, 'should_appear');
      });

      test('callback includes syncJobId when set', () {
        final entries = <LogEntry>[];
        final logger = SyncLogger(
          syncJobId: 'job-123',
          onLog: entries.add,
        );

        logger.info('test_event');

        expect(entries.first.syncJobId, 'job-123');
      });

      test('withJobId creates child logger with bound job ID', () {
        final entries = <LogEntry>[];
        final parent = SyncLogger(onLog: entries.add);
        final child = parent.withJobId('child-job');

        child.info('child_event');

        expect(entries.first.syncJobId, 'child-job');
      });

      test('withJobId child inherits minLevel and onLog', () {
        final entries = <LogEntry>[];
        final parent = SyncLogger(
          minLevel: LogLevel.warn,
          onLog: entries.add,
        );
        final child = parent.withJobId('child-job');

        child.info('should_skip');
        child.warn('should_appear');

        expect(entries, hasLength(1));
        expect(entries.first.event, 'should_appear');
      });
    });

    group('sensitive key filtering', () {
      test('strips access_token from log data', () {
        final entries = <LogEntry>[];
        final logger = SyncLogger(onLog: entries.add);

        logger.info('auth_event', {
          'access_token': 'secret-token',
          'user': 'test-user',
        });

        expect(entries.first.data.containsKey('access_token'), isFalse);
        expect(entries.first.data['user'], 'test-user');
      });

      test('strips multiple sensitive keys', () {
        final entries = <LogEntry>[];
        final logger = SyncLogger(onLog: entries.add);

        logger.info('auth_event', {
          'access_token': 'token',
          'refresh_token': 'refresh',
          'api_key': 'key',
          'secret': 'shhh',
          'password': 'pass',
          'authorization': 'bearer xyz',
          'safe_field': 'visible',
        });

        final data = entries.first.data;
        expect(data.containsKey('access_token'), isFalse);
        expect(data.containsKey('refresh_token'), isFalse);
        expect(data.containsKey('api_key'), isFalse);
        expect(data.containsKey('secret'), isFalse);
        expect(data.containsKey('password'), isFalse);
        expect(data.containsKey('authorization'), isFalse);
        expect(data['safe_field'], 'visible');
      });

      test('case-insensitive filtering', () {
        final entries = <LogEntry>[];
        final logger = SyncLogger(onLog: entries.add);

        logger.info('test', {
          'Access_Token': 'hidden',
          'AUTHORIZATION': 'hidden',
        });

        final data = entries.first.data;
        expect(data.containsKey('Access_Token'), isFalse);
        expect(data.containsKey('AUTHORIZATION'), isFalse);
      });
    });

    group('startTimer', () {
      test('logs elapsed duration_ms', () async {
        final entries = <LogEntry>[];
        final logger = SyncLogger(onLog: entries.add);

        final done = logger.startTimer('operation_completed');

        // Small delay to ensure elapsed > 0
        await Future.delayed(const Duration(milliseconds: 10));

        done();

        expect(entries, hasLength(1));
        expect(entries.first.event, 'operation_completed');
        expect(entries.first.data.containsKey('duration_ms'), isTrue);
        expect(entries.first.data['duration_ms'], isA<int>());
        expect(entries.first.data['duration_ms'], greaterThanOrEqualTo(0));
      });

      test('includes extra data alongside duration_ms', () {
        final entries = <LogEntry>[];
        final logger = SyncLogger(onLog: entries.add);

        final done = logger.startTimer('download_completed');
        done({'fileCount': 3, 'totalBytes': 1024});

        expect(entries.first.data['duration_ms'], isA<int>());
        expect(entries.first.data['fileCount'], 3);
        expect(entries.first.data['totalBytes'], 1024);
      });

      test('timer logs at info level', () {
        final entries = <LogEntry>[];
        final logger = SyncLogger(onLog: entries.add);

        final done = logger.startTimer('test_timer');
        done();

        expect(entries.first.level, LogLevel.info);
      });
    });

    group('LogEntry', () {
      test('toString includes event, level, and data', () {
        final entry = LogEntry(
          event: 'test_event',
          level: LogLevel.info,
          timestamp: DateTime(2026, 1, 1),
          data: {'key': 'value'},
        );

        expect(entry.toString(), contains('test_event'));
        expect(entry.toString(), contains('info'));
        expect(entry.toString(), contains('key'));
      });
    });
  });
}
