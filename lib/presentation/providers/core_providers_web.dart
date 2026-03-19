import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/sync_summary.dart';
import '../../domain/repositories/classification_rule_repository.dart';
import '../../domain/repositories/group_repository.dart';
import '../../domain/repositories/place_group_repository.dart';
import '../../domain/repositories/place_repository.dart';
import '../../domain/repositories/sync_job_repository.dart';
import '../../infrastructure/auth/supabase_auth_service.dart';
import '../../infrastructure/classification/classification_engine.dart';
import '../../infrastructure/csv/csv_parser.dart';
import '../../infrastructure/csv/geojson_parser.dart';
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
import '../../infrastructure/sync/sync_pipeline.dart';
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

final geoJsonParserProvider = Provider<GeoJsonParser>((ref) =>
    GeoJsonParser(ref.watch(syncLoggerProvider)));

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
      geoJsonParser: ref.watch(geoJsonParserProvider),
      normalizer: ref.watch(placeNormalizerProvider),
      diffEngine: ref.watch(diffEngineProvider),
      diffApplier: ref.watch(diffApplierProvider),
      classificationOrchestrator: ref.watch(classificationOrchestratorProvider),
      syncJobRepository: ref.watch(syncJobRepositoryProvider),
      logger: ref.watch(syncLoggerProvider),
    ));

// Sync pipeline (common interface for dashboard)
// Always force sync when user explicitly triggers via UI button.
final syncPipelineRunProvider =
    Provider<Future<SyncSummary> Function()>((ref) {
  final orchestrator = ref.watch(webSyncOrchestratorProvider);
  return () => orchestrator.runSync(
        const SyncPipelineOptions(forceSync: true),
      );
});

// Auth state
final authStateProvider =
    AsyncNotifierProvider<AuthStateNotifier, bool>(AuthStateNotifier.new);

class AuthStateNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final client = Supabase.instance.client;
    // Listen for auth state changes (e.g. after OAuth redirect)
    client.auth.onAuthStateChange.listen((data) {
      final isSignedIn = data.session != null;
      state = AsyncData(isSignedIn);
      if (isSignedIn) {
        final authService = ref.read(supabaseAuthServiceProvider);
        // Cache provider token for reuse across sync operations
        final providerToken = data.session!.providerToken;
        if (providerToken != null) {
          authService.cacheProviderToken(providerToken);
        }
        // Seed default data on first login
        authService.seedIfNeeded();
      }
    });
    return client.auth.currentSession != null;
  }

  Future<void> signIn() async {
    state = const AsyncLoading();
    try {
      await ref.read(supabaseAuthServiceProvider).ensureAuthenticated();
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> signOut() async {
    await ref.read(supabaseAuthServiceProvider).signOut();
    state = const AsyncData(false);
  }
}
