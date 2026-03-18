import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../domain/models/app_error.dart';
import '../../domain/models/normalized_place_record.dart';
import '../../domain/models/sync_job.dart';
import '../../domain/models/sync_summary.dart';
import '../../domain/repositories/sync_job_repository.dart';
import '../archive/archive_downloader.dart';
import '../archive/archive_extractor.dart';
import '../archive/file_cache_service.dart';
import '../classification/classification_engine.dart';
import '../csv/csv_discovery_service.dart';
import '../csv/csv_parser.dart';
import '../csv/place_normalizer.dart';
import '../drive/takeout_archive_locator.dart';
import '../auth/google_auth_service.dart';
import '../logging/sync_logger.dart';
import 'diff_applier.dart';
import 'diff_engine.dart';

class SyncOptions {
  final bool forceSync;
  final bool rebuildOnly;

  const SyncOptions({
    this.forceSync = false,
    this.rebuildOnly = false,
  });
}

/// Orchestrates the full sync pipeline.
class SyncOrchestrator {
  static const _uuid = Uuid();

  final GoogleAuthService _authService;
  final TakeoutArchiveLocator _archiveLocator;
  final ArchiveDownloader _downloader;
  final ArchiveExtractor _extractor;
  final FileCacheService _cacheService;
  final CsvDiscoveryService _csvDiscovery;
  final CsvParser _csvParser;
  final PlaceNormalizer _normalizer;
  final DiffEngine _diffEngine;
  final DiffApplier _diffApplier;
  final ClassificationOrchestrator _classificationOrchestrator;
  final SyncJobRepository _syncJobRepository;
  final SyncLogger _logger;

  SyncOrchestrator({
    required GoogleAuthService authService,
    required TakeoutArchiveLocator archiveLocator,
    required ArchiveDownloader downloader,
    required ArchiveExtractor extractor,
    required FileCacheService cacheService,
    required CsvDiscoveryService csvDiscovery,
    required CsvParser csvParser,
    required PlaceNormalizer normalizer,
    required DiffEngine diffEngine,
    required DiffApplier diffApplier,
    required ClassificationOrchestrator classificationOrchestrator,
    required SyncJobRepository syncJobRepository,
    required SyncLogger logger,
  })  : _authService = authService,
        _archiveLocator = archiveLocator,
        _downloader = downloader,
        _extractor = extractor,
        _cacheService = cacheService,
        _csvDiscovery = csvDiscovery,
        _csvParser = csvParser,
        _normalizer = normalizer,
        _diffEngine = diffEngine,
        _diffApplier = diffApplier,
        _classificationOrchestrator = classificationOrchestrator,
        _syncJobRepository = syncJobRepository,
        _logger = logger;

  /// Execute the full sync pipeline.
  Future<SyncSummary> runSync([SyncOptions options = const SyncOptions()]) async {
    final jobId = _uuid.v4();
    final logger = _logger.withJobId(jobId);
    final syncTimer = logger.startTimer('sync_total_duration');

    logger.info('sync_started', {
      'forceSync': options.forceSync,
      'rebuildOnly': options.rebuildOnly,
    });

    // Handle rebuild-only mode
    if (options.rebuildOnly) {
      final result = await _runRebuildOnly(jobId, logger);
      syncTimer();
      return result;
    }

    // Create a running sync job
    final job = SyncJob(
      id: jobId,
      archiveIdentifier: '',
      archiveName: '',
      startedAt: DateTime.now(),
      status: SyncJobStatus.running,
    );
    await _syncJobRepository.start(job);

    try {
      // Step 1: Authenticate
      await _authService.ensureAuthenticated();

      // Step 2: Find latest archive
      final archiveGroup = await _archiveLocator.findLatestArchiveGroup();
      if (archiveGroup == null) {
        throw const AppError(
          AppErrorCode.archiveNotFound,
          'No Takeout archives found on Drive',
        );
      }

      // Step 3: Skip if already processed
      if (!options.forceSync) {
        final latestJob = await _syncJobRepository.latest();
        if (latestJob != null &&
            latestJob.status == SyncJobStatus.success &&
            latestJob.archiveIdentifier == archiveGroup.identifier) {
          logger.info('sync_skipped_already_processed', {
            'archiveIdentifier': archiveGroup.identifier,
          });
          await _syncJobRepository.complete(jobId,
            status: SyncJobStatus.success,
          );
          syncTimer();
          return SyncSummary(
            status: 'success',
            archiveName: archiveGroup.displayName,
          );
        }
      }

      // Step 4: Download
      final cacheDir = await _cacheService.getCacheDir();
      final downloadTimer = logger.startTimer('archive_download_completed');
      final localPaths =
          await _downloader.downloadAll(archiveGroup, cacheDir);
      downloadTimer({
        'archiveName': archiveGroup.displayName,
        'fileCount': archiveGroup.files.length,
      });

      // Step 5: Extract
      final extractTimer = logger.startTimer('zip_extract_completed');
      final extractedDir =
          await _extractor.extractAll(localPaths, cacheDir, jobId);
      extractTimer();

      // Step 6: Discover CSVs
      final csvCandidates =
          await _csvDiscovery.findCandidates(extractedDir);

      if (csvCandidates.isEmpty) {
        throw const AppError(
          AppErrorCode.csvNotFound,
          'No Saved-places CSV found in archive',
        );
      }

      // Step 7: Parse + Normalize
      final parseTimer = logger.startTimer('csv_parse_and_normalize_completed');
      final parseResult = await _parseAndNormalize(csvCandidates, logger);
      parseTimer({
        'recordCount': parseResult.records.length,
        'skippedRows': parseResult.skippedRows,
      });

      var totalSkippedRows = parseResult.skippedRows;
      final normalized = parseResult.records;

      // Step 8: Diff
      logger.info('diff_computation_started');
      final diff = await _diffEngine.compute(normalized);
      totalSkippedRows += diff.skippedCount;

      // Step 9: Apply to DB
      logger.info('db_transaction_started');
      final newPlaceIds = await _diffApplier.apply(diff);
      logger.info('db_transaction_completed');

      // Step 10: Classify
      final classifyTimer = logger.startTimer('classification_completed');
      final placeIdsToClassify = [
        ...newPlaceIds,
        ...diff.updatedPlaceIds,
      ];

      var classificationFailed = false;
      try {
        await _classificationOrchestrator.rebuildForPlaces(placeIdsToClassify);
      } catch (e) {
        // Classification failure is non-fatal: mark as partial
        logger.error('classification_failed', {'error': e.toString()});
        classificationFailed = true;
      }
      classifyTimer({'placeCount': placeIdsToClassify.length});

      // Step 11: Complete job
      final status = classificationFailed
          ? SyncJobStatus.partial
          : SyncJobStatus.success;

      await _syncJobRepository.complete(
        jobId,
        status: status,
        newCount: diff.newRecords.length,
        updatedCount: diff.updatedRecords.length,
        unchangedCount: diff.unchangedRecords.length,
        deletedCandidateCount: diff.missingPlaceIds.length,
        skippedRowCount: totalSkippedRows,
      );

      // Step 12: Cleanup (always in finally-like fashion)
      await _safeCleanup(jobId);

      final summary = SyncSummary(
        status: status.value,
        newCount: diff.newRecords.length,
        updatedCount: diff.updatedRecords.length,
        unchangedCount: diff.unchangedRecords.length,
        deletedCandidateCount: diff.missingPlaceIds.length,
        skippedRowCount: totalSkippedRows,
        archiveName: archiveGroup.displayName,
      );

      syncTimer({
        'status': summary.status,
        'newCount': summary.newCount,
        'updatedCount': summary.updatedCount,
      });

      logger.info('sync_completed', {
        'status': summary.status,
        'newCount': summary.newCount,
        'updatedCount': summary.updatedCount,
        'unchangedCount': summary.unchangedCount,
        'deletedCandidateCount': summary.deletedCandidateCount,
        'skippedRowCount': summary.skippedRowCount,
      });

      return summary;
    } on AppError catch (e) {
      logger.error('sync_failed', {
        'errorCode': e.code.name,
        'errorMessage': e.message,
      });
      await _syncJobRepository.fail(jobId, '${e.code.name}: ${e.message}');
      await _safeCleanup(jobId);
      rethrow;
    } catch (e) {
      logger.error('sync_failed', {'error': e.toString()});
      await _syncJobRepository.fail(jobId, e.toString());
      await _safeCleanup(jobId);
      rethrow;
    }
  }

  /// Parse and normalize CSV candidates.
  /// Handles partial failure: if one CSV fails but others exist, continues.
  Future<_ParseResult> _parseAndNormalize(
    List<CsvCandidate> candidates,
    SyncLogger logger,
  ) async {
    final allNormalized = <NormalizedPlaceRecord>[];
    var totalSkipped = 0;
    var failedCsvCount = 0;

    for (final candidate in candidates) {
      try {
        final file = File(candidate.filePath);
        final bytes = await file.readAsBytes();
        final parseResult =
            _csvParser.parse(bytes, fileName: candidate.filePath);

        totalSkipped += parseResult.skippedRowCount;

        for (final raw in parseResult.records) {
          final normalized = _normalizer.normalize(raw);
          allNormalized.add(normalized);
        }

        logger.info('csv_parse_completed', {
          'fileName': candidate.filePath,
          'recordCount': parseResult.records.length,
          'skippedRows': parseResult.skippedRowCount,
        });
      } catch (e) {
        if (e is AppError &&
            (e.code == AppErrorCode.authRequired ||
             e.code == AppErrorCode.tokenExpired)) {
          rethrow; // Auth errors are always fatal
        }

        failedCsvCount++;

        // If other CSVs exist, continue processing
        if (candidates.length > 1) {
          logger.warn('csv_parse_partial_failure', {
            'fileName': candidate.filePath,
            'error': e.toString(),
            'remainingCandidates': candidates.length - failedCsvCount,
          });
          continue;
        }

        throw AppError(
          AppErrorCode.csvParseFailed,
          'CSV parse failed: ${candidate.filePath}',
          e,
        );
      }
    }

    if (allNormalized.isEmpty) {
      throw const AppError(
        AppErrorCode.csvParseFailed,
        'No records extracted from any CSV',
      );
    }

    logger.info('normalization_completed', {
      'totalRecords': allNormalized.length,
      'totalSkipped': totalSkipped,
      'failedCsvCount': failedCsvCount,
    });

    return _ParseResult(records: allNormalized, skippedRows: totalSkipped);
  }

  /// Rebuild classification only (no external fetch).
  Future<SyncSummary> _runRebuildOnly(String jobId, SyncLogger logger) async {
    logger.info('rebuild_only_started');

    try {
      await _classificationOrchestrator.rebuildAll();
      logger.info('rebuild_only_completed');

      return const SyncSummary(
        status: 'success',
        archiveName: null,
      );
    } catch (e) {
      logger.error('rebuild_only_failed', {'error': e.toString()});
      return const SyncSummary(
        status: 'failed',
        archiveName: null,
      );
    }
  }

  /// Cleanup that never throws.
  Future<void> _safeCleanup(String jobId) async {
    try {
      await _cacheService.cleanupJob(jobId);
      await _cacheService.cleanupArchives();
      await _cacheService.cleanupStale();
    } catch (e) {
      _logger.warn('cleanup_failed', {'error': e.toString()});
    }
  }
}

class _ParseResult {
  final List<NormalizedPlaceRecord> records;
  final int skippedRows;

  const _ParseResult({required this.records, required this.skippedRows});
}
