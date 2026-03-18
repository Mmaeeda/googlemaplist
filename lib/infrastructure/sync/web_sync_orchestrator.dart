import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/app_error.dart';
import '../../domain/models/normalized_place_record.dart';
import '../../domain/models/sync_job.dart';
import '../../domain/models/sync_summary.dart';
import '../../domain/repositories/sync_job_repository.dart';
import '../classification/classification_engine.dart';
import '../csv/csv_parser.dart';
import '../csv/place_normalizer.dart';
import '../drive/google_drive_service.dart';
import '../drive/takeout_archive_locator.dart';
import '../logging/sync_logger.dart';
import 'diff_applier.dart';
import 'diff_engine.dart';
import 'in_memory_csv_candidate.dart';
import 'sync_pipeline.dart';

/// Web sync orchestrator: fully in-memory, no dart:io.
/// Downloads ZIP from Drive → decodes in memory → parses CSV → diff → apply.
class WebSyncOrchestrator implements SyncPipeline {
  static const _uuid = Uuid();

  /// Maximum total archive size to process (200 MB).
  /// Prevents browser memory exhaustion.
  static const _maxTotalArchiveSize = 200 * 1024 * 1024;

  final TakeoutArchiveLocator _archiveLocator;
  final GoogleDriveService _driveService;
  final CsvParser _csvParser;
  final PlaceNormalizer _normalizer;
  final DiffEngine _diffEngine;
  final DiffApplier _diffApplier;
  final ClassificationOrchestrator _classificationOrchestrator;
  final SyncJobRepository _syncJobRepository;
  final SyncLogger _logger;

  // CSV discovery scoring (same logic as CsvDiscoveryService)
  static const _scoredHeaders = {
    'title': 3,
    'note': 2,
    'comments': 2,
    'item_content_url': 3,
    'collection_name': 2,
    'collection_description': 1,
    'url': 2,
  };

  static const _fileNamePatterns = ['saved', 'maps', 'places', 'locations'];

  WebSyncOrchestrator({
    required TakeoutArchiveLocator archiveLocator,
    required GoogleDriveService driveService,
    required CsvParser csvParser,
    required PlaceNormalizer normalizer,
    required DiffEngine diffEngine,
    required DiffApplier diffApplier,
    required ClassificationOrchestrator classificationOrchestrator,
    required SyncJobRepository syncJobRepository,
    required SyncLogger logger,
  })  : _archiveLocator = archiveLocator,
        _driveService = driveService,
        _csvParser = csvParser,
        _normalizer = normalizer,
        _diffEngine = diffEngine,
        _diffApplier = diffApplier,
        _classificationOrchestrator = classificationOrchestrator,
        _syncJobRepository = syncJobRepository,
        _logger = logger;

  @override
  Future<SyncSummary> runSync(
      [SyncPipelineOptions options = const SyncPipelineOptions()]) async {
    final jobId = _uuid.v4();
    final logger = _logger.withJobId(jobId);
    final syncTimer = logger.startTimer('sync_total_duration');

    logger.info('web_sync_started', {
      'forceSync': options.forceSync,
      'rebuildOnly': options.rebuildOnly,
    });

    // Handle rebuild-only mode
    if (options.rebuildOnly) {
      final result = await _runRebuildOnly(logger);
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
      // Step 1: Find latest archive
      final archiveGroup = await _archiveLocator.findLatestArchiveGroup();
      if (archiveGroup == null) {
        throw const AppError(
          AppErrorCode.archiveNotFound,
          'No Takeout archives found on Drive',
        );
      }

      // Step 2: Skip if already processed
      if (!options.forceSync) {
        final latestJob = await _syncJobRepository.latest();
        if (latestJob != null &&
            latestJob.status == SyncJobStatus.success &&
            latestJob.archiveIdentifier == archiveGroup.identifier) {
          logger.info('sync_skipped_already_processed', {
            'archiveIdentifier': archiveGroup.identifier,
          });
          await _syncJobRepository.complete(jobId,
              status: SyncJobStatus.success);
          syncTimer();
          return SyncSummary(
            status: 'success',
            archiveName: archiveGroup.displayName,
          );
        }
      }

      // Step 2.5: Size guard - reject archives that are too large for browser
      if (archiveGroup.totalSizeBytes > _maxTotalArchiveSize) {
        throw AppError(
          AppErrorCode.downloadFailed,
          'Archive too large for web processing: '
              '${archiveGroup.totalSizeBytes} bytes exceeds '
              '$_maxTotalArchiveSize byte limit',
        );
      }

      // Step 3: Download + decode + extract CSVs only
      // Process each ZIP file individually to minimize peak memory usage.
      // Only CSV entries are kept; all other entries are discarded immediately.
      final downloadTimer = logger.startTimer('archive_download_completed');
      final csvCandidates = <InMemoryCsvCandidate>[];

      for (final file in archiveGroup.files) {
        logger.info('archive_download_started', {
          'fileName': file.name,
          'sizeBytes': file.sizeBytes,
        });

        final zipBytes = await _driveService.downloadFile(file.fileId);

        // Decode ZIP and extract only CSV entries
        final Archive archive;
        try {
          archive = ZipDecoder().decodeBytes(zipBytes);
        } catch (e) {
          throw AppError(
            AppErrorCode.zipExtractFailed,
            'Failed to decode ZIP: ${file.name}',
            e,
          );
        }

        for (final entry in archive) {
          if (!entry.isFile) continue;
          final name = entry.name.toLowerCase();
          if (!name.endsWith('.csv')) continue;

          final entryBytes = Uint8List.fromList(entry.content as List<int>);
          final score = _scoreCandidate(entry.name, entryBytes);

          if (score >= 3) {
            csvCandidates.add(InMemoryCsvCandidate(
              fileName: entry.name,
              bytes: entryBytes,
              score: score,
            ));
          }
        }
        // zipBytes and archive go out of scope here → eligible for GC
      }

      downloadTimer({
        'archiveName': archiveGroup.displayName,
        'fileCount': archiveGroup.files.length,
        'csvCandidateCount': csvCandidates.length,
      });

      // Sort by score descending
      csvCandidates.sort((a, b) => b.score.compareTo(a.score));

      _logger.info('web_csv_discovery_completed', {
        'candidateCount': csvCandidates.length,
      });

      if (csvCandidates.isEmpty) {
        throw const AppError(
          AppErrorCode.csvNotFound,
          'No Saved-places CSV found in archive',
        );
      }

      // Step 4: Parse + Normalize
      final parseTimer = logger.startTimer('csv_parse_and_normalize_completed');
      final allNormalized = <NormalizedPlaceRecord>[];
      var totalSkippedRows = 0;
      var failedCsvCount = 0;

      for (final candidate in csvCandidates) {
        try {
          final parseResult =
              _csvParser.parse(candidate.bytes, fileName: candidate.fileName);
          totalSkippedRows += parseResult.skippedRowCount;

          for (final raw in parseResult.records) {
            allNormalized.add(_normalizer.normalize(raw));
          }

          logger.info('csv_parse_completed', {
            'fileName': candidate.fileName,
            'recordCount': parseResult.records.length,
            'skippedRows': parseResult.skippedRowCount,
          });
        } catch (e) {
          if (e is AppError &&
              (e.code == AppErrorCode.authRequired ||
                  e.code == AppErrorCode.tokenExpired)) {
            rethrow;
          }

          failedCsvCount++;

          if (csvCandidates.length > 1) {
            logger.warn('csv_parse_partial_failure', {
              'fileName': candidate.fileName,
              'error': e.toString(),
              'remainingCandidates':
                  csvCandidates.length - failedCsvCount,
            });
            continue;
          }

          throw AppError(
            AppErrorCode.csvParseFailed,
            'CSV parse failed: ${candidate.fileName}',
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

      parseTimer({
        'recordCount': allNormalized.length,
        'skippedRows': totalSkippedRows,
        'failedCsvCount': failedCsvCount,
      });

      // Step 5: Diff
      logger.info('diff_computation_started');
      final diff = await _diffEngine.compute(allNormalized);
      totalSkippedRows += diff.skippedCount;

      // Step 6: Apply
      logger.info('db_transaction_started');
      final newPlaceIds = await _diffApplier.apply(diff);
      logger.info('db_transaction_completed');

      // Step 7: Classify
      final classifyTimer = logger.startTimer('classification_completed');
      final placeIdsToClassify = [
        ...newPlaceIds,
        ...diff.updatedPlaceIds,
      ];

      var classificationFailed = false;
      try {
        await _classificationOrchestrator.rebuildForPlaces(placeIdsToClassify);
      } catch (e) {
        logger.error('classification_failed', {'error': e.toString()});
        classificationFailed = true;
      }
      classifyTimer({'placeCount': placeIdsToClassify.length});

      // Step 8: Complete job
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

      logger.info('web_sync_completed', {
        'status': summary.status,
        'newCount': summary.newCount,
        'updatedCount': summary.updatedCount,
      });

      return summary;
    } on AppError catch (e) {
      logger.error('web_sync_failed', {
        'errorCode': e.code.name,
        'errorMessage': e.message,
      });
      await _syncJobRepository.fail(jobId, '${e.code.name}: ${e.message}');
      rethrow;
    } catch (e) {
      logger.error('web_sync_failed', {'error': e.toString()});
      await _syncJobRepository.fail(jobId, e.toString());
      rethrow;
    }
  }

  /// Score a single CSV entry for relevance.
  int _scoreCandidate(String fullPath, Uint8List bytes) {
    var score = 0;
    final path = fullPath.toLowerCase();

    // Score by filename
    final fileName = path.split('/').last.replaceAll('.csv', '');
    for (final pattern in _fileNamePatterns) {
      if (fileName.contains(pattern)) score += 2;
    }

    // Score by header content (read first 2 KB)
    try {
      final sampleSize = bytes.length < 2048 ? bytes.length : 2048;
      final firstLine = utf8.decode(
        bytes.sublist(0, sampleSize),
        allowMalformed: true,
      );
      final headerLine = firstLine.split('\n').first.toLowerCase();
      for (final headerEntry in _scoredHeaders.entries) {
        if (headerLine.contains(headerEntry.key)) {
          score += headerEntry.value;
        }
      }
    } catch (_) {
      // Can't decode header, score stays as-is
    }

    return score;
  }

  Future<SyncSummary> _runRebuildOnly(SyncLogger logger) async {
    logger.info('rebuild_only_started');
    try {
      await _classificationOrchestrator.rebuildAll();
      logger.info('rebuild_only_completed');
      return const SyncSummary(status: 'success');
    } catch (e) {
      logger.error('rebuild_only_failed', {'error': e.toString()});
      return const SyncSummary(status: 'failed');
    }
  }
}
