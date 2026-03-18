// Stub file for conditional import.
// This file should never actually be used at runtime.
// It exists solely to satisfy the Dart analyzer when neither
// dart.library.io nor dart.library.html is available.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/sync_summary.dart';
import '../../domain/repositories/classification_rule_repository.dart';
import '../../domain/repositories/group_repository.dart';
import '../../domain/repositories/place_group_repository.dart';
import '../../domain/repositories/place_repository.dart';
import '../../domain/repositories/sync_job_repository.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/logging/sync_logger.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) =>
    throw UnsupportedError('Platform not supported'));

final placeRepositoryProvider = Provider<PlaceRepository>((ref) =>
    throw UnsupportedError('Platform not supported'));

final groupRepositoryProvider = Provider<GroupRepository>((ref) =>
    throw UnsupportedError('Platform not supported'));

final classificationRuleRepositoryProvider =
    Provider<ClassificationRuleRepository>((ref) =>
        throw UnsupportedError('Platform not supported'));

final syncJobRepositoryProvider = Provider<SyncJobRepository>((ref) =>
    throw UnsupportedError('Platform not supported'));

final placeGroupRepositoryProvider = Provider<PlaceGroupRepository>((ref) =>
    throw UnsupportedError('Platform not supported'));

final syncLoggerProvider = Provider<SyncLogger>((ref) =>
    throw UnsupportedError('Platform not supported'));

final syncPipelineRunProvider =
    Provider<Future<SyncSummary> Function()>((ref) =>
        throw UnsupportedError('Platform not supported'));
