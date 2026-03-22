import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/app_error.dart';
import '../../domain/models/archive_descriptor.dart';
import '../../domain/models/normalized_place_record.dart';
import '../../domain/models/sync_job.dart';
import '../../domain/models/sync_summary.dart';
import '../../domain/repositories/sync_job_repository.dart';
import '../classification/classification_engine.dart';
import '../csv/csv_parser.dart';
import '../csv/geojson_parser.dart';
import '../csv/place_normalizer.dart';
import '../drive/google_drive_service.dart';
import '../drive/takeout_archive_locator.dart';
import '../geocoding/place_name_resolver.dart';
import '../logging/sync_logger.dart';
import 'diff_applier.dart';
import 'diff_engine.dart';
import 'in_memory_csv_candidate.dart';
import 'sync_pipeline.dart';

/// Web sync orchestrator: fully in-memory, no dart:io.
/// Downloads ZIP from Drive → decodes in memory → parses CSV/GeoJSON → diff → apply.
class WebSyncOrchestrator implements SyncPipeline {
  static const _uuid = Uuid();

  /// Maximum total archive size to process (200 MB).
  /// Prevents browser memory exhaustion.
  static const _maxTotalArchiveSize = 200 * 1024 * 1024;

  final TakeoutArchiveLocator _archiveLocator;
  final GoogleDriveService _driveService;
  final CsvParser _csvParser;
  final GeoJsonParser _geoJsonParser;
  final PlaceNormalizer _normalizer;
  final DiffEngine _diffEngine;
  final DiffApplier _diffApplier;
  final ClassificationOrchestrator _classificationOrchestrator;
  final PlaceNameResolver _placeNameResolver;
  final SyncJobRepository _syncJobRepository;
  final SyncLogger _logger;

  // CSV discovery scoring (same logic as CsvDiscoveryService)
  static const _scoredHeaders = {
    // English headers
    'title': 3,
    'note': 2,
    'comments': 2,
    'comment': 2,
    'item_content_url': 3,
    'collection_name': 2,
    'collection_description': 1,
    'url': 2,
    'updated': 1,
    // Japanese headers
    'タイトル': 3,
    'メモ': 2,
    'コメント': 2,
    '説明': 1,
  };

  static const _fileNamePatterns = [
    // English
    'saved', 'maps', 'places', 'locations', 'favorite', 'want to go',
    // Japanese
    '保存', 'マップ', '場所', 'マイプレイス', 'お気に入り',
    '行きたい', '行ってみたい', 'スター',
  ];

  WebSyncOrchestrator({
    required TakeoutArchiveLocator archiveLocator,
    required GoogleDriveService driveService,
    required CsvParser csvParser,
    required GeoJsonParser geoJsonParser,
    required PlaceNormalizer normalizer,
    required DiffEngine diffEngine,
    required DiffApplier diffApplier,
    required ClassificationOrchestrator classificationOrchestrator,
    required PlaceNameResolver placeNameResolver,
    required SyncJobRepository syncJobRepository,
    required SyncLogger logger,
  }) : _archiveLocator = archiveLocator,
       _driveService = driveService,
       _csvParser = csvParser,
       _geoJsonParser = geoJsonParser,
       _normalizer = normalizer,
       _diffEngine = diffEngine,
       _diffApplier = diffApplier,
       _classificationOrchestrator = classificationOrchestrator,
       _placeNameResolver = placeNameResolver,
       _syncJobRepository = syncJobRepository,
       _logger = logger;

  @override
  Future<SyncSummary> runSync([
    SyncPipelineOptions options = const SyncPipelineOptions(),
  ]) async {
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
      // Step 1: Find candidate archives (latest first)
      final archiveGroups = await _archiveLocator.findArchiveGroupsSorted();
      if (archiveGroups.isEmpty) {
        throw const AppError(
          AppErrorCode.archiveNotFound,
          'No Takeout archives found on Drive',
        );
      }

      // Step 2: Collect data file candidates from ALL archive groups.
      // Multiple Takeout exports (e.g. "マップ" + "保存済み") may contain
      // different data that must be merged for correct sync.
      var csvCandidates = <InMemoryCsvCandidate>[];
      var checkedGroupCount = 0;
      var oversizedGroupCount = 0;
      var lastDiagnosticFiles = <String>[];
      final usedArchiveNames = <String>[];
      final usedIdentifiers = <String>[];

      for (final candidateGroup in archiveGroups) {
        checkedGroupCount++;

        // Size guard
        if (candidateGroup.totalSizeBytes > _maxTotalArchiveSize) {
          oversizedGroupCount++;
          logger.warn('archive_skipped_too_large', {
            'archiveName': candidateGroup.displayName,
            'sizeBytes': candidateGroup.totalSizeBytes,
            'maxBytes': _maxTotalArchiveSize,
          });
          continue;
        }

        final discovery = await _discoverCsvCandidates(candidateGroup, logger);
        if (discovery.allFileNames.isNotEmpty) {
          lastDiagnosticFiles = discovery.allFileNames;
        }

        if (discovery.csvCandidates.isNotEmpty) {
          csvCandidates.addAll(discovery.csvCandidates);
          usedArchiveNames.add(candidateGroup.displayName);
          usedIdentifiers.add(candidateGroup.identifier);
          logger.info('archive_with_data_found', {
            'archiveName': candidateGroup.displayName,
            'archiveIdentifier': candidateGroup.identifier,
            'dataCandidateCount': discovery.csvCandidates.length,
          });
        } else {
          logger.warn('archive_skipped_no_data_files', {
            'archiveName': candidateGroup.displayName,
            'allFileCount': discovery.allFileNames.length,
          });
        }
      }

      // Sort all candidates by score descending
      csvCandidates.sort((a, b) => b.score.compareTo(a.score));

      if (csvCandidates.isEmpty) {
        if (oversizedGroupCount == archiveGroups.length) {
          throw AppError(
            AppErrorCode.downloadFailed,
            'Drive上のTakeoutアーカイブがすべてサイズ上限超過です。\n'
            '上限: $_maxTotalArchiveSize bytes\n'
            '対象件数: ${archiveGroups.length}',
          );
        }

        throw AppError(
          AppErrorCode.csvNotFound,
          '確認したTakeoutアーカイブ($checkedGroupCount件)内に対象データファイルが見つかりません。\n'
          '最後に確認したZIP内の全ファイル(${lastDiagnosticFiles.length}件): '
          '${lastDiagnosticFiles.isEmpty ? "なし" : lastDiagnosticFiles.join(", ")}',
        );
      }

      // Combined identifier from all contributing archives
      final archiveIdentifier = (List<String>.from(usedIdentifiers)..sort()).join('+');
      final archiveDisplayName = usedArchiveNames.join(' + ');

      logger.info('archives_merged', {
        'archiveCount': usedArchiveNames.length,
        'totalCandidates': csvCandidates.length,
        'archiveNames': usedArchiveNames,
      });

      // Step 3: Skip if already processed (all archives unchanged)
      if (!options.forceSync) {
        final latestJob = await _syncJobRepository.latest();
        if (latestJob != null &&
            latestJob.status == SyncJobStatus.success &&
            latestJob.archiveIdentifier == archiveIdentifier) {
          logger.info('sync_skipped_already_processed', {
            'archiveIdentifier': archiveIdentifier,
          });
          await _syncJobRepository.complete(
            jobId,
            status: SyncJobStatus.success,
          );
          syncTimer();
          return SyncSummary(
            status: 'success',
            archiveName: archiveDisplayName,
          );
        }
      }

      // Step 4: Parse + Normalize
      final parseTimer = logger.startTimer('csv_parse_and_normalize_completed');
      final allNormalized = <NormalizedPlaceRecord>[];
      var totalSkippedRows = 0;
      var failedCsvCount = 0;
      final fileBreakdown = <String, String>{};

      for (final candidate in csvCandidates) {
        try {
          final isJson =
              candidate.fileName.toLowerCase().endsWith('.json') ||
              candidate.fileName.toLowerCase().endsWith('.geojson');

          if (isJson) {
            // Parse as GeoJSON
            final parseResult = _geoJsonParser.parse(
              candidate.bytes,
              fileName: candidate.fileName,
            );
            totalSkippedRows += parseResult.skippedCount;

            // Derive collection name from filename
            final collectionName = candidate.fileName
                .split('/')
                .last
                .replaceAll(RegExp(r'\.(geo)?json$', caseSensitive: false), '');

            for (final record in parseResult.records) {
              allNormalized.add(
                record.copyWith(
                  collectionName: record.collectionName ?? collectionName,
                ),
              );
            }

            final shortName = candidate.fileName.split('/').last;
            fileBreakdown[shortName] = '${parseResult.records.length}件';

            logger.info('geojson_parse_completed', {
              'fileName': candidate.fileName,
              'recordCount': parseResult.records.length,
              'skippedCount': parseResult.skippedCount,
            });
          } else {
            // Parse as CSV
            final parseResult = _csvParser.parse(
              candidate.bytes,
              fileName: candidate.fileName,
            );
            totalSkippedRows += parseResult.skippedRowCount;

            // Derive collection name from filename for CSVs without
            // a collection_name column (e.g. Saved section per-list CSVs)
            final csvCollectionName = candidate.fileName
                .split('/')
                .last
                .replaceAll(RegExp(r'\.csv$', caseSensitive: false), '');

            for (final raw in parseResult.records) {
              final normalized = _normalizer.normalize(raw);
              allNormalized.add(
                normalized.collectionName != null
                    ? normalized
                    : normalized.copyWith(collectionName: csvCollectionName),
              );
            }

            final shortName = candidate.fileName.split('/').last;
            if (parseResult.records.isEmpty) {
              // Diagnostic info for 0-record CSVs
              final byteLen = candidate.bytes.length;
              final headersStr = parseResult.headers.join(',');
              fileBreakdown[shortName] =
                  '0件 (${parseResult.totalDataRows}行/${byteLen}B, h: $headersStr)';

              // Log content preview for debugging
              final previewLen = byteLen < 500 ? byteLen : 500;
              final preview = utf8.decode(
                candidate.bytes.sublist(0, previewLen),
                allowMalformed: true,
              );
              logger.warn('csv_zero_records', {
                'fileName': candidate.fileName,
                'byteLength': byteLen,
                'totalDataRows': parseResult.totalDataRows,
                'skippedRows': parseResult.skippedRowCount,
                'headers': parseResult.headers,
                'contentPreview': preview,
              });
            } else {
              fileBreakdown[shortName] = '${parseResult.records.length}件';
            }

            logger.info('csv_parse_completed', {
              'fileName': candidate.fileName,
              'recordCount': parseResult.records.length,
              'totalDataRows': parseResult.totalDataRows,
              'skippedRows': parseResult.skippedRowCount,
              'headers': parseResult.headers,
              'derivedCollectionName': csvCollectionName,
            });
          }
        } catch (e) {
          if (e is AppError &&
              (e.code == AppErrorCode.authRequired ||
                  e.code == AppErrorCode.tokenExpired)) {
            rethrow;
          }

          failedCsvCount++;

          if (csvCandidates.length > 1) {
            logger.warn('parse_partial_failure', {
              'fileName': candidate.fileName,
              'error': e.toString(),
              'remainingCandidates': csvCandidates.length - failedCsvCount,
            });
            continue;
          }

          throw AppError(
            AppErrorCode.csvParseFailed,
            'Parse failed: ${candidate.fileName}',
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
      final placeIdsToClassify = [...newPlaceIds, ...diff.updatedPlaceIds];

      var classificationFailed = false;
      try {
        await _classificationOrchestrator.rebuildForPlaces(placeIdsToClassify);
      } catch (e) {
        logger.error('classification_failed', {'error': e.toString()});
        classificationFailed = true;
      }
      classifyTimer({'placeCount': placeIdsToClassify.length});

      // Step 8: Resolve place names via reverse geocoding
      final resolveTimer = logger.startTimer('name_resolution_completed');
      var resolvedNameCount = 0;
      try {
        resolvedNameCount = await _placeNameResolver.resolveAll();
      } catch (e) {
        logger.warn('name_resolution_failed', {'error': e.toString()});
      }
      resolveTimer({'resolvedCount': resolvedNameCount});

      // Step 9: Complete job
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
        archiveName: archiveDisplayName,
        archiveGroupCount: usedArchiveNames.length,
        dataFileCount: csvCandidates.length,
        parsedRecordCount: allNormalized.length,
        fileBreakdown: fileBreakdown,
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

  Future<_ArchiveCsvDiscoveryResult> _discoverCsvCandidates(
    ArchiveGroup archiveGroup,
    SyncLogger logger,
  ) async {
    final csvCandidates = <InMemoryCsvCandidate>[];
    final allFileNames = <String>[];
    final downloadTimer = logger.startTimer('archive_download_completed');

    // Process each ZIP file individually to minimize peak memory usage.
    // Only CSV entries are kept; all other entries are discarded immediately.
    for (final file in archiveGroup.files) {
      logger.info('archive_download_started', {
        'archiveName': archiveGroup.displayName,
        'fileName': file.name,
        'sizeBytes': file.sizeBytes,
      });

      final zipBytes = await _driveService.downloadFile(file.fileId);

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
        allFileNames.add(entry.name);

        final name = entry.name.toLowerCase();
        final isCsv = name.endsWith('.csv');
        final isJson = name.endsWith('.json') || name.endsWith('.geojson');

        // Skip archive_browser.html and other non-data files
        if (!isCsv && !isJson) continue;

        final entryBytes = Uint8List.fromList(entry.content as List<int>);

        if (isCsv) {
          final score = _scoreCandidate(entry.name, entryBytes);
          if (score >= 3) {
            csvCandidates.add(
              InMemoryCsvCandidate(
                fileName: entry.name,
                bytes: entryBytes,
                score: score,
              ),
            );
          }
        } else if (isJson) {
          // JSON/GeoJSON files from Takeout are always relevant
          // Score by filename patterns
          final jsonFileName = name.split('/').last;
          var score = 3; // Base score for JSON (always consider)
          for (final pattern in _fileNamePatterns) {
            if (jsonFileName.contains(pattern)) score += 2;
          }
          csvCandidates.add(
            InMemoryCsvCandidate(
              fileName: entry.name,
              bytes: entryBytes,
              score: score,
            ),
          );
        }
      }
    }

    // Sort by score descending
    csvCandidates.sort((a, b) => b.score.compareTo(a.score));
    downloadTimer({
      'archiveName': archiveGroup.displayName,
      'fileCount': archiveGroup.files.length,
      'allFileCount': allFileNames.length,
      'csvCandidateCount': csvCandidates.length,
    });

    return _ArchiveCsvDiscoveryResult(
      csvCandidates: csvCandidates,
      allFileNames: allFileNames,
    );
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

class _ArchiveCsvDiscoveryResult {
  final List<InMemoryCsvCandidate> csvCandidates;
  final List<String> allFileNames;

  const _ArchiveCsvDiscoveryResult({
    required this.csvCandidates,
    required this.allFileNames,
  });
}
