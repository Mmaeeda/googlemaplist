import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/app_error.dart';
import '../logging/sync_logger.dart';

/// Extracts ZIP archives with security safeguards.
class ArchiveExtractor {
  /// Maximum allowed total extracted size (500 MB).
  static const _maxExtractedSize = 500 * 1024 * 1024;

  /// Maximum allowed number of extracted files.
  static const _maxFileCount = 10000;

  final SyncLogger _logger;

  ArchiveExtractor({required SyncLogger logger}) : _logger = logger;

  /// Extract all ZIP files to a job-specific directory.
  /// Returns the path to the extraction directory.
  Future<String> extractAll(
    List<String> zipPaths,
    String extractBaseDir,
    String jobId,
  ) async {
    final extractDir = p.join(extractBaseDir, 'extracted', 'sync_job_$jobId');
    await Directory(extractDir).create(recursive: true);

    for (final zipPath in zipPaths) {
      _logger.info('zip_extract_started', {
        'zipPath': zipPath,
        'extractDir': extractDir,
      });

      await _extractSingle(zipPath, extractDir);

      _logger.info('zip_extract_completed', {'zipPath': zipPath});
    }

    return extractDir;
  }

  /// Extract a single ZIP file with safety checks.
  Future<void> _extractSingle(String zipPath, String extractDir) async {
    final file = File(zipPath);
    if (!await file.exists()) {
      throw AppError(
        AppErrorCode.zipExtractFailed,
        'ZIP file not found: $zipPath',
      );
    }

    final bytes = await file.readAsBytes();

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw AppError(
        AppErrorCode.zipExtractFailed,
        'Failed to decode ZIP: $zipPath',
        e,
      );
    }

    var totalSize = 0;
    var fileCount = 0;

    for (final entry in archive) {
      // Skip directories
      if (entry.isFile) {
        // Zip Slip protection: validate path
        final entryName = _sanitizePath(entry.name);
        if (entryName == null) {
          _logger.warn('zip_extract_skipped_unsafe_path', {
            'originalName': entry.name,
          });
          continue;
        }

        final outputPath = p.join(extractDir, entryName);

        // Verify the resolved path is within the extract directory
        final resolvedPath = p.normalize(p.absolute(outputPath));
        final resolvedExtractDir = p.normalize(p.absolute(extractDir));
        if (!resolvedPath.startsWith(resolvedExtractDir)) {
          _logger.warn('zip_extract_skipped_path_traversal', {
            'entryName': entry.name,
            'resolvedPath': resolvedPath,
          });
          continue;
        }

        // Size limit check
        totalSize += entry.size;
        if (totalSize > _maxExtractedSize) {
          throw AppError(
            AppErrorCode.zipExtractFailed,
            'Extracted size exceeds limit: $totalSize > $_maxExtractedSize',
          );
        }

        // File count limit check
        fileCount++;
        if (fileCount > _maxFileCount) {
          throw AppError(
            AppErrorCode.zipExtractFailed,
            'Extracted file count exceeds limit: $fileCount > $_maxFileCount',
          );
        }

        // Create parent directories and write file
        final outputFile = File(outputPath);
        await outputFile.parent.create(recursive: true);
        await outputFile.writeAsBytes(entry.content as List<int>);
      }
    }

    _logger.info('zip_extract_stats', {
      'totalFiles': fileCount,
      'totalSizeBytes': totalSize,
    });
  }

  /// Sanitize a file path from within a ZIP to prevent path traversal.
  /// Returns null if the path is unsafe.
  String? _sanitizePath(String entryName) {
    // Reject empty names
    if (entryName.isEmpty) return null;

    // Normalize path separators
    var sanitized = entryName.replaceAll('\\', '/');

    // Reject absolute paths
    if (sanitized.startsWith('/')) return null;

    // Reject paths with parent directory references
    final parts = sanitized.split('/');
    if (parts.any((part) => part == '..')) return null;

    // Reject hidden files (starting with .)
    final fileName = parts.last;
    if (fileName.startsWith('.') && fileName != '.') return null;

    return sanitized;
  }
}
