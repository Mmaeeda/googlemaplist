import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/models/app_error.dart';
import '../../domain/models/archive_descriptor.dart';
import '../drive/google_drive_service.dart';
import '../logging/sync_logger.dart';

/// Downloads archive files from Drive to local cache.
class ArchiveDownloader {
  static const _maxRetries = 3;
  static const _retryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 10),
  ];

  final GoogleDriveService _driveService;
  final SyncLogger _logger;

  ArchiveDownloader({
    required GoogleDriveService driveService,
    required SyncLogger logger,
  })  : _driveService = driveService,
        _logger = logger;

  /// Download all files in an archive group to the cache directory.
  /// Returns list of local file paths.
  Future<List<String>> downloadAll(
    ArchiveGroup archiveGroup,
    String cacheDir,
  ) async {
    final archiveDir = p.join(cacheDir, 'archives');
    await Directory(archiveDir).create(recursive: true);

    final localPaths = <String>[];

    for (final file in archiveGroup.files) {
      _logger.info('archive_download_started', {
        'fileId': file.fileId,
        'fileName': file.name,
        'sizeBytes': file.sizeBytes,
      });

      final localPath = p.join(archiveDir, file.name);
      await _downloadWithRetry(file, localPath);
      localPaths.add(localPath);

      _logger.info('archive_download_completed', {
        'fileName': file.name,
        'localPath': localPath,
      });
    }

    return localPaths;
  }

  /// Download a single file with exponential backoff retry.
  Future<void> _downloadWithRetry(ArchiveFile file, String localPath) async {
    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        final bytes = await _driveService.downloadFile(file.fileId);

        // Write to local file
        final outputFile = File(localPath);
        await outputFile.writeAsBytes(bytes);

        // Verify file size if known
        if (file.sizeBytes > 0) {
          final actualSize = await outputFile.length();
          if (actualSize != file.sizeBytes) {
            _logger.warn('archive_download_size_mismatch', {
              'expected': file.sizeBytes,
              'actual': actualSize,
              'fileName': file.name,
            });
          }
        }

        return; // Success
      } catch (e) {
        if (e is AppError &&
            (e.code == AppErrorCode.tokenExpired ||
             e.code == AppErrorCode.authRequired)) {
          rethrow; // Don't retry auth errors
        }

        if (attempt < _maxRetries) {
          final delay = _retryDelays[attempt];
          _logger.warn('archive_download_retry', {
            'fileName': file.name,
            'attempt': attempt + 1,
            'delayMs': delay.inMilliseconds,
            'error': e.toString(),
          });
          await Future.delayed(delay);
        } else {
          throw AppError(
            AppErrorCode.downloadFailed,
            'Download failed after $_maxRetries retries: ${file.name}',
            e,
          );
        }
      }
    }
  }
}
