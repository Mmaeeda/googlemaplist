import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/sync_summary.dart';
import '../../domain/repositories/classification_rule_repository.dart';
import '../../domain/repositories/group_repository.dart';
import '../../domain/repositories/place_group_repository.dart';
import '../../domain/repositories/place_repository.dart';
import '../../domain/repositories/sync_job_repository.dart';
import '../../infrastructure/archive/archive_downloader.dart';
import '../../infrastructure/archive/archive_extractor.dart';
import '../../infrastructure/archive/file_cache_service.dart';
import '../../infrastructure/auth/google_auth_service.dart';
import '../../infrastructure/classification/classification_engine.dart';
import '../../infrastructure/csv/csv_discovery_service.dart';
import '../../infrastructure/csv/csv_parser.dart';
import '../../infrastructure/csv/place_normalizer.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/database/sqlite_classification_rule_repository.dart';
import '../../infrastructure/database/sqlite_group_repository.dart';
import '../../infrastructure/database/sqlite_place_group_repository.dart';
import '../../infrastructure/database/sqlite_place_repository.dart';
import '../../infrastructure/database/sqlite_sync_job_repository.dart';
import '../../infrastructure/drive/google_drive_service.dart';
import '../../infrastructure/drive/takeout_archive_locator.dart';
import '../../infrastructure/logging/sync_logger.dart';
import '../../infrastructure/sync/diff_applier.dart';
import '../../infrastructure/sync/diff_engine.dart';
import '../../infrastructure/sync/source_key_generator.dart';
import '../../infrastructure/sync/sync_orchestrator.dart';

// Database
final appDatabaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

// Repositories
final placeRepositoryProvider = Provider<PlaceRepository>((ref) =>
    SqlitePlaceRepository(ref.watch(appDatabaseProvider)));

final groupRepositoryProvider = Provider<GroupRepository>((ref) =>
    SqliteGroupRepository(ref.watch(appDatabaseProvider)));

final classificationRuleRepositoryProvider =
    Provider<ClassificationRuleRepository>((ref) =>
        SqliteClassificationRuleRepository(ref.watch(appDatabaseProvider)));

final syncJobRepositoryProvider = Provider<SyncJobRepository>((ref) =>
    SqliteSyncJobRepository(ref.watch(appDatabaseProvider)));

final placeGroupRepositoryProvider = Provider<PlaceGroupRepository>((ref) =>
    SqlitePlaceGroupRepository(ref.watch(appDatabaseProvider)));

// Logging
final syncLoggerProvider = Provider<SyncLogger>((ref) => SyncLogger());

// Auth
final googleAuthServiceProvider = Provider<GoogleAuthService>((ref) =>
    GoogleAuthService(logger: ref.watch(syncLoggerProvider)));

// Drive
final googleDriveServiceProvider = Provider<GoogleDriveService>((ref) {
  final service = GoogleDriveService(
    authService: ref.watch(googleAuthServiceProvider),
    logger: ref.watch(syncLoggerProvider),
  );
  ref.onDispose(() => service.dispose());
  return service;
});

final takeoutArchiveLocatorProvider = Provider<TakeoutArchiveLocator>((ref) =>
    TakeoutArchiveLocator(
      driveService: ref.watch(googleDriveServiceProvider),
      logger: ref.watch(syncLoggerProvider),
    ));

// Archive
final archiveDownloaderProvider = Provider<ArchiveDownloader>((ref) =>
    ArchiveDownloader(
      driveService: ref.watch(googleDriveServiceProvider),
      logger: ref.watch(syncLoggerProvider),
    ));

final archiveExtractorProvider = Provider<ArchiveExtractor>((ref) =>
    ArchiveExtractor(logger: ref.watch(syncLoggerProvider)));

final fileCacheServiceProvider = Provider<FileCacheService>((ref) =>
    FileCacheService(logger: ref.watch(syncLoggerProvider)));

// CSV
final csvDiscoveryServiceProvider = Provider<CsvDiscoveryService>((ref) =>
    CsvDiscoveryService(ref.watch(syncLoggerProvider)));

final csvParserProvider = Provider<CsvParser>((ref) =>
    CsvParser(ref.watch(syncLoggerProvider)));

final placeNormalizerProvider = Provider<PlaceNormalizer>((ref) =>
    PlaceNormalizer());

// Sync
final sourceKeyGeneratorProvider = Provider<SourceKeyGenerator>((ref) =>
    SourceKeyGenerator());

final diffEngineProvider = Provider<DiffEngine>((ref) => DiffEngine(
      ref.watch(placeRepositoryProvider),
      ref.watch(sourceKeyGeneratorProvider),
      ref.watch(syncLoggerProvider),
    ));

final diffApplierProvider = Provider<DiffApplier>((ref) => DiffApplier(
      ref.watch(placeRepositoryProvider),
      ref.watch(sourceKeyGeneratorProvider),
      ref.watch(syncLoggerProvider),
    ));

// Classification
final ruleBasedClassifierProvider =
    Provider<RuleBasedClassificationEngine>((ref) =>
        RuleBasedClassificationEngine(
          ref.watch(classificationRuleRepositoryProvider),
          ref.watch(syncLoggerProvider),
        ));

final classificationOrchestratorProvider =
    Provider<ClassificationOrchestrator>((ref) => ClassificationOrchestrator(
          ref.watch(ruleBasedClassifierProvider),
          ref.watch(placeRepositoryProvider),
          ref.watch(placeGroupRepositoryProvider),
          ref.watch(groupRepositoryProvider),
          ref.watch(syncLoggerProvider),
        ));

// Sync Orchestrator
final syncOrchestratorProvider = Provider<SyncOrchestrator>((ref) =>
    SyncOrchestrator(
      authService: ref.watch(googleAuthServiceProvider),
      archiveLocator: ref.watch(takeoutArchiveLocatorProvider),
      downloader: ref.watch(archiveDownloaderProvider),
      extractor: ref.watch(archiveExtractorProvider),
      cacheService: ref.watch(fileCacheServiceProvider),
      csvDiscovery: ref.watch(csvDiscoveryServiceProvider),
      csvParser: ref.watch(csvParserProvider),
      normalizer: ref.watch(placeNormalizerProvider),
      diffEngine: ref.watch(diffEngineProvider),
      diffApplier: ref.watch(diffApplierProvider),
      classificationOrchestrator: ref.watch(classificationOrchestratorProvider),
      syncJobRepository: ref.watch(syncJobRepositoryProvider),
      logger: ref.watch(syncLoggerProvider),
    ));

// Sync pipeline (common interface for dashboard)
final syncPipelineRunProvider =
    Provider<Future<SyncSummary> Function()>((ref) {
  final orchestrator = ref.watch(syncOrchestratorProvider);
  return () => orchestrator.runSync();
});
