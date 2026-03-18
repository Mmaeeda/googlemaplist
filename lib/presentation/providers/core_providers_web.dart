import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/sync_summary.dart';
import '../../domain/repositories/classification_rule_repository.dart';
import '../../domain/repositories/group_repository.dart';
import '../../domain/repositories/place_group_repository.dart';
import '../../domain/repositories/place_repository.dart';
import '../../domain/repositories/sync_job_repository.dart';
import '../../infrastructure/auth/supabase_auth_service.dart';
import '../../infrastructure/classification/classification_engine.dart';
import '../../infrastructure/csv/csv_parser.dart';
import '../../infrastructure/csv/place_normalizer.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/drive/google_drive_service.dart';
import '../../infrastructure/drive/takeout_archive_locator.dart';
import '../../infrastructure/logging/sync_logger.dart';
import '../../infrastructure/supabase/supabase_classification_rule_repository.dart';
import '../../infrastructure/supabase/supabase_group_repository.dart';
import '../../infrastructure/supabase/supabase_place_group_repository.dart';
import '../../infrastructure/supabase/supabase_place_repository.dart';
import '../../infrastructure/supabase/supabase_sync_job_repository.dart';
import '../../infrastructure/sync/diff_applier.dart';
import '../../infrastructure/sync/diff_engine.dart';
import '../../infrastructure/sync/source_key_generator.dart';
import '../../infrastructure/sync/web_sync_orchestrator.dart';

// Database (stub for web — not used, but required for type compatibility)
final appDatabaseProvider = Provider<AppDatabase>((ref) =>
    throw UnsupportedError('AppDatabase is not available on web'));

// Repositories (Supabase implementations)
final placeRepositoryProvider = Provider<PlaceRepository>((ref) =>
    SupabasePlaceRepository());

final groupRepositoryProvider = Provider<GroupRepository>((ref) =>
    SupabaseGroupRepository());

final classificationRuleRepositoryProvider =
    Provider<ClassificationRuleRepository>((ref) =>
        SupabaseClassificationRuleRepository());

final syncJobRepositoryProvider = Provider<SyncJobRepository>((ref) =>
    SupabaseSyncJobRepository());

final placeGroupRepositoryProvider = Provider<PlaceGroupRepository>((ref) =>
    SupabasePlaceGroupRepository());

// Logging
final syncLoggerProvider = Provider<SyncLogger>((ref) => SyncLogger());

// Auth (Supabase)
final supabaseAuthServiceProvider = Provider<SupabaseAuthService>((ref) =>
    SupabaseAuthService(logger: ref.watch(syncLoggerProvider)));

// Drive (uses SupabaseAuthService as AuthTokenProvider)
final googleDriveServiceProvider = Provider<GoogleDriveService>((ref) {
  final service = GoogleDriveService(
    authService: ref.watch(supabaseAuthServiceProvider),
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

// CSV
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

// Web Sync Orchestrator
final webSyncOrchestratorProvider = Provider<WebSyncOrchestrator>((ref) =>
    WebSyncOrchestrator(
      archiveLocator: ref.watch(takeoutArchiveLocatorProvider),
      driveService: ref.watch(googleDriveServiceProvider),
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
  final orchestrator = ref.watch(webSyncOrchestratorProvider);
  return () => orchestrator.runSync();
});
