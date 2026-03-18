import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:maps_saved_app/infrastructure/archive/file_cache_service.dart';
import 'package:maps_saved_app/infrastructure/logging/sync_logger.dart';

void main() {
  late Directory tempDir;
  late FileCacheService cacheService;
  late SyncLogger logger;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('file_cache_test_');
    logger = SyncLogger(minLevel: LogLevel.error);
    cacheService = FileCacheService.withPath(tempDir.path, logger: logger);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('FileCacheService', () {
    group('cleanupJob', () {
      test('deletes job-specific extraction directory', () async {
        // Create a job directory with files
        final jobDir = Directory(
          p.join(tempDir.path, 'extracted', 'sync_job_test-job-1'),
        );
        await jobDir.create(recursive: true);
        await File(p.join(jobDir.path, 'data.csv')).writeAsString('test');

        expect(await jobDir.exists(), isTrue);

        await cacheService.cleanupJob('test-job-1');

        expect(await jobDir.exists(), isFalse);
      });

      test('does not throw for non-existent job', () async {
        // Should complete without error
        await cacheService.cleanupJob('nonexistent-job');
      });
    });

    group('cleanupArchives', () {
      test('deletes archives directory', () async {
        final archiveDir = Directory(p.join(tempDir.path, 'archives'));
        await archiveDir.create(recursive: true);
        await File(p.join(archiveDir.path, 'test.zip'))
            .writeAsString('zipdata');

        await cacheService.cleanupArchives();

        expect(await archiveDir.exists(), isFalse);
      });
    });

    group('cleanupStale', () {
      test('removes directories older than maxAge', () async {
        // Create an "old" job directory
        final oldJobDir = Directory(
          p.join(tempDir.path, 'extracted', 'sync_job_old-job'),
        );
        await oldJobDir.create(recursive: true);
        await File(p.join(oldJobDir.path, 'data.csv')).writeAsString('old');

        // Use a very short maxAge (0 seconds) to force cleanup
        final removed =
            await cacheService.cleanupStale(Duration.zero);

        expect(removed, 1);
        expect(await oldJobDir.exists(), isFalse);
      });

      test('preserves directories newer than maxAge', () async {
        // Create a "fresh" job directory
        final freshJobDir = Directory(
          p.join(tempDir.path, 'extracted', 'sync_job_fresh-job'),
        );
        await freshJobDir.create(recursive: true);
        await File(p.join(freshJobDir.path, 'data.csv'))
            .writeAsString('fresh');

        // Use a large maxAge (7 days) so nothing gets cleaned
        final removed =
            await cacheService.cleanupStale(const Duration(days: 7));

        expect(removed, 0);
        expect(await freshJobDir.exists(), isTrue);
      });

      test('returns 0 when extracted directory does not exist', () async {
        final removed = await cacheService.cleanupStale();

        expect(removed, 0);
      });

      test('only targets sync_job_ prefixed directories', () async {
        final extractedDir = Directory(p.join(tempDir.path, 'extracted'));
        await extractedDir.create(recursive: true);

        // Create a non-sync_job directory
        final otherDir = Directory(
          p.join(extractedDir.path, 'other_directory'),
        );
        await otherDir.create();

        // Create a sync_job directory
        final jobDir = Directory(
          p.join(extractedDir.path, 'sync_job_target'),
        );
        await jobDir.create();

        final removed =
            await cacheService.cleanupStale(Duration.zero);

        // Only the sync_job_ prefixed directory should be removed
        expect(removed, 1);
        expect(await otherDir.exists(), isTrue);
        expect(await jobDir.exists(), isFalse);
      });

      test('handles multiple stale directories', () async {
        final extractedDir = Directory(p.join(tempDir.path, 'extracted'));
        await extractedDir.create(recursive: true);

        for (var i = 0; i < 3; i++) {
          final dir = Directory(
            p.join(extractedDir.path, 'sync_job_old-$i'),
          );
          await dir.create();
        }

        final removed =
            await cacheService.cleanupStale(Duration.zero);

        expect(removed, 3);
      });
    });

    group('getCacheSize', () {
      test('returns 0 for empty cache', () async {
        final size = await cacheService.getCacheSize();
        expect(size, 0);
      });

      test('calculates total size of files', () async {
        // Create some files with known content
        final content = 'hello world'; // 11 bytes
        final subDir = Directory(p.join(tempDir.path, 'sub'));
        await subDir.create();

        await File(p.join(tempDir.path, 'file1.txt'))
            .writeAsString(content);
        await File(p.join(subDir.path, 'file2.txt'))
            .writeAsString(content);

        final size = await cacheService.getCacheSize();

        // Each file should be 11 bytes
        expect(size, 22);
      });
    });

    group('cleanupAll', () {
      test('removes all cache contents and recreates base directory', () async {
        // Create some files
        await File(p.join(tempDir.path, 'data.txt')).writeAsString('data');
        final subDir = Directory(p.join(tempDir.path, 'sub'));
        await subDir.create();
        await File(p.join(subDir.path, 'nested.txt')).writeAsString('nested');

        await cacheService.cleanupAll();

        // Base directory should exist but be empty
        expect(await Directory(tempDir.path).exists(), isTrue);
        final contents = await Directory(tempDir.path)
            .list()
            .toList();
        expect(contents, isEmpty);
      });
    });
  });
}
