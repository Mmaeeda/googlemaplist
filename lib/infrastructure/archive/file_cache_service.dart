import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../logging/sync_logger.dart';

/// Manages temporary file storage for archive downloads and extraction.
class FileCacheService {
  static const _defaultMaxAge = Duration(hours: 24);

  final SyncLogger _logger;
  String? _cacheBasePath;

  FileCacheService({required SyncLogger logger}) : _logger = logger;

  /// For testing: allow injecting a custom cache path.
  FileCacheService.withPath(String basePath, {required SyncLogger logger})
      : _cacheBasePath = basePath,
        _logger = logger;

  /// Get the base cache directory path.
  Future<String> getCacheDir() async {
    if (_cacheBasePath != null) return _cacheBasePath!;

    final appDir = await getApplicationCacheDirectory();
    _cacheBasePath = p.join(appDir.path, 'maps_saved_cache');
    await Directory(_cacheBasePath!).create(recursive: true);
    return _cacheBasePath!;
  }

  /// Clean up all files for a specific sync job.
  Future<void> cleanupJob(String jobId) async {
    final cacheDir = await getCacheDir();

    // Clean extracted files
    final extractedDir =
        Directory(p.join(cacheDir, 'extracted', 'sync_job_$jobId'));
    await _safeDelete(extractedDir);

    _logger.info('cache_cleanup_completed', {'jobId': jobId});
  }

  /// Clean up downloaded archive files.
  Future<void> cleanupArchives() async {
    final cacheDir = await getCacheDir();
    final archiveDir = Directory(p.join(cacheDir, 'archives'));
    await _safeDelete(archiveDir);
  }

  /// Remove stale job directories older than [maxAge].
  /// Scans the extracted/ directory for sync_job_* folders and deletes
  /// any whose last-modified time exceeds the threshold.
  Future<int> cleanupStale([Duration maxAge = _defaultMaxAge]) async {
    final cacheDir = await getCacheDir();
    final extractedDir = Directory(p.join(cacheDir, 'extracted'));

    if (!await extractedDir.exists()) return 0;

    final cutoff = DateTime.now().subtract(maxAge);
    var removedCount = 0;

    try {
      await for (final entity in extractedDir.list()) {
        if (entity is! Directory) continue;
        if (!p.basename(entity.path).startsWith('sync_job_')) continue;

        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete(recursive: true);
            removedCount++;
          }
        } catch (e) {
          _logger.warn('stale_cleanup_item_failed', {
            'path': entity.path,
            'error': e.toString(),
          });
        }
      }
    } catch (e) {
      _logger.warn('stale_cleanup_scan_failed', {'error': e.toString()});
    }

    if (removedCount > 0) {
      _logger.info('stale_cleanup_completed', {
        'removedCount': removedCount,
        'maxAgeHours': maxAge.inHours,
      });
    }

    return removedCount;
  }

  /// Calculate total cache size in bytes.
  Future<int> getCacheSize() async {
    final cacheDir = await getCacheDir();
    final dir = Directory(cacheDir);

    if (!await dir.exists()) return 0;

    var totalBytes = 0;
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          totalBytes += await entity.length();
        }
      }
    } catch (e) {
      _logger.warn('cache_size_scan_failed', {'error': e.toString()});
    }

    return totalBytes;
  }

  /// Clean up everything in the cache.
  Future<void> cleanupAll() async {
    final cacheDir = await getCacheDir();
    final dir = Directory(cacheDir);
    await _safeDelete(dir);
    // Recreate base directory
    await dir.create(recursive: true);
  }

  /// Safely delete a directory, logging but not throwing on failure.
  Future<void> _safeDelete(Directory dir) async {
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      _logger.warn('cache_cleanup_failed', {
        'path': dir.path,
        'error': e.toString(),
      });
    }
  }
}
